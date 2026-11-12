## Tool Options lets go of a filter's panel when another layer is made active.
##
## A press on a filter's row raised the panel and left the layer set alone, and
## the only things that took the pick back were a press on a layer's row and a
## record that was gone. So the + button, PageDown and an undo made another
## layer active and left the filter's sliders, with their Flatten button, in
## Tool Options over it. The panel is the painter's only while the layer that
## was active when they picked the row stays active, and picking the row again
## puts it back.
##
## The running app's half is `scenarios/tool-options-leaves-a-filter-s-panel-when-another-layer-is-made-active.json`.
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
var _record: SaAttachedFilter


## A filter with one number, which is all a panel needs to be one. It runs the
## fixture's invert kernel, so the compositor the bench built draws it when a
## step redraws the stack.
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
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _options = ToolOptionsDocker.new()
    _layers = LayersDocker.new()
    _layers.target_canvas = _canvas
    _layers.filter_registry = _registry
    _layers.tool_options = _options
    # Neither docker is in a tree, so `_ready` never ran and the pick is wired
    # by hand, the way the suites of the filter panel wire it.
    _layers.item_list.filter_selected.connect(_layers._on_filter_selected)
    _layers.sync_layer_list()


func after_each() -> void:
    _layers.free()
    _options.free()
    _canvas.free()
    _easel.free()
    _registry = null
    _first = null
    _record = null


func _panel() -> SaFilterPanel:
    return _options._filter_panel as SaFilterPanel


## Whether Tool Options shows the filter's sliders and their Flatten button
## rather than the tool's own rows.
func _shows_the_filter() -> bool:
    var panel := _panel()
    return panel != null and panel.find_child("FlattenButton", true, false) != null and not _options._rows_box.visible


## Whether Tool Options shows the tool's own rows, which is what it does with
## no filter picked.
func _shows_the_tool() -> bool:
    return _panel() == null and _options._rows_box.visible


func _pick_the_filter() -> void:
    _layers.item_list.picked.pick_filter(_record)


func test_picking_the_filter_row_raises_the_panel_and_keeps_it() -> void:
    assert_true(_shows_the_tool(), "Nothing is picked, so Tool Options shows the tool")
    _pick_the_filter()
    assert_true(_shows_the_filter(), "The pick shows the filter's sliders and Flatten")
    _layers.sync_layer_list()
    _layers._on_document_changed()
    assert_true(_shows_the_filter(), "and a rebuild of the list with the same layer active leaves them")
    assert_eq(_layers.item_list.picked.selected_record, _record, "the record is still the picked one")


func test_the_plus_button_takes_the_panel_away_and_picking_the_row_brings_it_back() -> void:
    _pick_the_filter()
    assert_true(_shows_the_filter(), "The panel is up over the first layer")
    var steps := _doc.history.step_count()
    _layers.actions.add_btn.pressed.emit()
    assert_true(_doc.active_layer != _first, "The + button made a new layer active")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step")
    assert_true(_shows_the_tool(), "Tool Options shows the tool and no Flatten button")
    assert_null(_layers.item_list.picked.selected_record, "and the list holds no picked filter")
    _pick_the_filter()
    assert_true(_shows_the_filter(), "Picking the filter's row again brings the panel back")
    assert_eq(_panel().record, _record, "for the same record")


func test_a_layer_made_active_by_a_key_takes_the_panel_away() -> void:
    var second := SaLayerOps.new(_doc).add()
    _doc.set_active_layer(_first)
    _layers.sync_layer_list()
    _pick_the_filter()
    assert_true(_shows_the_filter(), "The panel is up over the first layer")
    _doc.set_active_layer(second)
    assert_true(_shows_the_tool(), "PageDown, which sets the active layer, takes the panel away")
    assert_true(_first.filters.has(_record), "and the filter itself is left on its layer")
    _pick_the_filter()
    assert_true(_shows_the_filter(), "Picking the row again puts the panel back over the other layer")
    _doc.set_active_layer(_first)
    assert_true(_shows_the_tool(), "and going back to the first layer takes it away again, as the rule is the same")


func test_an_undo_that_changes_the_active_layer_takes_the_panel_away() -> void:
    SaLayerOps.new(_doc).add()
    _layers.sync_layer_list()
    assert_true(_doc.active_layer != _first, "The added layer is the active one")
    _pick_the_filter()
    assert_true(_shows_the_filter(), "The panel is up while the added layer is active")
    assert_true(_doc.undo(), "Ctrl+Z takes the added layer away")
    assert_eq(_doc.active_layer, _first, "and the first layer is active again")
    assert_true(_shows_the_tool(), "Tool Options shows the tool and no Flatten button")
    assert_null(_layers.item_list.picked.selected_record, "and the list holds no picked filter")
    assert_true(_doc.redo(), "The redo puts the layer back")
    assert_true(_shows_the_tool(), "and Tool Options keeps showing the tool")
    _pick_the_filter()
    assert_true(_shows_the_filter(), "Picking the row again brings the panel back")


func test_a_filter_on_the_root_keeps_its_panel_while_its_layer_stays_active() -> void:
    var root_record := SaFilterOps.new(_doc).attach(null, _knob, {"amount": 2.0})
    _layers.sync_layer_list()
    _layers.item_list.picked.pick_filter(root_record)
    assert_not_null(_panel(), "A global filter's panel is up")
    _layers.sync_layer_list()
    assert_not_null(_panel(), "and a rebuild with the same layer active leaves it")
    _doc.set_active_layer(SaLayerOps.new(_doc).add())
    assert_true(_shows_the_tool(), "A new active layer takes it away, the root's panel included")


## The route the ask walks: the Layer way makes an adjustment layer that holds
## the record, its row is picked and then a plain layer is added over it.
func test_a_new_layer_over_an_adjustment_layer_takes_its_panel_away() -> void:
    var types := Fixtures.make_registries().layer_types
    var adjustment := SaFilterConversion.new(_doc).add_holding(_knob, {"amount": 4.0}, types, "Knob")
    assert_not_null(adjustment, "The Layer way made an adjustment layer")
    assert_eq(_doc.active_layer, adjustment, "and it is the active one")
    _layers.sync_layer_list()
    _layers.item_list.picked.pick_filter(adjustment.filters[0])
    assert_true(_shows_the_filter(), "Its row shows the sliders and Flatten")
    _layers.actions.add_btn.pressed.emit()
    assert_true(_doc.active_layer != adjustment, "The + button made a new layer active")
    assert_true(_shows_the_tool(), "and Tool Options shows the tool again")
    _layers.item_list.picked.pick_filter(adjustment.filters[0])
    assert_true(_shows_the_filter(), "Picking the adjustment layer's row brings the panel back")
