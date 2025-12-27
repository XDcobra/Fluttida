// Centralized compile-time version constants.
// These can be overridden at build time with --dart-define.
const String kAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '0.1.0',
);
const String kBuildNumber = String.fromEnvironment(
  'APP_BUILD_NUMBER',
  defaultValue: '0',
);

/// Human readable short label
const String kVersionLabel = 'v$kAppVersion (build $kBuildNumber)';

/// Build mode flag: when true, the app acts as Lab (no ads).
/// Override at build time: --dart-define=LAB_APP=false for App Store builds.
const bool kIsLabApp = bool.fromEnvironment('LAB_APP', defaultValue: true);

/// AdMob App ID (Test ID as default; override in CI for release builds)
/// Note: This constant is primarily for documentation/reference purposes.
/// The actual AdMob App ID is injected into native configuration files
/// (AndroidManifest.xml and Info.plist) during the CI build process.
/// This constant can be used in future releases if needed.
const String kAdMobAppId = String.fromEnvironment(
  'ADMOB_APP_ID',
  defaultValue: 'ca-app-pub-3940256099942544~3347511713',
);

/// AdMob Banner Unit ID for Android (Test ID as default)
const String kAdMobBannerUnitAndroid = String.fromEnvironment(
  'ADMOB_BANNER_UNIT_ANDROID',
  defaultValue: 'ca-app-pub-3940256099942544/6300978111',
);

/// AdMob Banner Unit ID for iOS (Test ID as default)
const String kAdMobBannerUnitIos = String.fromEnvironment(
  'ADMOB_BANNER_UNIT_IOS',
  defaultValue: 'ca-app-pub-3940256099942544/2934735716',
);
