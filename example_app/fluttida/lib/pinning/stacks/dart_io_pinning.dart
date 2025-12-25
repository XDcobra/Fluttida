import 'dart:io' as io;

import '../global_http_override.dart';

/// Pinning helper for the dart:io HttpClient stack.
class DartIoPinning {
  static bool shouldPin() => GlobalHttpOverride.shouldPinDartIo();

  static io.HttpClient createClient() {
    return GlobalHttpOverride.createInstrumentedHttpClient();
  }
}
