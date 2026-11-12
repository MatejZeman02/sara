#!/usr/bin/env python3
"""Every right-click menu opens at the pointer, read at UI scale 2, 1.5 and 1.

    cd sara-godot && python scenarios/every-right-click-menu-opens-at-the-pointer-at-a-4k-screen-s-ui-scale.py [out]

A painter on 2026-10-23 saw the canvas menu open down and right of the press
on a 4K screen, twice as far from the window's corner as the pointer. This
runs Sara at each scale, the dockers in the main window and then each in a
window of its own, and right-clicks every place a menu opens from: the canvas
with the Brush, the Rectangle Select and the Move tool at three points each,
a layer's row, a chip of the swatches strip, the colour picker's shape, the
reference board and its tabs, a brush preset's cell and the grid around the
cells, a toolbox button and a title on the top bar. Each press is followed by
a `state` dump, whose `open_menus` carries each open menu's top-left corner in
the main window's logical units beside `pointer_aimed`, where the press was
aimed, and a shot.

Two of them answer a right click with something other than a list at the
corner. The Brush opens the Brush Presets docker beside the pointer,
twelve logical pixels clear of the press, so its top-left is read against the
place `_beside_pointer` gives it. The toolbox opens its button's flyout beside
the button, which a left press and a dragged tool open as well, so its corner
is read against the button's right edge.

Each scale runs under a headless mutter rather than the nested weston, since
weston gives a window of its own no position, and the
dockers' let-out half is what the fault was worst in.

With the canvas menu open a second right click closes it and opens nothing,
and a third opens it again at its own point.

Every reading goes to `readings.json` in the out folder, each with its error
in logical pixels, and the run fails when one is off by more than four. The
out folder defaults to this row's folder under `~/.cache/sara/scenario-runs`.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT / "scripts"))

from sara_door import SaraDoor  # noqa: E402

ROW = Path(__file__).stem
PROOF = Path.home() / ".cache" / "sara" / "scenario-runs" / ROW
WINDOW = (1920, 1080)
WITHIN = 4.0
SCALES = (2.0, 1.5, 1.0)
CANVAS_TOOLS = (("brush", "Brush"), ("marquee", "Rectangle Select"), ("transform", "Move"))
# Fractions of the logical window, clear of the dockers once they are parked and
# with room under each for the tallest menu at scale 2.
# BrushPresetsDocker.POINTER_GAP, logical pixels between the press and the docker.
POINTER_GAP = 12
CANVAS_POINTS = ((0.30, 0.22), (0.45, 0.35), (0.62, 0.28))


class MutterDoor(SaraDoor):
    """The door with Godot under a headless mutter on X11 rather than weston.

    A window of its own has no position under the nested weston, and weston's
    Xwayland places one where it likes,
    so a menu of a let-out docker cannot be read there. Mutter honours an X
    client's position and starts its own Xwayland, so nothing reaches the
    desktop. The door's weston still starts and stands unused.
    """

    def _launch_line(self, env: dict) -> list[str]:
        line = super()._launch_line(env)
        line = ["x11" if word == "wayland" and line[i - 1] == "--display-driver" else word for i, word in enumerate(line)]
        size = f"{WINDOW[0]}x{WINDOW[1]}"
        return ["mutter", "--headless", "--wayland", "--virtual-monitor", size, "--", *line]


class Run:
    """One Sara session and the readings taken in it."""

    def __init__(self, door: SaraDoor, out: Path) -> None:
        self.door = door
        self.out = out
        self.readings: list[dict] = []
        self.shots = 0

    def send(self, step: dict) -> dict:
        return self.door.send(step)

    def state(self, name: str) -> dict:
        self.shots += 1
        label = f"{self.shots:03d}-{name}"
        self.send({"shot": label})
        return self.door.send({"state": label}, dump=True).get("state", {})

    def quiet(self) -> dict:
        return self.door.send({"state": "quiet"}, dump=True).get("state", {})

    def right_click(self, spec: dict) -> None:
        # The pointer first, so a summon that reads the real pointer reads
        # this press and not the one before it.
        self.send({"move": spec})
        self.send({"wait": 4})
        self.send({"press": {"button": "right", **spec}})
        self.send({"release": {"button": "right", **spec}})
        self.send({"wait": 12})

    def read(self, name: str, state: dict, at: list | None, target: list | None, how: str = "menu corner", menu: str | None = None) -> dict:
        """Notes where something opened against where it should have."""
        error = None if at is None or target is None else max(abs(at[0] - target[0]), abs(at[1] - target[1]))
        reading = {
            "name": name,
            "how": how,
            "aimed": state.get("pointer_aimed"),
            "expected": target,
            "menu": menu,
            "at": at,
            "error": None if error is None else round(error, 2),
            "ok": error is not None and error <= WITHIN,
        }
        self.readings.append(reading)
        print(f"{name}: {menu} at {at}, expected {target}, off {reading['error']}")
        return reading

    def read_menu(self, name: str, state: dict) -> dict:
        menus = state.get("open_menus", [])
        first = menus[0] if menus else {}
        return self.read(name, state, first.get("at"), state.get("pointer_aimed"), menu=first.get("name"))

    def close(self) -> None:
        """Escape until no menu stands, so the next press opens a fresh one."""
        for _ in range(4):
            if not self.quiet().get("open_menus"):
                return
            self.send({"key": {"key": "escape"}})
            self.send({"wait": 8})


def logical(scale: float) -> tuple[float, float]:
    return WINDOW[0] / scale, WINDOW[1] / scale


def docker_place(scale: float, embedded: bool, at: tuple[float, float]) -> list[int]:
    """*at*, in logical units, as the docker step writes a window's position."""
    factor = 1.0 if embedded else scale
    return [int(at[0] * factor), int(at[1] * factor)]


def window_rect(window: dict, scale: float) -> list[float]:
    """A docker window's rectangle in the main window's logical units."""
    x, y = window["position"]["x"], window["position"]["y"]
    w, h = window["size"]["x"], window["size"]["y"]
    if not window.get("embedded"):
        x, y, w, h = x / scale, y / scale, w / scale, h / scale
    return [x, y, w, h]


def beside(point: list, rect: list, room: tuple[float, float]) -> list:
    """Where `_beside_pointer` puts the docker's top-left for a press at
    *point*: the gap after the point on each axis where the docker fits, before
    it where it fits there, and the point itself otherwise, then clamped inside
    the main window, all in its logical units."""
    wanted = []
    for axis in (0, 1):
        extent = rect[2 + axis]
        if point[axis] + POINTER_GAP + extent <= room[axis]:
            at = point[axis] + POINTER_GAP
        elif point[axis] - POINTER_GAP - extent >= 0:
            at = point[axis] - POINTER_GAP - extent
        else:
            at = point[axis]
        wanted.append(round(min(max(at, 0.0), max(room[axis] - extent, 0.0)), 2))
    return wanted


def canvas(run: Run, tag: str, scale: float) -> None:
    width, height = logical(scale)
    run.send({"docker": "park"})
    run.send({"wait": 15})
    for tool, label in CANVAS_TOOLS:
        run.send({"tool": {"id": tool}})
        run.send({"wait": 6})
        for index, (fx, fy) in enumerate(CANVAS_POINTS):
            point = [round(width * fx), round(height * fy)]
            run.right_click({"at": point})
            state = run.state(f"{tag}-canvas-{tool}-{index}")
            name = f"{tag} canvas {label} {index}"
            if tool != "brush":
                run.read_menu(name, state)
                run.close()
                continue
            window = next((w for w in state.get("windows", []) if w.get("title") == "Brush Presets" and w.get("visible")), None)
            rect = window_rect(window, scale) if window else None
            corner = [round(rect[0], 2), round(rect[1], 2)] if rect else None
            wanted = beside(point, rect, (width, height)) if rect else None
            run.read(name, state, corner, wanted, how="Brush Presets docker beside the pointer", menu="Brush Presets")
            run.right_click({"at": point})
            run.send({"docker": "park"})
            run.send({"wait": 8})


def second_click(run: Run, tag: str, scale: float) -> None:
    width, height = logical(scale)
    run.send({"docker": "park"})
    run.send({"tool": {"id": "marquee"}})
    run.send({"wait": 6})
    # The second press up and left of the first, clear of the menu it opened,
    # so it lands on the canvas and not on a row.
    order = (CANVAS_POINTS[1], CANVAS_POINTS[0], CANVAS_POINTS[2])
    points = [[round(width * fx), round(height * fy)] for fx, fy in order]
    run.close()
    run.right_click({"at": points[0]})
    run.read_menu(f"{tag} first right click opens", run.state(f"{tag}-second-click-1-opens"))
    run.right_click({"at": points[1]})
    state = run.state(f"{tag}-second-click-2-closes")
    still = state.get("open_menus", [])
    run.readings.append({"name": f"{tag} second right click closes", "how": "nothing open", "open": still, "ok": not still})
    print(f"{tag} second right click: {len(still)} menu open")
    run.right_click({"at": points[2]})
    run.read_menu(f"{tag} third right click opens again", run.state(f"{tag}-second-click-3-opens-again"))
    run.close()


def one(run: Run, name: str, tag: str, spec: dict) -> None:
    run.close()
    run.right_click(spec)
    run.read_menu(f"{tag} {name}", run.state(f"{tag}-{name.replace(' ', '-')}"))
    run.close()


def dockers(run: Run, tag: str, scale: float, embedded: bool) -> None:
    place = lambda x, y: docker_place(scale, embedded, (x, y))  # noqa: E731
    run.send({"docker": "park"})

    run.send({"docker": {"id": "LayersDocker", "at": place(140, 60)}})
    run.send({"wait": 15})
    one(run, "layer row", tag, {"control": "LayerRow_0", "in": "LayersDocker"})
    run.send({"docker": "park"})

    run.send({"docker": {"id": "ColorDocker", "at": place(140, 40), "size": place(320, 440)}})
    run.send({"wait": 20})
    one(run, "colour picker shape", tag, {"control": "ShapeFrame", "in": "ColorDocker"})
    one(run, "swatch chip", tag, {"control": "SwatchChip0", "in": "ColorDocker"})
    run.send({"docker": "park"})

    run.send({"docker": {"id": "ReferenceDocker", "at": place(140, 60)}})
    run.send({"wait": 20})
    one(run, "reference board", tag, {"control": "Picture", "in": "ReferenceDocker"})
    one(run, "reference tabs", tag, {"control": "Tabs", "in": "ReferenceDocker"})
    run.send({"docker": "park"})

    run.send({"docker": {"id": "BrushPresetsDocker", "at": place(140, 60)}})
    run.send({"wait": 20})
    one(run, "brush preset cell", tag, {"control": "Icon", "in": "BrushPresetsDocker"})
    # A search nothing matches empties the grid, so the chooser's middle is the
    # bare ground around the cells, which a right press there is aimed at.
    run.send({"control": {"name": "ChooserSearch", "value": "no such preset"}})
    run.send({"wait": 10})
    one(run, "brush presets grid", tag, {"control": "BrushPresetsChooser", "in": "BrushPresetsDocker"})
    run.send({"control": {"name": "ChooserSearch", "value": ""}})
    run.send({"wait": 10})
    run.send({"docker": "park"})

    run.send({"docker": {"id": "ToolBoxDocker", "at": place(140, 60)}})
    run.send({"wait": 20})
    run.close()
    # The toolbox step aims a real right press at the button it reports.
    run.send({"toolbox": {"right_press": "select"}})
    run.send({"wait": 12})
    state = run.state(f"{tag}-toolbox-flyout")
    corner = flyout_corner(state, 1.0 if embedded else scale)
    menus = state.get("open_menus", [])
    run.read(f"{tag} toolbox flyout", state, menus[0].get("at") if menus else None, corner, how="beside its button", menu=menus[0].get("name") if menus else None)
    run.send({"toolbox": {"close": True}})
    run.close()
    run.send({"docker": "park"})

    ramp(run, tag, place)
    one(run, "top bar title", tag, {"control": "Help"})


def ramp_stops(node: object) -> int | None:
    """How many stops the first ramp the dump reports holds."""
    if isinstance(node, dict):
        if isinstance(node.get("stops"), list) and "remove_control" in node:
            return len(node["stops"])
        node = list(node.values())
    if isinstance(node, list):
        for item in node:
            found = ramp_stops(item)
            if found is not None:
                return found
    return None


def ramp(run: Run, tag: str, place) -> None:
    """The gradient's ramp, whose right click removes a stop and opens no menu.

    A left click in the bar's middle adds a stop there, and the right click on
    that same point must take it away again with no menu standing after it.
    """
    run.close()
    run.send({"tool": {"id": "gradient"}})
    run.send({"docker": {"id": "ToolOptionsDocker", "at": place(140, 60), "size": place(440, 560)}})
    run.send({"wait": 20})
    bar = {"control": "Bar", "in": "ToolOptionsDocker"}
    run.send({"click": bar})
    run.send({"wait": 8})
    added = ramp_stops(run.quiet().get("tool_options"))
    run.right_click(bar)
    state = run.state(f"{tag}-colour-ramp")
    left = ramp_stops(state.get("tool_options"))
    menus = state.get("open_menus", [])
    ok = added is not None and left == added - 1 and not menus
    reading = {
        "name": f"{tag} colour ramp stop",
        "how": "removes the stop under the press and opens no menu",
        "aimed": state.get("pointer_aimed"),
        "stops": [added, left],
        "menu": menus[0].get("name") if menus else None,
        "ok": ok,
    }
    run.readings.append(reading)
    print(f"{reading['name']}: stops {added} then {left}, menu {reading['menu']}")
    run.close()
    run.send({"docker": "park"})


def flyout_corner(state: dict, factor: float) -> list | None:
    """Where the Select button's flyout opens: its button's right edge and top,
    in the main window's logical units, read off the toolbox's own report, whose
    `rect` is in the popup's space, the screen's pixels for a window of its own.
    """
    toolbox = state.get("toolbox", {}) or {}
    for entry in toolbox.get("buttons", []):
        if entry.get("category") == "select" and entry.get("rect"):
            x, y, w, _ = entry["rect"]
            return [round((x + w) / factor, 2), round(y / factor, 2)]
    return None


def swatches(run: Run) -> None:
    """The way to a strip with chips in it, once, at scale 1."""
    run.send({"docker": {"id": "ColorDocker", "at": [900, 160], "size": [320, 620]}})
    run.send({"docker_page": {"id": "ColorDocker"}})
    run.send({"wait": 30})
    run.send({"layout_gesture": {"elements": "Colour Picker"}})
    run.send({"wait": 15})
    run.send({"layout_gesture": {"switch": "Swatches"}})
    run.send({"wait": 10})
    run.send({"key": {"key": "comma", "ctrl": True}})
    run.send({"wait": 20})
    for colour in ("#c98c6e", "#78463c"):
        run.send({"colour": colour})
        run.send({"click": {"control": "AddSwatchButton", "in": "ColorDocker"}})
        run.send({"wait": 4})
    run.send({"docker": "park"})


def main() -> int:
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else PROOF / "scenario"
    out.mkdir(parents=True, exist_ok=True)
    readings: list[dict] = []
    with MutterDoor(out_dir=out) as door:
        run = Run(door, out)
        run.send({"window": list(WINDOW)})
        run.send({"wait": 45})
        run.send({"message": {"close": "escape"}})
        run.send({"document": "srgb"})
        run.send({"wait": 25})
        run.send({"prefs": {"ui_scale": 1.0}})
        run.send({"wait": 20})
        swatches(run)
        for scale in SCALES:
            for embedded in (True, False):
                tag = f"x{scale:g}-{'docked' if embedded else 'floating'}"
                run.send({"prefs": {"ui_scale": scale, "embed_subwindows": embedded}})
                run.send({"wait": 60})
                canvas(run, tag, scale)
                second_click(run, tag, scale)
                dockers(run, tag, scale, embedded)
        readings = run.readings
    (out / "readings.json").write_text(json.dumps(readings, indent=2) + "\n", encoding="utf-8")
    failed = [r["name"] for r in readings if not r["ok"]]
    print(f"{len(readings) - len(failed)} of {len(readings)} readings within {WITHIN:g} logical pixels")
    for name in failed:
        print(f"off: {name}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
