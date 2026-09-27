#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/readme-media-runtime.sh"

CAPTURE_SCRIPT="$(cd "$(dirname "$0")" && pwd -P)/capture-readme-media.sh"
RUNTIME_HELPER="$(cd "$(dirname "$0")" && pwd -P)/readme-media-runtime.sh"
MEDIA_HELPER="$(cd "$(dirname "$0")" && pwd -P)/render-readme-media.swift"
python3 - "$CAPTURE_SCRIPT" "$RUNTIME_HELPER" "$MEDIA_HELPER" <<'PY'
from pathlib import Path
import re
import sys

forbidden = {
    "setting desktop wallpaper": r"""(?is)\bevery\s+desktop\b.*?\bset\s+picture\b""",
    "changing Finder desktop visibility": r"""(?im)\bdefaults\s+write\s+com\.apple\.finder\s+CreateDesktop\b""",
    "restarting Finder": r"""(?im)\bkillall\s+Finder\b""",
    "closing every Finder window": r"""(?is)tell\s+application\s+['"]Finder['"].*?close\s+every\s+window""",
    "closing every Terminal window": r"""(?is)tell\s+application\s+['"]Terminal['"].*?close\s+every\s+window""",
}
# The Swift helper still defines seed commands for other apps; the shell path must never call them.
forbidden_in_shell = {
    "writing host preferences": r"""(?im)\bdefaults\s+write\b""",
    "seeding the host clipboard or another app's data": r"""\bseed-(?:clipboard|echotype)\b""",
    "installing packages outside the hosted-runner guard": r"""\bbrew\s+install\s+(?!"\$tool")""",
}
violations = []
for filename in sys.argv[1:]:
    source = Path(filename).read_text(encoding="utf-8")
    violations.extend(f"{Path(filename).name}: {label}" for label, pattern in forbidden.items() if re.search(pattern, source))
    if filename.endswith(".sh"):
        violations.extend(f"{Path(filename).name}: {label}" for label, pattern in forbidden_in_shell.items() if re.search(pattern, source))
capture = Path(sys.argv[1]).read_text(encoding="utf-8")
if not re.search(r"""(?m)^trap\s+finish_capture\s+EXIT\s*$""", capture):
    violations.append("restoring appearance state on every capture exit")
for signal in ("INT", "TERM", "HUP"):
    if not re.search(rf"""(?m)^trap\s+'exit\s+[0-9]+'\s+{signal}\s*$""", capture):
        violations.append(f"running the exit handler when the capture receives {signal}")
handler = re.search(r"""(?s)finish_capture\s*\(\)\s*\{(.*?)\n\}""", capture)
handler_body = re.sub(r"(?m)^\s*#.*\n", "", handler.group(1)) if handler else ""
if not re.search(r"""\A\s*local\s+exit_status="\$\?"\s*\n\s*trap\s+''\s+INT\s+TERM\s+HUP\s*\n""", handler_body):
    violations.append("capture exit handler ignores further signals before cleaning up")
steps = [handler_body.find(step) for step in ("stop_launched_app", "restore_app_preferences", "restore_appearance")]
if min(steps) < 0 or steps != sorted(steps):
    violations.append("capture exit handler quits the app, then restores its preferences, then the appearance")
workflow = (Path(sys.argv[1]).parent.parent / "workflows" / "readme-media.yml").read_text(encoding="utf-8")
if not re.search(r"""(?m)^\s*run:\s+exec\s+bash\s+\.github/scripts/capture-readme-media\.sh\s*$""", workflow):
    violations.append("readme-media.yml: capture script receives cancellation signals directly")
pgrep_calls = re.findall(r'\bpgrep\b[^\n|;&)]*', Path(sys.argv[2]).read_text(encoding="utf-8"))
if not pgrep_calls or any(not re.search(r'-U\s+"\$\(id\s+-u\b', call) for call in pgrep_calls):
    violations.append("readme-media-runtime.sh: only matching the current user's app processes")
launch = re.search(r"""(?m)^\s*open\s+"\$APP"\s*$""", capture)
guards = [capture.find(name) for name in ("require_app_not_running", "snapshot_app_preferences", "mark_app_launched")]
if not launch or min(guards) < 0 or max(guards) > launch.start():
    violations.append("checking, snapshotting, and tracking app state before launching the app")
for filename in sys.argv[1:3]:
    if re.search(r"""(?i)clipboard-?shelf|echotype|captiongrab""", Path(filename).read_text(encoding="utf-8")):
        violations.append(f"{Path(filename).name}: limiting the capture path to this repository's app")
if violations:
    raise SystemExit("FAIL: unsafe desktop behavior in capture helper: " + ", ".join(violations))
PY

ffprobe() { printf '%s\n' "${MOCK_VIDEO_DIMENSIONS:?}"; }

assert_equal() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL: %s (expected=%s, actual=%s)\n' "$label" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_equal '476,0,460,542,2' "$(menu_capture_region '500|22|400|500|880|0|32|24|0' 'frame=1920x1080|pixels=3840x2160|scale=2')" 'compute a bounded menu capture region from verified geometry'

for geometry in \
  '' \
  '500|22|400|500|880|0|32|24' \
  '500|22|400|500|880|0|32|24|1' \
  '0500|22|400|500|880|0|32|24|0' \
  '-1|22|400|500|880|0|32|24|0' \
  '500|22|239|500|880|0|32|24|0' \
  '1800|22|400|500|880|0|32|24|0'; do
  if menu_capture_region "$geometry" 'frame=1920x1080|pixels=3840x2160|scale=2' >/dev/null 2>&1; then
    printf 'FAIL: reject invalid/too-small/out-of-bounds geometry: %s\\n' "$geometry" >&2
    exit 1
  fi
done
if menu_capture_region '500|22|400|500|880|0|32|24|0' 'frame=1920x1080|pixels=3840x2160|scale=0' >/dev/null 2>&1; then
  printf 'FAIL: reject invalid display scale\n' >&2
  exit 1
fi

MOCK_VIDEO_DIMENSIONS=1280x900
assert_equal null "$(video_region_filter /unused 0 0 640 450 2)" 'accept exact region dimensions'

MOCK_VIDEO_DIMENSIONS=2560x1800
assert_equal 'crop=1280:900:200:80' "$(video_region_filter /unused 100 40 640 450 2)" 'crop full-display recording to exact requested region'

MOCK_VIDEO_DIMENSIONS=1300x900
if video_region_filter /unused 100 0 640 450 2 >/dev/null 2>&1; then
  printf '%s\n' 'FAIL: reject a region that does not fit the source recording' >&2
  exit 1
fi

MOCK_VIDEO_DIMENSIONS=1280x900
if video_region_filter /unused -1 0 640 450 2 >/dev/null 2>&1; then
  printf '%s\n' 'FAIL: reject negative capture coordinates' >&2
  exit 1
fi

if duration_is_acceptable 12.0001; then
  printf '%s\n' 'FAIL: reject fractional duration over 12 seconds' >&2
  exit 1
fi
if duration_is_acceptable 12.999; then
  printf '%s\n' 'FAIL: reject truncated integer duration over 12 seconds' >&2
  exit 1
fi
if duration_is_acceptable 5.999; then
  printf '%s\n' 'FAIL: reject fractional duration under 6 seconds' >&2
  exit 1
fi
for duration in 6 6.0001 11.999 12 12.000; do
  duration_is_acceptable "$duration" || { printf 'FAIL: accept duration %s within 6–12 seconds\n' "$duration" >&2; exit 1; }
done
if duration_is_acceptable invalid; then
  printf '%s\n' 'FAIL: reject malformed duration' >&2
  exit 1
fi

GITHUB_EVENT_NAME=workflow_dispatch
GITHUB_REF=refs/heads/main
GITHUB_REPOSITORY=9phfr6dsw4-dotcom/quick-drop-zone
require_trusted_main_dispatch 9phfr6dsw4-dotcom/quick-drop-zone || { echo 'FAIL: accept trusted canonical-repository main workflow dispatch' >&2; exit 1; }
GITHUB_REF=refs/heads/feature
if require_trusted_main_dispatch 9phfr6dsw4-dotcom/quick-drop-zone 2>/dev/null; then
  echo 'FAIL: reject workflow dispatch from an untrusted ref' >&2
  exit 1
fi
GITHUB_REF=refs/heads/main
GITHUB_REPOSITORY=attacker/quick-drop-zone
if require_trusted_main_dispatch 9phfr6dsw4-dotcom/quick-drop-zone 2>/dev/null; then
  echo 'FAIL: reject workflow dispatch from a fork' >&2
  exit 1
fi

MOCK_SET_STATUS=0
MOCK_SET_MUTATES_ON_ERROR=false
MOCK_SET_EFFECTIVE_MODE=''
MOCK_QUERY_STATUS=0
MOCK_APPEARANCE_MODE=false
MOCK_QUERY_COUNT=0
osascript() {
  case "$*" in
    *'set dark mode to '*)
      local requested status="$MOCK_SET_STATUS"
      if [[ "$*" == *'set dark mode to true' ]]; then requested=true; else requested=false; fi
      if [[ "$status" == 0 ]]; then
        MOCK_APPEARANCE_MODE="${MOCK_SET_EFFECTIVE_MODE:-$requested}"
      elif [[ "$MOCK_SET_MUTATES_ON_ERROR" == true ]]; then
        MOCK_APPEARANCE_MODE="$requested"
        MOCK_SET_STATUS=0
      fi
      return "$status"
      ;;
    *'get dark mode'*)
      MOCK_QUERY_COUNT=$((MOCK_QUERY_COUNT + 1))
      echo "$MOCK_APPEARANCE_MODE"
      return "$MOCK_QUERY_STATUS"
      ;;
    *) return 1 ;;
  esac
}
sleep() { :; }
APPEARANCE_ORIGINAL=''
APPEARANCE_ORIGINAL_SET=0
set_appearance true || { echo 'FAIL: accept a verified appearance change' >&2; exit 1; }
assert_equal false "$APPEARANCE_ORIGINAL" 'remember the original system appearance before changing it'
assert_equal true "$MOCK_APPEARANCE_MODE" 'apply the requested appearance'
restore_appearance || { echo 'FAIL: restore the original system appearance' >&2; exit 1; }
assert_equal false "$MOCK_APPEARANCE_MODE" 'restore system appearance after capture'
assert_equal 0 "$APPEARANCE_ORIGINAL_SET" 'clear saved appearance after restoration'

APPEARANCE_ORIGINAL=''
APPEARANCE_ORIGINAL_SET=0
MOCK_SET_EFFECTIVE_MODE=false
if set_appearance true 2>/dev/null; then
  echo 'FAIL: refuse a mismatched appearance change' >&2
  exit 1
fi
restore_appearance || { echo 'FAIL: restore appearance after a mismatched setter' >&2; exit 1; }
MOCK_SET_EFFECTIVE_MODE=''

APPEARANCE_ORIGINAL=''
APPEARANCE_ORIGINAL_SET=0
MOCK_QUERY_COUNT=0
MOCK_SET_STATUS=1
MOCK_SET_MUTATES_ON_ERROR=true
if set_appearance true 2>/dev/null; then
  echo 'FAIL: refuse a failed appearance change' >&2
  exit 1
fi
assert_equal true "$MOCK_APPEARANCE_MODE" 'regression fixture models a setter that changed state before failing'
restore_appearance || { echo 'FAIL: restore appearance after a failed setter' >&2; exit 1; }
assert_equal false "$MOCK_APPEARANCE_MODE" 'restore original appearance even when setter reports failure'
MOCK_SET_STATUS=0
MOCK_SET_MUTATES_ON_ERROR=false

TEST_SCRATCH="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/readme-media-runtime-test.XXXXXX")"
trap 'rm -rf "$TEST_SCRATCH"' EXIT

MOCK_RUNNING_PIDS=''
MOCK_PGREP_STATUS=''
MOCK_IGNORES_TERM=false
MOCK_KILL_LOG=''
pgrep() {
  if [[ -n "$MOCK_PGREP_STATUS" ]]; then return "$MOCK_PGREP_STATUS"; fi
  [[ -n "$MOCK_RUNNING_PIDS" ]] || return 1
  printf '%s\n' $MOCK_RUNNING_PIDS
}
kill() {
  MOCK_KILL_LOG+="$* ;"
  if [[ "$1" == -KILL || "$MOCK_IGNORES_TERM" != true ]]; then MOCK_RUNNING_PIDS=''; fi
}

MOCK_RUNNING_PIDS=4242
if require_app_not_running QuickDropZone 2>/dev/null; then
  echo 'FAIL: refuse to capture while a copy of the app is already running' >&2
  exit 1
fi
MOCK_RUNNING_PIDS=''
MOCK_PGREP_STATUS=3
if require_app_not_running QuickDropZone 2>/dev/null; then
  echo 'FAIL: refuse to capture when running copies cannot be checked' >&2
  exit 1
fi
MOCK_PGREP_STATUS=''
require_app_not_running QuickDropZone || { echo 'FAIL: allow capture when the app is not running' >&2; exit 1; }

stop_launched_app || { echo 'FAIL: stopping is a no-op before launch' >&2; exit 1; }
assert_equal '' "$MOCK_KILL_LOG" 'do not signal any process before the capture launches the app'
mark_app_launched QuickDropZone
MOCK_RUNNING_PIDS='4242 4243'
stop_launched_app || { echo 'FAIL: quit the app launched for capture' >&2; exit 1; }
assert_equal '-TERM 4242 4243 ;' "$MOCK_KILL_LOG" 'ask the launched app to quit'
assert_equal '' "$APP_LAUNCHED_PROCESS" 'forget the launched app after it quits'
MOCK_KILL_LOG=''
mark_app_launched QuickDropZone
MOCK_RUNNING_PIDS=4242
MOCK_IGNORES_TERM=true
stop_launched_app || { echo 'FAIL: force-quit a launched app that ignores TERM' >&2; exit 1; }
assert_equal '-TERM 4242 ;-KILL 4242 ;' "$MOCK_KILL_LOG" 'force-quit the launched app only after TERM fails'
MOCK_IGNORES_TERM=false
unset -f kill

MOCK_DEFAULTS_DOMAINS=''
MOCK_DEFAULTS_LOG=''
MOCK_IMPORT_STATUS=0
defaults() {
  MOCK_DEFAULTS_LOG+="$1 ${2:-} ;"
  case "$1" in
    read) [[ " $MOCK_DEFAULTS_DOMAINS " == *" $2 "* ]] ;;
    export) printf 'original-%s\n' "$2" > "$3" ;;
    delete) MOCK_DEFAULTS_DOMAINS="${MOCK_DEFAULTS_DOMAINS//$2/}"; return 0 ;;
    import)
      [[ "$MOCK_IMPORT_STATUS" == 0 ]] || return "$MOCK_IMPORT_STATUS"
      [[ "$(cat "$3")" == "original-$2" ]] || return 1
      MOCK_DEFAULTS_DOMAINS+=" $2"
      ;;
    *) return 1 ;;
  esac
}

backup="$TEST_SCRATCH/quick-drop-zone-preferences-backup.plist"
snapshot_app_preferences com.quickdropzone.app "$backup" || { echo 'FAIL: snapshot absent app preferences' >&2; exit 1; }
MOCK_DEFAULTS_DOMAINS+=' com.quickdropzone.app'
restore_app_preferences || { echo 'FAIL: remove app preferences the capture created' >&2; exit 1; }
if defaults read com.quickdropzone.app; then
  echo 'FAIL: remove app preferences created by a capture on a host that had none' >&2
  exit 1
fi

MOCK_DEFAULTS_DOMAINS=' com.quickdropzone.app'
MOCK_DEFAULTS_LOG=''
snapshot_app_preferences com.quickdropzone.app "$backup" || { echo 'FAIL: snapshot existing app preferences' >&2; exit 1; }
assert_equal "original-com.quickdropzone.app" "$(cat "$backup")" 'export existing app preferences into RUNNER_TEMP'
if defaults read com.quickdropzone.app; then
  echo 'FAIL: start the capture without the host copy of the app preferences' >&2
  exit 1
fi
MOCK_DEFAULTS_LOG=''
restore_app_preferences || { echo 'FAIL: restore existing app preferences' >&2; exit 1; }
assert_equal 'delete com.quickdropzone.app ;import com.quickdropzone.app ;' \
  "$MOCK_DEFAULTS_LOG" 'replace capture-time app preferences with the pre-capture copy'
assert_equal '' "$APP_PREFERENCES_DOMAIN" 'forget the preferences snapshot after restoring it'
[[ ! -e "$backup" ]] || { echo 'FAIL: remove the preferences backup after a successful restore' >&2; exit 1; }
[[ " $MOCK_DEFAULTS_DOMAINS " == *' com.quickdropzone.app '* ]] || { echo 'FAIL: host app preferences are back after capture' >&2; exit 1; }

MOCK_IMPORT_STATUS=1
snapshot_app_preferences com.quickdropzone.app "$backup"
if restore_app_preferences 2>/dev/null; then
  echo 'FAIL: report a failed app preference restore' >&2
  exit 1
fi
[[ -s "$backup" ]] || { echo 'FAIL: keep the preferences backup when restoring fails' >&2; exit 1; }
MOCK_IMPORT_STATUS=0
APP_PREFERENCES_DOMAIN=''

printf 'left-by-a-failed-run\n' > "$backup"
if snapshot_app_preferences com.quickdropzone.app "$backup" 2>/dev/null; then
  echo 'FAIL: refuse to start while a previous preferences backup is still unrestored' >&2
  exit 1
fi
assert_equal 'left-by-a-failed-run' "$(cat "$backup")" 'keep the only copy of preferences left by a failed run'
assert_equal '' "$APP_PREFERENCES_DOMAIN" 'do not track a snapshot that was refused'
rm -f "$backup"

ln -s "$TEST_SCRATCH/elsewhere.plist" "$TEST_SCRATCH/linked-backup.plist"
if snapshot_app_preferences com.quickdropzone.app "$TEST_SCRATCH/linked-backup.plist" 2>/dev/null; then
  echo 'FAIL: refuse a symlinked preferences backup path' >&2
  exit 1
fi
[[ ! -e "$TEST_SCRATCH/elsewhere.plist" ]] || { echo 'FAIL: do not write through a symlinked backup path' >&2; exit 1; }
unset -f defaults pgrep

MOCK_BREW_LOG=''
brew() { MOCK_BREW_LOG+="$* ;"; }
mkdir "$TEST_SCRATCH/bin"
printf '#!/bin/sh\n' > "$TEST_SCRATCH/bin/present-capture-tool"
chmod +x "$TEST_SCRATCH/bin/present-capture-tool"
(
  PATH="$TEST_SCRATCH/bin:$PATH"
  ensure_capture_tool present-capture-tool
) || { echo 'FAIL: accept an installed capture tool' >&2; exit 1; }
if RUNNER_ENVIRONMENT=self-hosted ensure_capture_tool missing-capture-tool 2>/dev/null; then
  echo 'FAIL: refuse to install packages on a self-hosted or local machine' >&2
  exit 1
fi
if RUNNER_ENVIRONMENT='' ensure_capture_tool missing-capture-tool 2>/dev/null; then
  echo 'FAIL: refuse to install packages when the runner type is unknown' >&2
  exit 1
fi
assert_equal '' "$MOCK_BREW_LOG" 'never install packages outside an ephemeral GitHub-hosted runner'
RUNNER_ENVIRONMENT=github-hosted ensure_capture_tool missing-capture-tool || { echo 'FAIL: install a missing tool on a GitHub-hosted runner' >&2; exit 1; }
assert_equal 'install missing-capture-tool ;' "$MOCK_BREW_LOG" 'install missing tools only on GitHub-hosted runners'
unset -f brew

for other_app in clipboard-shelf echotype captiongrab; do
  status=0
  env -u GITHUB_EVENT_NAME RUNNER_TEMP="$TEST_SCRATCH" APP_KEY="$other_app" bash "$CAPTURE_SCRIPT" >/dev/null 2>"$TEST_SCRATCH/other-app.err" || status=$?
  assert_equal 2 "$status" "refuse APP_KEY=$other_app before touching host state"
  grep -q 'Unknown APP_KEY' "$TEST_SCRATCH/other-app.err" || { echo "FAIL: explain why APP_KEY=$other_app is refused" >&2; exit 1; }
done

echo 'PASS: video crop, duration, trusted dispatch, safe desktop, appearance, app state, and package-install cases'
