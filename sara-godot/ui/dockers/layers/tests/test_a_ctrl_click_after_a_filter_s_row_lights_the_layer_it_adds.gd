## A Ctrl click on a layer while a filter's row holds the pick lights the layer
## it adds, and the minus then takes exactly the lit rows.
##
## Without that, after the Ctrl click no row was lit, so the docker showed
## nothing picked and the minus deleted C as `Delete Layer`.
## The Ctrl click hands the pick back from the filter, so the filter's row goes
## dark and the layer set, the target layer and the clicked one, is lit.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

var _easel: SaEasel
var _doc: SaDocument
var _canvas: SaCanvas
var _layers: LayersDocker
var _options: ToolOptionsDocker
var _registry: SaFilterRegistry
var _a: SaLayer
var _b: SaLayer
var _c: SaLayer
var _record: SaAttachedFilter


class Knob:
    extends SaFilter

    var amount: SaSlider

    func title() -> String:
        return "Knob"

    func build(ui: SaDialog) -> void:
        ui.title("Knob")
        ui.preview()
        amount = ui.slider("Amount", 0, 10, 3)
        ui.apply_cancel()

    func parameters() -> Dictionary:
        return {"amount": float(amount.value)} if amount != null else {}

    func set_parameters(values: Dictionary) -> void:
        if amount != null and values.has("amount"):
            amount.value = values["amount"]

    func run(ctx: SaFilterContext) -> void:
        ctx.point_pass("invert", "invert", PackedFloat32Array([0.0, 0.0, 0.0, 0.0]))


func before_each() -> void:
    _easel = Bench.easel(Vector2i(128, 128))
    _doc = _easel.document
    _a = _doc.active_layer
    _registry = _easel.compositor.filter_chain.registry
    var knob := Knob.new()
    _registry.register(knob, Bench.OWNER)
    var key := SaFilterRegistry.key_for(Bench.OWNER, knob)
    _b = SaLayerOps.new(_doc).add()
    _record = SaFilterOps.new(_doc).attach(_b, key, {"amount": 7.0})
    _c = SaLayerOps.new(_doc).add()
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _options = ToolOptionsDocker.new()
    _layers = LayersDocker.new()
    _layers.target_canvas = _canvas
    _layers.filter_registry = _registry
    _layers.tool_options = _options
    _layers.item_list.filter_selected.connect(_layers._on_filter_selected)
    _layers.list_keeper.listen()
    _layers.sync_layer_list()


func after_each() -> void:
    _layers.free()
    _options.free()
    _canvas.free()
    _easel.free()
    _registry = null
    _a = null
    _b = null
    _c = null
    _record = null


func _list() -> SaLayerList:
    return _layers.item_list


func _describe() -> String:
    var parts: Array[String] = []
    for i in _list().rows.size():
        var row: SaRowFrame = _list().rows[i]
        parts.append("%d:%s%s%s" % [i, row.label, "*" if row.lit else "", "+" if row.target else ""])
    return " ".join(parts) + " sel=" + str(_list().picked.selected_indices())


## A real left press on row *idx*, through the handler the row's own
## `gui_input` calls, Ctrl held when *ctrl*.
func _press(idx: int, ctrl: bool = false) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = true
    event.ctrl_pressed = ctrl
    if _list().filter_at(idx) != null:
        _list()._on_filter_row_gui_input(event, idx)
    else:
        _list()._on_row_gui_input(event, idx)


func _row_of(layer: SaLayer) -> int:
    for i in _list().rows.size():
        if _list().layer_at(i) == layer:
            return i
    return -1


func _filter_row() -> int:
    for i in _list().rows.size():
        if _list().filter_at(i) != null:
            return i
    return -1


## The layers whose rows are lit. A lit filter's row counts as no layer.
func _lit_layers() -> Array[SaLayer]:
    var out: Array[SaLayer] = []
    for i in _list().rows.size():
        if _list().rows[i].lit and _list().layer_at(i) != null:
            out.append(_list().layer_at(i))
    return out


func _lit_filter() -> bool:
    for i in _list().rows.size():
        if _list().rows[i].lit and _list().filter_at(i) != null:
            return true
    return false


## The first case: the filter hangs on B while C is the active layer, so
## C is the filter's target, in the set and drawn as the target but not lit.
## The Ctrl click on C would take C out of that set, leaving nothing lit and
## the minus to fall back on the active layer.
func test_a_ctrl_click_on_the_target_layer_lights_it() -> void:
    assert_eq(_doc.active_layer, _c, "C is the active layer before")
    _press(_filter_row())
    assert_eq(_list().picked.selected_record, _record, "the press on the filter's row picked it, %s" % _describe())
    assert_true(_list().rows[_row_of(_c)].target, "and C is drawn as the target, %s" % _describe())
    _press(_row_of(_c), true)
    assert_eq(_lit_layers(), [_c] as Array[SaLayer], "the Ctrl click lit C alone, %s" % _describe())
    assert_false(_lit_filter(), "the filter's row went dark, %s" % _describe())
    assert_null(_list().picked.selected_record, "the pick is back with the layers")
    assert_eq(_doc.active_layer, _c, "and C is active")


## A Ctrl click on a layer outside the set adds it to the target, and both are
## lit, so the target the painter painted under is not dropped unseen.
func test_a_ctrl_click_on_another_layer_lights_it_beside_the_target() -> void:
    _press(_filter_row())
    _press(_row_of(_a), true)
    var lit := _lit_layers()
    assert_eq(lit.size(), 2, "two layers lit, %s" % _describe())
    assert_true(lit.has(_a) and lit.has(_c), "A and C, %s" % _describe())
    assert_false(_lit_filter(), "the filter's row went dark, %s" % _describe())
    assert_eq(_doc.active_layer, _a, "and A, the one clicked, is active")


## Each case then presses the minus, and every lit layer is gone and no other.
func _minus_takes_the_lit_layers(clicked: SaLayer, count: int) -> void:
    _press(_filter_row())
    _press(_row_of(clicked), true)
    var lit := _lit_layers()
    assert_eq(lit.size(), count, "%d lit before the minus, %s" % [count, _describe()])
    var all: Array[SaLayer] = [_a, _b, _c]
    _layers.actions.del_btn.pressed.emit()
    for layer in all:
        var gone := not is_instance_valid(layer) or not _doc.is_ancestor_of(layer)
        assert_eq(gone, lit.has(layer), "%s gone exactly when it was lit" % layer.name)
    assert_eq(_record.key != &"" and _b.filters.has(_record), true, "B keeps its filter")


func test_the_minus_after_a_ctrl_click_on_the_target_deletes_it_alone() -> void:
    _minus_takes_the_lit_layers(_c, 1)


func test_the_minus_after_a_ctrl_click_on_another_layer_deletes_both_lit() -> void:
    _minus_takes_the_lit_layers(_a, 2)
