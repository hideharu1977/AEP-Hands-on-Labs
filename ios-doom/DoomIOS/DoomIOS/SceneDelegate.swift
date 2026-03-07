import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private weak var gameVC: GameViewController?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let vc = GameViewController()
        gameVC = vc
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = vc
        window.makeKeyAndVisible()
        self.window = window
    }

    // Pause the Doom game loop when the app moves to the background
    func sceneDidEnterBackground(_ scene: UIScene) {
        gameVC?.handleBackground()
    }

    // Resume the Doom game loop when the app returns to the foreground
    func sceneWillEnterForeground(_ scene: UIScene) {
        gameVC?.handleForeground()
    }
}
