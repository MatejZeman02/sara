## An attached filter comes off its layer from the Layers docker, by the minus
## under the list and by the More menu's Delete Filter row, and the layer and
## its pixels stay.
##
## The fixture is an invert, so a texel of the composite says whether the
## filter still runs: the paint's colour with it gone, its inverse with it on.
## The running app's half is `scenarios/an-attached-filter-can-be-taken-off.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const PAINT := Color(0.25, 0.5, 0.75, 1.0)
const INVERTED := Color(0.75, 0.5, 0.25, 1.0)
const AT := Vector2i(40, 40)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _background: SaLayer = null
var _record: SaAttachedFilter = null
var _canvas: SaCanvas = null
var _docker: LayersDocker = null


func before_each() -> void:
    _easel = Bench.easel(Vector2i(256, 256))
    _doc = _easel.document
    _background = _doc.get_node("Background") as SaLayer
    _doc.fill_layer(PAINT, _background)
    _record = SaFilterOps.new(_doc).attach(_background, Bench.INVERT)
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _docker = LayersDocker.new()
    _docker.target_canvas = _canvas
    _docker.sync_layer_list()


func after_each() -> void:
    _docker.free()
    _canvas.free()
    _easel.free()
    _docker = null
    _canvas = null
    _easel = null
    _doc = null
    _background = null
    _record = null


func _layers() -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for child in _doc.get_children():
        if child is SaLayer:
            found.append(child as SaLayer)
    return found


func _seen() -> Color:
    Bench.composite(_easel)
    return Bench.texel(_easel.output, AT)


func _close(a: Color, b: Color) -> bool:
    return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01


## The layers, the step count and the picture before a delete, and the checks
## every way of taking the filter off has to pass afterwards.
func _assert_taken_off(layers_before: Array[SaLayer], steps_before: int, how: String) -> void:
    assert_false(_background.filters.has(_record), "%s takes the filter off" % how)
    assert_eq(_layers(), layers_before, "%s leaves every layer where it was" % how)
    assert_true(is_instance_valid(_background) and _background.get_parent() == _doc, "and the layer itself")
    assert_true(_close(_seen(), PAINT), "%s leaves the layer's own paint showing" % how)
    assert_eq(_doc.history.step_count(), steps_before + 1, "%s is one step" % how)
    assert_eq(_doc.undo_redo.get_current_action_name(), "Detach Filter", "named Detach Filter, not Delete Layer")
    assert_null(_docker.item_list.picked.selected_record, "The list lets go of the record it no longer shows")

    assert_true(_doc.undo(), "The step undoes")
    assert_true(_background.filters.has(_record), "and the same record is back on its layer")
    assert_true(_close(_seen(), INVERTED), "running again")


func test_the_minus_over_a_picked_filter_takes_the_filter_off_and_keeps_the_layer() -> void:
    assert_true(_close(_seen(), INVERTED), "The invert runs before anything is deleted")
    var minus := _docker.actions.del_btn
    assert_eq(minus.tooltip_text, "Delete the layer", "With a layer's row picked the minus says it deletes the layer")
    _docker.item_list.picked.pick_filter(_record)
    assert_eq(minus.tooltip_text, "Delete the filter, and keep its layer", "and with a filter's row picked, the filter")

    var layers := _layers()
    var steps := _doc.history.step_count()
    minus.pressed.emit()
    _assert_taken_off(layers, steps, "The minus")


func test_the_more_menus_delete_filter_row_takes_the_filter_off() -> void:
    var actions := _docker.actions
    _docker.item_list.picked.pick_filter(_record)
    actions.sync_from_active_layer()
    assert_eq(actions.menu_titles()[0], "Delete Filter", "The first row over a picked filter is Delete Filter")
    assert_false(actions.menu.is_disabled(actions.FILTER_DELETE), "and it is live")

    var layers := _layers()
    var steps := _doc.history.step_count()
    assert_true(actions.menu.press_row(actions.FILTER_DELETE), "The row presses")
    _assert_taken_off(layers, steps, "Delete Filter")


func test_a_filter_on_the_root_comes_off_the_root() -> void:
    var root_record := SaFilterOps.new(_doc).attach(null, Bench.INVERT)
    _docker.sync_layer_list()
    _docker.item_list.picked.pick_filter(root_record)
    var layers := _layers()
    assert_true(_docker.actions.delete_filter(), "A global filter comes off")
    assert_false(_doc.root_filters.has(root_record), "the document's root no longer holds it")
    assert_true(_background.filters.has(_record), "and the layer's own filter is left alone")
    assert_eq(_layers(), layers, "with every layer kept")


func test_the_minus_over_a_layers_row_still_deletes_the_layer() -> void:
    SaLayerOps.new(_doc).add()
    _docker.sync_layer_list()
    var count := _layers().size()
    _docker.actions.del_btn.pressed.emit()
    assert_eq(_layers().size(), count - 1, "With no filter picked the minus deletes the layer, as it always did")
    assert_eq(_docker.actions.del_btn.tooltip_text, "Delete the layer", "and says so")
