import 'dart:io';
import 'package:flutter/services.dart';

class AdConfig {
  final bool adsEnabled;
  final String? bannerUnitAndroid;
  final String? bannerUnitIos;

  const AdConfig({
    required this.adsEnabled,
    this.bannerUnitAndroid,
    this.bannerUnitIos,
  });

  String? get bannerUnit {
    if (Platform.isAndroid) return bannerUnitAndroid;
    if (Platform.isIOS || Platform.isMacOS)
      return bannerUnitIos ?? bannerUnitAndroid;
    return null;
  }

  static const MethodChannel _channel = MethodChannel('fluttida/network');
  static AdConfig? _cached;

  static Future<AdConfig> load() async {
    if (_cached != null) return _cached!;

    // Only attempt native MethodChannel on mobile/desktop Apple/Android
    if (!(Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
      _cached = const AdConfig(adsEnabled: false);
      return _cached!;
    }

    try {
      final result = await _channel.invokeMethod('getAdConfig');
      if (result is Map) {
        final adsEnabled = result['adsEnabled'] == true;
        final bannerAndroid = result['admobBannerUnitAndroid'];
        final bannerIos =
            result['admobBannerUnitIos'] ?? result['admobBannerUnit'];
        _cached = AdConfig(
          adsEnabled: adsEnabled,
          bannerUnitAndroid: bannerAndroid is String && bannerAndroid.isNotEmpty
              ? bannerAndroid
              : null,
          bannerUnitIos: bannerIos is String && bannerIos.isNotEmpty
              ? bannerIos
              : null,
        );
        return _cached!;
      }
    } catch (_) {}

    _cached = const AdConfig(adsEnabled: false);
    return _cached!;
  }
}
