#!/usr/bin/env bash
# Checks that Levant can put a skin's icon on itself in Finder and take it off again, using the
# app's own code (--show-finder-icon), and that the app still launches with the icon on.
# Works on a copy of the built app, so dist/ is left as it was.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="$ROOT_DIR/dist/Levant.app"
DOMAIN="com.echoapps.levant"
SHOWN_KEY="QuickDropZone.appearance.finderIconShown.v1"

test -d "$SOURCE_APP"
WORK_DIR="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/levant-icon.XXXXXX")"
APP="$WORK_DIR/Levant.app"
BINARY="$APP/Contents/MacOS/Levant"
ICON_FILE="$APP/Icon"$'\r'
cleanup() {
    pkill -x Levant >/dev/null 2>&1 || true
    defaults delete "$DOMAIN" "$SHOWN_KEY" >/dev/null 2>&1 || true
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT
ditto "$SOURCE_APP" "$APP"
rm -f "$ICON_FILE"
xattr -d com.apple.FinderInfo "$APP" >/dev/null 2>&1 || true

has_custom_icon() {
    [[ -f "$ICON_FILE" ]]
}

expect_no_custom_icon() {
    if has_custom_icon; then
        echo "The app still has a custom icon." >&2
        exit 1
    fi
}

echo "1. The app's own icon: no custom icon."
expect_no_custom_icon

echo "2. Sky: the app puts its icon on itself."
"$BINARY" --show-finder-icon sky
has_custom_icon
test "$(defaults read "$DOMAIN" "$SHOWN_KEY")" = "sky"

echo "3. Bordeaux replaces it."
"$BINARY" --show-finder-icon bordeaux
has_custom_icon
test "$(defaults read "$DOMAIN" "$SHOWN_KEY")" = "bordeaux"

echo "4. The app still launches with the custom icon on."
pkill -x Levant >/dev/null 2>&1 || true
open -n -g "$APP"
STARTED=""
for _ in {1..20}; do
    if pgrep -x Levant >/dev/null 2>&1; then STARTED="yes"; break; fi
    sleep 0.5
done
if [[ -z "$STARTED" ]]; then
    echo "Levant did not start from Launch Services with the icon on." >&2
    exit 1
fi
sleep 2
pgrep -x Levant >/dev/null || { echo "Levant quit right after starting with the icon on." >&2; exit 1; }
pkill -x Levant
for _ in {1..20}; do
    if ! pgrep -x Levant >/dev/null 2>&1; then break; fi
    sleep 0.5
done
echo "   It starts from Launch Services and keeps running."
codesign --verify --deep --strict "$APP" 2>&1 | sed 's/^/   codesign with the icon: /' || true
CLEAN="$WORK_DIR/clean/Levant.app"
mkdir -p "$WORK_DIR/clean"
ditto "$APP" "$CLEAN"
rm -f "$CLEAN/Icon"$'\r'
xattr -c "$CLEAN"
codesign --verify --deep --strict "$CLEAN"
echo "   Everything the signature covers is unchanged."

echo "5. Back to the app's own icon."
"$BINARY" --show-finder-icon none
expect_no_custom_icon
if defaults read "$DOMAIN" "$SHOWN_KEY" >/dev/null 2>&1; then
    echo "The shown-icon marker should be gone." >&2
    exit 1
fi

if "$BINARY" --show-finder-icon retired-skin 2>/dev/null; then
    echo "An unknown skin should be refused." >&2
    exit 1
fi
echo "Finder icon test passed."
