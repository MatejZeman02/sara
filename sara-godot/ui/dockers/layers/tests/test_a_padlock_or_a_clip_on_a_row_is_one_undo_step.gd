## A row's padlocks and Clip to Layer Below are one undo step each, over every
## picked row.
##
## The padlocks and the
## clip once wrote no step, so the next Ctrl+Z took the fill laid before them and left
## the lock or the clip on. The running app's half, with real presses and a real
## Ctrl+Z, is `scenarios/a-padlock-or-a-clip-on-a-row-is-one-undo-step.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

var _easel: SaEasel
var _doc: SaDocument
var _canvas: SaCanvas
var _layers: LayersDocker
var _below: SaLayer
var _top: SaLayer


func before_each() -> void:
    _easel = Bench.easel(Vector2i(128, 128))
    _doc = _easel.document
    _below = _doc.active_layer
    _top = SaLayerOps.new(_doc).add()
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _layers = LayersDocker.new()
    _layers.target_canvas = _canvas
    _layers.list_keeper.listen()
    _layers.sync_layer_list()


func after_each() -> void:
    _layers.free()
    _canvas.free()
    _easel.free()
    _below = null
    _top = null


func _list() -> SaLayerList:
    return _layers.item_list


func _row_of(layer: SaLayer) -> int:
    for i in _list().rows.size():
        if _list().layer_at(i) == layer:
            return i
    return -1


func _pick(layer: SaLayer, ctrl: bool = false) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = true
    event.ctrl_pressed = ctrl
    _list()._on_row_gui_input(event, _row_of(layer))


## The button on *layer*'s row, pressed as a click presses it.
func _click(layer: SaLayer, which: StringName) -> void:
    var button := _list().rows[_row_of(layer)].toggles[which] as Button
    button.pressed.emit()


## The top layer filled, as one Fill Layer step, before any lock is touched.
func _fill_top() -> void:
    _pick(_top)
    _doc.fill_layer(Color(0.8, 0.2, 0.1, 1.0), _top)
    assert_false(_top.chunks.is_empty(), "the fill lays paint on the top layer")


func _undo_takes(which: StringName, step: String) -> void:
    assert_true(SaLayerFlagStep.read(_top, which), "the %s is on after the press" % which)
    assert_true(_doc.undo(), "Ctrl+Z has a step to take")
    assert_false(SaLayerFlagStep.read(_top, which), "Ctrl+Z takes the %s off, the %s step" % [which, step])
    assert_false(_top.chunks.is_empty(), "and the fill under it stays")


func test_the_paint_padlock_is_one_step() -> void:
    _fill_top()
    var steps := _doc.history.step_count()
    _click(_top, &"paint")
    assert_eq(_doc.history.step_count(), steps + 1, "the padlock writes a step")
    _undo_takes(&"paint", "Layer Lock")


func test_the_alpha_padlock_is_one_step() -> void:
    _fill_top()
    var steps := _doc.history.step_count()
    _click(_top, &"alpha")
    assert_eq(_doc.history.step_count(), steps + 1, "the alpha padlock writes a step")
    _undo_takes(&"alpha", "Layer Alpha Lock")


func test_the_clip_from_the_more_menu_is_one_step() -> void:
    _fill_top()
    var steps := _doc.history.step_count()
    _layers.actions.press_item(SaLayerActions.Item.CLIP)
    assert_eq(_doc.history.step_count(), steps + 1, "the menu's clip writes a step")
    _undo_takes(&"clip", "Clip to Layer Below")


func test_the_clip_from_the_rows_button_is_one_step() -> void:
    _fill_top()
    var steps := _doc.history.step_count()
    _click(_top, &"clip")
    assert_eq(_doc.history.step_count(), steps + 1, "the row's clip writes a step")
    _undo_takes(&"clip", "Clip to Layer Below")


## Two picked rows, one padlock pressed: both lock, as one step, and one undo
## unlocks both.
func test_the_paint_padlock_on_a_picked_pair_is_one_step() -> void:
    _pressed_on_a_pair(&"paint")


func test_the_alpha_padlock_on_a_picked_pair_is_one_step() -> void:
    _pressed_on_a_pair(&"alpha")


func _pressed_on_a_pair(which: StringName) -> void:
    _pick(_top)
    _pick(_below, true)
    assert_eq(_list().selected_layers().size(), 2, "both rows are picked")
    var steps := _doc.history.step_count()
    _click(_top, which)
    assert_true(SaLayerFlagStep.read(_top, which), "the pressed row's %s is on" % which)
    assert_true(SaLayerFlagStep.read(_below, which), "and the other picked row's")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step for the pair")
    assert_true(_doc.undo(), "one Ctrl+Z")
    assert_false(SaLayerFlagStep.read(_top, which), "takes the %s off the pressed row" % which)
    assert_false(SaLayerFlagStep.read(_below, which), "and off the other in the same step")
