#!/usr/bin/env python3
"""The `PARAMS` parser: the Krita plugin template's format, read as it is.

    cd sara-godot && PYTHONPATH=scripts python3 -m unittest scripts.test_sara_params

The format is the courses session's, sent on 2026-10-02 after it built and tried the template in Krita 6.0.3.
These cases hold the five kinds in their order with what `apply` gets for each, and one case of every
refusal the format names. They need NumPy and nothing else, so they run where `ipywidgets` is not installed.
"""

from __future__ import annotations

import ast
import sys
import unittest
from pathlib import Path

import numpy as np

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))

import sara_params  # noqa: E402
from sara_params import BOOL, CHOICE, COLOR, FLOAT, INT, MATRIX, ParamError  # noqa: E402

# The documented example, one of each kind.
EXAMPLE = {
    "amount": (1.0, 0.0, 1.0),
    "width": (16.0, 2.0, 64.0, 0.5),
    "steps": (4, 1, 8),
    "tint": "#ff8c32",
    "veil": "#3070ff80",
    "mode": ["Multiply", "Screen"],
    "invert": False,
    "weights": [[0, 1, 0], [1, -4, 1], [0, 1, 0]],
}


class ParamsTests(unittest.TestCase):
    def refused(self, value: object, *words: str, name: str = "x") -> str:
        with self.assertRaises(ParamError) as raised:
            sara_params.parse({name: value})
        said = str(raised.exception)
        self.assertIn(repr(name), said, "a refusal names the parameter")
        self.assertIn("A parameter is a bool", said, "and the forms there are")
        for word in words:
            self.assertIn(word, said)
        return said

    def test_the_example_parses_in_the_dicts_order_to_the_widgets_kinds(self) -> None:
        params = sara_params.parse(EXAMPLE)
        self.assertEqual([p.name for p in params], list(EXAMPLE))
        self.assertEqual([p.kind for p in params], [FLOAT, FLOAT, INT, COLOR, COLOR, CHOICE, BOOL, MATRIX])

    def test_each_value_apply_gets_before_any_move(self) -> None:
        got = {p.name: p.initial() for p in sara_params.parse(EXAMPLE)}
        self.assertEqual(got["amount"], 1.0)
        self.assertIs(type(got["amount"]), float)
        self.assertEqual(got["width"], 16.0)
        self.assertEqual(got["steps"], 4)
        self.assertIs(type(got["steps"]), int, "all whole numbers is a whole-number slider")
        self.assertEqual(got["tint"], (255 / 255, 140 / 255, 50 / 255), "sRGB as the picker shows it, no linear conversion")
        self.assertEqual(got["veil"], (48 / 255, 112 / 255, 255 / 255, 128 / 255), "alpha last as written, not Qt's #aarrggbb")
        self.assertEqual(got["mode"], "Multiply", "the label, and the first is the default")
        self.assertIs(got["invert"], False)
        weights = got["weights"]
        self.assertEqual((weights.dtype, weights.shape), (np.float32, (3, 3)))
        self.assertEqual(weights.tolist(), [[0, 1, 0], [1, -4, 1], [0, 1, 0]], "row by row")

    def test_a_slider_has_its_limits_and_its_step(self) -> None:
        amount, width, steps = sara_params.parse(EXAMPLE)[:3]
        self.assertEqual((amount.low, amount.high, amount.step), (0.0, 1.0, 0.01), "a float steps a hundredth of its range")
        self.assertEqual((width.low, width.high, width.step), (2.0, 64.0, 0.5), "or by the fourth number")
        self.assertEqual((steps.low, steps.high, steps.step), (1, 8, 1), "a whole number steps by one")
        mixed = sara_params.parse({"x": (1, 0.0, 4)})[0]
        self.assertEqual((mixed.kind, mixed.default), (FLOAT, 1.0), "one float among the numbers makes a float slider")
        self.assertEqual(sara_params.parse({"x": (2, 0, 8, 2)})[0].step, 2)

    def test_a_bool_is_a_checkbox_and_never_a_whole_number(self) -> None:
        self.assertEqual(sara_params.parse({"x": True})[0].kind, BOOL, "True is an int in Python, so the bool is checked first")
        self.refused((True, 0, 1), "numbers only")
        self.assertIs(sara_params.parse({"x": True})[0].value(1), True)

    def test_a_drop_down_hands_apply_the_label_and_a_colour_its_floats(self) -> None:
        mode, tint = sara_params.parse({"mode": ["Multiply", "Screen"], "tint": "#808080"})
        self.assertEqual(mode.value("Screen"), "Screen")
        self.assertEqual(mode.labels, ("Multiply", "Screen"))
        self.assertEqual(tint.value("#000000"), (0.0, 0.0, 0.0))
        self.assertEqual(tint.value("#FFFFFF"), (1.0, 1.0, 1.0), "either case of a hex digit")
        self.assertEqual(tint.value("#808080"), (128 / 255,) * 3, "the sRGB number, not 0.2158")
        self.assertFalse(tint.alpha)
        self.assertTrue(sara_params.parse({"c": "#00000000"})[0].alpha)

    def test_a_grid_is_a_new_array_each_time_and_any_size(self) -> None:
        weights = sara_params.parse({"w": [[1, 2], [3, 4]]})[0]
        first = weights.initial()
        first[:] = 9.0
        self.assertEqual(weights.initial().tolist(), [[1, 2], [3, 4]], "what apply changes is not what the next call gets")
        five = sara_params.parse({"k": [[0] * 5 for _ in range(5)]})[0]
        self.assertEqual((five.kind, five.size, five.initial().shape), (MATRIX, 5, (5, 5)))
        self.assertEqual(sara_params.parse({"k": [[2.5]]})[0].initial().tolist(), [[2.5]])
        moved = weights.value([[5, 6], [7, 8]])
        self.assertEqual(moved.tolist(), [[5, 6], [7, 8]])

    def test_a_slider_is_refused_for_each_fault_it_can_have(self) -> None:
        self.refused((1.0, 1.0, 1.0), "minimum 1.0 is not below the maximum 1.0")
        self.refused((1.0, 2.0, 1.0), "not below the maximum")
        self.refused((5.0, 0.0, 1.0), "default 5.0 is outside 0.0 to 1.0")
        self.refused((-1, 0, 1), "default -1 is outside")
        self.refused((0.5, 0.0, 1.0, 0.0), "step 0.0 is not above 0")
        self.refused((0.5, 0.0, 1.0, -0.1), "step -0.1 is not above 0")
        self.refused((0.5, 0.0), "holds 3 or 4 numbers, this holds 2")
        self.refused((0.5, 0.0, 1.0, 0.1, 9), "this holds 5")
        self.refused((0.5, "a", 1.0), "numbers only")
        self.refused((0.5, None, 1.0), "numbers only")
        self.refused((float("nan"), 0.0, 1.0), "numbers only")
        self.refused((0.5, 0.0, float("inf")), "numbers only")

    def test_a_colour_a_list_and_a_grid_are_refused_for_each_fault_they_can_have(self) -> None:
        self.refused("ff8c32", "is not \"#rrggbb\" or \"#rrggbbaa\"")
        self.refused("#ff8c3", "is not")
        self.refused("#ff8c32f", "is not")
        self.refused("#gg8c32", "is not")
        self.refused("red", "is not")
        self.refused([], "the list is empty")
        self.refused(["a", 3], "only str, or only lists")
        self.refused([[1, 2], "a"], "only str, or only lists")
        self.refused([[1, 2], [3]], "a grid is square, this has 2 rows of lengths [2, 1]", "square")
        self.refused([[1, 2, 3], [4, 5, 6]], "square")
        self.refused([[1, 2], [3, "a"]], "numbers only")
        self.refused([[1, 2], [3, True]], "numbers only")
        self.refused([[]], "square")

    def test_anything_else_is_refused_with_its_type(self) -> None:
        self.refused(None, "NoneType")
        self.refused({"a": 1}, "dict")
        self.refused(3, "int 3")
        self.refused(2.5, "float")
        self.refused(np.eye(3), "ndarray")
        self.refused({1, 2}, "set")

    def test_a_name_that_is_no_identifier_is_refused_and_so_is_a_params_that_is_no_dict(self) -> None:
        for name in ("two words", "1st", "", "a-b"):
            with self.assertRaises(ParamError) as raised:
                sara_params.parse({name: 1.0})
            self.assertIn(repr(name), str(raised.exception))
            self.assertIn("identifier", str(raised.exception))
        with self.assertRaises(ParamError) as raised:
            sara_params.parse({1: (0, 0, 1)})
        self.assertIn("identifier", str(raised.exception))
        with self.assertRaises(ParamError):
            sara_params.parse([("a", 1)])  # type: ignore[arg-type]
        self.assertEqual(sara_params.parse({}), [])

    def test_the_parser_imports_numpy_and_the_standard_library_only(self) -> None:
        tree = ast.parse((SCRIPTS / "sara_params.py").read_text(encoding="utf-8"))
        imported = {
            (alias.name if isinstance(node, ast.Import) else node.module or "").split(".")[0]
            for node in ast.walk(tree)
            if isinstance(node, (ast.Import, ast.ImportFrom))
            for alias in (node.names if isinstance(node, ast.Import) else [node])
        }
        self.assertLessEqual(imported, {"__future__", "math", "re", "numbers", "typing", "numpy"})


if __name__ == "__main__":
    unittest.main()
