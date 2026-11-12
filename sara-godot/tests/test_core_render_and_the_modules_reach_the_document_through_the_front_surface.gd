## Core, render and the modules reach the document through the
## front surface.
##
## Two things, because there are two halves. The walk below is the sweep's
## guard: no file under `core`, `render` or `modules` finds the document the
## painter is working on by searching the canvas list, and every search left
## there is one of the few that asks a different question and says which.
## The rest is the answer those files now give, `SaDocuments.front_in` and
## `SaCanvasView.front_canvas`, read against two surfaces with the second in
## front, which is what two tabs will be.
##
## In `tests/` rather than beside one of them, because it walks three folders
## and the door it proves spans `core/api` and `render`.
extends "res://tests/test_framework.gd"

## Chunks are real textures, so the halves that hold easels need a
## RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## The folders swept.
const ROOTS: Array[String] = ["res://core", "res://render", "res://modules"]

## The two readings of the canvas list, which answer "every canvas there is"
## and "the canvas in this window". Neither names one canvas once a second
## document is open, since every tab will stand in the main window.
const LOOKUPS: Array[String] = ["in_window(", "live_canvases("]

## Characters that join a name to what stands before it, so `pointer_in_window`
## and `_rect_in_window` are read as the different functions they are.
const WORD := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"

## Every file under those folders that still reads the canvas list, and why
## each is not a lookup for the document the painter is working on. A file
## that reads the list and is not here fails, and an entry whose file has stopped
## reading it fails as stale: a list nobody measures is worse than no list.
const KEPT: Dictionary = {
    "res://render/sa_canvas.gd":
    (
        "the file that owns the list: `capture_state_all` reports every canvas a dump holds,"
        + " and `in_window` is the reading a dump of one window takes."
    ),
    "res://render/cursor/sa_cursor_ring.gd":
    (
        "which canvas the pointer is over, a question about the hand. A ring is drawn wherever"
        + " a press would paint, the scratchpad included, so the front surface answers the wrong one."
    ),
    "res://render/cursor/sa_cursor_policy.gd":
    "the same question, asked of every window that has a ring in it at all" + " before the OS pointer is hidden.",
}

var _first: SaSurface = null
var _second: SaSurface = null
var _documents: SaDocuments = null
var _registries: SaRegistries = null


func before_each() -> void:
    _first = Fixtures.make_surface(Vector2i(256, 128))
    _first.id = &"first"
    _second = Fixtures.make_surface(Vector2i(128, 256))
    _second.id = &"second"
    _documents = SaDocuments.new()
    _documents.add(_first)
    _documents.add(_second)


func after_each() -> void:
    Fixtures.teardown(_first)
    Fixtures.teardown(_second)
    _first = null
    _second = null
    _documents = null
    _registries = null


## The sweep's guard. The walk is over the source rather than over the call
## graph, because what the rule forbids is the shape of the lookup, and a
## search planted tomorrow reads the same.
func test_no_file_under_core_render_or_the_modules_searches_the_canvas_list_for_the_working_document() -> void:
    var found := _files_that_read_the_list()
    assert_false(found.is_empty(), "The walk found no reader at all, so it is measuring nothing")

    var unlisted: Array[String] = []
    for path: String in found:
        if not KEPT.has(path):
            unlisted.append(path)
    unlisted.sort()
    assert_true(
        unlisted.is_empty(),
        (
            "These search the canvas list for a canvas. Ask SaCanvasView.front_canvas() for the document"
            + " the painter is working on, or add an entry to KEPT saying which other question it asks: %s" % ", ".join(unlisted)
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


## The second half, through the door a module uses. `create_layer` with no
## document named, which is what every built-in and every module calls, lands
## in the document the painter brought forward.
func test_a_layer_added_with_no_document_named_lands_in_the_one_in_front() -> void:
    var context := _context_on_the_documents()
    assert_true(_documents.bring_to_front(_second), "The second document comes forward")

    var first_document := _first.get_document()
    var second_document := _second.get_document()
    var before := SaLayerOps.new(first_document).layers().size()
    var added := context.create_layer(SaLayerTypeDescriptor.PLAIN)

    assert_not_null(added, "A layer is added through the context with no document named")
    assert_eq(added.get_parent(), second_document, "and it lands in the document in front")
    assert_eq(SaLayerOps.new(first_document).layers().size(), before, "while the first document has the layers it had")
    assert_eq(context.get_easel(), _second.easel, "The context answers the front easel")

    var mine := context.for_module(&"probe")
    var slice := mine.document_data()
    slice["kept"] = "front"
    assert_eq(second_document.module_data.get("probe", {}).get("kept"), "front", "and its module data is the front document's")
    assert_false(first_document.module_data.has("probe"), "nothing was written into the first document")


## The lookup itself, in the two steps every caller under `render` and the
## modules now takes: the owner says which surface is in front, and the view
## says which canvas that surface draws into.
func test_the_front_surface_answers_the_canvas_render_and_the_modules_draw_on() -> void:
    var canvas := SaCanvas.new()
    var view := SaCanvasView.new()
    view.canvas = canvas
    var shown := SaSurface.create(&"shown", _second.easel, view)
    _documents.add(shown)
    var host := Host.new(_documents)

    assert_eq(SaDocuments.front_in(host), _first, "The host's owner answers the surface in front")
    assert_true(_documents.bring_to_front(shown), "The surface with a canvas comes forward")
    assert_eq(SaDocuments.front_in(host), shown, "and the host answers that one")
    assert_eq(SaCanvasView.canvas_of(SaDocuments.front_in(host)), canvas, "whose canvas is what a lookup gets")

    assert_null(SaCanvasView.canvas_of(_first), "A surface shown through a view that is no Control has no canvas")
    assert_null(SaCanvasView.canvas_of(null), "and neither has no surface at all")
    var bare := Node.new()
    assert_null(SaDocuments.front_in(null), "A host that is not there holds no owner")
    assert_null(SaDocuments.front_in(bare), "and neither does one that holds no documents")

    _documents.remove(shown)
    bare.free()
    host.free()
    canvas.free()


## A context built the way main builds its own, on the owner's front easel and
## its surfaces, with the skeleton's layer types registered so `create_layer`
## has a type to make.
func _context_on_the_documents() -> SaContext:
    _registries = SaRegistries.new()
    var context := _registries.build_context(_documents.front_easel, func() -> Array: return _documents.surfaces.duplicate())
    _registries.register_builtins()
    return context


## Every file under [constant ROOTS] holding a reading of the canvas list,
## suites and declarations apart.
func _files_that_read_the_list() -> Array[String]:
    var out: Array[String] = []
    for root: String in ROOTS:
        _walk(root, out)
    return out


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


## A stand-in for main: a node that holds the open documents the way the app's
## does, so the lookup is read through the same door with no main scene.
class Host:
    extends Node

    var documents: SaDocuments = null

    func _init(held: SaDocuments) -> void:
        documents = held
