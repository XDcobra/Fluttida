import 'dart:async';
import 'package:flutter/material.dart';
import 'lab_screen.dart';
import 'stacks/stacks_impl.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Run consent flow before initializing ads
  await _initConsentAndPersistFlag();

  // Initialize MobileAds after consent handling
  MobileAds.instance.initialize();

  // Conditionally enable global HttpOverrides based on user preference
  await _initializeGlobalOverrides();
  runApp(const MyApp());
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
  final completer = Completer<void>();

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
      // Success callback - check and show form if required
      final status = await ConsentInformation.instance.getConsentStatus();
      debugPrint('Consent status after update: $status');

      if (status == ConsentStatus.required) {
        final available = await ConsentInformation.instance
            .isConsentFormAvailable();
        if (available) {
          ConsentForm.loadConsentForm(
            (ConsentForm form) {
              form.show((FormError? formError) async {
                if (formError != null) {
                  debugPrint('Consent form error: ${formError.message}');
                }
                // Complete when form is dismissed
                completer.complete();
              });
            },
            (FormError formError) {
              debugPrint('Failed to load form: ${formError.message}');
              completer.complete(); // Complete even on error
            },
          );
        } else {
          completer.complete(); // No form available
        }
      } else {
        // Consent not required or already obtained
        completer.complete();
      }
    },
    (FormError error) {
      debugPrint('Consent info update failed: ${error.message}');
      completer.complete(); // Complete even on error
    },
  );

  // Wait for consent flow to complete
  await completer.future;
  debugPrint('Consent flow completed');
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
