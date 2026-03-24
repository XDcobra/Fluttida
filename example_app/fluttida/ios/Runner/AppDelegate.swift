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

      if call.method == "getAdConfig" {
        let info = Bundle.main.infoDictionary

        func normalizedString(_ value: Any?) -> String? {
          guard let raw = value as? String else { return nil }
          let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
          if trimmed.isEmpty || trimmed.hasPrefix("$(") {
            return nil
          }
          return trimmed
        }

        var adsEnabledBool = false
        if let v = info?["ADS_ENABLED"] as? Bool {
          adsEnabledBool = v
        } else if let v = info?["ADS_ENABLED"] as? String {
          adsEnabledBool = (v as NSString).boolValue
        } else if let v = info?["ADS_ENABLED"] as? NSNumber {
          adsEnabledBool = v.boolValue
        }

        let banner = normalizedString(info?["admobBannerUnitIos"])
          ?? normalizedString(info?["admobBannerUnit"])

        // If IDs are unresolved/missing, force ads off to keep runtime stable.
        if banner == nil {
          adsEnabledBool = false
        }

        result([
          "adsEnabled": adsEnabledBool,
          "admobBannerUnitIos": banner ?? "",
        ])
        return
      }

      if call.method == "iosNativeCurl" {
        guard
          let args = call.arguments as? [String: Any],
          let urlStr = args["url"] as? String
        else {
          result(FlutterError(code: "bad_args", message: "Missing/invalid arguments", details: nil))
          return
        }

        let method = (args["method"] as? String) ?? "GET"
        let headers = (args["headers"] as? [String: String]) ?? [:]
        let bodyStr = args["body"] as? String
        let timeoutMs = (args["timeoutMs"] as? NSNumber) ?? NSNumber(value: 20000)

        DispatchQueue.global(qos: .userInitiated).async {
          let resultDict = NativeHttp.performRequest(
            method,
            url: urlStr,
            headers: headers,
            body: bodyStr,
            timeoutMs: timeoutMs
          )
          DispatchQueue.main.async {
            result(resultDict)
          }
        }
        return
      }

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

          // CFURLConnection trigger
          FluttidaCreateCFURLConnection(req)

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
