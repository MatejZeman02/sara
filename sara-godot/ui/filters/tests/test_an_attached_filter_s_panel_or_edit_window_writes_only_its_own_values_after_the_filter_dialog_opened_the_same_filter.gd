## The registry holds one instance per filter, and a page built on it points
## that instance's store at the page's controls. The one-shot Filter dialog
## builds its page on the same instance as an attached record's panel in the
## tool options docker and its edit window, so either of those, touched after
## the dialog had opened on that filter, read the dialog's values and wrote
## them over the record as an Edit Filter step.
##
## The dialog now asks them to give way before it builds. The panel hides its
## rows behind a line while the dialog is up, writes nothing, and draws its
## rows again from the record once the dialog closes. The edit window settles
## as Apply settles it, so a move the painter made in it stays as one step,
## and closes. The dialog's own Apply still writes onto the layer it opened on.
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
## With the formula a record without it reads as, so a panel's page, which
## names every parameter, writes nothing when nothing moved.
const RECORD := {"formula": 0.0, "brightness": 30.0, "contrast": 25.0}

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
    _host.name = "SharedInstanceTestHost"
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


## Opens Filters > Brightness/Contrast on "Layer 1" and moves its brightness
## to 60, as the painter would.
func _one_shot() -> void:
    _doc.set_active_layer(_doc.get_node("Layer 1") as SaLayer)
    assert_true(_registry.invoke(_key), "Brightness/Contrast opens as a one-shot dialog")
    SaFilterDialogWindow.capture(Engine.get_main_loop() as SceneTree, {"widget": "brightness", "value": 60.0})
    _window.dialog.flush_rerun()


## Moves a slider of *page* as a hand would and lets the deferred write land.
## The adjust filters' sliders are rows of the module's own, moved through the
## one method their author wrote for a capture, as `SaFilterEditWindow` moves
## them.
func _move(page: SaDialog, key: StringName, value: float) -> void:
    var control := page.row(key).control
    assert_true(control != null and control.has_method("capture_option_edit"), "The %s slider takes a capture's move" % key)
    control.call("capture_option_edit", {"value": value})
    page.flush_rerun()


func _under() -> Color:
    return Bench.texel((_doc.get_node("Layer 1") as SaLayer).get_field(LEFT), AT)


func test_a_panel_rerun_after_the_dialog_was_cancelled_writes_nothing() -> void:
    var panel := _panel()
    var steps := _doc.undo_redo.get_history_count()
    _one_shot()
    _window.cancel_filter()
    panel.dialog.request_rerun()
    panel.dialog.flush_rerun()
    assert_eq(_record.parameters, RECORD, "A rerun of the panel's page leaves the record as it was")
    assert_eq(_doc.undo_redo.get_history_count(), steps, "and adds no step")
    assert_eq(panel.writes, 0, "since the panel wrote nothing")
    assert_eq(float(panel.filter.parameters()["brightness"]), 30.0, "Its rows are drawn from the record again")
    panel.free()


func test_a_panel_writes_nothing_while_the_dialog_is_up() -> void:
    var panel := _panel()
    var steps := _doc.undo_redo.get_history_count()
    _one_shot()
    assert_true(panel.describe()["lent"], "The panel has lent the filter to the dialog")
    assert_true(panel.has_node("LentNote"), "and says so in place of its rows")
    panel.dialog.request_rerun()
    panel.dialog.flush_rerun()
    assert_eq(_record.parameters, RECORD, "A rerun of the panel's page with the dialog up writes nothing")
    assert_eq(_doc.undo_redo.get_history_count(), steps, "and makes no step")
    _window.cancel_filter()
    assert_false(panel.describe()["lent"], "Cancel hands the filter back to the panel")
    assert_false(panel.has_node("LentNote"), "and its rows stand again")
    panel.free()


func test_a_panel_move_after_the_dialog_writes_only_that_move() -> void:
    var panel := _panel()
    _one_shot()
    _window.cancel_filter()
    var steps := _doc.undo_redo.get_history_count()
    _move(panel.dialog, &"contrast", 40.0)
    assert_eq(float(_record.parameters["brightness"]), 30.0, "The record keeps its own brightness")
    assert_eq(float(_record.parameters["contrast"]), 40.0, "and takes the contrast the panel moved")
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "as one Edit Filter step")
    _doc.undo()
    assert_eq(_record.parameters, RECORD, "whose undo puts the record back")
    panel.free()


func test_the_dialog_s_apply_still_writes_its_layer_with_a_panel_up() -> void:
    var panel := _panel()
    var before := _under()
    _one_shot()
    _window.apply_filter()
    assert_true(_under().r > before.r + 0.02, "Apply brightens the layer the dialog opened on: %s from %s" % [_under(), before])
    assert_eq(_record.parameters, RECORD, "and leaves the panel's record as it was")
    panel.dialog.request_rerun()
    panel.dialog.flush_rerun()
    assert_eq(_record.parameters, RECORD, "even after a rerun of the panel's page")
    panel.free()


func test_the_edit_window_settles_and_closes_when_the_dialog_opens() -> void:
    var editor := _editor()
    _move(editor.dialog, &"brightness", 10.0)
    var steps := _doc.undo_redo.get_history_count()
    _one_shot()
    assert_false(editor.visible, "The edit window closes when the dialog opens on its filter")
    assert_null(editor.record, "and holds no record")
    assert_eq(float(_record.parameters["brightness"]), 10.0, "The record keeps the move made in the window")
    assert_eq(float(_record.parameters["contrast"]), 25.0, "and holds none of the dialog's values")
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "as the one step the settle makes")
    _window.cancel_filter()
    assert_eq(float(_record.parameters["brightness"]), 10.0, "The dialog's Cancel leaves the record as the window left it")
    _doc.undo()
    assert_eq(_record.parameters, RECORD, "and undo takes the window's edit back")
    editor.free()


func test_the_dialog_s_apply_still_writes_its_layer_after_the_edit_window() -> void:
    var editor := _editor()
    var before := _under()
    _one_shot()
    _window.apply_filter()
    assert_true(_under().r > before.r + 0.02, "Apply brightens the layer the dialog opened on: %s from %s" % [_under(), before])
    assert_eq(_record.parameters, RECORD, "and the record the edit window held is as it was")
    editor.free()
