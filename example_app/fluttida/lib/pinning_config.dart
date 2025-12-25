import 'dart:convert';

enum PinningMode { publicKey, certHash }

// Technique options for how each stack enforces pinning
enum PinningTechnique {
  none, // disable enforcement for the stack
  postConnect, // post-connect verification in client (HttpURLConnection/OkHttp)
  trustManager, // Custom TrustManager (HttpURLConnection)
  okhttpPinner, // OkHttp CertificatePinner (SPKI only)
  curlPreflight, // Native curl: preflight OpenSSL probe only
  curlSslCtx, // Native curl: SSL_CTX verify callback only
  curlBoth, // Native curl: preflight + SSL_CTX
}

// Per-stack pinning configuration
class StackPinConfig {
  final bool enabled;
  final PinningTechnique technique;

  const StackPinConfig({required this.enabled, required this.technique});

  const StackPinConfig.disabled()
    : enabled = false,
      technique = PinningTechnique.postConnect;

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'technique': technique.name,
  };

  static StackPinConfig fromJson(Map<String, dynamic>? m) {
    if (m == null) return const StackPinConfig.disabled();
    return StackPinConfig(
      enabled: m['enabled'] == true,
      technique: _techFromName(m['technique'] as String?),
    );
  }

  static PinningTechnique _techFromName(String? s) {
    switch (s) {
      case 'none':
        return PinningTechnique.none;
      case 'postConnect':
        return PinningTechnique.postConnect;
      case 'trustManager':
        return PinningTechnique.trustManager;
      case 'okhttpPinner':
        return PinningTechnique.okhttpPinner;
      case 'curlPreflight':
        return PinningTechnique.curlPreflight;
      case 'curlSslCtx':
        return PinningTechnique.curlSslCtx;
      case 'curlBoth':
        return PinningTechnique.curlBoth;
      default:
        return PinningTechnique.postConnect;
    }
  }
}

class PinningConfig {
  final bool enabled;
  final PinningMode mode;
  final List<String> spkiPins; // base64 SHA-256 of SPKI
  final List<String> certSha256Pins; // base64 SHA-256 of full cert

  // Per-stack configuration
  final Map<String, StackPinConfig>
  stacks; // keys: httpUrlConnection, okHttp, nativeCurl, cronet, dartIo

  const PinningConfig({
    required this.enabled,
    required this.mode,
    required this.spkiPins,
    required this.certSha256Pins,
    this.stacks = const {},
  });

  const PinningConfig.disabled()
    : enabled = false,
      mode = PinningMode.publicKey,
      spkiPins = const [],
      certSha256Pins = const [],
      stacks = const {};

  PinningConfig copyWith({
    bool? enabled,
    PinningMode? mode,
    List<String>? spkiPins,
    List<String>? certSha256Pins,
    Map<String, StackPinConfig>? stacks,
  }) {
    return PinningConfig(
      enabled: enabled ?? this.enabled,
      mode: mode ?? this.mode,
      spkiPins: spkiPins ?? this.spkiPins,
      certSha256Pins: certSha256Pins ?? this.certSha256Pins,
      stacks: stacks ?? this.stacks,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'mode': mode.name,
    'spkiPins': spkiPins,
    'certSha256Pins': certSha256Pins,
    'stacks': stacks.map((k, v) => MapEntry(k, v.toJson())),
  };

  static PinningConfig fromJson(Map<String, dynamic> m) {
    final modeStr = (m['mode'] as String?) ?? PinningMode.publicKey.name;
    final mode = modeStr == PinningMode.certHash.name
        ? PinningMode.certHash
        : PinningMode.publicKey;

    // Parse stacks (backward compatible with old 'techniques' format)
    Map<String, StackPinConfig> stacks = {};
    final stacksData = m['stacks'];
    if (stacksData is Map) {
      stacksData.forEach((k, v) {
        if (k is String && v is Map<String, dynamic>) {
          stacks[k] = StackPinConfig.fromJson(v);
        }
      });
    } else {
      // Backward compat: try reading old 'techniques.overrides' format
      final techs = m['techniques'];
      if (techs is Map) {
        final ov = techs['overrides'];
        if (ov is Map) {
          ov.forEach((k, v) {
            if (k is String) {
              stacks[k] = StackPinConfig(
                enabled: true,
                technique: StackPinConfig._techFromName(v as String?),
              );
            }
          });
        }
      }
    }

    return PinningConfig(
      enabled: m['enabled'] == true,
      mode: mode,
      spkiPins: (m['spkiPins'] as List?)?.cast<String>() ?? const [],
      certSha256Pins:
          (m['certSha256Pins'] as List?)?.cast<String>() ?? const [],
      stacks: stacks,
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
