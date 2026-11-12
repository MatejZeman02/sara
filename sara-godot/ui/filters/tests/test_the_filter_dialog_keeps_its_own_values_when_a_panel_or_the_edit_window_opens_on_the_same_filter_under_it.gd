## The registry holds one instance per filter, and a page built on it points
## that instance's store at the page's controls. The one-shot Filter dialog
## asks a panel and the edit window to give way when it opens, but a panel or
## the edit window built while the dialog was already up took the instance
## from it, so the dialog's preview and Apply used the record's values under
## sliders showing its own, and a move of the dialog's contrast reached the
## record through the panel's next rerun.
##
## Built under the dialog, the panel and the edit window now show a line in
## place of their rows and build no page until the dialog closes.
##
## The painting is the bench of the filter dialog suites: two chunks across,
## the background hidden, "Layer 1" opaque over the left chunk and "Stroke"
## half transparent over both, with the record on the stroke and the dialog
## opened on "Layer 1".
extends "res://tests/test_framework.gd"

const Teardown := preload("res://tests/fixtures/teardown.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(512, 256)
const LEFT := Vector2i(0, 0)
const RIGHT := Vector2i(1, 0)
const AT := Vector2i(16, 16)
const UNDER := Color(0.125, 0.625, 0.25, 1.0)
const HALF := Color(0.75, 0.25, 0.125, 0.5)
const RECORD := {"formula": 0.0, "brightness": 30.0, "contrast": 25.0}
const NEAR := 0.0005

var _easel: SaEasel = null
var _doc: SaDocument = null
var _canvas: SaCanvas = null
var _window: SaFilterDialogWindow = null
var _host: Node = null
var _registry: SaFilterRegistry = null
var _key: StringName = &""
var _record: SaAttachedFilter = null
var _was_embedding: bool = false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        _was_embedding = tree.root.gui_embed_subwindows
        tree.root.gui_embed_subwindows = true
    SaProblems.pending_refusals = PackedStringArray()
    SaProblems.announce = false

    _host = Node.new()
    _host.name = "DialogFirstTestHost"
    EventBus.add_child(_host)

    _easel = _painting()
    _doc = _easel.document
    _registry = _easel.compositor.filter_chain.registry
    _key = SaFilterRegistry.key_for(&"sara-base-modules", SaBrightnessContrastFilter.new())
    _registry.register(SaBrightnessContrastFilter.new(), &"sara-base-modules")

    _canvas = SaCanvas.new()
    _canvas.easel = _easel

    _window = SaFilterDialogWindow.new()
    _window.target_canvas = _canvas
    _window.watch(_registry)
    _host.add_child(_window)

    _record = SaFilterOps.new(_doc).attach(_doc.get_node("Stroke") as SaLayer, _key, RECORD)
    SaSettings.filter_way = "bake"


func after_each() -> void:
    SaSettings.filter_way = "bake"
    Teardown.free_nodes([_window, _canvas, _easel])
    _window = null
    _canvas = null
    _easel = null
    _doc = null
    _registry = null
    _record = null
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


## The panel the Layers docker's pick of the record's row hands the tool
## options docker, built before it is added, as the docker builds it.
func _panel() -> SaFilterPanel:
    var panel := SaFilterPanel.new(_record, _registry.get_filter(_key), _doc)
    _host.add_child(panel)
    return panel


func _editor() -> SaFilterEditWindow:
    var editor := SaFilterEditWindow.new()
    editor.watch(_registry)
    _host.add_child(editor)
    editor.open(_record, _doc)
    return editor


## Opens Filters > Brightness/Contrast on "Layer 1" at brightness 60 and
## contrast 50, as the painter would.
func _one_shot() -> void:
    _doc.set_active_layer(_doc.get_node("Layer 1") as SaLayer)
    assert_true(_registry.invoke(_key), "Brightness/Contrast opens as a one-shot dialog")
    _dialog_moves(60.0, 50.0)


func _dialog_moves(brightness: float, contrast: float) -> void:
    var tree := Engine.get_main_loop() as SceneTree
    SaFilterDialogWindow.capture(tree, {"widget": "brightness", "value": brightness})
    SaFilterDialogWindow.capture(tree, {"widget": "contrast", "value": contrast})
    _window.dialog.flush_rerun()


func _under() -> Color:
    return Bench.texel((_doc.get_node("Layer 1") as SaLayer).get_field(LEFT), AT)


## What the dialog alone at brightness 60 and contrast 50 bakes into the
## texel, taken back again so the test goes on from the painting as it was.
func _alone() -> Color:
    _one_shot()
    _window.apply_filter()
    var baked := _under()
    _doc.undo()
    assert_true(_under().is_equal_approx(UNDER), "Undo puts the texel back before the measured run: %s" % _under())
    assert_true(baked.r > UNDER.r + 0.02, "The dialog alone brightens the texel: %s" % baked)
    return baked


func _assert_near(got: Color, wanted: Color, said: String) -> void:
    var off := maxf(maxf(absf(got.r - wanted.r), absf(got.g - wanted.g)), absf(got.b - wanted.b))
    assert_true(off < NEAR, "%s: %s against %s" % [said, got, wanted])


func test_a_panel_built_after_the_dialog_leaves_its_apply_the_dialog_s_values() -> void:
    var alone := _alone()
    _one_shot()
    var panel := _panel()
    assert_true(panel.describe()["lent"], "The panel built under the dialog waits behind it")
    assert_true(panel.has_node("LentNote"), "and says so in place of its rows")
    assert_null(panel.dialog, "It builds no page on the instance while the dialog is up")
    assert_eq(float(_window.filter.parameters()["brightness"]), 60.0, "The dialog's instance still answers its own sliders")
    _window.apply_filter()
    _assert_near(_under(), alone, "Apply bakes what the dialog alone gives")
    assert_eq(_record.parameters, RECORD, "and the record keeps its own values")
    assert_false(panel.describe()["lent"], "The dialog's close hands the filter to the panel")
    assert_not_null(panel.dialog, "which draws its rows")
    assert_eq(float(panel.filter.parameters()["brightness"]), 30.0, "from the record")
    panel.free()


func test_the_edit_window_opened_after_the_dialog_leaves_its_apply_the_dialog_s_values() -> void:
    var alone := _alone()
    _one_shot()
    var editor := _editor()
    assert_true(editor.visible, "The edit window opens under the dialog")
    assert_null(editor.dialog, "with no page built on the instance")
    assert_not_null(editor.find_child("WaitNote", true, false), "and a line saying where the filter is open")
    _window.apply_filter()
    _assert_near(_under(), alone, "Apply bakes what the dialog alone gives")
    assert_eq(_record.parameters, RECORD, "and the record keeps its own values")
    assert_not_null(editor.dialog, "The dialog's close lets the edit window build its page")
    assert_eq(float(editor.filter.parameters()["brightness"]), 30.0, "from the record")
    editor.accept()
    assert_eq(_record.parameters, RECORD, "Its Apply holds the record's values, none of the dialog's")
    editor.free()


func test_the_edit_window_waiting_behind_the_dialog_cancels_with_nothing_to_put_back() -> void:
    _one_shot()
    var editor := _editor()
    var steps := _doc.undo_redo.get_history_count()
    editor.cancel()
    assert_false(editor.visible, "Cancel closes the waiting window")
    assert_eq(_record.parameters, RECORD, "and the record is as it was")
    assert_eq(_doc.undo_redo.get_history_count(), steps, "with no step")
    _window.cancel_filter()
    assert_null(editor.dialog, "A closed window builds no page when the dialog goes")
    editor.free()


func test_a_dialog_move_with_the_panel_up_never_reaches_the_record() -> void:
    _one_shot()
    var panel := _panel()
    var steps := _doc.undo_redo.get_history_count()
    _dialog_moves(60.0, 70.0)
    # The waiting panel has no page, so its rerun is the write it would run.
    panel.write_back()
    assert_eq(_record.parameters, RECORD, "A rerun with the dialog up leaves the record as it was")
    assert_eq(_doc.undo_redo.get_history_count(), steps, "and makes no step")
    _window.cancel_filter()
    panel.dialog.request_rerun()
    panel.dialog.flush_rerun()
    assert_eq(_record.parameters, RECORD, "nor does a rerun of the page drawn after the dialog closed")
    assert_eq(_doc.undo_redo.get_history_count(), steps, "which makes no step either")
    assert_eq(panel.writes, 0, "since the panel wrote nothing")
    panel.free()
