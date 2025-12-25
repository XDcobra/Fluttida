import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'pinning_config.dart';
import 'stacks/stacks_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  PinningConfig _pinning = const PinningConfig.disabled();
  final TextEditingController _pinInputController = TextEditingController();
  bool _useGlobalOverride = false;

  @override
  void initState() {
    super.initState();
    _loadPinningConfig();
    _loadGlobalOverrideSetting();
  }

  @override
  void dispose() {
    _pinInputController.dispose();
    super.dispose();
  }

  Future<void> _loadPinningConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('pinning.config');
      if (raw != null) {
        _pinning = PinningConfig.importJson(raw);
      }
    } catch (_) {}
    await StacksImpl.setGlobalPinningConfig(_pinning);
    if (mounted) setState(() {});
  }

  Future<void> _savePinningConfig(PinningConfig cfg) async {
    setState(() => _pinning = cfg);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pinning.config', PinningConfig.exportJson(cfg));
    } catch (_) {}
    await StacksImpl.setGlobalPinningConfig(cfg);
  }

  Future<void> _loadGlobalOverrideSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getBool('pinning.useGlobalOverride') ?? false;
      if (mounted) setState(() => _useGlobalOverride = value);
    } catch (_) {}
  }

  Future<void> _saveGlobalOverrideSetting(bool value) async {
    setState(() => _useGlobalOverride = value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('pinning.useGlobalOverride', value);
    } catch (_) {}
    if (value) {
      StacksImpl.enableGlobalHttpOverrides();
    } else {
      StacksImpl.disableGlobalHttpOverrides();
    }
  }

  void _toggleStack(String key, bool enabled) {
    final stacks = Map<String, StackPinConfig>.from(_pinning.stacks);
    final existing = stacks[key] ?? const StackPinConfig.disabled();
    stacks[key] = StackPinConfig(
      enabled: enabled,
      technique: existing.technique,
    );
    _savePinningConfig(_pinning.copyWith(stacks: stacks));
  }

  void _setStackTechnique(String key, PinningTechnique technique) {
    final stacks = Map<String, StackPinConfig>.from(_pinning.stacks);
    final existing = stacks[key] ?? const StackPinConfig.disabled();
    stacks[key] = StackPinConfig(
      enabled: existing.enabled,
      technique: technique,
    );
    _savePinningConfig(_pinning.copyWith(stacks: stacks));
  }

  @override
  Widget build(BuildContext context) {
    final activePins = _pinning.mode == PinningMode.publicKey
        ? _pinning.spkiPins
        : _pinning.certSha256Pins;

    return Scaffold(
      appBar: AppBar(title: const Text('SSL Pinning Settings')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SSL Certificate Pinning',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Enable Pinning'),
                    value: _pinning.enabled,
                    onChanged: (v) =>
                        _savePinningConfig(_pinning.copyWith(enabled: v)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text(
                        'Mode:',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SegmentedButton<PinningMode>(
                          segments: const [
                            ButtonSegment(
                              value: PinningMode.publicKey,
                              label: Text('Public Key (SPKI)'),
                            ),
                            ButtonSegment(
                              value: PinningMode.certHash,
                              label: Text('Certificate Hash'),
                            ),
                          ],
                          selected: {_pinning.mode},
                          onSelectionChanged: (Set<PinningMode> selection) {
                            _savePinningConfig(
                              _pinning.copyWith(mode: selection.first),
                            );
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.info_outline, size: 20),
                        onPressed: _showModeInfo,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text(
                        'Pins',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '(${_pinning.mode == PinningMode.publicKey ? 'SPKI SHA-256' : 'Cert SHA-256'})',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (activePins.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No pins configured',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  else
                    ...activePins.asMap().entries.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                e.value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, size: 20),
                              onPressed: () {
                                final list = List<String>.from(activePins)
                                  ..removeAt(e.key);
                                _savePinningConfig(
                                  _pinning.mode == PinningMode.publicKey
                                      ? _pinning.copyWith(spkiPins: list)
                                      : _pinning.copyWith(certSha256Pins: list),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _pinInputController,
                          decoration: const InputDecoration(
                            labelText: 'Add pin (base64)',
                            hintText: 'AbCd...==',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _addPinFromInput(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _addPinFromInput,
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () async {
                          final imported = await _promptImportJson(context);
                          if (imported != null) {
                            await _savePinningConfig(imported);
                          }
                        },
                        icon: const Icon(Icons.upload_file, size: 18),
                        label: const Text('Import'),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () => _promptExportJson(context, _pinning),
                        icon: const Icon(Icons.download, size: 18),
                        label: const Text('Export'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Per-Stack Configuration',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enable pinning for specific HTTP stacks',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  _buildStackRow(
                    key: 'httpUrlConnection',
                    label: 'HttpURLConnection',
                    techniques: const [PinningTechnique.postConnect],
                  ),
                  _buildStackRow(
                    key: 'okHttp',
                    label: 'OkHttp',
                    techniques: const [
                      PinningTechnique.postConnect,
                      PinningTechnique.okhttpPinner,
                    ],
                    badge:
                        _pinning.mode == PinningMode.certHash &&
                            (_pinning.stacks['okHttp']?.technique ==
                                PinningTechnique.okhttpPinner)
                        ? '(SPKI only)'
                        : null,
                  ),
                  _buildStackRow(
                    key: 'nativeCurl',
                    label: 'NDK libcurl',
                    techniques: const [
                      PinningTechnique.curlPreflight,
                      PinningTechnique.curlSslCtx,
                      PinningTechnique.curlBoth,
                    ],
                  ),
                  _buildStackRow(
                    key: 'cronet',
                    label: 'Cronet',
                    techniques: const [],
                    badge: '(SPKI only)',
                    disabled: _pinning.mode == PinningMode.certHash,
                  ),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text(
                    'dart:io Stacks',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  _buildStackRow(
                    key: 'dartIo',
                    label: 'dart:io (HttpClient)',
                    techniques: const [],
                    badge: _useGlobalOverride ? '(via global override)' : null,
                  ),
                  _buildStackRow(
                    key: 'packageHttp',
                    label: 'package:http',
                    techniques: const [],
                    badge: _useGlobalOverride ? '(via global override)' : null,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.settings, size: 18),
                            const SizedBox(width: 8),
                            const Text(
                              'Alternative: Global HttpOverrides',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Use global dart:io override'),
                          subtitle: const Text(
                            'Replaces per-stack for all dart:io-based stacks',
                          ),
                          value: _useGlobalOverride,
                          onChanged: _saveGlobalOverrideSetting,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStackRow({
    required String key,
    required String label,
    required List<PinningTechnique> techniques,
    String? badge,
    bool disabled = false,
  }) {
    final config = _pinning.stacks[key] ?? const StackPinConfig.disabled();
    final isEnabled = config.enabled && !disabled;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Checkbox(
            value: isEnabled,
            onChanged: disabled ? null : (v) => _toggleStack(key, v ?? false),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: disabled ? Theme.of(context).disabledColor : null,
                  ),
                ),
                if (badge != null)
                  Text(
                    badge,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: disabled
                          ? Theme.of(context).disabledColor
                          : Colors.orange,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          if (techniques.isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: DropdownButton<PinningTechnique>(
                isExpanded: true,
                isDense: true,
                value: config.technique,
                items: techniques
                    .map(
                      (t) => DropdownMenuItem(
                        value: t,
                        child: Text(
                          _techniqueLabel(t),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (isEnabled && !disabled)
                    ? (t) {
                        if (t != null) _setStackTechnique(key, t);
                      }
                    : null,
              ),
            ),
          ] else
            const Expanded(flex: 3, child: SizedBox()),
        ],
      ),
    );
  }

  String _techniqueLabel(PinningTechnique t) {
    switch (t) {
      case PinningTechnique.none:
        return 'None';
      case PinningTechnique.postConnect:
        return 'Post-Connect';
      case PinningTechnique.okhttpPinner:
        return 'CertificatePinner';
      case PinningTechnique.curlPreflight:
        return 'Preflight';
      case PinningTechnique.curlSslCtx:
        return 'SSL_CTX Callback';
      case PinningTechnique.curlBoth:
        return 'Both';
    }
  }

  void _showModeInfo() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Pinning Modes'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Public Key (SPKI):',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text(
                'Pins the server public key. More resilient across certificate renewals. Recommended for most use cases.',
              ),
              SizedBox(height: 12),
              Text(
                'Certificate Hash:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text(
                'Pins the full leaf certificate fingerprint. Use only when you must pin the exact certificate.',
              ),
              SizedBox(height: 12),
              Text(
                '⚠️ Note: Some techniques only support SPKI mode (e.g., OkHttp CertificatePinner, Cronet).',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _addPinFromInput() {
    final v = _pinInputController.text.trim();
    if (v.isEmpty) return;
    if (!isBase64Sha256(v)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid base64 SHA-256 value')),
      );
      return;
    }
    final activePins = _pinning.mode == PinningMode.publicKey
        ? _pinning.spkiPins
        : _pinning.certSha256Pins;
    final list = List<String>.from(activePins)..add(v);
    _savePinningConfig(
      _pinning.mode == PinningMode.publicKey
          ? _pinning.copyWith(spkiPins: list)
          : _pinning.copyWith(certSha256Pins: list),
    );
    _pinInputController.clear();
  }

  Future<PinningConfig?> _promptImportJson(BuildContext ctx) async {
    final controller = TextEditingController();
    return await showDialog<PinningConfig>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Import Configuration'),
        content: TextField(
          controller: controller,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: '{"enabled": true, "mode": "publicKey", ...}',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              try {
                final cfg = PinningConfig.importJson(controller.text);
                Navigator.pop(ctx, cfg);
              } catch (_) {
                ScaffoldMessenger.of(
                  ctx,
                ).showSnackBar(const SnackBar(content: Text('Invalid JSON')));
              }
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  void _promptExportJson(BuildContext ctx, PinningConfig cfg) {
    final json = PinningConfig.exportJson(cfg);
    showDialog<void>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Export Configuration'),
        content: SelectableText(
          json,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: json));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
              );
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
