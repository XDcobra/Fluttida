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

      let method = (args["method"] as? String) ?? "GET"
      let headers = (args["headers"] as? [String: String]) ?? [:]
      let bodyStr = args["body"] as? String
      let timeoutMs = (args["timeoutMs"] as? Int) ?? 20000

      var req = URLRequest(url: url)
      req.httpMethod = method
      req.timeoutInterval = Double(timeoutMs) / 1000.0
      headers.forEach { k, v in req.setValue(v, forHTTPHeaderField: k) }
      if let bodyStr, !bodyStr.isEmpty {
        req.httpBody = bodyStr.data(using: .utf8)
      }

      DispatchQueue.global(qos: .userInitiated).async {
        let start = Date()
        do {
          var response: URLResponse?
          let data = try NSURLConnection.sendSynchronousRequest(req, returning: &response)

          // CFURLConnection trigger (needs NSURLRequest)
          FluttidaCreateCFURLConnection(req as NSURLRequest)

          let httpResp = response as? HTTPURLResponse
          let status = httpResp?.statusCode ?? -1
          let body = String(data: data, encoding: .utf8) ?? ""
          let ms = Int(Date().timeIntervalSince(start) * 1000)

          DispatchQueue.main.async {
                result(["status": status, "body": body, "durationMs": ms, "error": NSNull()])
          }
        } catch {
          let ms = Int(Date().timeIntervalSince(start) * 1000)
          DispatchQueue.main.async {
            result(["status": NSNull(), "body": "", "durationMs": ms, "error": "\(error)"])
          }
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
