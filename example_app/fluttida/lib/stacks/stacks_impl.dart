import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/services.dart';

// iOS only:
import 'package:cupertino_http/cupertino_http.dart' as cupertino_http;

import '../lab_screen.dart';

class StacksImpl {
  static const MethodChannel _legacyChannel = MethodChannel('fluttida/network');

  // Normalize native channel maps to RequestResult with safe defaults
  static RequestResult _fromNativeMap(
    Map<dynamic, dynamic>? map, {
    String noResponseError = 'No response from native channel.',
  }) {
    if (map == null) {
      return RequestResult(
        status: null,
        body: '',
        durationMs: 0,
        error: noResponseError,
      );
    }
    final status = (map['status'] as num?)?.toInt();
    final body = (map['body'] as String?) ?? '';
    final durationMs = (map['durationMs'] as num?)?.toInt() ?? 0;
    final error = map['error'] as String?;
    return RequestResult(
      status: status,
      body: body,
      durationMs: durationMs,
      error: error,
    );
  }

  // ---------------------------------------------------------------------------
  // 1) RAW dart:io HttpClient
  // ---------------------------------------------------------------------------
  static Future<RequestResult> requestDartIoRaw(RequestConfig cfg) async {
    final sw = Stopwatch()..start();
    try {
      final client = HttpClient();
      client.connectionTimeout = cfg.timeout;

      final uri = Uri.parse(cfg.url);
      final req = await client.openUrl(cfg.method, uri);

      // Apply headers but avoid honoring an explicit Content-Length or Transfer-Encoding
      // from the UI because it can conflict with the actual body we write below.
      cfg.headers.forEach((k, v) {
        final lk = k.toLowerCase();
        if (lk == 'content-length' || lk == 'transfer-encoding') return;
        req.headers.set(k, v);
      });

      // Only send a body for non-GET/HEAD methods and when a body is provided.
      final bodyBytes =
          (cfg.body != null &&
              cfg.body!.isNotEmpty &&
              cfg.method.toUpperCase() != 'GET' &&
              cfg.method.toUpperCase() != 'HEAD')
          ? utf8.encode(cfg.body!)
          : null;

      if (bodyBytes != null) {
        // Ensure HttpClient knows the correct content length to avoid
        // "Content size exceed specified contentLength" errors.
        req.contentLength = bodyBytes.length;
        req.add(bodyBytes);
      }

      final resp = await req.close();

      final bytes = await resp.fold<List<int>>(<int>[], (p, e) => p..addAll(e));
      final body = utf8.decode(bytes, allowMalformed: true);

      sw.stop();
      return RequestResult(
        status: resp.statusCode,
        body: body,
        durationMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      sw.stop();
      return RequestResult(
        status: null,
        body: "",
        durationMs: sw.elapsedMilliseconds,
        error: e.toString(),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 2) package:http (default)
  // ---------------------------------------------------------------------------
  static Future<RequestResult> requestHttpDefault(RequestConfig cfg) async {
    final sw = Stopwatch()..start();
    try {
      final uri = Uri.parse(cfg.url);

      final http.Request r = http.Request(cfg.method, uri);
      r.headers.addAll(cfg.headers);
      if (cfg.body != null) {
        r.body = cfg.body!;
      }

      final streamed = await http.Client().send(r);
      final resp = await http.Response.fromStream(streamed);

      sw.stop();
      return RequestResult(
        status: resp.statusCode,
        body: resp.body,
        durationMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      sw.stop();
      return RequestResult(
        status: null,
        body: "",
        durationMs: sw.elapsedMilliseconds,
        error: e.toString(),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 3) package:http via IOClient (explicit)
  // ---------------------------------------------------------------------------
  static Future<RequestResult> requestHttpViaExplicitIoClient(
    RequestConfig cfg,
  ) async {
    final sw = Stopwatch()..start();
    try {
      final ioHttpClient = HttpClient();
      ioHttpClient.connectionTimeout = cfg.timeout;

      final client = IOClient(ioHttpClient);

      final uri = Uri.parse(cfg.url);
      final http.Request r = http.Request(cfg.method, uri);
      r.headers.addAll(cfg.headers);
      if (cfg.body != null) r.body = cfg.body!;

      final streamed = await client.send(r);
      final resp = await http.Response.fromStream(streamed);

      sw.stop();
      return RequestResult(
        status: resp.statusCode,
        body: resp.body,
        durationMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      sw.stop();
      return RequestResult(
        status: null,
        body: "",
        durationMs: sw.elapsedMilliseconds,
        error: e.toString(),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 4) cupertino_http (iOS NSURLSession)
  // ---------------------------------------------------------------------------
  static Future<RequestResult> requestCupertinoDefault(
    RequestConfig cfg,
  ) async {
    final sw = Stopwatch()..start();
    try {
      if (!Platform.isIOS) {
        throw Exception("cupertino_http is iOS-only");
      }

      final session =
          cupertino_http.CupertinoClient.defaultSessionConfiguration();

      final uri = Uri.parse(cfg.url);
      final http.Request r = http.Request(cfg.method, uri);
      r.headers.addAll(cfg.headers);
      if (cfg.body != null) r.body = cfg.body!;

      final streamed = await session.send(r);
      final resp = await http.Response.fromStream(streamed);

      sw.stop();
      return RequestResult(
        status: resp.statusCode,
        body: resp.body,
        durationMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      sw.stop();
      return RequestResult(
        status: null,
        body: "",
        durationMs: sw.elapsedMilliseconds,
        error: e.toString(),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 5) iOS legacy NSURLConnection / CFURLConnection
  //
  // WICHTIG: Das hier ist nur ein Platzhalter.
  // Du hast dafür bereits einen MethodChannel in AppDelegate.swift.
  // In Step 2.3 verdrahten wir diesen Channel hier sauber.
  // ---------------------------------------------------------------------------
  static Future<RequestResult> requestLegacyIos(RequestConfig cfg) async {
    if (!Platform.isIOS) {
      return RequestResult(
        status: null,
        body: '',
        durationMs: 0,
        error: 'Legacy stack is iOS-only (NSURLConnection/CFURLConnection).',
      );
    }

    final map = await _legacyChannel.invokeMapMethod<String, dynamic>(
      'legacyRequest',
      {
        'url': cfg.url,
        'method': cfg.method, // "GET", "POST", ...
        'headers': cfg.headers, // Map<String,String>
        'body': cfg.body, // String? (optional)
        'timeoutMs': cfg.timeout.inMilliseconds,
      },
    );

    return _fromNativeMap(
      map,
      noResponseError: 'No response from native channel.',
    );
  }

  // ---------------------------------------------------------------------------
  // Android native: HttpURLConnection (via MethodChannel)
  // ---------------------------------------------------------------------------
  static Future<RequestResult> requestAndroidHttpUrlConnection(
    RequestConfig cfg,
  ) async {
    if (!Platform.isAndroid) {
      return RequestResult(
        status: null,
        body: '',
        durationMs: 0,
        error: 'Android HttpURLConnection is Android-only',
      );
    }

    final map = await _legacyChannel
        .invokeMapMethod<String, dynamic>('androidHttpURLConnection', {
          'url': cfg.url,
          'method': cfg.method,
          'headers': cfg.headers,
          'body': cfg.body,
          'timeoutMs': cfg.timeout.inMilliseconds,
        });

    return _fromNativeMap(
      map,
      noResponseError: 'No response from native channel (HttpURLConnection).',
    );
  }

  // ---------------------------------------------------------------------------
  // Android native: OkHttp (via MethodChannel)
  // ---------------------------------------------------------------------------
  static Future<RequestResult> requestAndroidOkHttp(RequestConfig cfg) async {
    if (!Platform.isAndroid) {
      return RequestResult(
        status: null,
        body: '',
        durationMs: 0,
        error: 'Android OkHttp is Android-only',
      );
    }

    final map = await _legacyChannel
        .invokeMapMethod<String, dynamic>('androidOkHttp', {
          'url': cfg.url,
          'method': cfg.method,
          'headers': cfg.headers,
          'body': cfg.body,
          'timeoutMs': cfg.timeout.inMilliseconds,
        });

    return _fromNativeMap(
      map,
      noResponseError: 'No response from native channel (OkHttp).',
    );
  }

  // ---------------------------------------------------------------------------
  // Android native: Cronet (via MethodChannel) -- scaffold
  // ---------------------------------------------------------------------------
  static Future<RequestResult> requestAndroidCronet(RequestConfig cfg) async {
    if (!Platform.isAndroid) {
      return RequestResult(
        status: null,
        body: '',
        durationMs: 0,
        error: 'Android Cronet is Android-only',
      );
    }

    final map = await _legacyChannel
        .invokeMapMethod<String, dynamic>('androidCronet', {
          'url': cfg.url,
          'method': cfg.method,
          'headers': cfg.headers,
          'body': cfg.body,
          'timeoutMs': cfg.timeout.inMilliseconds,
        });

    return _fromNativeMap(
      map,
      noResponseError: 'No response from native channel (Cronet).',
    );
  }

  // ---------------------------------------------------------------------------
  // Android native: NDK libcurl via JNI (MethodChannel)
  // ---------------------------------------------------------------------------
  static Future<RequestResult> requestAndroidNativeCurl(
    RequestConfig cfg,
  ) async {
    if (!Platform.isAndroid) {
      return RequestResult(
        status: null,
        body: '',
        durationMs: 0,
        error: 'Android NDK (libcurl) is Android-only',
      );
    }

    final map = await _legacyChannel
        .invokeMapMethod<String, dynamic>('androidNativeCurl', {
          'url': cfg.url,
          'method': cfg.method,
          'headers': cfg.headers,
          'body': cfg.body,
          'timeoutMs': cfg.timeout.inMilliseconds,
        });

    return _fromNativeMap(
      map,
      noResponseError: 'No response from native channel (NDK libcurl).',
    );
  }

  // ---------------------------------------------------------------------------
  // 6) WebView headless (DOM outerHTML)
  // ---------------------------------------------------------------------------
  static Future<RequestResult> requestWebViewHeadless(RequestConfig cfg) async {
    final sw = Stopwatch()..start();
    try {
      throw Exception(
        "Provide WebViewController from UI and call requestWebViewHeadlessWith(controller, cfg)",
      );
    } catch (e) {
      sw.stop();
      return RequestResult(
        status: null,
        body: "",
        durationMs: sw.elapsedMilliseconds,
        error: e.toString(),
      );
    }
  }

  // Headless WebView using an existing controller created in the widget tree.
  static Future<RequestResult> requestWebViewHeadlessWith(
    WebViewController controller,
    RequestConfig cfg,
  ) async {
    final sw = Stopwatch()..start();
    try {
      final uri = Uri.parse(cfg.url);

      // Configure JS to allow DOM extraction
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      // Try to use the extended loadRequest signature with method/headers/body.
      bool loaded = false;
      try {
        // Map method to LoadRequestMethod if available
        final methodUpper = cfg.method.toUpperCase();
        dynamic loadMethod;
        try {
          // Prefer LoadRequestMethod from webview_flutter >= 4.7
          final m = LoadRequestMethod.values.firstWhere(
            (m) => m.name.toUpperCase() == methodUpper,
            orElse: () => LoadRequestMethod.get,
          );
          loadMethod = m;
        } catch (_) {
          // Fallback: use GET when enum not present
          loadMethod = null;
        }

        if (loadMethod != null) {
          // Prefer constructing a LoadRequest object (newer webview_flutter API)
          // This ensures headers/body/method are forwarded reliably.
          await controller.loadRequest(
            uri,
            method: loadMethod,
            headers: cfg.headers,
            body: cfg.body != null
                ? Uint8List.fromList(utf8.encode(cfg.body!))
                : null,
          );
          loaded = true;
        }
      } catch (_) {
        // ignore; will fallback below
      }

      if (!loaded) {
        // Graceful fallback for older plugin versions
        await controller.loadRequest(uri);
      }

      // Simple settle wait; UI controller doesn't expose onPageFinished awaits.
      // We'll try a few times to get outerHTML.
      String html = "";
      for (int i = 0; i < 10; i++) {
        try {
          final result = await controller.runJavaScriptReturningResult(
            'document.documentElement.outerHTML',
          );

          if (result is String) {
            var candidate = result;
            // If result looks like a quoted JS string literal or contains
            // escaped unicode sequences, try JSON decode to unescape it.
            if ((candidate.startsWith('"') && candidate.endsWith('"')) ||
                candidate.contains(r'\\u') ||
                candidate.contains(r'\\n') ||
                candidate.contains(r'\\t')) {
              try {
                final decoded = json.decode(candidate);
                if (decoded is String) {
                  html = decoded;
                } else {
                  html = candidate;
                }
              } catch (_) {
                // Fallback: replace common escaped sequences
                html = candidate
                    .replaceAll(r'\\n', '\n')
                    .replaceAll(r'\\t', '\t')
                    .replaceAll(r'\\"', '"');
              }
            } else if (candidate.contains(r'\\u')) {
              // try simple unicode unescape via json decode wrapper
              try {
                final decoded = json.decode('"' + candidate + '"');
                if (decoded is String)
                  html = decoded;
                else
                  html = candidate;
              } catch (_) {
                html = candidate;
              }
            } else {
              html = candidate;
            }
          } else if (result != null) {
            html = result.toString();
          }
        } catch (_) {
          // ignore interim errors
        }
        if (html.isNotEmpty) break;
        await Future.delayed(const Duration(milliseconds: 300));
      }

      sw.stop();
      return RequestResult(
        status: null, // WebView doesn't expose HTTP status
        body: html,
        durationMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      sw.stop();
      return RequestResult(
        status: null,
        body: "",
        durationMs: sw.elapsedMilliseconds,
        error: e.toString(),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // iOS Native (libcurl via Secure Transport)
  // ---------------------------------------------------------------------------
  static Future<RequestResult> requestIosNativeCurl(RequestConfig cfg) async {
    try {
      final result = await _legacyChannel.invokeMethod<Map>('iosNativeCurl', {
        'method': cfg.method,
        'url': cfg.url,
        'headers': cfg.headers,
        'body': cfg.body,
        'timeoutMs': cfg.timeout.inMilliseconds,
      });
      return _fromNativeMap(result);
    } catch (e) {
      return RequestResult(
        status: null,
        body: '',
        durationMs: 0,
        error: e.toString(),
      );
    }
  }
}
