import 'dart:convert';
import 'dart:io' as io;

import '../lab_screen.dart';
import '../pinning/stacks/dart_io_pinning.dart';

/// RAW dart:io HttpClient implementation extracted from `stacks_impl.dart`.
Future<RequestResult> requestDartIoRaw(RequestConfig cfg) async {
  final sw = Stopwatch()..start();
  try {
    final client = DartIoPinning.shouldPin()
        ? DartIoPinning.createClient()
        : io.HttpClient();
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
      body: '',
      durationMs: sw.elapsedMilliseconds,
      error: e.toString(),
    );
  }
}
