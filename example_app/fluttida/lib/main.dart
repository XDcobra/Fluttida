import 'dart:async';
import 'package:flutter/material.dart';
import 'lab_screen.dart';
import 'stacks/stacks_impl.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Start UI immediately so the app is usable while consent runs
  runApp(const MyApp());

  // Bootstrap consent + ads + overrides asynchronously with retry/backoff
  _bootstrap();
}

Future<void> _bootstrap() async {
  const int maxAttempts = 3;
  Duration backoff = const Duration(seconds: 6);
  bool consentDone = false;

  for (int attempt = 1; attempt <= maxAttempts && !consentDone; attempt++) {
    debugPrint('Consent: attempt $attempt/$maxAttempts');
    try {
      // Try consent flow with timeout; on timeout or error, we'll retry
      await _initConsentAndPersistFlag().timeout(const Duration(seconds: 8));
      consentDone = true;
      debugPrint('Consent: completed on attempt $attempt');
    } catch (e) {
      debugPrint('Consent: timeout/error on attempt $attempt: $e');
      if (attempt < maxAttempts) {
        await Future.delayed(backoff);
        backoff *= 2;
      }
    }
  }

  // Initialize MobileAds after consent handling (or after retries)
  try {
    await MobileAds.instance.initialize();
  } catch (_) {}

  // Apply global overrides after UI is up
  await _initializeGlobalOverrides();
}

Future<void> _initializeGlobalOverrides() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final useGlobal = prefs.getBool('pinning.useGlobalOverride') ?? false;
    if (useGlobal) {
      StacksImpl.enableGlobalHttpOverrides();
    } else {
      StacksImpl.disableGlobalHttpOverrides();
    }
  } catch (_) {
    // If loading fails, don't enable global overrides
  }
}

/// Runs consent flow and shows form when required.
/// Returns a Future that completes when the consent flow is finished.
Future<void> _initConsentAndPersistFlag() async {
  final updateDone = Completer<void>();

  Future<void> showFormIfNeeded() async {
    final status = await ConsentInformation.instance.getConsentStatus();
    final formAvailable = await ConsentInformation.instance
        .isConsentFormAvailable();

    // Treat unknown the same as required: attempt to show form when available.
    final needsForm =
        status == ConsentStatus.required || status == ConsentStatus.unknown;

    if (!formAvailable || !needsForm) {
      debugPrint(
        'Consent form not shown (status=$status, available=$formAvailable)',
      );
      return;
    }

    final showDone = Completer<void>();
    ConsentForm.loadConsentForm(
      (ConsentForm form) {
        form.show((FormError? formError) {
          if (formError != null) {
            debugPrint('Consent form error: ${formError.message}');
          }
          if (!showDone.isCompleted) showDone.complete();
        });
      },
      (FormError formError) {
        debugPrint('Failed to load form: ${formError.message}');
        if (!showDone.isCompleted) showDone.complete();
      },
    );
    await showDone.future;
  }

  final params = ConsentRequestParameters(
    tagForUnderAgeOfConsent: false,
    consentDebugSettings: ConsentDebugSettings(
      // Enable for manual testing outside EU/EEA:
      // debugGeography: DebugGeography.debugGeographyEea,
      // testDeviceIdentifiers: ['YOUR-DEVICE-ID'],
    ),
  );

  ConsentInformation.instance.requestConsentInfoUpdate(
    params,
    () async {
      try {
        await showFormIfNeeded();
      } finally {
        if (!updateDone.isCompleted) updateDone.complete();
      }
    },
    (FormError error) {
      debugPrint('Consent info update failed: ${error.message}');
      if (!updateDone.isCompleted) updateDone.complete();
    },
  );

  await updateDone.future;
  final finalStatus = await ConsentInformation.instance.getConsentStatus();
  final finalCanRequest = await ConsentInformation.instance.canRequestAds();
  final finalFormAvailable = await ConsentInformation.instance
      .isConsentFormAvailable();
  debugPrint(
    'Consent flow completed | status=$finalStatus | canRequestAds=$finalCanRequest | formAvailable=$finalFormAvailable',
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fluttida',
      theme: ThemeData(useMaterial3: true),
      home: LabScreen(
        initialUrl: 'https://echo.free.beeceptor.com/',
        dartIoRaw: StacksImpl.requestDartIoRaw,
        httpDefault: StacksImpl.requestHttpDefault,
        httpIoClient: StacksImpl.requestHttpViaExplicitIoClient,
        cupertinoHttp: StacksImpl.requestCupertinoDefault,
        iosLegacyNsUrlConnection: StacksImpl.requestLegacyIos,
        androidHttpUrlConnection: StacksImpl.requestAndroidHttpUrlConnection,
        androidOkHttp: StacksImpl.requestAndroidOkHttp,
        androidCronet: StacksImpl.requestAndroidCronet,
        androidNativeCurl: StacksImpl.requestAndroidNativeCurl,
        iosNativeCurl: StacksImpl.requestIosNativeCurl,
        webViewHeadless: StacksImpl.requestWebViewHeadless,
      ),
    );
  }
}
