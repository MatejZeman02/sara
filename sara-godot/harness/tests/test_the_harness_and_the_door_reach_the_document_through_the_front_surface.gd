## The harness and the door reach the document through the front surface.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Every lookup in `harness` took the first canvas in the root window. A second
## open document stands in that same window, so a `document` step opened its
## new picture in whichever canvas the list answered first and a `load` step
## overwrote one the painter had not asked about. Two canvases are built here,
## the second brought forward the way a tab will be, and the scenario's own
## calls and the door's steps are run at them: the one in front is replaced and
## the other keeps the layer it held.
##
## The walk at the end is the sweep's guard, the shape `core`, `render` and
## the modules also keep: no file under `harness` finds the document the
## painter is working on by searching the canvas list.
extends "res://tests/test_framework.gd"

## Two documents, each with an easel of chunks and an output texture.
const REQUIRES_GPU := true

const MainCanvasScript = preload("res://render/main_canvas.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CanvasDriver := preload("res://harness/drivers/sa_canvas_driver.gd")
const ScenarioDocument := preload("res://harness/scenario/sa_scenario_document.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## Where a run's files would go. Nothing here writes one, but a run is given a
## folder of its own rather than the painter's.
static var scratch_run_folder: String = SaDataRoot.path("front-surface-run")

## The name given to the layer of the document that is not in front, which is
## what says a step left it alone.
const KEPT_LAYER: String = "KeptByTheFirst"

## The sizes the two documents open at, told apart so a size answers which
## document a step reached.
const FIRST_SIZE := Vector2i(320, 200)
const SECOND_SIZE := Vector2i(256, 256)

## The saved document a `load` step opens, a painted one from the fixtures.
const SAVED: String = "res://tests/data/plain_v4.sad"

## The folder the sweep walks, and one it is proved against: the matcher has
## to find the readings `render` keeps on purpose, or an empty answer under
## `harness` would mean nothing.
const SWEPT: String = "res://harness"
const PROVEN_AGAINST: String = "res://render"

## The two readings of the canvas list, as the guard names them. Neither answers
## one canvas once a second document is open.
const LOOKUPS: Array[String] = ["in_window(", "live_canvases("]

## Characters that join a name to what stands before it, so `pointer_in_window`
## reads as the different function it is.
const WORD := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"

## Every file under [constant SWEPT] that still reads the canvas list, and why
## each asks a different question. Empty, because nothing under `harness` asks
## for a canvas any more: a file that reads the list and is not here fails, and
## a row whose file has stopped reading it fails as stale.
const KEPT: Dictionary = {}

var _host: Node = null
var _first: SaCanvas = null
var _second: SaCanvas = null
var _first_surface: SaSurface = null
var _second_surface: SaSurface = null
var _front: Fixtures.FrontDocuments = null
var _run: CaptureRun = null
var _table: StepTable = null
var _scenario: ScenarioDocument = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "U277FrontSurfaceTestHost"
    EventBus.add_child(_host)
    var first_node := _a_canvas(FIRST_SIZE, "First")
    var second_node := _a_canvas(SECOND_SIZE, "Second")
    _first = first_node.canvas as SaCanvas
    _second = second_node.canvas as SaCanvas
    _first_surface = Fixtures.FrontDocuments.surface_over(_first)
    _second_surface = Fixtures.FrontDocuments.surface_over(_second)
    _first.document.active_layer.name = KEPT_LAYER
    _front = Fixtures.FrontDocuments.over(_first)
    _front.also(_second_surface)
    _run = CaptureRun.new(scratch_run_folder)
    _table = StepTable.new(_run)
    _scenario = ScenarioDocument.new(_run)


func after_each() -> void:
    _scenario = null
    _table = null
    _run = null
    if _front != null:
        _front.close(_second_surface)
        _front.put_back()
        _front = null
    _first_surface = null
    _second_surface = null
    _first = null
    _second = null
    if _host != null:
        _host.free()
        _host = null


## A canvas of its own, the node that builds the easel, the document and the
## surface the way the app's main canvas does.
func _a_canvas(size: Vector2i, called: String) -> Node:
    var made: Node = MainCanvasScript.new()
    made.name = called
    var canvas := made.canvas as SaCanvas
    canvas.canvas_size = size
    _host.add_child(made)
    return made


## What the first document is made of, so a step that reached it shows.
func _first_layers() -> Array[String]:
    var out: Array[String] = []
    for child: Node in _first.document.get_children():
        if child is SaLayer:
            out.append(String(child.name))
    return out


## The lookup itself, before any step is run: the canvas the harness acts on is
## the one the front surface draws into, not the first in the window.
func test_the_lookup_answers_the_canvas_of_the_surface_in_front() -> void:
    assert_eq(CanvasDriver.main_canvas(), _second, "The second document is in front, so the harness finds it")
    assert_true(_front.also(_first_surface), "The first document comes forward")
    assert_eq(CanvasDriver.main_canvas(), _first, "and the harness finds that one instead")


## First case, the scenario's own call: `new_document` opens its picture in
## the document in front and leaves the other as it stands.
func test_a_new_document_replaces_the_one_in_front_and_no_other() -> void:
    var kept := _first_layers()
    _scenario.new_document("srgb", {}, [640, 480])

    assert_eq(_second.document.canvas_size, Vector2i(640, 480), "The document in front is the new one")
    assert_eq(_second.canvas_size, Vector2i(640, 480), "and its canvas was resized with it")
    assert_eq(_first.document.canvas_size, FIRST_SIZE, "The other document is the size it was")
    assert_eq(_first_layers(), kept, "with the layers it held: %s" % str(_first_layers()))
    assert_true(_first_layers().has(KEPT_LAYER), "the one it was given before the step among them")


## First case, the other half: `load_document` opens the file into the
## document in front and leaves the other as it stands.
func test_a_load_opens_into_the_document_in_front_and_no_other() -> void:
    var kept := _first_layers()
    var before: Vector2i = _second.document.canvas_size
    _scenario.load_document(SAVED)

    assert_false(_second.document.canvas_size == before, "The document in front is the file's")
    assert_eq(_second.canvas_size, _second.document.canvas_size, "and its canvas followed the file")
    assert_eq(_first.document.canvas_size, FIRST_SIZE, "The other document is the size it was")
    assert_eq(_first_layers(), kept, "with the layers it held: %s" % str(_first_layers()))
    assert_true(_first_layers().has(KEPT_LAYER), "the one it was given before the step among them")


## Second case: the door's `document` and `canvas` steps, run through the
## step table a door client's request goes through, answer the front surface.
func test_the_doors_document_and_canvas_steps_answer_the_front_surface() -> void:
    var kept := _first_layers()
    _table.run({"document": "srgb", "size": [800, 600]})
    assert_eq(_second.document.canvas_size, Vector2i(800, 600), "The `document` step made the new one in front")
    assert_eq(_first.document.canvas_size, FIRST_SIZE, "and left the other document at its size")

    _table.run({"canvas": [512, 384]})
    assert_eq(_second.document.canvas_size, Vector2i(512, 384), "The `canvas` step resized the one in front")
    assert_eq(_first.document.canvas_size, FIRST_SIZE, "and left the other document at its size")
    assert_eq(_first_layers(), kept, "which still holds the layers it did: %s" % str(_first_layers()))


## The sweep's guard, over the source rather than over the call graph: what the
## row forbids is the shape of the lookup, and a search planted tomorrow reads
## the same.
func test_no_file_under_the_harness_searches_the_canvas_list_for_the_working_document() -> void:
    var proving: Array[String] = []
    _walk(PROVEN_AGAINST, proving)
    assert_false(proving.is_empty(), "The walk finds no reader under %s, so it is measuring nothing" % PROVEN_AGAINST)

    var found: Array[String] = []
    _walk(SWEPT, found)
    var unlisted: Array[String] = []
    for path: String in found:
        if not KEPT.has(path):
            unlisted.append(path)
    unlisted.sort()
    assert_true(
        unlisted.is_empty(),
        (
            "These search the canvas list for a canvas. Ask SaCanvasView.front_canvas() for the document"
            + " a step acts on, or add a row to KEPT saying which other question it asks: %s" % ", ".join(unlisted)
        )
    )

    var stale: Array[String] = []
    for path: String in KEPT:
        if not found.has(path):
            stale.append(path)
    stale.sort()
    assert_true(stale.is_empty(), "These no longer read the list, so take their rows out of KEPT: %s" % ", ".join(stale))

    for path: String in KEPT:
        assert_true(String(KEPT[path]).length() > 40, "%s says why it keeps its reading" % path)


func _walk(dir_path: String, out: Array[String]) -> void:
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return
    dir.list_dir_begin()
    var entry := dir.get_next()
    while not entry.is_empty():
        var child := dir_path.path_join(entry)
        if dir.current_is_dir():
            if entry != "tests":
                _walk(child, out)
        elif entry.get_extension() == "gd" and _reads_the_list(child):
            out.append(child)
        entry = dir.get_next()
    dir.list_dir_end()


## Whether the file at *path* holds a line that reads the canvas list.
func _reads_the_list(path: String) -> bool:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return false
    for line: String in file.get_as_text().split("\n"):
        if _line_reads_the_list(line):
            return true
    return false


## Whether *line* reads the list. A comment is prose about it, and a `func`
## line declares one of the two readings or a different function whose name
## ends in the same word.
static func _line_reads_the_list(line: String) -> bool:
    var stripped := line.strip_edges()
    if stripped.begins_with("#") or stripped.begins_with("func ") or stripped.begins_with("static func "):
        return false
    for name: String in LOOKUPS:
        var at := line.find(name)
        while at >= 0:
            var before := line.substr(0, at)
            if before.ends_with("SaCanvas.") or not _joins_on(before):
                return true
            at = line.find(name, at + 1)
    return false


## Whether *before* ends in a character that makes the name after it part of a
## longer name or of another class's call.
static func _joins_on(before: String) -> bool:
    if before.is_empty():
        return false
    var last := before.substr(before.length() - 1)
    return last == "." or WORD.contains(last)
