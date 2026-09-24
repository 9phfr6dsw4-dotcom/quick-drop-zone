#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

APP="dist/Quick Drop Zone.app"
ICONSET="dist/AppIcon.iconset"
VERIFY_DIR="dist/verify-extracted"
ZIP="dist/Quick-Drop-Zone-1.1.1.zip"

swift build -c release --product QuickDropZone
rm -rf "$APP" "$ICONSET" "$VERIFY_DIR" "$ZIP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" dist
cp .build/release/QuickDropZone "$APP/Contents/MacOS/QuickDropZone"
cp Resources/Info.plist "$APP/Contents/Info.plist"
swift Scripts/GenerateIcon.swift "$ICONSET"
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$ICONSET"
chmod 755 "$APP/Contents/MacOS/QuickDropZone"

plutil -lint "$APP/Contents/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$APP/Contents/Info.plist")" = "true"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")" = "26.0"
test -s "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

# Verify the exact ZIP intended for download, including executable mode.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
mkdir -p "$VERIFY_DIR"
ditto -x -k "$ZIP" "$VERIFY_DIR"
EXTRACTED_APP="$VERIFY_DIR/Quick Drop Zone.app"
test -x "$EXTRACTED_APP/Contents/MacOS/QuickDropZone"
plutil -lint "$EXTRACTED_APP/Contents/Info.plist"
codesign --verify --deep --strict "$EXTRACTED_APP"
file "$EXTRACTED_APP/Contents/MacOS/QuickDropZone"
shasum -a 256 "$ZIP" > "$ZIP.sha256"
printf 'Verified package: %s\n' "$ZIP"
