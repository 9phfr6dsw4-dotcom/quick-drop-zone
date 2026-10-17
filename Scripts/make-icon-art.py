#!/usr/bin/env python3
"""Draws Quick Drop Zone's icon artwork: the layers of Resources/AppIcon.icon and the flat
1024px fallback (Resources/AppIcon-1024.png, docs/images/quick-drop-zone-icon.png).

Developer tool, not part of CI. Needs Pillow and numpy:  python3 Scripts/make-icon-art.py
macOS draws the rounded shape, the edge shine and the glass itself, so the layers carry no
rounded-square outline and no shadow; they sit on a full 1024x1024 canvas.
"""
from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Resources" / "AppIcon.icon" / "Assets"
S = 1024
SS = 2  # supersampling for the shapes

# Palette: gunmetal slab, champagne brass, frosted glass, warm white light.
STEEL_TOP = (128, 134, 142)
STEEL_BOTTOM = (26, 28, 33)
BRASS_LIGHT = (240, 222, 168)
BRASS_MID = (201, 171, 108)
BRASS_DARK = (122, 96, 52)
GLOW = (255, 240, 205)

rng = np.random.default_rng(20261017)
FOREGROUND_SCALE = 1.14
SHIFT_Y = 0


def shifted(mask: Image.Image, dy: int) -> Image.Image:
    out = Image.new("L", mask.size, 0)
    out.paste(mask, (0, dy))
    return out


def canvas() -> Image.Image:
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


def rrect_mask(box, radius, size=S) -> Image.Image:
    big = Image.new("L", (size * SS, size * SS), 0)
    d = ImageDraw.Draw(big)
    d.rounded_rectangle([c * SS for c in box], radius=radius * SS, fill=255)
    return big.resize((size, size), Image.LANCZOS)


def vgradient(size, top, bottom) -> Image.Image:
    w, h = size
    t = np.linspace(0, 1, h)[:, None, None]
    top_a, bot_a = np.array(top, float), np.array(bottom, float)
    arr = (top_a * (1 - t) + bot_a * t) * np.ones((1, w, 1))
    return Image.fromarray(arr.astype(np.uint8), "RGB")


def with_mask(rgb: Image.Image, mask: Image.Image) -> Image.Image:
    out = rgb.convert("RGBA")
    out.putalpha(mask)
    return out


def brushed_plate() -> Image.Image:
    """The dark face of the slab: spun (circular) brushed metal with a soft conic sheen."""
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    cx, cy = S / 2, S / 2
    r = np.hypot(xx - cx, yy - cy)
    theta = np.arctan2(yy - cy, xx - cx)
    rings = rng.normal(0, 1, 1500).astype(np.float32)
    rings = np.convolve(rings, np.ones(3) / 3, mode="same")
    ring_val = rings[np.clip((r * 1.6).astype(int), 0, 1499)]
    grain = rng.normal(0, 1, (S, S)).astype(np.float32)
    sheen = 0.5 + 0.5 * np.cos(2 * theta - 0.9)  # two opposite light wedges
    base = 34 + 22 * sheen * np.clip(r / 520, 0.25, 1) + 5.5 * ring_val + 2.2 * grain
    top_light = np.clip(1.15 - yy / S * 0.9, 0.55, 1.15)  # lit from the top
    v = np.clip(base * top_light, 0, 255)
    rgb = np.stack([v * 0.99, v * 1.0, v * 1.04], axis=2)
    return Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB")


def layer_slab() -> Image.Image:
    """Layer 1: the brushed dark face, set into the polished steel edge (the icon's fill)."""
    inset, radius = 44, 190
    box = (inset, inset, S - inset, S - inset)
    mask = rrect_mask(box, radius)
    face = with_mask(brushed_plate(), mask)
    # A fine bright line where the face meets the steel edge, and a darker line inside it.
    outer = rrect_mask(box, radius)
    inner = rrect_mask((inset + 5, inset + 5, S - inset - 5, S - inset - 5), radius - 5)
    ring = ImageChops.subtract(outer, inner)
    glint = Image.new("RGBA", (S, S), (214, 220, 228, 0))
    glint.putalpha(ring.point(lambda p: int(p * 0.55)))
    out = Image.alpha_composite(face, glint)
    inner2 = rrect_mask((inset + 5, inset + 5, S - inset - 5, S - inset - 5), radius - 5)
    inner3 = rrect_mask((inset + 12, inset + 12, S - inset - 12, S - inset - 12), radius - 12)
    shade = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shade.putalpha(ImageChops.subtract(inner2, inner3).point(lambda p: int(p * 0.55)))
    return Image.alpha_composite(out, shade)


def layer_ticks() -> Image.Image:
    """Layer 2: ruler marks around the tray, like a precision instrument."""
    img = canvas()
    d = ImageDraw.Draw(img)
    color = (222, 198, 142, 150)
    major = (232, 210, 156, 215)
    # left and right edges (horizontal ticks), bottom edge (vertical ticks)
    for i, y in enumerate(range(262, 790, 16)):
        long = i % 5 == 0
        c = major if long else color
        n = 30 if long else 17
        d.line([(262 - n, y), (262, y)], fill=c, width=3)
        d.line([(762, y), (762 + n, y)], fill=c, width=3)
    for i, x in enumerate(range(336, 700, 16)):
        long = i % 5 == 0
        c = major if long else color
        n = 30 if long else 17
        d.line([(x, 806), (x, 806 + n)], fill=c, width=3)
    return img


def layer_tray() -> Image.Image:
    """Layer 3: the champagne-brass bezel around a recessed steel mesh."""
    box = (320, 250, 704, 800)
    radius = 82
    out = canvas()
    bezel_mask = rrect_mask(box, radius)
    bezel = with_mask(vgradient((S, S), BRASS_LIGHT, BRASS_DARK), bezel_mask)
    out = Image.alpha_composite(out, bezel)
    # Fine polished lip on the very top edge of the bezel.
    lip_mask = ImageChops.subtract(bezel_mask, rrect_mask((320, 254, 704, 800), radius))
    lip = Image.new("RGBA", (S, S), (255, 248, 226, 0))
    lip.putalpha(lip_mask.point(lambda p: int(p * 0.9)))
    out = Image.alpha_composite(out, lip)
    # Recess: dark, with a mesh of tiny holes.
    ib = (340, 270, 684, 780)
    recess_mask = rrect_mask(ib, 64)
    recess = vgradient((S, S), (14, 15, 18), (30, 32, 37))
    px = np.array(recess).astype(np.float32)
    yy, xx = np.mgrid[0:S, 0:S]
    pitch = 9
    hole = ((xx % pitch) - pitch / 2) ** 2 + ((yy % pitch) - pitch / 2) ** 2 < 5.2
    px[hole] = px[hole] * 0.30
    px[~hole] = px[~hole] * 0.9 + np.array([120, 126, 134]) * 0.36
    recess = Image.fromarray(np.clip(px, 0, 255).astype(np.uint8), "RGB")
    out = Image.alpha_composite(out, with_mask(recess, recess_mask))
    # Inner shadow along the top of the recess so it reads as sunk.
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sh = ImageChops.subtract(recess_mask, rrect_mask((340, 292, 684, 790), 64))
    shadow.putalpha(sh.point(lambda p: int(p * 0.7)).filter(ImageFilter.GaussianBlur(5)))
    out = Image.alpha_composite(out, shadow)
    # LED slot at the bottom of the tray.
    led = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ld = ImageDraw.Draw(led)
    ld.rounded_rectangle((448, 728, 576, 744), radius=8, fill=(255, 248, 232, 255))
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle((440, 722, 584, 750), radius=14, fill=GLOW + (210,))
    glow = glow.filter(ImageFilter.GaussianBlur(14))
    out = Image.alpha_composite(out, glow)
    return Image.alpha_composite(out, led)


def layer_glass() -> Image.Image:
    """Layer 4: the frosted-glass document tile, lifted above the tray. macOS adds the glass shine."""
    box = (378, 292, 646, 692)
    snip = 70
    big = Image.new("L", (S * SS, S * SS), 0)
    d = ImageDraw.Draw(big)
    d.rounded_rectangle([c * SS for c in box], radius=36 * SS, fill=255)
    # cut the top-right corner off diagonally
    x1, y0 = box[2], box[1]
    d.polygon([((x1 - snip) * SS, (y0 - 2) * SS), ((x1 + 2) * SS, (y0 - 2) * SS), ((x1 + 2) * SS, (y0 + snip) * SS)], fill=0)
    mask = big.resize((S, S), Image.LANCZOS)
    body = with_mask(vgradient((S, S), (226, 231, 238), (132, 139, 150)), mask.point(lambda p: int(p * 0.82)))
    out = Image.alpha_composite(canvas(), body)
    # Bright glass edge, strongest along the top and left, softer elsewhere.
    edge = ImageChops.subtract(mask, mask.filter(ImageFilter.MinFilter(7)))
    rim = Image.new("RGBA", (S, S), (246, 249, 252, 0))
    rim.putalpha(edge.point(lambda p: int(p * 0.85)))
    out = Image.alpha_composite(out, rim)
    # Thick-glass look: a lighter band inside the top edge.
    inner = ImageChops.subtract(mask.filter(ImageFilter.MinFilter(7)), mask.filter(ImageFilter.MinFilter(25)))
    band = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    band.putalpha(inner.filter(ImageFilter.GaussianBlur(5)).point(lambda p: int(p * 0.22)))
    out = Image.alpha_composite(out, band)
    # The folded corner: a lighter triangle with a crisp edge.
    fold = Image.new("RGBA", (S * SS, S * SS), (0, 0, 0, 0))
    ImageDraw.Draw(fold).polygon([((x1 - snip) * SS, y0 * SS), ((x1 - snip) * SS, (y0 + snip) * SS), (x1 * SS, (y0 + snip) * SS)], fill=(240, 244, 249, 150))
    out = Image.alpha_composite(out, fold.resize((S, S), Image.LANCZOS))
    return out


def layer_chevron() -> Image.Image:
    """Layer 5: the brass down-chevron, standing on the glass."""
    img = canvas()
    big = Image.new("RGBA", (S * SS, S * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    pts = [(468 * SS, 500 * SS), (512 * SS, 546 * SS), (556 * SS, 500 * SS)]
    d.line(pts, fill=BRASS_LIGHT + (255,), width=17 * SS, joint="curve")
    for p in (pts[0], pts[-1]):
        d.ellipse([p[0] - 8.5 * SS, p[1] - 8.5 * SS, p[0] + 8.5 * SS, p[1] + 8.5 * SS], fill=BRASS_LIGHT + (255,))
    img = big.resize((S, S), Image.LANCZOS)
    shade = img.filter(ImageFilter.GaussianBlur(4))
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow.putalpha(shade.split()[3].point(lambda p: int(p * 0.45)))
    shadow = ImageChops.offset(shadow, 0, 6)  # layer is transparent at the edges, so wrapping is harmless
    return Image.alpha_composite(shadow, img)


LAYERS = {
    "slab": layer_slab,
    "ticks": layer_ticks,
    "tray": layer_tray,
    "glass": layer_glass,
    "chevron": layer_chevron,
}


def squircle_mask(size=S, n=5.0) -> Image.Image:
    """A continuous-corner rounded square close to macOS's shape, filling the whole canvas."""
    c = (size * SS - 1) / 2
    y, x = np.mgrid[0:size * SS, 0:size * SS].astype(np.float32)
    v = (np.abs((x - c) / c) ** n + np.abs((y - c) / c) ** n) <= 1.0
    big = Image.fromarray((v * 255).astype(np.uint8), "L")
    return big.resize((size, size), Image.LANCZOS)


def flat_composite(layers: dict[str, Image.Image]) -> Image.Image:
    """Stacks the layers on the steel fill, edge to edge, for the fallback PNG and previews."""
    base = with_mask(vgradient((S, S), STEEL_TOP, STEEL_BOTTOM), Image.new("L", (S, S), 255))
    for name in LAYERS:
        base = Image.alpha_composite(base, layers[name])
    mask = squircle_mask()
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    out.paste(base, (0, 0), mask)
    # Soft top-edge light, as macOS would add.
    sheen = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    top = ImageChops.subtract(mask, shifted(mask, 5)).filter(ImageFilter.GaussianBlur(1.2))
    sheen.putalpha(top.point(lambda p: min(255, int(p * 2.4))))
    return Image.alpha_composite(out, sheen)


def main() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    layers = {}
    for name, fn in LAYERS.items():
        art = fn()
        if name != "slab":  # the slab already spans the canvas; the rest grow around the centre
            n = round(S * FOREGROUND_SCALE)
            art = art.resize((n, n), Image.LANCZOS)
            full = canvas()
            full.alpha_composite(art, ((S - n) // 2, (S - n) // 2 + SHIFT_Y)) if n <= S else full.paste(art.crop(((n - S) // 2, (n - S) // 2, (n - S) // 2 + S, (n - S) // 2 + S)), (0, 0))
            art = full
        layers[name] = art
        art.save(ASSETS / f"{name}.png", optimize=True)
    flat = flat_composite(layers)
    flat.save(ROOT / "Resources" / "AppIcon-1024.png", optimize=True)
    flat.save(ROOT / "docs" / "images" / "quick-drop-zone-icon.png", optimize=True)
    print("wrote layers:", ", ".join(LAYERS), "and the flat 1024px icon")


if __name__ == "__main__":
    main()
