#!/usr/bin/env python3
"""The `%%gmacs` cell magic and its sliders against a stub door.

    cd sara-godot && PYTHONPATH=scripts python3 -m unittest scripts.test_sara_notebook

The magic runs in IPython's own shell, the stub door of `test_sara.py` taught
the `kernel` step's contract: the request carries the source, the name,
the layers and the params, and the verdict answers `ok`, `params` as
`{name, type, default}` and the layer written. Where IPython or `ipywidgets` is
not installed every case skips with a line saying which.
"""

from __future__ import annotations

import ast
import importlib.util
import json
import os
import re
import sys
import tempfile
import threading
import unittest
from functools import partial
from pathlib import Path
from unittest import mock

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))

MISSING = [name for name in ("IPython", "ipywidgets") if importlib.util.find_spec(name) is None]
if MISSING:
    # The runner shows a skip's reason only when verbose, so the line is said here too.
    print(f"test_sara_notebook: {' and '.join(MISSING)} not installed, the %%gmacs cases skip", file=sys.stderr)

import numpy as np  # noqa: E402

import sara  # noqa: E402
import test_sara  # noqa: E402
from test_sara import StubDoor  # noqa: E402

CELLS = """kernel cells

image src: readonly
image dst

params:
    float scale: hint_range(2, 64)
    int seeds: hint_range(1, 32)
    vec2 centre

def cells():
    image_store(dst, pixel, image_load(src, pixel) * scale)
"""

# Lesson 1's shape in the short pixel form, which the app wraps into `pixels`.
DITHER = """import linear_srgb_color_space
import oklab_color_space

uniform float levels = 4.0    # range 2 16
uniform int steps = 3    # range 1 8
uniform float spread = 0.25

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0)

def pixel(ivec2 at) -> vec4:
    vec4 here = src(at)
    float threshold = (BAYER[(at.y % 4) * 4 + at.x % 4] + 0.5) / 16.0 - 0.5
    return floor(here * levels + threshold * spread + 0.5) / levels
"""


# The same kernel with its ranges in the `# range` comment the hint replaced,
# which an older saved cell still carries.
OLD_CELLS = CELLS.replace(": hint_range(2, 64)", "    # range 2 64").replace(": hint_range(1, 32)", "    # range 1 32")

# The same kernel with a step on each hint, Godot's third number.
STEPPED_CELLS = CELLS.replace("hint_range(2, 64)", "hint_range(2, 64, 0.5)").replace("hint_range(1, 32)", "hint_range(1, 32, 3)")

# A kernel with a tagged colour of each width and an untagged vector beside
# them, three cases in one cell.
COLOUR_CELLS = """kernel tinted

image src: readonly
image dst

params:
    float amount: hint_range(0, 1)
    vec3 tint: source_color
    vec4 wash: source_color
    vec3 offset

def tinted():
    vec4 c = image_load(src, pixel)
    image_store(dst, pixel, vec4(c.rgb * tint * wash.rgb * amount + offset, c.a * wash.a))
"""

# A kernel switched by a drop-down and a checkbox, two kinds.
SWITCHED = """kernel switched

image src: readonly
image dst

params:
    int mode: hint_enum("Keep", "Black", "White")
    bool lift
    int count: hint_range(1, 8)

def switched():
    image_store(dst, pixel, image_load(src, pixel))
"""


# A kernel reading a second layer under `src1`, two operands.
MIXED = """kernel mixed

image src: readonly
image src1: readonly
image dst

params:
    vec2 extent
    float weight: hint_range(0, 2)

def mixed():
    if pixel.x >= int(extent.x) or pixel.y >= int(extent.y):
        return
    image_store(dst, pixel, image_load(src, pixel) + image_load(src1, pixel) * weight)
"""

# A matrix on a params line is a grid of number fields, and an
# array whose length is no square is left without a widget.
MATRIX_CELLS = CELLS.replace("    vec2 centre\n", "    vec2 centre\n    float small[9]\n    float middle[25]\n    float large[49]\n    float odd[6]\n")

# A params line that declares an array of float, its name and its length.
_FLOAT_ARRAY = re.compile(r"^[ \t]+float[ \t]+(\w+)\[(\d+)\]", re.MULTILINE)


class KernelStub(StubDoor):
    """A stub door, answering the `kernel` step the way the real driver does."""

    def _run(self, step: dict) -> list[str]:
        kind, spec = next(iter(step.items()))
        if kind != "kernel":
            return super()._run(step)
        if "no_such_thing" in spec["source"]:
            said = {"ok": False, "error": "cells.gmacs:4: no_such_thing undeclared", "line": 4}
            return ["SaCapture: kernel " + json.dumps(said)]
        into = spec.get("into", spec["name"])
        if self._find(into) is None:
            super()._run({"layer": {"add": into}})
        params = [{"name": "scale", "type": "float", "default": 0.0}]
        params += [{"name": "seeds", "type": "int", "default": 0}, {"name": "centre", "type": "vec2", "default": [0, 0]}]
        if spec["name"] == "tinted":
            params = [{"name": "amount", "type": "float", "default": 0.0}]
            params += [{"name": "tint", "type": "vec3", "default": [0.0, 0.0, 0.0]}]
            params += [{"name": "wash", "type": "vec4", "default": [0.0, 0.0, 0.0, 0.0]}]
            params += [{"name": "offset", "type": "vec3", "default": [0.0, 0.0, 0.0]}]
        elif spec["name"] == "switched":
            # The driver answers a bool's zero as 0.0, the way it answers every
            # type it has no zero of its own for.
            params = [{"name": "mode", "type": "int", "default": 0}, {"name": "lift", "type": "bool", "default": 0.0}]
            params += [{"name": "count", "type": "int", "default": 0}]
        elif spec["name"] == "pixels":
            # The driver answers a short form's params at the defaults its `uniform` lines declare.
            params = [{"name": "levels", "type": "float", "default": 4.0}, {"name": "steps", "type": "int", "default": 3}]
            params += [{"name": "spread", "type": "float", "default": 0.25}]
        # An array answers its length beside the type. The numbers count up from
        # one rather than the driver's one in the middle, so a case sees their order.
        for name, length in _FLOAT_ARRAY.findall(spec["source"]):
            numbers = [float(n) for n in range(1, int(length) + 1)]
            params.append({"name": name, "type": "float", "default": numbers, "length": int(length)})
        said = {"ok": True, "compiled": True, "params": params, "layer": spec.get("layer", 0), "into": into}
        # A GPU time, a different one each run so a case sees the line follow.
        said["gpu_ms"] = 0.21 + 0.01 * len([r for r in self.requests if "kernel" in r])
        return ["SaCapture: kernel " + json.dumps(said)]


class Clock:
    """A clock the test moves, so a frame passes when the test says."""

    def __init__(self) -> None:
        self.now = 100.0

    def __call__(self) -> float:
        return self.now


@unittest.skipIf(MISSING, f"{' and '.join(MISSING)} not installed, the %%gmacs magic is not tested")
class GmacsMagicTests(unittest.TestCase):
    def setUp(self) -> None:
        from IPython.core.interactiveshell import InteractiveShell

        import sara_notebook

        self.notebook = sara_notebook
        folder = Path(tempfile.mkdtemp(prefix="sara-gmacs-"))
        self.stub = KernelStub(folder, "tcp")
        self.addCleanup(self.stub.close)
        with mock.patch.object(sara, "TRANSPORT", "tcp"):
            self.doc = sara.connect(self.stub.file)
        self.addCleanup(self.doc.close)
        self.shell = InteractiveShell.instance()
        sara_notebook.load_ipython_extension(self.shell)
        sara_notebook.use(self.doc)
        self.addCleanup(sara_notebook.use, None)

    def kernels(self) -> list[dict]:
        return [r["kernel"] for r in self.stub.requests if "kernel" in r]

    def run_cell(self, line: str, body: str = CELLS, clock: Clock | None = None, interval: float | None = None):
        """Runs a cell, its debounce on *clock* and *interval* when given, the frame's otherwise."""
        made = {"clock": clock} if clock is not None else {}
        made |= {"interval": interval} if interval is not None else {}
        with mock.patch.object(self.notebook, "Debounce", partial(self.notebook.Debounce, **made)):
            self.shell.run_cell_magic("gmacs", line, body)
        return self.notebook.GmacsMagics.last

    @staticmethod
    def drag(widget, value) -> None:
        """Moves *widget* the way the page does, through the state message a drag sends."""
        widget.set_state({"value": value})

    def test_the_magic_sends_the_body_as_the_kernel_and_shows_the_result(self) -> None:
        cell = self.run_cell("Background -> Cells scale=12")
        sent = self.kernels()
        self.assertEqual(len(sent), 1)
        self.assertEqual(sent[0]["source"], CELLS)
        self.assertEqual(sent[0]["name"], "cells")
        self.assertEqual((sent[0]["layer"], sent[0]["into"]), ("Background", "Cells"))
        self.assertEqual(sent[0]["params"], {"scale": 12.0})
        shown = [r["read_pixels"]["layer"] for r in self.stub.requests if "read_pixels" in r]
        self.assertEqual(shown, ["Cells"], "the cell shows the written layer")
        self.assertEqual(list(cell.sliders), ["scale", "seeds"], "a slider per scalar parameter")
        scale, seeds = cell.sliders["scale"], cell.sliders["seeds"]
        self.assertEqual((scale.min, scale.max, scale.value), (2.0, 64.0, 12.0))
        self.assertEqual((seeds.min, seeds.max, seeds.value), (1, 32, 1))

    def test_a_cells_picture_is_an_image_widget_and_no_output_widget_is_made(self) -> None:
        """VS Code's Jupyter 2025.9.1 cannot load `@jupyter-widgets/output`, the `Image` is from the module that works."""
        import ipywidgets

        cell = self.run_cell("Background -> Cells scale=12")
        box = cell.build([])
        self.assertIs(box.children[-1], cell.picture, "the picture sits last, under the line")
        self.assertIsInstance(cell.picture, ipywidgets.Image)
        self.assertEqual(cell.picture.format, "png")
        made = {type(widget) for widget in self.widgets_under(box)}
        self.assertNotIn(ipywidgets.Output, made)
        self.assertEqual(sum(isinstance(widget, ipywidgets.Image) for widget in self.widgets_under(box)), 1)

    def test_the_image_holds_the_png_the_door_made_and_a_slider_move_replaces_it(self) -> None:
        cell = self.run_cell("Background -> Cells scale=12")
        cells = next(pixels for name, pixels in self.stub.layers if name == "Cells")
        first = sara.png_bytes(sara.tone_map(cells))
        self.assertEqual(cell.picture.value, first, "the first run drew the layer's small form")
        cells[:] = 0.75
        self.drag(cell.sliders["scale"], 20.0)
        cell._debounce.flush()
        moved = sara.png_bytes(sara.tone_map(cells))
        self.assertNotEqual(moved, first)
        self.assertEqual(cell.picture.value, moved, "a slider move sets the same widget to the layer's new picture")
        self.assertEqual(test_sara.decode_png(bytes(cell.picture.value))[0, 0].tolist(), [191, 191, 191, 191])

    def test_a_step_the_door_refuses_on_a_slider_move_is_the_line_under_the_sliders(self) -> None:
        cell = self.run_cell("Background -> Cells scale=12")
        self.assertRegex(cell.timing.value, r"^GPU ")
        before = cell.picture.value
        with mock.patch.object(cell, "run", side_effect=sara.SaraError("cells.gmacs:4: no_such_thing undeclared")):
            cell.sliders["scale"].value = 20.0
        self.assertEqual(cell.timing.value, "cells.gmacs:4: no_such_thing undeclared")
        self.assertEqual(cell.picture.value, before, "the last picture stays")

    @staticmethod
    def widgets_under(widget) -> list:
        """*widget* and every widget inside it, through the boxes' `children`."""
        found = [widget]
        for child in getattr(widget, "children", ()):
            found += GmacsMagicTests.widgets_under(child)
        return found

    def test_a_line_that_names_no_layer_writes_a_new_one_and_a_rerun_writes_there_again(self) -> None:
        cell = self.run_cell("0")
        cell.sliders["scale"].value = 3.0
        sent = self.kernels()
        self.assertNotIn("into", sent[0])
        self.assertEqual(sent[1]["into"], "cells", "the rerun writes the layer the first run added")
        self.assertEqual(sent[0]["layer"], 0)
        self.assertEqual([layer[0] for layer in self.stub.layers], ["Background", "cells"])

    def test_two_slider_moves_send_two_requests_with_the_new_values(self) -> None:
        clock = Clock()
        cell = self.run_cell("Background -> Cells scale=12", clock=clock)
        self.drag(cell.sliders["scale"], 20.0)
        cell._debounce.settle()
        clock.now += 1.0
        self.drag(cell.sliders["seeds"], 7)
        cell._debounce.settle()
        sent = self.kernels()[1:]
        self.assertEqual([k["params"] for k in sent], [{"scale": 20.0}, {"scale": 20.0, "seeds": 7}])
        self.assertTrue(all(k["into"] == "Cells" for k in sent))

    def test_every_picture_a_slider_draws_is_the_small_form_made_in_sara(self) -> None:
        """The readback, not the kernel, set a slider's delay on a GTX 1060."""
        cell = self.run_cell("Background -> Cells scale=12")
        cell.sliders["scale"].value = 20.0
        reads = [r["read_pixels"] for r in self.stub.requests if "read_pixels" in r]
        self.assertEqual(len(reads), 2, "the first run and the rerun each drew one picture")
        self.assertTrue(all(read.get("max_size") == 512 for read in reads), reads)

    def test_a_drag_inside_one_frame_sends_one_request_with_its_last_value(self) -> None:
        clock = Clock()
        cell = self.run_cell("Background -> Cells scale=12", clock=clock, interval=0.2)
        self.drag(cell.sliders["scale"], 20.0)
        cell._debounce.settle()
        for value in (21.0, 22.0, 23.0):
            clock.now += 0.001
            self.drag(cell.sliders["scale"], value)
        self.assertEqual(len(self.kernels()), 2, "the drag's first step went, the rest wait for the frame")
        self.assertIsNotNone(cell._debounce.worker, "and the worker holds them")
        cell._debounce.settle()
        self.assertEqual([k["params"]["scale"] for k in self.kernels()[1:]], [20.0, 23.0])

    def test_a_value_set_from_code_reaches_the_door_at_once(self) -> None:
        """A script that set a slider had to call `flush()` on the cell's debounce."""
        clock = Clock()
        cell = self.run_cell("Background -> Cells scale=12", clock=clock, interval=0.2)
        cell.sliders["scale"].value = 20.0
        cell.sliders["scale"].value = 21.0
        cell.sliders["seeds"].value = 7
        sent = [k["params"] for k in self.kernels()[1:]]
        self.assertEqual(sent, [{"scale": 20.0}, {"scale": 21.0}, {"scale": 21.0, "seeds": 7}], "each set reruns before the next line, inside one frame")
        self.assertIsNone(cell._debounce.pending, "and leaves no send waiting")

    def test_a_grid_and_a_picker_set_from_code_reach_the_door_at_once(self) -> None:
        matrix = self.run_cell("Background -> Cells scale=12", MATRIX_CELLS, clock=Clock(), interval=0.2)
        matrix.grids["small"].children[0].value = 0.5
        matrix.grids["small"].children[1].value = 0.25
        self.assertEqual(self.kernels()[-1]["params"]["small"][:2], [0.5, 0.25], "a grid's two fields went inside one frame")
        tinted = self.run_cell("Background -> Tinted", COLOUR_CELLS, clock=Clock(), interval=0.2)
        tinted.alphas["wash"].value = 0.5
        tinted.pickers["wash"].value = "#ffffff"
        self.assertEqual(self.kernels()[-1]["params"]["wash"], [1.0, 1.0, 1.0, 0.5], "and so did a picker and its alpha")

    def test_a_value_set_from_code_overtakes_a_drag_that_waits(self) -> None:
        clock = Clock()
        cell = self.run_cell("Background -> Cells scale=12", clock=clock, interval=0.2)
        self.drag(cell.sliders["scale"], 20.0)
        cell._debounce.settle()
        clock.now += 0.001
        self.drag(cell.sliders["scale"], 21.0)
        cell.sliders["scale"].value = 30.0
        cell._debounce.settle()
        self.assertEqual([k["params"]["scale"] for k in self.kernels()[1:]], [20.0, 30.0], "the waiting drag step is older and is dropped")

    def test_the_line_under_the_sliders_says_each_runs_gpu_time_and_round_trip(self) -> None:
        cell = self.run_cell("Background -> Cells scale=12")
        box = cell.build([])
        self.assertIs(box.children[-2], cell.timing, "the line sits under the sliders, above the picture")
        self.assertRegex(cell.timing.value, r"^GPU 0\.22 ms, round trip \d+ ms$")
        cell.sliders["scale"].value = 20.0
        self.assertRegex(cell.timing.value, r"^GPU 0\.23 ms, round trip \d+ ms$", "and it follows the rerun")
        self.assertIn("Cells", self.doc.kernels, "the run is the one `sara.bench` repeats")

    def test_the_old_range_comment_makes_the_slider_the_hint_does(self) -> None:
        self.assertIn("# range 2 64", OLD_CELLS)
        hinted = self.run_cell("Background -> Cells scale=12")
        commented = self.run_cell("Background -> Cells scale=12", OLD_CELLS)
        for name in ("scale", "seeds"):
            new, old = hinted.sliders[name], commented.sliders[name]
            self.assertEqual((old.min, old.max, old.step), (new.min, new.max, new.step), f"{name} reads the same either way")
        self.assertEqual((commented.sliders["scale"].min, commented.sliders["scale"].max), (2.0, 64.0))

    def test_a_hints_step_reaches_the_slider_and_its_absence_keeps_the_default(self) -> None:
        stepped = self.run_cell("Background -> Cells scale=12", STEPPED_CELLS)
        self.assertEqual(stepped.sliders["scale"].step, 0.5, "a float steps by the hint's third number")
        self.assertEqual(stepped.sliders["seeds"].step, 3, "and so does a whole number")
        plain = self.run_cell("Background -> Cells scale=12")
        self.assertAlmostEqual(plain.sliders["scale"].step, (64.0 - 2.0) / 100.0, msg="with no step a float moves a hundredth of its range")
        self.assertEqual(plain.sliders["seeds"].step, 1, "and a whole number by one")

    def test_a_matrix_is_a_grid_of_number_fields_its_side_to_a_row(self) -> None:
        cell = self.run_cell("Background -> Cells scale=12", MATRIX_CELLS)
        self.assertEqual(list(cell.sliders), ["scale", "seeds", "small", "middle", "large"], "in the order the block declares")
        self.assertNotIn("odd", cell.grids, "six numbers are no square, so no grid")
        for name, side in (("small", 3), ("middle", 5), ("large", 7)):
            grid = cell.grids[name]
            self.assertEqual(grid.layout.grid_template_columns, f"repeat({side}, 5.5em)", f"{name} is {side} by {side}")
            numbers = [entry.value for entry in grid.children]
            self.assertEqual(numbers, [float(n) for n in range(1, side * side + 1)], f"{name} reads row by row")
        self.assertEqual(cell.sliders["small"].children[0].value, "small", "the grid sits under its name")

    def test_a_number_typed_into_a_grid_sends_the_whole_matrix(self) -> None:
        cell = self.run_cell("Background -> Cells scale=12", MATRIX_CELLS)
        # Row two, column three of the 3 by 3: the sixth number the kernel reads.
        cell.grids["small"].children[5].value = 0.5
        sent = self.kernels()[-1]["params"]
        self.assertEqual(sent["small"], [1.0, 2.0, 3.0, 4.0, 5.0, 0.5, 7.0, 8.0, 9.0])
        self.assertEqual(sent["scale"], 12.0, "beside the values the line gave")
        cell.grids["large"].children[48].value = -2.0
        self.assertEqual(self.kernels()[-1]["params"]["large"][-1], -2.0, "the last of forty-nine is the bottom right")
        self.assertEqual(self.kernels()[-1]["params"]["small"][5], 0.5, "and the first grid keeps its change")

    def test_ranges_reads_the_hint_the_comment_and_neither(self) -> None:
        source = "params:\n    float a: hint_range(0, 2, 0.25)  # note\n    int b    # range 1 8\n"
        source += "    int c: hint_range(0, 9) = 3\n    float d\n    float e: hint_range(1)\n    int f: hint_range(1, 4)    # range 0 100\n"
        found = self.notebook.ranges(source)
        self.assertEqual(found["a"], (0.0, 2.0, 0.25))
        self.assertEqual(found["b"], (1.0, 8.0, None), "the comment has no room for a step")
        self.assertEqual(found["c"], (0.0, 9.0, None), "a value after the hint is not read as one")
        self.assertNotIn("d", found, "a line with no range keeps the default")
        self.assertNotIn("e", found, "and so does a hint that is not two or three numbers")
        self.assertEqual(found["f"], (1.0, 4.0, None), "the hint wins over a comment on the same line")

    def test_a_tagged_colour_is_a_picker_and_an_untagged_vector_has_no_widget(self) -> None:
        cell = self.run_cell("Background -> Tinted", COLOUR_CELLS)
        self.assertEqual(sorted(cell.pickers), ["tint", "wash"], "a picker per tagged colour")
        self.assertNotIn("offset", cell.pickers, "the untagged vec3 earns none")
        self.assertNotIn("offset", cell.sliders, "and no slider either")
        self.assertEqual(list(cell.alphas), ["wash"], "the vec4 gets an alpha slider, the picker having none")
        self.assertEqual(cell.pickers["tint"].value, "#000000", "opening on the kernel's default")
        self.assertEqual(self.notebook.colours(COLOUR_CELLS), {"tint", "wash"})

    def test_a_picked_colour_reaches_the_kernel_as_the_numbers_the_picker_shows(self) -> None:
        cell = self.run_cell("Background -> Tinted", COLOUR_CELLS)
        cell.pickers["tint"].value = "#4080c0"
        sent = self.kernels()[-1]["params"]["tint"]
        self.assertEqual(sent, [0x40 / 255.0, 0x80 / 255.0, 0xC0 / 255.0], "sRGB as shown, no linear conversion")
        cell.alphas["wash"].value = 0.5
        cell.pickers["wash"].value = "#ffffff"
        self.assertEqual(self.kernels()[-1]["params"]["wash"], [1.0, 1.0, 1.0, 0.5], "a vec4 carries its alpha slider's value last")
        self.assertNotIn("offset", self.kernels()[-1]["params"], "the untagged vector keeps the kernel's own value")

    def test_a_choice_is_a_drop_down_and_a_bool_a_checkbox(self) -> None:
        import ipywidgets

        cell = self.run_cell("Background -> Switched", SWITCHED)
        mode, lift, count = cell.sliders["mode"], cell.sliders["lift"], cell.sliders["count"]
        self.assertIsInstance(mode, ipywidgets.Dropdown, "a hint_enum makes a drop-down")
        self.assertIsInstance(lift, ipywidgets.Checkbox, "a bool makes a checkbox")
        self.assertIsInstance(count, ipywidgets.IntSlider, "and an int with a range keeps its slider")
        self.assertEqual(list(mode.options), [("Keep", 0), ("Black", 1), ("White", 2)], "the labels in order, each worth its index")
        self.assertEqual((mode.value, lift.value), (0, False), "opening on the first entry and an unticked box")
        mode.value = 2
        lift.value = True
        sent = [k["params"] for k in self.kernels()[1:]]
        self.assertEqual(sent, [{"mode": 2}, {"mode": 2, "lift": True}], "a pick reaches the kernel as its index, a tick as true")
        self.assertIs(sent[1]["lift"], True, "a JSON true, which the packer writes as GLSL's 32-bit one")

    def test_the_first_line_sets_an_entry_and_a_box(self) -> None:
        cell = self.run_cell("Background -> Switched mode=1 lift=true", SWITCHED)
        self.assertEqual((cell.sliders["mode"].value, cell.sliders["lift"].value), (1, True))
        self.assertEqual(self.kernels()[0]["params"], {"mode": 1.0, "lift": True}, "the line's values go as written")
        self.assertEqual(cell.values, {"mode": 1, "lift": True}, "and a rerun sends the entry as a whole index")

    def test_choices_reads_quoted_labels_only(self) -> None:
        source = 'params:\n    int a: hint_enum("x", "y, z")\n    int b: hint_enum(x, y)\n    int c: hint_enum()\n'
        source += '    int d: hint_range(0, 4)\n    int e:hint_enum( "only" ) = 0\n'
        source += 'uniform int f: hint_enum("Multiply", "Screen") = 1\n'
        found = self.notebook.choices(source)
        self.assertEqual(found["f"], ["Multiply", "Screen"], "a `uniform` line of a short form reads the same")
        del found["f"]
        self.assertEqual(found, {"a": ["x", "y, z"], "e": ["only"]}, "unquoted or empty labels leave the line a slider")

    def test_the_debounce_worker_sends_what_waited(self) -> None:
        """A send in flight holds the worker, the moves that come meanwhile replace each other and one newest runs."""
        sent: list[dict] = []
        sending, release = threading.Event(), threading.Event()

        def send(values: dict) -> None:
            sent.append(values)
            sending.set()
            release.wait(5)

        debounce = self.notebook.Debounce(send, interval=0.01)
        debounce({"a": 1})
        self.assertTrue(sending.wait(5))
        debounce({"a": 2})
        debounce({"a": 3})
        release.set()
        debounce.settle()
        self.assertEqual(sent, [{"a": 1}, {"a": 3}])

    def test_a_kernel_that_does_not_compile_fails_the_cell_and_says_the_apps_line_once(self) -> None:
        """The cell raises the `SaraError`, so IPython marks
        it failed, and no widget repeats the line the handler of `sara.init` shows. The line is the app's sentence
        after the step's name, as the client says since a refused step stopped showing its JSON."""
        broken = CELLS.replace("image_load(src, pixel)", "no_such_thing")
        with mock.patch.object(self.notebook, "display") as shown:
            with self.assertRaises(sara.SaraError) as raised:
                self.run_cell("Background -> Broken", broken)
        shown.assert_not_called()
        self.assertTrue(str(raised.exception).startswith("kernel: "), str(raised.exception))
        self.assertNotIn("SaCapture", str(raised.exception), "the app's sentence, not its answer line")
        self.assertIn("no_such_thing", str(raised.exception))

    def test_init_in_a_shell_registers_the_magic_on_the_connection_it_made(self) -> None:
        """The door serves one client, so the magic must not connect a second."""
        self.doc.close()
        self.notebook.use(None)
        self.notebook.GmacsMagics.last = None
        self.shell.magics_manager.magics["cell"].pop("gmacs", None)
        with mock.patch.object(sara, "TRANSPORT", "tcp"):
            doc, layer, pixels = sara.init(self.stub.file, attach=True)
        self.addCleanup(doc.close)
        self.assertEqual((layer.key, pixels.shape), ("Background", (16, 16, 4)))
        self.assertIs(self.notebook.GmacsMagics.document, doc)
        self.assertIsNotNone(self.run_cell("Background -> Cells scale=12"))
        self.assertEqual(self.stub.connections, 2, "the case's own and init's, none for the cell")

    def test_registering_makes_one_hidden_widget_before_any_cell_does(self) -> None:
        """VS Code's renderer fails the first widget a kernel announces while it loads its modules, so that
        widget is one nobody sees, made once however often the magic is registered."""
        import ipywidgets

        self.notebook.register(self.shell)
        first = self.notebook._warm_up
        self.assertIsInstance(first, ipywidgets.Label)
        self.notebook.register(self.shell)
        self.assertIs(self.notebook._warm_up, first, "one per kernel")
        box = self.run_cell("Background -> Cells scale=12").build([])
        self.assertNotIn(first, self.widgets_under(box))

    def test_the_first_line_reads_layers_values_and_a_rectangle(self) -> None:
        line = self.notebook.CellLine("'My layer' -> 2 amount=0.5 rect=0,0,64,32")
        self.assertEqual((line.layer, line.into, line.values, line.rect), ("My layer", 2, {"amount": 0.5}, [0, 0, 64, 32]))
        with self.assertRaises(ValueError):
            self.notebook.CellLine("a b c")

    def test_the_first_line_names_a_layer_for_each_further_image(self) -> None:
        """A word `<image>=<layer>` binds a readonly image the kernel declares."""
        self.assertEqual(self.notebook.images(MIXED), {"src1"}, "src is the line's first layer, dst is written")
        self.assertEqual(self.notebook.images(CELLS), set())
        line = self.notebook.CellLine("First src1='My sky' -> Out weight=0.5", {"src1"})
        self.assertEqual((line.layer, line.into, line.inputs, line.values), ("First", "Out", {"src1": "My sky"}, {"weight": 0.5}))
        self.assertEqual(self.notebook.CellLine("0 src1=3", {"src1"}).inputs, {"src1": 3}, "a number is the layer's index")
        with self.assertRaises(ValueError, msg="an image the kernel never declared is no layer"):
            self.notebook.CellLine("First src2=Sky", {"src1"})

    def test_a_cell_reading_two_layers_sends_the_step_written_with_inputs_by_hand(self) -> None:
        self.doc.door.send({"layer": {"add": "Second"}})
        cell = self.run_cell("Background src1=Second -> Mixed weight=0.5 rect=0,0,8,8", MIXED)
        by_hand = {"source": MIXED, "name": "mixed", "params": {"weight": 0.5}, "layer": "Background"}
        by_hand.update({"into": "Mixed", "rect": [0, 0, 8, 8], "inputs": {"src1": "Second"}})
        self.assertEqual(self.kernels(), [by_hand])
        cell.sliders["scale"].value = 1.5
        self.assertEqual(self.kernels()[1]["inputs"], {"src1": "Second"}, "a slider's rerun reads the second layer too")

    def test_the_short_pixel_form_is_sent_as_the_pixels_kernel(self) -> None:
        self.assertEqual(self.notebook.kernel_name(DITHER), "pixels")
        self.assertEqual(self.notebook.kernel_name(CELLS), "cells", "a kernel line still names its kernel")
        with self.assertRaises(ValueError):
            self.notebook.kernel_name("def helper() -> float:\n    return 1.0\n")
        self.run_cell("Background -> Dithered", DITHER)
        sent = self.kernels()
        self.assertEqual((sent[0]["source"], sent[0]["name"]), (DITHER, "pixels"), "the body goes as it was written")

    def test_ranges_are_read_on_uniform_lines_as_on_params_lines(self) -> None:
        self.assertEqual(self.notebook.ranges(DITHER), {"levels": (2.0, 16.0, None), "steps": (1.0, 8.0, None)})
        self.assertEqual(self.notebook.ranges(CELLS), {"scale": (2.0, 64.0, None), "seeds": (1.0, 32.0, None)})
        hinted = "uniform float level: hint_range(0, 1, 0.25) = 0.5\nuniform int steps: hint_range(1, 8) = 3    # range 0 100\n"
        self.assertEqual(self.notebook.ranges(hinted), {"level": (0.0, 1.0, 0.25), "steps": (1.0, 8.0, None)}, "the hint reads on a uniform line, and wins over the comment")

    def test_a_short_forms_sliders_open_at_the_declared_defaults(self) -> None:
        cell = self.run_cell("Background -> Dithered", DITHER)
        levels, steps, spread = cell.sliders["levels"], cell.sliders["steps"], cell.sliders["spread"]
        self.assertEqual((levels.min, levels.max, levels.value), (2.0, 16.0, 4.0))
        self.assertEqual((steps.min, steps.max, steps.value), (1, 8, 3))
        self.assertEqual((spread.min, spread.max, spread.value), (0.0, 1.0, 0.25), "an unranged uniform keeps its default too")

    def test_sara_py_stays_free_of_ipython(self) -> None:
        """`init()` names IPython to look for it among the loaded modules, and imports neither it nor its widgets."""
        tree = ast.parse((SCRIPTS / "sara.py").read_text(encoding="utf-8"))
        imported = [
            alias.name if isinstance(node, ast.Import) else node.module or ""
            for node in ast.walk(tree)
            if isinstance(node, (ast.Import, ast.ImportFrom))
            for alias in (node.names if isinstance(node, ast.Import) else [node])
        ]
        self.assertEqual([name for name in imported if name.split(".")[0] in ("IPython", "ipywidgets")], [])


@unittest.skipIf(MISSING, f"{' and '.join(MISSING)} not installed, the %%gmacs magic is not tested")
class ACellReadingTwoLayersInARealSara(unittest.TestCase):
    """The pixels a cell writes from two layers, against the step run by hand.

    The stub answers what its author expects, so the result is held in a real
    Sara, started as the other door suites start it, with its user folder in a folder of
    this case."""

    setUpClass = classmethod(test_sara.ARealSaraWithNoCaptureFolder.setUpClass.__func__)
    tearDownClass = classmethod(test_sara.ARealSaraWithNoCaptureFolder.tearDownClass.__func__)
    START_TIMEOUT_S = test_sara.ARealSaraWithNoCaptureFolder.START_TIMEOUT_S

    def setUp(self) -> None:
        from IPython.core.interactiveshell import InteractiveShell

        import sara_notebook

        self.notebook = sara_notebook
        self.doc = sara.connect(self.known)
        self.addCleanup(self.doc.close)
        self.doc.door.send({"wait": 30})
        self.shell = InteractiveShell.instance()
        sara_notebook.load_ipython_extension(self.shell)
        sara_notebook.use(self.doc)
        self.addCleanup(sara_notebook.use, None)

    def test_a_cell_reading_two_layers_writes_what_the_step_with_inputs_writes(self) -> None:
        folder = self.home / "d77"
        folder.mkdir(exist_ok=True)
        ramp = np.zeros((8, 8, 4), np.uint8)
        ramp[..., 0] = np.arange(8)[None, :] * 30
        ramp[..., 1] = np.arange(8)[:, None] * 20
        ramp[..., 3] = 255
        flat = np.full((8, 8, 4), (40, 90, 160, 255), np.uint8)
        (folder / "d77_first.png").write_bytes(sara.png_bytes(ramp))
        (folder / "d77_second.png").write_bytes(sara.png_bytes(flat))
        first = self.doc.import_image(str(folder / "d77_first.png"))
        second = self.doc.import_image(str(folder / "d77_second.png"))
        self.shell.run_cell_magic("gmacs", "d77_first src1=d77_second -> d77_cell weight=0.5 rect=0,0,8,8", MIXED)
        self.assertIsNotNone(self.notebook.GmacsMagics.last, "the cell ran")
        by_hand = {"source": MIXED, "name": "mixed", "params": {"weight": 0.5}, "layer": "d77_first"}
        by_hand.update({"into": "d77_by_hand", "rect": [0, 0, 8, 8], "inputs": {"src1": "d77_second"}})
        self.doc.kernel(by_hand)
        cell = self.doc.layer("d77_cell").read([0, 0, 8, 8])
        hand = self.doc.layer("d77_by_hand").read([0, 0, 8, 8])
        self.assertTrue(np.array_equal(cell, hand), f"the cell wrote {cell[0, :2].tolist()}, the step {hand[0, :2].tolist()}")
        # The layer keeps half floats, so the sum is held to their rounding and no closer.
        expected = first.read([0, 0, 8, 8]) + second.read([0, 0, 8, 8]) * 0.5
        self.assertTrue(np.allclose(cell, expected, atol=2e-3), f"not the sum: {cell[1, :2].tolist()} {expected[1, :2].tolist()}")
        self.assertGreater(len(np.unique(cell[..., 0])), 1)
        proof = os.environ.get("SARA_D77_PROOF")
        if proof:
            np.save(Path(proof) / "cell.npy", cell)
            np.save(Path(proof) / "by_hand.npy", hand)
            np.save(Path(proof) / "expected.npy", expected)


if __name__ == "__main__":
    unittest.main()
