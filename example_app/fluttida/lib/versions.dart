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
