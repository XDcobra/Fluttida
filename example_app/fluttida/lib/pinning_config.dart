import 'dart:convert';

enum PinningMode { publicKey, certHash }

class PinningConfig {
  final bool enabled;
  final PinningMode mode;
  final List<String> spkiPins; // base64 SHA-256 of SPKI
  final List<String> certSha256Pins; // base64 SHA-256 of full cert

  const PinningConfig({
    required this.enabled,
    required this.mode,
    required this.spkiPins,
    required this.certSha256Pins,
  });

  const PinningConfig.disabled()
    : enabled = false,
      mode = PinningMode.publicKey,
      spkiPins = const [],
      certSha256Pins = const [];

  PinningConfig copyWith({
    bool? enabled,
    PinningMode? mode,
    List<String>? spkiPins,
    List<String>? certSha256Pins,
  }) {
    return PinningConfig(
      enabled: enabled ?? this.enabled,
      mode: mode ?? this.mode,
      spkiPins: spkiPins ?? this.spkiPins,
      certSha256Pins: certSha256Pins ?? this.certSha256Pins,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'mode': mode.name,
    'spkiPins': spkiPins,
    'certSha256Pins': certSha256Pins,
  };

  static PinningConfig fromJson(Map<String, dynamic> m) {
    final modeStr = (m['mode'] as String?) ?? PinningMode.publicKey.name;
    final mode = modeStr == PinningMode.certHash.name
        ? PinningMode.certHash
        : PinningMode.publicKey;
    return PinningConfig(
      enabled: m['enabled'] == true,
      mode: mode,
      spkiPins: (m['spkiPins'] as List?)?.cast<String>() ?? const [],
      certSha256Pins:
          (m['certSha256Pins'] as List?)?.cast<String>() ?? const [],
    );
  }

  static String exportJson(PinningConfig cfg) =>
      const JsonEncoder.withIndent('  ').convert(cfg.toJson());
  static PinningConfig importJson(String s) =>
      PinningConfig.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

bool isBase64Sha256(String v) {
  // Accept padded/unpadded base64; SHA-256 is 32 bytes (typical padded length 44)
  final base64Chars = RegExp(r'^[A-Za-z0-9+/]+={0,2}$');
  return v.isNotEmpty &&
      v.length >= 40 &&
      v.length <= 64 &&
      base64Chars.hasMatch(v);
}
