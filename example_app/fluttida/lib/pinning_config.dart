import 'dart:convert';

enum PinningMode { publicKey, certHash }

// Technique options for how each stack enforces pinning
enum PinningTechnique {
  auto, // default behavior per stack
  none, // disable enforcement for the stack
  postConnect, // post-connect verification in client (HttpURLConnection/OkHttp)
  okhttpPinner, // OkHttp CertificatePinner (SPKI only)
  curlPreflight, // Native curl: preflight OpenSSL probe only
  curlSslCtx, // Native curl: SSL_CTX verify callback only
  curlBoth, // Native curl: preflight + SSL_CTX
}

class PinningConfig {
  final bool enabled;
  final PinningMode mode;
  final List<String> spkiPins; // base64 SHA-256 of SPKI
  final List<String> certSha256Pins; // base64 SHA-256 of full cert

  // Technique selection
  final PinningTechnique defaultTechnique;
  final Map<String, PinningTechnique>
  stackOverrides; // keys: httpUrlConnection, okHttp, nativeCurl, cronet

  const PinningConfig({
    required this.enabled,
    required this.mode,
    required this.spkiPins,
    required this.certSha256Pins,
    this.defaultTechnique = PinningTechnique.auto,
    this.stackOverrides = const {},
  });

  const PinningConfig.disabled()
    : enabled = false,
      mode = PinningMode.publicKey,
      spkiPins = const [],
      certSha256Pins = const [],
      defaultTechnique = PinningTechnique.auto,
      stackOverrides = const {};

  PinningConfig copyWith({
    bool? enabled,
    PinningMode? mode,
    List<String>? spkiPins,
    List<String>? certSha256Pins,
    PinningTechnique? defaultTechnique,
    Map<String, PinningTechnique>? stackOverrides,
  }) {
    return PinningConfig(
      enabled: enabled ?? this.enabled,
      mode: mode ?? this.mode,
      spkiPins: spkiPins ?? this.spkiPins,
      certSha256Pins: certSha256Pins ?? this.certSha256Pins,
      defaultTechnique: defaultTechnique ?? this.defaultTechnique,
      stackOverrides: stackOverrides ?? this.stackOverrides,
    );
  }

  static String _techToName(PinningTechnique t) => t.name;
  static PinningTechnique _techFromName(String? s) {
    switch (s) {
      case 'none':
        return PinningTechnique.none;
      case 'postConnect':
        return PinningTechnique.postConnect;
      case 'okhttpPinner':
        return PinningTechnique.okhttpPinner;
      case 'curlPreflight':
        return PinningTechnique.curlPreflight;
      case 'curlSslCtx':
        return PinningTechnique.curlSslCtx;
      case 'curlBoth':
        return PinningTechnique.curlBoth;
      case 'auto':
      default:
        return PinningTechnique.auto;
    }
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'mode': mode.name,
    'spkiPins': spkiPins,
    'certSha256Pins': certSha256Pins,
    'techniques': {
      'default': _techToName(defaultTechnique),
      'overrides': stackOverrides.map((k, v) => MapEntry(k, _techToName(v))),
    },
  };

  static PinningConfig fromJson(Map<String, dynamic> m) {
    final modeStr = (m['mode'] as String?) ?? PinningMode.publicKey.name;
    final mode = modeStr == PinningMode.certHash.name
        ? PinningMode.certHash
        : PinningMode.publicKey;

    // techniques (backward compatible)
    PinningTechnique defTech = PinningTechnique.auto;
    Map<String, PinningTechnique> overrides = const {};
    final techs = m['techniques'];
    if (techs is Map) {
      defTech = _techFromName(techs['default'] as String?);
      final ov = techs['overrides'];
      if (ov is Map) {
        final tmp = <String, PinningTechnique>{};
        ov.forEach((k, v) {
          if (k is String) tmp[k] = _techFromName(v as String?);
        });
        overrides = tmp;
      }
    }

    return PinningConfig(
      enabled: m['enabled'] == true,
      mode: mode,
      spkiPins: (m['spkiPins'] as List?)?.cast<String>() ?? const [],
      certSha256Pins:
          (m['certSha256Pins'] as List?)?.cast<String>() ?? const [],
      defaultTechnique: defTech,
      stackOverrides: overrides,
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
