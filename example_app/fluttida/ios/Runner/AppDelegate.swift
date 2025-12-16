import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "fluttida/network", binaryMessenger: controller.binaryMessenger)

    channel.setMethodCallHandler { call, result in
      guard call.method == "legacyRequest" else {
        result(FlutterMethodNotImplemented)
        return
      }

      guard
        let args = call.arguments as? [String: Any],
        let urlStr = args["url"] as? String,
        let url = URL(string: urlStr)
      else {
        result(FlutterError(code: "bad_args", message: "Missing/invalid url", details: nil))
        return
      }

      var req = URLRequest(url: url)
      req.httpMethod = "GET"
      req.setValue("Fluttida/1.0 (NSURLConnection)", forHTTPHeaderField: "User-Agent")

      // Run in background (sync request must not block main thread)
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          var response: URLResponse?
          let data = try NSURLConnection.sendSynchronousRequest(req, returning: &response)

          // Additionally: trigger CFURLConnectionCreateWithRequest (creation only)
          let nsReq = req as NSURLRequest
          FluttidaCreateCFURLConnection(nsReq)

          let httpResp = response as? HTTPURLResponse
          let status = httpResp?.statusCode ?? -1
          let body = String(data: data, encoding: .utf8) ?? ""

          DispatchQueue.main.async {
            result(["status": status, "body": body])
          }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "legacy_failed", message: "\(error)", details: nil))
          }
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
