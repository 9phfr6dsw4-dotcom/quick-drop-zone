#!/usr/bin/env python3
"""Draws Quick Drop Zone's icon: the layers of Resources/AppIcon.icon and the flat 1024px fallback
(Resources/AppIcon-1024.png and docs/images/quick-drop-zone-icon.png).

Developer tool, not part of CI. Needs Pillow and numpy:  python3 Scripts/make-icon-art.py

The design: a brushed-titanium bezel, a recessed dark chamber ringed with dial ticks, a tray slot, a
frosted-glass document with a folded corner, and a champagne chevron. Geometry follows the concept
SwiftUI sketch (bezel radius 224, chamber inset 58, document 440x490 with a 110 fold, slot 540x95).

macOS draws the outer rounded shape, shadow and shine itself, so the bezel layer is a full 1024x1024
square with no outline. In icon.json the FIRST group and FIRST layer are the FRONT-most: the file lists
chevron, glass, slot, dial, bezel in that order, and this script composites them back to front.
"""
from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Resources" / "AppIcon.icon" / "Assets"
S = 1024
SS = 2  # supersampling for shapes
C = S / 2
rng = np.random.default_rng(20261018)

CHAMBER_INSET = 100  # bezel thickness: the chamber sits this far in from the edge

CHAMPAGNE_LIGHT = (240, 225, 194)
CHAMPAGNE_MID = (209, 189, 153)
CHAMPAGNE_DARK = (173, 148, 112)

# Back to front. Also the order the layers are drawn in the flat fallback.
BACK_TO_FRONT = ["bezel", "chamber", "ticks", "slot", "glass", "chevron"]


# ----- helpers -----------------------------------------------------------------------------------

def canvas() -> Image.Image:
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


def superellipse_mask(half_w: float, half_h: float, n: float, cx: float = C, cy: float = C) -> Image.Image:
    """Continuous-corner rounded square (|x/a|^n + |y/b|^n <= 1), anti-aliased."""
    y, x = np.mgrid[0:S * SS, 0:S * SS].astype(np.float32)
    x = (x + 0.5) / SS - cx
    y = (y + 0.5) / SS - cy
    inside = (np.abs(x / half_w) ** n + np.abs(y / half_h) ** n) <= 1.0
    big = Image.fromarray((inside * 255).astype(np.uint8), "L")
    return big.resize((S, S), Image.LANCZOS)


def lerp_stops(t: np.ndarray, stops: list[tuple[float, float]]) -> np.ndarray:
    xs = [s[0] for s in stops]
    ys = [s[1] for s in stops]
    return np.interp(t, xs, ys)


def diag_t() -> np.ndarray:
    y, x = np.mgrid[0:S, 0:S].astype(np.float32)
    return (x + y) / (2 * (S - 1))


def blurred_noise(local: np.random.Generator, radius: float) -> np.ndarray:
    """Zero-mean, roughly unit-variance noise, blurred (Pillow only blurs 8-bit images)."""
    raw = np.clip(local.normal(128, 42, (S, S)), 0, 255).astype(np.uint8)
    img = Image.fromarray(raw, "L").filter(ImageFilter.GaussianBlur(radius))
    arr = (np.array(img).astype(np.float32) - 128.0)
    return arr / (arr.std() or 1.0)


def brushed(strength: float, seed_shift: int = 0) -> np.ndarray:
    """Horizontal brushed-metal grain, roughly zero-mean, in grey levels."""
    local = np.random.default_rng(20261018 + seed_shift)
    narrow = np.clip(local.normal(128, 42, (S, max(8, S // 46))), 0, 255).astype(np.uint8)
    streaks = np.array(Image.fromarray(narrow, "L").resize((S, S), Image.BICUBIC)).astype(np.float32) - 128.0
    streaks = streaks / (streaks.std() or 1.0)
    fine = blurred_noise(local, 0.7)
    return strength * (0.75 * streaks + 0.45 * fine)


def with_alpha(rgb: np.ndarray, alpha: Image.Image | np.ndarray) -> Image.Image:
    img = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    if isinstance(alpha, np.ndarray):
        alpha = Image.fromarray(np.clip(alpha, 0, 255).astype(np.uint8), "L")
    img.putalpha(alpha)
    return img


def solid(color: tuple[int, ...], alpha: Image.Image, opacity: float = 1.0) -> Image.Image:
    layer = Image.new("RGBA", (S, S), color[:3] + (0,))
    layer.putalpha(alpha.point(lambda p: int(p * opacity)))
    return layer


def gradient_image(top: tuple[int, ...], bottom: tuple[int, ...], box: tuple[int, int, int, int]) -> Image.Image:
    """A vertical gradient that fills the whole canvas, running between the box's top and bottom edges."""
    y = np.arange(S, dtype=np.float32)[:, None, None]
    t = np.clip((y - box[1]) / max(1, box[3] - box[1]), 0, 1)
    top_a, bot_a = np.array(top[:3], np.float32), np.array(bottom[:3], np.float32)
    arr = (top_a * (1 - t) + bot_a * t) * np.ones((1, S, 1), np.float32)
    return Image.fromarray(arr.astype(np.uint8), "RGB").convert("RGBA")


# ----- layers ---------------------------------------------------------------------------------------

def layer_bezel() -> Image.Image:
    """Brushed titanium, edge to edge, with a polished chamfer along the outer edge."""
    t = diag_t()
    base = lerp_stops(t, [(0.0, 112), (0.22, 74), (0.62, 46), (0.86, 40), (1.0, 80)])
    y, _ = np.mgrid[0:S, 0:S].astype(np.float32)
    top_light = np.clip(1 - y / (S * 0.5), 0, 1) * 34  # lit from the top
    v = base + top_light + brushed(7.0)
    rgb = np.stack([v * 0.99, v * 1.0, v * 1.03], axis=2)
    out = with_alpha(rgb, np.full((S, S), 255, np.uint8))

    outer = superellipse_mask(C - 1, C - 1, 5.0)
    inner = superellipse_mask(C - 26, C - 26, 5.0)
    ring = ImageChops.subtract(outer, inner)
    rt = diag_t()
    ring_v = lerp_stops(rt, [(0.0, 238), (0.30, 150), (0.62, 70), (0.82, 92), (1.0, 196)])
    ring_rgb = np.stack([ring_v, ring_v, ring_v * 1.02], axis=2)
    out = Image.alpha_composite(out, with_alpha(ring_rgb, np.array(ring).astype(np.float32) * 0.95))

    # A dark gap, then a thin bright line: the step from the chamfer down to the face.
    gap = ImageChops.subtract(superellipse_mask(C - 26, C - 26, 5.0), superellipse_mask(C - 33, C - 33, 5.0))
    out = Image.alpha_composite(out, solid((8, 9, 11), gap, 0.9))
    lip = ImageChops.subtract(superellipse_mask(C - 33, C - 33, 5.0), superellipse_mask(C - 38, C - 38, 5.0))
    lip_v = lerp_stops(rt, [(0.0, 150), (0.45, 70), (0.75, 60), (1.0, 205)])
    out = Image.alpha_composite(out, with_alpha(np.stack([lip_v] * 3, axis=2), np.array(lip).astype(np.float32) * 0.8))

    # The front lip along the bottom is brighter, like the polished underside in the concept.
    low = ImageChops.subtract(superellipse_mask(C - 56, C - 56, 5.0), superellipse_mask(C - 66, C - 66, 5.0))
    fade = np.clip((np.mgrid[0:S, 0:S][0].astype(np.float32) - S * 0.55) / (S * 0.3), 0, 1)
    out = Image.alpha_composite(out, solid((215, 219, 226), Image.fromarray((np.array(low) * fade * 0.55).astype(np.uint8)), 1.0))
    return out


def layer_chamber() -> Image.Image:
    """The recessed dark chamber, slightly lighter in the middle, with a shadowed edge."""
    half = C - CHAMBER_INSET
    mask = superellipse_mask(half, half, 4.6)
    y, x = np.mgrid[0:S, 0:S].astype(np.float32)
    r = np.hypot((x - C) / half, (y - (C - 40)) / half)
    v = lerp_stops(np.clip(r, 0, 1.4), [(0.0, 78), (0.55, 60), (0.95, 38), (1.4, 28)])
    rgb = np.stack([v * 0.93, v * 0.98, v * 1.1], axis=2)
    out = with_alpha(rgb, np.array(mask).astype(np.float32))
    # Inner shadow: dark along the top and left edges, a faint light along the bottom right.
    edge = ImageChops.subtract(mask, superellipse_mask(half - 16, half - 16, 4.6)).filter(ImageFilter.GaussianBlur(3))
    t = diag_t()
    shade = lerp_stops(t, [(0.0, 235), (0.45, 120), (0.8, 40), (1.0, 0)])
    out = Image.alpha_composite(out, with_alpha(np.zeros((S, S, 3)), np.array(edge).astype(np.float32) * (shade / 255.0) * 0.9))
    glow = ImageChops.subtract(superellipse_mask(half, half, 4.6), superellipse_mask(half - 3, half - 3, 4.6))
    glow_a = np.array(glow).astype(np.float32) * np.clip((t - 0.55) / 0.45, 0, 1) * 0.5
    out = Image.alpha_composite(out, with_alpha(np.full((S, S, 3), 175, np.float32), glow_a))
    return out


def layer_ticks() -> Image.Image:
    """Dial ticks that follow the chamber's rounded edge, plus four small screws."""
    img = Image.new("RGBA", (S * SS, S * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    a, n = C - CHAMBER_INSET - 30, 4.6
    # Sample the curve densely, then place ticks at equal distances along it.
    ts = np.linspace(0, 2 * math.pi, 6000, endpoint=False)
    ex = 2.0 / n
    xs = C + a * np.sign(np.cos(ts)) * np.abs(np.cos(ts)) ** ex
    ys = C + a * np.sign(np.sin(ts)) * np.abs(np.sin(ts)) ** ex
    seg = np.hypot(np.diff(xs, append=xs[0]), np.diff(ys, append=ys[0]))
    cum = np.concatenate([[0], np.cumsum(seg)])[:-1]
    count = 96
    for k in range(count):
        i = int(np.searchsorted(cum, cum[-1] * k / count))
        i = min(i, len(ts) - 1)
        px, py = xs[i], ys[i]
        gx = n * np.sign(px - C) * (abs(px - C) / a) ** (n - 1) / a
        gy = n * np.sign(py - C) * (abs(py - C) / a) ** (n - 1) / a
        norm = math.hypot(gx, gy) or 1.0
        nx, ny = gx / norm, gy / norm  # outward
        major = k % 6 == 0
        length = 26 if major else 14
        width = 5 if major else 3
        color = (186, 191, 201, 235) if major else (150, 156, 168, 150)
        d.line([((px) * SS, (py) * SS), ((px - nx * length) * SS, (py - ny * length) * SS)], fill=color, width=width * SS)
    # screws
    for sx in (-1, 1):
        for sy in (-1, 1):
            cx, cy = C + sx * 290, C + sy * 290
            d.ellipse([(cx - 11) * SS, (cy - 11) * SS, (cx + 11) * SS, (cy + 11) * SS], fill=(92, 96, 106, 255))
            d.ellipse([(cx - 8) * SS, (cy - 8) * SS, (cx + 8) * SS, (cy + 8) * SS], fill=(44, 47, 54, 255))
            ang = math.radians(25 + 37 * (sx + 2 * sy))
            d.line([(cx - 6 * math.cos(ang)) * SS, (cy - 6 * math.sin(ang)) * SS, (cx + 6 * math.cos(ang)) * SS, (cy + 6 * math.sin(ang)) * SS], fill=(14, 15, 18, 255), width=2 * SS)
    return img.resize((S, S), Image.LANCZOS)


def rrect_mask(box: tuple[float, float, float, float], radius: float) -> Image.Image:
    big = Image.new("L", (S * SS, S * SS), 0)
    ImageDraw.Draw(big).rounded_rectangle([c * SS for c in box], radius=radius * SS, fill=255)
    return big.resize((S, S), Image.LANCZOS)


def layer_slot() -> Image.Image:
    """The tray slot at the bottom: a dark cavity with a thin metal lip."""
    box = (C - 345, 735 - 56, C + 345, 735 + 56)
    mask = rrect_mask(box, 30)
    cavity = gradient_image((5, 6, 8), (30, 32, 38), (0, int(box[1]), 0, int(box[3])))
    out = Image.alpha_composite(canvas(), Image.composite(cavity, canvas(), mask))
    ring = ImageChops.subtract(mask, rrect_mask((box[0] + 4, box[1] + 4, box[2] - 4, box[3] - 4), 26))
    out = Image.alpha_composite(out, solid((0, 0, 0), ring, 0.9))
    lip = rrect_mask((box[0] + 26, box[3] - 10, box[2] - 26, box[3] - 5), 2.5)
    out = Image.alpha_composite(out, solid((120, 126, 138), lip, 0.85))
    return out


def doc_polygon(rect: tuple[float, float, float, float], fold: float, radius: float) -> Image.Image:
    x0, y0, x1, y1 = rect
    big = Image.new("L", (S * SS, S * SS), 0)
    d = ImageDraw.Draw(big)
    d.rounded_rectangle([c * SS for c in rect], radius=radius * SS, fill=255)
    # the top-right corner is folded away
    d.polygon([((x1 - fold) * SS, (y0 - 3) * SS), ((x1 + 3) * SS, (y0 - 3) * SS), ((x1 + 3) * SS, (y0 + fold) * SS)], fill=0)
    return big.resize((S, S), Image.LANCZOS)


def layer_glass() -> Image.Image:
    """The frosted-glass document with a curled corner. macOS adds its own glass shine on top."""
    rect = (207, 169, 817, 789)
    fold, radius = 170, 40
    mask = doc_polygon(rect, fold, radius)
    y, x = np.mgrid[0:S, 0:S].astype(np.float32)
    t = np.clip(((x - rect[0]) / (rect[2] - rect[0]) * 0.45 + (y - rect[1]) / (rect[3] - rect[1]) * 0.75) / 1.2, 0, 1)
    r = lerp_stops(t, [(0, 166), (0.5, 132), (1, 100)])
    g = lerp_stops(t, [(0, 173), (0.5, 140), (1, 108)])
    b = lerp_stops(t, [(0, 184), (0.5, 152), (1, 120)])
    frost = blurred_noise(np.random.default_rng(7), 1.6) * 1.4
    rgb = np.stack([r + frost, g + frost, b + frost], axis=2)
    body = with_alpha(rgb, np.array(mask).astype(np.float32) * 0.93)
    out = Image.alpha_composite(canvas(), body)

    # Softer, darker where the sheet slides into the slot.
    low = np.clip((y - (rect[3] - 130)) / 130, 0, 1)
    out = Image.alpha_composite(out, with_alpha(np.zeros((S, S, 3)), np.array(mask).astype(np.float32) / 255.0 * low * 70))
    # Glass edge: bright along the top and left, faint along the bottom.
    edge = ImageChops.subtract(mask, mask.filter(ImageFilter.MinFilter(7)))
    edge_a = np.array(edge).astype(np.float32) * lerp_stops(diag_t(), [(0, 0.95), (0.5, 0.45), (1, 0.18)])
    out = Image.alpha_composite(out, with_alpha(np.full((S, S, 3), 248, np.float32), edge_a))
    # A broad soft highlight across the upper left, as on thick frosted glass.
    hl = Image.new("L", (S, S), 0)
    ImageDraw.Draw(hl).ellipse([rect[0] - 100, rect[1] - 200, rect[0] + 420, rect[1] + 260], fill=64)
    hl = hl.filter(ImageFilter.GaussianBlur(60))
    out = Image.alpha_composite(out, solid((255, 255, 255), ImageChops.multiply(hl, mask), 1.0))

    # The curled corner: a lighter flap with a soft shadow on the sheet beneath it.
    x1, y0 = rect[2], rect[1]
    flap = Image.new("L", (S * SS, S * SS), 0)
    fd = ImageDraw.Draw(flap)
    corner = 34
    pts = [((x1 - fold) * SS, y0 * SS), ((x1 - fold) * SS, (y0 + fold - corner) * SS)]
    for k in range(0, 21):  # a rounded outer corner
        ang = math.radians(180 - 90 * k / 20)
        pts.append(((x1 - fold + corner + corner * math.cos(ang)) * SS, (y0 + fold - corner + corner * math.sin(math.pi - ang) * -1 * -1) * SS))
    pts += [(x1 * SS, (y0 + fold) * SS)]
    fd.polygon(pts, fill=255)
    flap = flap.resize((S, S), Image.LANCZOS)
    shadow = flap.filter(ImageFilter.GaussianBlur(10))
    shadow = ImageChops.offset(shadow, -8, 10)
    out = Image.alpha_composite(out, solid((0, 0, 0), ImageChops.multiply(shadow, mask), 0.55))
    flap_y = np.clip((y - y0) / fold, 0, 1)
    flap_v = 214 - 76 * flap_y
    out = Image.alpha_composite(out, with_alpha(np.stack([flap_v, flap_v + 3, flap_v + 8], axis=2), np.array(flap).astype(np.float32) * 0.96))
    flap_edge = ImageChops.subtract(flap, flap.filter(ImageFilter.MinFilter(5)))
    out = Image.alpha_composite(out, solid((255, 255, 255), flap_edge, 0.85))
    return out


def layer_chevron() -> Image.Image:
    """The champagne chevron with rounded ends, standing proud of the glass."""
    big = Image.new("L", (S * SS, S * SS), 0)
    d = ImageDraw.Draw(big)
    cx, cy, half_w, h, width = 512, 494, 100, 92, 42
    pts = [((cx - half_w) * SS, (cy - h / 2) * SS), (cx * SS, (cy + h / 2) * SS), ((cx + half_w) * SS, (cy - h / 2) * SS)]
    d.line(pts, fill=255, width=width * SS, joint="curve")
    for p in (pts[0], pts[-1]):
        d.ellipse([p[0] - width / 2 * SS, p[1] - width / 2 * SS, p[0] + width / 2 * SS, p[1] + width / 2 * SS], fill=255)
    mask = big.resize((S, S), Image.LANCZOS)
    y = np.mgrid[0:S, 0:S][0].astype(np.float32)
    t = np.clip((y - (cy - 40)) / 120, 0, 1)
    r = lerp_stops(t, [(0, CHAMPAGNE_LIGHT[0]), (0.5, CHAMPAGNE_MID[0]), (1, CHAMPAGNE_DARK[0])])
    g = lerp_stops(t, [(0, CHAMPAGNE_LIGHT[1]), (0.5, CHAMPAGNE_MID[1]), (1, CHAMPAGNE_DARK[1])])
    b = lerp_stops(t, [(0, CHAMPAGNE_LIGHT[2]), (0.5, CHAMPAGNE_MID[2]), (1, CHAMPAGNE_DARK[2])])
    body = with_alpha(np.stack([r, g, b], axis=2), mask)
    shadow = ImageChops.offset(mask.filter(ImageFilter.GaussianBlur(7)), 0, 9)
    out = Image.alpha_composite(solid((0, 0, 0), shadow, 0.5), body)
    rim = ImageChops.subtract(mask, mask.filter(ImageFilter.MinFilter(5)))
    return Image.alpha_composite(out, solid((255, 250, 236), rim, 0.55))


LAYER_FUNCS = {
    "bezel": layer_bezel,
    "chamber": layer_chamber,
    "ticks": layer_ticks,
    "slot": layer_slot,
    "glass": layer_glass,
    "chevron": layer_chevron,
}


def flat_composite(layers: dict[str, Image.Image]) -> Image.Image:
    """All layers back to front, edge to edge in a squircle, for the fallback PNG and the README."""
    base = Image.new("RGBA", (S, S), (0, 0, 0, 255))
    for name in BACK_TO_FRONT:
        base = Image.alpha_composite(base, layers[name])
    mask = superellipse_mask(C, C, 5.0)
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    out.paste(base, (0, 0), mask)
    return out


def main() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    for stale in ("slab.png", "tray.png"):
        (ASSETS / stale).unlink(missing_ok=True)
    layers = {}
    for name, fn in LAYER_FUNCS.items():
        layers[name] = fn()
        layers[name].save(ASSETS / f"{name}.png", optimize=True)
    flat = flat_composite(layers)
    flat.save(ROOT / "Resources" / "AppIcon-1024.png", optimize=True)
    flat.save(ROOT / "docs" / "images" / "quick-drop-zone-icon.png", optimize=True)
    print("wrote layers:", ", ".join(BACK_TO_FRONT), "and the flat 1024px icon")


if __name__ == "__main__":
    main()
