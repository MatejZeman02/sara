## A preview run that is still running when the slider moves
## again is dropped for the newer one, never queued behind it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Local Contrast's preview lagged under a dragged slider. It is nine steps of a
## neighbourhood pass over
## every chunk, so one run costs tens of milliseconds and a slider that asks for
## a run per frame queues them behind each other on the card. The dialog's rerun
## now goes through [SaPreviewCompressor], the rule the brush editor's strip and
## its tip preview answer to: the first change runs at once, and every change
## inside the window the run opened folds into one run when the window closes.
##
## The document is 1920 by 1080 because the rule only opens a window on a run
## that outlasts the frame that asked for it, and Local Contrast's run is tens of
## milliseconds at that size and a couple on a small one.
extends "res://tests/test_framework.gd"

const Teardown := preload("res://tests/fixtures/teardown.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const LocalContrastFilter = preload("res://modules/sara-base-modules/base/filters/local_contrast/local_contrast_filter.gd")

const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
const MODULE_DIR := "res://modules/sara-base-modules"
const SIZE := Vector2i(1920, 1080)
const PAINT := Color(0.25, 0.5, 0.75, 1.0)
## The places a short drag takes the Detail slider through.
const DRAG_TICKS := 10
const FIRST_DETAIL := 110.0
const DETAIL_STEP := 10.0

var _easel: SaEasel = null
var _doc: SaDocument = null
var _canvas: SaCanvas = null
var _window: SaFilterDialogWindow = null
var _host: Node = null
var _registry: SaFilterRegistry = null
var _key: StringName = &""
var _was_embedding: bool = false
var _dir_was_set: bool = false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        _was_embedding = tree.root.gui_embed_subwindows
        tree.root.gui_embed_subwindows = true
    _dir_was_set = ModuleLoader.module_dirs.has(OWNER)
    if not _dir_was_set:
        ModuleLoader.module_dirs[OWNER] = MODULE_DIR

    _host = Node.new()
    _host.name = "D31TestHost"
    EventBus.add_child(_host)

    _easel = Bench.easel(SIZE)
    _doc = _easel.document
    _doc.fill_layer(PAINT, _doc.active_layer)
    Bench.composite(_easel)

    _canvas = SaCanvas.new()
    _canvas.easel = _easel

    var filter := LocalContrastFilter.new()
    _key = SaFilterRegistry.key_for(OWNER, filter)
    _registry = SaFilterRegistry.new()
    _registry.register(filter, OWNER)

    _window = SaFilterDialogWindow.new()
    _window.target_canvas = _canvas
    _window.watch(_registry)
    _host.add_child(_window)


func after_each() -> void:
    Teardown.free_nodes([_window, _canvas, _easel])
    _window = null
    _canvas = null
    _easel = null
    _doc = null
    _registry = null
    if _host != null:
        _host.free()
        _host = null
    if not _dir_was_set:
        ModuleLoader.module_dirs.erase(OWNER)
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = _was_embedding


## Ten changes of a drag, each asking the way a slider tick does, read as one
## run at once and one more when the window closes, that one on the last place.
func test_ten_slider_changes_faster_than_a_run_are_folded_into_one() -> void:
    _window.open_filter(_key)
    assert_eq(_window.runs, 1, "the open runs at once")
    var row := _window.dialog.row(&"detail")
    assert_not_null(row, "Local Contrast's first row is its Detail slider")
    var coalesced_before := _window.compressor.coalesced

    for tick in range(1, DRAG_TICKS + 1):
        row.drive(FIRST_DETAIL + float(tick - 1) * DETAIL_STEP)
        _window.dialog.flush_rerun()
    assert_eq(_window.runs, 1, "and the ten changes of a drag are none of them a run")
    assert_eq(
        _window.compressor.coalesced - coalesced_before,
        DRAG_TICKS,
        "each folded into the run waiting for the window, rather than dropped"
    )
    assert_true(_window.compressor.pending, "with one run waiting for the window to close")
    assert_eq(int(_window.describe()["coalesced"]), _window.compressor.coalesced, "which the dialog's dump counts")

    _window.compressor.timeout.emit()
    assert_eq(_window.runs, 2, "the window closing runs once more")
    assert_false(_window.compressor.pending, "and leaves nothing waiting")
    var last_detail := FIRST_DETAIL + float(DRAG_TICKS - 1) * DETAIL_STEP
    assert_almost_eq(float(_window.filter.parameter(&"detail")), last_detail, 1e-6, "on the last place the slider stood")
    var pass_shown := _window.context.point as SaNeighbourhoodPass
    assert_not_null(pass_shown, "and the run recorded a neighbourhood pass")
    assert_almost_eq(
        float(pass_shown.steps[0].params["clarity"]),
        last_detail / 100.0 - 1.0,
        1e-5,
        "whose kernel params are the last change's, not the first's"
    )


## A run that a later change replaces leaves nothing queued: the pass the
## compositor holds is the last one recorded, and the chunks are marked once.
func test_a_dropped_run_leaves_the_last_pass_on_the_canvas() -> void:
    _window.open_filter(_key)
    var row := _window.dialog.row(&"detail")
    for tick in range(1, DRAG_TICKS + 1):
        row.drive(FIRST_DETAIL + float(tick - 1) * DETAIL_STEP)
        _window.dialog.flush_rerun()
    _window.compressor.timeout.emit()
    var previewed := _easel.compositor.point_preview.for_document(_doc)
    assert_true(previewed is SaNeighbourhoodPass, "the compositor previews the pass the last run recorded")
    assert_almost_eq(
        float((previewed as SaNeighbourhoodPass).steps[0].params["clarity"]),
        (FIRST_DETAIL + float(DRAG_TICKS - 1) * DETAIL_STEP) / 100.0 - 1.0,
        1e-5,
        "which is the last change's, so the picture on the canvas is the latest one asked for"
    )
