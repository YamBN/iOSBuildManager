#!/bin/bash
# Builds a Release .app and packages it two ways into dist/:
#   1. iOSBuildManager-<version>.dmg     — branded drag-to-Applications installer
#   2. iOSBuildManager-<version>.app.zip — standalone app to run directly
#
# The DMG's background/icon layout is built with dmgbuild (pure Python), which
# writes the .DS_Store bytes directly instead of driving Finder's GUI via
# osascript. That matters: live Finder automation was found to intermittently
# drop the background/icon-position metadata depending on Finder's cached
# per-volume window state — fine interactively, not something to ship in an
# automated release. dmgbuild is deterministic and works headless (CI).
#
# The app is ad-hoc signed (free Apple ID), so on other Macs Gatekeeper will
# ask the user to right-click → Open the first time. See README.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
PROJECT="$ROOT/iOSBuildManager/iOSBuildManager.xcodeproj"
SCHEME="iOSBuildManager"
APP_NAME="iOSBuildManager"
VOL_NAME="iOS Build Manager"
DERIVED="$ROOT/build/dmg-derived"
DIST="$ROOT/dist"
VENV="$ROOT/build/.dmgbuild-venv"

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

# --- dmgbuild (isolated venv so this doesn't touch system/Homebrew Python) ---
if [ ! -x "$VENV/bin/dmgbuild" ]; then
  echo "==> Setting up dmgbuild…"
  rm -rf "$VENV"
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet dmgbuild
fi

# --- Background image for the DMG window ---
echo "==> Rendering DMG background…"
BACKGROUND="$ROOT/build/dmg-background.png"
APP_ICON="$ROOT/iOSBuildManager/iOSBuildManager/Resources/Assets.xcassets/AppIcon.appiconset/icon_256.png"
swift "$ROOT/scripts/render_dmg_background.swift" "$BACKGROUND" "$APP_ICON" >/dev/null

# --- Build the DMG ---
echo "==> Building DMG…"
DMG_PATH="$DIST/$APP_NAME-$VERSION.dmg"
VOLICON="$APP_PATH/Contents/Resources/AppIcon.icns"
rm -f "$DMG_PATH"
"$VENV/bin/dmgbuild" \
  -s "$ROOT/scripts/dmg_settings.py" \
  -D app="$APP_PATH" \
  -D background="$BACKGROUND" \
  -D volicon="$VOLICON" \
  "$VOL_NAME" "$DMG_PATH" >/dev/null

echo ""
echo "Done:"
echo "  DMG : $DMG_PATH"
echo "  App : $APP_ZIP"
