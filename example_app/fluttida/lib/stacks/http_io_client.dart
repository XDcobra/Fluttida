import 'dart:async';
import 'dart:io' as io;

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../pinning/stacks/package_http_pinning.dart';
import '../lab_screen.dart';

Future<RequestResult> requestHttpViaExplicitIoClient(RequestConfig cfg) async {
  final sw = Stopwatch()..start();
  try {
    final usePinning = PackageHttpPinning.shouldPinViaIOClient();
    final io.HttpClient ioHttpClient = usePinning
        ? PackageHttpPinning.createClient()
        : io.HttpClient();
    if (usePinning) {
      // lightweight debug trace — logging sink lives in stacks_impl
      // ignore: avoid_print
      print(
        '[PIN DEBUG] requestHttpViaExplicitIoClient: instrumented HttpClient created',
      );
    }
    ioHttpClient.connectionTimeout = cfg.timeout;

    final client = IOClient(ioHttpClient);

    final uri = Uri.parse(cfg.url);
    final http.Request r = http.Request(cfg.method, uri);
    r.headers.addAll(cfg.headers);
    if (cfg.body != null) r.body = cfg.body!;

    final streamed = await client.send(r);
    final resp = await http.Response.fromStream(streamed);

    client.close();
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
      body: '',
      durationMs: sw.elapsedMilliseconds,
      error: e.toString(),
    );
  }
}
