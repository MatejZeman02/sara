#!/usr/bin/env python3
"""Read a shot from `sara_shot.py` against the record committed for it.

    python3 sara-godot/scripts/shot_diff.py <shot.png> <record.png>
    python3 sara-godot/scripts/shot_diff.py <shot.png> <record.png> --tolerance 6
    python3 sara-godot/scripts/shot_diff.py <shot-dir> tests/shots/<scenario>

Until this file, nothing in the tree ever opened a shot again. `sara_shot.py`
writes the pictures and `test_shot_problems.py` reads the run log, so the only
thing a capture proved automatically was that the app had not printed an error.
Every picture was read by a person or by nobody.

**Two GPUs are not bit-identical, so the answer is a count and not a bit.** A
texel counts as different when its largest per-channel distance from the record
is over `--tolerance`, and the check fails when more than `--max-texels` of them
are. The defaults are `TOLERANCE` and 0 below: one texel that moves further than
the tolerance is a regression, and any number of texels that stay inside it is
the same picture drawn by a different driver.

**The standard library alone**, `zlib` and `struct`, because the gate has to run
on a machine with neither Pillow nor numpy, and because a check that needs a
wheel is a check that is skipped. That costs a decoder for the one PNG shape
Godot writes, 8 bits a channel and no interlacing, and the decoder says so
rather than guessing when it meets anything else.

The difference picture goes beside the shot as `<shot>.diff.png`: the record
washed out to a pale grey, every differing texel in red, and a cyan box around
the region that holds them, because a single red texel in a 1280 by 800 frame
is not something an eye finds.
"""

from __future__ import annotations

import argparse
import struct
import sys
import zlib
from pathlib import Path

# Eight bits a channel is a distance of 1 in 255, and a shot is the compositor's
# own read of the frame rather than a photograph of it, so nothing drifts by
# rounding on one machine: run A against run B of the same scenario on this
# card differed by 0 everywhere. The number is headroom for the machine this was
# not written on, where a different driver rasterises a glyph's edge or a
# gradient's dither one step further. Six is small enough that a wrong colour
# cannot hide inside it, black on white being 255 apart, and large enough that
# an antialiased edge landing one step differently is not a failure.
TOLERANCE = 6

# The wash the difference picture puts the record under, so a red mark on it is
# the only saturated thing in the frame. 4 keeps a quarter of the record's own
# contrast, which is enough to recognise the layout and not enough to compete.
WASH = 4

# The same wash as a byte table, which is how it is actually applied: one
# `bytes.translate` over the whole picture instead of a million divisions.
WASH_TABLE = bytes(255 - (255 - value) // WASH for value in range(256))

# What a difference picture is called, beside the shot it belongs to. It is a
# suffix rather than a folder because the pair belongs together in the review
# folder an agent looks at, and it is skipped by `pairs` for the same reason.
DIFF_SUFFIX = ".diff.png"

MARK = (255, 0, 0)
BOX = (0, 200, 255)

# The smallest the outline is drawn, whatever the region inside it measures. One
# red texel in a 1280 by 800 frame with a 3 by 3 box around it is still a dot
# nobody finds, and the first difference this file was ever pointed at in anger
# was exactly that. The box grows around the middle of the region, so it stays
# where the difference is.
BOX_MINIMUM = 24

PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
CHANNELS = {0: 1, 2: 3, 4: 2, 6: 4}


class ShotDiffError(Exception):
    """A picture this file will not read, or a pair it will not compare."""


class Picture:
    """An 8-bit picture: `width`, `height`, `channels` and one flat bytearray.

    Rows are `width * channels` bytes with no filter byte and no padding, which
    is what `read_png` unfilters into and what `write_png` filters back out of.
    """

    def __init__(self, width: int, height: int, channels: int, pixels: bytearray) -> None:
        expected = width * height * channels
        if len(pixels) != expected:
            raise ShotDiffError(f"{width}x{height} at {channels} channels wants {expected} bytes, got {len(pixels)}")
        self.width = width
        self.height = height
        self.channels = channels
        self.pixels = pixels

    def size(self) -> "tuple[int, int]":
        return self.width, self.height

    def texel(self, x: int, y: int) -> "tuple[int, ...]":
        start = (y * self.width + x) * self.channels
        return tuple(self.pixels[start : start + self.channels])


class Difference:
    """What `compare` found: the count, the worst texel, and where they are.

    `count` is texels over the tolerance, `worst` the largest per-channel
    distance anywhere in the frame including the ones under it, and `box` the
    bounding rectangle of the differing texels as `(x0, y0, x1, y1)` inclusive,
    or None when nothing differed.
    """

    def __init__(self, count: int, worst: int, worst_at: "tuple[int, int] | None", box, marks: bytearray) -> None:
        self.count = count
        self.worst = worst
        self.worst_at = worst_at
        self.box = box
        self.marks = marks

    def passes(self, max_texels: int) -> bool:
        return self.count <= max_texels


def read_png(path: Path) -> Picture:
    """Decode a PNG the way Godot writes one: 8 bits a channel, not interlaced.

    Anything else is refused by name rather than half decoded, because a
    silently wrong decode would make the comparison lie in the direction that
    passes.
    """
    data = Path(path).read_bytes()
    if not data.startswith(PNG_MAGIC):
        raise ShotDiffError(f"{path} is not a PNG")
    header = None
    body = bytearray()
    offset = len(PNG_MAGIC)
    while offset + 8 <= len(data):
        (length,) = struct.unpack(">I", data[offset : offset + 4])
        kind = data[offset + 4 : offset + 8]
        payload = data[offset + 8 : offset + 8 + length]
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", payload)
        elif kind == b"IDAT":
            body += payload
        elif kind == b"IEND":
            break
        offset += 12 + length
    if header is None:
        raise ShotDiffError(f"{path} has no IHDR chunk")
    width, height, depth, colour, compression, filtering, interlace = header
    if depth != 8:
        raise ShotDiffError(f"{path} is {depth} bits a channel, and this reads 8")
    if colour not in CHANNELS:
        raise ShotDiffError(f"{path} is colour type {colour}, and this reads {sorted(CHANNELS)}")
    if interlace != 0:
        raise ShotDiffError(f"{path} is interlaced, and this reads the plain form")
    if compression != 0 or filtering != 0:
        raise ShotDiffError(f"{path} uses compression {compression} and filter method {filtering}, and this reads 0")
    channels = CHANNELS[colour]
    return Picture(width, height, channels, unfilter(zlib.decompress(bytes(body)), width, height, channels))


def unfilter(raw: bytes, width: int, height: int, channels: int) -> bytearray:
    """Undo the five PNG row filters, which is where a decoder is usually wrong.

    Each row is one filter byte and then `width * channels` bytes, and every
    filter reads the row above and the texel `channels` bytes to the left, both
    of which are zero off the edge.
    """
    stride = width * channels
    if len(raw) != (stride + 1) * height:
        raise ShotDiffError(f"{height} rows of {stride} bytes want {(stride + 1) * height} decompressed, got {len(raw)}")
    out = bytearray(stride * height)
    previous = bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        kind = raw[start]
        row = bytearray(raw[start + 1 : start + 1 + stride])
        if kind == 1:
            for i in range(channels, stride):
                row[i] = (row[i] + row[i - channels]) & 0xFF
        elif kind == 2:
            for i in range(stride):
                row[i] = (row[i] + previous[i]) & 0xFF
        elif kind == 3:
            for i in range(stride):
                left = row[i - channels] if i >= channels else 0
                row[i] = (row[i] + ((left + previous[i]) >> 1)) & 0xFF
        elif kind == 4:
            for i in range(stride):
                left = row[i - channels] if i >= channels else 0
                up_left = previous[i - channels] if i >= channels else 0
                row[i] = (row[i] + paeth(left, previous[i], up_left)) & 0xFF
        elif kind != 0:
            raise ShotDiffError(f"row {y} has filter type {kind}, and PNG has five")
        out[y * stride : (y + 1) * stride] = row
        previous = row
    return out


def paeth(left: int, up: int, up_left: int) -> int:
    """PNG's fourth filter predictor, the one of the three neighbours nearest
    to `left + up - up_left`, ties going to the left one."""
    estimate = left + up - up_left
    distances = (abs(estimate - left), abs(estimate - up), abs(estimate - up_left))
    if distances[0] <= distances[1] and distances[0] <= distances[2]:
        return left
    if distances[1] <= distances[2]:
        return up
    return up_left


def write_png(path: Path, picture: Picture) -> None:
    """Write a picture back out, every row unfiltered.

    The difference picture is the only thing this writes and it is read by an
    eye, so nothing here chases the last few kilobytes: zlib over unfiltered
    rows is a tenth of the raw bytes on a picture that is mostly one grey.
    """
    colour = {1: 0, 2: 4, 3: 2, 4: 6}[picture.channels]
    stride = picture.width * picture.channels
    raw = bytearray()
    for y in range(picture.height):
        raw.append(0)
        raw += picture.pixels[y * stride : (y + 1) * stride]
    chunks = [
        chunk(b"IHDR", struct.pack(">IIBBBBB", picture.width, picture.height, 8, colour, 0, 0, 0)),
        chunk(b"IDAT", zlib.compress(bytes(raw), 6)),
        chunk(b"IEND", b""),
    ]
    Path(path).write_bytes(PNG_MAGIC + b"".join(chunks))


def chunk(kind: bytes, payload: bytes) -> bytes:
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)


def compare(shot: Picture, record: Picture, tolerance: int = TOLERANCE) -> Difference:
    """Count the texels of *shot* that are further than *tolerance* from *record*.

    The distance is the largest of the per-channel distances rather than their
    sum, so a tolerance is a number in the units a colour is written in: 6 means
    no channel may move by more than 6 in 255.

    **A texel is only looked at when its row is not already equal.** A million
    texels walked in Python is a second, and the gate's answer is almost always
    that nothing moved, so the whole buffer is compared first and then row by
    row. That is what keeps this suite beside the other four rather than making
    the phase it joins twice as long.
    """
    if shot.size() != record.size():
        raise ShotDiffError(f"the shot is {shot.width}x{shot.height} and the record is {record.width}x{record.height}")
    if shot.channels != record.channels:
        raise ShotDiffError(f"the shot has {shot.channels} channels and the record has {record.channels}")
    marks = bytearray(shot.width * shot.height)
    if shot.pixels == record.pixels:
        return Difference(0, 0, None, None, marks)
    count = 0
    worst = 0
    worst_at = None
    box = None
    channels = shot.channels
    stride = shot.width * channels
    for y in range(shot.height):
        row = y * stride
        if shot.pixels[row : row + stride] == record.pixels[row : row + stride]:
            continue
        for x in range(shot.width):
            start = row + x * channels
            distance = 0
            for offset in range(channels):
                step = abs(shot.pixels[start + offset] - record.pixels[start + offset])
                if step > distance:
                    distance = step
            if distance > worst:
                worst = distance
                worst_at = (x, y)
            if distance > tolerance:
                marks[y * shot.width + x] = min(distance, 255)
                count += 1
                box = (x, y, x, y) if box is None else (min(box[0], x), min(box[1], y), max(box[2], x), max(box[3], y))
    return Difference(count, worst, worst_at, box, marks)


def difference_picture(record: Picture, difference: Difference) -> Picture:
    """The record under a wash, the differing texels in red, a box around them.

    The wash is a byte table and a strided copy rather than a loop over texels,
    for the reason `compare` skips an equal row: a picture built one texel at a
    time in Python is a second of the gate for nothing. Each channel keeps its
    own value under the table, so a coloured record stays recognisably itself in
    pale, and the only saturated thing left in the frame is a mark.
    """
    width, height = record.size()
    washed = bytes(record.pixels).translate(WASH_TABLE)
    pixels = bytearray(width * height * 3)
    for channel in range(3):
        pixels[channel::3] = washed[(channel if record.channels >= 3 else 0) :: record.channels]
    for index, mark in enumerate(difference.marks):
        if mark:
            pixels[index * 3 : index * 3 + 3] = bytes(MARK)
    picture = Picture(width, height, 3, pixels)
    if difference.box is not None:
        draw_box(picture, difference.box)
    return picture


def draw_box(picture: Picture, box: "tuple[int, int, int, int]") -> None:
    """Outline *box* one texel outside itself, so no mark is painted over.

    A box that would fall off the edge is clipped there, which is why the
    marks are drawn first and the box second: on a difference in the top left
    texel the outline is two lines rather than four, and the marks are still all
    of them. A region under `BOX_MINIMUM` on a side is grown to it first, so a
    lone texel is ringed rather than hidden under its own outline.
    """
    x0, y0, x1, y1 = box
    x0, x1 = grow(x0, x1)
    y0, y1 = grow(y0, y1)
    x0, y0, x1, y1 = x0 - 1, y0 - 1, x1 + 1, y1 + 1
    for x in range(max(x0, 0), min(x1, picture.width - 1) + 1):
        for y in (y0, y1):
            if 0 <= y < picture.height:
                picture.pixels[(y * picture.width + x) * 3 : (y * picture.width + x) * 3 + 3] = bytes(BOX)
    for y in range(max(y0, 0), min(y1, picture.height - 1) + 1):
        for x in (x0, x1):
            if 0 <= x < picture.width:
                picture.pixels[(y * picture.width + x) * 3 : (y * picture.width + x) * 3 + 3] = bytes(BOX)


def grow(low: int, high: int) -> "tuple[int, int]":
    """*low* and *high* pushed apart to `BOX_MINIMUM` around their middle."""
    short = BOX_MINIMUM - (high - low + 1)
    if short <= 0:
        return low, high
    return low - short // 2, high + short - short // 2


def pairs(shot: Path, record: Path) -> "list[tuple[Path, Path]]":
    """The (shot, record) pairs two paths name.

    Two files are one pair. Two directories are every `.png` the record folder
    holds, matched by name, and a record with no shot is a failure of its own:
    a scenario that stopped shooting a frame is exactly the regression a record
    set exists to notice.

    **The difference pictures are not shots.** They are written beside the shot
    with a name ending in `.diff.png`, so a folder read twice would otherwise
    ask for the diff of a diff on the second pass. That is not hypothetical: it
    happened the first time two runs of one scenario were compared here.
    """
    if shot.is_file() and record.is_file():
        return [(shot, record)]
    if not record.is_dir():
        raise ShotDiffError(f"{record} is neither a picture nor a folder of them")
    if not shot.is_dir():
        raise ShotDiffError(f"{shot} is not a folder, and {record} is")
    found = []
    for path in sorted(path for path in record.glob("*.png") if not path.name.endswith(DIFF_SUFFIX)):
        taken = shot / path.name
        if not taken.exists():
            raise ShotDiffError(f"the record has {path.name} and the shot folder {shot} does not")
        found.append((taken, path))
    if not found:
        raise ShotDiffError(f"{record} holds no record picture")
    return found


def check(shot: Path, record: Path, tolerance: int, max_texels: int, write_diff: bool = True) -> "tuple[bool, str]":
    """Compare one pair and say what happened in one line, plus the diff path."""
    difference = compare(read_png(shot), read_png(record), tolerance)
    if difference.passes(max_texels):
        return True, f"  ok    {shot.name}  {difference.count} texel(s) over {tolerance}, worst {difference.worst}"
    line = (
        f"  FAIL  {shot.name}  {difference.count} texel(s) over {tolerance}, "
        f"worst {difference.worst} at {difference.worst_at}"
    )
    if write_diff:
        out = shot.with_suffix(DIFF_SUFFIX)
        write_png(out, difference_picture(read_png(record), difference))
        line += f"\n        the difference picture is {out}"
    return False, line


def main(argv: "list[str] | None" = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("shot", type=Path, help="the picture a run wrote, or the folder it wrote into")
    parser.add_argument("record", type=Path, help="the committed record, or the folder of them")
    parser.add_argument(
        "--tolerance",
        type=int,
        default=TOLERANCE,
        help=f"the largest per-channel distance that is still the same texel (default: {TOLERANCE})",
    )
    parser.add_argument(
        "--max-texels", type=int, default=0, help="how many texels may be over the tolerance (default: 0)"
    )
    parser.add_argument("--no-diff", action="store_true", help="do not write the difference picture")
    args = parser.parse_args(argv)

    try:
        found = pairs(args.shot, args.record)
    except ShotDiffError as refusal:
        print(f"  {refusal}", file=sys.stderr)
        return 2
    failed = 0
    for taken, kept in found:
        try:
            passed, line = check(taken, kept, args.tolerance, args.max_texels, not args.no_diff)
        except ShotDiffError as refusal:
            print(f"  FAIL  {taken.name}  {refusal}", file=sys.stderr)
            failed += 1
            continue
        print(line if passed else line, file=sys.stdout if passed else sys.stderr)
        failed += 0 if passed else 1
    print(f"  {len(found)} pair(s) read, {failed} over the tolerance")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
