#!/bin/bash
# package-ipa.sh — sample helper script for Xcode Run Script integration.
#
# Packages a built .app into an .ipa (Payload/AppName.app -> zip) and copies it
# into iCloud Builds so it can be installed later via SideStore / AltStore /
# Sideloadly. Also refreshes latest.ipa.
#
# This is the same script that iOS Build Manager installs at runtime into:
#   ~/Library/Application Support/iOSBuildManager/package-ipa.sh
#
# Usage:
#   ./package-ipa.sh <path-to-built.app> [app-name] [version] [build-number]
#
# When invoked from an Xcode Run Script Build Phase, the build phase passes:
#   "$BUILT_PRODUCTS_DIR/$FULL_PRODUCT_NAME" "$PRODUCT_NAME" \
#   "$MARKETING_VERSION" "$CURRENT_PROJECT_VERSION"
set -euo pipefail

APP_PATH="${1:?usage: package-ipa.sh <app-path> [name] [version] [build]}"
APP_NAME="${2:-$(basename "$APP_PATH" .app)}"
VERSION="${3:-0.0.0}"
BUILD="${4:-0}"

OUTPUT_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/iOS Builds"
mkdir -p "$OUTPUT_DIR"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/Payload"
cp -R "$APP_PATH" "$TMP/Payload/${APP_NAME}.app"

SAFE_NAME="$(echo "$APP_NAME" | tr ' ' '_')"
IPA="$OUTPUT_DIR/${SAFE_NAME}-${VERSION}-${BUILD}.ipa"
rm -f "$IPA"
( cd "$TMP" && zip -rXq "$IPA" Payload )

# Always refresh latest.ipa for SideStore / AltStore / Sideloadly.
cp -f "$IPA" "$OUTPUT_DIR/latest.ipa"

echo "IPA created: $IPA"
echo "latest.ipa updated at: $OUTPUT_DIR/latest.ipa"
