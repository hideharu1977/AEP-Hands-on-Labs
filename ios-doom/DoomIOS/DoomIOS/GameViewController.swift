import UIKit
import MetalKit

/// Root view controller that owns the Metal rendering view and touch controls,
/// and manages the Doom game loop running on a background thread.
class GameViewController: UIViewController {

    private var metalView: MTKView!
    private var renderer: DoomRenderer!
    private var touchControls: TouchControlsView!

    // MARK: - View lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupMetalView()
        setupTouchControls()
        startDoom()
    }

    override var prefersStatusBarHidden: Bool { true }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .landscape
    }

    // MARK: - Setup

    private func setupMetalView() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device.")
        }

        metalView = MTKView(frame: view.bounds, device: device)
        metalView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.addSubview(metalView)

        guard let r = DoomRenderer(view: metalView) else {
            fatalError("Failed to create DoomRenderer.")
        }
        renderer = r
    }

    private func setupTouchControls() {
        touchControls = TouchControlsView(frame: view.bounds)
        touchControls.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(touchControls)
    }

    // MARK: - Game loop

    private func startDoom() {
        guard let wadPath = Bundle.main.path(forResource: "freedoom1", ofType: "wad") else {
            showMissingWADAlert()
            return
        }

        let args: [String] = ["doom", "-iwad", wadPath]
        // Allocate heap C-strings; these must outlive the game thread (forever).
        let cArgs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        let argc = Int32(args.count)

        /*
         * Use a raw pthread with an 8 MB stack.
         * GCD queues default to 512 KB, which can overflow during Doom's
         * recursive BSP rendering. 8 MB matches the iOS main-thread stack size.
         */
        var attr = pthread_attr_t()
        pthread_attr_init(&attr)
        pthread_attr_setstacksize(&attr, 8 * 1024 * 1024)

        // Box the context so we can pass it through the C void* bridge.
        let ctx = DoomThreadContext(argc: argc, argv: cArgs)
        let ctxPtr = Unmanaged.passRetained(ctx).toOpaque()

        var tid: pthread_t?
        pthread_create(&tid, &attr, doomThreadEntry, ctxPtr)
        pthread_attr_destroy(&attr)
        // tid is intentionally not joined — Doom never returns.
    }

    // MARK: - Pause / resume (called from SceneDelegate)

    func handleForeground() {
        dg_ios_set_paused(0)
        metalView.isPaused = false
    }

    func handleBackground() {
        dg_ios_set_paused(1)
        metalView.isPaused = true
    }

    // MARK: - Error handling

    private func showMissingWADAlert() {
        let alert = UIAlertController(
            title: "Missing Game Data",
            message: "freedoom1.wad was not found in the app bundle.\n\n"
                   + "Run setup.sh from the ios-doom directory to download it, "
                   + "then rebuild the app.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Doom thread bootstrap

/// Context object passed through the pthread C entry-point.
private final class DoomThreadContext {
    let argc: Int32
    let argv: [UnsafeMutablePointer<CChar>?]
    init(argc: Int32, argv: [UnsafeMutablePointer<CChar>?]) {
        self.argc = argc
        self.argv = argv
    }
}

/// C-compatible thread entry point for the Doom game loop.
private func doomThreadEntry(_ ptr: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
    let ctx = Unmanaged<DoomThreadContext>.fromOpaque(ptr).takeRetainedValue()
    var argv = ctx.argv
    argv.withUnsafeMutableBufferPointer { buf in
        doomgeneric_Create(ctx.argc, buf.baseAddress)
    }
    // doomgeneric_Create does initialization + two bootstrap tics, then returns.
    // The actual game loop must be driven by calling doomgeneric_Tick() repeatedly —
    // this matches how all other doomgeneric ports work (SDL, Allegro, Linux, etc.
    // all have their own `while(1) { doomgeneric_Tick(); }` after Create returns).
    while true {
        doomgeneric_Tick()
    }
}
