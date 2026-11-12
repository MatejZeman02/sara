## The adjustments preview at composite time and cost no history step.
##
## Before this, every look at a slider was a rewrite of the layer and one
## undo entry, so a drag spent the history budget and the dialog offered no
## preview at all. What this suite holds is the split: the preview changes
## the canvas and nothing else, and Apply then commits exactly what was
## previewed, as one step.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice.
const REQUIRES_GPU := true

var _easel: SaEasel = null
var _doc: SaDocument = null
var _engine: SaPointAdjust = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document
    _engine = SaPointAdjust.new()


func after_each() -> void:
    _engine = null
    _easel.free()
    _easel = null
    _doc = null


func _composite() -> void:
    _easel.request_composite()
    _easel.process_pending_composite()


func _output_texel(x: int, y: int) -> Color:
    var texture := _easel.output
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, y * texture.size.x + x)


func _layer_texel(x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var texture := _doc.active_layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(
        bytes, texture.format, (y - grid.y * SaChunk.SIZE) * texture.size.x + (x - grid.x * SaChunk.SIZE)
    )


func _show_preview(kind: StringName, values: Dictionary) -> void:
    _easel.compositor.point_preview.set_pass(_doc, _engine.record(kind, values, _doc.color_space))
    _doc.invalidate_chunks(_doc.active_layer.chunks.keys())
    _composite()


func _hide_preview() -> void:
    _easel.compositor.point_preview.clear(_doc)
    _doc.invalidate_chunks(_doc.active_layer.chunks.keys())
    _composite()


func test_a_preview_changes_the_canvas_and_neither_the_layer_nor_the_history() -> void:
    _doc.active_layer.fill(Color(0.5, 0.5, 0.5, 1.0))
    _easel.request_full_composite()
    _easel.process_pending_composite()
    assert_almost_eq(_output_texel(10, 10).r, 0.5, 0.01, "The canvas shows the grey")
    var steps := _doc.history.step_count()

    _show_preview(SaPointAdjust.HUE_SATURATION_LIGHTNESS, {"lightness": 0.2})
    assert_true(_output_texel(10, 10).r > 0.6, "The preview lifts what the canvas shows: %s" % _output_texel(10, 10))
    assert_almost_eq(_layer_texel(10, 10).r, 0.5, 1e-5, "and the layer's own pixels are untouched")
    assert_eq(_doc.history.step_count(), steps, "with no history step")

    _hide_preview()
    assert_almost_eq(_output_texel(10, 10).r, 0.5, 0.01, "Dropping the preview shows the layer again")
    assert_eq(_doc.history.step_count(), steps, "still with no step")


func test_apply_commits_what_was_previewed_as_one_step() -> void:
    _doc.active_layer.fill(Color(0.25, 0.5, 0.75, 1.0))
    _easel.request_full_composite()
    _easel.process_pending_composite()
    var values := {"brightness": 0.1, "contrast": 1.0}
    var steps := _doc.history.step_count()

    _show_preview(SaPointAdjust.BRIGHTNESS_CONTRAST, values)
    var previewed := _output_texel(10, 10)
    assert_almost_eq(previewed.r, 0.35, 0.01, "The preview shows the brightness")

    _hide_preview()
    var kind := SaPointAdjust.BRIGHTNESS_CONTRAST
    assert_true(_engine.apply(_doc, _doc.active_layer, kind, values, "Brightness/Contrast"), "Apply runs")
    _composite()
    var applied := _output_texel(10, 10)
    assert_almost_eq(applied.r, previewed.r, 1e-3, "and the canvas shows what the preview showed")
    assert_almost_eq(applied.b, previewed.b, 1e-3, "channel for channel")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step")


## One compositor serves more than one easel, so a preview on one document
## must not show on another.
func test_a_preview_is_the_document_s_own() -> void:
    var other := SaEasel.create_default(Vector2i(256, 256), _easel.compositor)
    var previews := _easel.compositor.point_preview
    assert_null(previews.for_document(other.document), "Nothing previewed on the other")
    previews.set_pass(_doc, _engine.record(SaPointAdjust.HUE_SATURATION_LIGHTNESS, {"hue": 90.0}, _doc.color_space))
    assert_not_null(previews.for_document(_doc), "This one has its preview")
    assert_null(previews.for_document(other.document), "and the other still has none")
    other.free()


func test_the_pass_and_the_preview_read_the_same_parameters() -> void:
    var params := SaPointAdjust.params_for(SaPointAdjust.HUE_SATURATION_LIGHTNESS, {"hue": 180.0, "saturation": 0.5})
    assert_almost_eq(params[2], PI, 1e-6, "Hue in degrees becomes radians")
    assert_almost_eq(params[3], 0.5, 1e-6, "saturation is the factor")
    assert_almost_eq(params[4], 0.0, 1e-6, "and a missing lightness is no change")
    var recorded := _engine.record(SaPointAdjust.HUE_SATURATION_LIGHTNESS, {"hue": 180.0, "saturation": 0.5}, SaColorSpace.srgb())
    var push := recorded.push_for(Vector2i(16, 24))
    assert_eq(push.size(), 32, "128 bytes, the Vulkan guarantee")
    assert_almost_eq(push[5], 16.0, 1e-6, "with the region's origin after the parameters")
    assert_almost_eq(push[6], 24.0, 1e-6, "both axes")


## The filter's dialog realized into a detached host, the way the filter window
## realizes it into its own. The caller frees the host.
func _built(filter: SaAdjustFilter) -> Dictionary:
    var dialog := SaDialog.new()
    var host := VBoxContainer.new()
    filter.build(dialog)
    dialog.realize(host)
    return {"dialog": dialog, "host": host}


func test_a_slider_move_asks_for_one_run_and_the_run_reads_it() -> void:
    var filter := SaHueSaturationLightnessFilter.new()
    var built := _built(filter)
    var dialog: SaDialog = built["dialog"]
    var reruns: Array = []
    dialog.rerun.connect(func() -> void: reruns.append(filter.values()))

    filter.capture_set({"hue": 90.0})
    assert_true(dialog.rerun_pending, "A slider move asks for a run")
    dialog.flush_rerun()
    assert_eq(reruns.size(), 1, "which the frame's end makes once")
    assert_almost_eq(float(reruns[0]["hue"]), 90.0, 1e-6, "with the hue in degrees")

    filter.capture_set({"hue": 45.0, "lightness": 10.0})
    dialog.flush_rerun()
    assert_eq(reruns.size(), 2, "Two sliders moved together are one run more")
    assert_almost_eq(float(reruns[1]["hue"]), 45.0, 1e-6, "with the sliders as they are now")
    assert_almost_eq(float(reruns[1]["lightness"]), 0.1, 1e-6, "in the units the pass takes")
    (built["host"] as Node).free()


## The Preview box, Cancel and Apply are the filter window's, and
## `core/api/filter/tests/test_point_filter.gd` holds them for every point filter. What is
## this filter's own is that its run records the pass the window hands on.
func test_a_run_records_the_pass_the_window_previews_and_applies() -> void:
    _doc.active_layer.fill(Color(0.5, 0.5, 0.5, 1.0))
    var filter := SaBrightnessContrastFilter.new()
    var ctx := SaFilterContext.new(_doc, _doc.active_layer, &"", filter.title(), true)
    filter.run(ctx)
    assert_eq(ctx.point.kernel if ctx.point != null else "", "brightness_contrast", "A run records its kernel and shows nothing")


func test_the_gradients_are_oklab_ramps() -> void:
    var filter := SaHueSaturationLightnessFilter.new()
    var lightness: PackedColorArray = filter.gradient_for("lightness")
    assert_eq(lightness.size(), SaAdjustFilter.GRADIENT_STOPS, "Sampled evenly")
    assert_true(lightness[0].r < 0.05, "Lightness starts black")
    assert_true(lightness[lightness.size() - 1].r > 0.95, "and ends white")
    var hue: PackedColorArray = filter.gradient_for("hue")
    var first := hue[0]
    var last := hue[hue.size() - 1]
    assert_true(first.is_equal_approx(last), "The hue ramp is a full turn, so its ends meet")
    var middle := hue[int(hue.size() / 2.0)]
    assert_false(middle.is_equal_approx(first), "and its middle is the opposite hue")


func test_a_preview_honours_the_selection() -> void:
    _doc.active_layer.fill(Color(0.5, 0.5, 0.5, 1.0))
    _doc.selection.select_rect(Rect2i(0, 0, 128, 128))
    _easel.request_full_composite()
    _easel.process_pending_composite()

    _show_preview(SaPointAdjust.BRIGHTNESS_CONTRAST, {"brightness": 0.2, "contrast": 1.0})
    assert_almost_eq(_output_texel(64, 64).r, 0.7, 0.01, "Inside the selection the preview shows")
    assert_almost_eq(_output_texel(200, 64).r, 0.5, 0.01, "outside it, in the same chunk, nothing changes")
    assert_almost_eq(_output_texel(300, 300).r, 0.5, 0.01, "nor in a chunk the selection leaves out")
