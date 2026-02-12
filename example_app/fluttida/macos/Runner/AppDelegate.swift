import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    guard let controller = mainFlutterWindow.contentViewController as? FlutterViewController else {
      return
    }

    let channel = FlutterMethodChannel(name: "fluttida/network", binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      if call.method == "getBuildInfo" {
        let info = Bundle.main.infoDictionary
        let versionName = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let buildNumber = info?["CFBundleVersion"] as? String ?? "0"
        result([
          "versionName": versionName,
          "buildNumber": buildNumber,
        ])
        return
      }
      result(FlutterMethodNotImplemented)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
