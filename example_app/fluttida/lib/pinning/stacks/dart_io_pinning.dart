import 'dart:io' as io;

import '../global_http_override.dart';

/// Pinning helper for the dart:io HttpClient stack.
class DartIoPinning {
  static bool shouldPin() {
    final cfg = GlobalHttpOverride.currentConfig;
    if (!cfg.enabled) return false; // Global disabled = ignore all
    if (GlobalHttpOverride.globalOverrideEnabled) return true;
    return cfg.stacks['dartIoRaw']?.enabled ?? false;
  }

  static io.HttpClient createClient() {
    return GlobalHttpOverride.createInstrumentedHttpClient();
  }
}
