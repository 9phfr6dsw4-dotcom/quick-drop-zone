#!/usr/bin/env bash
set -euo pipefail
unset GH_TOKEN GITHUB_TOKEN
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
[[ "$RUNNER_TEMP" == /* ]] || { printf 'RUNNER_TEMP must be an absolute path.\n' >&2; exit 2; }
[[ ! -L "${BASH_SOURCE[0]}" ]] || { printf 'Refusing to run through a symlinked capture script.\n' >&2; exit 2; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
cd "$ROOT"
APP_KEY="${APP_KEY:?APP_KEY is required}"
source "$ROOT/.github/scripts/readme-media-runtime.sh"

case "$APP_KEY" in
  clipboard-shelf)
    RELEASE_REPO='9phfr6dsw4-dotcom/clipboard-shelf'
    APP_BUNDLE='Clipboard Shelf.app'; WINDOW_OWNER='ClipboardShelf'; APP_NAME='Clipboard Shelf'
    TAGLINE='A quiet macOS menu-bar clipboard history with search, pins, and a pause switch.'
    MENU_APP=1
    ;;
  quick-drop-zone)
    RELEASE_REPO='9phfr6dsw4-dotcom/quick-drop-zone'
    APP_BUNDLE='Quick Drop Zone.app'; WINDOW_OWNER='QuickDropZone'; APP_NAME='Quick Drop Zone'
    TAGLINE='A careful, local-first file organizer in the macOS menu bar.'
    MENU_APP=1
    ;;
  echotype)
    RELEASE_REPO='9phfr6dsw4-dotcom/echotype'
    APP_BUNDLE='EchoType.app'; WINDOW_OWNER='EchoType'; APP_NAME='EchoType'
    TAGLINE='Private, on-device dictation for macOS with Apple Speech, Parakeet v3, and Whisper.'
    MENU_APP=0
    ;;
  captiongrab)
    RELEASE_REPO='9phfr6dsw4-dotcom/captiongrab'
    APP_BUNDLE='CaptionGrab.app'; WINDOW_OWNER='CaptionGrab'; APP_NAME='CaptionGrab'
    TAGLINE='Get English YouTube captions and save them as Markdown or Word.'
    MENU_APP=0
    ;;
  *) printf 'Unknown APP_KEY: %s' "$APP_KEY" >&2; exit 2 ;;
esac

require_trusted_main_dispatch "$RELEASE_REPO"

STATUS_LABEL="$APP_NAME"

case "$APP_KEY" in
  clipboard-shelf) SLUG='clipboard-shelf' ;;
  quick-drop-zone) SLUG='quick-drop-zone' ;;
  echotype) SLUG='echotype' ;;
  captiongrab) SLUG='captiongrab' ;;
esac

HELPER="$ROOT/.github/scripts/render-readme-media.swift"
ARTIFACT_DIR="$RUNNER_TEMP/readme-media"
EXTRACT_DIR="$RUNNER_TEMP/release-app"
RELEASE_DOWNLOAD_DIR="$RUNNER_TEMP/release-download"
FIXTURE_DOWNLOADS="$RUNNER_TEMP/quick-drop-zone-demo/Downloads"
python3 "$ROOT/.github/scripts/prepare-readme-media-workspace.py" "$ROOT" "$RUNNER_TEMP" "$APP_KEY" --validate-only
python3 "$ROOT/.github/scripts/prepare-readme-media-artifacts.py" "$RUNNER_TEMP" "$ARTIFACT_DIR"

rm -f "$ROOT/docs/images/$SLUG-light.png" "$ROOT/docs/images/$SLUG-dark.png" "$ROOT/docs/images/$SLUG-hero.gif" "$ROOT/docs/images/social-preview.png"

printf '%s\n' '=== Display configuration ==='
system_profiler SPDisplaysDataType 2>&1 | tee "$ARTIFACT_DIR/display-info.txt"
swift "$HELPER" display-info | tee -a "$ARTIFACT_DIR/display-info.txt"
echo '=== Preparing a clean synthetic-demo desktop ==='
swift "$HELPER" wallpaper "$RUNNER_TEMP/readme-wallpaper.png"
osascript -e "tell application \"System Events\" to tell every desktop to set picture to \"$RUNNER_TEMP/readme-wallpaper.png\"" || printf '%s\n' 'Wallpaper AppleScript was unavailable.'
defaults write com.apple.finder CreateDesktop false || true
killall Finder >/dev/null 2>&1 || true
osascript -e 'tell application "Finder" to close every window' >/dev/null 2>&1 || true
osascript -e 'tell application "Terminal" to close every window' >/dev/null 2>&1 || true

printf 'Using the already-downloaded release from %s.\n' "$RELEASE_REPO"
if [[ "$APP_KEY" == quick-drop-zone ]]; then
  ZIP_PATH="$RELEASE_DOWNLOAD_DIR/Quick-Drop-Zone-1.2.1.zip"
  python3 "$ROOT/.github/scripts/verify-readme-media-release.py" "$RELEASE_DOWNLOAD_DIR"
else
  ZIP_PATH="$(python3 - "$RELEASE_DOWNLOAD_DIR" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
if root.is_symlink() or not root.is_dir() or root.resolve(strict=True) != root:
    raise SystemExit('Release download path is missing or symlinked')
files = sorted(root.glob('*.zip'))
if len(files) != 1:
    raise SystemExit(f'Expected one ZIP asset from the latest release; found {len(files)}')
if files[0].is_symlink() or not files[0].is_file() or files[0].resolve(strict=True).parent != root:
    raise SystemExit('Release ZIP must be a regular file directly inside the validated download directory')
print(files[0])
PY
  )"
fi
ditto -x -k "$ZIP_PATH" "$EXTRACT_DIR"
APP="$EXTRACT_DIR/$APP_BUNDLE"
[[ ! -L "$APP" && -d "$APP" ]]
if [[ "$APP_KEY" == quick-drop-zone ]]; then
  bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
  bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
  [[ "$bundle_identifier" == com.quickdropzone.app ]] || { printf 'Unexpected Quick Drop Zone bundle identifier: %s' "$bundle_identifier" >&2; exit 1; }
  [[ "$bundle_version" == 1.2.1 ]] || { printf 'Unexpected Quick Drop Zone bundle version: %s' "$bundle_version" >&2; exit 1; }
  codesign --verify --deep --strict "$APP"
fi
xattr -dr com.apple.quarantine "$APP" >/dev/null 2>&1 || true
ICON="$ROOT/docs/images/$SLUG-icon.png"
test -s "$ICON"

show_menu_popover() {
  if menu_geometry >/dev/null 2>&1; then return 0; fi
  osascript - "$WINDOW_OWNER" "$STATUS_LABEL" <<'APPLESCRIPT' || return 1
on run argv
  set appName to item 1 of argv
  set statusLabel to item 2 of argv
  tell application "System Events"
    tell process appName
      set frontmost to true
      set statusItem to missing value
      set matches to 0
      try
        repeat with candidate in every menu bar item of menu bar 2
          set itemName to ""
          set itemDescription to ""
          try
            set itemName to name of candidate as text
          end try
          try
            set itemDescription to description of candidate as text
          end try
          if itemDescription is statusLabel then
            set statusItem to candidate
            set matches to matches + 1
          end if
        end repeat
      end try
      if matches is 0 then
        try
          repeat with candidate in every menu bar item of menu bar 1
            set itemName to ""
            set itemDescription to ""
            try
              set itemName to name of candidate as text
            end try
            try
              set itemDescription to description of candidate as text
            end try
            if itemDescription is statusLabel then
              set statusItem to candidate
              set matches to matches + 1
            end if
          end repeat
        end try
      end if
      if matches is not 1 then error "Could not uniquely identify this app's menu-bar status item."
      click statusItem
    end tell
  end tell
end run
APPLESCRIPT
  local attempt
  for attempt in {1..12}; do
    if menu_geometry >/dev/null 2>&1; then return 0; fi
    sleep 0.25
  done
  printf 'The app popover did not appear adjacent to its identified status item.\n' >&2
  return 1
}

menu_geometry() {
  osascript - "$WINDOW_OWNER" "$STATUS_LABEL" <<'APPLESCRIPT'
on run argv
  set appName to item 1 of argv
  set statusLabel to item 2 of argv
  tell application "System Events"
    tell process appName
      set statusItem to missing value
      set matches to 0
      try
        repeat with candidate in every menu bar item of menu bar 2
          set itemName to ""
          set itemDescription to ""
          try
            set itemName to name of candidate as text
          end try
          try
            set itemDescription to description of candidate as text
          end try
          if itemDescription is statusLabel then
            set statusItem to candidate
            set matches to matches + 1
          end if
        end repeat
      end try
      if matches is 0 then
        try
          repeat with candidate in every menu bar item of menu bar 1
            set itemName to ""
            set itemDescription to ""
            try
              set itemName to name of candidate as text
            end try
            try
              set itemDescription to description of candidate as text
            end try
            if itemDescription is statusLabel then
              set statusItem to candidate
              set matches to matches + 1
            end if
          end repeat
        end try
      end if
      if matches is not 1 then error "Could not uniquely identify this app's menu-bar status item."
      set statusPosition to position of statusItem
      set statusSize to size of statusItem
      set statusLeft to item 1 of statusPosition as integer
      set statusTop to item 2 of statusPosition as integer
      set statusRight to statusLeft + (item 1 of statusSize as integer)
      set statusBottom to statusTop + (item 2 of statusSize as integer)
      set matchingWindows to 0
      set windowPosition to {0, 0}
      set windowSize to {0, 0}
      repeat with candidateWindow in every window
        try
          if visible of candidateWindow then
            set candidatePosition to position of candidateWindow
            set candidateSize to size of candidateWindow
            set candidateLeft to item 1 of candidatePosition as integer
            set candidateTop to item 2 of candidatePosition as integer
            set candidateWidth to item 1 of candidateSize as integer
            set candidateHeight to item 2 of candidateSize as integer
            set verticalGap to candidateTop - statusBottom
            set overlapsStatusItem to (candidateLeft < statusRight + 80) and (candidateLeft + candidateWidth > statusLeft - 80)
            if overlapsStatusItem and verticalGap >= -8 and verticalGap <= 120 and candidateWidth >= 240 and candidateHeight >= 240 then
              set matchingWindows to matchingWindows + 1
              set windowPosition to candidatePosition
              set windowSize to candidateSize
            end if
          end if
        end try
      end repeat
      if matchingWindows is not 1 then error "Could not uniquely identify a visible popover adjacent to the app status item."
    end tell
  end tell
  set fields to {item 1 of windowPosition, item 2 of windowPosition, item 1 of windowSize, item 2 of windowSize, item 1 of statusPosition, item 2 of statusPosition, item 1 of statusSize, item 2 of statusSize, 0}
  set output to ""
  repeat with fieldValue in fields
    if output is not "" then set output to output & "|"
    set output to output & (((fieldValue as integer) as text))
  end repeat
  return output
end run
APPLESCRIPT
}

window_info() {
  swift "$HELPER" window "$WINDOW_OWNER"
}

capture_app_window() {
  local output="$1"
  local info id x y width height scale
  rm -f "$output"
  info="$(window_info)"
  IFS='|' read -r id x y width height scale <<< "$info"
  [[ "$id" =~ ^[0-9]+$ && "$width" =~ ^[0-9]+$ && "$height" =~ ^[0-9]+$ ]]
  (( width >= 500 && height >= 400 ))
  printf 'Window %s bounds: id=%s x=%s y=%s width=%s height=%s backing-scale=%s\n' "$WINDOW_OWNER" "$id" "$x" "$y" "$width" "$height" "$scale"
  screencapture -x -l "$id" "$output"
  test -s "$output"
}

fit_app_window() {
  local max_width="$1" max_height="$2" info frame screen_width screen_height width height
  info="$(swift "$HELPER" display-info)"
  IFS='|' read -r frame _ _ <<< "$info"
  frame="${frame#frame=}"
  screen_width="${frame%x*}"
  screen_height="${frame#*x}"
  [[ "$screen_width" =~ ^[0-9]+$ && "$screen_height" =~ ^[0-9]+$ ]] || return 1
  width=$(( screen_width - 80 ))
  height=$(( screen_height - 100 ))
  (( width > max_width )) && width="$max_width"
  (( height > max_height )) && height="$max_height"
  (( width >= 680 && height >= 520 )) || return 1
  osascript - "$WINDOW_OWNER" "$width" "$height" <<'APPLESCRIPT'
on run argv
  set appName to item 1 of argv
  set windowWidth to item 2 of argv as integer
  set windowHeight to item 3 of argv as integer
  tell application "System Events"
    tell process appName
      set frontmost to true
      set size of window 1 to {windowWidth, windowHeight}
      set position of window 1 to {40, 40}
    end tell
  end tell
end run
APPLESCRIPT
  printf 'Fitted %s to %sx%s within a %sx%s display.\n' "$WINDOW_OWNER" "$width" "$height" "$screen_width" "$screen_height"
}

capture_menu_region() {
  local output="$1"
  local info display_info region
  local stem="${output##*/}"
  stem="${stem%.png}"
  rm -f "$output"
  if ! info="$(menu_geometry 2>"$ARTIFACT_DIR/$stem-menu-geometry-error.txt")"; then
    printf 'Could not read menu-bar and popover bounds for %s; capture failed.\n' "$WINDOW_OWNER" | tee "$ARTIFACT_DIR/$stem-capture-status.txt"
    return 1
  fi
  display_info="$(swift "$HELPER" display-info)"
  if ! region="$(menu_capture_region "$info" "$display_info")"; then
    printf 'Invalid, absent, or too-small menu capture geometry for %s; refusing capture. geometry=%s display=%s\n' \
      "$WINDOW_OWNER" "$info" "$display_info" | tee "$ARTIFACT_DIR/$stem-capture-status.txt" >&2
    return 1
  fi
  LAST_MENU_REGION="$region"
  printf 'Verified menu-bar/popover geometry for %s; native display %s; capture region %s\n' \
    "$WINDOW_OWNER" "$display_info" "$LAST_MENU_REGION"
  screencapture -x -R "$region" "$output"
  test -s "$output"
}

prepare_clipboard_demo() {
  swift "$HELPER" seed-clipboard
}

prepare_quick_drop_demo() {
  python3 "$ROOT/.github/scripts/prepare-quick-drop-zone-fixtures.py" "$RUNNER_TEMP" "$RUNNER_TEMP/readme-wallpaper.png"
  for demo_file in \
    "$FIXTURE_DOWNLOADS/Atlas-project-brief.pdf" \
    "$FIXTURE_DOWNLOADS/Atlas-review-notes.md" \
    "$FIXTURE_DOWNLOADS/Atlas-timeline.xlsx" \
    "$FIXTURE_DOWNLOADS/Atlas-copy-draft.docx"; do
    [[ -s "$demo_file" ]] || { printf 'Atlas demo content is absent or empty: %s\n' "$demo_file" >&2; return 1; }
  done
}

select_fixture_cleanup_folder() {
  osascript - "$FIXTURE_DOWNLOADS" <<'APPLESCRIPT'
on run argv
  set fixturePath to item 1 of argv
  tell application "System Events"
    tell process "QuickDropZone"
      set frontmost to true
      click button "Choose cleanup folder" of window 1
      delay 0.25
      try
        click menu item "Choose Folder…" of menu 1 of button "Choose cleanup folder" of window 1
      on error
        click menu item "Choose Folder..." of menu 1 of button "Choose cleanup folder" of window 1
      end try
      delay 0.5
      keystroke "g" using {command down, shift down}
      delay 0.25
      keystroke fixturePath
      key code 36
      delay 0.5
      key code 36
      delay 1
    end tell
  end tell
end run
APPLESCRIPT
}

open_cleanup_review() {
  osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "QuickDropZone"
    set frontmost to true
    set reviewOpen to false
    try
      set reviewOpen to (exists button "Approve & Move" of window 1)
    on error
      set reviewOpen to false
    end try
    if not reviewOpen then
      try
        click button "Clean up…" of window 1
      on error
        click button "Clean up..." of window 1
      end try
    end if
    delay 2
    if not (exists button "Approve & Move" of window 1) then error "Cleanup review did not open."
  end tell
end tell
APPLESCRIPT
  select_fixture_cleanup_folder
  osascript - "$FIXTURE_DOWNLOADS" <<'APPLESCRIPT'
on run argv
  set fixturePath to item 1 of argv
  tell application "System Events"
    tell process "QuickDropZone"
      set frontmost to true
      delay 1
      set visibleContent to ""
      repeat with itemText in every static text of window 1
        try
          set visibleContent to visibleContent & " " & (value of itemText as text)
        end try
      end repeat
      if visibleContent does not contain fixturePath then error "Cleanup review is not scoped to the RUNNER_TEMP fixture folder."
      if visibleContent does not contain "Atlas-project-brief.pdf" then error "Atlas project brief is not visible in Cleanup review."
      if visibleContent does not contain "Atlas-review-notes.md" then error "Atlas review notes are not visible in Cleanup review."
      if visibleContent does not contain "Atlas-timeline.xlsx" then error "Atlas timeline is not visible in Cleanup review."
      if visibleContent does not contain "Atlas-copy-draft.docx" then error "Atlas copy draft is not visible in Cleanup review."
      set groupToggles to every checkbox of window 1 whose name contains "Atlas" and name contains "Include group"
      if (count of groupToggles) is not 1 then error "Expected exactly one Atlas Include group checkbox."
      set groupToggle to item 1 of groupToggles
      if (value of groupToggle as text) is not "1" then click groupToggle
      delay 1
      if (value of groupToggle as text) is not "1" then error "Atlas group selection did not register."
      set fourSelected to false
      repeat with itemText in every static text of window 1
        try
          if (value of itemText as text) is "4 selected" then set fourSelected to true
        end try
      end repeat
      if not fourSelected then error "Refusing the synthetic move unless exactly the four Atlas fixture files are selected."
    end tell
  end tell
end run
APPLESCRIPT
}

caption_transcript_loaded() {
  osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "CaptionGrab"
    set foundTranscriptURL to false
    repeat with itemText in every static text of window 1
      try
        if (value of itemText as text) starts with "YouTube Video url:" then set foundTranscriptURL to true
      end try
    end repeat
    if not foundTranscriptURL then error "No transcript-only video URL is visible."
  end tell
end tell
APPLESCRIPT
}

case "$APP_KEY" in
  clipboard-shelf)
    prepare_clipboard_demo
    open "$APP"
    sleep 5
    set_appearance false
    show_menu_popover
    capture_menu_region "$ROOT/docs/images/clipboard-shelf-light.png"
    set_appearance true
    sleep 2
    capture_menu_region "$ROOT/docs/images/clipboard-shelf-dark.png"
    set_appearance false
    show_menu_popover
    capture_video_region "$LAST_MENU_REGION"
    ;;
  quick-drop-zone)
    prepare_quick_drop_demo
    open "$APP"
    sleep 5
    set_appearance false
    show_menu_popover
    open_cleanup_review
    capture_menu_region "$ROOT/docs/images/quick-drop-zone-light.png"
    set_appearance true
    sleep 2
    show_menu_popover
    open_cleanup_review
    capture_menu_region "$ROOT/docs/images/quick-drop-zone-dark.png"
    set_appearance false
    show_menu_popover
    open_cleanup_review
    capture_video_region "$LAST_MENU_REGION"
    ;;
  echotype)
    swift "$HELPER" seed-echotype
    defaults write com.echotype.app EchoType.hasSeenLaunchAtLoginOption -bool true
    open "$APP"
    sleep 8
    fit_app_window 1100 950
    set_appearance false
    capture_app_window "$ROOT/docs/images/echotype-light.png"
    osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "EchoType"
    click radio button "Speech Models" of tab group 1 of window 1
  end tell
end tell
APPLESCRIPT
    sleep 3
    capture_app_window "$ROOT/docs/images/echotype-model-library-light.png"
    set_appearance true
    osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "EchoType"
    click radio button "Home" of tab group 1 of window 1
  end tell
end tell
APPLESCRIPT
    sleep 2
    capture_app_window "$ROOT/docs/images/echotype-dark.png"
    set_appearance false
    ;;
  captiongrab)
    open "$APP"
    sleep 6
    fit_app_window 1100 950
    if [[ "${ALLOW_LIVE_YOUTUBE_FETCH:-false}" != "true" ]]; then
      printf '%s\n' 'YouTube was already tried once and returned no transcript; not repeating the live request. No CaptionGrab screenshots or social preview will be emitted.' | tee "$ARTIFACT_DIR/captiongrab-live-fetch-status.txt"
    else
      osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "CaptionGrab"
    set frontmost to true
    set value of text field 1 of window 1 to "https://www.youtube.com/watch?v=aqz-KE-bpKQ"
    click button "Get transcript" of window 1
  end tell
end tell
APPLESCRIPT
      sleep 18
      if caption_transcript_loaded; then
        set_appearance false
        capture_app_window "$ROOT/docs/images/captiongrab-light.png"
        set_appearance true
        capture_app_window "$ROOT/docs/images/captiongrab-dark.png"
        set_appearance false
      else
        printf '%s\n' 'Live fetch produced no transcript-only URL; empty-state image and social preview omitted.' | tee "$ARTIFACT_DIR/captiongrab-live-fetch-status.txt"
      fi
    fi
    ;;
esac

if [[ -s "$ROOT/docs/images/$SLUG-light.png" ]]; then
  swift "$HELPER" social "$ROOT/docs/images/social-preview.png" "$ICON" "$APP_NAME" "$TAGLINE" "$ROOT/docs/images/$SLUG-light.png"
  cp "$ROOT/docs/images/social-preview.png" "$ARTIFACT_DIR/social-preview.png"
else
  printf 'Social preview omitted because there is no qualifying real app screenshot.\n' | tee "$ARTIFACT_DIR/social-preview-status.txt"
fi
for image in "$ROOT/docs/images/$SLUG-light.png" "$ROOT/docs/images/$SLUG-dark.png" "$ROOT/docs/images/$SLUG-hero.gif" "$ROOT/docs/images/social-preview.png"; do
  [[ ! -e "$image" ]] || cp "$image" "$ARTIFACT_DIR/"
done
printf 'Capture candidates are in docs/images and artifacts in %s\n' "$ARTIFACT_DIR"
