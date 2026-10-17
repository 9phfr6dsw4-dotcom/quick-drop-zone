#!/usr/bin/env python3
"""Checks Resources/AppIcon.icon/icon.json before the icon is compiled.

In an Icon Composer file the FIRST group and the FIRST layer are the FRONT-most. Quick Drop Zone's
2.2.0 icon came out black because the full-size dark bezel was listed first and covered everything.
This fails if that order is wrong, a named image is missing, or a file in Assets/ isn't used.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ICON = Path(__file__).resolve().parent.parent / "Resources" / "AppIcon.icon"
FRONT_TO_BACK = ["chevron", "glass", "slot", "ticks", "chamber", "bezel"]


def main() -> int:
    data = json.loads((ICON / "icon.json").read_text())
    layers = [layer for group in data["groups"] for layer in group["layers"]]
    names = [layer["name"] for layer in layers]
    problems: list[str] = []
    if names != FRONT_TO_BACK:
        problems.append(f"layers are {names}, expected front to back {FRONT_TO_BACK}")
    images = [layer["image-name"] for layer in layers]
    for image in images:
        if not (ICON / "Assets" / image).is_file():
            problems.append(f"missing Assets/{image}")
    for path in sorted((ICON / "Assets").iterdir()):
        if path.name not in images:
            problems.append(f"Assets/{path.name} is not used by icon.json")
    for problem in problems:
        print(f"error: {problem}", file=sys.stderr)
    if not problems:
        print("icon.json: " + " > ".join(names) + " (front to back), all images present")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
