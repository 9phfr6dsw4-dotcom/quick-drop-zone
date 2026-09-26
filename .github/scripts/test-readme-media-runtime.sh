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
violations = []
for filename in sys.argv[1:]:
    source = Path(filename).read_text(encoding="utf-8")
    violations.extend(f"{Path(filename).name}: {label}" for label, pattern in forbidden.items() if re.search(pattern, source))
capture = Path(sys.argv[1]).read_text(encoding="utf-8")
if not re.search(r"""(?m)^trap\s+finish_capture\s+EXIT\s*$""", capture):
    violations.append("restoring appearance state on every capture exit")
if not re.search(r"""(?s)finish_capture\s*\(\)\s*\{[^}]*restore_appearance""", capture):
    violations.append("capture exit handler restores original appearance")
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

echo 'PASS: video crop, duration, trusted dispatch, safe desktop, and appearance restoration cases'
