import 'dart:async';
import 'package:flutter/material.dart';
import 'lab_screen.dart';
import 'versions.dart';
import 'stacks/stacks_impl.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Notifier that signals when consent is complete and ads can be loaded
final ValueNotifier<bool> consentCompleteNotifier = ValueNotifier<bool>(false);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Start UI immediately so the app is usable while consent runs
  runApp(const MyApp());

  // Kick off Mobile Ads SDK initialization immediately (non-blocking)
  // This ensures the SDK is ready when banner requests are made from initState.
  // TEMP: output build-time AdMob IDs to logs for CI debug (remove later)
  try {
    debugPrint(
      'BUILD: kIsLabApp=$kIsLabApp kAdMobAppId=$kAdMobAppId kAdMobBannerUnitAndroid=$kAdMobBannerUnitAndroid kAdMobBannerUnitIos=$kAdMobBannerUnitIos',
    );
  } catch (_) {}

  try {
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(testDeviceIds: ['E6EC72C60550A0F920B2B7FCDFA91129']),
    );
  } catch (_) {}

  try {
    await MobileAds.instance.initialize();
  } catch (_) {}

  // Bootstrap consent + ads + overrides asynchronously with retry/backoff
  _bootstrap();
}

Future<void> _bootstrap() async {
  const int maxAttempts = 5;
  Duration backoff = const Duration(seconds: 6);
  bool consentDone = false;

  for (int attempt = 1; attempt <= maxAttempts && !consentDone; attempt++) {
    try {
      await _initConsentAndPersistFlag().timeout(const Duration(seconds: 15));
      consentDone = true;
    } catch (e) {
      if (attempt < maxAttempts) {
        await Future.delayed(backoff);
        backoff *= 2;
      }
    }
  }

  if (!consentDone) {
    debugPrint('Consent: giving up after $maxAttempts attempts');
  }

  // Initialize MobileAds after consent handling (or after retries)
  try {
    await MobileAds.instance.initialize();
  } catch (_) {}

  // Signal that consent is complete so ads can be loaded
  consentCompleteNotifier.value = true;

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

    final needsForm =
        status == ConsentStatus.required || status == ConsentStatus.unknown;

    if (!formAvailable || !needsForm) {
      return;
    }

    final showDone = Completer<void>();
    ConsentForm.loadConsentForm(
      (ConsentForm form) {
        form.show((FormError? formError) {
          if (!showDone.isCompleted) showDone.complete();
        });
      },
      (FormError formError) {
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
  // ...existing code...
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
