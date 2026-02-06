import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:webview_flutter/webview_flutter.dart';

import '../lab_screen.dart';

String _decodeJsResult(dynamic result) {
  if (result == null) return '';
  if (result is String) {
    var candidate = result;
    if ((candidate.startsWith('"') && candidate.endsWith('"')) ||
        candidate.contains(r'\\u') ||
        candidate.contains(r'\\n') ||
        candidate.contains(r'\\t')) {
      try {
        final decoded = json.decode(candidate);
        if (decoded is String) return decoded;
      } catch (_) {
        return candidate
            .replaceAll(r'\\n', '\n')
            .replaceAll(r'\\t', '\t')
            .replaceAll(r'\\"', '"');
      }
    } else if (candidate.contains(r'\\u')) {
      try {
        final decoded = json.decode('"$candidate"');
        if (decoded is String) return decoded;
      } catch (_) {
        return candidate;
      }
    }
    return candidate;
  }
  return result.toString();
}

bool _isPlaceholderHtml(String html) {
  final normalized = html.trim().toLowerCase();
  return normalized == '<html><head></head><body></body></html>';
}

Future<void> _waitForPageLoad(
  WebViewController controller,
  Duration timeout,
) async {
  final completer = Completer<void>();
  controller.setNavigationDelegate(
    NavigationDelegate(
      onPageFinished: (_) {
        if (!completer.isCompleted) completer.complete();
      },
      onWebResourceError: (_) {
        if (!completer.isCompleted) completer.complete();
      },
    ),
  );
  try {
    await completer.future.timeout(timeout);
  } catch (_) {
    // Timeout means we'll continue with best-effort DOM extraction.
  }
}

Future<RequestResult> requestWebViewHeadless(RequestConfig cfg) async {
  final sw = Stopwatch()..start();
  sw.stop();
  return RequestResult(
    status: null,
    body: '',
    durationMs: sw.elapsedMilliseconds,
    error:
        "Provide WebViewController from UI and call requestWebViewHeadlessWith(controller, cfg)",
  );
}

Future<RequestResult> requestWebViewHeadlessWith(
  WebViewController controller,
  RequestConfig cfg,
) async {
  final sw = Stopwatch()..start();
  try {
    final uri = Uri.parse(cfg.url);

    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);

    bool loaded = false;
    try {
      final methodUpper = cfg.method.toUpperCase();
      dynamic loadMethod;
      try {
        final m = LoadRequestMethod.values.firstWhere(
          (m) => m.name.toUpperCase() == methodUpper,
          orElse: () => LoadRequestMethod.get,
        );
        loadMethod = m;
      } catch (_) {
        loadMethod = null;
      }

      if (loadMethod != null) {
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
      } catch (e) {
      // Expected: LoadRequestMethod may not exist in some webview versions
      // ignore: avoid_print
      print('WebView loadRequest with method failed: $e');
    }

    if (!loaded) await controller.loadRequest(uri);

    await _waitForPageLoad(controller, cfg.timeout);

    String html = '';
    for (int i = 0; i < 10; i++) {
      try {
        final result = await controller.runJavaScriptReturningResult(
          'document.documentElement.outerHTML',
        );

        html = _decodeJsResult(result);

        final readyState = _decodeJsResult(
          await controller.runJavaScriptReturningResult('document.readyState'),
        );
        final bodyInner = _decodeJsResult(
          await controller.runJavaScriptReturningResult(
            'document.body ? document.body.innerHTML : ""',
          ),
        );

        final htmlLooksEmpty =
            html.isEmpty || _isPlaceholderHtml(html) || bodyInner.trim().isEmpty;
        if (readyState == 'complete' && !htmlLooksEmpty) {
          break;
        }
      } catch (e) {
        // Expected: HTML may not be ready during page load
        // ignore: avoid_print
        print('WebView HTML retrieval attempt ${i + 1} failed: $e');
      }
      if (html.isNotEmpty && !_isPlaceholderHtml(html)) break;
      await Future.delayed(const Duration(milliseconds: 300));
    }

    sw.stop();
    return RequestResult(
      status: null,
      body: html,
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
