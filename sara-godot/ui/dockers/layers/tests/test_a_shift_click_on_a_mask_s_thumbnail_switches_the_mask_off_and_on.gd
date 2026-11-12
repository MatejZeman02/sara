## Shift and a click on a layer's mask thumbnail switch the mask off and on.
##
## The active mask can be hidden without moving it to an empty new layer. A layer
## carries a mask, the mask is the paint target, and the presses go to the
## layers list the way a row hands them on. The first Shift press switches the
## mask off and the second on, each one undo step, the paint target and the
## picked rows untouched, and the row's mark follows. A plain press and a Shift
## press on the layer's own picture leave the mask as it was.
##
## A docker is a `Window` and adding one to the tree in a headless test hangs,
## so nothing here enters the tree, and the two pictures are placed by hand
## where the row's box would have put them, as the Ctrl click suite does.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

## Along the row: the layer's picture from 30 to 62, the mask's from 64 to 96.
const AT_THUMB := 40.0
const AT_MASK := 80.0

var _easel: SaEasel
var _canvas: SaCanvas
var _docker: LayersDocker
var _doc: SaDocument
var _layer: SaLayer


func before_each() -> void:
    _easel = Bench.easel(Vector2i(512, 256))
    _doc = _easel.document
    _layer = _doc.get_node("Layer 1") as SaLayer
    _doc.fill_layer(Color(0.8, 0.2, 0.2, 1.0), _layer)
    _doc.set_active_layer(_layer)
    assert_true(SaMaskOps.new(_doc).add(_layer), "the layer takes a mask")
    _doc.mask_target = _layer.mask
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _docker = LayersDocker.new()
    _docker.target_canvas = _canvas
    _docker.sync_layer_list()


func after_each() -> void:
    _docker.free()
    _canvas.free()
    _easel.free()


## The row that draws the layer.
func _row() -> SaRowFrame:
    var rows: Array = _docker.item_list.rows
    var idx: int = rows.find_custom(func(row: SaRowFrame) -> bool: return row.has_layer() and row.layer == _layer)
    assert_true(idx >= 0, "the layer has a row")
    return rows[idx]


## Presses the layer's row at *x*, with Shift unless *shift* says not, the way
## a row hands a press to the list.
func _press(x: float, shift: bool = true) -> void:
    var row := _row()
    assert_not_null(row.mask_thumb, "the row carries the mask's picture")
    row.hbox.position = Vector2.ZERO
    row.thumb.position = Vector2(30.0, 0.0)
    row.thumb.size = Vector2(32.0, 22.0)
    row.mask_thumb.position = Vector2(64.0, 0.0)
    row.mask_thumb.size = Vector2(32.0, 22.0)
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = true
    event.position = Vector2(x, 11.0)
    event.shift_pressed = shift
    _docker.item_list._on_row_gui_input(event, row.row_index)


## Whether the row's mask picture wears the switched-off mark, once the row has
## taken the mask's state as a redraw would give it.
func _marked() -> bool:
    var row := _row()
    row.refresh(_doc)
    return row.mask_thumb.is_dimmed()


func test_two_shift_clicks_switch_the_mask_off_and_on_one_step_each() -> void:
    var picked_before: Array[int] = _docker.item_list.picked.selected_indices()
    var steps := _doc.undo_redo.get_history_count()
    assert_false(_marked(), "a mask that is on wears no mark")

    _press(AT_MASK)
    assert_false(_layer.mask.enabled, "the first Shift click switches the mask off")
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "as one step")
    assert_eq(_doc.mask_target, _layer.mask, "and the mask is still what the brush paints")
    assert_eq(_doc.active_layer, _layer, "the active layer is as it was")
    assert_eq(_docker.item_list.picked.selected_indices(), picked_before, "and so are the picked rows")
    assert_eq(_docker.item_list._drag_from, -1, "and no drag is armed")
    assert_true(_marked(), "the row's mask picture wears the mark")

    _press(AT_MASK)
    assert_true(_layer.mask.enabled, "the second Shift click switches it on again")
    assert_eq(_doc.undo_redo.get_history_count(), steps + 2, "as one more step")
    assert_eq(_doc.mask_target, _layer.mask, "and the target is still the mask")
    assert_false(_marked(), "and the mark is gone")

    assert_true(_doc.undo(), "the switch on undoes")
    assert_false(_layer.mask.enabled, "one undo gives the mask back off")
    assert_true(_doc.undo(), "the switch off undoes")
    assert_true(_layer.mask.enabled, "and the second gives it back on")
    assert_eq(_doc.mask_target, _layer.mask, "with the target never moved")


func test_a_plain_click_or_a_shift_click_on_the_layers_picture_leaves_the_mask_on() -> void:
    _press(AT_MASK, false)
    assert_true(_layer.mask.enabled, "a plain click on the mask's picture picks it and leaves it on")
    assert_eq(_doc.mask_target, _layer.mask, "and the brush paints the mask")
    var steps := _doc.undo_redo.get_history_count()
    _press(AT_THUMB)
    assert_true(_layer.mask.enabled, "a Shift click on the layer's own picture leaves the mask on")
    assert_eq(_doc.undo_redo.get_history_count(), steps, "and adds no step")


func test_the_mask_s_tooltip_names_the_shift_click() -> void:
    var tip := _row().mask_thumb.tooltip_text
    assert_true(tip.contains("Shift"), "the mask's tooltip names the Shift click: %s" % tip)
    _press(AT_MASK)
    _row().refresh(_doc)
    tip = _row().mask_thumb.tooltip_text
    assert_true(tip.contains("Shift"), "and so does the tooltip of a mask that is off: %s" % tip)
