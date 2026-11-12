#!/usr/bin/env python3
"""Make `pear_mask.png`, the shape of the pear in `pear.jpg`, for the
Magnetic Lasso's suite.

    cd sara-godot/modules/sara-base-modules/base/magnetic/tests/fixtures
    python make_pear_mask.py

The ground is a white card, so the pear is every pixel with more Oklab chroma
than 0.06, and the stem, a dark brown nearer grey, every pixel darker than an
Oklab lightness of 0.6 above row 250. Below that row the dark is the pear's
contact shadow, which is no part of it. One opening takes the card's speckle
off, the largest region is kept and its holes filled. The outline it gives
was read by eye over the photograph, the stem and the base above all.
"""

from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = Path(__file__).resolve().parent
CHROMA = 0.06
DARK = 0.6
STEM_ROWS = 250

TO_LMS = np.array(
    [
        [0.4122214708, 0.5363325363, 0.0514459929],
        [0.2119034982, 0.6806995451, 0.1073969566],
        [0.0883024619, 0.2817188376, 0.6299787005],
    ]
)
TO_LAB = np.array(
    [
        [0.2104542553, 0.7936177850, -0.0040720468],
        [1.9779984951, -2.4285922050, 0.4505937099],
        [0.0259040371, 0.7827717662, -0.8086757660],
    ]
)


def main() -> None:
    rgb = np.asarray(Image.open(HERE / "pear.jpg").convert("RGB")).astype(np.float64) / 255.0
    linear = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    lab = np.cbrt(linear @ TO_LMS.T) @ TO_LAB.T
    chroma = np.hypot(lab[..., 1], lab[..., 2])
    rows = np.arange(rgb.shape[0])[:, None] * np.ones((1, rgb.shape[1]))
    mask = (chroma > CHROMA) | ((lab[..., 0] < DARK) & (rows < STEM_ROWS))
    mask = ndimage.binary_opening(mask, iterations=1)
    labels, count = ndimage.label(mask)
    sizes = ndimage.sum(mask, labels, range(1, count + 1))
    mask = ndimage.binary_fill_holes(labels == 1 + int(np.argmax(sizes)))
    Image.fromarray((mask * 255).astype(np.uint8)).save(HERE / "pear_mask.png")


if __name__ == "__main__":
    main()
