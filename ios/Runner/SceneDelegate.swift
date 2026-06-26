import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

    // Called on cold-start when the app is launched via URL (e.g. from share extension).
    override func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        super.scene(scene, willConnectTo: session, options: connectionOptions)

        // After super, the Flutter window/view controller is ready — wire up the channel.
        if let windowScene = scene as? UIWindowScene,
           let controller = windowScene.windows.first?.rootViewController as? FlutterViewController {
            (UIApplication.shared.delegate as? AppDelegate)?.setupDeepLinkChannel(controller)
        }

        // Handle a URL that launched the app cold.
        for context in connectionOptions.urlContexts {
            if context.url.scheme == "align" {
                (UIApplication.shared.delegate as? AppDelegate)?
                    .handleAlignDeepLink(context.url.absoluteString)
                return
            }
        }
    }

    // Called when the app is already running and brought to foreground via URL.
    override func scene(
        _ scene: UIScene,
        openURLContexts URLContexts: Set<UIOpenURLContext>
    ) {
        for context in URLContexts {
            if context.url.scheme == "align" {
                (UIApplication.shared.delegate as? AppDelegate)?
                    .handleAlignDeepLink(context.url.absoluteString)
                return
            }
        }
        super.scene(scene, openURLContexts: URLContexts)
    }
}
