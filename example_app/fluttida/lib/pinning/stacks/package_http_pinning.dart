import 'dart:io' as io;

import '../global_http_override.dart';

/// Pinning helper for package:http (IO-backed) requests.
class PackageHttpPinning {
  /// Check if package:http default should pin (dartIoHttp stack)
  static bool shouldPinDefault() {
    final cfg = GlobalHttpOverride.currentConfig;
    if (!cfg.enabled) return false; // Global disabled = ignore all
    if (GlobalHttpOverride.globalOverrideEnabled) return true;
    return cfg.stacks['dartIoHttp']?.enabled ?? false;
  }

  /// Check if package:http via explicit IOClient should pin (dartIoHttpExplicit stack)
  static bool shouldPinViaIOClient() {
    final cfg = GlobalHttpOverride.currentConfig;
    if (!cfg.enabled) return false; // Global disabled = ignore all
    if (GlobalHttpOverride.globalOverrideEnabled) return true;
    return cfg.stacks['dartIoHttpExplicit']?.enabled ?? false;
  }

  static io.HttpClient createClient() {
    return GlobalHttpOverride.createInstrumentedHttpClient();
  }
}
