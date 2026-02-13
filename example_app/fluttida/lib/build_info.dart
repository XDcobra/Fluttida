import 'dart:io';
import 'package:flutter/services.dart';

class BuildInfo {
  final String versionName;
  final String buildNumber;

  const BuildInfo({required this.versionName, required this.buildNumber});

  static const MethodChannel _channel = MethodChannel('fluttida/network');
  static BuildInfo? _cached;

  static Future<BuildInfo> load() async {
    if (_cached != null) return _cached!;
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
      _cached = const BuildInfo(versionName: '0.0.0', buildNumber: '0');
      return _cached!;
    }

    try {
      final result = await _channel.invokeMethod('getBuildInfo');
      if (result is Map) {
        final versionName = result['versionName'];
        final buildNumber = result['buildNumber'];
        _cached = BuildInfo(
          versionName: versionName is String && versionName.isNotEmpty
              ? versionName
              : '0.0.0',
          buildNumber: buildNumber?.toString() ?? '0',
        );
        return _cached!;
      }
    } catch (_) {}

    _cached = const BuildInfo(versionName: '0.0.0', buildNumber: '0');
    return _cached!;
  }
}
