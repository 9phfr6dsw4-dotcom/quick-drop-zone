#!/usr/bin/env bash
# Captures Quick Drop Zone README media on a manually dispatched runner. It must leave the
# host as it found it: no wallpaper, Finder, Terminal, or other-app changes; demo files
# stay under RUNNER_TEMP; and every exit quits the launched app and restores its
# preferences and the system appearance.
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

finish_capture() {
  local exit_status="$?"
  trap - EXIT
  if ! stop_launched_app; then
    exit_status=1
  fi
  if ! restore_app_preferences; then
    exit_status=1
  fi
  if ! restore_appearance; then
    exit_status=1
  fi
  exit "$exit_status"
}
trap finish_capture EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

case "$APP_KEY" in
  quick-drop-zone)
    RELEASE_REPO='9phfr6dsw4-dotcom/quick-drop-zone'
    APP_BUNDLE='Quick Drop Zone.app'; APP_BUNDLE_ID='com.quickdropzone.app'
    WINDOW_OWNER='QuickDropZone'; APP_NAME='Quick Drop Zone'
    TAGLINE='A careful, local-first file organizer in the macOS menu bar.'
    SLUG='quick-drop-zone'
    ;;
  *) printf 'Unknown APP_KEY: %s. This helper captures only Quick Drop Zone.\n' "$APP_KEY" >&2; exit 2 ;;
esac

require_trusted_main_dispatch "$RELEASE_REPO"

STATUS_LABEL="$APP_NAME"

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
printf 'Using the already-downloaded release from %s.\n' "$RELEASE_REPO"
ZIP_PATH="$RELEASE_DOWNLOAD_DIR/Quick-Drop-Zone-1.2.1.zip"
python3 "$ROOT/.github/scripts/verify-readme-media-release.py" "$RELEASE_DOWNLOAD_DIR"
ditto -x -k "$ZIP_PATH" "$EXTRACT_DIR"
APP="$EXTRACT_DIR/$APP_BUNDLE"
[[ ! -L "$APP" && -d "$APP" ]]
bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[[ "$bundle_identifier" == "$APP_BUNDLE_ID" ]] || { printf 'Unexpected Quick Drop Zone bundle identifier: %s' "$bundle_identifier" >&2; exit 1; }
[[ "$bundle_version" == 1.2.1 ]] || { printf 'Unexpected Quick Drop Zone bundle version: %s' "$bundle_version" >&2; exit 1; }
codesign --verify --deep --strict "$APP"
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

prepare_quick_drop_demo() {
  printf '%s\n' 'Creating a temporary synthetic image for the Quick Drop Zone demo.'
  swift "$HELPER" wallpaper "$RUNNER_TEMP/readme-wallpaper.png"
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

prepare_quick_drop_demo
require_app_not_running "$WINDOW_OWNER"
snapshot_app_preferences "$APP_BUNDLE_ID" "$RUNNER_TEMP/$SLUG-preferences-backup.plist"
mark_app_launched "$WINDOW_OWNER"
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
