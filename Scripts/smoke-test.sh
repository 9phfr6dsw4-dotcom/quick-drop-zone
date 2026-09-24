#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT_DIR/dist/Quick Drop Zone.app"
test -x "$APP/Contents/MacOS/QuickDropZone"
open "$APP"
sleep 3
pid="$(pgrep -x QuickDropZone || true)"
if test -z "$pid"; then
  printf 'App did not remain running after launch.\n' >&2
  exit 1
fi
kill "$pid"
printf 'App launch smoke test passed (process started and was stopped cleanly).\n'
