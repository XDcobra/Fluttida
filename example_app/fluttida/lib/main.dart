import 'dart:async';
import 'package:flutter/material.dart';
import 'lab_screen.dart';
import 'ad_config.dart';
import 'stacks/stacks_impl.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Notifier that signals when consent is complete and ads can be loaded
final ValueNotifier<bool> consentCompleteNotifier = ValueNotifier<bool>(false);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Start UI immediately so the app is usable while consent runs
  runApp(const MyApp());

  // Bootstrap consent + ads + overrides asynchronously with retry/backoff
  _bootstrap();
}

Future<void> _bootstrap() async {
  final adConfig = await AdConfig.load();
  if (adConfig.adsEnabled) {
    _initializeMobileAds();
    await _initConsentWithRetry();
  } else {
    debugPrint('ADS: disabled via BuildConfig.ADS_ENABLED');
  }

  await _initializeGlobalOverrides();
}

void _initializeMobileAds() {
  // Kick off Mobile Ads SDK initialization immediately (non-blocking)
  // This ensures the SDK is ready when banner requests are made from initState.
  try {
    final RequestConfiguration config = RequestConfiguration(
      testDeviceIds: <String>['5071A5FDBA233F83AEE71564026F08AB'],
    );

    MobileAds.instance.updateRequestConfiguration(config);

    MobileAds.instance.initialize();
  } catch (_) {}
}

Future<void> _initConsentWithRetry() async {
  const int maxAttempts = 5;
  Duration backoff = const Duration(seconds: 6);

  ConsentStatus? finalStatus;

  for (
    int attempt = 1;
    attempt <= maxAttempts && finalStatus == null;
    attempt++
  ) {
    try {
      finalStatus = await _initConsentAndPersistFlag().timeout(
        const Duration(seconds: 15),
      );
    } catch (_) {
      if (attempt < maxAttempts) {
        await Future.delayed(backoff);
        backoff *= 2;
      }
    }
  }

  if (finalStatus == null) {
    debugPrint('Consent: giving up after $maxAttempts attempts');
    return;
  }

  if (finalStatus != ConsentStatus.unknown) {
    consentCompleteNotifier.value = true;
    debugPrint('Consent complete → ads enabled ($finalStatus)');
  }
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
Future<ConsentStatus> _initConsentAndPersistFlag() async {
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

  final status = await ConsentInformation.instance.getConsentStatus();
  debugPrint('Consent: final status=$status');
  return status;
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
