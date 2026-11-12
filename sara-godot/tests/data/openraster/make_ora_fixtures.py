#!/usr/bin/env python3
"""Writes the two OpenRaster fixtures that Sara did not write itself.

`krita_like.ora` is shaped the way Krita writes a file: a nested stack with its
own offset and isolation, a hidden layer, layers placed by `x` and `y`, an
operator Sara has no mode for, a sixteen-bit layer, a layer whose `src` is not
in the zip, a thumbnail and a merged image. `gimp_like.ora` is shaped the way
GIMP writes one: a single stack, no thumbnail, no merged image, and a layer
with no `composite-op` at all.

Every pixel is a flat colour, so the suite can name the texel it expects from
the numbers below. Run from anywhere, it writes beside itself:

    python3 sara-godot/tests/data/openraster/make_ora_fixtures.py
"""

import struct
import zipfile
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent

# The sixteen-bit layer's samples, chosen so that eight bits cannot carry them:
# 0x1234 is 4660 of 65535, and the nearest eight-bit value is 18 of 255,
# 4626 when widened, which the suite tells apart.
SIXTEEN = (0x1234, 0x8001, 0xFEDC, 0xFFFF)


def png(width, height, pixel, bits=8, alpha=True):
    """A PNG of one flat colour, *pixel* a tuple of samples at *bits*."""
    colour_type = 6 if alpha else 2
    channels = 4 if alpha else 3
    sample = ">H" if bits == 16 else ">B"
    row = b"".join(struct.pack(sample, value) for value in pixel[:channels]) * width
    raw = b"".join(b"\x00" + row for _ in range(height))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, bits, colour_type, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")


def write(name, stack, entries, extras=()):
    """The zip, `mimetype` first and stored as the format asks."""
    with zipfile.ZipFile(HERE / name, "w") as archive:
        archive.writestr(zipfile.ZipInfo("mimetype"), "image/openraster", compress_type=zipfile.ZIP_STORED)
        archive.writestr("stack.xml", stack, compress_type=zipfile.ZIP_DEFLATED)
        for entry, data in list(entries) + list(extras):
            archive.writestr(entry, data, compress_type=zipfile.ZIP_STORED)


KRITA_STACK = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE image>
<image w="64" h="48" xres="300" yres="300" version="0.0.1" name="krita_like">
 <stack>
  <layer name="Sixteen" src="data/layer4.png" x="40" y="4" opacity="1" visibility="visible" composite-op="svg:src-over" selected="true"/>
  <stack name="Group" x="2" y="2" opacity="0.5" visibility="visible" composite-op="svg:src-over" isolation="isolate">
   <layer name="Hidden" src="data/layer3.png" x="10" y="10" opacity="1" visibility="hidden" composite-op="svg:multiply"/>
   <layer name="Xor" src="data/layer2.png" x="0" y="0" opacity="0.75" visibility="visible" composite-op="svg:xor"/>
  </stack>
  <layer name="Missing" src="data/layer9.png" x="0" y="0" opacity="1" visibility="visible" composite-op="svg:src-over"/>
  <layer name="Background" src="data/layer1.png" x="0" y="0" opacity="1" visibility="visible" composite-op="svg:src-over"/>
 </stack>
</image>
"""

GIMP_STACK = """<?xml version='1.0' encoding='UTF-8'?>
<image w="40" h="30">
  <stack opacity="1" name="root" visibility="visible" composite-op="svg:src-over" isolation="isolate">
    <layer opacity="1" name="Screen" src="data/screen.png" visibility="visible" x="20" y="10" composite-op="svg:screen"/>
    <layer opacity="1" name="Plain" src="data/plain.png" visibility="visible" x="0" y="0"/>
  </stack>
</image>
"""


def main():
    background = png(64, 48, (230, 220, 200), alpha=False)
    write(
        "krita_like.ora",
        KRITA_STACK,
        [
            ("data/layer1.png", background),
            ("data/layer2.png", png(4, 4, (0, 200, 0, 255))),
            ("data/layer3.png", png(4, 4, (200, 0, 0, 255))),
            ("data/layer4.png", png(8, 8, SIXTEEN, bits=16)),
        ],
        [("Thumbnails/thumbnail.png", png(64, 48, (128, 128, 128, 255))), ("mergedimage.png", background)],
    )
    write(
        "gimp_like.ora",
        GIMP_STACK,
        [
            ("data/screen.png", png(10, 10, (0, 0, 255, 128))),
            ("data/plain.png", png(40, 30, (255, 255, 0, 255))),
        ],
    )


if __name__ == "__main__":
    main()
