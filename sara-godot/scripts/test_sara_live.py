#!/usr/bin/env python3
"""`sara.live` against the stub door of `test_sara.py`.

    cd sara-godot && PYTHONPATH=scripts python3 -m unittest scripts.test_sara_live

The runner reads `source`, calls the student's `apply(img, **values)` first with the defaults and then on every
widget move, a drag once a frame, and writes what it answers to the layer called `target`. The parser it reads
`PARAMS` with is `test_sara_params.py`'s. Where IPython or `ipywidgets` is not installed every case skips with
a line saying which.

A drag is one undo step. Its writes send `"history": false` and the let go writes the last picture once
more with history on, which the stub cases hold the requests of. The last class starts a real Sara, the only
thing that can say what its history did, with the fixture borrowed from `test_sara.py` as the bench suite does.
"""

from __future__ import annotations

import importlib.util
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

import numpy as np

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))

MISSING = [name for name in ("IPython", "ipywidgets") if importlib.util.find_spec(name) is None]
if MISSING:
    # The runner shows a skip's reason only when verbose, so the line is said here too.
    print(f"test_sara_live: {' and '.join(MISSING)} not installed, the sara.live cases skip", file=sys.stderr)

import sara  # noqa: E402
import test_sara  # noqa: E402
from test_sara import StubDoor  # noqa: E402
from test_sara_notebook import Clock  # noqa: E402

# The documented example, one parameter of each kind.
PARAMS = {
    "amount": (1.0, 0.0, 1.0),
    "width": (16.0, 2.0, 64.0, 0.5),
    "steps": (4, 1, 8),
    "tint": "#ff8c32",
    "veil": "#3070ff80",
    "mode": ["Multiply", "Screen"],
    "invert": False,
    "weights": [[0, 1, 0], [1, -4, 1], [0, 1, 0]],
}


@unittest.skipIf(MISSING, f"{' and '.join(MISSING)} not installed, sara.live is not tested")
class LiveTests(unittest.TestCase):
    def setUp(self) -> None:
        from IPython.core.interactiveshell import InteractiveShell

        import sara_live
        import sara_notebook

        self.live = sara_live
        self.notebook = sara_notebook
        folder = Path(tempfile.mkdtemp(prefix="sara-live-"))
        self.stub = StubDoor(folder, "tcp")
        self.addCleanup(self.stub.close)
        with mock.patch.object(sara, "TRANSPORT", "tcp"):
            self.doc = sara.connect(self.stub.file)
        self.addCleanup(self.doc.close)
        InteractiveShell.instance()
        sara_notebook.use(self.doc)
        self.addCleanup(sara_notebook.use, None)
        self.addCleanup(setattr, sara_live, "last", None)
        # A wait for the let go that outlived its case would write to the next case's stub.
        self.addCleanup(lambda: sara_live.last is not None and sara_live.last.cancel())
        # And one that ran out inside a slow case would add a write the case does not count.
        resting = mock.patch.object(sara_live, "LET_GO_S", 60.0)
        resting.start()
        self.addCleanup(resting.stop)
        # The cell's output is a notebook's to draw, a bare shell would print each widget's repr.
        patched = mock.patch.object(sara_live, "display")
        patched.start()
        self.addCleanup(patched.stop)
        self.picture = np.linspace(0.0, 1.0, 16 * 16 * 4, dtype=np.float32).reshape(16, 16, 4)
        self.doc.layer("Background").write(self.picture)
        self.doc.new_layer("balls", self.picture * 0.5)
        self.laid = len(self.writes())
        self.calls: list[tuple[np.ndarray, dict]] = []

    def apply(self, img: np.ndarray, **values: object) -> np.ndarray:
        """The student's function: it keeps what it was given and answers the picture scaled by `amount`."""
        self.calls.append((img, values))
        return img * np.float32(values["amount"])

    def target(self, name: str) -> np.ndarray:
        return next(pixels for layer, pixels in self.stub.layers if layer == name)

    def start(self, **given: object):
        sara_live = self.live
        sara_live.live(self.apply, PARAMS, **given)
        return sara_live.last

    def writes(self) -> list[dict]:
        return [r["write_pixels"] for r in self.stub.requests if "write_pixels" in r]

    def sent(self) -> list[dict]:
        """The writes since the two `setUp` lays the layers with."""
        return self.writes()[self.laid :]

    def test_the_runner_reads_the_source_and_writes_applys_answer_to_the_target(self) -> None:
        run = self.start(source="balls", target="Goal NumPy")
        self.assertEqual(len(self.calls), 1, "one run with the defaults, before any move")
        img, values = self.calls[0]
        self.assertEqual((img.dtype, img.shape), (np.float32, (16, 16, 4)))
        np.testing.assert_array_equal(img, self.picture * 0.5, "it read `balls`, not the selected layer")
        np.testing.assert_array_equal(self.target("Goal NumPy"), self.picture * 0.5, "an amount of 1.0 hands the picture back")
        self.assertEqual(self.writes()[-1]["new_layer"], "Goal NumPy")
        self.assertIs(run.controls["amount"].main.value, 1.0)

    def test_each_value_apply_gets_before_any_move_is_the_parsers(self) -> None:
        self.start(source="balls", target="Goal NumPy")
        values = self.calls[0][1]
        self.assertEqual(list(values), list(PARAMS), "keywords in the dict's order")
        self.assertEqual((values["amount"], values["width"], values["steps"]), (1.0, 16.0, 4))
        self.assertIs(type(values["steps"]), int)
        self.assertEqual(values["tint"], (1.0, 140 / 255, 50 / 255))
        self.assertEqual(values["veil"], (48 / 255, 112 / 255, 1.0, 128 / 255))
        self.assertEqual((values["mode"], values["invert"]), ("Multiply", False))
        self.assertEqual((values["weights"].dtype, values["weights"].shape), (np.float32, (3, 3)))

    def test_the_picture_is_an_image_widget_and_no_output_widget_is_made(self) -> None:
        """VS Code's Jupyter 2025.9.1 cannot load `@jupyter-widgets/output`, the `Image` is from the module that works."""
        import ipywidgets

        run = self.start(source="balls", target="Goal NumPy")
        inside = [run.box]
        for widget in inside:
            inside += getattr(widget, "children", ())
        self.assertNotIn(ipywidgets.Output, {type(widget) for widget in inside})
        self.assertIs(run.box.children[-1], run.picture, "the picture sits last, under the status line")
        self.assertIsInstance(run.picture, ipywidgets.Image)
        self.assertEqual(run.picture.format, "png")
        self.assertEqual(run.picture.value, sara.png_bytes(sara.tone_map(self.target("Goal NumPy"))), "the first run's picture")
        run.controls["amount"].main.value = 0.5
        run.debounce.flush()
        np.testing.assert_allclose(self.target("Goal NumPy"), self.picture * 0.5 * 0.5 + 0.0, atol=1e-6)
        self.assertEqual(run.picture.value, sara.png_bytes(sara.tone_map(self.target("Goal NumPy"))), "a move replaces it in the same widget")

    def test_a_drag_inside_one_frame_runs_apply_once_with_its_last_value(self) -> None:
        run = self.start(source="balls", target="Goal NumPy")
        clock = Clock()
        run.debounce = self.notebook.Debounce(run.rerun, clock=clock)
        run.controls["amount"].main.value = 0.9
        run.debounce.settle()
        for value in (0.8, 0.7, 0.6):
            clock.now += 0.001
            run.controls["amount"].main.value = value
        self.assertEqual([c[1]["amount"] for c in self.calls], [1.0, 0.9], "the drag's first step ran, the rest wait for the frame")
        run.debounce.settle()
        self.assertEqual([c[1]["amount"] for c in self.calls], [1.0, 0.9, 0.6], "one run for the frames that followed")
        clock.now += 1.0
        run.controls["amount"].main.value = 0.5
        run.debounce.settle()
        self.assertEqual(len(self.calls), 4, "a move in the next frame runs at once")
        np.testing.assert_allclose(self.target("Goal NumPy"), self.picture * 0.5 * 0.5)

    def test_a_move_of_each_kind_of_widget_reaches_apply_as_the_value_it_declares(self) -> None:
        run = self.start(source="balls", target="Goal NumPy")
        controls = run.controls
        for name, widget_value in (("width", 20.5), ("steps", 7), ("mode", "Screen"), ("invert", True)):
            controls[name].main.value = widget_value
            run.debounce.flush()
            self.assertEqual(self.calls[-1][1][name], widget_value)
        controls["tint"].main.value = "#00ff00"
        run.debounce.flush()
        self.assertEqual(self.calls[-1][1]["tint"], (0.0, 1.0, 0.0))
        controls["veil"].alpha.value = 1.0
        run.debounce.flush()
        self.assertEqual(self.calls[-1][1]["veil"], (48 / 255, 112 / 255, 1.0, 1.0), "the alpha slider is the last number")
        controls["weights"].fields[1][1].value = -5.0
        run.debounce.flush()
        weights = self.calls[-1][1]["weights"]
        self.assertEqual((weights.dtype, weights[1, 1], weights[0, 1]), (np.float32, -5.0, 1.0))
        self.assertEqual(self.calls[-1][1]["mode"], "Screen", "the earlier moves stay")

    def test_the_widgets_are_the_ones_the_format_names(self) -> None:
        import ipywidgets

        run = self.start(source="balls", target="Goal NumPy")
        controls = run.controls
        self.assertIsInstance(controls["invert"].main, ipywidgets.Checkbox)
        self.assertIsInstance(controls["steps"].main, ipywidgets.IntSlider)
        self.assertIsInstance(controls["amount"].main, ipywidgets.FloatSlider)
        self.assertEqual((controls["width"].main.min, controls["width"].main.max, controls["width"].main.step), (2.0, 64.0, 0.5))
        self.assertAlmostEqual(controls["amount"].main.step, 0.01)
        self.assertEqual((controls["steps"].main.min, controls["steps"].main.max, controls["steps"].main.step), (1, 8, 1))
        self.assertIsInstance(controls["tint"].main, ipywidgets.ColorPicker)
        self.assertIsNone(controls["tint"].alpha, "the six-digit form has no alpha")
        self.assertIsInstance(controls["veil"].alpha, ipywidgets.FloatSlider)
        self.assertEqual(controls["veil"].main.value, "#3070ff")
        self.assertAlmostEqual(controls["veil"].alpha.value, 128 / 255)
        self.assertIsInstance(controls["mode"].main, ipywidgets.Dropdown)
        self.assertEqual(list(controls["mode"].main.options), ["Multiply", "Screen"])
        grid = controls["weights"].fields
        self.assertEqual([[field.value for field in row] for row in grid], [[0, 1, 0], [1, -4, 1], [0, 1, 0]])
        self.assertTrue(all(isinstance(field, ipywidgets.FloatText) for row in grid for field in row))

    def test_apply_changing_its_picture_or_its_grid_changes_nothing_for_the_next_run(self) -> None:
        def greedy(img: np.ndarray, **values: object) -> np.ndarray:
            self.calls.append((img.copy(), {k: (v.copy() if isinstance(v, np.ndarray) else v) for k, v in values.items()}))
            img *= 0.0
            values["weights"][:] = 7.0
            return img + 0.25

        self.live.live(greedy, PARAMS, source="balls", target="Goal NumPy")
        run = self.live.last
        run.controls["amount"].main.value = 0.5
        run.debounce.flush()
        first, second = self.calls[0], self.calls[1]
        np.testing.assert_array_equal(second[0], first[0], "the picture it zeroed is a copy")
        np.testing.assert_array_equal(second[1]["weights"], first[1]["weights"], "and so is the grid it filled with sevens")
        np.testing.assert_array_equal(self.target("balls"), self.picture * 0.5, "the source layer is never written")

    def test_running_the_cell_again_and_every_move_leave_one_layer_of_the_target(self) -> None:
        run = self.start(source="balls", target="Goal NumPy")
        run.controls["amount"].main.value = 0.5
        run.debounce.flush()
        self.start(source="balls", target="Goal NumPy")
        names = [layer for layer, _ in self.stub.layers]
        self.assertEqual(names, ["Background", "balls", "Goal NumPy"], "a layer of that name is reused")

    def test_the_target_falls_back_to_the_notebooks_title(self) -> None:
        def apply(img: np.ndarray, **values: object) -> np.ndarray:
            return img

        apply.__globals__["TITLE"] = "Blur by hand"
        self.addCleanup(apply.__globals__.pop, "TITLE", None)
        self.live.live(apply, PARAMS, source="balls")
        self.assertEqual(self.writes()[-1]["new_layer"], "Blur by hand")
        self.live.live(apply, PARAMS, source="balls", target="Given")
        self.assertEqual(self.writes()[-1]["new_layer"], "Given", "a target named in the call wins")
        apply.__globals__.pop("TITLE")
        self.live.live(apply, PARAMS, source="balls")
        self.assertEqual(self.writes()[-1]["new_layer"], self.live.DEFAULT_TARGET)

    def test_the_source_is_the_layer_init_read_unless_the_call_names_one(self) -> None:
        self.doc.close()
        self.notebook.use(None)
        self.stub.active = 1
        with mock.patch.object(sara, "TRANSPORT", "tcp"):
            doc, layer, pixels = sara.init(self.stub.file, attach=True)
        self.addCleanup(doc.close)
        self.assertEqual(layer.key, "balls")
        doc.layer("Background").write(self.picture)
        self.stub.active = 0
        self.notebook.use(doc)
        sara.live(self.apply, PARAMS, target="Out")
        np.testing.assert_array_equal(self.calls[-1][0], self.picture * 0.5, "init read `balls`, and the selection has moved on since")
        sara.live(self.apply, PARAMS, source=doc.layer(0), target="Out")
        np.testing.assert_array_equal(self.calls[-1][0], self.picture, "a Layer is taken as it is")
        sara.live(self.apply, PARAMS, source=0, target="Out")
        np.testing.assert_array_equal(self.calls[-1][0], self.picture, "and so is an index")

    def test_a_layer_as_the_source_brings_its_document_so_a_script_dials_no_second_connection(self) -> None:
        self.notebook.use(None)
        before = self.stub.connections
        sara.live(self.apply, PARAMS, source=self.doc.layer("balls"), target="Out")
        self.assertEqual(self.stub.connections, before, "the door serves one client, and the run used the Layer's own")
        np.testing.assert_array_equal(self.calls[-1][0], self.picture * 0.5)

    def test_p8_init_then_live_keeps_one_connection(self) -> None:
        # A plain script: no shell, no IPython among the modules and the notebook module not importable,
        # so the document `layer_of` runs on can only be the one `sara.py` held when `init()` answered.
        self.doc.close()
        self.notebook.use(None)
        self.stub.active = 1
        before = self.stub.connections
        loaded = [name for name in sys.modules if name == "IPython" or name.startswith("IPython.")]
        with mock.patch.dict(sys.modules, {"sara_notebook": None}):
            for name in loaded:
                del sys.modules[name]
            with mock.patch.object(sara, "TRANSPORT", "tcp"):
                doc, layer, _ = sara.init(self.stub.file, attach=True)
            self.addCleanup(doc.close)
            self.assertNotIn("IPython", sys.modules, "init loaded nothing of IPython")
            self.assertIs(sara.layer_of(None), layer, "the fallback is init's own layer")
            self.assertNotIn("IPython", sys.modules, "and finding it loaded nothing of IPython")
            self.stub.active = 0
            # The run draws under an `ipywidgets.Output`, whose `with` asks IPython for a shell and finds none.
            sara.live(self.apply, PARAMS, target="Out")
        self.assertEqual(self.stub.connections, before + 1, "init's one connection, and live dialled none")
        self.assertEqual(layer.key, "balls")
        np.testing.assert_array_equal(self.calls[-1][0], self.picture * 0.5, "init's layer read, not the one selected since")
        np.testing.assert_array_equal(self.target("Out"), self.picture * 0.5, "and the target written")

        doc.close()
        with mock.patch.object(sara, "TRANSPORT", "tcp"), mock.patch.dict("os.environ", {sara.DOOR_FILE_ENV: str(self.stub.file)}):
            sara.live(self.apply, PARAMS, target="Out")
        self.addCleanup(lambda: self.notebook.GmacsMagics.document.close())
        self.assertEqual(self.stub.connections, before + 2, "a document closed is not reused, the next call connects")
        np.testing.assert_array_equal(self.calls[-1][0], self.picture, "and runs on the layer selected in Sara")

    def test_a_connect_with_no_init_runs_on_the_layer_selected_in_sara(self) -> None:
        self.assertIsNone(self.doc.home)
        sara.live(self.apply, PARAMS, target="Out")
        np.testing.assert_array_equal(self.calls[-1][0], self.picture, "Background is the one selected in the stub")

    def test_an_answer_that_is_not_an_array_of_the_pictures_shape_with_finite_values_is_refused(self) -> None:
        def answers(result: object):
            return lambda img, **values: result

        wrong = {
            "a list": ([[0.0]] * 16, "list"),
            "a shape": (np.zeros((16, 16, 3), np.float32), "shape (16, 16, 3)"),
            "None": (None, "NoneType"),
            "a NaN": (np.where(self.picture > 0.5, np.nan, 0.0).astype(np.float32), "finite"),
            "an infinity": (np.full((16, 16, 4), np.inf, np.float32), "finite"),
            "text": (np.full((16, 16, 4), "x"), "finite"),
        }
        before = len(self.writes())
        for label, (result, word) in wrong.items():
            with self.subTest(label), self.assertRaises(self.live.ResultError) as raised:
                self.live.live(answers(result), PARAMS, source="balls", target="Refused")
            self.assertIn(word, str(raised.exception))
        self.assertEqual(len(self.writes()), before, "a refused answer is never written")
        self.assertNotIn("Refused", [layer for layer, _ in self.stub.layers])

    def test_a_move_whose_answer_is_refused_says_so_under_the_widgets_and_the_next_move_goes_on(self) -> None:
        def flaky(img: np.ndarray, amount: float, **rest: object) -> np.ndarray:
            if amount < 0.5:
                raise ZeroDivisionError("the slider reached the hole")
            return img * np.float32(amount)

        self.live.live(flaky, PARAMS, source="balls", target="Goal NumPy")
        run = self.live.last
        written = len(self.writes())
        run.controls["amount"].main.value = 0.25
        run.debounce.flush()
        self.assertEqual(run.status.value, "ZeroDivisionError: the slider reached the hole")
        self.assertEqual(len(self.writes()), written, "nothing was written for it")
        run.controls["amount"].main.value = 0.75
        run.debounce.flush()
        self.assertRegex(run.status.value, r"^apply \d+ ms, written \d+ ms$")
        np.testing.assert_allclose(self.target("Goal NumPy"), self.picture * 0.5 * 0.75)

    def test_a_drag_writes_without_history_and_its_let_go_writes_once_with_it(self) -> None:
        run = self.start(source="balls", target="Goal NumPy")
        first = self.sent()[-1]
        self.assertNotIn("history", first, "the cell's own run records its step at once")
        self.assertEqual(first["name"], "live Goal NumPy")
        for value in (0.9, 0.8, 0.7):
            run.controls["amount"].main.value = value
            run.debounce.flush()
        self.assertEqual([w.get("history") for w in self.sent()[1:]], [False] * 3, "each write of the drag records none")
        self.assertIsNotNone(run.armed, "and the wait for the let go runs")
        run.let_go()
        self.assertEqual(len(self.sent()), 5, "the let go is one write more")
        self.assertNotIn("history", self.sent()[-1], "which records")
        self.assertEqual(self.sent()[-1]["name"], "live Goal NumPy", "under the cell's name")
        np.testing.assert_allclose(self.target("Goal NumPy"), self.picture * 0.5 * 0.7, err_msg="the drag's last picture")
        self.assertIsNone(run.armed)
        run.let_go()
        self.assertEqual(len(self.sent()), 5, "a second let go has nothing to send")
        settles = [r.get("settle") for r in self.stub.requests if "write_pixels" in r]
        self.assertEqual(settles, [0] * (self.laid + 5), "every write asks the door to answer in the frame it ran")

    def test_the_let_go_is_written_once_the_widgets_have_rested(self) -> None:
        run = self.start(source="balls", target="Goal NumPy")
        with mock.patch.object(self.live, "LET_GO_S", 0.05):
            run.controls["amount"].main.value = 0.5
            run.debounce.flush()
        deadline = time.monotonic() + 10.0
        while len(self.sent()) < 3 and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertEqual([w.get("history", True) for w in self.sent()], [True, False, True], "the wait ran out and let go")
        self.assertIsNone(run.armed)

    def test_a_wait_a_later_move_started_again_sends_nothing(self) -> None:
        run = self.start(source="balls", target="Goal NumPy")
        run.controls["amount"].main.value = 0.5
        run.debounce.flush()
        stale = run.armed
        run.controls["amount"].main.value = 0.25
        run.debounce.flush()
        self.assertIsNot(run.armed, stale, "the move started the wait again")
        stale.join(5.0)
        self.assertFalse(stale.is_alive(), "and stopped the old one")
        run.rested()
        self.assertEqual(len(self.sent()), 3, "a call from a thread that is not the running wait sends nothing")

    def test_running_the_cell_again_in_the_middle_of_a_drag_lets_the_drag_go_first(self) -> None:
        run = self.start(source="balls", target="Goal NumPy")
        run.controls["amount"].main.value = 0.5
        run.debounce.flush()
        self.start(source="balls", target="Goal NumPy")
        self.assertEqual([w.get("history", True) for w in self.sent()], [True, False, True, True], "the drag's step, then the cell's")
        self.assertIsNone(run.armed, "and the old run waits for nothing")

    def test_a_layers_write_and_a_new_layer_take_history_off(self) -> None:
        self.doc.layer("balls").write(self.picture, history=False)
        self.doc.new_layer("Other", self.picture, history=False)
        self.doc.layer("balls").write(self.picture)
        sent = self.writes()[-3:]
        self.assertEqual([w.get("history", True) for w in sent], [False, False, True])

    def test_a_params_that_is_refused_raises_before_anything_reaches_sara(self) -> None:
        from sara_params import ParamError

        before = len(self.stub.requests)
        with self.assertRaises(ParamError) as raised:
            sara.live(self.apply, {"amount": (2.0, 0.0, 1.0)}, source="balls")
        self.assertIn("'amount'", str(raised.exception))
        self.assertEqual(len(self.stub.requests), before)
        with self.assertRaises(TypeError):
            sara.live("not a function", PARAMS, source="balls")  # type: ignore[arg-type]

    def test_sara_live_is_the_runner_and_sara_py_still_imports_neither_module_at_the_top(self) -> None:
        self.assertIs(sara.live.__name__, "live")
        self.assertNotIn("sara_live", sys.modules.get("sara").__dict__, "imported at the first call, not at import")


@unittest.skipIf(MISSING, f"{' and '.join(MISSING)} not installed, sara.live is not tested")
class ALiveDragInARealSara(unittest.TestCase):
    """The history of the real app, read from the door's state dump."""

    START_TIMEOUT_S = test_sara.ARealSaraWithNoCaptureFolder.START_TIMEOUT_S
    setUpClass = classmethod(test_sara.ARealSaraWithNoCaptureFolder.setUpClass.__func__)
    tearDownClass = classmethod(test_sara.ARealSaraWithNoCaptureFolder.tearDownClass.__func__)
    setUp = test_sara.ARealSaraWithNoCaptureFolder.setUp
    names = test_sara.ARealSaraWithNoCaptureFolder.names

    def steps(self) -> int:
        return self.doc.door.send({"state": "d113", "dump": True})["state"]["history"]["steps"]

    def test_a_drag_of_thirty_steps_is_one_undo_step_back_to_the_cells_own_run(self) -> None:
        from IPython.core.interactiveshell import InteractiveShell

        import sara_live

        doc = self.doc
        self.addCleanup(lambda: [doc.layer(n).delete() for n in self.names() if n.startswith("Probe")])
        self.addCleanup(setattr, sara_live, "last", None)
        self.addCleanup(lambda: sara_live.last is not None and sara_live.last.cancel())
        for patched in (mock.patch.object(sara_live, "display"), mock.patch.object(sara_live, "LET_GO_S", 60.0)):
            patched.start()
            self.addCleanup(patched.stop)
        InteractiveShell.instance()
        source = doc.new_layer("Source", np.full((16, 16, 4), 0.5, np.float32), rect=[0, 0, 16, 16])
        before = self.steps()

        sara_live.live(lambda img, amount: img * np.float32(amount), {"amount": (1.0, 0.0, 1.0)}, source=source, target="Live")
        run = sara_live.last
        after_the_cell = self.steps()
        self.assertEqual(after_the_cell, before + 1, "the cell's own run is a step")
        live = doc.layer("Live")
        value = lambda: float(live.read([0, 0, 16, 16])[3, 3, 0])  # noqa: E731
        for i in range(30):
            run.controls["amount"].main.value = 0.95 - i / 64
            run.debounce.flush()
        self.assertEqual(self.steps(), after_the_cell, "thirty writes of a drag record none")
        dragged = 0.5 * run.values["amount"]
        self.assertAlmostEqual(value(), dragged, places=3, msg="and the last one is the picture")

        run.let_go()
        self.assertEqual(self.steps(), after_the_cell + 1, "the let go records the drag's one step")
        self.assertAlmostEqual(value(), dragged, places=3, msg="and changes nothing in the picture")
        doc.undo()
        self.assertAlmostEqual(value(), 0.5, places=3, msg="one undo gives back the cell's own run")
        doc.door.send({"redo": 1})
        self.assertAlmostEqual(value(), dragged, places=3, msg="and one redo the drag's last picture")


if __name__ == "__main__":
    unittest.main()
