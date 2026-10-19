#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

APP="dist/Quick Drop Zone.app"
ICONSET="dist/AppIcon.iconset"
ICON_OUT="dist/AppIcon-compiled"
VERIFY_DIR="dist/verify-extracted"
ZIP="dist/Quick-Drop-Zone-2.5.0.zip"
SIGNING_REPORT="dist/signing.txt"
SIGN_MODE="${SIGN_MODE:-adhoc}"
export SIGN_MODE

swift build -c release --product QuickDropZone
rm -rf "$APP" "$ICONSET" "$ICON_OUT" "$VERIFY_DIR" "$ZIP" "$ZIP.sha256" "$SIGNING_REPORT" "dist/notarize"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" dist
cp .build/release/QuickDropZone "$APP/Contents/MacOS/QuickDropZone"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Acknowledgements.txt "$APP/Contents/Resources/Acknowledgements.txt"

# Sparkle comes from the exact version SwiftPM resolved and checksummed.
SPARKLE_FRAMEWORKS=()
while IFS= read -r framework; do
    SPARKLE_FRAMEWORKS+=("$framework")
done < <(find .build/artifacts -type d -path '*/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework' -prune)
if [[ "${#SPARKLE_FRAMEWORKS[@]}" -ne 1 ]]; then
    printf 'Expected one Sparkle.framework in .build/artifacts, found %s.\n' "${#SPARKLE_FRAMEWORKS[@]}" >&2
    exit 1
fi
ditto "${SPARKLE_FRAMEWORKS[0]}" "$APP/Contents/Frameworks/Sparkle.framework"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Frameworks/Sparkle.framework/Resources/Info.plist" | grep -Fx '2.10.0'
test -x "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
test -x "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater"
otool -L "$APP/Contents/MacOS/QuickDropZone" | grep -F '@rpath/Sparkle.framework/Versions/B/Sparkle'
otool -l "$APP/Contents/MacOS/QuickDropZone" | grep -F 'path @executable_path/../Frameworks'
grep -F 'Sparkle 2.10.0' "$APP/Contents/Resources/Acknowledgements.txt"

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
expect_plist CFBundleShortVersionString 2.5.0
expect_plist CFBundleVersion 9
expect_plist CFBundleIconFile AppIcon
expect_plist CFBundleIconName AppIcon
expect_plist SUFeedURL "https://github.com/9phfr6dsw4-dotcom/quick-drop-zone/releases/latest/download/appcast.xml"
test -s "$APP/Contents/Resources/AppIcon.icns"
test -s "$APP/Contents/Resources/Assets.car"

# Signing is the last change to the app; everything after only zips, checks and hashes it.
bash Scripts/sign-app.sh "$APP"

NOTARIZED="no"
if [[ "$SIGN_MODE" == "developer-id" ]]; then
    bash Scripts/notarize.sh "$APP"
    NOTARIZED="yes"
fi

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
test -x "$EXTRACTED_APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
test -L "$EXTRACTED_APP/Contents/Frameworks/Sparkle.framework/Versions/Current"
expect_plist_in() {
    local actual
    actual="$(/usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist")"
    if [ "$actual" != "$3" ]; then
        echo "error: Info.plist $2 inside the ZIP is '$actual', expected '$3'" >&2
        exit 1
    fi
}
expect_plist_in "$EXTRACTED_APP" CFBundleShortVersionString 2.5.0
expect_plist_in "$EXTRACTED_APP" CFBundleVersion 9
expect_plist_in "$EXTRACTED_APP" CFBundleIconName AppIcon
expect_plist_in "$EXTRACTED_APP" SUFeedURL "https://github.com/9phfr6dsw4-dotcom/quick-drop-zone/releases/latest/download/appcast.xml"
plutil -lint "$EXTRACTED_APP/Contents/Info.plist"
codesign --verify --deep --strict "$EXTRACTED_APP"
if [[ "$NOTARIZED" == "yes" ]]; then
    xcrun stapler validate "$EXTRACTED_APP"
    spctl --assess --type execute --verbose=2 "$EXTRACTED_APP"
fi
file "$EXTRACTED_APP/Contents/MacOS/QuickDropZone"
bash Scripts/write-checksum-sidecar.sh "$ZIP"
{
    printf 'mode=%s\n' "$SIGN_MODE"
    printf 'notarized=%s\n' "$NOTARIZED"
    codesign --display --requirements - "$EXTRACTED_APP" 2>/dev/null | sed -n 's/^designated => /requirement=/p'
} > "$SIGNING_REPORT"
cat "$SIGNING_REPORT"
printf 'Verified package: %s\n' "$ZIP"
