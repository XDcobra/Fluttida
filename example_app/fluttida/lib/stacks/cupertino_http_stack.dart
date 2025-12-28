import 'dart:async';
import 'dart:io' as io;

import 'package:http/http.dart' as http;
import 'package:cupertino_http/cupertino_http.dart' as cupertino_http;

import '../lab_screen.dart';

Future<RequestResult> requestCupertinoDefault(RequestConfig cfg) async {
  final sw = Stopwatch()..start();
  try {
    if (!io.Platform.isIOS) {
      throw Exception("cupertino_http is iOS-only");
    }

    final session = cupertino_http.CupertinoClient.defaultSessionConfiguration();

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
