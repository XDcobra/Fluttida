import '../global_http_override.dart';
import '../../pinning_config.dart';

/// Pinning helper for Android HttpURLConnection stack.
/// Supports both postConnect and trustManager techniques.
class AndroidHttpURLConnectionPinning {
  static bool shouldPin() {
    final cfg = GlobalHttpOverride.currentConfig;
    if (!cfg.enabled) return false;
    return cfg.stacks['androidHttpURLConnection']?.enabled ?? false;
  }

  static PinningTechnique getTechnique() {
    final cfg = GlobalHttpOverride.currentConfig;
    return cfg.stacks['androidHttpURLConnection']?.technique ??
        PinningTechnique.postConnect;
  }
}
