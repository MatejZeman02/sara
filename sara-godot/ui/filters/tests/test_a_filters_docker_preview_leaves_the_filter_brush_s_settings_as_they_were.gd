## The registry holds one instance per filter, and the Filters docker's
## preview runs that instance at its defaults. It skipped a filter whose dialog,
## edit window or panel was up, but not the Filter Brush's rows, which `ui`
## never names, so a click on the brush's own filter in the docker reset the
## store the rows trust. Their next move wrote brightness 0, contrast 40 and
## formula 2 onto a brush the rows showed at 30 and 25, and the next stroke
## painted those.
##
## The preview now puts back the values the store held once its run is over,
## and still shows its picture.
##
## The painting is the bench of the filter dialog suites: two chunks across,
## the background hidden, "Layer 1" opaque over the left chunk and "Stroke"
## half transparent over both.
extends "res://tests/test_framework.gd"

const Teardown := preload("res://tests/fixtures/teardown.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const FilterRows := preload("res://modules/sara-base-modules/filter-brush/filter_rows.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(512, 256)
const LEFT := Vector2i(0, 0)
const RIGHT := Vector2i(1, 0)
const AT := Vector2i(16, 16)
const UNDER := Color(0.125, 0.625, 0.25, 1.0)
const HALF := Color(0.75, 0.25, 0.125, 0.5)
## The brush's Brightness/Contrast page, with the values the fault was seen at.
const BRUSH := {"formula": 0.0, "brightness": 30.0, "contrast": 25.0}

var _easel: SaEasel = null
var _doc: SaDocument = null
var _canvas: SaCanvas = null
var _host: Node = null
var _registry: SaFilterRegistry = null
var _key: StringName = &""
var _blur: StringName = &""
var _was_embedding: bool = false
## Every page the rows handed the docker's write, in order.
var _writes: Array[Dictionary] = []


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        _was_embedding = tree.root.gui_embed_subwindows
        tree.root.gui_embed_subwindows = true
    SaProblems.pending_refusals = PackedStringArray()
    SaProblems.announce = false

    _host = Node.new()
    _host.name = "FilterBrowserRowsTestHost"
    EventBus.add_child(_host)

    _easel = _painting()
    _doc = _easel.document
    _registry = _easel.compositor.filter_chain.registry
    _key = SaFilterRegistry.key_for(&"sara-base-modules", SaBrightnessContrastFilter.new())
    _registry.register(SaBrightnessContrastFilter.new(), &"sara-base-modules")
    _blur = SaFilterRegistry.key_for(&"sara-base-modules", SaGaussianBlurFilter.new())
    _registry.register(SaGaussianBlurFilter.new(), &"sara-base-modules")

    _canvas = SaCanvas.new()
    _canvas.easel = _easel

    _writes.clear()


func after_each() -> void:
    SaSettings.filter_way = "bake"
    Teardown.free_nodes([_canvas, _easel])
    _canvas = null
    _easel = null
    _doc = null
    _registry = null
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = _was_embedding
    SaProblems.announce = true


func _painting() -> SaEasel:
    var easel := Bench.easel(SIZE)
    var doc := easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    var under := doc.get_node("Layer 1") as SaLayer
    doc.set_active_layer(under)
    under.get_or_create_chunk(LEFT).clear(UNDER)
    var stroke := SaLayerOps.new(doc).add()
    stroke.name = "Stroke"
    for grid_pos: Vector2i in [LEFT, RIGHT]:
        stroke.get_or_create_chunk(grid_pos).clear(HALF)
    doc.history.reset()
    doc.undo_redo.clear_history()
    return easel


func _write(page: Dictionary) -> void:
    _writes.append(page.duplicate(true))


## The rows of the brush's page on *key* at *values*, in the docker's place.
func _rows(key: StringName, values: Dictionary) -> Node:
    var rows: Node = FilterRows.new(_write)
    _host.add_child(rows)
    rows.call("show_page", _page(key, values))
    return rows


func _page(key: StringName, values: Dictionary) -> Dictionary:
    return {"filter_key": String(key), "parameters": values.duplicate(true), "filter": _registry.get_filter(key)}


## Moves the Brightness/Contrast slider *key* of *page* as a hand would and
## lets the deferred write land.
func _move(page: SaDialog, key: StringName, value: float) -> void:
    var control := page.row(key).control
    assert_true(control != null and control.has_method("capture_option_edit"), "The %s slider takes a capture's move" % key)
    control.call("capture_option_edit", {"value": value})
    page.flush_rerun()


func _last_write() -> Dictionary:
    return _writes[-1].get("parameters", {}) if not _writes.is_empty() else {}


## The Filters docker's browser on the bench's registry and canvas.
func _browser() -> SaFilterBrowser:
    var browser := SaFilterBrowser.new()
    browser.target_canvas = _canvas
    _host.add_child(browser)
    browser.watch(_registry, null)
    return browser


func test_a_move_after_the_docker_previewed_the_brush_s_filter_writes_the_brush_s_values() -> void:
    var rows := _rows(_key, BRUSH)
    var browser := _browser()
    assert_true(browser.pick(_key), "The docker lists Brightness/Contrast")
    var shown: Dictionary = rows.get("filter").parameters()
    assert_eq(float(shown.get("brightness", -1.0)), 30.0, "The preview leaves the instance at the brush's brightness")
    assert_eq(float(shown.get("contrast", -1.0)), 25.0, "and its contrast")
    assert_eq(float(shown.get("formula", -1.0)), 0.0, "and its formula")
    rows.call("follow_holder")
    _move(rows.get("dialog"), &"contrast", 40.0)
    var wrote := _last_write()
    assert_eq(float(wrote.get("brightness", -1.0)), 30.0, "Contrast's move keeps the brush's brightness, not 0")
    assert_eq(float(wrote.get("contrast", -1.0)), 40.0, "and writes the contrast the rows moved")
    assert_eq(float(wrote.get("formula", -1.0)), 0.0, "and keeps the brush's formula, not the default 2")
    browser.free()
    rows.free()


func test_the_docker_still_previews_the_filter_the_brush_holds() -> void:
    var rows := _rows(_key, BRUSH)
    var browser := _browser()
    var before := browser.previews
    assert_true(browser.pick(_key), "The docker lists Brightness/Contrast")
    assert_eq(browser.previews, before + 1, "and runs its preview with the brush's rows up")
    browser.free()
    rows.free()


func test_the_docker_previews_a_filter_no_page_holds() -> void:
    var browser := _browser()
    var before := browser.previews
    assert_true(browser.pick(_blur), "The docker lists Gaussian Blur")
    assert_eq(browser.previews, before + 1, "and runs its preview, the run counted")
    browser.free()
