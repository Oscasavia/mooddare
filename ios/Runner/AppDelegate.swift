import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let settings = FlutterMethodChannel(name: "mooddare/settings", binaryMessenger: controller.binaryMessenger)
      settings.setMethodCallHandler { call, result in
        switch call.method {
        case "version":
          let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
          let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
          result("\(version) (\(build))")
        case "notifications":
          let destination: String
          if #available(iOS 16.0, *) { destination = UIApplication.openNotificationSettingsURLString }
          else { destination = UIApplication.openSettingsURLString }
          guard let url = URL(string: destination) else { result(FlutterError(code: "unavailable", message: "Settings unavailable", details: nil)); return }
          UIApplication.shared.open(url) { opened in
            result(opened ? nil : FlutterError(code: "unavailable", message: "Settings unavailable", details: nil))
          }
        case "openUrl":
          guard let value = call.arguments as? String, let url = URL(string: value),
                ["https", "mailto"].contains(url.scheme ?? "") else {
            result(FlutterError(code: "invalid-url", message: "Unsupported link", details: nil)); return
          }
          UIApplication.shared.open(url) { opened in
            result(opened ? nil : FlutterError(code: "unavailable", message: "No app available", details: nil))
          }
        default: result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
