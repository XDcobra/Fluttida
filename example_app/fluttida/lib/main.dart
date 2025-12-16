import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cupertino_http/cupertino_http.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  runApp(const FluttidaApp());
}

class FluttidaApp extends StatelessWidget {
  const FluttidaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _legacyChannel = MethodChannel('fluttida/network');
  static const _url = 'https://echo.free.beeceptor.com/';

  bool _loading = false;
  String _output = 'Ready.';

  WebViewController? _headlessWebViewController;

  Future<void> _run(String name, Future<RequestResult> Function() fn) async {
    setState(() {
      _loading = true;
      _output = 'Running: $name ...';
    });

    try {
      final res = await fn();
      final preview = res.body.length > 1200
          ? '${res.body.substring(0, 1200)}\n\n... (truncated)'
          : res.body;

      setState(() {
        _output = '[$name]\nStatus: ${res.status}\n\n$preview';
      });
    } catch (e) {
      setState(() {
        _output = '[$name]\nERROR: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _runAll() async {
    setState(() {
      _loading = true;
      _output = 'Running all scenarios...\n';
    });

    final results = <String>[];

    Future<void> step(String name, Future<RequestResult> Function() fn) async {
      try {
        final r = await fn();
        final snippet = r.body.length > 260
            ? '${r.body.substring(0, 260)}...'
            : r.body;
        results.add('[$name] Status: ${r.status}\n$snippet\n');
      } catch (e) {
        results.add('[$name] ERROR: $e\n');
      }

      setState(() {
        _output = results.join('\n----------------------\n');
      });
    }

    await step('raw dart:io', _requestDartIoRaw);
    await step('package:http (default)', _requestHttpDefault);
    await step(
      'package:http via IOClient(explicit)',
      _requestHttpViaExplicitIoClient,
    );
    await step('cupertino_http (NSURLSession)', _requestCupertinoDefault);

    if (Platform.isIOS) {
      await step(
        'package:http via CupertinoClient (NSURLSession)',
        _requestHttpViaCupertinoClient,
      );
      await step(
        'legacy ios (NSURLConnection/CFURLConnection)',
        _requestLegacyIos,
      );
    } else {
      results.add('[package:http via CupertinoClient] SKIPPED (iOS only)\n');
      results.add('[legacy ios] SKIPPED (iOS only)\n');
      setState(() => _output = results.join('\n----------------------\n'));
    }

    await step('webview (headless)', _requestWebViewHeadless);

    setState(() {
      _loading = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Scenario 1: RAW dart:io HttpClient (socket-based)
  // ---------------------------------------------------------------------------
  Future<RequestResult> _requestDartIoRaw() async {
    final client = HttpClient();
    client.userAgent = 'Fluttida/1.0 (raw dart:io)';

    final req = await client.getUrl(Uri.parse(_url));
    final resp = await req.close();

    final bytes = await resp.fold<List<int>>(
      <int>[],
      (acc, chunk) => acc..addAll(chunk),
    );
    final body = utf8.decode(bytes, allowMalformed: true);

    client.close(force: true);
    return RequestResult(resp.statusCode, body);
  }

  // ---------------------------------------------------------------------------
  // Scenario 2: package:http default (very common in apps)
  // (intern usually IOClient on mobile; you want it as its own button anyway)
  // ---------------------------------------------------------------------------
  Future<RequestResult> _requestHttpDefault() async {
    final resp = await http.get(
      Uri.parse(_url),
      headers: {'User-Agent': 'Fluttida/1.0 (package:http default)'},
    );
    return RequestResult(resp.statusCode, resp.body);
  }

  // ---------------------------------------------------------------------------
  // Scenario 3: package:http using explicit dart:io client (IOClient)
  // Useful to compare against default and to ensure the exact stack.
  // ---------------------------------------------------------------------------
  Future<RequestResult> _requestHttpViaExplicitIoClient() async {
    final io = HttpClient()
      ..userAgent = 'Fluttida/1.0 (package:http IOClient explicit)';
    final client = IOClient(io);

    try {
      final resp = await client.get(Uri.parse(_url));
      return RequestResult(resp.statusCode, resp.body);
    } finally {
      client.close();
      io.close(force: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Scenario 4: cupertino_http default session (iOS: NSURLSession)
  // ---------------------------------------------------------------------------
  Future<RequestResult> _requestCupertinoDefault() async {
    final client = CupertinoClient.defaultSessionConfiguration();
    try {
      final resp = await client.get(
        Uri.parse(_url),
        headers: {'User-Agent': 'Fluttida/1.0 (cupertino_http)'},
      );
      return RequestResult(resp.statusCode, resp.body);
    } finally {
      client.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Scenario 5 (iOS only): package:http client interface backed by NSURLSession
  // This is a neat scenario because it looks like package:http in Dart,
  // but hooks should fire on NSURLSession.
  // ---------------------------------------------------------------------------
  Future<RequestResult> _requestHttpViaCupertinoClient() async {
    if (!Platform.isIOS && !Platform.isMacOS) {
      throw Exception('CupertinoClient is only available on iOS/macOS.');
    }

    final client = CupertinoClient.defaultSessionConfiguration();
    try {
      final resp = await client.get(
        Uri.parse(_url),
        headers: {
          'User-Agent': 'Fluttida/1.0 (package:http via CupertinoClient)',
        },
      );
      return RequestResult(resp.statusCode, resp.body);
    } finally {
      client.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Scenario 6 (iOS only): NSURLConnection + CFURLConnection (MethodChannel)
  // ---------------------------------------------------------------------------
  Future<RequestResult> _requestLegacyIos() async {
    if (!Platform.isIOS) {
      throw Exception(
        'Legacy stack is iOS-only (NSURLConnection/CFURLConnection).',
      );
    }

    final map = await _legacyChannel.invokeMapMethod<String, dynamic>(
      'legacyRequest',
      {'url': _url},
    );

    if (map == null) throw Exception('No response from native channel.');

    final status = (map['status'] as num?)?.toInt() ?? -1;
    final body = (map['body'] as String?) ?? '';
    return RequestResult(status, body);
  }

  // ---------------------------------------------------------------------------
  // Scenario 7: WebView headless (iOS: WKWebView loadRequest)
  // ---------------------------------------------------------------------------
  // ---------------------------------------------------------------------------
  // Scenario 7: WebView headless (iOS: WKWebView loadRequest)
  // ---------------------------------------------------------------------------
  Future<RequestResult> _requestWebViewHeadless() async {
    final finished = Completer<void>();
    final errors = Completer<String?>();

    // Optional: für Debug / um zu sehen, ob überhaupt navigiert wird
    bool sawAnyNavigation = false;

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            sawAnyNavigation = true;
            debugPrint("WV started: $url");
          },
          onPageFinished: (url) {
            debugPrint("WV finished: $url");
            if (!finished.isCompleted) finished.complete();
          },
          onWebResourceError: (err) {
            final msg = "code=${err.errorCode} desc=${err.description}";
            debugPrint("WV error: $msg");
            if (!errors.isCompleted) errors.complete(msg);
          },
          onNavigationRequest: (req) {
            debugPrint("WV nav: ${req.url}");
            return NavigationDecision.navigate;
          },
        ),
      );

    // Wichtig: Controller in State speichern, damit Offstage(WebViewWidget) ihn "hostet"
    setState(() {
      _headlessWebViewController = controller;
    });

    await controller.loadRequest(Uri.parse(_url));

    final done = await Future.any([
      finished.future.then((_) => null),
      errors.future,
      Future.delayed(
        const Duration(seconds: 20),
        () => sawAnyNavigation
            ? 'timeout_after_navigation'
            : 'timeout_no_navigation',
      ),
    ]);

    if (done != null) {
      throw Exception('WebView load failed: $done');
    }

    final htmlAny = await controller.runJavaScriptReturningResult(
      'document.documentElement.outerHTML',
    );

    return RequestResult(-1, htmlAny.toString());
  }

  void _openWebViewScreen() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => WebViewScreen(url: _url)));
  }

  @override
  Widget build(BuildContext context) {
    SizedBox btn(String text, VoidCallback onTap) => SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _loading ? null : onTap,
        child: Text(text),
      ),
    );

    Widget section(String title) => Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Fluttida – Network Stack Lab')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            btn('Run all scenarios', _runAll),

            section('Dart / Flutter stacks'),
            btn(
              '1) RAW dart:io HttpClient',
              () => _run('raw dart:io', _requestDartIoRaw),
            ),
            btn(
              '2) package:http (default)',
              () => _run('package:http default', _requestHttpDefault),
            ),
            btn(
              '3) package:http via IOClient (explicit)',
              () => _run(
                'package:http IOClient',
                _requestHttpViaExplicitIoClient,
              ),
            ),
            btn(
              '4) cupertino_http (NSURLSession)',
              () => _run('cupertino_http', _requestCupertinoDefault),
            ),

            section('iOS-specific stacks'),
            btn(
              '5) package:http via CupertinoClient (NSURLSession)',
              () => _run(
                'http via CupertinoClient',
                _requestHttpViaCupertinoClient,
              ),
            ),
            btn(
              '6) NSURLConnection/CFURLConnection (iOS)',
              () => _run('legacy ios', _requestLegacyIos),
            ),

            section('WebView stacks'),
            btn('7) WebView (open screen)', _openWebViewScreen),

            const SizedBox(height: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _output,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ),
            ),

            // Wichtig: WKWebView muss im Widget-Tree hängen, auch wenn offstage
            Offstage(
              offstage: true,
              child: SizedBox(
                width: 1,
                height: 1,
                child: _headlessWebViewController == null
                    ? const SizedBox.shrink()
                    : WebViewWidget(controller: _headlessWebViewController!),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  final String url;
  const WebViewScreen({super.key, required this.url});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) => debugPrint("UI WV started: $url"),
          onPageFinished: (url) => debugPrint("UI WV finished: $url"),
          onWebResourceError: (e) =>
              debugPrint("UI WV error: ${e.errorCode} ${e.description}"),
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('WebView: ${widget.url}')),
      body: SafeArea(child: WebViewWidget(controller: _controller)),
    );
  }
}

class RequestResult {
  final int status;
  final String body;
  RequestResult(this.status, this.body);
}
