#!/bin/bash
# Builds a Release .app and packages it two ways into dist/:
#   1. iOSBuildManager-<version>.dmg   — drag-to-Applications installer
#   2. iOSBuildManager-<version>.app.zip — standalone app to run directly
#
# No external tools required (uses xcodebuild + hdiutil + ditto).
# The app is ad-hoc signed (free Apple ID), so on other Macs Gatekeeper will
# ask the user to right-click → Open the first time. See README.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
PROJECT="$ROOT/iOSBuildManager/iOSBuildManager.xcodeproj"
SCHEME="iOSBuildManager"
APP_NAME="iOSBuildManager"
DERIVED="$ROOT/build/dmg-derived"
DIST="$ROOT/dist"
STAGE="$ROOT/build/dmg-stage"

# Version from the app's source of truth.
VERSION="$(sed -n 's/.*static let version: String = "\(.*\)".*/\1/p' \
  "$ROOT/iOSBuildManager/iOSBuildManager/Models/AppVersion.swift")"
VERSION="${VERSION:-0.0.0}"

echo "==> Building $APP_NAME $VERSION (Release)…"
rm -rf "$DERIVED"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$DERIVED" build >/dev/null

APP_PATH="$DERIVED/Build/Products/Release/$APP_NAME.app"
[ -d "$APP_PATH" ] || { echo "error: build produced no .app at $APP_PATH"; exit 1; }

mkdir -p "$DIST"

# --- Standalone app (run directly) ---
echo "==> Zipping standalone app…"
APP_ZIP="$DIST/$APP_NAME-$VERSION.app.zip"
rm -f "$APP_ZIP"
ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"

# --- DMG (drag-to-Applications) ---
echo "==> Building DMG…"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

DMG_PATH="$DIST/$APP_NAME-$VERSION.dmg"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG_PATH" >/dev/null

rm -rf "$STAGE"

echo ""
echo "Done:"
echo "  DMG : $DMG_PATH"
echo "  App : $APP_ZIP"
