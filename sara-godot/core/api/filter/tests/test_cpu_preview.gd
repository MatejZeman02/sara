## A CPU filter's run is a preview, and Apply is still the only writer.
##
## The defect this closes: a filter whose `run` reads, changes and
## writes, run three times against one context, left three undo steps and the
## layer changed three times. In a dialog that meant opening a CPU filter wrote
## the layer before the painter had touched anything, every slider frame wrote
## it again, and Cancel undid none of it.
##
## So the suite reads both halves. A context that is previewing shows and does
## not write, however many times it is run, and Apply then lands exactly one
## step. A context that is not previewing, which is a script or a suite calling
## `write_pixels` directly, writes on the spot the way it was built.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const CpuFilter = preload("res://tests/fixtures/modules/cpu-filter-fixture/cpu_filter.gd")
const SaExportScript = preload("res://core/export/sa_export.gd")

const PAINTED := Vector2i(0, 0)
const GREY := Color(0.25, 0.25, 0.25, 1.0)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null
var _filter: CpuFilter = null
var _host: VBoxContainer = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document
    _layer = _doc.active_layer
    _layer.get_or_create_chunk(PAINTED).clear(GREY)
    _doc.selection.select_rect(Rect2i(16, 16, 32, 32))
    _filter = CpuFilter.new()
    _host = VBoxContainer.new()
    var dialog := SaDialog.new()
    _filter.build(dialog)
    dialog.realize(_host)


func after_each() -> void:
    _host.free()
    _host = null
    _filter = null
    _easel.free()
    _easel = null
    _doc = null
    _layer = null


func _layer_texel(x: int, y: int) -> Color:
    var texture := _layer.get_field(PAINTED)
    if texture == null:
        return Color.TRANSPARENT
    return SaExportScript.get_texture_image_float(texture).get_pixel(x, y)


func _steps_in_history() -> int:
    var counted := 0
    while _doc.undo_redo.has_undo() and counted < 1000:
        _doc.undo_redo.undo()
        counted += 1
    return counted


func test_a_preview_run_writes_nothing_however_many_times_it_runs() -> void:
    var ctx := SaFilterContext.new(_doc, _layer, &"", _filter.title(), true)
    for _i in 3:
        _filter.run(ctx)
    assert_eq(_filter.runs, 3, "the filter ran three times")
    assert_false(_doc.undo_redo.has_undo(), "and left no undo step at all")
    assert_almost_eq(_layer_texel(24, 24).r, GREY.r, 0.002, "with the layer as it was")
    assert_not_null(ctx.shown, "what it did leave is a result in the preview")


func test_apply_after_a_preview_lands_one_step() -> void:
    var ctx := SaFilterContext.new(_doc, _layer, &"", _filter.title(), true)
    _filter.run(ctx)
    _filter.run(ctx)
    assert_true(SaFilterApply.apply(ctx, _filter.title()), "apply wrote")
    assert_almost_eq(_layer_texel(24, 24).r, 1.0 - GREY.r, 0.01, "the layer holds the effect once")
    assert_eq(_doc.undo_redo.get_current_action_name(), _filter.title(), "named after the filter")
    assert_eq(_steps_in_history(), 1, "and two runs and an apply are one undo step")
    assert_almost_eq(_layer_texel(24, 24).r, GREY.r, 0.002, "which undoes back to what was there")


func test_cancelling_a_preview_leaves_the_layer_alone() -> void:
    var ctx := SaFilterContext.new(_doc, _layer, &"", _filter.title(), true)
    _filter.run(ctx)
    ctx = null
    assert_false(_doc.undo_redo.has_undo(), "dropping the context is the whole of cancel")
    assert_almost_eq(_layer_texel(24, 24).r, GREY.r, 0.002, "and nothing was ever written")


func test_a_write_outside_a_dialog_still_writes_on_the_spot() -> void:
    var ctx := SaFilterContext.new(_doc, _layer, &"", _filter.title())
    _filter.run(ctx)
    assert_true(_doc.undo_redo.has_undo(), "a context that is not previewing writes directly")
    assert_almost_eq(_layer_texel(24, 24).r, 1.0 - GREY.r, 0.01, "and the layer holds the effect")
    assert_eq(_steps_in_history(), 1, "as one step")


func test_the_preview_holds_what_the_run_produced() -> void:
    var ctx := SaFilterContext.new(_doc, _layer, &"", _filter.title(), true)
    _filter.run(ctx)
    assert_eq(ctx.shown_rect, ctx.rect, "the shown rectangle is the run's")
    var texel := SaExportScript.get_texture_image_float(ctx.shown).get_pixel(8, 8)
    assert_almost_eq(texel.r, 1.0 - GREY.r, 0.01, "and the texture is the inverted picture")
