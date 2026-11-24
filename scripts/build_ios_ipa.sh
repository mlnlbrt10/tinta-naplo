#!/usr/bin/env bash
# Builds an unsigned Tinta Napló .ipa package for AltStore / SideStore sideloading.
# Must be executed on macOS with Xcode & CocoaPods installed.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: iOS builds require macOS with Xcode installed." >&2
  exit 1
fi

echo "==> Checking Flutter dependencies..."
flutter pub get

echo "==> Installing CocoaPods dependencies..."
(
  cd ios
  pod install
)

echo "==> Building unsigned iOS release bundle (Runner.app)..."
flutter build ios --release --no-codesign "$@"

APP_PATH="$ROOT_DIR/build/ios/iphoneos/Runner.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: Expected Runner.app not found at $APP_PATH" >&2
  exit 1
fi

STAGING_DIR="$ROOT_DIR/build/ios/ipa_staging"
PAYLOAD_DIR="$STAGING_DIR/Payload"
OUTPUT_IPA="$ROOT_DIR/tinta-naplo-ios.ipa"

echo "==> Packaging Payload/Runner.app into $OUTPUT_IPA..."
rm -rf "$STAGING_DIR" "$OUTPUT_IPA"
mkdir -p "$PAYLOAD_DIR"
cp -R "$APP_PATH" "$PAYLOAD_DIR/Runner.app"

(
  cd "$STAGING_DIR"
  zip -qry "$OUTPUT_IPA" Payload
)

rm -rf "$STAGING_DIR"
IPA_SIZE="$(du -h "$OUTPUT_IPA" | awk '{print $1}')"
echo "==> Done! Created unsigned IPA: $OUTPUT_IPA ($IPA_SIZE)"
echo "    Install via AltStore or SideStore on your iPhone/iPad."
