#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

APP="dist/Quick Drop Zone.app"
ICONSET="dist/AppIcon.iconset"
VERIFY_DIR="dist/verify-extracted"
ZIP="dist/Quick-Drop-Zone-2.1.0.zip"

swift build -c release --product QuickDropZone
rm -rf "$APP" "$ICONSET" "$VERIFY_DIR" "$ZIP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" dist
cp .build/release/QuickDropZone "$APP/Contents/MacOS/QuickDropZone"
cp Resources/Info.plist "$APP/Contents/Info.plist"
swift Scripts/GenerateIcon.swift "$ICONSET" "Resources/AppIcon-1024.png"
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$ICONSET"
cp Resources/AppIcon-1024.png "$APP/Contents/Resources/AppIcon-1024.png"
python3 Scripts/test_icon_package.py "$ROOT_DIR/Resources/AppIcon-1024.png" "$ROOT_DIR/$APP"
chmod 755 "$APP/Contents/MacOS/QuickDropZone"

# Each check names the key that doesn't match, so a failure is never silent.
expect_plist() {
    local actual
    actual="$(/usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist")"
    if [ "$actual" != "$2" ]; then
        echo "error: Info.plist $1 is '$actual', expected '$2'" >&2
        exit 1
    fi
}

plutil -lint "$APP/Contents/Info.plist"
expect_plist LSUIElement true
expect_plist LSMinimumSystemVersion 26.0
expect_plist CFBundleShortVersionString 2.1.0
expect_plist CFBundleVersion 4
test -s "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

# Verify the exact ZIP intended for download, including executable mode.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
mkdir -p "$VERIFY_DIR"
ditto -x -k "$ZIP" "$VERIFY_DIR"
EXTRACTED_APP="$VERIFY_DIR/Quick Drop Zone.app"
test -x "$EXTRACTED_APP/Contents/MacOS/QuickDropZone"
python3 Scripts/test_icon_package.py "$ROOT_DIR/Resources/AppIcon-1024.png" "$ROOT_DIR/$EXTRACTED_APP"
plutil -lint "$EXTRACTED_APP/Contents/Info.plist"
codesign --verify --deep --strict "$EXTRACTED_APP"
file "$EXTRACTED_APP/Contents/MacOS/QuickDropZone"
bash Scripts/write-checksum-sidecar.sh "$ZIP"
printf 'Verified package: %s\n' "$ZIP"
