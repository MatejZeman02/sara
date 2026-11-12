## A picked filter's widgets open in the tool options docker and write the
## record, as an Edit Filter step.
##
## No filter in the tree implements `SaFilter.parameters`, so the suite
## brings one of its own, a slider and the two rows every filter declares, and
## registers it the way a module does.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const KNOB := &"b4_suite.knob"

var _easel: SaEasel
var _doc: SaDocument
var _canvas: SaCanvas
var _layers: LayersDocker
var _options: ToolOptionsDocker
var _registry: SaFilterRegistry
var _record: SaAttachedFilter


## A filter with one number, which is all the contract needs.
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
        return {"amount": float(amount.value)}

    func set_parameters(values: Dictionary) -> void:
        if values.has("amount"):
            amount.value = values["amount"]

    func run(_ctx: SaFilterContext) -> void:
        pass


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(128, 128))
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _doc = _easel.document
    _registry = SaFilterRegistry.new()
    _registry.register(Knob.new(), &"b4_suite")
    _record = SaFilterOps.new(_doc).attach(_doc.active_layer, KNOB, {"amount": 7.0})
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _options = ToolOptionsDocker.new()
    _layers = LayersDocker.new()
    _layers.target_canvas = _canvas
    _layers.filter_registry = _registry
    _layers.tool_options = _options
    # Neither docker is in a tree, so `_ready` never ran and the pick is wired
    # by hand, the way `test_layer_drag.gd` wires a drop.
    _layers.item_list.filter_selected.connect(_layers._on_filter_selected)
    _layers.sync_layer_list()


func after_each() -> void:
    _layers.free()
    _options.free()
    _canvas.free()
    _easel.free()
    _registry = null


func _row_of(record: SaAttachedFilter) -> int:
    for i: int in _layers.item_list.row_count():
        if _layers.item_list.record_at(i) == record:
            return i
    return -1


func _panel() -> SaFilterPanel:
    return _options._filter_panel as SaFilterPanel


func test_the_row_is_titled_by_the_filter() -> void:
    var report: Array = _layers.item_list.row_report()
    assert_eq(report[_row_of(_record)]["title"], "Knob", "The row carries the filter's own title")
    SaFilterOps.new(_doc).attach(_doc.active_layer, &"nobody.gone")
    report = _layers.item_list.row_report()
    assert_eq(report[_row_of(_doc.active_layer.filters[1])]["title"], "nobody.gone", "and the key when no module answers to it")


func test_a_picked_record_opens_its_panel_with_the_records_values() -> void:
    assert_null(_panel(), "Nothing is shown until a filter is picked")
    _layers.item_list.picked.pick_filter(_record)
    var panel := _panel()
    assert_not_null(panel, "A picked record's panel is in the tool options docker")
    assert_eq(panel.record, _record, "and it is that record's")
    assert_false(_options._rows_box.visible, "The tool's own rows are hidden while it is shown")
    assert_true(_layers.item_list.row_report()[_row_of(_record)]["selected"], "and the filter's row is marked")
    assert_eq(panel.dialog.row(&"amount").read(), 7.0, "The widget is drawn from what the record keeps")
    assert_eq(_record.revision, 0, "and opening the panel announced no change")
    for declared: SaPageRow in panel.dialog.rows():
        if SaFilterPanel.LEFT_OUT.has(panel.dialog.widget_name(declared.key)):
            assert_false(declared.line.visible, "The %s row is left out" % panel.dialog.widget_name(declared.key))


func test_a_moved_widget_writes_the_record_as_one_step() -> void:
    _layers.item_list.picked.pick_filter(_record)
    var panel := _panel()
    var steps := _doc.undo_redo.get_history_count()
    var revision := _record.revision
    panel.dialog.row(&"amount").drive(2.0)
    panel.dialog.flush_rerun()
    assert_eq(_record.parameters, {"amount": 2.0}, "The record's parameters are the widget's")
    assert_true(_record.revision > revision, "and its revision moved, which is what redraws the canvas")
    assert_true(_doc.modified, "The document is modified")
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "and the history has one step for it")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Edit Filter", "named the way the edit window's Apply names it")
    assert_eq(panel.writes, 1, "One settled change is one write")

    panel.dialog.request_rerun()
    panel.dialog.flush_rerun()
    assert_eq(panel.writes, 1, "A rerun that changed nothing writes nothing")


func test_a_layer_row_and_a_detach_clear_the_panel() -> void:
    _layers.item_list.picked.pick_filter(_record)
    _layers.item_list.picked.pick_filter(null)
    assert_null(_panel(), "A layer's row takes the pick back and the panel goes")
    assert_true(_options._rows_box.visible, "and the tool has its rows again")

    _layers.item_list.picked.pick_filter(_record)
    var second := SaFilterOps.new(_doc).attach(_doc.active_layer, KNOB, {"amount": 1.0})
    _layers.item_list.picked.pick_filter(second)
    assert_eq(_panel().record, second, "One record at a time: the second pick replaces the first panel")
    assert_eq(_panel().dialog.row(&"amount").read(), 1.0, "with its own values")
    _doc.undo()
    assert_null(_panel(), "A picked record that an undo detached takes its panel with it")
    assert_null(_layers.item_list.picked.selected_record, "and the pick")


func test_a_record_nobody_provides_says_so() -> void:
    var orphan := SaFilterOps.new(_doc).attach(_doc.active_layer, &"nobody.gone")
    _layers.item_list.picked.pick_filter(orphan)
    assert_not_null(_panel(), "A record of a missing module still opens a panel")
    assert_null(_panel().dialog, "with no widgets")
    assert_false(_panel().describe()["provided"], "and the dump says nobody provides it")
