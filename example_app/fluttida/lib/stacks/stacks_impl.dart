import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

      cfg.headers.forEach((k, v) => req.headers.set(k, v));
      if (cfg.body != null && cfg.body!.isNotEmpty) {
        req.add(utf8.encode(cfg.body!));
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

    if (map == null) {
      return RequestResult(
        status: null,
        body: '',
        durationMs: 0,
        error: 'No response from native channel.',
      );
    }

    final status = (map['status'] as num?)?.toInt();
    final body = (map['body'] as String?) ?? '';
    final durationMs = (map['durationMs'] as num?)?.toInt() ?? 0;

    return RequestResult(
      status: status,
      body: body,
      durationMs: durationMs,
      error: map['error'] as String?,
    );
  }

  // ---------------------------------------------------------------------------
  // 6) WebView headless (DOM outerHTML)
  // ---------------------------------------------------------------------------
  static Future<RequestResult> requestWebViewHeadless(RequestConfig cfg) async {
    final sw = Stopwatch()..start();

    // Hinweis: WebView benötigt "UI thread" + widget tree.
    // Wenn du es headless machst, muss es im Widget tree existieren (Offstage),
    // das machst du bereits im LabScreen.
    //
    // Daher: In Step 2.4 machen wir es so, dass LabScreen den Controller erzeugt
    // und hier nur "load+wait+extract" auf dem Controller passiert.
    //
    // Für jetzt: wir werfen eine klare Exception.
    sw.stop();
    return RequestResult(
      status: null,
      body: "",
      durationMs: sw.elapsedMilliseconds,
      error:
          "Step 2.4: WebView headless wird über Controller aus dem Screen gelöst.",
    );
  }
}
