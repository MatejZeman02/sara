#!/usr/bin/env python3
"""Writes the three ICC profiles an export names its gamut with.

sRGB, Display P3 and Rec. 2020, each a matrix and curve display profile at
version 2.4, because a v4 profile is still refused by readers that predate it,
which are the readers an `iCCP` chunk is there for. Every profile carries the
sRGB curve, since every 8-bit export Sara writes is the document's gamut through
that curve: the picker's triple, which is what a painted `1, 0, 0` is.

Generated rather than copied so the numbers have one source anyone can read:
the primaries and the white are the ones `core/api/color/sa_gamut.gd` and
`core/api/color/sa_color_space.gd` declare, adapted to the D50 connection space by
Bradford the way `SaColorSpace.adaptation` does. The output is byte for byte the
same on every run, so `--check` can say whether the committed files are stale.

    python3 scripts/gen_icc_profiles.py          # rewrite assets/icc/
    python3 scripts/gen_icc_profiles.py --check  # exit 1 when a file differs
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "icc"

# Sara's D65, to six places for the reason sa_color_space.gd gives.
WHITE_D65 = (0.312727, 0.329023)
# The ICC connection space's illuminant, exactly as the specification writes it.
D50_XYZ = (0.9642, 1.0, 0.8249)

BRADFORD = (
    (0.8951, 0.2664, -0.1614),
    (-0.7502, 1.7135, 0.0367),
    (0.0389, -0.0685, 1.0296),
)

# Profile id, the description a reader shows, and the three primaries in CIE xy.
PROFILES = (
    ("srgb", "Sara sRGB", ((0.640, 0.330), (0.300, 0.600), (0.150, 0.060))),
    ("display_p3", "Sara Display P3", ((0.680, 0.320), (0.265, 0.690), (0.150, 0.060))),
    ("rec2020", "Sara Rec. 2020 with the sRGB curve", ((0.708, 0.292), (0.170, 0.797), (0.131, 0.046))),
)

COPYRIGHT = "No copyright, use freely. Written by Sara's scripts/gen_icc_profiles.py."
CURVE_ENTRIES = 1024


def xy_to_xyz(xy: tuple[float, float]) -> tuple[float, float, float]:
    x, y = xy
    return (x / y, 1.0, (1.0 - x - y) / y)


def mat_mul(a, b):
    return tuple(tuple(sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)) for i in range(3))


def mat_vec(a, v):
    return tuple(sum(a[i][k] * v[k] for k in range(3)) for i in range(3))


def mat_inv(m):
    (a, b, c), (d, e, f), (g, h, i) = m
    det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    return (
        ((e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det),
        ((f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det),
        ((d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det),
    )


def rgb_to_xyz(primaries, white_xy):
    """The columns are the primaries scaled so that 1, 1, 1 is the white."""
    columns = [xy_to_xyz(p) for p in primaries]
    p = tuple(tuple(columns[j][i] for j in range(3)) for i in range(3))
    scale = mat_vec(mat_inv(p), xy_to_xyz(white_xy))
    return tuple(tuple(p[i][j] * scale[j] for j in range(3)) for i in range(3))


def bradford(source_xyz, target_xyz):
    cone_source = mat_vec(BRADFORD, source_xyz)
    cone_target = mat_vec(BRADFORD, target_xyz)
    ratio = tuple(tuple(cone_target[i] / cone_source[i] if i == j else 0.0 for j in range(3)) for i in range(3))
    return mat_mul(mat_inv(BRADFORD), mat_mul(ratio, BRADFORD))


def s15f16(value: float) -> bytes:
    return struct.pack(">i", int(round(value * 65536.0)))


def srgb_decode(value: float) -> float:
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def pad4(data: bytes) -> bytes:
    return data + b"\0" * (-len(data) % 4)


def tag_desc(text: str) -> bytes:
    ascii_text = text.encode("ascii") + b"\0"
    body = b"desc" + b"\0" * 4 + struct.pack(">I", len(ascii_text)) + ascii_text
    # No Unicode and no ScriptCode description: their counts are zero, and the
    # 67 bytes after the ScriptCode count are required whatever it says.
    body += struct.pack(">II", 0, 0) + struct.pack(">HB", 0, 0) + b"\0" * 67
    return body


def tag_text(text: str) -> bytes:
    return b"text" + b"\0" * 4 + text.encode("ascii") + b"\0"


def tag_xyz(xyz) -> bytes:
    return b"XYZ " + b"\0" * 4 + b"".join(s15f16(v) for v in xyz)


def tag_sf32(matrix) -> bytes:
    return b"sf32" + b"\0" * 4 + b"".join(s15f16(v) for row in matrix for v in row)


def tag_curve() -> bytes:
    entries = [int(round(srgb_decode(i / (CURVE_ENTRIES - 1)) * 65535.0)) for i in range(CURVE_ENTRIES)]
    return b"curv" + b"\0" * 4 + struct.pack(">I", CURVE_ENTRIES) + struct.pack(">%dH" % CURVE_ENTRIES, *entries)


def profile(description: str, primaries) -> bytes:
    chad = bradford(xy_to_xyz(WHITE_D65), D50_XYZ)
    adapted = mat_mul(chad, rgb_to_xyz(primaries, WHITE_D65))
    curve = tag_curve()
    # The three curves are one block of bytes that three tags point at, which
    # the specification allows and every matrix profile in the wild does.
    tags = [
        (b"desc", tag_desc(description)),
        (b"cprt", tag_text(COPYRIGHT)),
        (b"wtpt", tag_xyz(D50_XYZ)),
        (b"chad", tag_sf32(chad)),
        (b"rXYZ", tag_xyz(tuple(adapted[i][0] for i in range(3)))),
        (b"gXYZ", tag_xyz(tuple(adapted[i][1] for i in range(3)))),
        (b"bXYZ", tag_xyz(tuple(adapted[i][2] for i in range(3)))),
        (b"rTRC", curve),
        (b"gTRC", curve),
        (b"bTRC", curve),
    ]
    table_bytes = 4 + 12 * len(tags)
    offset = 128 + table_bytes
    table = struct.pack(">I", len(tags))
    data = b""
    placed: dict[bytes, int] = {}
    for signature, body in tags:
        if body not in placed:
            placed[body] = offset + len(data)
            data += pad4(body)
        table += signature + struct.pack(">II", placed[body], len(body))
    size = 128 + table_bytes + len(data)
    header = struct.pack(">I", size)
    header += b"\0" * 4  # no preferred CMM
    header += struct.pack(">I", 0x02400000)
    header += b"mntr" + b"RGB " + b"XYZ "
    header += struct.pack(">6H", 2026, 9, 11, 0, 0, 0)
    header += b"acsp"
    header += b"\0" * 4  # no primary platform
    header += b"\0" * 4  # flags
    header += b"\0" * 8  # manufacturer and model
    header += b"\0" * 8  # attributes
    header += struct.pack(">I", 0)  # perceptual
    header += b"".join(s15f16(v) for v in D50_XYZ)
    header += b"\0" * 4  # creator
    header += b"\0" * (128 - len(header))
    return header + table + data


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="exit 1 when a committed profile differs")
    args = parser.parse_args()
    stale = []
    for profile_id, description, primaries in PROFILES:
        path = OUT / f"{profile_id}.icc"
        wanted = profile(description, primaries)
        if args.check:
            if not path.exists() or path.read_bytes() != wanted:
                stale.append(path)
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(wanted)
        print(f"wrote {path.relative_to(ROOT)} ({len(wanted)} bytes)")
    if stale:
        for path in stale:
            print(f"stale: {path.relative_to(ROOT)}", file=sys.stderr)
        return 1
    if args.check:
        print(f"{len(PROFILES)} profile(s) current")
    return 0


if __name__ == "__main__":
    sys.exit(main())
