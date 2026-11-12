#!/usr/bin/env python3
"""Regenerate the file map pages from the source tree itself.

A hand-kept list of files is the purest form of the rot `check_docs.py` exists
to catch: it is correct on the day it is written and wrong the first time
anybody renames anything. Nobody notices, because nothing reads it often enough
to trip over the gap. So the map is generated, and the tree is the source of
truth.

What is *not* generated is the one-line reason each directory exists. That is
the part a reader actually needs and the part a script cannot infer, so it is
kept in AREAS below. A directory missing from AREAS is an error rather than a
silent omission, which is what stops a new area from quietly failing to appear.

The per-file line is the file's own docstring, so keeping the map honest is the
same act as documenting the file. Two files have no docstring today and the map
says so instead of inventing one.

    python3 sara-godot/scripts/gen_file_map.py            # rewrite in place
    python3 sara-godot/scripts/gen_file_map.py --check    # fail if stale

Run it after adding, renaming or moving a source file. The gate runs --check.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path, PurePath

REPO_ROOT = Path(__file__).resolve().parents[2]
GODOT = REPO_ROOT / "sara-godot"
OUT = REPO_ROOT / "docs" / "architecture" / "FILE_MAP.md"
PACKAGES_DIR = OUT.parent / "packages"

# Every directory holding source, and the one line that says why it is there.
# Order is the reading order of the map: the headless model first, then what
# draws it, then what a person clicks, then the shaders and the two shipped
# modules. A directory not listed here fails the run.
AREAS = [
    ("core", "The document model, and the parts of it that never touch a screen."),
    ("core/api", "What a module is handed. Every descriptor a third party fills in to register something."),
    ("core/registry", "Where those descriptors land. One registry per kind of thing a module can add."),
    ("core/builtin", "Sara's own module, registered through exactly the API above."),
    ("core/custom-shader", "The `.gmacs` compiler and the RAII wrapper around a compute dispatch."),
    ("render", "The GPU side: chunks composited into a texture, and the node that shows it."),
    ("tools", "The state machine every tool runs inside."),
    ("ui", "The application window: menus, dialogs, the theme, and the scale chain."),
    ("ui/menus", "One file per menu under the top bar, so a phase that fills a menu edits one file."),
    ("ui/dockers", "The panels around the canvas, and the machinery that lets them float and dock."),
    ("ui/settings", "One file per Preferences page, each built through `SaSettingsRows`, so a unit adding a row edits one file."),
    ("ui/brush_editor", "The brush editor and the controls only it shows, starting with the curve option."),
    ("ui/welcome", "The window a painter meets before any brush, and one file per pane in it."),
    ("utils", "Small conversions with no home of their own."),
    ("shaders/compute", "The kernels. One file per job, `#kernel` per entry point."),
    ("shaders/compute/libs", "Include-only `.gmacs`: maths shared between kernels, no kernels of its own."),
    ("patterns", "The patterns Sara ships"),
    ("modules/sara-base-modules/base", "The brush, eraser, fill, eyedropper, pan and zoom."),
    ("modules/sara-base-modules/base/tools", "One file per tool state, each registered through `SaToolDescriptor`, for the tools with no folder of their own."),
    ("modules/sara-base-modules/base/wand", "The magic wand and its flood."),
    ("modules/sara-base-modules/base/magnetic", "The Magnetic Lasso, intelligent scissors: the kernel that weighs a window of the picture into links, the live path's search, one trace with its anchors and path cooling, the tool state and its option rows."),
    ("modules/sara-base-modules/base/colorize", "The Colourise layer: a layer type whose flats fill the regions of a line art layer from a few colour scribbles, the fill kernels that carry each key across the window under a cost high on the ink, the kernel that shows the flats with the scribbles, and its docker."),
    ("modules/sara-base-modules/base/patch", "The patch tool. Its state, its Smooth and Texture methods and their two kernels, a feature folder beside the wand."),
    ("modules/sara-base-modules/base/gradient", "The gradient tool. Its state, the pass that lays the ramp, its stock ends and its kernel, a feature folder beside the wand."),
    (
        "modules/sara-base-modules/base/transform",
        "The transform tool's free transform. The gesture, the pass that lifts, previews and commits, the box's handles and its kernels. The warps and the selection's carry are folders below.",
    ),
    (
        "modules/sara-base-modules/base/transform/warps",
        "The transform's warps. The perspective's homography, the freehand mesh and its kernel, the points a hand places on either with the drags that place them, and the strip a mode is picked on, cut from the free transform since the two would not fit one package.",
    ),
    (
        "modules/sara-base-modules/base/transform/warps/cage",
        "The transform's Cage mode. The polygon a painter clicks round the subject, its Green coordinates worked out at the close over a dense grid on the lifted box, and the grid each drag of a cage point moves, which the freehand warp's kernel draws the picture through.",
    ),
    (
        "modules/sara-base-modules/base/transform/live",
        "The transform tool's session on a layer's live transform, which the pass holds in place of a lift with nothing selected, drawing each map through the layer's own transform and ending in one history step.",
    ),
    (
        "modules/sara-base-modules/base/transform/group",
        "The transform tool's pass on a group. The box round every paint layer inside it at any depth, each previewed through a live map, the ordinary ones baked and the smart ones kept live at Enter, the group masks carried, all in one history step.",
    ),
    (
        "modules/sara-base-modules/base/transform/drawn",
        "The transform tool's move of a text layer. The lift takes the layer as paint for the drag, and Enter hands the move to the recipe, which draws the letters again at the new place in one step, while a scale, a turn, a skew or a selected part is refused.",
    ),
    (
        "modules/sara-base-modules/base/transform/mask",
        "The layer mask's half of a transform. The carry that cuts the mask out of the layer with the lifted paint, draws it moved under each frame of the drag and lays it down through the paint's own map at Enter, with its two kernels.",
    ),
    (
        "modules/sara-base-modules/base/transform/selection",
        "The selection's half of a transform. The carry that resamples the mask through the map a lift's pixels went through, and Select > Transform Selection, the pass that moves, turns and scales the outline alone with the tool's box and lands it in one history step at Enter.",
    ),
    ("modules/sara-base-modules/base/assistants", "The drawing assistants, a feature folder whose facade `sa_assistants.gd` registers the Assistants tool that places, moves and deletes rulers, the View menu's Show Assistants and the holder that keeps every brush stroke on the nearest ruler through `SaStrokeHold` while Snap is on."),
    ("modules/sara-base-modules/base/liquify", "Liquify, an engine of the Brush and a feature folder whose facade `sa_liquify.gd` registers it with its settings resource, its shipped presets, one per mode with a thumbnail drawn on a grid of its own, and the command that picks the last one used: a session's displacement field, its three kernels and its tool state, with push, reconstruct, twirl, shrink and grow and a smooth of the picture itself."),
    (
        "modules/sara-base-modules/base/filters",
        "The six adjustments as filters, their panels and the slider over a ramp, and the engine that came out of the skeleton with them. Levels, Colour Lookup and the gradient map are the folders beside them.",
    ),
    (
        "modules/sara-base-modules/base/filters/levels",
        "Levels. A feature folder whose facade `levels_filter.gd` registers it: the filter with its Equalize map, the panel of handles and histogram, the bar they sit on and the node histogram Equalize reads.",
    ),
    (
        "modules/sara-base-modules/base/filters/color_lookup",
        "Colour Lookup. A feature folder whose facade `color_lookup_filter.gd` registers it: the filter that moves every pixel towards the nearest colour of a palette in Oklab, and the strip of chips, each with its own bands, it is edited on (cut out of `filters`).",
    ),
    (
        "modules/sara-base-modules/base/filters/gradient_map",
        "Gradient Map. A feature folder whose facade `gradient_map_filter.gd` registers it: the filter with its ramp and its table, the panel of ramp editor and shortcuts, and the point kernel that picks a colour by lightness.",
    ),
    (
        "modules/sara-base-modules/base/filters/white_point",
        "White Point. A feature folder whose facade `white_point_filter.gd` registers it: the filter with its von Kries matrix, the panel of eyedropper, Auto and swatch over Levels' sampler, the point kernel that applies the matrix in linear light, and Auto's estimate from the surfaces or the edges with the kernel that sums it chunk by chunk.",
    ),
    (
        "modules/sara-base-modules/base/filters/local_contrast",
        "Local Contrast. A feature folder whose facade `local_contrast_filter.gd` registers it: darktable's local laplacian on the Oklab lightness, a pyramid of five levels with its remaps kept in a storage buffer, and the kernel of its four steps, which carries darktable's remapping curve under its notice.",
    ),
    (
        "modules/sara-base-modules/base/usual",
        "The usual filters, one file each, in a folder of their own beside the six adjustments: noise, the denoises, the sharpens, the two map filters and Box Blur with its kernel of three steps.",
    ),
    ("modules/sara-base-modules/base/shaders", "The wand's flood and the six adjustments, the kernels that followed their tools and filters out of the skeleton."),
    (
        "modules/sara-base-modules/base/simulation",
        "The simulation rules the base module ships after Spread, each a kernel `module.gd` registers through `SaContext.register_simulation_rule` as a stranger's would: the Game of Life on the birth and survival counts a painter sets, Conway's by default.",
    ),
    (
        "modules/sara-base-modules/base/ui",
        "The widgets this module brings for its own option rows, through `SaOptionSpec.Kind.CUSTOM` (E6).",
    ),
    (
        "modules/sara-base-modules/stamp-brush",
        "The stamp brush engine, which groups B and C fill in: the module, its settings and the masking brush they carry.",
    ),
    (
        "modules/sara-base-modules/stamp-brush/tools",
        "The brush, the eraser and their settings, with the stroke's route, the kernel's bindings and the report a capture reads.",
    ),
    (
        "modules/sara-base-modules/stamp-brush/walk",
        "The stroke's walk. The stabilizer the samples are smoothed by, the batch a frame's dabs are sent in, and the budget that carries a fast stroke over frames.",
    ),
    (
        "modules/sara-base-modules/stamp-brush/krita",
        "The stamp's Krita import. The reader of a `.kpp`, a folder or a `.bundle`, the mapping table onto the settings with its curves and its masking brush, Krita's own pressure curve, and the door's `kpp` and `preset_import` steps.",
    ),
    (
        "modules/sara-base-modules/stamp-brush/presets",
        "The stamp's shipped presets. The basic set, the drawn bundle, the Krita bundles a module installs at first run, and the converters to the noise brush's presets and back.",
    ),
    (
        "modules/sara-base-modules/stamp-brush/pattern",
        "The stamp's dab pattern. The paper every dab is textured with, the tone folded into it and the door's `pattern` step.",
    ),
    ("modules/sara-base-modules/stamp-brush/shaders", "The engine's own kernels, one file per job, `#kernel` per entry point."),
    (
        "modules/sara-base-modules/stamp-brush/ui",
        "The curve option's page widget and its sensor list, beside the option they edit.",
    ),
    (
        "modules/sara-base-modules/filter-brush",
        "The filter brush, an engine of the Brush that paints any filter the registry offers with the parameters its own dialog sets: the stroke that filters from the layer as it was at the press and mixes the result in by its coverage, the gesture and the settings window.",
    ),
    (
        "modules/sara-base-modules/filter-brush/presets",
        "The filter brush's shipped presets, a blur, a sharpen, a desaturate and a grain.",
    ),
    (
        "modules/sara-base-modules/image-formats",
        "The picture formats Sara reads and writes beyond the four Godot decodes, registered through `SaContext.register_image_format` after the skeleton's: TIFF, Radiance HDR and OpenRaster.",
    ),
    (
        "modules/sara-base-modules/image-formats/tiff",
        "Sara's own TIFF writer, 16-bit integer or 32-bit float, and the reader that opens what it and other painters write, uncompressed, Deflate, LZW or PackBits.",
    ),
    (
        "modules/sara-base-modules/image-formats/radiance",
        "The Radiance reader: a `.hdr`'s header, flat and run-length scanlines, RGBE and XYZE in all eight orientations, read to the bit.",
    ),
    (
        "modules/sara-base-modules/image-formats/open_raster",
        "OpenRaster, the layered file Krita, GIMP and MyPaint all read: the writer, the reader that opens one as a document, and the stored zip both are made of.",
    ),
    (
        "modules/sara-base-modules/stats",
        "The Stats docker as a module of the base modules: numbers about the picture on `SaReductions`, computed only while the docker is open and its switch is on, each number a part of its own (a module).",
    ),
    (
        "modules/sara-base-modules/kaleidoscope",
        "The second showcase module, read after the box blur: a widget of its own, presets, a pass that reads the whole layer and a suite.",
    ),
    (
        "modules/sara-base-modules/exposure",
        "The Exposure docker as a module of its own, the first docker a module registers: the view's exposure, the paint's and the active layer's values, each in stops.",
    ),
    (
        "modules/sara-base-modules/sphere",
        "The Sphere docker as a module of its own, the second after Exposure: the panorama on a ball seen from outside through the Environment view's maths, turned by a drag inside it.",
    ),
    (
        "modules/sara-base-modules/language-en-us",
        "American English, a catalogue `scripts/write_en_us.py` writes from the tree and its table.",
    ),
    (
        "modules/sara-base-modules/blender-live",
        "Blender Live: a socket on 127.0.0.1 that takes Blender's frames and lands each in a frame layer, reached by the skeleton's frame role.",
    ),
    (
        "modules/sara-base-modules/blender-live/shaders",
        "Blender Live's kernel: a Blender layer's own exposure and Sara's tone mapper, run from the linear frame the layer keeps.",
    ),
    (
        "modules/sara-base-modules/drifting-sky",
        "The first module to register a scene type: a drifting sky in Add Layer.",
    ),
    (
        "modules/sara-base-modules/midi",
        "MIDI as a module of its own, shaped to be a repository of its own: a controller's knobs, faders and keys drive the sliders, presets and filters a painter maps them to, through an input source, a Preferences page, Map to MIDI and the context's drive, with Listen and the bindings its own preferences.",
    ),
    (
        "modules/sara-base-modules/linux-pen",
        "The pen read from the kernel on Linux, so the upper barrel button let go in the air is heard where Godot's Wayland driver says nothing.",
    ),
    ("modules/sara-base-modules/text", "Text layers, point text in one font: a drawn layer whose recipe keeps the shaped glyphs and their outlines, so a `.sad` draws the same pixels where the font is missing, registered with the Text tool and the door's `text` and `font` steps."),
    ("modules/sara-base-modules/text/fonts", "The fonts a text layer is set in: the three shipped, Source Serif 4, Comic Neue and Caveat, with their licences, any file loaded, and what a `.sad` keeps to name one."),
    ("modules/sara-base-modules/text/layout", "A block shaped line by line at the size outlines are read at, its carets and hit tests, and each glyph's outline as path data in thousandths of an em."),
    ("modules/sara-base-modules/text/edit", "The Text tool's state, which the shortcut router asks before any chord while a block is edited, and the session that makes the layer and records the one history step."),
    ("modules/sara-base-modules/text/door", "The door's `text` and `font` steps, reached through the roles the module registers."),
    ("modules/sara-base-modules/vector", "Vector layers: a drawn layer of rectangles and ellipses with a fill and a stroke, its recipe, the objects, the door's `shape` step and the suite."),
    ("modules/sara-base-modules/vector/tools", "The Shape tool, which draws an object with a drag, and the Object tool, which picks, moves and resizes them by their handles."),
    ("modules/sara-base-modules/vector/ui", "The objects list on the Tool Options docker, with its eye, lock, order and colour buttons."),
    (
        "modules/sara-pigment-mixing",
        "A blend mode that mixes paint the way real paint mixes: the first mode with side data, a baked model it binds as a storage buffer.",
    ),
    (
        "modules/sara-jxl",
        "JPEG XL, the first native module: a GDExtension `SaJxl` with libjxl built in, which `packaging/build.sh` builds for Linux and Windows, and a `module.gd` that registers it as the codec `jxl` a save asks for by name.",
    ),
    (
        "modules/sara-tutorials",
        "Tutorials, the recorded paintings replayed with the learner's turns: a repository of its own, `sara-tutorials`, whose `module.gd` registers Help > Tutorials through the door, the three recording commands and the player a row or `--tutorials-play` starts.",
    ),
    (
        "modules/sara-tutorials/recording",
        "The recording mode, `lesson_recorder.gd` its facade: the recorded input read as a scenario's steps, the microphone or a sound file on a bus of its own, the box a turn's instruction is asked in, chapters and turns saved as states.",
    ),
    (
        "modules/sara-tutorials/lesson",
        "The lesson folder's format, written and read: `lesson.json`, `steps.json`, `voice.wav`, `instructions.pot` and `states/`.",
    ),
    (
        "modules/sara-tutorials/player",
        "The lesson player, `lesson_player.gd` its facade: the steps laid out as beats on the recording's clock and sent at a pace as a hand's input, the drawn pointer and ring, the voice a passage at a time, the box, and the check of a learner's turn.",
    ),
    (
        "modules/sara-background-removal",
        "Select Subject, a repository of its own, `sara-background-removal`: a selection tool through the door, and the weights downloaded once on the painter's Accept.",
    ),
    (
        "modules/sara-background-removal/network",
        "U²-NetP as Sara's kernels, `subject_network.gd` its facade: the 191 steps of convolution, pool, resample and sigmoid recorded as one compute list over four pages of intermediates, the folded weights read through U399's file.",
    ),
    (
        "modules/sara-background-removal/selection",
        "The click's selection, `subject_selection.gd` its facade: the merged picture or the active layer resampled to the network's tensor on the GPU, the mask spread bilinearly into the selection's `r32f` chunks through `merge_region` as one undo step, nothing read back.",
    ),
    (
        "modules/sara-language-cs",
        "Sara's own Czech, a repository of its own, `sara-language-cs`: `cs.po`, a machine draft of every message that no Czech speaker has reviewed yet, registered through the door, and `cs.machine.po`, that draft untouched.",
    ),
    (
        "modules/sara-noise-brush-engine",
        "The noise brush. A second submodule that sees the door only: its tool, settings, stroke state and dab kernel.",
    ),
    (
        "modules/sara-noise-brush-engine/dab_list",
        "The noise brush's dab list. An event's stretch of points in the buffer the kernel reads, laid on every image the symmetry paints and sent as one compute list, and the field's binding, the other buffer every dispatch reads.",
    ),
    (
        "modules/sara-noise-brush-engine/build_up",
        "The noise brush's build-up. The path a stroke has laid so far, a point every quarter radius, written near each stretch for the kernel's `noise_build_up`, so a pen that comes back over the stroke's own paint builds it up while a single pass stays a wash.",
    ),
    (
        "modules/sara-noise-brush-engine/field_kernel",
        "The noise brush's field pass for a field that brings its own kernel: the dab kernel built again with a module's GLSL where the shipped fields are read, and the seam it goes in at.",
    ),
    (
        "modules/sara-noise-brush-engine/field_folder",
        "The painter's own noise fields. One `.gmacs` file each in `brush-fields/noise/` under the data folder, registered through a context of their own, read again when a file's text moves, with the header that names a field and its numbers.",
    ),
    (
        "modules/sara-noise-brush-engine/tip",
        "The noise brush's tip. The Tip row with its Image choice, Tip Image list and Load Tip action, and the tip's arithmetic as a point of the stroke takes it, its stretch, its box and its reach.",
    ),
    (
        "modules/sara-noise-brush-engine/presets",
        "The noise brush's eight presets. And the cut a preset stored before the shift was painted under, carried to the shift it is now.",
    ),
    (
        "modules/sara-noise-brush-engine/randomise",
        "The noise brush's randomise row under a slider: how far the setting rolls below it, along the stroke or once a stroke.",
    ),
]

SOURCE_SUFFIXES = (".gd", ".gmacs")

# The skeleton's folders and their blurbs come from the package manifest once
# the tree has moved into packages, so a package row that adds a folder edits
# its own entry there and never this script. `AREAS` stays the list for the
# shaders and the modules, which are not packages of the skeleton.
#
# **Once the tree has moved** is read off the manifest itself: while a package
# still carries its `files` list the move has not run, the manifest describes a
# tree that does not exist yet, and `AREAS` is used whole. With no manifest at
# all the same holds.
MANIFEST = GODOT / "packages.json"
SKELETON_ROOTS = ("core", "render", "tools", "ui", "utils", "harness")


def areas(manifest: Path = MANIFEST) -> list[tuple[str, str]]:
    """Every directory of the map with its blurb, in reading order."""
    if not manifest.exists():
        return list(AREAS)
    packages = json.loads(manifest.read_text(encoding="utf-8"))["packages"]
    if any("files" in entry for entry in packages):
        return list(AREAS)
    skeleton = [(entry["dir"], entry["about"] + ".") for entry in sorted(packages, key=lambda entry: entry["dir"])]
    rest = [(name, blurb) for name, blurb in AREAS if name.split("/")[0] not in SKELETON_ROOTS]
    return skeleton + rest


def manifest_packages(manifest: Path = MANIFEST) -> list[dict]:
    """The manifest's own package entries, once the tree has moved, else none.

    The same "has the move run" test `areas()` makes, kept separate because a
    package's kind and public face are not part of what `areas()` promises: its
    callers, `test_file_map.py` among them, only ever asked it for the blurb.
    """
    if not manifest.exists():
        return []
    packages = json.loads(manifest.read_text(encoding="utf-8"))["packages"]
    if any("files" in entry for entry in packages):
        return []
    return packages


CLASS_NAME = re.compile(r"^class_name\s+(\w+)", re.M)


def package_page(name: str) -> Path:
    """The page under `packages/` for a package or an area, its folder with slashes as hyphens."""
    return PACKAGES_DIR / (name.replace("/", "-") + ".md")


def package_meta(name: str, by_dir: dict[str, dict]) -> tuple[str, "str | list[str]"]:
    """(kind, public face) for a mapped entry: the manifest's own, or an area's default.

    A shader or module directory carries neither in `AREAS`, because it is not
    a package of the skeleton and nothing splits it into a public and a private
    half, so the whole of it is its face.
    """
    entry = by_dir.get(name)
    if entry is not None:
        return entry.get("kind", "feature"), entry.get("public", "*")
    if name.startswith("shaders/"):
        return "shaders", "*"
    if name.startswith("modules/"):
        return "module", "*"
    return "area", "*"


def public_files(files: list[Path], public: "str | list[str]") -> list[Path]:
    """The subset of *files* that is the package's public face."""
    if public == "*":
        return list(files)
    names = set(public)
    return [path for path in files if path.name in names]


def identifiers_of(path: Path, text: str) -> set[str]:
    """A public file's own name, and the class it declares if it declares one.

    The name catches a `preload()` or a bare `res://` path, the class catches a
    type used with neither, which between them is how one file is referred to
    across the tree.
    """
    ids = {path.name}
    match = CLASS_NAME.search(text)
    if match:
        ids.add(match.group(1))
    return ids


def directory_of(rel: PurePath) -> str:
    """The directory *rel* sits in, written with forward slashes whatever the platform.

    `packages.json` and `AREAS` name directories the way git does. `str()` of a
    path on Windows joins its parts with backslashes, and a directory written
    that way is neither an area nor a package, which makes `--check` refuse the
    whole tree.
    """
    return rel.parent.as_posix()


## The words a cut cell may not end on: an article, a possessive, a
## preposition or a conjunction says only that more followed, and the cut
## dropped what did.
DANGLING = frozenset(
    "a an and as at by each every for from in into its of on one or than that the their to which with".split()
)


def short(text: str, limit: int = 36) -> str:
    """*text*, cut to a word boundary under *limit*, for a table cell. No
    ellipsis marks the cut, which would cost three bytes a row on a page held
    to a byte budget, and the row's own page carries the whole sentence. A
    sentence that ends under *limit* ends the cell, so a package's about can
    open on a short name of itself. The cell drops that sentence's full stop,
    which a table cell does not need, as a cut one drops its comma. A cut cell
    drops the words of `DANGLING` it would end on, `the` of "the reservoir" or
    `its` of "its context", which lead only into what the cut took. *limit* is
    36 because two rows that did not fit were paid for with a character off
    every cut cell each, 143 bytes the first time, and the page has no byte of
    a row's frame left to give instead."""
    stop = text.find(". ", 0, limit)
    if stop != -1:
        return text[:stop]
    if len(text) <= limit:
        return text.removesuffix(".")
    words = text[:limit].rsplit(" ", 1)[0].split(" ")
    while len(words) > 1 and words[-1].rstrip(",:;").lower() in DANGLING:
        words.pop()
    return " ".join(words).rstrip(",:;")


def grouped(names: list[str]) -> list[tuple[str, str]]:
    """`(line, name)` for every row of the top page in *names*' order, where
    *line* is either the bold folder a run of rows opens on, with *name*
    empty, or a row's name said from that folder.

    The folder is a row's first, `core` for `core/api/color`, and under
    `modules/` the module's own when it has rows of its own beside it,
    `modules/sara-base-modules` for its `stamp-brush/krita`. A module of one
    row is said from `modules`. A row naming the folder itself keeps its
    whole name, so `tools` under `**tools/**` cannot be read as the folder
    above it."""
    modules: dict[str, int] = {}
    for name in names:
        if name.startswith("modules/"):
            module = "/".join(name.split("/")[:2])
            modules[module] = modules.get(module, 0) + 1
    out: list[tuple[str, str]] = []
    opened = ""
    for name in names:
        group = name.split("/")[0]
        module = "/".join(name.split("/")[:2])
        if group == "modules" and modules.get(module, 0) > 1:
            group = module
        if group != opened:
            opened = group
            out.append(("**%s/**" % group, ""))
        out.append((name if name == group else name[len(group) + 1 :], name))
    return out


def test_paths() -> list[Path]:
    """Every tracked suite in a `tests` folder anywhere in the project, once each.

    Named `test_*.gd` by `tests/test_hard_rules.gd`'s own rule, so a fixture
    such as `tests/fixtures/modules/bundle-fixture/module.gd`, which exists to
    be loaded rather than to test anything, does not swell "Its suites" with a
    packages/library's own base classes. A suite lives in the `tests` folder
    beside what it tests, and the first `tests` folder in a
    path is the suite's, so a fixture module's own `tests` inside it is not one,
    which is the rule `run_all.gd` walks by. `--deduplicate` guards the
    half-merged index `source_paths` guards against, where one path is listed
    more than once.
    """
    listed = subprocess.run(
        [
            "git",
            "-C",
            str(GODOT),
            "ls-files",
            "-z",
            "--deduplicate",
            "--recurse-submodules",
            "--",
            ":(glob)**/tests/test_*.gd",
        ],
        capture_output=True,
        check=True,
        encoding="utf-8",
    ).stdout
    found: list[Path] = []
    seen: set[str] = set()
    for name in listed.split("\0"):
        if not name or name in seen:
            continue
        seen.add(name)
        rel = Path(name)
        if rel.name == FRAMEWORK_FILE or rel.parts.index(SUITES_DIR) != len(rel.parts) - 2:
            continue
        found.append(rel)
    return sorted(found)


def suite_home(rel: PurePath) -> str:
    """The folder a suite sits beside, `core/layers` for `core/layers/tests/x.gd`,
    and an empty string for one in `sara-godot/tests`, which tests the tree."""
    return rel.parent.parent.as_posix() if len(rel.parts) > 2 else ""


# The folder name a suite lives in, and the one file in it that is not a suite
# but the base class every suite extends.
SUITES_DIR = "tests"
FRAMEWORK_FILE = "test_framework.gd"

# Source that exists but is not part of the map. `tests` is excluded on purpose:
# 59 files whose names already say what they cover, and listing them would
# double the map's length to say nothing. `scripts` is the tooling that produces
# the map rather than the program it maps.
SKIP_DIRS = {"tests", "scripts"}

HEADER = """# File map
"""

FOOTER = """`scripts/gen_file_map.py` writes these pages, and `--check` fails on a stale
one or on a folder in neither `packages.json` nor `AREAS`.
"""

SEPARATOR = re.compile(r"^#+\s*-{3,}\s*$")

# A period that ends a sentence has whitespace or the end of the line after it.
# `.gmacs` and `256x256.` do not, which is the whole reason this is not split().
SENTENCE = re.compile(r"^(.*?[.!?])(?:\s|$)")


def first_sentence(lines: list[str]) -> str:
    """The first sentence of a docstring, rejoined across the lines it wraps over.

    Taking the first *line* looked right until `sa_easel.gd`, whose opening
    sentence runs to a second line and so appeared in the map as "the document,
    the compositor that flattens it, and the" with no end. A summary that stops
    mid-clause is worse than no summary, because it reads as the whole of what
    the file does.
    """
    paragraph: list[str] = []
    for line in lines:
        if not line:
            if paragraph:
                break
            continue
        paragraph.append(line)
    joined = " ".join(paragraph).strip()
    match = SENTENCE.match(joined)
    return (match.group(1) if match else joined).replace("|", "\\|")


def gd_docstring(text: str) -> str:
    """The purpose line of a `.gd` file: its leading `##` block, licence aside.

    `global_shader_compiler.gd` opens with a twelve-line MIT banner inside the
    same `##` run as its actual description, so the first line of the block is
    a rule of the licence rather than a statement about the file. Everything up
    to the last `## ---` separator is treated as banner.
    """
    block: list[str] = []
    for line in text.splitlines():
        if line.startswith("##"):
            block.append(line[2:].strip())
        elif not line.strip() and not block:
            # Blank lines above the docstring are fine. Code above it is not:
            # the block then belongs to whatever declaration follows it, and
            # reading it as the file's own puts the comment on a constant into
            # the map as the summary of the file.
            continue
        else:
            break
    last_rule = max((i for i, line in enumerate(block) if SEPARATOR.match("#" + line)), default=-1)
    return first_sentence(block[last_rule + 1:])


def gmacs_docstring(text: str) -> str:
    """The purpose line of a `.gmacs` file: the comment it opens with.

    The first line is usually `Kernel: <name>` or `Kernels: <a>, <b>`, which the
    file's own name already said, so the line after it is the one worth quoting.

    Three comment syntaxes, because the tree holds all three: a GLSL kernel
    opens with a `/* */` block, a dialect one opens with a run of `#` lines,
    and the two composite libraries open with a run of `//`. Reading only the
    first writes *(no docstring)* against every dialect kernel and against
    those two besides, in a map whose whole point is that a file says what it
    is.
    """
    match = re.search(r"/\*(.*?)\*/", text, re.DOTALL)
    if match:
        body = [raw.strip().lstrip("*").strip() for raw in match.group(1).splitlines()]
    else:
        body = _comment_run(text)
    return first_sentence(_without_kernel_names(body))


def _without_kernel_names(body: list[str]) -> list[str]:
    """*body* with any `Kernel:` or `Kernels:` header taken off, wrap and all.

    A file that declares more names than fit a line wraps its header, indented
    under the first name, and by the time the comment run has been read the
    indentation is gone. Dropping only the line that opens with the word
    leaves every continuation behind, which puts the tail of the list in front
    of the sentence: `composite.gmacs`, with twenty-one kernels over four
    lines, would open its cell on fourteen names.

    What ends a wrapped header is the comma: a wrap breaks the list after one,
    so every line of the header but its last ends with a comma. A header whose
    last line ends with one anyway would eat the line after it, which is the
    safe direction, because that line is part of a list nobody finished.
    """
    kept: list[str] = []
    rest = list(body)
    while rest:
        line = rest.pop(0)
        if not line.startswith(("Kernel:", "Kernels:")):
            kept.append(line)
            continue
        while line.endswith(",") and rest:
            line = rest.pop(0)
    return kept


def _comment_run(text: str) -> list[str]:
    """The run of line comments a file opens with, `#` or `//`, whichever it is.

    Taken only at the top, the way the block comment above is looked for at the
    top rather than anywhere: a comment further down belongs to whatever
    declaration follows it, which is the mistake `gd_docstring()` carries a
    paragraph about.

    `# text` and a bare `#` are comments, `#kernel` and `#include` are
    directives. A GLSL file with no block comment opens with the second kind and
    still has no docstring to quote, and reading `#kernel dab` as one would
    replace a missing summary with a wrong one.
    """
    for prefix in ("//", "#"):
        run: list[str] = []
        for raw in text.splitlines():
            line = raw.strip()
            if not line and not run:
                continue
            if not line.startswith(prefix):
                break
            if prefix == "#" and line != "#" and not line.startswith("# "):
                break
            run.append(line[len(prefix):].strip())
        if run:
            return run
    return []


def describe(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    found = gd_docstring(text) if path.suffix == ".gd" else gmacs_docstring(text)
    return found or "*(no docstring)*"


def source_paths(listing: str) -> list[Path]:
    """The source files in a NUL-separated `git ls-files` listing, once each.

    **Once each is what this function is for.** `git ls-files` prints an
    unmerged path once per merge stage, so a run against a half-merged index
    lists every conflicted file three times, and the map then carries three
    identical rows for it, three times its length in its area's total and three
    times in the repository's. That is not a hypothetical: every agent
    regenerates this map while merging, so a run under a conflict is the
    ordinary case, and one wrote a map with three
    `harness/report/sa_state_report.gd` rows and 103 files in `ui/` against the
    truth of 101.

    `--deduplicate` is git's own answer and is passed below. This is the same
    answer a second time, on purpose, because the caller is a gate command that
    every agent runs on every merge and the flag is one word away from being
    dropped by a future edit that adds a pathspec.
    """
    found: list[Path] = []
    seen: set[str] = set()
    for name in listing.split("\0"):
        if not name or name in seen:
            continue
        seen.add(name)
        rel = Path(name)
        if not any(part in SKIP_DIRS for part in rel.parts):
            found.append(rel)
    return sorted(found)


def unmerged_paths() -> list[str]:
    """Every path the index holds more than one stage of, once each.

    Deduplicating the listing above stops a conflicted tree from writing a
    tripled map, and does not stop it from writing a wrong one: `describe` and
    the line count read the file off disk, where an unresolved conflict is a
    file with markers in it and a length nobody meant. So the map refuses to be
    written at all while any of these exist, and says which.
    """
    listed = subprocess.run(
        ["git", "-C", str(GODOT), "ls-files", "-z", "-u"],
        capture_output=True,
        check=True,
        encoding="utf-8",
    ).stdout
    return sorted({entry.split("\t", 1)[-1] for entry in listed.split("\0") if entry})


def tracked_source() -> list[Path]:
    """Every source file the repository tracks, as a path relative to sara-godot.

    Asked of git rather than of the filesystem, because "in the repository" is
    exactly the set this map is about. `scratch/` holds half a dozen throwaway
    probes and is gitignored, and a skip list naming it would have to grow every
    time somebody ignores another directory.
    """
    conflicted = unmerged_paths()
    if conflicted:
        raise SystemExit(
            "gen_file_map.py: the index is half-merged, so the map would be written from a tree "
            "that is neither side. Resolve and `git add` these first: " + ", ".join(conflicted)
        )
    listed = subprocess.run(
        ["git", "-C", str(GODOT), "ls-files", "-z", "--deduplicate", "--recurse-submodules", "--", "*.gd", "*.gmacs"],
        capture_output=True,
        check=True,
        encoding="utf-8",
    ).stdout
    return source_paths(listed)


def area_section(name: str, blurb: str, files: list[Path], lines: dict[Path, int], up: str) -> list[str]:
    """A directory's own section on the single-page map, files and all.

    Used only where the tree has not moved into packages and the whole map is
    one page (`test_the_unmoved_tree_is_one_page`). Where it has,
    `package_section()` below carries the files instead, one page each.
    """
    out = [
        "## `sara-godot/%s`\n\n%s\n\n%d files, %s lines.\n"
        % (name, blurb, len(files), format(sum(lines.values()), ","))
    ]
    out.append("| File | Lines | What it is |")
    out.append("|---|---:|---|")
    for path in files:
        href = "%s/sara-godot/%s/%s" % (up, name, path.name)
        out.append("| [%s](%s) | %d | %s |" % (path.name, href, lines[path], describe(path)))
    out.append("")
    return out


def cell_list(items: list[str], cap: int = 15) -> str:
    """Every item, backticked and comma-joined, or a count and a sample past *cap*.

    `core/api` is named by 58 packages and tested by over a hundred suites, and
    listing either whole would put its own page well past the 6 KB budget on
    its own. The count is the fact that matters once a list is that long, a
    single package or file among that many is not.
    """
    if len(items) <= cap:
        return ", ".join("`%s`" % item for item in items)
    return "%d in all, among them %s, …" % (len(items), ", ".join("`%s`" % item for item in items[:cap]))


def package_section(
    name: str,
    blurb: str,
    kind: str,
    public: "str | list[str]",
    files: list[Path],
    lines: dict[Path, int],
    named_by: list[str],
    suites: list[str],
) -> str:
    """One package's own page: its files, who reaches into its public face, and who tests it."""
    face = "the whole package" if public == "*" else ", ".join("`%s`" % filename for filename in public)
    out = [
        "# `sara-godot/%s`\n" % name,
        "%s\n" % blurb,
        "**Kind:** %s. **Public face:** %s.\n" % (kind, face),
        "%d files, %s lines.\n" % (len(files), format(sum(lines.values()), ",")),
        "| File | Lines | What it is |",
        "|---|---:|---|",
    ]
    for path in files:
        href = "../../../sara-godot/%s/%s" % (name, path.name)
        out.append("| [%s](%s) | %d | %s |" % (path.name, href, lines[path], describe(path)))
    out.append("")
    named = cell_list(named_by) if named_by else "nothing outside the package"
    out.append("**Named by:** %s.\n" % named)
    tested = cell_list(suites) if suites else "none beside it or under `sara-godot/tests`"
    out.append("**Its suites:** %s.\n" % tested)
    return "\n".join(out).rstrip() + "\n"


def render_pages() -> dict[Path, str]:
    """Every page of the map with its text, the main page first.

    Where the tree has not moved into packages this is one page. Where it
    has, the main page is a table with no file in it and every package and
    area gets a page of its own under `packages/`, which is what keeps a
    reader of one package out of the other hundred and forty.
    """
    source = tracked_source()
    mapped = areas()
    from_manifest = mapped != list(AREAS)
    listed = [name for name, _ in mapped]
    missing = sorted({directory_of(rel) for rel in source} - set(listed))
    if missing:
        raise SystemExit(
            "gen_file_map.py: these directories hold source and are neither in AREAS nor a package of "
            "packages.json: " + ", ".join(missing)
        )

    # A source copy leaves module folders out, and an absent folder has no page.
    mapped = [(name, blurb) for name, blurb in mapped if (GODOT / name).is_dir()]
    files_by_name: dict[str, list[Path]] = {}
    for name, _ in mapped:
        files = sorted(GODOT / rel for rel in source if directory_of(rel) == name)
        if not files:
            raise SystemExit("gen_file_map.py: '%s' is in AREAS and holds no source." % name)
        files_by_name[name] = files

    texts = {path: path.read_text(encoding="utf-8") for files in files_by_name.values() for path in files}
    lines_by_name = {name: {path: len(texts[path].splitlines()) for path in files} for name, files in files_by_name.items()}
    total_files = sum(len(files) for files in files_by_name.values())
    total_lines = sum(sum(lines.values()) for lines in lines_by_name.values())

    if not from_manifest:
        out = [HEADER]
        for name, blurb in mapped:
            out.extend(area_section(name, blurb, files_by_name[name], lines_by_name[name], "../.."))
        out.append(
            "## Totals\n\n%d source files, %s lines, across %d directories. `tests/` is "
            "deliberately absent: 59 files whose names already say what they cover.\n"
            % (total_files, format(total_lines, ","), len(mapped))
        )
        out.append(FOOTER)
        return {OUT: "\n".join(out).rstrip() + "\n"}

    by_dir = {entry["dir"]: entry for entry in manifest_packages()}
    meta = {name: package_meta(name, by_dir) for name, _ in mapped}

    owner_of: dict[str, str] = {}
    for name, (_, public) in meta.items():
        for path in public_files(files_by_name[name], public):
            for ident in identifiers_of(path, texts[path]):
                owner_of[ident] = name

    pattern = None
    if owner_of:
        pattern = re.compile(
            r"\b(?:%s)\b" % "|".join(re.escape(ident) for ident in sorted(owner_of, key=len, reverse=True))
        )

    named_by: dict[str, set[str]] = {name: set() for name, _ in mapped}
    if pattern:
        for name, files in files_by_name.items():
            for path in files:
                for ident in set(pattern.findall(texts[path])):
                    owner = owner_of[ident]
                    if owner != name:
                        named_by[owner].add(name)

    # A suite beside a package is that package's, whatever it names, and reads
    # `tests/<suite>` on its page. One in `sara-godot/tests` is every package's
    # whose public face it names, and reads as its bare name.
    suites: dict[str, set[str]] = {name: set() for name, _ in mapped}
    for rel in test_paths():
        home = suite_home(rel)
        if home:
            if home in suites:
                suites[home].add(rel.relative_to(home).as_posix())
            continue
        if pattern is None:
            continue
        text = (GODOT / rel).read_text(encoding="utf-8")
        for ident in set(pattern.findall(text)):
            suites[owner_of[ident]].add(rel.relative_to(SUITES_DIR).as_posix())

    # The top page has a byte budget the suite holds it to, and the table is
    # as thin as GitHub's Markdown allows because every byte a row does not
    # spend is what the next row is paid for with. No public face column, which
    # cost 18 bytes a row, no count of files, 4, no kind, 10, and no space
    # beside a pipe, 6: each of the three columns is stated on the package page
    # the row links to, and Markdown renders the spaces away. No thousands
    # comma in a count of lines, which reads as well without. No pipe at the
    # start or the end of a row, which GitHub's tables do not ask for. No full
    # stop at the end of a whole cell, as a cut one has no comma, and a cut
    # cell ends on no word that only leads into what was cut, which `DANGLING`
    # drops. What is left to pay a new row with is the frame, the header and
    # footer prose and the limit on `short`, and the folder a run repeats:
    # `grouped` says it once on the bold line the run opens on and each row
    # after it reads from there.
    out = [HEADER, "Package|What for|Lines", "-|-|-:"]
    blurbs = dict(mapped)
    for line, name in grouped([name for name, _ in mapped]):
        if not name:
            out.append(line)
            continue
        out.append(
            "[%s](packages/%s.md)|%s|%d"
            % (
                line,
                name.replace("/", "-"),
                short(blurbs[name]),
                sum(lines_by_name[name].values()),
            )
        )
    out.append("")
    out.append(
        "%d files, %d lines, `tests/` aside.\n" % (total_files, total_lines)
    )

    pages: dict[Path, str] = {OUT: "\n".join(out).rstrip() + "\n"}
    for name, blurb in mapped:
        kind, public = meta[name]
        pages[package_page(name)] = package_section(
            name,
            blurb,
            kind,
            public,
            files_by_name[name],
            lines_by_name[name],
            sorted(named_by[name]),
            # The package's own suites first, so a page capped at fifteen
            # names still shows the ones that live beside it.
            sorted(suites[name], key=lambda suite: (not suite.startswith(SUITES_DIR + "/"), suite)),
        )
    return pages


def render() -> str:
    """The main page alone, for a caller that wants the top table only."""
    return render_pages()[OUT]


def with_orphans(fresh: dict[Path, str]) -> dict[Path, str]:
    """*fresh* plus every existing generated page nothing renders any more, mapped to "".

    A retired layer split (`FILE_MAP_UI.md`) and a package the manifest
    dropped are the same case: a page on disk that the current tree has no
    section for, which is as stale as a page whose text differs. The empty
    string is `main()`'s own signal to delete rather than to write.
    """
    out = dict(fresh)
    for leftover in sorted(OUT.parent.glob("FILE_MAP_*.md")):
        out.setdefault(leftover, "")
    if PACKAGES_DIR.is_dir():
        for leftover in sorted(PACKAGES_DIR.glob("*.md")):
            out.setdefault(leftover, "")
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if the file is stale instead of writing it")
    args = parser.parse_args()

    if args.check and not (REPO_ROOT / "docs").is_dir():
        print("no docs folder here (a public copy carries none), so there are no pages to check", file=sys.stderr)
        return 0
    fresh = with_orphans(render_pages())
    stale = [page for page, text in fresh.items() if (page.read_text(encoding="utf-8") if page.exists() else "") != text]
    if not stale:
        return 0
    if args.check:
        names = ", ".join(page.relative_to(REPO_ROOT).as_posix() for page in stale)
        print("%s is stale. Run: python3 sara-godot/scripts/gen_file_map.py" % names, file=sys.stderr)
        return 1
    for page in stale:
        if fresh[page]:
            page.parent.mkdir(parents=True, exist_ok=True)
            page.write_text(fresh[page], encoding="utf-8", newline="\n")
            print("wrote %s" % page.relative_to(REPO_ROOT), file=sys.stderr)
        else:
            page.unlink()
            print("removed %s" % page.relative_to(REPO_ROOT), file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
