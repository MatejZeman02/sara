"""What `shot_diff.py` says about a shot and the record beside it.

    cd sara-godot && PYTHONPATH=scripts python3 -m unittest scripts.test_shot_diff

The committed records under `tests/shots/` are the fixtures: they are read here
the way a check would read them, and every edit this file makes to them is made
to a copy in a temporary folder. A check that only ever compared a picture to
itself would pass with a decoder that returned the same wrong bytes twice, so
the edits are the point, and each one names the number it moves.

No Godot, no weston, no GPU, and the records are decoded once and shared, which
is what keeps this beside the other Python suites rather than doubling the phase
they run in.
"""

from __future__ import annotations

import io
import shutil
import struct
import tempfile
import unittest
import zlib
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

import shot_diff


PROJECT = Path(__file__).resolve().parent.parent
SCENARIO = PROJECT / "scenarios" / "the-shot-is-read-against-a-record.json"
RECORDS = PROJECT / "tests" / "shots" / "the-shot-is-read-against-a-record" / "rtx-3070-laptop"


def records() -> "list[Path]":
    return sorted(RECORDS.glob("*.png"))


# Decoding a 1280 by 800 frame in Python is half a second, and every case below
# wants one. They are read once and shared, which is safe because `edited` and
# `difference_picture` both build a new picture rather than writing into theirs.
_DECODED: "dict[Path, shot_diff.Picture]" = {}


def decoded(path: Path) -> shot_diff.Picture:
    if path not in _DECODED:
        _DECODED[path] = shot_diff.read_png(path)
    return _DECODED[path]


def edited(picture: shot_diff.Picture, x: int, y: int, by: int) -> shot_diff.Picture:
    """A copy of *picture* with the red channel of one texel moved by *by*."""
    pixels = bytearray(picture.pixels)
    index = (y * picture.width + x) * picture.channels
    pixels[index] = (pixels[index] + by) % 256
    return shot_diff.Picture(picture.width, picture.height, picture.channels, pixels)


def outline(picture: shot_diff.Picture) -> "tuple[int, int, int, int]":
    """The bounding rectangle of the cyan outline in a difference picture."""
    found = [
        (index % picture.width, index // picture.width)
        for index in range(picture.width * picture.height)
        if picture.pixels[index * 3 : index * 3 + 3] == bytes(shot_diff.BOX)
    ]
    return (
        min(x for x, _ in found),
        min(y for _, y in found),
        max(x for x, _ in found),
        max(y for _, y in found),
    )


class RecordSetTest(unittest.TestCase):
    """The committed pictures themselves, before anything is compared."""

    def test_the_record_folder_holds_the_frames_the_scenario_shoots(self) -> None:
        import json

        steps = json.loads(SCENARIO.read_text(encoding="utf-8"))
        shots = [step["shot"] for step in steps if isinstance(step, dict) and "shot" in step]
        self.assertEqual(sorted(f"{name}.png" for name in shots), sorted(path.name for path in records()))

    def test_every_record_decodes_to_a_frame_of_the_window(self) -> None:
        self.assertGreaterEqual(len(records()), 2, "a record set is two or three frames, not one")
        for path in records():
            with self.subTest(record=path.name):
                picture = decoded(path)
                self.assertEqual(picture.size(), (1280, 800), "the scenario asks for a 1280 by 800 window")
                self.assertIn(picture.channels, (3, 4))
                self.assertEqual(len(picture.pixels), 1280 * 800 * picture.channels)

    def test_the_two_records_of_one_frame_are_the_same_picture(self) -> None:
        """2-one-stroke and 3-the-same-frame-again are one frame shot twice.

        Nothing happens between them in the scenario, so they are the run's own
        proof that a shot repeats. If this ever fails, the record set is not
        stable and no comparison against it means anything.
        """
        twice = [decoded(RECORDS / name) for name in ("2-one-stroke.png", "3-the-same-frame-again.png")]
        difference = shot_diff.compare(twice[0], twice[1])
        self.assertEqual(difference.count, 0)
        self.assertEqual(difference.worst, 0, "the pair the record set rests on differs by nothing at all")


class CompareTest(unittest.TestCase):
    def setUp(self) -> None:
        self.record = decoded(records()[0])

    def test_a_record_against_itself_is_no_difference(self) -> None:
        difference = shot_diff.compare(self.record, self.record)
        self.assertEqual((difference.count, difference.worst, difference.box), (0, 0, None))
        self.assertTrue(difference.passes(0))

    def test_one_edited_texel_is_counted_and_located(self) -> None:
        difference = shot_diff.compare(edited(self.record, 700, 300, 200), self.record)
        self.assertEqual(difference.count, 1)
        self.assertEqual(difference.worst_at, (700, 300))
        self.assertEqual(difference.box, (700, 300, 700, 300))
        self.assertFalse(difference.passes(0))

    def test_the_tolerance_is_where_the_count_starts(self) -> None:
        """The number is the point of the whole file, so it is asserted from
        both sides: at the tolerance a texel is the same texel, one step over it
        is a difference."""
        inside = shot_diff.compare(edited(self.record, 10, 10, shot_diff.TOLERANCE), self.record)
        self.assertEqual(inside.count, 0)
        self.assertEqual(inside.worst, shot_diff.TOLERANCE, "it is seen, and it is not counted")
        outside = shot_diff.compare(edited(self.record, 10, 10, shot_diff.TOLERANCE + 1), self.record)
        self.assertEqual(outside.count, 1)

    def test_a_drift_under_the_tolerance_everywhere_is_still_the_same_picture(self) -> None:
        """The machine this was not written on. Every texel one step off, which
        is what a different driver's rounding looks like, and the check passes."""
        pixels = bytearray((value + 1) % 256 if value < 255 else 254 for value in self.record.pixels)
        drifted = shot_diff.Picture(self.record.width, self.record.height, self.record.channels, pixels)
        self.assertEqual(shot_diff.compare(drifted, self.record).count, 0)

    def test_a_shot_of_another_size_is_refused_by_name(self) -> None:
        smaller = shot_diff.Picture(4, 4, self.record.channels, bytearray(4 * 4 * self.record.channels))
        with self.assertRaises(shot_diff.ShotDiffError) as refusal:
            shot_diff.compare(smaller, self.record)
        self.assertIn("4x4", str(refusal.exception))
        self.assertIn(f"{self.record.width}x{self.record.height}", str(refusal.exception))

    def test_a_shot_with_alpha_against_a_record_without_it_is_refused(self) -> None:
        other = shot_diff.Picture(self.record.width, self.record.height, 7 - self.record.channels, bytearray(
            self.record.width * self.record.height * (7 - self.record.channels)
        ))
        with self.assertRaises(shot_diff.ShotDiffError) as refusal:
            shot_diff.compare(other, self.record)
        self.assertIn("channels", str(refusal.exception))


class DifferencePictureTest(unittest.TestCase):
    def setUp(self) -> None:
        self.record = decoded(records()[0])

    def test_one_edited_texel_leaves_one_red_mark_and_a_box_around_it(self) -> None:
        difference = shot_diff.compare(edited(self.record, 700, 300, 200), self.record)
        picture = shot_diff.difference_picture(self.record, difference)
        self.assertEqual(picture.channels, 3)
        marks = [
            (index % picture.width, index // picture.width)
            for index in range(picture.width * picture.height)
            if picture.pixels[index * 3 : index * 3 + 3] == bytes(shot_diff.MARK)
        ]
        self.assertEqual(marks, [(700, 300)], "the mark is the texel and nothing around it")
        # One texel grown to BOX_MINIMUM around itself, and then the outline one
        # texel outside that, which is where an eye can find a single red dot.
        x0, y0, x1, y1 = outline(picture)
        self.assertGreaterEqual(x1 - x0 + 1, shot_diff.BOX_MINIMUM)
        self.assertGreaterEqual(y1 - y0 + 1, shot_diff.BOX_MINIMUM)
        self.assertTrue(x0 < 700 < x1 and y0 < 300 < y1, "and it is around the mark")
        self.assertNotEqual(picture.texel(699, 299), shot_diff.BOX, "and nothing is drawn against the mark")

    def test_a_difference_in_the_corner_keeps_every_mark_it_has(self) -> None:
        """The box is clipped at the edge and the marks are not, which is the
        one way an outline drawn after the marks could eat one."""
        difference = shot_diff.compare(edited(self.record, 0, 0, 200), self.record)
        picture = shot_diff.difference_picture(self.record, difference)
        self.assertEqual(picture.texel(0, 0), shot_diff.MARK)
        x0, y0, x1, y1 = outline(picture)
        self.assertEqual((x0, y0), (0, 0), "the two lines that fall off the edge are simply not drawn")
        self.assertGreaterEqual(min(x1, y1), shot_diff.BOX_MINIMUM // 2, "the two that fit are")

    def test_the_record_under_the_wash_keeps_its_shape_and_loses_its_contrast(self) -> None:
        difference = shot_diff.compare(self.record, self.record)
        picture = shot_diff.difference_picture(self.record, difference)
        for x, y in ((0, 0), (640, 400), (1279, 799)):
            under = self.record.texel(x, y)[:3]
            self.assertEqual(picture.texel(x, y), tuple(255 - (255 - value) // shot_diff.WASH for value in under))

    def test_a_greyscale_record_washes_into_three_equal_channels(self) -> None:
        grey = shot_diff.Picture(2, 1, 1, bytearray((0, 255)))
        picture = shot_diff.difference_picture(grey, shot_diff.compare(grey, grey))
        self.assertEqual(picture.texel(0, 0), (shot_diff.WASH_TABLE[0],) * 3)
        self.assertEqual(picture.texel(1, 0), (255, 255, 255))

    def test_a_written_picture_reads_back_the_same(self) -> None:
        difference = shot_diff.compare(edited(self.record, 12, 34, 200), self.record)
        picture = shot_diff.difference_picture(self.record, difference)
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "diff.png"
            shot_diff.write_png(path, picture)
            read_back = shot_diff.read_png(path)
        self.assertEqual((read_back.width, read_back.height, read_back.channels), (1280, 800, 3))
        self.assertEqual(read_back.pixels, picture.pixels)


class DecoderTest(unittest.TestCase):
    """The five row filters and the four refusals, on pictures built here.

    Godot's own writer picks whichever filter compresses best per row, so the
    records exercise these already, but not one at a time and not visibly.
    """

    def png(self, width: int, height: int, channels: int, rows: "list[tuple[int, bytes]]", depth: int = 8,
            interlace: int = 0) -> bytes:
        colour = {1: 0, 2: 4, 3: 2, 4: 6}[channels]
        raw = b"".join(bytes((kind,)) + row for kind, row in rows)
        header = struct.pack(">IIBBBBB", width, height, depth, colour, 0, 0, interlace)
        return shot_diff.PNG_MAGIC + b"".join(
            shot_diff.chunk(kind, payload)
            for kind, payload in ((b"IHDR", header), (b"IDAT", zlib.compress(raw)), (b"IEND", b""))
        )

    def read(self, data: bytes) -> shot_diff.Picture:
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "made.png"
            path.write_bytes(data)
            return shot_diff.read_png(path)

    def test_each_row_filter_is_undone(self) -> None:
        # One 3 by 3 RGB picture written five times, once through each filter,
        # every one describing the same texels: 10, 20, 30 stepping by 10.
        wanted = [bytes((10 + 10 * (y * 3 + x) + c for x in range(3) for c in range(3))) for y in range(3)]
        for kind in range(5):
            with self.subTest(filter=kind):
                rows = []
                previous = bytes(9)
                for row in wanted:
                    if kind == 0:
                        encoded = row
                    elif kind == 1:
                        encoded = bytes((row[i] - (row[i - 3] if i >= 3 else 0)) & 0xFF for i in range(9))
                    elif kind == 2:
                        encoded = bytes((row[i] - previous[i]) & 0xFF for i in range(9))
                    elif kind == 3:
                        encoded = bytes(
                            (row[i] - (((row[i - 3] if i >= 3 else 0) + previous[i]) >> 1)) & 0xFF for i in range(9)
                        )
                    else:
                        encoded = bytes(
                            (
                                row[i]
                                - shot_diff.paeth(
                                    row[i - 3] if i >= 3 else 0, previous[i], previous[i - 3] if i >= 3 else 0
                                )
                            )
                            & 0xFF
                            for i in range(9)
                        )
                    rows.append((kind, encoded))
                    previous = row
                picture = self.read(self.png(3, 3, 3, rows))
                self.assertEqual(bytes(picture.pixels), b"".join(wanted))

    def test_a_sixth_filter_is_refused(self) -> None:
        with self.assertRaises(shot_diff.ShotDiffError) as refusal:
            self.read(self.png(1, 1, 3, [(5, bytes(3))]))
        self.assertIn("filter type 5", str(refusal.exception))

    def test_sixteen_bits_a_channel_is_refused_rather_than_halved(self) -> None:
        with self.assertRaises(shot_diff.ShotDiffError) as refusal:
            self.read(self.png(1, 1, 3, [(0, bytes(6))], depth=16))
        self.assertIn("16 bits", str(refusal.exception))

    def test_an_interlaced_picture_is_refused(self) -> None:
        with self.assertRaises(shot_diff.ShotDiffError) as refusal:
            self.read(self.png(1, 1, 3, [(0, bytes(3))], interlace=1))
        self.assertIn("interlaced", str(refusal.exception))

    def test_something_that_is_not_a_png_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "run.log"
            path.write_text("the app printed this", encoding="utf-8")
            with self.assertRaises(shot_diff.ShotDiffError) as refusal:
                shot_diff.read_png(path)
        self.assertIn("not a PNG", str(refusal.exception))

    def test_a_greyscale_and_an_alpha_picture_both_read(self) -> None:
        for channels in (1, 2, 4):
            with self.subTest(channels=channels):
                picture = self.read(self.png(2, 1, channels, [(0, bytes(range(2 * channels)))]))
                self.assertEqual(picture.channels, channels)


class CommandLineTest(unittest.TestCase):
    """The exit codes, which is all a gate line ever reads.

    Two small pictures written here stand in for a record set in most of these,
    because the point being asserted is the exit code and a real 1280 by 800
    frame is half a second to decode. One case runs against the committed
    records themselves, so the shape of a real folder is exercised too.
    """

    def run_main(self, argv: "list[str]") -> "tuple[int, str]":
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = shot_diff.main(argv)
        return code, out.getvalue() + err.getvalue()

    def small_set(self, folder: Path) -> "list[Path]":
        """Two 64 by 40 pictures, one grey and one with a black square in it."""
        made = []
        for name, fill in (("1-flat.png", 128), ("2-a-square.png", 200)):
            pixels = bytearray([fill]) * (64 * 40 * 3)
            if name.startswith("2"):
                for y in range(10, 30):
                    pixels[(y * 64 + 10) * 3 : (y * 64 + 40) * 3] = bytes(30 * 3)
            path = folder / name
            shot_diff.write_png(path, shot_diff.Picture(64, 40, 3, pixels))
            made.append(path)
        return made

    def test_a_folder_of_shots_that_match_their_records_exits_zero(self) -> None:
        with tempfile.TemporaryDirectory() as kept, tempfile.TemporaryDirectory() as taken:
            for path in self.small_set(Path(kept)):
                shutil.copy(path, Path(taken) / path.name)
            code, said = self.run_main([taken, kept])
        self.assertEqual(code, 0, said)
        self.assertIn("2 pair(s) read, 0 over the tolerance", said)

    def test_the_committed_records_read_against_a_copy_of_themselves(self) -> None:
        """The real folder, at its real size, through the real command line."""
        with tempfile.TemporaryDirectory() as folder:
            for path in records():
                shutil.copy(path, Path(folder) / path.name)
            code, said = self.run_main([folder, str(RECORDS)])
        self.assertEqual(code, 0, said)
        self.assertIn(f"{len(records())} pair(s) read, 0 over the tolerance", said)

    def test_one_edited_texel_in_a_folder_exits_one_and_writes_the_picture(self) -> None:
        with tempfile.TemporaryDirectory() as kept, tempfile.TemporaryDirectory() as taken:
            made = self.small_set(Path(kept))
            for path in made:
                shutil.copy(path, Path(taken) / path.name)
            first = Path(taken) / made[0].name
            shot_diff.write_png(first, edited(shot_diff.read_png(first), 20, 15, 200))
            code, said = self.run_main([taken, kept])
            self.assertEqual(code, 1, said)
            self.assertIn("1 texel(s) over 6", said)
            self.assertIn("(20, 15)", said)
            self.assertTrue(first.with_suffix(".diff.png").exists(), "the difference picture goes beside the shot")
            self.assertEqual(shot_diff.read_png(first.with_suffix(".diff.png")).texel(20, 15), shot_diff.MARK)

    def test_a_second_run_over_the_same_folder_does_not_read_its_own_diffs(self) -> None:
        """A difference picture is written beside the shot, and the folder is
        read by name, so the first run left something the second would have
        asked the record folder for. It happened, once, for real."""
        with tempfile.TemporaryDirectory() as kept, tempfile.TemporaryDirectory() as taken:
            made = self.small_set(Path(kept))
            for path in made:
                shutil.copy(path, Path(taken) / path.name)
            shot_diff.write_png(made[0].with_suffix(shot_diff.DIFF_SUFFIX), shot_diff.read_png(made[0]))
            code, said = self.run_main([taken, kept])
        self.assertEqual(code, 0, said)
        self.assertIn("2 pair(s) read", said)

    def test_a_missing_shot_is_the_records_own_failure(self) -> None:
        with tempfile.TemporaryDirectory() as kept, tempfile.TemporaryDirectory() as taken:
            made = self.small_set(Path(kept))
            code, said = self.run_main([taken, kept])
        self.assertEqual(code, 2, said)
        self.assertIn(made[0].name, said)

    def test_a_record_folder_that_is_not_there_is_refused(self) -> None:
        code, said = self.run_main([str(RECORDS), str(RECORDS / "nothing")])
        self.assertEqual(code, 2, said)
        self.assertIn("neither a picture nor a folder", said)


class GateTest(unittest.TestCase):
    """The committed gate against this file, the way test_file_map holds the map.

    A suite nothing runs is a suite that rots, and the two places the gate is
    written down are the repository's own contract with an agent.
    """

    def test_both_gate_pages_name_this_suite(self) -> None:
        if not (PROJECT.parent / "docs").is_dir():
            self.skipTest("a public copy has no docs folder, and its AGENTS.md is not the gate page")
        for page in (PROJECT.parent / "AGENTS.md", PROJECT.parent / "docs" / "guides" / "TESTING.md"):
            with self.subTest(page=page.name):
                if not page.exists():
                    self.skipTest("a copy of the source carries no %s" % page.name)
                self.assertIn("scripts.test_shot_diff", page.read_text(encoding="utf-8"))

    def test_the_testing_guide_says_how_a_record_is_read(self) -> None:
        page = PROJECT.parent / "docs" / "guides" / "TESTING.md"
        if not page.exists():
            self.skipTest("a copy of the source carries no %s" % page.name)
        guide = page.read_text(encoding="utf-8")
        self.assertIn("shot_diff.py", guide)
        self.assertIn("tests/shots/", guide)


if __name__ == "__main__":
    unittest.main()
