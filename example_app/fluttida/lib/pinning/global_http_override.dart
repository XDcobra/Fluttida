import 'dart:convert';
import 'dart:io' as io;

import 'package:asn1lib/asn1lib.dart';
import 'package:crypto/crypto.dart' as crypto;

import '../pinning_config.dart';

/// Centralizes global HttpOverrides and instrumented HttpClient creation
/// so dart:io-based stacks can opt into pinning or stay plain.
class GlobalHttpOverride {
  static PinningConfig _config = const PinningConfig.disabled();
  static bool _globalOverrideEnabled = false;
  static void Function(String)? _logSink;
  static final io.HttpOverrides _noOverrides = _NoOverrides();

  static void setConfig(PinningConfig cfg) {
    _config = cfg;
  }

  static void setLogSink(void Function(String)? sink) {
    _logSink = sink;
  }

  static bool get globalOverrideEnabled => _globalOverrideEnabled;

  static void enableGlobalOverride() {
    _globalOverrideEnabled = true;
    io.HttpOverrides.global = _PinnedHttpOverrides();
  }

  static void disableGlobalOverride() {
    _globalOverrideEnabled = false;
    io.HttpOverrides.global = null;
  }

  static bool shouldPinDartIo() {
    if (_globalOverrideEnabled) return true;
    if (!_config.enabled) return false;
    return _config.stacks['dartIo']?.enabled == true;
  }

  static bool shouldPinPackageHttp() {
    if (_globalOverrideEnabled) return true;
    if (!_config.enabled) return false;
    return _config.stacks['packageHttp']?.enabled == true;
  }

  static io.HttpClient createInstrumentedHttpClient() {
    final client = _newHttpClientRaw();
    client.badCertificateCallback =
        (io.X509Certificate cert, String host, int port) {
              if (!_config.enabled) return true;
              _log(
                '[PIN DEBUG] badCertificateCallback invoked for host=$host port=$port mode=${_config.mode.name} spkiPins=${_config.spkiPins.length} certPins=${_config.certSha256Pins.length}',
              );
              try {
                if (_config.mode == PinningMode.certHash) {
                  final h = _computeCertSha256Base64(cert);
                  _log('[PIN DEBUG] computed cert sha256 (base64)=$h');
                  if (_config.certSha256Pins.contains(h)) return true;
                  _log('[PIN DEBUG] cert hash mismatch');
                  return false;
                } else {
                  final h = _computeSpkiSha256Base64(cert);
                  _log('[PIN DEBUG] computed spki sha256 (base64)=$h');
                  if (_config.spkiPins.contains(h)) return true;
                  _log('[PIN DEBUG] spki hash mismatch');
                  return false;
                }
              } catch (e, st) {
                _log('[PIN DEBUG] pin check failed: $e\n$st');
                return false;
              }
            }
            as bool Function(io.X509Certificate, String, int)?;
    return client;
  }

  static io.HttpClient _newHttpClientRaw() {
    final ctx = io.SecurityContext(withTrustedRoots: false);
    return io.HttpOverrides.runWithHttpOverrides<io.HttpClient>(
      () => io.HttpClient(context: ctx),
      _noOverrides,
    );
  }

  static void _log(String msg) {
    // ignore: avoid_print
    print(msg);
    try {
      _logSink?.call(msg);
    } catch (_) {}
  }

  static String _computeCertSha256Base64(io.X509Certificate cert) {
    final der = cert.der;
    final digest = crypto.sha256.convert(der);
    return base64.encode(digest.bytes);
  }

  static String _computeSpkiSha256Base64(io.X509Certificate cert) {
    final der = cert.der;
    final parser = ASN1Parser(der);
    final top = parser.nextObject() as ASN1Sequence; // Certificate
    final tbs = top.elements[0] as ASN1Sequence; // tbsCertificate

    ASN1Sequence? spki;
    for (final el in tbs.elements) {
      if (el is ASN1Sequence) {
        final children = el.elements;
        if (children.any((c) => c is ASN1BitString)) {
          spki = el;
          break;
        }
      }
    }
    if (spki == null) {
      if (tbs.elements.length > 6 && tbs.elements[6] is ASN1Sequence) {
        spki = tbs.elements[6] as ASN1Sequence;
      } else {
        throw Exception('SPKI not found in certificate');
      }
    }
    final spkiBytes = spki.encodedBytes;
    final digest = crypto.sha256.convert(spkiBytes);
    return base64.encode(digest.bytes);
  }
}

class _PinnedHttpOverrides extends io.HttpOverrides {
  @override
  io.HttpClient createHttpClient(io.SecurityContext? context) {
    return GlobalHttpOverride.createInstrumentedHttpClient();
  }
}

class _NoOverrides extends io.HttpOverrides {}
