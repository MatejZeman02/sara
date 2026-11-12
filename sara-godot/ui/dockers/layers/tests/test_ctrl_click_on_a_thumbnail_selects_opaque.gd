## Ctrl and a click on a layer's thumbnail selects what the layer holds.
##
## Ctrl and a click on a layer is
## selection. A disc is painted on one layer and a square on another, and the
## presses go to the layers list the way a row hands them on: Ctrl on the
## disc's thumbnail replaces the selection with it, Ctrl and Shift on the
## square's add it, Ctrl and Alt on the disc's take the disc out again. Each is
## read at a texel inside and outside, each is undone once and redone, and a
## Ctrl press on a row's name still picks the row and leaves the selection be.
##
## A docker is a `Window` and adding one to the tree in a headless test hangs,
## so nothing here enters the tree, and the thumbnail is placed by hand where
## the row's box would have put it, as `test_mask_row.gd` does.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

## The disc, in the left chunk, and the square, in the right one, so each
## layer holds one chunk of the two the canvas has.
const DISC := Rect2i(40, 40, 120, 120)
const SQUARE := Rect2i(300, 60, 100, 100)
const IN_DISC := Vector2i(100, 100)
## Inside the disc's box and outside the disc, its top left corner.
const OUT_OF_DISC := Vector2i(45, 45)
const IN_SQUARE := Vector2i(350, 110)
const OUT_OF_SQUARE := Vector2i(450, 200)

## Along the row: the thumbnail from 30 to 62, and the name well past it.
const AT_THUMB := 40.0
const AT_NAME := 150.0

var _easel: SaEasel
var _canvas: SaCanvas
var _docker: LayersDocker
var _doc: SaDocument
var _disc: SaLayer
var _square: SaLayer


func before_each() -> void:
    _easel = Bench.easel(Vector2i(512, 256))
    _doc = _easel.document
    _disc = _doc.get_node("Layer 1") as SaLayer
    _square = SaLayerOps.new(_doc).add()
    _doc.selection.select_ellipse(DISC)
    _doc.fill_layer(Color(0.8, 0.2, 0.2, 1.0), _disc)
    _doc.selection.select_rect(SQUARE)
    _doc.fill_layer(Color(0.1, 0.3, 0.9, 1.0), _square)
    _doc.selection.deselect()
    _doc.set_active_layer(_disc)
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _docker = LayersDocker.new()
    _docker.target_canvas = _canvas
    _docker.sync_layer_list()


func after_each() -> void:
    _docker.free()
    _canvas.free()
    _easel.free()


## The coverage the selection holds at *at*: one everywhere with no selection,
## zero where an active one holds no chunk.
func _selected(at: Vector2i) -> float:
    var selection := _doc.selection
    if not selection.active:
        return 1.0
    var grid := Vector2i(floori(at.x / 256.0), floori(at.y / 256.0))
    var chunk: SaChunk = selection.chunks.get(grid, null)
    if chunk == null:
        return 0.0
    var field := chunk.field(SaSelection.FIELD)
    return Bench.texel(field, at - grid * chunk.pixel_size()).r


## The row that draws *layer*.
func _row_of(layer: SaLayer) -> int:
    var rows: Array = _docker.item_list.rows
    return rows.find_custom(func(row: SaRowFrame) -> bool: return row.has_layer() and row.layer == layer)


## Presses *layer*'s row at *x* with the modifiers, the way a row hands a press
## to the list.
func _press(layer: SaLayer, x: float, shift: bool = false, alt: bool = false, ctrl: bool = true) -> void:
    var idx := _row_of(layer)
    assert_true(idx >= 0, "%s has a row" % layer.name)
    var row: SaRowFrame = _docker.item_list.rows[idx]
    row.hbox.position = Vector2.ZERO
    row.thumb.position = Vector2(30.0, 0.0)
    row.thumb.size = Vector2(32.0, 22.0)
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = true
    event.position = Vector2(x, 11.0)
    event.ctrl_pressed = ctrl
    event.shift_pressed = shift
    event.alt_pressed = alt
    _docker.item_list._on_row_gui_input(event, idx)


## Undoes the press just made, reads that the selection is back to *before*
## at *at*, and redoes it.
func _undo_gives_back(at: Vector2i, before: float, what: String) -> void:
    var after := _selected(at)
    assert_true(_doc.undo(), "%s is one step to undo" % what)
    assert_almost_eq(_selected(at), before, 1e-4, "one undo gives back the selection before %s" % what)
    assert_true(_doc.redo(), "and it redoes")
    assert_almost_eq(_selected(at), after, 1e-4, "to what %s made" % what)


func test_ctrl_replaces_shift_adds_and_alt_subtracts_the_layers_alpha() -> void:
    var picked_before: Array[int] = _docker.item_list.picked.selected_indices()
    _press(_disc, AT_THUMB)
    assert_true(_doc.selection.active, "Ctrl on the disc's thumbnail makes a selection")
    assert_almost_eq(_selected(IN_DISC), 1.0, 1e-4, "which is one inside the disc")
    assert_almost_eq(_selected(OUT_OF_DISC), 0.0, 1e-4, "and nought outside it")
    assert_almost_eq(_selected(IN_SQUARE), 0.0, 1e-4, "and nought on the other layer's square")
    assert_eq(_docker.item_list.picked.selected_indices(), picked_before, "the picked rows are as they were")
    assert_eq(_doc.active_layer, _disc, "and so is the active layer")
    assert_eq(_docker.item_list._drag_from, -1, "and no drag is armed")
    _undo_gives_back(IN_DISC, 1.0, "the replace")

    _press(_square, AT_THUMB, true)
    assert_almost_eq(_selected(IN_SQUARE), 1.0, 1e-4, "Ctrl and Shift on the square's thumbnail add the square")
    assert_almost_eq(_selected(OUT_OF_SQUARE), 0.0, 1e-4, "and nothing beside it")
    assert_almost_eq(_selected(IN_DISC), 1.0, 1e-4, "and the disc stays")
    assert_eq(_doc.active_layer, _disc, "the active layer stays the disc's")
    _undo_gives_back(IN_SQUARE, 0.0, "the add")

    _press(_disc, AT_THUMB, false, true)
    assert_almost_eq(_selected(IN_DISC), 0.0, 1e-4, "Ctrl and Alt on the disc's thumbnail take the disc away")
    assert_almost_eq(_selected(OUT_OF_DISC), 0.0, 1e-4, "and outside it was nought already")
    assert_almost_eq(_selected(IN_SQUARE), 1.0, 1e-4, "and the square stays")
    _undo_gives_back(IN_DISC, 1.0, "the subtract")


func test_ctrl_on_the_name_still_picks_the_row_and_leaves_the_selection() -> void:
    var steps := _doc.history.step_count()
    _press(_square, AT_NAME)
    assert_false(_doc.selection.active, "Ctrl on the name makes no selection")
    assert_eq(_doc.history.step_count(), steps, "and records nothing")
    assert_true(_docker.item_list.picked.selected_indices().has(_row_of(_square)), "the row joins the picked set")
    assert_true(_docker.item_list.picked.selected_indices().has(_row_of(_disc)), "beside the one picked before")


func test_a_plain_press_on_the_thumbnail_selects_nothing() -> void:
    _press(_square, AT_THUMB, false, false, false)
    assert_false(_doc.selection.active, "a press with no Ctrl is the row's as it always was")


func test_a_layer_with_no_paint_changes_nothing() -> void:
    var empty := SaLayerOps.new(_doc).add()
    _doc.set_active_layer(_disc)
    _docker.sync_layer_list()
    var steps := _doc.history.step_count()
    var picked_before: Array[int] = _docker.item_list.picked.selected_indices()
    _press(empty, AT_THUMB)
    assert_false(_doc.selection.active, "an empty layer's thumbnail selects nothing")
    assert_eq(_doc.history.step_count(), steps, "and records no step")
    assert_eq(_docker.item_list.picked.selected_indices(), picked_before, "and picks no row")


## Alt and a left press anywhere in a docker drags the docker, which is how the
## page's Ctrl and Alt never reached the thumbnail in the running app. With
## Ctrl held as well the press is the docker's controls' again, and Alt alone
## still drags.
func test_ctrl_and_alt_is_not_a_docker_drag() -> void:
    var window := Window.new()
    window.size = Vector2i(200, 150)
    var grip := Control.new()
    window.add_child(grip)
    var handle := DockerDragHandle.new()
    handle.bind(window, grip)
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.alt_pressed = true
    press.ctrl_pressed = true
    assert_false(handle.handle_input(press), "Ctrl and Alt reach the thumbnail")
    press.ctrl_pressed = false
    assert_true(handle.handle_input(press), "and Alt alone is still the docker's drag")
    window.free()
    handle.free()


func test_a_group_is_not_taken() -> void:
    var group := SaLayer.new()
    group.is_group = true
    assert_false(SaSelectOpaque.takes(group), "a group holds no pixels of its own to read")
    assert_false(SaSelectOpaque.new(_doc).select(group, SaSelection.Mode.REPLACE), "and selecting from one changes nothing")
    group.free()
