#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

APP="dist/Quick Drop Zone.app"
ICONSET="dist/AppIcon.iconset"
ICON_OUT="dist/AppIcon-compiled"
VERIFY_DIR="dist/verify-extracted"
ZIP="dist/Quick-Drop-Zone-2.2.0.zip"

swift build -c release --product QuickDropZone
rm -rf "$APP" "$ICONSET" "$ICON_OUT" "$VERIFY_DIR" "$ZIP" "$ZIP.sha256"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" dist
cp .build/release/QuickDropZone "$APP/Contents/MacOS/QuickDropZone"
cp Resources/Info.plist "$APP/Contents/Info.plist"
swift Scripts/GenerateIcon.swift "$ICONSET" "Resources/AppIcon-1024.png"
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$ICONSET"
cp Resources/AppIcon-1024.png "$APP/Contents/Resources/AppIcon-1024.png"
python3 Scripts/test_icon_package.py "$ROOT_DIR/Resources/AppIcon-1024.png" "$ROOT_DIR/$APP"

# The macOS 26+ icon: compile the Icon Composer file (Resources/AppIcon.icon) into Assets.car.
# Without it, newer macOS versions show the classic .icns shrunk onto a grey plate in the Dock.
# actool can exit 0 even when it skips the icon, so the output is checked, not the exit code.
mkdir -p "$ICON_OUT"
xcrun actool Resources/AppIcon.icon \
    --compile "$ICON_OUT" \
    --platform macosx \
    --target-device mac \
    --minimum-deployment-target 26.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$ICON_OUT/partial.plist" \
    --output-format human-readable-text \
    --errors --warnings --notices || { echo "error: actool couldn't compile Resources/AppIcon.icon" >&2; exit 1; }
ls -l "$ICON_OUT"
if [ ! -s "$ICON_OUT/Assets.car" ]; then
    echo "error: actool didn't produce Assets.car from Resources/AppIcon.icon" >&2
    exit 1
fi
icon_name="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconName" "$ICON_OUT/partial.plist" 2>/dev/null || true)"
echo "actool partial Info.plist CFBundleIconName: ${icon_name:-<none>}"
if [ "$icon_name" != "AppIcon" ]; then
    car_info="$(xcrun assetutil --info "$ICON_OUT/Assets.car" 2>&1 || true)"
    case "$car_info" in
        *'"AppIcon"'*) echo "Assets.car lists AppIcon." ;;
        *) printf '%s\n' "$car_info" >&2; echo "error: Assets.car doesn't contain an app icon named AppIcon" >&2; exit 1 ;;
    esac
fi
# Only Assets.car is copied; the classic AppIcon.icns above stays as the fallback.
cp "$ICON_OUT/Assets.car" "$APP/Contents/Resources/Assets.car"
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
expect_plist CFBundleShortVersionString 2.2.0
expect_plist CFBundleVersion 5
expect_plist CFBundleIconFile AppIcon
expect_plist CFBundleIconName AppIcon
test -s "$APP/Contents/Resources/AppIcon.icns"
test -s "$APP/Contents/Resources/Assets.car"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

# Verify the exact ZIP intended for download, including executable mode.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
mkdir -p "$VERIFY_DIR"
ditto -x -k "$ZIP" "$VERIFY_DIR"
EXTRACTED_APP="$VERIFY_DIR/Quick Drop Zone.app"
test -x "$EXTRACTED_APP/Contents/MacOS/QuickDropZone"
python3 Scripts/test_icon_package.py "$ROOT_DIR/Resources/AppIcon-1024.png" "$ROOT_DIR/$EXTRACTED_APP"
if [ ! -s "$EXTRACTED_APP/Contents/Resources/Assets.car" ]; then
    echo "error: Assets.car (the macOS 26+ icon) is missing inside the ZIP" >&2
    exit 1
fi
expect_plist_in() {
    local actual
    actual="$(/usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist")"
    if [ "$actual" != "$3" ]; then
        echo "error: Info.plist $2 inside the ZIP is '$actual', expected '$3'" >&2
        exit 1
    fi
}
expect_plist_in "$EXTRACTED_APP" CFBundleShortVersionString 2.2.0
expect_plist_in "$EXTRACTED_APP" CFBundleIconName AppIcon
plutil -lint "$EXTRACTED_APP/Contents/Info.plist"
codesign --verify --deep --strict "$EXTRACTED_APP"
file "$EXTRACTED_APP/Contents/MacOS/QuickDropZone"
bash Scripts/write-checksum-sidecar.sh "$ZIP"
printf 'Verified package: %s\n' "$ZIP"
