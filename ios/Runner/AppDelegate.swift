import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {

  private var deepLinkChannel: FlutterMethodChannel?
  private var pendingDeepLink: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Called by SceneDelegate once the FlutterViewController is ready.
  func setupDeepLinkChannel(_ controller: FlutterViewController) {
    guard deepLinkChannel == nil else { return }
    deepLinkChannel = FlutterMethodChannel(
      name: "com.arnav.align/deeplink",
      binaryMessenger: controller.binaryMessenger
    )
    deepLinkChannel?.setMethodCallHandler { [weak self] call, result in
      if call.method == "getInitialLink" {
        result(self?.pendingDeepLink)
        self?.pendingDeepLink = nil
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    // If a deep link arrived before the channel was ready, deliver it now.
    if let pending = pendingDeepLink {
      deepLinkChannel?.invokeMethod("onDeepLink", arguments: pending)
      pendingDeepLink = nil
    }
  }

  // Called by SceneDelegate when an align:// URL arrives.
  func handleAlignDeepLink(_ urlString: String) {
    if deepLinkChannel != nil {
      deepLinkChannel?.invokeMethod("onDeepLink", arguments: urlString)
    } else {
      pendingDeepLink = urlString
    }
  }

  // Fallback for non-scene-based targets.
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if url.scheme == "align" {
      handleAlignDeepLink(url.absoluteString)
      return true
    }
    return super.application(app, open: url, options: options)
  }
}
