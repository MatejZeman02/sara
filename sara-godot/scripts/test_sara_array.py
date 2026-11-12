#!/usr/bin/env python3
"""`sara_array.py` with no Sara: the kernels it writes and the steps it sends.

    cd sara-godot && PYTHONPATH=scripts python3 -m unittest scripts.test_sara_array

The five expressions below are read against the kernel text they must become,
so a change to what the array writes is a change a reader sees here. The door
is a stub that records each step and answers what Sara would, so the steps
`evaluate`, the reductions and the scratch layers send are checked too. The
same five against a running Sara are `test_door_array.py`.
"""

from __future__ import annotations

import gc
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import numpy as np  # noqa: E402
import sara  # noqa: E402
import sara_array  # noqa: E402
from sara_array import Array, NotCovered, kernel_source, where  # noqa: E402

HEAD = """kernel array_expr

{images}
image dst

params:
    vec2 extent
{params}
def array_expr():
    if pixel.x >= int(extent.x) or pixel.y >= int(extent.y):
        return
"""


def expected(images: list[str], params: int, body: str) -> str:
    declared = "\n".join(f"image {name}: readonly" for name in images)
    fields = "".join(f"    float c{i}\n" for i in range(params))
    return HEAD.format(images=declared, params=fields) + body


class StubDoor:
    """Answers the steps an Array sends the way Sara does, and keeps them."""

    def __init__(self) -> None:
        self.steps: list[dict] = []
        self.stack = [
            {"i": 0, "name": "Paint", "active": True, "bounds": [0, 0, 512, 256]},
            {"i": 1, "name": "Sky", "active": False, "bounds": [0, 0, 512, 512]},
        ]

    def verdict(self, step: dict) -> object:
        self.steps.append(step)
        kind = next(iter(step))
        if kind == "layers":
            return self.stack
        if kind == "layer":
            if "add" in step["layer"]:
                self.stack.append({"i": len(self.stack), "name": step["layer"]["add"], "active": False, "bounds": None})
            return "done"
        if kind == "kernel":
            return {"ok": True, "compiled": True}
        if kind == "reduce":
            rect = step["reduce"]["rect"]
            return {"texels": rect[2] * rect[3], "sum": [8.0, 4.0, 2.0, 2.0], "min": [-1.0, 0.0, 0.5, 1.0], "max": [3.0, 1.0, 0.5, 1.0]}
        raise AssertionError(f"the stub has no answer for {step}")

    def kinds(self) -> list[str]:
        return [next(iter(step)) for step in self.steps]


class KernelTextTest(unittest.TestCase):
    """The five expressions and the kernels they are written as."""

    def setUp(self) -> None:
        self.door = StubDoor()
        self.doc = sara.Document(self.door)  # type: ignore[arg-type]
        self.a = Array(self.doc.layer("Paint"), [0, 0, 256, 256])
        self.b = Array(self.doc.layer(1), [256, 0, 256, 256])

    def test_one_operation_on_one_layer(self) -> None:
        source, params, _ = kernel_source((self.a * 2).node)
        body = "    vec4 a0 = image_load(src, pixel)\n    vec4 t0 = (a0 * vec4(c0))\n    image_store(dst, pixel, t0)\n"
        self.assertEqual(source, expected(["src"], 1, body))
        self.assertEqual(params, {"c0": 2.0})

    def test_the_specs_own_expression_reads_two_layers(self) -> None:
        source, params, leaves = kernel_source(((self.a * 0.5 + self.b).clip(0, 1)).node)
        body = (
            "    vec4 a0 = image_load(src, pixel)\n"
            "    vec4 a1 = image_load(src1, pixel)\n"
            "    vec4 t0 = (a0 * vec4(c0))\n"
            "    vec4 t1 = (t0 + a1)\n"
            "    vec4 t2 = min(max(t1, vec4(c1)), vec4(c2))\n"
            "    image_store(dst, pixel, t2)\n"
        )
        self.assertEqual(source, expected(["src", "src1"], 3, body))
        self.assertEqual(params, {"c0": 0.5, "c1": 0.0, "c2": 1.0})
        self.assertEqual([leaf.name for leaf in leaves], ["Paint", "Sky"])

    def test_a_comparison_chooses_through_where(self) -> None:
        source, _, _ = kernel_source(where(self.a > self.b, self.a, np.sqrt(self.b)).node)
        body = (
            "    vec4 a0 = image_load(src, pixel)\n"
            "    vec4 a1 = image_load(src1, pixel)\n"
            "    vec4 t0 = vec4(greater_than(a0, a1))\n"
            "    vec4 t1 = sqrt(a1)\n"
            "    vec4 t2 = mix(t1, a0, not_equal(t0, vec4(0.0)))\n"
            "    image_store(dst, pixel, t2)\n"
        )
        self.assertEqual(source, expected(["src", "src1"], 0, body))

    def test_numpys_own_calls_and_a_constant_per_channel(self) -> None:
        tint = np.float32([1.0, 0.5, 0.25, 1.0])
        source, params, _ = kernel_source((np.maximum(1.0 - self.a, 0.0) * tint).node)
        body = (
            "    vec4 a0 = image_load(src, pixel)\n"
            "    vec4 t0 = (vec4(c0) - a0)\n"
            "    vec4 t1 = max(t0, vec4(c1))\n"
            "    vec4 t2 = (t1 * vec4(c2, c3, c4, c5))\n"
            "    image_store(dst, pixel, t2)\n"
        )
        self.assertEqual(source, expected(["src"], 6, body))
        self.assertEqual(params["c3"], 0.5)

    def test_two_rectangles_of_one_layer_are_two_images(self) -> None:
        left, right = self.a[:, :128], self.a[:, 128:]
        source, _, leaves = kernel_source((abs(left - right) ** 2).node)
        body = (
            "    vec4 a0 = image_load(src, pixel)\n"
            "    vec4 a1 = image_load(src1, pixel)\n"
            "    vec4 t0 = (a0 - a1)\n"
            "    vec4 t1 = abs(t0)\n"
            "    vec4 t2 = pow(t1, vec4(c0))\n"
            "    image_store(dst, pixel, t2)\n"
        )
        self.assertEqual(source, expected(["src", "src1"], 1, body))
        self.assertEqual([leaf.rect for leaf in leaves], [[0, 0, 128, 256], [128, 0, 128, 256]])

    def test_numbers_past_the_block_are_written_as_literals(self) -> None:
        tree = self.a
        for step in range(sara_array.PARAM_FLOATS + 2):
            tree = tree + step
        source, params, _ = kernel_source(tree.node)
        self.assertEqual(len(params), sara_array.PARAM_FLOATS)
        self.assertIn("vec4(24.0)", source)
        self.assertEqual(sara_array._literal(float("inf")), "uint_bits_to_float(0x7f800000u)")
        self.assertEqual(sara_array._literal(3), "3.0")


class ShapeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.door = StubDoor()
        self.doc = sara.Document(self.door)  # type: ignore[arg-type]

    def test_a_layer_is_what_it_holds_and_a_slice_is_a_rectangle(self) -> None:
        a = Array(self.doc.layer(0))
        self.assertEqual(a.shape, (256, 512, 4))
        cut = a[10:-10, 100:200]
        self.assertEqual(cut.shape, (236, 100, 4))
        self.assertEqual(cut.node.rect, [100, 10, 100, 236])
        self.assertEqual(a[..., :][5:6].node.rect, [0, 5, 512, 1])

    def test_what_is_not_covered_says_the_call(self) -> None:
        a = Array(self.doc.layer("Paint"))
        cases = {
            "numpy.fft": lambda: np.fft.fft2(a),
            "a channel": lambda: a[:, :, 0],
            "a step": lambda: a[::2],
            "numpy.arctan2": lambda: np.arctan2(a, a),
            "an ndarray": lambda: a + np.zeros((3, 3)),
            "axis": lambda: a.sum(axis=0),
            "out": lambda: np.add(a, a, out=a),
        }
        for name, call in cases.items():
            with self.subTest(name), self.assertRaises(NotCovered):
                call()
        with self.assertRaises(ValueError):
            a + Array(self.doc.layer("Sky"))


class SendingTest(unittest.TestCase):
    def setUp(self) -> None:
        self.door = StubDoor()
        self.doc = sara.Document(self.door)  # type: ignore[arg-type]
        self.a = Array(self.doc.layer("Paint"), [0, 0, 256, 256])
        self.b = Array(self.doc.layer("Sky"), [256, 0, 256, 256])

    def test_nothing_is_sent_until_a_result_is_asked_for(self) -> None:
        before = len(self.door.steps)
        (self.a * 0.5 + self.b).clip(0, 1)
        self.assertEqual(len(self.door.steps), before)

    def test_evaluate_is_one_kernel_into_a_hidden_scratch_layer(self) -> None:
        result = (self.a + self.b).evaluate()
        kernel = self.door.steps[-1]["kernel"]
        self.assertEqual(kernel["layer"], "Paint")
        self.assertEqual(kernel["rect"], [0, 0, 256, 256])
        self.assertEqual(kernel["inputs"], {"src1": {"layer": "Sky", "at": [256, 0]}})
        self.assertEqual(kernel["into"], "Array scratch 1")
        added = [s["layer"] for s in self.door.steps if next(iter(s)) == "layer"]
        self.assertEqual(added, [{"add": "Array scratch 1", "visible": False}, {"activate": "Paint"}])
        self.assertEqual(result.node.rect, [0, 0, 256, 256])

    def test_a_freed_result_gives_its_scratch_layer_back(self) -> None:
        kept = (self.a * 2).evaluate()
        (self.a * 3).evaluate()
        gc.collect()
        (self.a * 4).evaluate()
        into = [s["kernel"]["into"] for s in self.door.steps if next(iter(s)) == "kernel"]
        self.assertEqual(into, ["Array scratch 1", "Array scratch 2", "Array scratch 2"])
        derived = kept + 1
        del kept
        gc.collect()
        derived.evaluate()
        into = [s["kernel"]["into"] for s in self.door.steps if next(iter(s)) == "kernel"]
        self.assertNotEqual(into[-1], "Array scratch 1", "a tree that reads a scratch layer keeps it")

    def test_the_reductions_read_the_reduce_step(self) -> None:
        self.assertEqual(self.a.sum(), np.float32(16.0))
        self.assertEqual(self.a.min(), np.float32(-1.0))
        np.testing.assert_allclose(self.a.max(axis=(0, 1)), [3.0, 1.0, 0.5, 1.0])
        self.assertAlmostEqual(float(np.mean(self.a)), 16.0 / (256 * 256 * 4))
        np.testing.assert_allclose(self.a.mean(axis=(0, 1)), np.float32([8.0, 4.0, 2.0, 2.0]) / (256 * 256))
        self.assertEqual(self.door.steps[-1]["reduce"], {"layer": "Paint", "rect": [0, 0, 256, 256], "ops": ["sum"]})
        self.assertNotIn("kernel", self.door.kinds(), "a layer is reduced where it is, with no kernel")


if __name__ == "__main__":
    unittest.main()
