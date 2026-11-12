#!/usr/bin/env python3
"""`sara.py` against a stub door in the same process.

    cd sara-godot && PYTHONPATH=scripts python3 -m unittest scripts.test_sara

The stub is a small socket server that speaks the contract of
the door's contract over its HTTP,
on a Unix socket or the loopback port with a token, so the client is tested
without a Sara. It counts the connections it took, so a case reads back that a
session is one. The last class starts a real Sara, because a
Windows sitting found that the app's own answers were Godot paths a Python
outside it could not open. It skips where there is no Godot or compositor.
"""

from __future__ import annotations

import importlib
import json
import os
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
import types
import unittest
import zlib
from pathlib import Path
from unittest import mock

import numpy as np

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))

import harness_platform  # noqa: E402
import sara  # noqa: E402
import sara_shot  # noqa: E402

TOKEN = "stub-token"


def http_requests(stream):  # noqa: ANN201  (a generator of pairs)
    """Each HTTP request on *stream* as its lower cased headers and its JSON body."""
    while stream.readline():
        headers = {}
        while line := stream.readline().decode().strip():
            name, _, value = line.partition(":")
            headers[name.strip().lower()] = value.strip()
        yield headers, json.loads(stream.read(int(headers.get("content-length", 0))))


def http_answer(stream, status: int, body: object) -> None:  # noqa: ANN001
    """One HTTP answer with a JSON body, as the door writes it."""
    data = json.dumps(body).encode()
    head = f"HTTP/1.1 {status} X\r\nContent-Type: application/json\r\nContent-Length: {len(data)}\r\n\r\n"
    stream.write(head.encode() + data)
    stream.flush()


class StubDoor:
    """A door that keeps its layers as arrays and answers the pixel steps."""

    def __init__(self, folder: Path, transport: str, token: str = TOKEN) -> None:
        self.folder = folder
        self.transport = transport
        ## The token the known file carries and a request must bear, another one for a Sara opened since.
        self.token = token
        self.layers = [["Background", np.zeros((16, 16, 4), np.float32)]]
        ## The index of the layer selected in the app, which a step naming none acts on.
        self.active = 0
        self.history: list[tuple[str, int, np.ndarray]] = []
        self.requests: list[dict] = []
        ## What the stack lists of a layer besides its name, the way the door keeps them.
        self.shown: dict[str, bool] = {}
        self.opacities: dict[str, float] = {}
        ## A document's only layer, locked, which a delete keeps rather than clears.
        self.locked_last = False
        ## How many connections the stub took, which a session holds one of.
        self.connections = 0
        ## The connection being served, which `drop` closes from the door's side.
        self.client: socket.socket | None = None
        self.left = threading.Event()
        ## Set to run the next step that is not an attach and then close without answering it.
        self.cut_next = False
        if transport == "unix":
            self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            self.where = {"socket": str(folder / "door.sock"), "token": token}
            self.server.bind(self.where["socket"])
        else:
            self.server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.server.bind((sara.LOOPBACK, 0))
            self.where = {"port": self.server.getsockname()[1], "token": token}
        self.server.listen(1)
        self.file = folder / "door.json"
        self.file.write_text(json.dumps(self.where), encoding="utf-8")
        self.thread = threading.Thread(target=self._serve, daemon=True)
        self.thread.start()

    def _serve(self) -> None:
        while True:
            try:
                client, _ = self.server.accept()
            except OSError:
                return
            self.connections += 1
            self.client = client
            with client, client.makefile("rwb") as stream:
                for headers, body in http_requests(stream):
                    if headers.get("authorization") != f"Bearer {self.token}":
                        http_answer(stream, 401, {"ok": False, "error": "no token"})
                        break
                    answers = [self._answer(request) for request in (body if isinstance(body, list) else [body])]
                    if self.cut_next and not any("attached" in answer for answer in answers):
                        self.cut_next = False
                        break
                    http_answer(stream, 200, answers if isinstance(body, list) else answers[0])
            self.left.set()
            # What `sa_agent_door.gd` does for an HTTP client that hangs up: the
            # door listens for the next, whoever started it.

    def drop(self) -> None:
        """What the door does to a client idle past its timeout: it closes the connection and goes on
        listening, and this answers once the close is done."""
        self.left.clear()
        self.client.shutdown(socket.SHUT_RDWR)
        if not self.left.wait(5.0):
            raise TimeoutError("the stub did not close the client")

    def _answer(self, request: dict) -> dict:
        self.requests.append(request)
        if request.get("attach"):
            return {"id": request["id"], "ok": True, "attached": True}
        return {"id": request["id"], "ok": True, "printed": self._run({k: v for k, v in request.items() if k != "id"})}

    def _find(self, key: str | int) -> list | None:
        if isinstance(key, int):
            return self.layers[key] if 0 <= key < len(self.layers) else None
        return next((layer for layer in self.layers if layer[0] == key), None)

    def selected(self) -> str:
        """The name of the layer selected in the app, or nothing when none is."""
        return self.layers[self.active][0] if 0 <= self.active < len(self.layers) else ""

    def _stack(self) -> list[dict]:
        """What the `layers` step lists, bottom first, in the door's short keys."""
        return [
            {
                "i": index,
                "name": name,
                "kind": "plain",
                "visible": self.shown.get(name, True),
                "opacity": self.opacities.get(name, 1.0),
                "blend": "normal",
                "active": index == self.active,
                "group": None,
                "bounds": None,
            }
            for index, (name, _) in enumerate(self.layers)
        ]

    def _layer_step(self, spec: dict) -> list[str]:
        """The `layer` step as the door answers it: one JSON line, `layer`, `index`, `active`, `done`."""

        def said(answer: dict) -> list[str]:
            return ["SaCapture: layer " + json.dumps(answer)]

        def refused(sentence: str) -> list[str]:
            return said({"error": f"layer step: {sentence}, so nothing was done"})

        if "add" in spec:
            # As the app keeps it: a layer of that name is kept and selected.
            kept = self._find(spec["add"])
            if kept is None:
                self.layers.append([spec["add"], np.zeros((16, 16, 4), np.float32)])
            self.active = next(i for i, row in enumerate(self.layers) if row[0] == spec["add"])
            done = [f"{'kept' if kept else 'added'} {spec['add']}"]
            return said({"layer": spec["add"], "index": self.active, "active": spec["add"], "done": done})
        acted = self._find(spec["of"]) if "of" in spec else self._find(self.active)
        if acted is None:
            if isinstance(spec["of"], str):
                return refused(f"there is no layer named '{spec['of']}'")
            return refused(f"there is no layer {spec['of']}, the stack holds {len(self.layers)}")
        if "activate" in spec and self._find(spec["activate"]) is None:
            return refused(f"there is no layer called {spec['activate']} to activate")
        name, done = acted[0], []
        if "activate" in spec:
            self.active = self.layers.index(self._find(spec["activate"]))
            done.append(f"active {spec['activate']}")
        if "opacity" in spec:
            self.opacities[name] = round(min(max(spec["opacity"], 0.0), 1.0), 3)
            done.append(f"{name} at opacity {spec['opacity']}")
        if "visible" in spec:
            self.shown[name] = spec["visible"]
            done.append(f"{name} visible {spec['visible']}")
        place = next(index for index, row in enumerate(self.layers) if row is acted)
        if spec.get("duplicate"):
            copy = f"{name} Copy"
            self.layers.insert(place + 1, [copy, acted[1].copy()])
            self.active = place + 1
            done.append(f"duplicated as {copy}")
        if spec.get("delete"):
            if len(self.layers) > 1:
                del self.layers[place]
                if self.active >= place:
                    self.active = max(self.active - 1, 0) if self.active > place else min(place, len(self.layers) - 1)
                done.append(f"deleted {name}")
            elif self.locked_last:
                done.append("kept the last layer")
            else:
                acted[1][:] = 0
                done.append(f"cleared {name}")
        index = next((i for i, row in enumerate(self.layers) if row is acted), -1)
        return said({"layer": name, "index": index, "active": self.selected(), "done": done})

    def _run(self, step: dict) -> list[str]:
        kind, spec = next(iter(step.items()))
        if kind == "layers":
            return ["SaCapture: layers " + json.dumps(self._stack())]
        if kind == "layer":
            return self._layer_step(spec)
        if kind == "undo":
            for _ in range(int(spec)):
                _, index, before = self.history.pop()
                if before is None:
                    del self.layers[index]
                else:
                    self.layers[index][1] = before
            return []
        if kind == "look":
            Path(spec["path"]).write_bytes(sara.png_bytes(np.full((2, 2, 4), 200, np.uint8)))
            return [f"SaCapture: look {spec['path']} -> err 0, 2x2 from 2x2"]
        if kind == "import":
            # As the app answers it: the picture named after its file, in
            # the place of a layer already called that.
            if not Path(spec).is_file():
                return ["SaCapture: import " + json.dumps({"error": f"Sara could not read {spec} as a picture."})]
            name, pixels = Path(spec).stem, decode_png(Path(spec).read_bytes()).astype(np.float32) / 255.0
            found = self._find(name)
            if found is None:
                self.layers.append([name, pixels])
            else:
                found[1] = pixels
            return ["SaCapture: import " + json.dumps({"layer": name, "path": spec})]
        if "new_layer" in spec and self._find(spec["new_layer"]) is not None:
            spec = dict(spec, layer=spec.pop("new_layer"))
        if "new_layer" in spec:
            # The app's add and its write are one step: undo takes the layer away.
            self.layers.append([spec["new_layer"], np.zeros((16, 16, 4), np.float32)])
            self.history.append((spec.get("name", "Add Layer"), len(self.layers) - 1, None))
            x, y, w, h = spec["rect"]
            self.layers[-1][1][y : y + h, x : x + w] = np.load(spec["file"])
            return ["SaCapture: write_pixels " + json.dumps({"layer": spec["new_layer"], "rect": spec["rect"]})]
        layer = self._find(spec["layer"] if "layer" in spec else self.active)
        if layer is None:
            return [f"SaCapture: {kind} " + json.dumps({"error": f"no layer {spec.get('layer')}"})]
        rect = spec.get("rect")
        x, y, w, h = [0, 0, 16, 16] if rect in (None, "canvas") else rect
        if kind == "read_pixels":
            path = self.folder / f"read-{len(self.requests)}.npy"
            pixels = layer[1][y : y + h, x : x + w]
            if "max_size" in spec:
                # The app's small form, stood in for by a stride: eight bits, the long
                # side at most `max_size`, never enlarged.
                every = max(1, -(-max(w, h) // int(spec["max_size"])))
                pixels = sara.tone_map(pixels[::every, ::every])
            np.save(path, pixels)
            answer = {"path": str(path), "shape": list(pixels.shape), "rect": [x, y, w, h], "dtype": str(pixels.dtype)}
            return ["SaCapture: read_pixels " + json.dumps(answer)]
        written = np.load(spec["file"])
        if written.shape != (h, w, 4):
            wrong = f"shape {list(written.shape)} is not {[h, w, 4]}"
            return ["SaCapture: write_pixels " + json.dumps({"error": wrong})]
        self.history.append((spec.get("name", "write pixels"), self.layers.index(layer), layer[1].copy()))
        layer[1][y : y + h, x : x + w] = written
        return ["SaCapture: write_pixels " + json.dumps({"rect": [x, y, w, h], "name": spec.get("name")})]

    def close(self) -> None:
        self.server.close()


def decode_png(data: bytes) -> np.ndarray:
    """An eight bit RGBA PNG with every row unfiltered, which is what `sara.png_bytes` writes."""
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    at, idat, width, height = 8, b"", 0, 0
    while at < len(data):
        (length,) = struct.unpack(">I", data[at : at + 4])
        kind, body = data[at + 4 : at + 8], data[at + 8 : at + 8 + length]
        (crc,) = struct.unpack(">I", data[at + 8 + length : at + 12 + length])
        assert crc == zlib.crc32(kind + body), kind
        if kind == b"IHDR":
            width, height, depth, colour = struct.unpack(">IIBB", body[:10])
            assert (depth, colour) == (8, 6)
        elif kind == b"IDAT":
            idat += body
        at += 12 + length
    rows = np.frombuffer(zlib.decompress(idat), np.uint8).reshape(height, 1 + width * 4)
    assert not rows[:, 0].any()
    return rows[:, 1:].reshape(height, width, 4)


class ClientTests(unittest.TestCase):
    def open(self, transport: str) -> tuple[StubDoor, sara.Document]:
        folder = Path(tempfile.mkdtemp(prefix="sara-stub-"))
        stub = StubDoor(folder, transport)
        self.addCleanup(stub.close)
        with mock.patch.object(sara, "TRANSPORT", transport):
            doc = sara.connect(stub.file)
        self.addCleanup(doc.close)
        self.assertEqual(doc.door.transport, transport)
        return stub, doc

    def test_connect_over_both_ways_in(self) -> None:
        for transport in ("unix", "tcp") if hasattr(socket, "AF_UNIX") else ("tcp",):
            with self.subTest(transport=transport):
                stub, doc = self.open(transport)
                self.assertEqual(doc.layer("Background").read().shape, (16, 16, 4))
                self.assertEqual(stub.requests[0], {"id": 1, "attach": True}, "the first line attaches")
                self.assertEqual(len(stub.requests), 2)

    def test_hanging_up_leaves_sara_answering_the_next_client(self) -> None:
        """An attached client hanging up leaves the door listening."""
        for transport in ("unix", "tcp") if hasattr(socket, "AF_UNIX") else ("tcp",):
            with self.subTest(transport=transport):
                stub, doc = self.open(transport)
                doc.layer(0).write(np.full((2, 2, 4), 0.5, np.float32), rect=[0, 0, 2, 2])
                doc.close()
                with mock.patch.object(sara, "TRANSPORT", transport):
                    again = sara.connect(stub.file)
                self.addCleanup(again.close)
                self.assertEqual(float(again.layer(0).read([0, 0, 2, 2])[1, 1, 3]), 0.5)

    def test_a_session_holds_one_connection_for_all_its_steps(self) -> None:
        """The steps go over the connection the attach opened."""
        for transport in ("unix", "tcp") if hasattr(socket, "AF_UNIX") else ("tcp",):
            with self.subTest(transport=transport):
                stub, doc = self.open(transport)
                for _ in range(5):
                    doc.layer(0).read([0, 0, 2, 2])
                doc.undo_step("half")
                doc.layer(0).write(np.full((2, 2, 4), 0.5, np.float32), rect=[0, 0, 2, 2])
                self.assertEqual(len(stub.requests), 7)
                self.assertEqual(stub.connections, 1)

    def test_a_batch_is_one_request_answered_in_order(self) -> None:
        stub, doc = self.open("tcp")
        answers = doc.door.batch([{"layer": {"add": "One"}}, {"layer": {"add": "Two"}}])
        lines = [json.loads(a["printed"][0].removeprefix("SaCapture: layer ")) for a in answers]
        self.assertEqual([line["done"] for line in lines], [["added One"], ["added Two"]])
        self.assertEqual([layer[0] for layer in stub.layers], ["Background", "One", "Two"])
        self.assertEqual([r["id"] for r in stub.requests], [1, 2, 3], "ids run on across the batch")

    def test_a_wrong_token_is_refused_with_the_status(self) -> None:
        stub, doc = self.open("tcp")
        doc.close()
        stub.file.write_text(json.dumps({**stub.where, "token": "not-it"}), encoding="utf-8")
        with mock.patch.object(sara, "TRANSPORT", "tcp"), self.assertRaises(sara.SaraError) as caught:
            sara.connect(stub.file)
        self.assertIn("401", str(caught.exception))

    def test_the_known_file_is_found_from_the_environment(self) -> None:
        stub, first = self.open("tcp")
        # One client at a time, as the door serves them.
        first.close()
        named = {sara.DOOR_FILE_ENV: str(stub.file)}
        with mock.patch.dict(os.environ, named), mock.patch.object(sara, "TRANSPORT", "tcp"):
            doc = sara.connect()
        doc.close()
        with mock.patch.dict(os.environ, {"APPDATA": r"C:\Users\student\AppData\Roaming"}, clear=True):
            self.assertEqual(sara.door_file("win32").parts[-3:], ("app_userdata", "Sara", "door.json"))

    def test_a_write_and_a_read_round_trip_a_known_array_above_one(self) -> None:
        _, doc = self.open("tcp")
        known = np.arange(4 * 6 * 4, dtype=np.float32).reshape(4, 6, 4) / 10.0
        doc.layer("Background").write(known, rect=[3, 5, 6, 4])
        self.assertTrue(np.array_equal(doc.layer("Background").read([3, 5, 6, 4]), known))
        self.assertGreater(float(doc.layer(0).read([3, 5, 6, 4]).max()), 1.0)
        self.assertFalse(doc.layer(0).read([0, 0, 3, 3]).any())

    def test_the_undo_step_names_the_write_and_undo_takes_it_away(self) -> None:
        stub, doc = self.open("tcp")
        doc.undo_step("fourier magnitude")
        doc.layer(0).write(np.ones((16, 16, 3), np.float32))
        self.assertEqual(stub.history[-1][0], "fourier magnitude")
        doc.layer(0).write(np.ones((16, 16), np.float32), name="second")
        self.assertEqual(stub.history[-1][0], "second")
        doc.undo(2)
        self.assertFalse(doc.layer(0).read().any())

    def test_a_layer_by_name_and_by_index(self) -> None:
        stub, doc = self.open("tcp")
        doc.new_layer("Ink").write(np.full((2, 2, 4), 0.5, np.float32), rect=[0, 0, 2, 2])
        self.assertEqual(float(doc.layer(1).read([0, 0, 2, 2])[0, 0, 0]), 0.5)
        self.assertFalse(doc.layer(0).read().any())
        self.assertEqual([r["read_pixels"]["layer"] for r in stub.requests if "read_pixels" in r], [1, 0])

    def test_a_new_layer_with_its_pixels_is_one_step(self) -> None:
        stub, doc = self.open("tcp")
        layer = doc.new_layer("Spectrum", np.full((2, 2, 4), 0.5, np.float32), rect=[1, 1, 2, 2], step="fourier")
        self.assertEqual(layer.key, "Spectrum")
        self.assertEqual(float(layer.read([1, 1, 2, 2])[0, 0, 0]), 0.5)
        self.assertEqual([r for r in stub.requests if "layer" in r], [], "no separate add step")
        self.assertEqual(stub.history[-1][0], "fourier")
        doc.undo()
        self.assertEqual([name for name, _ in stub.layers], ["Background"])

    def stack_of_two(self, transport: str = "tcp") -> tuple[StubDoor, sara.Document]:
        """Background under Ink, Background still the selection, as a painter leaves a stack."""
        stub, doc = self.open(transport)
        doc.new_layer("Ink")
        stub.active = 0
        stub.requests.clear()
        return stub, doc

    def test_layers_lists_the_stack_bottom_first_in_the_doors_keys(self) -> None:
        """`doc.layers()` is the `layers` step's line as a list of dicts."""
        stub, doc = self.stack_of_two()
        stub.shown["Ink"], stub.opacities["Ink"] = False, 0.25
        stack = doc.layers()
        self.assertEqual([entry["name"] for entry in stack], ["Background", "Ink"])
        self.assertEqual([entry["i"] for entry in stack], [0, 1])
        self.assertEqual([entry["active"] for entry in stack], [True, False])
        self.assertEqual((stack[1]["visible"], stack[1]["opacity"]), (False, 0.25))
        self.assertEqual(sorted(stack[0]), sorted(["i", "name", "kind", "visible", "opacity", "blend", "active", "group", "bounds"]))
        self.assertEqual([{k: v for k, v in r.items() if k != "id"} for r in stub.requests], [{"layers": True}])
        with mock.patch.object(doc.door, "verdict", return_value="refused, no document"), self.assertRaises(sara.SaraError):
            doc.layers()

    def test_visible_and_opacity_are_properties_that_leave_the_selection_alone(self) -> None:
        stub, doc = self.stack_of_two()
        self.assertTrue(doc.layer("Ink").visible)
        doc.layer("Ink").visible = False
        doc.layer(1).opacity = 0.25
        sent = [{k: v for k, v in r.items() if k != "id"} for r in stub.requests if "layer" in r]
        self.assertEqual(sent, [{"layer": {"of": "Ink", "visible": False}}, {"layer": {"of": 1, "opacity": 0.25}}])
        self.assertFalse(doc.layer(1).visible)
        self.assertEqual(doc.layer("Ink").opacity, 0.25)
        self.assertEqual(stub.selected(), "Background", "an `of` step does not move the selection")
        self.assertTrue(doc.layer("Background").visible)
        self.assertEqual(doc.layer(0).opacity, 1.0)

    def test_an_opacity_outside_zero_to_one_raises_before_any_step_is_sent(self) -> None:
        stub, doc = self.stack_of_two()
        for value in (-0.1, 1.5, 50):
            with self.assertRaises(ValueError):
                doc.layer("Ink").opacity = value
        self.assertEqual([r for r in stub.requests if "layer" in r], [])

    def test_select_names_the_layer_even_when_it_is_known_by_its_index(self) -> None:
        stub, doc = self.stack_of_two()
        doc.layer(1).select()
        self.assertEqual(stub.selected(), "Ink")
        doc.layer("Background").select()
        self.assertEqual(stub.selected(), "Background")
        sent = [r["layer"] for r in stub.requests if "layer" in r]
        self.assertEqual(sent, [{"of": 1, "activate": "Ink"}, {"of": "Background", "activate": "Background"}])

    def test_duplicate_answers_the_copy_as_a_layer_and_the_copy_is_selected(self) -> None:
        stub, doc = self.stack_of_two()
        doc.layer("Ink").write(np.full((2, 2, 4), 0.5, np.float32), rect=[0, 0, 2, 2])
        copy = doc.layer("Ink").duplicate()
        self.assertIsInstance(copy, sara.Layer)
        self.assertEqual(copy.key, "Ink Copy")
        self.assertEqual([name for name, _ in stub.layers], ["Background", "Ink", "Ink Copy"])
        self.assertEqual(float(copy.read([0, 0, 2, 2])[0, 0, 0]), 0.5, "the copy holds the pixels")
        self.assertEqual(stub.selected(), "Ink Copy", "the door selects the copy, which the docstring says")
        self.assertEqual([r["layer"] for r in stub.requests if "layer" in r], [{"of": "Ink", "duplicate": True}])
        self.assertEqual(copy.duplicate().key, "Ink Copy Copy")

    def test_delete_takes_the_named_layer_out_and_not_the_selected_one(self) -> None:
        stub, doc = self.stack_of_two()
        doc.layer("Ink").delete()
        self.assertEqual([name for name, _ in stub.layers], ["Background"])
        self.assertEqual(stub.selected(), "Background")
        self.assertEqual([r["layer"] for r in stub.requests if "layer" in r], [{"of": "Ink", "delete": True}])

    def test_the_only_layer_is_cleared_and_a_locked_one_raises(self) -> None:
        stub, doc = self.open("tcp")
        doc.layer(0).write(np.ones((2, 2, 4), np.float32), rect=[0, 0, 2, 2])
        doc.layer(0).delete()
        self.assertEqual([name for name, _ in stub.layers], ["Background"], "cleared, as the menu does")
        self.assertFalse(doc.layer(0).read().any())
        stub.locked_last = True
        with self.assertRaises(sara.SaraError) as caught:
            doc.layer(0).delete()
        self.assertIn("kept the last layer", str(caught.exception))

    def test_a_layer_that_is_not_there_raises_with_the_doors_message_and_nothing_is_done(self) -> None:
        stub, doc = self.stack_of_two()
        actions = {
            "delete": lambda layer: layer.delete(),
            "duplicate": lambda layer: layer.duplicate(),
            "select": lambda layer: layer.select(),
            "visible": lambda layer: setattr(layer, "visible", False),
            "opacity": lambda layer: setattr(layer, "opacity", 0.5),
        }
        for what, act in actions.items():
            for key, said in (("Typo", "there is no layer named 'Typo'"), (7, "there is no layer 7, the stack holds 2")):
                with self.subTest(step=what, layer=key), self.assertRaises(sara.SaraError) as caught:
                    act(doc.layer(key))
                self.assertIn(said, str(caught.exception))
        self.assertEqual([name for name, _ in stub.layers], ["Background", "Ink"], "nothing was deleted or copied")
        self.assertEqual(stub.selected(), "Background")
        self.assertEqual((stub.shown, stub.opacities), ({}, {}))
        sent = [r["layer"] for r in stub.requests if "layer" in r]
        self.assertTrue(all("of" in step for step in sent), "every step names its layer, none acts on the selection")

    def test_a_new_layer_run_twice_is_one_layer_holding_the_second_array(self) -> None:
        """A cell run again writes into the layer it made the first time."""
        stub, doc = self.open("tcp")
        for value in (0.25, 0.75):
            layer = doc.new_layer("Spectrum", np.full((2, 2, 4), value, np.float32), rect=[1, 1, 2, 2])
            self.assertEqual(layer.key, "Spectrum")
        for _ in range(2):
            self.assertEqual(doc.new_layer("Ink").key, "Ink")
        self.assertEqual([name for name, _ in stub.layers], ["Background", "Spectrum", "Ink"])
        self.assertEqual(float(doc.layer("Spectrum").read([1, 1, 2, 2])[0, 0, 0]), 0.75)

    def test_an_import_by_a_relative_path_is_resolved_where_the_notebook_runs(self) -> None:
        """Sara runs in another folder, so the client sends the path it means."""
        stub, doc = self.open("tcp")
        notebook = Path(tempfile.mkdtemp(prefix="sara-notebook-"))
        (notebook / "img").mkdir()
        chart = np.array([[[0, 64, 128, 255], [255, 128, 64, 255]]], np.uint8)
        (notebook / "img" / "chart.png").write_bytes(sara.png_bytes(chart))
        self.addCleanup(os.chdir, os.getcwd())
        os.chdir(notebook)
        for _ in range(2):
            layer = doc.import_image("img/chart.png")
            self.assertEqual(layer.key, "chart")
        self.assertEqual(stub.requests[-1]["import"], str(notebook / "img" / "chart.png"))
        self.assertEqual([name for name, _ in stub.layers], ["Background", "chart"], "a rerun leaves one")
        self.assertTrue(np.allclose(layer.read([0, 0, 2, 1]), chart / 255.0))

    def test_an_import_sara_cannot_read_raises_its_reason(self) -> None:
        _, doc = self.open("unix" if hasattr(socket, "AF_UNIX") else "tcp")
        with self.assertRaises(sara.SaraError) as caught:
            doc.import_image("no/such/picture.png")
        self.assertIn("could not read", str(caught.exception))

    def test_show_is_a_png_of_the_tone_mapped_values_and_the_array_untouched(self) -> None:
        _, doc = self.open("tcp")
        values = np.array([[[2.0, 0.5, -1.0, 1.0], [0.25, 1.0, 0.0, 0.5]]], np.float32)
        doc.layer(0).write(values, rect=[0, 0, 2, 1])
        shown = decode_png(doc.layer(0).show([0, 0, 2, 1])._repr_png_())
        self.assertEqual(shown.tolist(), [[[255, 128, 0, 255], [64, 255, 0, 128]]])
        self.assertEqual(float(doc.layer(0).read([0, 0, 2, 1])[0, 0, 0]), 2.0)
        self.assertEqual(decode_png(doc.show()._repr_png_()).shape, (2, 2, 4))

    def test_show_asks_for_the_small_form_and_read_for_the_full_one(self) -> None:
        """A picture is made small on the GPU, the array stays whole float32."""
        stub, doc = self.open("tcp")
        layer = doc.layer(0)
        self.assertEqual(layer.read().dtype, np.float32)
        layer.show()
        layer.show(max_size=8)
        layer.show(max_size=None)
        reads = [r["read_pixels"] for r in stub.requests if "read_pixels" in r]
        self.assertNotIn("max_size", reads[0], "read() asks for the whole layer in float")
        self.assertEqual(reads[1]["max_size"], 512, "show() asks for the small form, 512 px")
        self.assertEqual(reads[2]["max_size"], 8, "at the size asked for")
        self.assertNotIn("max_size", reads[3], "and None is the full read")
        self.assertEqual(decode_png(layer.show(max_size=8)._repr_png_()).shape, (8, 8, 4))
        doc.show()
        doc.show(max_size=None)
        looks = [r["look"] for r in stub.requests if "look" in r]
        self.assertEqual(looks[0]["long_edge"], 512, "the document's picture is small too")
        self.assertEqual(looks[1]["long_edge"], 0, "unless asked for at full size, which `look` reads as zero")

    def test_an_error_from_the_app_says_its_sentence_and_keeps_its_verdict(self) -> None:
        _, doc = self.open("tcp")
        with self.assertRaises(sara.SaraError) as caught:
            doc.layer("Nothing").read()
        self.assertEqual(str(caught.exception), "read_pixels: no layer Nothing", "no JSON a student has to read")
        self.assertEqual(caught.exception.said, {"error": "no layer Nothing"})

    def test_a_stale_file_says_to_start_sara_with_its_door(self) -> None:
        folder = Path(tempfile.mkdtemp(prefix="sara-stale-"))
        listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        listener.bind((sara.LOOPBACK, 0))
        port = listener.getsockname()[1]
        listener.close()
        (folder / "door.json").write_text(json.dumps({"port": port, "token": TOKEN}), encoding="utf-8")
        with mock.patch.object(sara, "TRANSPORT", "tcp"), self.assertRaises(sara.SaraError) as caught:
            sara.connect(folder / "door.json", start=False)
        self.assertIn("start Sara with its door", str(caught.exception))
        with self.assertRaises(sara.SaraError):
            sara.connect(folder / "missing.json", start=False)

    def test_without_af_unix_the_client_chooses_tcp(self) -> None:
        """Windows: CPython there has no `socket.AF_UNIX`, and the file names both ways in."""
        saved = socket.AF_UNIX if hasattr(socket, "AF_UNIX") else None
        try:
            if saved is not None:
                del socket.AF_UNIX
            reloaded = importlib.reload(sara)
            self.assertEqual(reloaded.TRANSPORT, "tcp")
        finally:
            if saved is not None:
                socket.AF_UNIX = saved
        folder = Path(tempfile.mkdtemp(prefix="sara-both-"))
        stub = StubDoor(folder, "tcp")
        self.addCleanup(stub.close)
        stub.file.write_text(json.dumps({**stub.where, "socket": str(folder / "none.sock")}), encoding="utf-8")
        doc = reloaded.connect(stub.file)
        self.addCleanup(doc.close)
        self.assertEqual(doc.door.transport, "tcp")
        importlib.reload(sara)

    def test_a_read_with_no_rectangle_is_the_whole_canvas(self) -> None:
        """The layer holds a corner and the canvas is what comes back."""
        stub, doc = self.open("tcp")
        stub.layers[0][1][2:4, 3:5] = 0.5
        whole = doc.layer("Background").read()
        self.assertEqual(whole.shape, (16, 16, 4))
        self.assertEqual(float(whole[2, 3, 0]), 0.5)
        self.assertEqual(float(whole[10, 10, 0]), 0.0)
        self.assertEqual([r["read_pixels"]["rect"] for r in stub.requests if "read_pixels" in r], ["canvas"])
        self.assertEqual(decode_png(doc.layer(0).show()._repr_png_()).shape, (16, 16, 4), "and show follows it")
        self.assertEqual(doc.layer(0).read([2, 3, 1, 1]).shape, (1, 1, 4), "a rectangle is still the rectangle")

    def test_no_key_is_the_layer_selected_in_sara(self) -> None:
        stub, doc = self.open("tcp")
        stub.layers.append(["Ink", np.zeros((16, 16, 4), np.float32)])
        stub.active = 1
        self.assertEqual(doc.layer().key, "Ink")
        stub.layers.append(["Ink", np.zeros((16, 16, 4), np.float32)])
        stub.active = 2
        self.assertEqual(doc.layer().key, 2, "a name two layers share is not enough, so the index is")
        stub.active = -1
        with self.assertRaises(sara.SaraError) as caught:
            doc.layer()
        self.assertIn("no layer is selected", str(caught.exception))

    def test_init_answers_the_document_the_selected_layer_and_the_canvas(self) -> None:
        stub, first = self.open("tcp")
        stub.layers.append(["Ink", np.zeros((16, 16, 4), np.float32)])
        stub.layers[1][1][0, 15] = 0.25
        stub.active = 1
        # One client at a time, as the door serves them.
        first.close()
        with mock.patch.object(sara, "TRANSPORT", "tcp"):
            doc, layer, pixels = sara.init(stub.file, attach=True)
        self.addCleanup(doc.close)
        self.assertEqual(layer.key, "Ink")
        self.assertEqual(pixels.shape, (16, 16, 4), "the canvas's size, the layer holding one corner")
        self.assertEqual(float(pixels[0, 15, 0]), 0.25)
        self.assertEqual([next(key for key in r if key != "id") for r in stub.requests[1:]], ["attach", "layers", "read_pixels"])
        self.assertEqual(stub.connections, 2, "one for the case's own document and one for init")

    def test_init_without_ipython_never_imports_it(self) -> None:
        stub, first = self.open("tcp")
        first.close()
        loaded = {name: module for name, module in sys.modules.items() if name == "IPython" or name.startswith("IPython.")}
        with mock.patch.dict(sys.modules):
            for name in loaded:
                del sys.modules[name]
            sys.modules.pop("sara_notebook", None)
            with mock.patch.object(sara, "TRANSPORT", "tcp"):
                doc, _, _ = sara.init(stub.file, attach=True)
            self.addCleanup(doc.close)
            self.assertNotIn("IPython", sys.modules, "init did not import it")
            self.assertNotIn("sara_notebook", sys.modules, "and did not load the notebook module")

    def test_init_in_ipython_registers_the_magic_on_its_document(self) -> None:
        stub, first = self.open("tcp")
        first.close()
        shell = mock.Mock()
        notebook = mock.Mock()
        fake = mock.Mock(get_ipython=mock.Mock(return_value=shell))
        with mock.patch.dict(sys.modules, {"IPython": fake, "sara_notebook": notebook}):
            with mock.patch.object(sara, "TRANSPORT", "tcp"):
                doc, _, _ = sara.init(stub.file, attach=True)
            self.addCleanup(doc.close)
        notebook.register.assert_called_once_with(shell, doc)

    def test_init_in_ipython_without_ipywidgets_still_answers(self) -> None:
        stub, first = self.open("tcp")
        first.close()
        fake = mock.Mock(get_ipython=mock.Mock(return_value=mock.Mock()))
        with mock.patch.dict(sys.modules, {"IPython": fake, "sara_notebook": None}):
            with mock.patch.object(sara, "TRANSPORT", "tcp"), mock.patch("sys.stderr") as stderr:
                doc, _, pixels = sara.init(stub.file, attach=True)
            self.addCleanup(doc.close)
        self.assertEqual(pixels.shape, (16, 16, 4))
        self.assertIn("%%gmacs is not registered", "".join(call.args[0] for call in stderr.write.call_args_list))

    def test_a_failed_init_hangs_up_for_the_next_client(self) -> None:
        stub, first = self.open("tcp")
        first.close()
        stub.active = -1
        with mock.patch.object(sara, "TRANSPORT", "tcp"), self.assertRaises(sara.SaraError):
            sara.init(stub.file, attach=True)
        stub.active = 0
        with mock.patch.object(sara, "TRANSPORT", "tcp"):
            doc, layer, _ = sara.init(stub.file, attach=True)
        self.addCleanup(doc.close)
        self.assertEqual(layer.key, "Background")

    def test_the_file_stays_under_nine_hundred_and_sixty_lines(self) -> None:
        # P3 asked for three hundred lines, and the file is still one thing copied whole.
        self.assertLess(len((SCRIPTS / "sara.py").read_text(encoding="utf-8").splitlines()), 960)


class TimedStub(StubDoor):
    """The stub answering the `kernel` step as the driver does: the layer it wrote and the GPU
    time of its dispatch, the next of *gpu_ms* each run, null with a reason past them."""

    def __init__(self, folder: Path, gpu_ms: list[float]) -> None:
        super().__init__(folder, "tcp")
        self.gpu_ms = list(gpu_ms)

    def _run(self, step: dict) -> list[str]:
        kind, spec = next(iter(step.items()))
        if kind != "kernel":
            return super()._run(step)
        said = {"ok": True, "params": [], "layer": spec.get("layer", 0), "into": spec.get("into", spec["name"])}
        said["in_place"] = said["layer"] == said["into"]
        if self.gpu_ms:
            said["gpu_ms"] = self.gpu_ms.pop(0)
        else:
            said.update(gpu_ms=None, gpu_unknown="the device answered no timestamps for the dispatch")
        return ["SaCapture: kernel " + json.dumps(said)]


class BenchTests(unittest.TestCase):
    """`bench` reruns the kernel that last wrote a layer and answers two medians."""

    STEP = {"source": "kernel cells\n", "name": "cells", "layer": "Background", "params": {"scale": 12.0}}

    def open(self, gpu_ms: list[float]) -> tuple[TimedStub, sara.Document]:
        stub = TimedStub(Path(tempfile.mkdtemp(prefix="sara-bench-")), gpu_ms)
        self.addCleanup(stub.close)
        with mock.patch.object(sara, "TRANSPORT", "tcp"):
            doc = sara.connect(stub.file)
        self.addCleanup(doc.close)
        return stub, doc

    @staticmethod
    def clock(round_trips_ms: list[float]) -> mock.Mock:
        """A `perf_counter` whose every pair of calls is one of *round_trips_ms* apart."""
        ticks: list[float] = []
        for n, wait in enumerate(round_trips_ms):
            ticks += [float(n), n + wait / 1000.0]
        return mock.Mock(side_effect=ticks)

    def test_bench_answers_the_medians_of_runs_answers(self) -> None:
        stub, doc = self.open([9.0, 0.3, 0.2, 0.25, 0.21, 0.22])
        doc.kernel(self.STEP)
        trips = [40.0, 38.0, 90.0, 37.0, 39.0]
        with mock.patch.object(sara.time, "perf_counter", self.clock(trips)), mock.patch("builtins.print") as printed:
            timing = sara.bench(doc.layer("cells"), runs=5)
        self.assertIsInstance(timing, sara.Timing)
        self.assertAlmostEqual(timing.gpu_ms, 0.22)
        self.assertAlmostEqual(timing.round_trip_ms, 39.0)
        self.assertEqual(timing._fields, ("gpu_ms", "round_trip_ms"))
        self.assertEqual(printed.call_args.args[0], "GPU 0.22 ms, round trip 39 ms (median of 5)")
        sent = [r["kernel"] for r in stub.requests if "kernel" in r]
        self.assertEqual(len(sent), 6, "the first run and five reruns, a request each")
        self.assertTrue(all(k == dict(self.STEP, into="cells", history=False) for k in sent[1:]), "each the step that wrote it")

    def test_a_rerun_with_new_values_is_the_one_bench_repeats(self) -> None:
        stub, doc = self.open([0.2] * 4)
        doc.kernel(self.STEP)
        doc.kernel(dict(self.STEP, into="cells", params={"scale": 30.0}))
        with mock.patch("builtins.print"):
            sara.bench(doc.layer("cells"), runs=2)
        sent = [r["kernel"] for r in stub.requests if "kernel" in r]
        self.assertEqual([k["params"] for k in sent[2:]], [{"scale": 30.0}] * 2)

    def test_a_device_with_no_timestamps_reads_as_not_known(self) -> None:
        _, doc = self.open([])
        said = doc.kernel(self.STEP)
        self.assertIsNone(said["gpu_ms"])
        with mock.patch.object(sara.time, "perf_counter", self.clock([38.0] * 3)), mock.patch("builtins.print") as printed:
            timing = sara.bench(doc.layer("cells"), runs=3)
        self.assertIsNone(timing.gpu_ms)
        expected = "GPU time not known (the device answered no timestamps for the dispatch), round trip 38 ms (median of 3)"
        self.assertEqual(printed.call_args.args[0], expected)

    def test_a_layer_no_kernel_wrote_is_refused_with_what_to_do(self) -> None:
        _, doc = self.open([])
        with self.assertRaisesRegex(sara.SaraError, "no kernel has written 'Background'"):
            sara.bench(doc.layer("Background"))

    def test_the_line_keeps_a_small_time_readable(self) -> None:
        self.assertEqual(sara.Timing(0.21, 38.4).line(), "GPU 0.21 ms, round trip 38 ms")
        self.assertEqual(sara.Timing(0.0042, 12.0).line(), "GPU 0.0042 ms, round trip 12 ms")
        self.assertEqual(sara.Timing(16.4342, 120.0).line(), "GPU 16.43 ms, round trip 120 ms")


class ARealSaraWithNoCaptureFolder(unittest.TestCase):
    """The paths a Sara started with no `--capture-out` answers.

    Its capture folder is then `user://captures`, which only Godot opens, and
    Windows got that path back for `np.load`. The user folder and the settings,
    by `XDG_CONFIG_HOME`, move into this case's folder.

    The last case is the layer wrappers against the real `layer`
    and `layers` steps. It leaves the stack as it found it.
    """

    START_TIMEOUT_S = 120
    proc: subprocess.Popen
    weston: subprocess.Popen | None
    home: Path
    known: Path

    @classmethod
    def setUpClass(cls) -> None:
        env = dict(os.environ)
        env.pop("GDK_BACKEND", None)
        godot = sara_shot.godot_for_a_suite()
        sara_shot.ensure_class_cache(godot, env)
        cls.weston = sara_shot.start_offscreen_compositor(env)
        if cls.weston is None:
            raise unittest.SkipTest("no offscreen compositor")
        cls.home = Path(tempfile.mkdtemp(prefix="sara-d2-"))
        env.update(XDG_DATA_HOME=str(cls.home), XDG_CONFIG_HOME=str(cls.home / "config"))
        cls.user = cls.home / "godot" / "app_userdata" / "Sara"
        cls.known = cls.user / "door.json"
        cls.proc = subprocess.Popen(
            [godot, "--path", str(SCRIPTS.parent), "--display-driver", "wayland", "--", "--agent-door"],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            preexec_fn=harness_platform.child_setup(),  # noqa: PLW1509
        )
        deadline = time.time() + cls.START_TIMEOUT_S
        while not cls.known.is_file():
            if cls.proc.poll() is not None or time.time() > deadline:
                cls.tearDownClass()
                raise AssertionError(f"Sara never wrote {cls.known}")
            time.sleep(0.2)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.proc.terminate()
        try:
            cls.proc.wait(timeout=15)
        except subprocess.TimeoutExpired:
            cls.proc.kill()
        if cls.weston is not None:
            cls.weston.terminate()
            cls.weston.wait(timeout=5)
        shutil.rmtree(cls.home, ignore_errors=True)

    def setUp(self) -> None:
        self.doc = sara.connect(self.known)
        self.addCleanup(self.doc.close)
        self.doc.door.send({"wait": 30})

    def test_a_layer_is_read_back_from_the_path_the_answer_names(self) -> None:
        said = self.doc.door.verdict({"read_pixels": {"layer": 0, "rect": [0, 0, 4, 4]}})
        self.assertNotIn("://", said["path"], "the answer is no Godot path")
        self.assertTrue(os.path.isabs(said["path"]), said["path"])
        self.assertEqual(Path(said["path"]).parent, self.user / "captures", "it is in the folder the run keeps")
        self.assertEqual(np.load(said["path"]).shape, (4, 4, 4), "and NumPy opens it")
        self.assertEqual(self.doc.layer(0).read([0, 0, 4, 4]).shape, (4, 4, 4), "as the client does")

    def test_a_picture_imported_by_a_relative_path_is_one_layer_in_the_documents_space(self) -> None:
        """Decoded from sRGB into a linear document, run twice from a notebook's folder."""
        self.doc.door.send({"document": "linear_srgb"})
        notebook = self.home / "notebook"
        (notebook / "img").mkdir(parents=True, exist_ok=True)
        chart = np.array([[[0, 64, 128, 255], [255, 188, 32, 255]]], np.uint8)
        (notebook / "img" / "d64_chart.png").write_bytes(sara.png_bytes(chart))
        self.addCleanup(os.chdir, os.getcwd())
        os.chdir(notebook)
        for _ in range(2):
            layer = self.doc.import_image("img/d64_chart.png")
        self.assertEqual(layer.key, "d64_chart")
        names = [entry["name"] for entry in self.doc.door.verdict({"layers": True})]
        self.assertEqual(names.count("d64_chart"), 1, f"a rerun leaves one layer: {names}")
        encoded = chart / 255.0
        linear = np.where(encoded <= 0.04045, encoded / 12.92, ((encoded + 0.055) / 1.055) ** 2.4)
        linear[..., 3] = encoded[..., 3]
        read = layer.read([0, 0, 2, 1])
        self.assertTrue(np.allclose(read, linear, atol=2e-3), f"{read.tolist()} is not {linear.tolist()}")
        with self.assertRaises(sara.SaraError):
            self.doc.import_image("img/missing.png")

    def test_a_layer_painted_in_one_corner_reads_as_the_whole_canvas(self) -> None:
        """No rectangle is the canvas, and no key is the layer selected in Sara."""
        canvas = self.doc.door.send({"state": "d71", "dump": True})["state"]["document"]["canvas_size"]
        width, height = (int(canvas["x"]), int(canvas["y"])) if isinstance(canvas, dict) else (int(canvas[0]), int(canvas[1]))
        self.assertGreater(width, 256, "a canvas wider than the one chunk the paint lands in")
        self.doc.new_layer("Corner", np.full((8, 8, 4), 0.5, np.float32), rect=[0, 0, 8, 8])
        self.doc.close()
        document, layer, pixels = sara.init(self.known, attach=True)
        self.addCleanup(document.close)
        self.assertEqual(layer.key, "Corner", "the layer the add selected")
        self.assertEqual(pixels.shape, (height, width, 4), "the canvas's size, where the layer holds one chunk")
        self.assertEqual(float(pixels[7, 7, 0]), 0.5)
        self.assertEqual(float(pixels[8, 8, 3]), 0.0)
        self.assertFalse(pixels[:, 256:].any(), "and zeros past the chunk the paint reached")
        self.assertEqual(layer.show()._repr_png_()[:8], b"\x89PNG\r\n\x1a\n")

    def test_a_second_notebook_takes_its_turn_once_the_first_goes_idle(self) -> None:
        """Sara serves one client, so an idle one lets go and a second notebook attaches, then the first
        attaches again on its next call."""
        self.doc.layers()
        other = sara.connect(self.known, start=False)
        self.assertIsInstance(other.layers(), list, "the second attached once the first let go")
        other.close()
        self.assertIsInstance(self.doc.layers(), list, "and the first attaches again")

    def test_a_client_still_held_past_the_wait_says_sara_is_busy(self) -> None:
        """The door answers a second client with a 409 that says who holds Sara. `connect` shares the
        process's one Door, so the second client here is a Door of its own, as another process's is."""
        self.doc.layers()
        with mock.patch.object(sara, "HELD_WAIT_S", 0.0), self.assertRaises(sara.DoorBusyError) as caught:
            sara.Door(self.known)
        self.assertIn("another notebook or script is connected", str(caught.exception))
        self.assertIsInstance(self.doc.layers(), list, "and the first keeps Sara")

    def test_check_holds_a_layer_written_from_an_array_near_that_array(self) -> None:
        """A default document keeps half floats, so the read is the array rounded to
        eleven bits, at most 2^-11 off near 1, which the share past the tolerance reads as no pixel."""
        mine = np.random.default_rng(74).random((16, 16, 4), np.float32)
        layer = self.doc.new_layer("Probe", mine, rect=[0, 0, 16, 16])
        expected = np.zeros_like(layer.read())
        expected[:16, :16] = mine
        with mock.patch("builtins.print") as printed:
            found = sara.check(layer, expected)
        self.assertLessEqual(found.largest, 2.0**-11, printed.call_args.args[0])
        self.assertEqual(found.percent, 0.0, printed.call_args.args[0])
        expected[3, 5, 0] += 0.5
        with mock.patch("builtins.print"):
            found = sara.check(layer, expected)
        self.assertEqual(found.where, (5, 3))
        self.assertAlmostEqual(found.largest, 0.5, places=3)
        # The name a lesson writes reads the same layer of the running app.
        notebook = types.SimpleNamespace(GmacsMagics=types.SimpleNamespace(document=self.doc))
        with mock.patch.dict(sys.modules, {"sara_notebook": notebook}), mock.patch("builtins.print"):
            self.assertEqual(sara.check("Probe", expected), found)

    def test_show_writes_where_it_was_told(self) -> None:
        picture = self.doc.show()
        self.assertEqual(picture.data[:8], b"\x89PNG\r\n\x1a\n", "a picture came back")
        self.assertEqual(list((self.user / "captures").glob("*look*")), [], "and none was left in the capture folder")

    def test_a_path_written_with_a_drive_letter_is_not_put_under_the_capture_folder(self) -> None:
        sent = "C:\\Users\\me\\AppData\\Local\\Temp\\sara-look-x\\look.png"
        said = self.doc.door.verdict({"look": {"path": sent}})
        self.assertTrue(said.startswith(sent + " -> "), f"the verdict names the path as it was sent: {said}")
        self.assertEqual(list((self.user / "captures").glob("C*")), [], "nothing was made after user://captures")

    def test_a_shot_answers_a_path_the_client_can_open(self) -> None:
        answer = self.doc.door.send({"shot": "d2"})
        self.assertTrue(answer["shot"], f"the answer names the picture: {answer}")
        self.assertNotIn("://", answer["shot"])
        self.assertTrue(Path(answer["shot"]).is_file(), answer["shot"])

    def names(self) -> list[str]:
        return [entry["name"] for entry in self.doc.layers()]

    def test_the_layer_wrappers_act_on_the_layer_they_name_and_leave_the_selection(self) -> None:
        """Each wrapper once against the app, the stack read back from it each time."""
        doc, before = self.doc, self.names()
        bottom = before[0]
        selected = lambda: next(entry["name"] for entry in doc.layers() if entry["active"])  # noqa: E731
        ink = doc.new_layer("D65 Ink")
        self.addCleanup(lambda: [doc.layer(n).delete() for n in self.names() if n.startswith("D65")])
        doc.layer(bottom).select()
        self.assertEqual(selected(), bottom)

        ink.visible = False
        ink.opacity = 0.5
        shown = {entry["name"]: entry for entry in doc.layers()}
        self.assertEqual((shown["D65 Ink"]["visible"], shown["D65 Ink"]["opacity"]), (False, 0.5))
        self.assertEqual((ink.visible, ink.opacity), (False, 0.5))
        self.assertEqual(selected(), bottom, "a property leaves the selection where the painter put it")

        copy = ink.duplicate()
        after = self.names()
        self.assertEqual(after.index(copy.key), after.index("D65 Ink") + 1, "the copy sits above the layer")
        self.assertEqual(len(after), len(before) + 2)
        self.assertEqual((selected(), copy.visible, copy.opacity), (copy.key, False, 0.5), "the app selects the copy")

        doc.layer(bottom).select()
        copy.delete()
        self.assertNotIn(copy.key, self.names())
        self.assertEqual(selected(), bottom)
        ink.delete()
        self.assertEqual(self.names(), before)
        doc.undo()
        self.assertIn("D65 Ink", self.names(), "a delete is one history step")

        with self.assertRaises(sara.SaraError) as caught:
            doc.layer("Typo").delete()
        self.assertIn("there is no layer named 'Typo'", str(caught.exception))
        self.assertEqual(len(self.names()), len(before) + 1, "and a refusal deletes nothing")


if __name__ == "__main__":
    unittest.main()
