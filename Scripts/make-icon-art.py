#!/usr/bin/env python3
"""Draws Levant's icon: the layers of Resources/AppIcon.icon, the flat 1024px fallback
(Resources/AppIcon-1024.png and docs/images/levant-icon.png) and one Dock icon per skin
(Resources/SkinIcons/icon-<skin>.png).

Developer tool, not part of CI. Needs Pillow and numpy:  python3 Scripts/make-icon-art.py

The design ("Oyster Steel"): a polished steel bezel around a dial with a fine minute track and
baton hour markers; a document slides into a tray slot under a chevron. The default icon is the
Oyster skin (white dial, steel bezel, navy chevron); the other skins recolour the same drawing.

macOS draws the outer rounded shape, shadow and shine itself, so the layers are drawn on a full
1024x1024 canvas: the tile colour is the .icon's `fill`, and the layers sit on top of it. In icon.json
the FIRST group and FIRST layer are the FRONT-most. This script composites them back to front.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ICON = ROOT / "Resources" / "AppIcon.icon"
ASSETS = ICON / "Assets"
SKIN_ICONS = ROOT / "Resources" / "SkinIcons"
S = 1024
SS = 2  # supersampling for shapes
C = S / 2
K = 1024 / 824  # the concept was drawn on an 824 tile; the .icon canvas is the whole tile

# Back to front. Also the order the layers are drawn in the flat icons.
BACK_TO_FRONT = ["bezel", "chamber", "ticks", "slot", "glass", "chevron", "lip"]

# name: tile top, tile bottom, bezel light/mid/dark, dial centre/edge colours, dial rim, tick, baton,
# slot, document fill (r, g, b, a), document edge, chevron. "marked" adds a dive bezel with minute marks.
SKINS: dict[str, dict] = {
    "slate": dict(bg=("#2E343A", "#111417"), bezel=("#F4F6F8", "#AAB2BC", "#6A7480"), dial=("#2F353C", "#0F1215"),
                  rim="#8C96A2", tick="#D5DCE3", baton="#E6EBF0", slot="#06080A", doc=(255, 255, 255, 26),
                  docedge="#D5DCE3", chev="#A9C2DA"),
    "oyster": dict(bg=("#F1F2F4", "#BEC3CA"), bezel=("#FFFFFF", "#B7BDC6", "#7D8590"), dial=("#FFFFFF", "#E4E0D6"),
                   rim="#9AA1AB", tick="#2A2D32", baton="#23262B", slot="#1E2126", doc=(30, 38, 52, 20),
                   docedge="#23262B", chev="#2B5784"),
    "sky": dict(bg=("#14264A", "#060C1A"), bezel=("#EAF1FD", "#8EA8D0", "#566F9C"), dial=("#183062", "#07101F"),
                rim="#5876A6", tick="#D3E3FB", baton="#E4EEFC", slot="#030610", doc=(220, 235, 255, 26),
                docedge="#D3E3FB", chev="#8DBBF7"),
    "submariner": dict(bg=("#12261C", "#040806"), bezel=("#3B403D", "#171918", "#0A0B0A"), dial=("#111513", "#040504"),
                       rim="#2A302C", tick="#E7F2EA", baton="#E7F2EA", slot="#000000", doc=(255, 255, 255, 18),
                       docedge="#CFE6D6", chev="#5BDB96", marked=True, mark="#EFF5F0", lume="#5BDB96"),
    "turquoise": dict(bg=("#0F2A2C", "#041012"), bezel=("#E3F7F5", "#8FC2BF", "#4F8582"), dial=("#1F5C5E", "#072123"),
                      rim="#4B8E8A", tick="#D6F3F0", baton="#E9FAF8", slot="#020809", doc=(220, 250, 246, 26),
                      docedge="#D6F3F0", chev="#6EE0D6"),
    "bordeaux": dict(bg=("#2D1319", "#10060A"), bezel=("#F3DDE0", "#C28A94", "#7C3D49"), dial=("#5A1F2D", "#1C070C"),
                     rim="#A05A68", tick="#F2D4D9", baton="#F8E4E7", slot="#060103", doc=(255, 225, 230, 26),
                     docedge="#F2D4D9", chev="#F0A3B0"),
    "wisteria": dict(bg=("#231E3A", "#0C0A18"), bezel=("#EFEAFB", "#A99BD6", "#6A5CA3"), dial=("#3C3270", "#120E26"),
                     rim="#7D6BC0", tick="#E1D9F7", baton="#EEE9FB", slot="#05030C", doc=(235, 228, 255, 26),
                     docedge="#E1D9F7", chev="#BBA8F5"),
    "mint": dict(bg=("#E8F1EC", "#B9CFC3"), bezel=("#FFFFFF", "#B3C4BA", "#7E958A"), dial=("#FBFDFC", "#DCE8E1"),
                 rim="#93AA9D", tick="#1F2A24", baton="#1B2620", slot="#1B2320", doc=(25, 40, 32, 20),
                 docedge="#1B2620", chev="#1E6B4A"),
}
DEFAULT_SKIN = "oyster"


# ----- helpers -----------------------------------------------------------------------------------

def rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16)


def canvas() -> Image.Image:
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


def pt(x: float, y: float) -> tuple[float, float]:
    """A point from the 824-tile concept, moved onto the full canvas."""
    return C + (x - 512) * K, C + (y - 512) * K


def circle_mask(radius: float) -> Image.Image:
    big = Image.new("L", (S * SS, S * SS), 0)
    ImageDraw.Draw(big).ellipse([(C - radius) * SS, (C - radius) * SS, (C + radius) * SS, (C + radius) * SS], fill=255)
    return big.resize((S, S), Image.LANCZOS)


def squircle_mask(half: float, n: float = 5.0) -> Image.Image:
    """Continuous-corner rounded square, anti-aliased."""
    y, x = np.mgrid[0:S * SS, 0:S * SS].astype(np.float32)
    x = (x + 0.5) / SS - C
    y = (y + 0.5) / SS - C
    inside = (np.abs(x / half) ** n + np.abs(y / half) ** n) <= 1.0
    return Image.fromarray((inside * 255).astype(np.uint8), "L").resize((S, S), Image.LANCZOS)


def lerp3(t: np.ndarray, stops: list[tuple[float, tuple[int, int, int]]]) -> np.ndarray:
    xs = [s[0] for s in stops]
    return np.stack([np.interp(t, xs, [s[1][c] for s in stops]) for c in range(3)], axis=2)


def with_alpha(color: np.ndarray, alpha: Image.Image | np.ndarray) -> Image.Image:
    img = Image.fromarray(np.clip(color, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    if isinstance(alpha, np.ndarray):
        alpha = Image.fromarray(np.clip(alpha, 0, 255).astype(np.uint8), "L")
    img.putalpha(alpha)
    return img


def solid(color: tuple[int, ...], alpha: Image.Image, opacity: float = 1.0) -> Image.Image:
    layer = Image.new("RGBA", (S, S), tuple(color[:3]) + (0,))
    layer.putalpha(alpha.point(lambda p: int(p * opacity)))
    return layer


def big_draw() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGBA", (S * SS, S * SS), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def to_canvas(img: Image.Image) -> Image.Image:
    return img.resize((S, S), Image.LANCZOS)


def rotated_rect(cx: float, cy: float, along: float, across: float, angle: float) -> list[tuple[float, float]]:
    """Corners of a rectangle centred on (cx, cy): `across` radial (outward) by `along` tangential."""
    ux, uy = math.cos(angle), math.sin(angle)  # outward
    tx, ty = -uy, ux
    pts = []
    for a, b in ((-1, -1), (-1, 1), (1, 1), (1, -1)):
        pts.append(((cx + ux * a * across / 2 + tx * b * along / 2) * SS, (cy + uy * a * across / 2 + ty * b * along / 2) * SS))
    return pts


# ----- layers ---------------------------------------------------------------------------------------

BEZEL_R = 430
DIAL_R = 370


def layer_bezel(p: dict) -> Image.Image:
    """A polished steel ring, lit from the top left, with a thin bright edge."""
    y, x = np.mgrid[0:S, 0:S].astype(np.float32)
    u = (x - (C - BEZEL_R)) / (2 * BEZEL_R)
    v = (y - (C - BEZEL_R)) / (2 * BEZEL_R)
    t = np.clip(((u - 0.15) * 0.7 + v * 1.0) / (0.7 * 0.7 + 1.0), 0, 1)
    b1, b2, b3 = (rgb(c) for c in p["bezel"])
    color = lerp3(t, [(0.0, b1), (0.5, b2), (1.0, b3)])
    out = with_alpha(color, np.array(circle_mask(BEZEL_R)).astype(np.float32))
    mask = circle_mask(BEZEL_R)
    # A diagonal sheen: bright at the top left, shaded at the bottom right.
    light = np.clip(1 - t / 0.45, 0, 1) * 0.30
    dark = np.clip((t - 0.45) / 0.55, 0, 1) * 0.22
    out = Image.alpha_composite(out, with_alpha(np.full((S, S, 3), 255, np.float32), np.array(mask).astype(np.float32) * light))
    out = Image.alpha_composite(out, with_alpha(np.zeros((S, S, 3), np.float32), np.array(mask).astype(np.float32) * dark))
    edge = ImageChops.subtract(mask, circle_mask(BEZEL_R - 4))
    out = Image.alpha_composite(out, solid((255, 255, 255), edge, 0.45))
    if p.get("marked"):
        img, d = big_draw()
        mark = rgb(p["mark"]) + (255,)
        for k in range(60):
            ang = math.radians(k * 6 - 90)
            major = k % 5 == 0
            radius = BEZEL_R - 28
            length = 34 if major else 17
            width = 11 if major else 4.5
            cx, cy = C + math.cos(ang) * radius, C + math.sin(ang) * radius
            d.polygon(rotated_rect(cx, cy, width, length, ang), fill=mark)
        out = Image.alpha_composite(out, to_canvas(img))
        pip = Image.new("L", (S * SS, S * SS), 0)
        ImageDraw.Draw(pip).ellipse([(C - 22) * SS, (C - BEZEL_R + 26 - 22) * SS, (C + 22) * SS, (C - BEZEL_R + 26 + 22) * SS], fill=255)
        out = Image.alpha_composite(out, solid(rgb(p["lume"]), to_canvas(pip.convert("L")), 1.0))
    return out


def layer_chamber(p: dict) -> Image.Image:
    """The dial: a soft radial gradient with a thin rim."""
    y, x = np.mgrid[0:S, 0:S].astype(np.float32)
    cx0, cy0 = C - DIAL_R + 0.4 * 2 * DIAL_R, C - DIAL_R + 0.3 * 2 * DIAL_R
    t = np.clip(np.hypot(x - cx0, y - cy0) / (0.9 * 2 * DIAL_R), 0, 1)
    d1, d2 = rgb(p["dial"][0]), rgb(p["dial"][1])
    color = lerp3(t, [(0.0, d1), (1.0, d2)])
    mask = circle_mask(DIAL_R)
    out = with_alpha(color, np.array(mask).astype(np.float32))
    rim = ImageChops.subtract(mask, circle_mask(DIAL_R - 10))
    return Image.alpha_composite(out, solid(rgb(p["rim"]), rim, 1.0))


def layer_ticks(p: dict) -> Image.Image:
    """A fine minute track and twelve baton hour markers."""
    img, d = big_draw()
    tick = rgb(p["tick"]) + (215,)
    baton = rgb(p["baton"]) + (255,)
    for k in range(60):
        if k % 5 == 0:
            continue
        ang = math.radians(k * 6 - 90)
        radius = 333
        d.polygon(rotated_rect(C + math.cos(ang) * radius, C + math.sin(ang) * radius, 3.4, 15, ang), fill=tick)
    for k in range(12):
        ang = math.radians(k * 30 - 90)
        radius = 320
        d.polygon(rotated_rect(C + math.cos(ang) * radius, C + math.sin(ang) * radius, 10.5, 55, ang), fill=baton)
    return to_canvas(img)


def rounded_box(box: tuple[float, float, float, float], radius: float) -> Image.Image:
    big = Image.new("L", (S * SS, S * SS), 0)
    ImageDraw.Draw(big).rounded_rectangle([c * SS for c in box], radius=radius * SS, fill=255)
    return big.resize((S, S), Image.LANCZOS)


def layer_slot(p: dict) -> Image.Image:
    """The tray slot: a dark cavity."""
    x0, y0 = pt(352, 598)
    x1, y1 = pt(672, 642)
    return solid(rgb(p["slot"]), rounded_box((x0, y0, x1, y1), (y1 - y0) / 2), 1.0)


def layer_glass(p: dict) -> Image.Image:
    """The document with its folded corner, cut off where it slides into the slot."""
    img, d = big_draw()
    outline = [pt(416, 330), pt(562, 330), pt(608, 376), pt(608, 640), pt(416, 640)]
    d.polygon([(x * SS, y * SS) for x, y in outline], fill=tuple(p["doc"]))
    width = int(6 * K * SS)
    line = [(x * SS, y * SS) for x, y in outline + [outline[0]]]
    d.line(line, fill=rgb(p["docedge"]) + (255,), width=width, joint="curve")
    fold = [(x * SS, y * SS) for x, y in (pt(562, 330), pt(562, 376), pt(608, 376))]
    d.line(fold, fill=rgb(p["docedge"]) + (255,), width=width, joint="curve")
    for x, y in line[:-1] + fold:  # round the joints
        d.ellipse([x - width / 2, y - width / 2, x + width / 2, y + width / 2], fill=rgb(p["docedge"]) + (255,))
    out = to_canvas(img)
    cut = pt(0, 618)[1]
    arr = np.array(out)
    arr[int(round(cut)):, :, 3] = 0
    return Image.fromarray(arr, "RGBA")


def layer_chevron(p: dict) -> Image.Image:
    img, d = big_draw()
    pts = [pt(466, 452), pt(512, 498), pt(558, 452)]
    width = 28 * K
    color = rgb(p["chev"]) + (255,)
    d.line([(x * SS, y * SS) for x, y in pts], fill=color, width=int(width * SS), joint="curve")
    for x, y in (pts[0], pts[-1]):
        d.ellipse([(x - width / 2) * SS, (y - width / 2) * SS, (x + width / 2) * SS, (y + width / 2) * SS], fill=color)
    out = to_canvas(img)
    shadow = ImageChops.offset(out.getchannel("A").filter(ImageFilter.GaussianBlur(7)), 0, 8)
    return Image.alpha_composite(solid((0, 0, 0), shadow, 0.28), out)


def layer_lip(p: dict) -> Image.Image:
    """The front edge of the slot, in front of the document."""
    top, bottom = pt(0, 620)[1], pt(0, 648)[1]
    left, right = pt(352, 0)[0], pt(672, 0)[0]
    radius = (pt(0, 642)[1] - pt(0, 598)[1]) / 2
    big = Image.new("L", (S * SS, S * SS), 0)
    d = ImageDraw.Draw(big)
    pts: list[tuple[float, float]] = [(left, top), (right, top), (right, top + (pt(0, 626)[1] - top))]
    for k in range(0, 19):  # the right-hand corner
        ang = math.radians(k * 90 / 18)
        pts.append((right - radius + radius * math.cos(ang), bottom - radius + radius * math.sin(ang)))
    for k in range(0, 19):  # the left-hand corner
        ang = math.radians(90 + k * 90 / 18)
        pts.append((left + radius + radius * math.cos(ang), bottom - radius + radius * math.sin(ang)))
    d.polygon([(x * SS, y * SS) for x, y in pts], fill=255)
    mask = big.resize((S, S), Image.LANCZOS)
    y = np.mgrid[0:S, 0:S][0].astype(np.float32)
    t = np.clip((y - top) / max(1.0, bottom - top), 0, 1)
    b1, b3 = rgb(p["bezel"][0]), rgb(p["bezel"][2])
    color = lerp3(t, [(0.0, b1), (1.0, b3)])
    return with_alpha(color, np.array(mask).astype(np.float32) * 0.95)


LAYER_FUNCS = {
    "bezel": layer_bezel,
    "chamber": layer_chamber,
    "ticks": layer_ticks,
    "slot": layer_slot,
    "glass": layer_glass,
    "chevron": layer_chevron,
    "lip": layer_lip,
}


def render_layers(p: dict) -> dict[str, Image.Image]:
    return {name: fn(p) for name, fn in LAYER_FUNCS.items()}


def tile(p: dict) -> Image.Image:
    top, bottom = rgb(p["bg"][0]), rgb(p["bg"][1])
    y = np.mgrid[0:S, 0:S][0].astype(np.float32)
    color = lerp3(np.clip(y / (S - 1), 0, 1), [(0.0, top), (1.0, bottom)])
    base = with_alpha(color, np.full((S, S), 255, np.float32))
    gloss = np.clip(1 - y / (S * 0.5), 0, 1) * 0.16 * 255
    return Image.alpha_composite(base, with_alpha(np.full((S, S, 3), 255, np.float32), gloss))


def flat_bleed(p: dict, layers: dict[str, Image.Image]) -> Image.Image:
    """The whole icon edge to edge in a squircle (the fallback PNG, the .icns and the README)."""
    base = tile(p)
    for name in BACK_TO_FRONT:
        base = Image.alpha_composite(base, layers[name])
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    out.paste(base, (0, 0), squircle_mask(C))
    return out


def dock_icon(flat: Image.Image) -> Image.Image:
    """The icon at the standard macOS size (an 824 tile on a 1024 canvas) with a soft shadow, for the
    Dock icon the app sets itself when a skin changes."""
    body = flat.resize((824, 824), Image.LANCZOS)
    out = canvas()
    shadow = Image.new("L", (S, S), 0)
    shadow.paste(body.getchannel("A"), (100, 100 + 12))
    out = Image.alpha_composite(out, solid((0, 0, 0), shadow.filter(ImageFilter.GaussianBlur(14)), 0.38))
    out.alpha_composite(body, (100, 100))
    return out


def write_icon_json(p: dict) -> None:
    def srgb(value: str) -> str:
        r, g, b = rgb(value)
        return f"srgb:{r / 255:.5f},{g / 255:.5f},{b / 255:.5f},1.00000"

    data = {
        "fill": {"linear-gradient": [srgb(p["bg"][0]), srgb(p["bg"][1])]},
        "groups": [
            {
                "layers": [
                    {"image-name": "lip.png", "name": "lip"},
                    {"image-name": "chevron.png", "name": "chevron"},
                    {"glass": True, "image-name": "glass.png", "name": "glass"},
                ],
                "name": "Tile",
                "shadow": {"kind": "neutral", "opacity": 0.5},
                "specular": True,
                "translucency": {"enabled": True, "value": 0.15},
            },
            {"layers": [{"image-name": "slot.png", "name": "slot"}], "name": "Slot"},
            {
                "layers": [
                    {"image-name": "ticks.png", "name": "ticks"},
                    {"image-name": "chamber.png", "name": "chamber"},
                ],
                "name": "Dial",
            },
            {"layers": [{"image-name": "bezel.png", "name": "bezel"}], "name": "Bezel"},
        ],
        "supported-platforms": {"squares": "shared"},
    }
    (ICON / "icon.json").write_text(json.dumps(data, indent=2, separators=(",", " : ")) + "\n")


def main() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    SKIN_ICONS.mkdir(parents=True, exist_ok=True)
    default = SKINS[DEFAULT_SKIN]
    layers = render_layers(default)
    for name, image in layers.items():
        image.save(ASSETS / f"{name}.png", optimize=True)
    write_icon_json(default)
    flat = flat_bleed(default, layers)
    flat.save(ROOT / "Resources" / "AppIcon-1024.png", optimize=True)
    flat.save(ROOT / "docs" / "images" / "levant-icon.png", optimize=True)
    for skin, palette in SKINS.items():
        skin_layers = layers if skin == DEFAULT_SKIN else render_layers(palette)
        dock_icon(flat_bleed(palette, skin_layers)).save(SKIN_ICONS / f"icon-{skin}.png", optimize=True)
    print("wrote layers:", ", ".join(BACK_TO_FRONT), "; the flat 1024px icon; and", len(SKINS), "skin icons")


if __name__ == "__main__":
    main()
