## The registry holds one instance per filter, and a page built on it points
## that instance's store at the page's controls. The filter brush's rows in the
## Tool Options build their page on the same instance as the one-shot Filter
## dialog, so a move of a row after the dialog had opened on that filter handed
## the brush the dialog's values: brightness 60, contrast 0 and formula 2 where
## the rows read 30 and 40, and the next stroke painted those.
##
## The rows now ask the filter whose page it holds. While the dialog is up they
## hide behind a line and write nothing, and once it has gone they draw again
## from the brush's page and take the instance back, so their next move writes
## the brush's values with only that move changed.
##
## The painting is the bench of the filter dialog suites: two chunks across,
## the background hidden, "Layer 1" opaque over the left chunk and "Stroke"
## half transparent over both, with the dialog opened on "Layer 1".
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
## The brush's Brightness/Contrast page, the values a painter reported.
const BRUSH := {"formula": 0.0, "brightness": 30.0, "contrast": 25.0}

var _easel: SaEasel = null
var _doc: SaDocument = null
var _canvas: SaCanvas = null
var _window: SaFilterDialogWindow = null
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
    _host.name = "FilterRowsTestHost"
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

    _window = SaFilterDialogWindow.new()
    _window.target_canvas = _canvas
    _window.watch(_registry)
    _host.add_child(_window)
    _writes.clear()


func after_each() -> void:
    SaSettings.filter_way = "bake"
    Teardown.free_nodes([_window, _canvas, _easel])
    _window = null
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


## Opens the one-shot Filter dialog of *key* on "Layer 1" and moves *widget*
## to *value*, as the painter would.
func _one_shot(key: StringName, widget: String, value: float) -> void:
    _doc.set_active_layer(_doc.get_node("Layer 1") as SaLayer)
    assert_true(_registry.invoke(key), "%s opens as a one-shot dialog" % key)
    SaFilterDialogWindow.capture(Engine.get_main_loop() as SceneTree, {"widget": widget, "value": value})
    _window.dialog.flush_rerun()


## Moves the Brightness/Contrast slider *key* of *page* as a hand would and
## lets the deferred write land. The adjust filters' sliders are the module's
## own rows, moved through the one method their author wrote for a capture.
func _move(page: SaDialog, key: StringName, value: float) -> void:
    var control := page.row(key).control
    assert_true(control != null and control.has_method("capture_option_edit"), "The %s slider takes a capture's move" % key)
    control.call("capture_option_edit", {"value": value})
    page.flush_rerun()


func _last_write() -> Dictionary:
    return _writes[-1].get("parameters", {}) if not _writes.is_empty() else {}


func _under() -> Color:
    return Bench.texel((_doc.get_node("Layer 1") as SaLayer).get_field(LEFT), AT)


func test_a_move_after_the_dialog_was_cancelled_writes_the_brush_s_values_with_that_move() -> void:
    var rows := _rows(_key, BRUSH)
    _one_shot(_key, "brightness", 60.0)
    _window.cancel_filter()
    # The frame after the dialog went, which the rows spend taking the instance back.
    rows.call("follow_holder")
    assert_false(rows.has_node("LentNote"), "The rows stand again once the dialog has gone")
    assert_eq(float(rows.get("filter").parameter(&"brightness")), 30.0, "drawn from the brush's page")
    _move(rows.get("dialog"), &"contrast", 40.0)
    var wrote := _last_write()
    assert_eq(float(wrote.get("brightness", -1.0)), 30.0, "Contrast's move keeps the brush's brightness, not 60")
    assert_eq(float(wrote.get("contrast", -1.0)), 40.0, "and writes the contrast the rows moved, not 0")
    assert_eq(float(wrote.get("formula", -1.0)), 0.0, "and keeps the brush's formula, not the dialog's 2")
    rows.free()


func test_the_docker_s_next_show_takes_the_instance_back_as_a_frame_does() -> void:
    var rows := _rows(_key, BRUSH)
    _one_shot(_key, "brightness", 60.0)
    _window.cancel_filter()
    rows.call("show_page", _page(_key, BRUSH))
    _move(rows.get("dialog"), &"contrast", 40.0)
    var wrote := _last_write()
    assert_eq(float(wrote.get("brightness", -1.0)), 30.0, "The brush keeps its brightness")
    assert_eq(float(wrote.get("contrast", -1.0)), 40.0, "and takes the contrast moved")
    rows.free()


func test_a_move_while_the_dialog_is_up_writes_none_of_the_dialog_s_values() -> void:
    var rows := _rows(_key, BRUSH)
    _one_shot(_key, "brightness", 60.0)
    rows.call("follow_holder")
    assert_true(rows.has_node("LentNote"), "The rows say the filter is open in the Filter dialog in their place")
    _move(rows.get("dialog"), &"contrast", 40.0)
    assert_true(_writes.is_empty(), "A move with the dialog up writes nothing onto the brush: %s" % [_writes])
    _window.cancel_filter()
    rows.call("follow_holder")
    assert_false(rows.has_node("LentNote"), "Cancel hands the filter back to the rows")
    assert_eq(float(rows.get("filter").parameter(&"brightness")), 30.0, "which show the brush's brightness")
    assert_eq(float(rows.get("filter").parameter(&"contrast")), 25.0, "and its contrast")
    rows.free()


func test_a_new_brush_page_while_the_dialog_is_up_leaves_the_dialog_s_values_alone() -> void:
    var rows := _rows(_key, BRUSH)
    _one_shot(_key, "brightness", 60.0)
    var preset := {"formula": 0.0, "brightness": -10.0, "contrast": 5.0}
    rows.call("show_page", _page(_key, preset))
    var dialog_brightness := float(_window.filter.parameter(&"brightness"))
    assert_eq(dialog_brightness, 60.0, "A preset picked with the dialog up leaves the dialog at its brightness")
    _window.cancel_filter()
    rows.call("follow_holder")
    assert_eq(float(rows.get("filter").parameter(&"brightness")), -10.0, "and the rows show the preset once it has gone")
    assert_true(_writes.is_empty(), "with nothing written back, since the brush already holds it: %s" % [_writes])
    rows.free()


func test_the_gaussian_blur_s_radius_row_keeps_its_own_move() -> void:
    var rows := _rows(_blur, {"radius": 3.0})
    _one_shot(_blur, "radius", 20.0)
    _window.cancel_filter()
    rows.call("follow_holder")
    var page: SaDialog = rows.get("dialog")
    page.row(&"radius").drive(8.0)
    page.flush_rerun()
    assert_eq(float(_last_write().get("radius", -1.0)), 8.0, "The Radius row writes its own move, not the dialog's 20")
    rows.free()


func test_the_dialog_s_apply_still_writes_its_layer_with_the_rows_up() -> void:
    var rows := _rows(_key, BRUSH)
    var before := _under()
    _one_shot(_key, "brightness", 60.0)
    _window.apply_filter()
    assert_true(_under().r > before.r + 0.02, "Apply brightens the layer the dialog opened on: %s from %s" % [_under(), before])
    rows.call("follow_holder")
    assert_true(_writes.is_empty(), "and writes nothing onto the brush: %s" % [_writes])
    rows.free()
