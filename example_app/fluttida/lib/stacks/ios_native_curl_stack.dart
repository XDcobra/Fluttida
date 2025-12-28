import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/services.dart';

import '../lab_screen.dart';
import 'stacks_common.dart' as stacks_common;

const MethodChannel _legacyChannel = MethodChannel('fluttida/network');

Future<RequestResult> requestIosNativeCurl(RequestConfig cfg) async {
  if (!io.Platform.isIOS) {
    return RequestResult(
      status: null,
      body: '',
      durationMs: 0,
      error: 'iOS native curl is iOS-only',
    );
  }

  final map = await _legacyChannel.invokeMapMethod<String, dynamic>('iosNativeCurl', {
    'method': cfg.method,
    'url': cfg.url,
    'headers': cfg.headers,
    'body': cfg.body,
    'timeoutMs': cfg.timeout.inMilliseconds,
  });

  return stacks_common.fromNativeMap(map,
      noResponseError: 'No response from native channel (iOS native curl).');
}
