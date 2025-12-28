import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/services.dart';
import 'dart_io_raw.dart' as dart_io_raw;
import 'http_default.dart' as http_default;
import 'http_io_client.dart' as http_io_client;
import 'cupertino_http_stack.dart' as cupertino_http_stack;
import 'legacy_ios_stack.dart' as legacy_ios_stack;
import 'android_http_urlconnection_stack.dart' as android_http_urlconnection_stack;
import 'android_okhttp_stack.dart' as android_okhttp_stack;
import 'android_cronet_stack.dart' as android_cronet_stack;
import 'android_native_curl_stack.dart' as android_native_curl_stack;
import 'stacks_common.dart' as stacks_common;
import 'webview_headless_stack.dart' as webview_headless_stack;
import 'ios_native_curl_stack.dart' as ios_native_curl_stack;

import '../lab_screen.dart';
import '../pinning_config.dart';
import '../pinning/global_http_override.dart';
import '../pinning/stacks/dart_io_pinning.dart';
import '../pinning/stacks/package_http_pinning.dart';

class StacksImpl {
  static const MethodChannel _legacyChannel = MethodChannel('fluttida/network');
  static void Function(String)? _logSink;

  static void setupLogChannel() {
    _legacyChannel.setMethodCallHandler((call) async {
      if (call.method == 'log') {
        final msg = (call.arguments as Map?)?['message'] as String?;
        if (msg != null) _log(msg);
      }
    });
  }

  // Global pinning propagation. Safe if native side doesn't implement.
  static Future<void> setGlobalPinningConfig(PinningConfig cfg) async {
    // Build techniques map from per-stack configs
    final techniques = <String, String>{};
    cfg.stacks.forEach((key, config) {
      if (config.enabled) {
        techniques[key] = config.technique.name;
      }
    });

    final payload = {
      'pinning': {
        'enabled': cfg.enabled,
        'mode': cfg.mode.name, // 'publicKey' | 'certHash'
        'spkiPins': cfg.spkiPins,
        'certSha256Pins': cfg.certSha256Pins,
        'techniques': techniques,
      },
    };
    try {
      await _legacyChannel.invokeMethod('setGlobalPinningConfig', payload);
      GlobalHttpOverride.setConfig(cfg);
    } catch (_) {
      // Ignore: keeps UI responsive even if native handler not present
    }
  }

  static void setLogSink(void Function(String) sink) {
    _logSink = sink;
    GlobalHttpOverride.setLogSink(sink);
  }

  static Future<bool> isCronetPinningSupported() async {
    try {
      final res = await _legacyChannel.invokeMethod('isCronetPinningSupported');
      if (res is bool) return res;
      return false;
    } catch (_) {
      return false;
    }
  }

  // Normalize native channel maps to RequestResult with safe defaults
  static RequestResult _fromNativeMap(
    Map<dynamic, dynamic>? map, {
    String noResponseError = 'No response from native channel.',
  }) => stacks_common.fromNativeMap(map, noResponseError: noResponseError);

  // Helper that instruments `HttpClient` with debug logging for certificate
  // verification. It sets a `badCertificateCallback` that prints certificate
  // details so we can see whether the callback is being invoked at runtime.
  // In debug builds the callback rejects the certificate to surface pinning
  // problems; in release builds it preserves the previous (accept) behavior.
  static bool _shouldPinDartIoRaw() {
    return DartIoPinning.shouldPin();
  }

  static void _log(String msg) {
    // Console log for dev
    // ignore: avoid_print
    print(msg);
    try {
      _logSink?.call(msg);
    } catch (_) {}
  }

  // Enable global HttpOverrides so all `HttpClient` instances use our instrumented client
  static void enableGlobalHttpOverrides() {
    GlobalHttpOverride.enableGlobalOverride();
  }

  // Disable global HttpOverrides (reset to null)
  static void disableGlobalHttpOverrides() {
    GlobalHttpOverride.disableGlobalOverride();
  }

  // ---------------------------------------------------------------------------
  // 1) RAW dart:io HttpClient
  // ---------------------------------------------------------------------------
  static Future<RequestResult> requestDartIoRaw(RequestConfig cfg) =>
      dart_io_raw.requestDartIoRaw(cfg);

  // ---------------------------------------------------------------------------
  // 2) package:http (default)
  // ---------------------------------------------------------------------------
  static Future<RequestResult> requestHttpDefault(RequestConfig cfg) =>
      http_default.requestHttpDefault(cfg);

  // ---------------------------------------------------------------------------
  // 3) package:http via IOClient (explicit)
  // ---------------------------------------------------------------------------
  static Future<RequestResult> requestHttpViaExplicitIoClient(
    RequestConfig cfg,
  ) => http_io_client.requestHttpViaExplicitIoClient(cfg);

  // ---------------------------------------------------------------------------
  // 4) cupertino_http (iOS NSURLSession)
  // ---------------------------------------------------------------------------
  static Future<RequestResult> requestCupertinoDefault(
    RequestConfig cfg,
  ) => cupertino_http_stack.requestCupertinoDefault(cfg);

  // ---------------------------------------------------------------------------
  // 5) iOS legacy NSURLConnection / CFURLConnection
  //
  // IMPORTANT: This is only a placeholder.
  // You already have a MethodChannel for this in AppDelegate.swift.
  // ---------------------------------------------------------------------------
  static Future<RequestResult> requestLegacyIos(RequestConfig cfg) =>
      legacy_ios_stack.requestLegacyIos(cfg);

  // ---------------------------------------------------------------------------
  // Android native: HttpURLConnection (via MethodChannel)
  // ---------------------------------------------------------------------------
  static Future<RequestResult> requestAndroidHttpUrlConnection(
    RequestConfig cfg,
  ) async {
    return android_http_urlconnection_stack
        .requestAndroidHttpUrlConnection(cfg);
  }

  // ---------------------------------------------------------------------------
  // Android native: OkHttp (via MethodChannel)
  // ---------------------------------------------------------------------------
  static Future<RequestResult> requestAndroidOkHttp(RequestConfig cfg) async {
    return android_okhttp_stack.requestAndroidOkHttp(cfg);
  }

  // ---------------------------------------------------------------------------
  // Android native: Cronet (via MethodChannel) -- scaffold
  // ---------------------------------------------------------------------------
  static Future<RequestResult> requestAndroidCronet(RequestConfig cfg) async {
    return android_cronet_stack.requestAndroidCronet(cfg);
  }

  // ---------------------------------------------------------------------------
  // Android native: NDK libcurl via JNI (MethodChannel)
  // ---------------------------------------------------------------------------
  static Future<RequestResult> requestAndroidNativeCurl(
    RequestConfig cfg,
  ) async {
    return android_native_curl_stack.requestAndroidNativeCurl(cfg);
  }

  // ---------------------------------------------------------------------------
  // 6) WebView headless (DOM outerHTML)
  // ---------------------------------------------------------------------------
  static Future<RequestResult> requestWebViewHeadless(RequestConfig cfg) async {
    return webview_headless_stack.requestWebViewHeadless(cfg);
  }

  // Headless WebView using an existing controller created in the widget tree.
  static Future<RequestResult> requestWebViewHeadlessWith(
    WebViewController controller,
    RequestConfig cfg,
  ) async {
    return webview_headless_stack.requestWebViewHeadlessWith(controller, cfg);
  }

  // ---------------------------------------------------------------------------
  // iOS Native (libcurl via Secure Transport)
  // ---------------------------------------------------------------------------
  static Future<RequestResult> requestIosNativeCurl(RequestConfig cfg) async {
    return ios_native_curl_stack.requestIosNativeCurl(cfg);
  }
}
