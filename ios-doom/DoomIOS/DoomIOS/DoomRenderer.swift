import MetalKit

/// Renders the Doom 320×200 framebuffer to the screen using Metal.
///
/// Each draw call:
///   1. Tries to pull a new frame from the C engine via dg_ios_copy_frame_if_new()
///   2. Uploads the pixels to a 320×200 BGRA8 MTLTexture
///   3. Draws a letterboxed quad using DoomShaders.metal
///
/// Letterboxing maintains Doom's 8:5 (320×200) aspect ratio regardless of
/// the device screen size or orientation.
class DoomRenderer: NSObject, MTKViewDelegate {

    // MARK: - Metal objects

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var renderPipeline: MTLRenderPipelineState!
    private var doomTexture: MTLTexture!

    // MARK: - Frame staging buffer

    // Must match DOOMGENERIC_RESX / DOOMGENERIC_RESY in doomgeneric.h (640 × 400).
    private let doomWidth  = 640
    private let doomHeight = 400
    /// CPU-side buffer reused every frame to avoid repeated allocation.
    private var stagingBuffer: [UInt8]

    // MARK: - Letterbox uniform
    // SIMD4<Float> = (left, bottom, right, top) in NDC, matches QuadUniforms in .metal
    private var quadRect = SIMD4<Float>(-1, -1, 1, 1)   // default: fullscreen

    // MARK: - Init

    init?(view: MTKView) {
        guard let device = view.device,
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        self.device = device
        self.commandQueue = commandQueue
        self.stagingBuffer = [UInt8](repeating: 0, count: 640 * 400 * 4)
        super.init()

        guard buildPipeline(view: view),
              buildTexture() else {
            return nil
        }

        view.delegate = self
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        // Drive the display at native refresh rate; the game loop runs at ~35 Hz
        // independently — the renderer simply re-uploads the same texture when
        // no new frame is available.
        view.preferredFramesPerSecond = UIScreen.main.maximumFramesPerSecond
    }

    // MARK: - Setup

    private func buildPipeline(view: MTKView) -> Bool {
        guard let library  = device.makeDefaultLibrary(),
              let vertexFn = library.makeFunction(name: "doom_vertex"),
              let fragFn   = library.makeFunction(name: "doom_fragment") else {
            print("[DoomRenderer] Failed to load shader functions")
            return false
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction   = vertexFn
        descriptor.fragmentFunction = fragFn
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat

        do {
            renderPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            print("[DoomRenderer] Pipeline creation failed: \(error)")
            return false
        }
        return true
    }

    private func buildTexture() -> Bool {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width:  doomWidth,
            height: doomHeight,
            mipmapped: false
        )
        desc.usage = [.shaderRead]
        // .shared = CPU + GPU share memory on iOS (unified memory architecture)
        desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else { return false }
        doomTexture = tex
        return true
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        updateLetterbox(drawableSize: size)
    }

    func draw(in view: MTKView) {
        // Pull latest frame from the game thread (no-op if nothing new)
        stagingBuffer.withUnsafeMutableBytes { ptr in
            _ = dg_ios_copy_frame_if_new(
                    ptr.baseAddress!.assumingMemoryBound(to: UInt8.self))
        }

        // Upload to GPU texture (always, so the previous frame stays visible)
        let region = MTLRegionMake2D(0, 0, doomWidth, doomHeight)
        doomTexture.replace(region: region,
                            mipmapLevel: 0,
                            withBytes: stagingBuffer,
                            bytesPerRow: doomWidth * 4)

        // Encode render pass
        guard let rpd      = view.currentRenderPassDescriptor,
              let drawable  = view.currentDrawable,
              let cmdBuf    = commandQueue.makeCommandBuffer(),
              let encoder   = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else {
            return
        }

        encoder.setRenderPipelineState(renderPipeline)
        encoder.setFragmentTexture(doomTexture, index: 0)

        // Upload the letterbox rect as vertex buffer 0 (QuadUniforms in .metal)
        var rect = quadRect
        encoder.setVertexBytes(&rect,
                               length: MemoryLayout<SIMD4<Float>>.stride,
                               index: 0)

        // Triangle strip: 4 vertices = fullscreen (or letterboxed) quad
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        cmdBuf.present(drawable)
        cmdBuf.commit()
    }

    // MARK: - Letterboxing

    private func updateLetterbox(drawableSize size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let screenAspect = Float(size.width  / size.height)
        // Doom's 320×200 (640×400) was authored for 4:3 CRT displays — pixels
        // were non-square (1.2× taller than wide).  Use 4:3 so it looks correct.
        let doomAspect: Float = 4.0 / 3.0

        let quadW: Float
        let quadH: Float
        if screenAspect > doomAspect {
            // Screen wider than Doom: pillarbox (shrink width)
            quadH = 1.0
            quadW = doomAspect / screenAspect
        } else {
            // Screen taller than Doom: letterbox (shrink height)
            quadW = 1.0
            quadH = screenAspect / doomAspect
        }
        quadRect = SIMD4<Float>(-quadW, -quadH, quadW, quadH)
    }
}
