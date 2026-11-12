## The interface reaches the document through the front
## surface.
##
## Two easels, each shown through a real `SaCanvas` in an `SaCanvasView`, are
## held by an `SaDocuments` the runner hands `SaCanvasView.front_canvas()` the
## way main does in the app. Bringing the second forward must leave every
## docker that shows the document reading the second one: the four main hands a
## canvas to, through `MainFrontDocument`, and the ones that look the canvas up
## as they read it. The last test walks `ui` for a lookup that bypasses the
## front surface.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const InfoDockerScript := preload("res://ui/dockers/panels/info_docker.gd")
const FilterParameters = preload("res://ui/dockers/filters/filter_parameters.gd")

const ROOT := "res://ui"

## The readings that bypass the front surface: a call of another node's
## `get_canvas()`, which in the app is main's, and the two walks of `SaCanvas`.
const LOOKUPS: Array[String] = [".get_canvas()", "SaCanvas.in_window(", "SaCanvas.live_canvases("]

## The readings kept under `ui`, each with what it asks that is not "the
## document the painter is working on".
const KEPT: Dictionary = {
    "res://ui/canvas/sa_cursor_prediction.gd":
    (
        "which canvas view the pointer is over, a question about the hand and the windows."
        + " The scratchpad's view stops a stroke as surely as the painting's does."
    ),
}

var _first: SaEasel = null
var _second: SaEasel = null
var _canvases: Array[SaCanvas] = []
var _surfaces: Array[SaSurface] = []
var _documents: SaDocuments = null
var _host: Node = null
var _was_embedding := false


## Embedding is forced the way the docker suites force it, so the dockers under the
## host map no OS window.
func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _first = Bench.easel(Vector2i(256, 128))
    _second = Bench.easel(Vector2i(128, 64))
    _layers(_first, 1)
    _layers(_second, 3)
    _steps(_first, 1)
    _steps(_second, 4)
    _surfaces = [_surface(&"first", _first), _surface(&"second", _second)]
    _documents = SaDocuments.new()
    tree.current_scene.set(&"documents", _documents)
    _host = Node.new()
    _host.name = "U276Host"
    EventBus.add_child(_host)


func after_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    tree.current_scene.set(&"documents", null)
    tree.root.gui_embed_subwindows = _was_embedding
    _host.free()
    _host = null
    SaColors.follow(null)
    for canvas: SaCanvas in _canvases:
        canvas.free()
    _canvases.clear()
    _surfaces.clear()
    _documents = null
    _first.free()
    _second.free()


func test_the_dockers_main_wires_read_the_second_document_once_it_comes_forward() -> void:
    var layers := LayersDocker.new()
    var info: InfoDocker = InfoDockerScript.new()
    var minimap := MinimapDocker.new()
    var graph := GraphDocker.new()
    var undo := UndoDocker.new()
    _host.add_child(undo)
    var front := MainFrontDocument.new([info, minimap, graph, layers])
    _host.add_child(front)

    _documents.add(_surfaces[0])
    _documents.add(_surfaces[1])
    assert_eq(layers.target_canvas, _canvases[0], "The first document held is the one the Layers docker shows")
    undo.refresh()
    assert_eq(undo.step_names().size(), 1, "and the Undo docker lists its one step")

    assert_true(_documents.bring_to_front(_surfaces[1]), "The second document comes forward")
    var second_document := _second.document
    var second_size := second_document.canvas_size

    layers.sync_layer_list()
    assert_eq(layers.target_canvas, _canvases[1], "The Layers docker holds the second canvas")
    assert_eq(
        layers.item_list.row_count(),
        SaLayerOps.new(second_document).layers().size(),
        "and draws a row for each of the second document's layers"
    )
    assert_true(
        SaLayerOps.new(second_document).layers().size() != SaLayerOps.new(_first.document).layers().size(),
        "which is a count the first document does not have"
    )

    undo.refresh()
    var second_steps := second_document.undo_redo.get_history_count()
    assert_eq(undo.step_names().size(), second_steps, "The Undo docker lists the second document's steps")
    assert_true(second_steps > 1, "which are more than the first document's one")
    assert_eq(info.target_canvas.document.canvas_size, second_size, "The Info docker reads the second document's size")
    assert_eq(minimap.target_canvas.document.canvas_size, second_size, "and so does the minimap")
    assert_eq(graph.target_canvas.document.canvas_size, second_size, "and so does the graph")
    assert_true(second_size != _first.document.canvas_size, "a size the first document does not have")
    assert_eq(SaColors._document, second_document, "The colour store follows the second document's mask target")

    assert_true(_documents.bring_to_front(_surfaces[0]), "The first comes back to the front")
    assert_eq(graph.target_canvas.document.canvas_size, _first.document.canvas_size, "and the graph reads it again")
    undo.refresh()
    assert_eq(undo.step_names().size(), 1, "and the Undo docker lists its one step again")

    layers.free()
    info.free()
    minimap.free()
    graph.free()


func test_filter_parameters_and_the_reference_docker_read_the_second_document() -> void:
    var record := SaFilterOps.new(_second.document).attach(_second.document.active_layer, Bench.INVERT)
    assert_not_null(record, "A filter is attached to a layer of the second document")
    _first.document.reference_boards = [SaReferenceBoard.new("First's board").to_header()]
    _second.document.reference_boards = [SaReferenceBoard.new("Second's board").to_header()]

    var parameters := FilterParameters.new()
    _host.add_child(parameters)
    var docker_of_references := ReferenceDocker.new()
    _host.add_child(docker_of_references)
    var was_kept: Variant = SaSettings.get_docker_option(SaDockerIds.REFERENCE, ReferenceDocker.OPTION_STORE)
    SaSettings.set_docker_option(SaDockerIds.REFERENCE, ReferenceDocker.OPTION_STORE, "document")

    _documents.add(_surfaces[0])
    _documents.add(_surfaces[1])
    parameters.pick(record)
    assert_null(parameters.shown_record(), "With the first document in front the second's filter is not shown")
    assert_eq(docker_of_references.board().name, "First's board", "and the Reference docker shows the first document's board")

    _documents.bring_to_front(_surfaces[1])
    assert_eq(parameters.shown_record(), record, "Filter parameters shows the filter of the second document's layer")
    assert_eq(docker_of_references.board().name, "Second's board", "and the Reference docker shows the second document's board")

    SaSettings.set_docker_option(SaDockerIds.REFERENCE, ReferenceDocker.OPTION_STORE, was_kept)


func test_no_file_under_ui_reaches_the_working_document_around_the_front_surface() -> void:
    var found: Array[String] = []
    _walk(ROOT, found)
    var unlisted: Array[String] = []
    for path: String in found:
        if not KEPT.has(path):
            unlisted.append(path)
    unlisted.sort()
    assert_true(
        unlisted.is_empty(),
        (
            "These reach a canvas around the front surface. Ask SaCanvasView.front_canvas() for the"
            + " document the painter is working on, or add a row to KEPT saying which other question"
            + " it asks: %s" % ", ".join(unlisted)
        )
    )
    var stale: Array[String] = []
    for path: String in KEPT:
        if not found.has(path):
            stale.append(path)
    assert_true(stale.is_empty(), "These no longer read a canvas that way, so take their rows out of KEPT: %s" % ", ".join(stale))
    for path: String in KEPT:
        assert_true(String(KEPT[path]).length() > 40, "%s says why it keeps its reading" % path)


## *count* plain layers added to *easel*'s document.
func _layers(easel: SaEasel, count: int) -> void:
    for i in count:
        SaLayerOps.new(easel.document).add()


## *count* named steps committed to *easel*'s history.
func _steps(easel: SaEasel, count: int) -> void:
    var undo_redo := easel.document.undo_redo
    for i in count:
        undo_redo.create_action("Step %d" % (i + 1))
        undo_redo.add_do_method(func() -> void: pass)
        undo_redo.add_undo_method(func() -> void: pass)
        undo_redo.commit_action()


## A surface shown the way the app shows one, a canvas in a view.
func _surface(id: StringName, easel: SaEasel) -> SaSurface:
    var canvas := SaCanvas.new()
    canvas.easel = easel
    var view := SaCanvasView.new()
    view.canvas = canvas
    _canvases.append(canvas)
    return SaSurface.create(id, easel, view)


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
        elif entry.get_extension() == "gd" and _reads_around(child):
            out.append(child)
        entry = dir.get_next()
    dir.list_dir_end()


## Whether a line of *path* that is not a comment holds one of the lookups.
func _reads_around(path: String) -> bool:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return false
    for line: String in file.get_as_text().split("\n"):
        if line.strip_edges().begins_with("#"):
            continue
        for lookup: String in LOOKUPS:
            if line.contains(lookup):
                return true
    return false
