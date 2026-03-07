import MetalKit

/// Renders the Doom 320×200 framebuffer to the screen using Metal.
/// Each draw call:
///   1. Reads the latest framebuffer from the C engine via dg_ios_get_framebuffer()
///   2. Uploads the pixels to a 320×200 MTLTexture
///   3. Draws a fullscreen quad using DoomShaders.metal
class DoomRenderer: NSObject, MTKViewDelegate {

    // MARK: - Metal objects

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var renderPipeline: MTLRenderPipelineState!
    private var doomTexture: MTLTexture!

    // MARK: - Init

    init?(view: MTKView) {
        guard let device = view.device,
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        self.device = device
        self.commandQueue = commandQueue
        super.init()

        guard buildPipeline(view: view),
              buildTexture() else {
            return nil
        }

        view.delegate = self
        view.framebufferOnly = false
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.preferredFramesPerSecond = 35  // Classic Doom runs at ~35 Hz
    }

    // MARK: - Setup

    private func buildPipeline(view: MTKView) -> Bool {
        guard let library = device.makeDefaultLibrary(),
              let vertexFn   = library.makeFunction(name: "doom_vertex"),
              let fragmentFn = library.makeFunction(name: "doom_fragment") else {
            return false
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction   = vertexFn
        descriptor.fragmentFunction = fragmentFn
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
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width:  320,
            height: 200,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return false
        }
        doomTexture = texture
        return true
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // No resize handling needed — Doom always renders at 320×200
    }

    func draw(in view: MTKView) {
        // Upload latest framebuffer from C engine
        if let fb = dg_ios_get_framebuffer() {
            let region = MTLRegionMake2D(0, 0, 320, 200)
            doomTexture.replace(
                region: region,
                mipmapLevel: 0,
                withBytes: fb,
                bytesPerRow: 320 * 4  // 4 bytes per BGRA pixel
            )
        }

        guard let renderPassDescriptor = view.currentRenderPassDescriptor,
              let drawable              = view.currentDrawable,
              let commandBuffer         = commandQueue.makeCommandBuffer(),
              let encoder               = commandBuffer.makeRenderCommandEncoder(
                                             descriptor: renderPassDescriptor) else {
            return
        }

        encoder.setRenderPipelineState(renderPipeline)
        encoder.setFragmentTexture(doomTexture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
