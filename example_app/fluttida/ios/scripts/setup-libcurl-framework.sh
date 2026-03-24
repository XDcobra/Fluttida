#!/bin/bash
set -euo pipefail

FORCE_DOWNLOAD=false
if [ "${1:-}" = "--force" ]; then
  FORCE_DOWNLOAD=true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$IOS_DIR/.." && pwd)"
FRAMEWORKS_DIR="$IOS_DIR/Runner/Frameworks"
PIN_FILE="$PROJECT_ROOT/config/ios-libs.versions"
STAMP_FILE="$FRAMEWORKS_DIR/.framework-version-libcurl"

read_pin_value() {
  local key="$1"
  local file="$2"
  local value

  value="$(grep -E "^${key}=" "$file" | head -n1 | cut -d'=' -f2- | tr -d '\r' | xargs || true)"
  echo "$value"
}

if [ ! -f "$PIN_FILE" ]; then
  echo "Error: iOS pinning file not found: $PIN_FILE" >&2
  exit 1
fi

LIBCURL_VERSION="$(read_pin_value "libcurl_openssl_version" "$PIN_FILE")"
LIBCURL_TAG="$(read_pin_value "libcurl_ios_release_tag" "$PIN_FILE")"
LIBCURL_ZIP_ASSET="$(read_pin_value "libcurl_ios_zip_asset" "$PIN_FILE")"
LIBCURL_XCFW_NAME="$(read_pin_value "libcurl_ios_xcframework_name" "$PIN_FILE")"

if [ -z "$LIBCURL_VERSION" ] || [ -z "$LIBCURL_TAG" ] || [ -z "$LIBCURL_ZIP_ASSET" ] || [ -z "$LIBCURL_XCFW_NAME" ]; then
  echo "Error: Missing required keys in $PIN_FILE" >&2
  echo "Required: libcurl_openssl_version, libcurl_ios_release_tag, libcurl_ios_zip_asset, libcurl_ios_xcframework_name" >&2
  exit 1
fi

TARGET_XCFW_DIR="$FRAMEWORKS_DIR/libcurl.xcframework"

if [ "$FORCE_DOWNLOAD" != true ] && [ -d "$TARGET_XCFW_DIR" ] && [ -f "$STAMP_FILE" ]; then
  INSTALLED_VERSION="$(cat "$STAMP_FILE" | tr -d '\r\n' || true)"
  if [ "$INSTALLED_VERSION" = "$LIBCURL_VERSION" ]; then
    echo "libcurl iOS framework already at pinned version $LIBCURL_VERSION, skipping download."
    exit 0
  fi
fi

REPO_SLUG="${LIBCURL_IOS_REPO:-XDcobra/libcurl-ios-android-prebuilt-and-buildscripts}"
DOWNLOAD_URL="https://github.com/${REPO_SLUG}/releases/download/${LIBCURL_TAG}/${LIBCURL_ZIP_ASSET}"

mkdir -p "$FRAMEWORKS_DIR"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fluttida-libcurl-ios.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

ZIP_PATH="$TMP_DIR/$LIBCURL_ZIP_ASSET"

echo "Downloading $DOWNLOAD_URL"
curl -fL -o "$ZIP_PATH" "$DOWNLOAD_URL"

echo "Extracting $LIBCURL_ZIP_ASSET"
unzip -q -o "$ZIP_PATH" -d "$TMP_DIR/extracted"

SRC_XCFW_DIR="$TMP_DIR/extracted/$LIBCURL_XCFW_NAME"
if [ ! -d "$SRC_XCFW_DIR" ]; then
  echo "Error: Expected XCFramework '$LIBCURL_XCFW_NAME' not found in zip." >&2
  ls -la "$TMP_DIR/extracted" >&2 || true
  exit 1
fi

rm -rf "$TARGET_XCFW_DIR"
cp -R "$SRC_XCFW_DIR" "$TARGET_XCFW_DIR"

printf "%s\n" "$LIBCURL_VERSION" > "$STAMP_FILE"

echo "Installed libcurl.xcframework version $LIBCURL_VERSION"
