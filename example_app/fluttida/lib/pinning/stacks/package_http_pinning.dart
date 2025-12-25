import 'dart:io' as io;

import '../global_http_override.dart';

/// Pinning helper for package:http (IO-backed) requests.
class PackageHttpPinning {
  static bool shouldPin() => GlobalHttpOverride.shouldPinPackageHttp();

  static io.HttpClient createClient() {
    return GlobalHttpOverride.createInstrumentedHttpClient();
  }
}
