#!/usr/bin/env python3
"""Makes Android's adaptive icon layers from `ui/icon.png`.

    cd sara-godot && python3 ui/android-icon/make_android_icon.py

A launcher shows only the middle of an adaptive icon's 108 dp layer and
masks it to a shape of its own, a circle on most tablets. Android promises
that the centred circle of 66 dp is never cut, so the foreground holds the
whole logo inside that circle, 264 of the layer's 432 pixels across, with a
few pixels of margin so resampling never puts a soft edge outside it. The
background is the plain colour of the logo's own ground, so the mask cuts
only ground. The monochrome layer is the logo's light marks in one colour on
transparency, which a themed launcher tints. A new logo makes all three
again by running this script.
"""

from __future__ import annotations

import math
from collections import Counter
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent / "icon.png"
SIZE = 432
SAFE_DIAMETER = 264
MARGIN = 4
FOREGROUND = HERE / "foreground.png"
BACKGROUND = HERE / "background.png"
MONOCHROME = HERE / "monochrome.png"


def logo_radius(logo: Image.Image) -> tuple[float, float, float]:
    """The centre of the logo's opaque pixels' box and the farthest any
    pixel with alpha lies from it."""
    left, top, right, bottom = logo.getchannel("A").getbbox()
    cx, cy = (left + right) / 2, (top + bottom) / 2
    alpha = logo.getchannel("A").load()
    far = 0.0
    for y in range(top, bottom):
        for x in range(left, right):
            if alpha[x, y]:
                far = max(far, math.hypot(x + 0.5 - cx, y + 0.5 - cy))
    return cx, cy, far


def ground_colour(logo: Image.Image) -> tuple[int, int, int]:
    """The commonest colour among the fully opaque pixels."""
    counts = Counter(p[:3] for p in logo.getdata() if p[3] == 255)
    return counts.most_common(1)[0][0]


def placed(picture: Image.Image, cx: float, cy: float, far: float) -> Image.Image:
    """The picture scaled so its circle of radius `far` round (cx, cy) sits
    centred in the safe circle less the margin, on a transparent layer."""
    scale = (SAFE_DIAMETER / 2 - MARGIN) / far
    side = max(1, round(picture.width * scale))
    small = picture.resize((side, side), Image.LANCZOS)
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    offset = (round(SIZE / 2 - cx * scale), round(SIZE / 2 - cy * scale))
    layer.alpha_composite(small, offset)
    return layer


def marks(logo: Image.Image, ground: tuple[int, int, int]) -> Image.Image:
    """White wherever the logo is lighter than its ground, its alpha the
    distance from the ground, so the marks keep their soft edges."""
    out = Image.new("RGBA", logo.size, (255, 255, 255, 0))
    src = logo.load()
    dst = out.load()
    for y in range(logo.height):
        for x in range(logo.width):
            r, g, b, a = src[x, y]
            lift = max(abs(r - ground[0]), abs(g - ground[1]), abs(b - ground[2]))
            strength = min(1.0, max(0.0, (lift - 40) / 80))
            dst[x, y] = (255, 255, 255, round(strength * a))
    return out


def main() -> None:
    logo = Image.open(SOURCE).convert("RGBA")
    cx, cy, far = logo_radius(logo)
    ground = ground_colour(logo)
    placed(logo, cx, cy, far).save(FOREGROUND, optimize=True)
    Image.new("RGBA", (SIZE, SIZE), ground + (255,)).save(BACKGROUND, optimize=True)
    mono = placed(marks(logo, ground), cx, cy, far)
    alpha = mono.getchannel("A")
    mono = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    mono.putalpha(alpha)
    mono.save(MONOCHROME, optimize=True)


if __name__ == "__main__":
    main()
