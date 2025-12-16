import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'stacks/stacks_impl.dart';

enum StackLayer { dart, native, webview, ndk }

class RequestConfig {
  final String url;
  final String method; // "GET", "POST", ...
  final Map<String, String> headers;
  final String? body;
  final Duration timeout;

  const RequestConfig({
    required this.url,
    this.method = "GET",
    this.headers = const {},
    this.body,
    this.timeout = const Duration(seconds: 20),
  });

  RequestConfig copyWith({
    String? url,
    String? method,
    Map<String, String>? headers,
    String? body,
    Duration? timeout,
  }) {
    return RequestConfig(
      url: url ?? this.url,
      method: method ?? this.method,
      headers: headers ?? this.headers,
      body: body ?? this.body,
      timeout: timeout ?? this.timeout,
    );
  }
}

class RequestResult {
  final int? status; // null bei hard error/timeout
  final String body;
  final String? error;
  final int durationMs;

  const RequestResult({
    required this.status,
    required this.body,
    required this.durationMs,
    this.error,
  });

  bool get ok => error == null;
}

class LogLine {
  final DateTime ts;
  final String text;
  LogLine(this.text) : ts = DateTime.now();
}

class SupportInfo {
  final bool supported;
  final String? reason;
  const SupportInfo(this.supported, [this.reason]);
}

class StackDefinition {
  final String id;
  final String name;
  final String description;
  final StackLayer layer;

  /// returns SupportInfo (supported + reason if not)
  final SupportInfo Function() support;

  /// performs request
  final Future<RequestResult> Function(RequestConfig cfg) run;

  const StackDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.layer,
    required this.support,
    required this.run,
  });
}

/// Central controller / state (no extra deps)
class LabController extends ChangeNotifier {
  RequestConfig config;

  bool isRunning = false;
  String? currentStackId;

  final Map<String, RequestResult> results = {};
  final List<LogLine> logs = [];

  final Set<String> selected = {};

  LabController({required this.config});

  void appendLog(String msg) {
    logs.add(LogLine(msg));
    notifyListeners();
  }

  void clearOutput() {
    results.clear();
    logs.clear();
    notifyListeners();
  }

  void toggleSelected(String id, bool value) {
    if (value) {
      selected.add(id);
    } else {
      selected.remove(id);
    }
    notifyListeners();
  }

  Future<void> runSequential({
    required List<StackDefinition> queue,
    required String runName,
  }) async {
    if (isRunning) return;

    isRunning = true;
    currentStackId = null;
    appendLog("=== $runName (sequential) ===");

    try {
      for (final s in queue) {
        currentStackId = s.id;
        notifyListeners();

        appendLog("=> START ${s.name}");

        final sw = Stopwatch()..start();
        RequestResult res;

        try {
          res = await s
              .run(config)
              .timeout(
                config.timeout,
                onTimeout: () {
                  return RequestResult(
                    status: null,
                    body: "",
                    durationMs: sw.elapsedMilliseconds,
                    error: "timeout after ${config.timeout.inSeconds}s",
                  );
                },
              );
        } catch (e) {
          res = RequestResult(
            status: null,
            body: "",
            durationMs: sw.elapsedMilliseconds,
            error: e.toString(),
          );
        } finally {
          sw.stop();
        }

        results[s.id] = res;

        final statusStr = res.status?.toString() ?? "—";
        final errStr = res.error == null ? "" : " | ERROR: ${res.error}";
        appendLog(
          "<= DONE  ${s.name} | status=$statusStr | ${res.durationMs}ms$errStr",
        );

        // tiny pause so UI feels stable & logs render nicely
        await Future.delayed(const Duration(milliseconds: 150));
      }

      appendLog("=== DONE: $runName ===");
    } finally {
      currentStackId = null;
      isRunning = false;
      notifyListeners();
    }
  }
}

/// ------------------------------------------------------------
/// Placeholder / helper: shorten body for list rendering
String previewBody(String s, {int max = 1200}) {
  if (s.length <= max) return s;
  return s.substring(0, max) + "\n… (truncated)";
}

/// ------------------------------------------------------------
/// Your existing implementations can be plugged here.
/// For Step 1 we keep most things minimal.
/// ------------------------------------------------------------
class LabStacks {
  static List<StackDefinition> build({
    required Future<RequestResult> Function(RequestConfig) dartIoRaw,
    required Future<RequestResult> Function(RequestConfig) httpDefault,
    required Future<RequestResult> Function(RequestConfig) httpIoClient,
    required Future<RequestResult> Function(RequestConfig) cupertinoHttp,
    required Future<RequestResult> Function(RequestConfig)
    iosLegacyNsUrlConnection,
    required Future<RequestResult> Function(RequestConfig)
    androidHttpUrlConnection,
    required Future<RequestResult> Function(RequestConfig) androidOkHttp,
    required Future<RequestResult> Function(RequestConfig) webViewHeadless,
    required Future<RequestResult> Function(RequestConfig) androidCronet,
  }) {
    SupportInfo iosOnly() => Platform.isIOS
        ? const SupportInfo(true)
        : const SupportInfo(false, "Only available on iOS");

    SupportInfo androidOnly() => Platform.isAndroid
        ? const SupportInfo(true)
        : const SupportInfo(false, "Only available on Android");

    return [
      StackDefinition(
        id: "dart_io",
        name: "dart:io HttpClient",
        description: "Pure Dart network stack (no platform channel).",
        layer: StackLayer.dart,
        support: () => const SupportInfo(true),
        run: dartIoRaw,
      ),
      StackDefinition(
        id: "http_default",
        name: "package:http (default)",
        description: "package:http default client.",
        layer: StackLayer.dart,
        support: () => const SupportInfo(true),
        run: httpDefault,
      ),
      StackDefinition(
        id: "http_ioclient",
        name: "package:http via IOClient",
        description: "Explicit IOClient for package:http.",
        layer: StackLayer.dart,
        support: () => const SupportInfo(true),
        run: httpIoClient,
      ),

      // iOS native
      StackDefinition(
        id: "ios_nsurlsession",
        name: "cupertino_http (NSURLSession)",
        description: "Uses NSURLSession via cupertino_http.",
        layer: StackLayer.native,
        support: iosOnly,
        run: cupertinoHttp,
      ),
      StackDefinition(
        id: "ios_legacy",
        name: "NSURLConnection / CFURLConnection",
        description: "Legacy iOS connection APIs (your AppDelegate channel).",
        layer: StackLayer.native,
        support: iosOnly,
        run: iosLegacyNsUrlConnection,
      ),

      // Android native placeholders (Step 2+)
      StackDefinition(
        id: "android_httpurlconnection",
        name: "HttpURLConnection (Android)",
        description:
            "Native Android HttpURLConnection (placeholder for Step 2).",
        layer: StackLayer.native,
        support: androidOnly,
        run: androidHttpUrlConnection,
      ),
      StackDefinition(
        id: "android_okhttp",
        name: "OkHttp (Android)",
        description: "Native OkHttp client (placeholder for Step 3).",
        layer: StackLayer.native,
        support: androidOnly,
        run: androidOkHttp,
      ),
      StackDefinition(
        id: "android_cronet",
        name: "Cronet (Android)",
        description: "Cronet stack (placeholder later).",
        layer: StackLayer.native,
        support: androidOnly,
        run: androidCronet,
      ),

      // WebView (we keep visible, but you can disable if it’s flaky on iOS)
      StackDefinition(
        id: "webview_headless",
        name: "WebView (headless)",
        description: "Loads URL in an offstage WebView and reads DOM HTML.",
        layer: StackLayer.webview,
        support: () => const SupportInfo(true),
        run: webViewHeadless,
      ),
    ];
  }
}

/// ------------------------------------------------------------
/// UI Screen
/// ------------------------------------------------------------
Map<String, String>? _tryParseJsonMap(String s) {
  try {
    final decoded = json.decode(s);
    if (decoded is Map) {
      final out = <String, String>{};
      decoded.forEach((key, value) {
        if (key is String) {
          out[key] = value?.toString() ?? '';
        }
      });
      return out;
    }
  } catch (_) {
    // not JSON, fallthrough
  }
  return null;
}

class LabScreen extends StatefulWidget {
  final String initialUrl;

  /// Plug in your existing scenario functions here
  final Future<RequestResult> Function(RequestConfig) dartIoRaw;
  final Future<RequestResult> Function(RequestConfig) httpDefault;
  final Future<RequestResult> Function(RequestConfig) httpIoClient;
  final Future<RequestResult> Function(RequestConfig) cupertinoHttp;
  final Future<RequestResult> Function(RequestConfig) iosLegacyNsUrlConnection;
  final Future<RequestResult> Function(RequestConfig) androidHttpUrlConnection;
  final Future<RequestResult> Function(RequestConfig) androidOkHttp;
  // Cronet: will fallback to HttpURLConnection until native handler is implemented
  final Future<RequestResult> Function(RequestConfig) androidCronet;
  final Future<RequestResult> Function(RequestConfig) webViewHeadless;

  const LabScreen({
    super.key,
    required this.initialUrl,
    required this.dartIoRaw,
    required this.httpDefault,
    required this.httpIoClient,
    required this.cupertinoHttp,
    required this.iosLegacyNsUrlConnection,
    required this.androidHttpUrlConnection,
    required this.androidOkHttp,
    required this.androidCronet,
    required this.webViewHeadless,
  });

  @override
  State<LabScreen> createState() => _LabScreenState();
}

class _LabScreenState extends State<LabScreen> {
  late final LabController ctrl;
  late final List<StackDefinition> stacks;
  late final WebViewController _webViewController;

  final _urlController = TextEditingController();
  String _method = "GET";
  final _bodyController = TextEditingController();
  final _headersController = TextEditingController();
  int _timeoutSeconds = 20;

  @override
  void initState() {
    super.initState();

    _urlController.text = widget.initialUrl;

    ctrl = LabController(config: RequestConfig(url: widget.initialUrl));

    // Prepare a persistent WebViewController for headless usage
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);

    stacks = LabStacks.build(
      dartIoRaw: widget.dartIoRaw,
      httpDefault: widget.httpDefault,
      httpIoClient: widget.httpIoClient,
      cupertinoHttp: widget.cupertinoHttp,
      iosLegacyNsUrlConnection: widget.iosLegacyNsUrlConnection,
      androidHttpUrlConnection: widget.androidHttpUrlConnection,
      androidOkHttp: widget.androidOkHttp,
      androidCronet: widget.androidCronet,
      webViewHeadless: (cfg) async {
        // Delegate to implementation using the persistent controller
        return StacksImpl.requestWebViewHeadlessWith(_webViewController, cfg);
      },
    );

    // default select: all supported stacks
    for (final s in stacks) {
      if (s.support().supported) {
        ctrl.selected.add(s.id);
      }
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _bodyController.dispose();
    _headersController.dispose();
    ctrl.dispose();
    super.dispose();
  }

  void _applyConfig() {
    // Parse headers from text area: support JSON map or simple key:value lines
    Map<String, String> parsedHeaders = {};
    final raw = _headersController.text.trim();
    if (raw.isNotEmpty) {
      try {
        final maybeJson = raw;
        final decoded = _tryParseJsonMap(maybeJson);
        if (decoded != null) {
          parsedHeaders = decoded;
        } else {
          for (final line in raw.split(RegExp(r"\r?\n"))) {
            final trimmed = line.trim();
            if (trimmed.isEmpty) continue;
            final idx = trimmed.indexOf(":");
            if (idx > 0) {
              final k = trimmed.substring(0, idx).trim();
              final v = trimmed.substring(idx + 1).trim();
              if (k.isNotEmpty) parsedHeaders[k] = v;
            }
          }
        }
      } catch (_) {
        // ignore parse errors; leave headers empty if invalid
      }
    }

    // Always include a lab UA unless overridden
    parsedHeaders.putIfAbsent("User-Agent", () => "Fluttida/1.0 (Lab)");

    ctrl.config = ctrl.config.copyWith(
      url: _urlController.text.trim(),
      method: _method,
      headers: parsedHeaders,
      body: _bodyController.text.isEmpty ? null : _bodyController.text,
      timeout: Duration(seconds: _timeoutSeconds.clamp(1, 600)),
    );
  }

  Future<void> _runAllSupported() async {
    _applyConfig();

    final queue = stacks.where((s) => s.support().supported).toList();
    await ctrl.runSequential(queue: queue, runName: "Run All Supported");
  }

  Future<void> _runSelected() async {
    _applyConfig();

    final queue = stacks
        .where((s) => ctrl.selected.contains(s.id))
        .where((s) => s.support().supported)
        .toList();

    await ctrl.runSequential(queue: queue, runName: "Run Selected");
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) {
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: const Text("Fluttida – Network Stack Lab"),
              bottom: const TabBar(
                tabs: [
                  Tab(text: "Results"),
                  Tab(text: "Logs"),
                ],
              ),
            ),
            body: Column(
              children: [
                // A) Config
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _urlController,
                              decoration: const InputDecoration(
                                labelText: "URL",
                                border: OutlineInputBorder(),
                              ),
                              enabled: !ctrl.isRunning,
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 110,
                            child: DropdownButtonFormField<String>(
                              value: _method,
                              items: const [
                                DropdownMenuItem(
                                  value: "GET",
                                  child: Text("GET"),
                                ),
                                DropdownMenuItem(
                                  value: "POST",
                                  child: Text("POST"),
                                ),
                                DropdownMenuItem(
                                  value: "HEAD",
                                  child: Text("HEAD"),
                                ),
                              ],
                              onChanged: ctrl.isRunning
                                  ? null
                                  : (v) {
                                      if (v != null)
                                        setState(() => _method = v);
                                    },
                              decoration: const InputDecoration(
                                labelText: "Method",
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _bodyController,
                              maxLines: 5,
                              decoration: const InputDecoration(
                                labelText: "Body (optional)",
                                hintText: "Raw request body",
                                border: OutlineInputBorder(),
                              ),
                              enabled: !ctrl.isRunning,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _headersController,
                              maxLines: 5,
                              decoration: const InputDecoration(
                                labelText: "Headers",
                                hintText:
                                    "Either JSON map or lines: Key: Value",
                                border: OutlineInputBorder(),
                              ),
                              enabled: !ctrl.isRunning,
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 140,
                            child: TextField(
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: "Timeout (s)",
                                border: OutlineInputBorder(),
                              ),
                              controller: TextEditingController(
                                text: _timeoutSeconds.toString(),
                              ),
                              onChanged: (v) {
                                final n = int.tryParse(v) ?? _timeoutSeconds;
                                setState(() => _timeoutSeconds = n);
                              },
                              enabled: !ctrl.isRunning,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: ctrl.isRunning ? null : _runSelected,
                              child: const Text("Run Selected (sequential)"),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: ctrl.isRunning
                                  ? null
                                  : _runAllSupported,
                              child: const Text(
                                "Run All Supported (sequential)",
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton(
                            onPressed: ctrl.isRunning ? null : ctrl.clearOutput,
                            child: const Text("Clear"),
                          ),
                        ],
                      ),
                      if (ctrl.isRunning && ctrl.currentStackId != null) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "Running: ${ctrl.currentStackId}",
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                      // Offstage WebView to keep controller alive in widget tree
                      const SizedBox(height: 8),
                      Offstage(
                        offstage: true,
                        child: SizedBox(
                          height: 0,
                          width: 0,
                          child: WebViewWidget(controller: _webViewController),
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // B) Stack list
                Expanded(
                  flex: 2,
                  child: ListView.builder(
                    itemCount: stacks.length,
                    itemBuilder: (context, i) {
                      final s = stacks[i];
                      final sup = s.support();
                      final isSelected = ctrl.selected.contains(s.id);
                      final isRunningThis = ctrl.currentStackId == s.id;

                      final res = ctrl.results[s.id];
                      final status = res?.status;
                      final hasErr = res?.error != null;

                      return ListTile(
                        enabled: sup.supported && !ctrl.isRunning,
                        leading: Checkbox(
                          value: isSelected,
                          onChanged: (!sup.supported || ctrl.isRunning)
                              ? null
                              : (v) => ctrl.toggleSelected(s.id, v ?? false),
                        ),
                        title: Row(
                          children: [
                            Expanded(child: Text(s.name)),
                            if (isRunningThis)
                              const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          sup.supported
                              ? s.description
                              : "${s.description}\nNot supported: ${sup.reason}",
                        ),
                        trailing: _StatusChip(status: status, error: hasErr),
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            builder: (_) => Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.name,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text("Layer: ${s.layer.name}"),
                                  const SizedBox(height: 8),
                                  Text(s.description),
                                  const SizedBox(height: 10),
                                  Text(
                                    sup.supported
                                        ? "Supported on this platform ✅"
                                        : "Unsupported 🚫 — ${sup.reason}",
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),

                const Divider(height: 1),

                // C) Output pane
                Expanded(
                  flex: 3,
                  child: TabBarView(
                    children: [
                      // Results
                      ListView(
                        padding: const EdgeInsets.all(12),
                        children: stacks.map((s) {
                          final r = ctrl.results[s.id];
                          if (r == null) {
                            return Card(
                              child: ListTile(
                                title: Text(s.name),
                                subtitle: const Text("No result yet."),
                              ),
                            );
                          }
                          final title =
                              "${s.name}  •  status=${r.status ?? '—'}  •  ${r.durationMs}ms";
                          final sub = r.error != null
                              ? "ERROR: ${r.error}\n\n${previewBody(r.body)}"
                              : previewBody(r.body);

                          return Card(
                            child: ListTile(
                              title: Text(title),
                              subtitle: Text(
                                sub,
                                style: const TextStyle(fontFamily: "monospace"),
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                      // Logs
                      ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: ctrl.logs.length,
                        itemBuilder: (context, i) {
                          final l = ctrl.logs[i];
                          final ts = l.ts
                              .toIso8601String()
                              .split("T")
                              .last
                              .split(".")
                              .first;
                          return Text(
                            "[$ts] ${l.text}",
                            style: const TextStyle(fontFamily: "monospace"),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  final int? status;
  final bool error;

  const _StatusChip({required this.status, required this.error});

  @override
  Widget build(BuildContext context) {
    String text;
    if (error) {
      text = "error";
    } else if (status == null) {
      text = "—";
    } else {
      text = status.toString();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
