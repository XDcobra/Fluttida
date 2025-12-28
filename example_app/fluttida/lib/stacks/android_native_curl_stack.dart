import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/services.dart';

import '../lab_screen.dart';
import 'stacks_common.dart' as stacks_common;

const MethodChannel _legacyChannel = MethodChannel('fluttida/network');

Future<RequestResult> requestAndroidNativeCurl(RequestConfig cfg) async {
  if (!io.Platform.isAndroid) {
    return RequestResult(
      status: null,
      body: '',
      durationMs: 0,
      error: 'Android NDK (libcurl) is Android-only',
    );
  }

  final map = await _legacyChannel.invokeMapMethod<String, dynamic>('androidNativeCurl', {
    'url': cfg.url,
    'method': cfg.method,
    'headers': cfg.headers,
    'body': cfg.body,
    'timeoutMs': cfg.timeout.inMilliseconds,
  });

  return stacks_common.fromNativeMap(map,
      noResponseError: 'No response from native channel (NDK libcurl).');
}
