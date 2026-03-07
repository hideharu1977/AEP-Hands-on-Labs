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
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard self != nil else { return }

            // Locate the Freedoom WAD bundled in the app
            guard let wadPath = Bundle.main.path(forResource: "freedoom1", ofType: "wad") else {
                DispatchQueue.main.async {
                    self?.showMissingWADAlert()
                }
                return
            }

            // Build argv: doom -iwad /path/to/freedoom1.wad
            let args: [String] = ["doom", "-iwad", wadPath]
            // strdup so C code gets stable char* pointers
            var argv: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
            defer { argv.forEach { free($0) } }

            doomgeneric_Create(Int32(args.count), &argv)

            // Run the Doom tick loop forever (Doom manages its own timing)
            while true {
                doomgeneric_Tick()
            }
        }
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
