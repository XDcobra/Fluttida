import 'package:flutter/material.dart';
import 'lab_screen.dart';
import 'stacks/stacks_impl.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
