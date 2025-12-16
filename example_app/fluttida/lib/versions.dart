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
