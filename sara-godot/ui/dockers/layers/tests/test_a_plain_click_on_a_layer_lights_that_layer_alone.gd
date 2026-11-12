## A plain click on a layer lights that layer alone, and a filter's panel lights
## the filter's row with its layer drawn as the target.
##
## Sometimes an effect or group and a layer were selected together though no
## shift was used to select multiple. Every gesture a painter makes between
## plain clicks was made here, and one left two rows lit: a press on a filter's
## row, which picks the record and leaves the layer set as it was, so the
## filter's row and the active layer's row wore one look. Adding, duplicating,
## grouping, deleting, undoing each and dragging a row each left one.
##
## The running app's half is `scenarios/a-plain-click-on-a-layer-lights-that-layer-alone.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

var _easel: SaEasel
var _doc: SaDocument
var _canvas: SaCanvas
var _layers: LayersDocker
var _options: ToolOptionsDocker
var _registry: SaFilterRegistry
var _knob: StringName = &""
var _first: SaLayer
var _second: SaLayer
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
    _first = _doc.active_layer
    _registry = _easel.compositor.filter_chain.registry
    var knob := Knob.new()
    _registry.register(knob, Bench.OWNER)
    _knob = SaFilterRegistry.key_for(Bench.OWNER, knob)
    _record = SaFilterOps.new(_doc).attach(_first, _knob, {"amount": 7.0})
    _second = SaLayerOps.new(_doc).add()
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
    _first = null
    _second = null
    _record = null


func _list() -> SaLayerList:
    return _layers.item_list


func _lit() -> Array[int]:
    var out: Array[int] = []
    for i in _list().rows.size():
        if _list().rows[i].lit:
            out.append(i)
    return out


func _describe() -> String:
    var parts: Array[String] = []
    for i in _list().rows.size():
        var row: SaRowFrame = _list().rows[i]
        parts.append("%d:%s%s" % [i, row.label, "*" if row.lit else ""])
    return " ".join(parts) + " sel=" + str(_list().picked.selected_indices())


func _press(idx: int) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = true
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


func _targets() -> Array[int]:
    var out: Array[int] = []
    for i in _list().rows.size():
        if _list().rows[i].target:
            out.append(i)
    return out


## After *gesture*, a plain click on the first layer leaves its row alone lit
## and alone in the set.
func _one_after(gesture: String) -> void:
    _press(_row_of(_first))
    var row := _row_of(_first)
    assert_eq(_lit(), [row], "%s, then a plain click: one lit row, %s" % [gesture, _describe()])
    assert_eq(_list().picked.selected_indices(), [row], "%s, then a plain click: one layer picked" % gesture)
    assert_eq(_targets(), [], "%s, then a plain click: no target row" % gesture)


func test_each_gesture_then_a_plain_click_lights_one_row() -> void:
    _press(_filter_row())
    _one_after("opening a filter's panel")
    _press(_filter_row())
    _press(_filter_row())
    _one_after("pressing the filter's row twice")
    _layers.actions.add_btn.pressed.emit()
    _one_after("adding a layer")
    assert_true(_doc.undo(), "the add is undone")
    _one_after("undoing the add")
    _layers.actions.duplicate_layer()
    _one_after("duplicating")
    assert_true(_doc.undo(), "the duplicate is undone")
    _one_after("undoing the duplicate")
    _layers.actions.toggle_group()
    _one_after("grouping")
    assert_true(_doc.undo(), "the group is undone")
    _one_after("undoing the group")
    _press(_row_of(_second))
    _layers.actions.delete_layer()
    _one_after("deleting a layer")
    assert_true(_doc.undo(), "the delete is undone")
    _one_after("undoing the delete")
    _press(_row_of(_second))
    _list()._arm_drag(_row_of(_second), Vector2.ZERO)
    _list().dragging = true
    _list().drag_over(_row_of(_doc.get_child(0) as SaLayer), SaLayerList.Drop.BELOW)
    var before := _second.get_index()
    _list().drop()
    assert_true(_second.get_index() != before, "the drag moved the layer")
    _one_after("dragging a row")
    assert_true(_doc.undo(), "the drag is undone")
    _one_after("undoing the drag")


## The press on a filter's row lights that row, and the layer the painter keeps
## painting under is the target and not lit.
func test_a_filters_panel_lights_its_row_and_draws_its_layer_as_the_target() -> void:
    var active := _row_of(_second)
    assert_eq(_lit(), [active], "the active layer is lit before")
    var filter := _filter_row()
    _press(filter)
    assert_eq(_list().picked.selected_record, _record, "the press picked the record")
    assert_eq(_lit(), [filter], "only the filter's row is lit, %s" % _describe())
    assert_eq(_targets(), [active], "and the active layer is the target")
    assert_eq(_list().picked.selected_indices(), [active], "the layer set is still the active layer")
    var report: Array = _list().row_report()
    assert_true(bool(report[filter]["selected"]), "the dump reads the filter's row picked")
    assert_false(bool(report[active]["selected"]), "and the layer's row not picked")
    assert_true(bool(report[active]["target"]), "but the target")
    _press(active)
    assert_null(_list().picked.selected_record, "a press on the layer takes the pick back")
    assert_eq(_lit(), [active], "and its row is lit again")
    assert_eq(_targets(), [], "with no target")
