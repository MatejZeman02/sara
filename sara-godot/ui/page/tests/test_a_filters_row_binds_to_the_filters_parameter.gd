## A filter's row binds to the filter's parameter. A filter with one slider and
## no `parameters()` or `set_parameters()` of its own keeps its value in
## `SaFilter.store`: a record round-trips through it, the row's range clamps
## it, the compositor's run with no dialog reads it, and the dialog adds the
## title, both pictures and the two buttons the `build` left out.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const PAINT := Color(0.25, 0.5, 0.75, 1.0)


## One slider and nothing else, the shape the box blur's `build` has now. The
## run inverts, so it is a pass the chain can record under the fixture's
## module, and it notes the strength it read so a suite can see the record's.
class OneRow:
    extends SaFilter

    var seen: float = -1.0

    func title() -> String:
        return "One Row Fixture"

    func build(ui: SaDialog) -> void:
        ui.slider("Strength", 0.0, 2.0, 0.5, {"hard_max": 4.0})

    func run(ctx: SaFilterContext) -> void:
        seen = float(parameter(&"strength"))
        ctx.point_pass("invert", "invert", PackedFloat32Array([0.0, 0.0, 0.0, 0.0]))


## The same slider beside a filter written before the store, whose own
## `parameters()` is what a record keeps.
class HandWritten:
    extends OneRow

    func parameters() -> Dictionary:
        return {"strength": 1.0}


var _easel: SaEasel = null


func after_each() -> void:
    if _easel != null:
        _easel.free()
        _easel = null


func test_a_record_round_trips_through_the_filter() -> void:
    var filter := OneRow.new()
    assert_true(filter.keeps_values(), "A filter with no hand-written parameters keeps its values in the store")
    assert_eq(filter.parameters(), {"strength": 0.5}, "Before any record it answers the row's default")
    filter.set_parameters({"strength": 1.25})
    assert_eq(filter.parameters(), {"strength": 1.25}, "and the value a record handed it")
    assert_eq(filter.parameter(&"strength"), 1.25, "which is the parameter its run reads")
    filter.set_parameters({"unknown": 3})
    assert_eq(filter.parameters(), {"strength": 0.5}, "A record naming no strength reads as the default")


func test_the_rows_range_is_the_clamp() -> void:
    var filter := OneRow.new()
    filter.set_parameters({"strength": 9.0})
    assert_eq(filter.parameter(&"strength"), 4.0, "A value past the hard maximum is held to it")
    filter.set_parameters({"strength": -1.0})
    assert_eq(filter.parameter(&"strength"), 0.0, "and one under the minimum to that")
    filter.write_parameter(&"strength", 7.5)
    assert_eq(filter.parameter(&"strength"), 4.0, "whichever door the number comes through")
    filter.set_parameters({"strength": "much"})
    assert_eq(filter.parameter(&"strength"), 0.5, "and a value that is no number reads as the default")


func test_the_row_is_the_filters_value() -> void:
    var filter := OneRow.new()
    filter.set_parameters({"strength": 1.5})
    var host := VBoxContainer.new()
    var dialog := SaDialog.for_filter(filter)
    dialog.realize(host)
    var row := dialog.row(&"strength")
    assert_eq(row.target, filter.store, "The row is bound to the filter's store")
    assert_eq(float(row.read()), 1.5, "and opens on the value the filter holds")
    row.write(0.75)
    assert_eq(filter.parameter(&"strength"), 0.75, "A row moved by hand is the filter's value at once")
    filter.set_parameters({"strength": 1.75})
    var shown := float((row.custom_control as FactorSlider).value)
    assert_almost_eq(shown, 1.75, 0.0001, "and a record the filter is handed moves the row")
    host.free()


func test_a_filter_written_before_the_store_keeps_its_rows_to_itself() -> void:
    var filter := HandWritten.new()
    assert_false(filter.keeps_values(), "A filter with its own parameters keeps its values itself")
    var dialog := SaDialog.for_filter(filter)
    var host := VBoxContainer.new()
    dialog.realize(host)
    var row := dialog.row(&"strength")
    assert_not_null(row, "The slider is drawn as it was")
    if row != null:
        assert_null(row.target, "and its row binds to nothing")
    assert_eq(filter.parameters(), {"strength": 1.0}, "and its record is what it writes")
    host.free()


func test_an_attached_filter_runs_the_records_value_with_no_dialog() -> void:
    _easel = Bench.easel(Vector2i(SaChunk.SIZE, SaChunk.SIZE))
    var filter := OneRow.new()
    filter.write_parameter(&"strength", 0.25)
    _easel.compositor.filter_chain.registry.register(filter, Bench.OWNER)
    var key := SaFilterRegistry.key_for(Bench.OWNER, filter)
    var layer := _easel.document.active_layer
    layer.get_or_create_chunk(Vector2i.ZERO).clear(PAINT)
    SaFilterOps.new(_easel.document).attach(layer, key, {"strength": 1.5})
    Bench.composite(_easel)
    assert_eq(filter.seen, 1.5, "The compositor's run read the record's strength")
    assert_eq(filter.parameter(&"strength"), 0.25, "and gave back what the filter held before it")
    filter.seen = -1.0
    SaFilterOps.new(_easel.document).attach(layer, key, {"strength": 12.0})
    Bench.composite(_easel)
    assert_eq(filter.seen, 4.0, "A record past the range runs clamped to it")


func test_a_build_with_one_row_gets_the_frame() -> void:
    var dialog := SaDialog.for_filter(OneRow.new())
    var host := VBoxContainer.new()
    dialog.realize(host)
    assert_eq(dialog.dialog_title, "One Row Fixture", "The dialog is titled by the filter's title")
    var names := dialog.rows().map(func(one: SaPageRow) -> String: return dialog.widget_name(one.key))
    assert_eq(
        names,
        ["slider", "canvas_preview", "thumbnail", "apply_cancel"],
        "The row comes first and the buttons last, the switch above the picture"
    )
    assert_not_null(dialog.preview_control, "The thumbnail is drawn")
    assert_not_null(dialog.canvas_box, "and so is the Preview box")
    assert_not_null(dialog.apply_button, "and Apply")
    assert_not_null(dialog.cancel_button, "and Cancel")
    host.free()
