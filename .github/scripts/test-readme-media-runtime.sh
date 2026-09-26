#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/readme-media-runtime.sh"

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
  printf '%s\\n' 'FAIL: reject invalid display scale' >&2
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

printf '%s\n' 'PASS: video crop and duration validation cases'
