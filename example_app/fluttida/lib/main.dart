import 'package:flutter/material.dart';
import 'lab_screen.dart';
import 'stacks/stacks_impl.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Request consent information update and show consent form if needed
  await _requestConsentInfoUpdate();

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

/// Request consent information update using Google UMP SDK
/// This handles GDPR, CCPA, and other privacy regulations
Future<void> _requestConsentInfoUpdate() async {
  final params = ConsentRequestParameters();

  // For testing purposes, you can reset consent by uncommenting:
  // await ConsentInformation.instance.reset();

  ConsentInformation.instance.requestConsentInfoUpdate(
    params,
    () async {
      // Consent info updated successfully
      if (await ConsentInformation.instance.isConsentFormAvailable()) {
        await _loadConsentForm();
      }
    },
    (FormError error) {
      // Handle error - consent form not available
      // We'll still initialize ads, but as non-personalized
      debugPrint('Consent form error: ${error.errorCode} - ${error.message}');
    },
  );
}

/// Load and show consent form if required
Future<void> _loadConsentForm() async {
  ConsentForm.loadConsentForm(
    (ConsentForm consentForm) async {
      final status = await ConsentInformation.instance.getConsentStatus();
      if (status == ConsentStatus.required) {
        consentForm.show((FormError? formError) {
          // Handle form dismissal
          if (formError != null) {
            debugPrint(
              'Consent form error: ${formError.errorCode} - ${formError.message}',
            );
          }
          // Reload consent form for next time if needed
          _loadConsentForm();
        });
      }
    },
    (FormError formError) {
      // Handle form load error
      debugPrint(
        'Failed to load consent form: ${formError.errorCode} - ${formError.message}',
      );
    },
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
