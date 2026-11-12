## The mask's picture on a layer's row, and the press that aims the brush at it.
##
## The ask: "The layers docker shows the mask beside the thumbnail, selects it
## by a click, and a mask under edit is marked on the canvas the way the quick
## mask is." The picture itself is the GPU's and the scenario's, so this holds
## what a photograph cannot: how many pictures a row carries, what a press on
## each writes into the document, the dimming of a mask that is switched off,
## and the words the canvas strip says.
##
## A docker is a `Window` and adding one to the tree in a headless test hangs,
## so nothing here enters the tree, and the two pictures are placed by hand
## where a container would have put them.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

var _easel: SaEasel
var _canvas: SaCanvas
var _docker: LayersDocker


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(128, 128))
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _docker = LayersDocker.new()
    _docker.target_canvas = _canvas
    _docker.sync_layer_list()


func after_each() -> void:
    _docker.free()
    _canvas.free()
    _easel.free()


## The row of the active layer, which is the painted one of a default document.
func _active_row() -> int:
    return _docker.item_list.picked.selected_idx


func _row(idx: int) -> SaRowFrame:
    return _docker.item_list.rows[idx]


## Every picture the row carries, counted off its box rather than off the
## members, so a picture built and never dropped would be counted too.
func _pictures(row: SaRowFrame) -> int:
    var count := 0
    for child in row.hbox.get_children():
        if child is SaLayerThumbnail and not child.is_queued_for_deletion():
            count += 1
    return count


## Lays the row's pictures out the way the box would, the layer's at 30 and the
## mask's at 70 along it, each 32 by 22.
func _lay_out(row: SaRowFrame) -> void:
    row.hbox.position = Vector2.ZERO
    row.thumb.position = Vector2(30.0, 0.0)
    row.thumb.size = Vector2(32.0, 22.0)
    if row.mask_thumb != null:
        row.mask_thumb.position = Vector2(70.0, 0.0)
        row.mask_thumb.size = Vector2(32.0, 22.0)


func _press_at(x: float) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = true
    event.position = Vector2(x, 11.0)
    return event


## Presses row *idx* at *x* along it, the way a press reaches the list.
func _press(idx: int, x: float) -> void:
    _lay_out(_row(idx))
    _docker.item_list._on_row_gui_input(_press_at(x), idx)


func test_a_row_with_no_mask_has_one_picture() -> void:
    var row := _row(_active_row())
    assert_null(row.mask_thumb, "no mask, no second picture")
    assert_eq(_pictures(row), 1, "and the box holds the one picture it always did")
    assert_false(bool(row.report()["has_mask"]), "the report says so")


func test_a_row_with_a_mask_has_two_and_the_same_height() -> void:
    var layer := _easel.document.active_layer
    var height := _row(_active_row()).custom_minimum_size.y
    layer.add_mask()
    _docker.item_list.refresh_all()

    var row := _row(_active_row())
    assert_not_null(row.mask_thumb, "a mask added while the row stood gets its picture")
    assert_eq(_pictures(row), 2, "two pictures in the box")
    assert_eq(row.mask_thumb.get_index(), row.thumb.get_index() + 1, "the mask's right after the layer's")
    assert_eq(row.custom_minimum_size.y, height, "and the row is no taller for it")

    layer.drop_mask()
    _docker.item_list.refresh_all()
    assert_null(row.mask_thumb, "a mask taken away takes its picture")
    assert_eq(_pictures(row), 1, "and the box is back to one")


func test_a_row_built_for_a_masked_layer_has_the_picture_from_the_start() -> void:
    _easel.document.active_layer.add_mask()
    _docker.sync_layer_list()
    assert_eq(_pictures(_row(_active_row())), 2, "the mask's picture is built with the row")


func test_a_press_on_the_mask_picks_it_and_one_on_the_layer_gives_it_back() -> void:
    var document := _easel.document
    var layer := document.active_layer
    var mask := layer.add_mask()
    _docker.sync_layer_list()
    var idx := _active_row()

    _press(idx, 80.0)
    assert_eq(document.mask_target, mask, "a press on the mask's picture writes the mask target")
    assert_eq(document.active_layer, layer, "and the layer stays the active one")
    var row := _row(_active_row())
    assert_eq(str(row.report()["picked"]), "mask", "the row reports the mask as picked")
    assert_true(row.mask_thumb.picked, "and the mask's rim is the picked one")
    assert_false(row.thumb.picked, "the layer's is not")

    _press(_active_row(), 40.0)
    assert_null(document.mask_target, "a press on the layer's picture clears it")
    row = _row(_active_row())
    assert_eq(str(row.report()["picked"]), "layer", "the row reports the layer as picked")
    assert_true(row.thumb.picked, "and the layer's rim is the picked one")
    assert_false(row.mask_thumb.picked, "the mask's is not")


## A press on the name keeps the pick on the same layer, and a press on another
## layer's row gives the brush back to paint, because painting one layer's mask
## while another layer is active is a mode nobody asked for.
func test_a_press_elsewhere_keeps_the_pick_only_on_its_own_row() -> void:
    var document := _easel.document
    var mask := document.active_layer.add_mask()
    _docker.sync_layer_list()

    _press(_active_row(), 80.0)
    _press(_active_row(), 200.0)
    assert_eq(document.mask_target, mask, "a press on the name of the same row keeps the mask")

    var other := 1 - _active_row() if _docker.item_list.rows.size() == 2 else 0
    _press(other, 200.0)
    assert_null(document.mask_target, "a press on another row gives the brush back to the paint")


func test_a_row_with_no_mask_draws_no_picked_rim() -> void:
    var row := _row(_active_row())
    assert_eq(str(row.report()["picked"]), "layer", "the active layer is what the brush paints")
    assert_false(row.thumb.picked, "and its rim stays the plain one, so a row with no mask is unchanged")


func test_a_disabled_mask_is_dimmed_and_says_so() -> void:
    var mask := _easel.document.active_layer.add_mask()
    _docker.sync_layer_list()
    var row := _row(_active_row())
    assert_false(row.mask_thumb.is_dimmed(), "an enabled mask is drawn whole")

    mask.enabled = false
    _docker.item_list.refresh_all()
    assert_true(row.mask_thumb.is_dimmed(), "a disabled mask's picture is veiled and crossed out")
    assert_true(bool(row.report()["mask_dimmed"]), "and the report says so")
    assert_true(row.mask_thumb.tooltip_text.contains("switched off"), "and its tooltip says why")


func test_the_banner_names_the_layer_whose_mask_is_under_edit() -> void:
    var document := _easel.document
    var layer := document.active_layer
    var banner := SaQuickMaskBanner.new(_canvas)
    assert_false(banner.is_on(), "no strip while the brush paints colour")

    document.mask_target = layer.add_mask()
    assert_true(banner.is_on(), "the strip while it paints a mask")
    assert_true(banner.message().contains(str(layer.name)), "naming the layer whose mask it is")
    assert_true(banner.message().contains("paint the layer again"), "and the way back")

    document.selection.editing = true
    assert_true(banner.message().begins_with("Quick Mask"), "the quick mask wins, because it is what the brush paints")
    document.selection.editing = false

    document.mask_target = null
    assert_false(banner.is_on(), "and it goes when the brush paints colour again")
    banner.free()
