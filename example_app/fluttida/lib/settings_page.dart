import 'package:flutter/material.dart';
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
  bool _cronetPinningSupported = false;

  @override
  void initState() {
    super.initState();
    _loadPinningConfig();
    _detectCronetSupport();
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

  Future<void> _detectCronetSupport() async {
    final supported = await StacksImpl.isCronetPinningSupported();
    if (mounted) setState(() => _cronetPinningSupported = supported);
  }

  @override
  Widget build(BuildContext context) {
    final activePins = _pinning.mode == PinningMode.publicKey
        ? _pinning.spkiPins
        : _pinning.certSha256Pins;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
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
                    'SSL Pinning',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Enable SSL Pinning'),
                    subtitle: const Text(
                      'Global toggle for Android HTTP stacks',
                    ),
                    value: _pinning.enabled,
                    onChanged: (v) =>
                        _savePinningConfig(_pinning.copyWith(enabled: v)),
                  ),
                  Row(
                    children: [
                      const Text('Mode:'),
                      const SizedBox(width: 12),
                      DropdownButton<PinningMode>(
                        value: _pinning.mode,
                        items: const [
                          DropdownMenuItem(
                            value: PinningMode.publicKey,
                            child: Text('Public Key (SPKI)'),
                          ),
                          DropdownMenuItem(
                            value: PinningMode.certHash,
                            child: Text('Certificate SHA-256'),
                          ),
                        ],
                        onChanged: (m) {
                          if (m != null)
                            _savePinningConfig(_pinning.copyWith(mode: m));
                        },
                      ),
                    ],
                  ),
                  if (_pinning.enabled && !_cronetPinningSupported)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Note: Cronet does not support pinning in this build; it will warn and skip.',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Colors.orange),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Pins (${_pinning.mode == PinningMode.publicKey ? 'SPKI' : 'Cert SHA-256'})',
                  ),
                  const SizedBox(height: 8),
                  for (int i = 0; i < activePins.length; i++)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            activePins[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () {
                            final list = List<String>.from(activePins)
                              ..removeAt(i);
                            _savePinningConfig(
                              _pinning.mode == PinningMode.publicKey
                                  ? _pinning.copyWith(spkiPins: list)
                                  : _pinning.copyWith(certSha256Pins: list),
                            );
                          },
                        ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          decoration: const InputDecoration(
                            labelText: 'Add base64 SHA-256 pin',
                            hintText: 'e.g. AbCd...==',
                            border: OutlineInputBorder(),
                          ),
                          onFieldSubmitted: (v) {
                            if (!isBase64Sha256(v)) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Invalid base64 SHA-256 value'),
                                ),
                              );
                              return;
                            }
                            final list = List<String>.from(activePins)..add(v);
                            _savePinningConfig(
                              _pinning.mode == PinningMode.publicKey
                                  ? _pinning.copyWith(spkiPins: list)
                                  : _pinning.copyWith(certSha256Pins: list),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          final imported = await _promptImportJson(context);
                          if (imported != null)
                            await _savePinningConfig(imported);
                        },
                        child: const Text('Import'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => _promptExportJson(context, _pinning),
                        child: const Text('Export'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<PinningConfig?> _promptImportJson(BuildContext ctx) async {
    final controller = TextEditingController();
    return await showDialog<PinningConfig>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Import pins (JSON)'),
        content: TextField(controller: controller, maxLines: 8),
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
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Export pins (JSON)'),
        content: SelectableText(
          json,
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
