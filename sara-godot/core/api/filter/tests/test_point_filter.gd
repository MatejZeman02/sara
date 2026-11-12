## A point filter walks the chunks and previews on the canvas.
##
## A filter whose `run` records a pass rather than showing a texture: the
## compositor previews the pass on the active layer at composite time and
## writes nothing, and Apply walks it once over the chunks as one history step,
## through the selection's mask. The fixture is an invert, so a texel read
## says which of the two happened.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const InvertFilter = preload("res://tests/fixtures/modules/point-fixture/invert_filter.gd")

## The fixture's folder, which is the owner the shader index files its kernel
## under, and its id.
const OWNER: StringName = &"point-fixture"
const GREY := Color(0.25, 0.5, 0.75, 1.0)

var _easel: SaEasel = null
var _doc: SaDocument = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document
    _doc.active_layer.fill(GREY)
    _easel.request_full_composite()
    _easel.process_pending_composite()


func after_each() -> void:
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


## A context run the way the dialog runs it, previewing.
func _run() -> SaFilterContext:
    var ctx := SaFilterContext.new(_doc, _doc.active_layer, OWNER, "Invert", true)
    assert_true(SaFilterApply.call_run(InvertFilter.new(), ctx), "The run counts as clean")
    return ctx


func _show(ctx: SaFilterContext) -> void:
    _easel.compositor.point_preview.set_pass(_doc, ctx.point)
    _doc.invalidate_chunks(_doc.active_layer.chunks.keys())
    _composite()


func _hide() -> void:
    _easel.compositor.point_preview.clear(_doc)
    _doc.invalidate_chunks(_doc.active_layer.chunks.keys())
    _composite()


func test_a_point_run_records_a_pass_and_shows_nothing() -> void:
    var steps := _doc.history.step_count()
    var ctx := _run()
    assert_not_null(ctx.point, "The run recorded a pass")
    assert_eq(ctx.point.shader, "point-fixture/invert", "qualified by the module's folder")
    assert_eq(ctx.point.kernel, "invert", "naming the entry point")
    assert_null(ctx.shown, "and showed no texture, so nothing was stitched or allocated")
    assert_eq(_doc.history.step_count(), steps, "and wrote no step")


func test_the_pass_previews_on_the_canvas_and_leaves_the_layer() -> void:
    var steps := _doc.history.step_count()
    _show(_run())
    assert_almost_eq(_output_texel(10, 10).r, 0.75, 0.01, "The canvas shows the invert: %s" % _output_texel(10, 10))
    assert_almost_eq(_output_texel(300, 300).b, 0.25, 0.01, "in every chunk")
    assert_almost_eq(_layer_texel(10, 10).r, 0.25, 1e-5, "while the layer's own texel is what it was")
    assert_almost_eq(_layer_texel(300, 300).b, 0.75, 1e-5, "in every chunk")
    assert_eq(_doc.history.step_count(), steps, "with no history step")

    _hide()
    assert_almost_eq(_output_texel(10, 10).r, 0.25, 0.01, "Dropping the pass shows the layer again")


func test_apply_walks_the_pass_once_under_a_selection_as_one_step() -> void:
    _doc.selection.select_rect(Rect2i(0, 0, 128, 128))
    var ctx := _run()
    _show(ctx)
    assert_almost_eq(_output_texel(64, 64).r, 0.75, 0.01, "The preview inverts inside the selection")
    assert_almost_eq(_output_texel(200, 200).r, 0.25, 0.01, "and not outside it, in the same chunk")
    assert_almost_eq(_layer_texel(64, 64).r, 0.25, 1e-5, "Before Apply the layer is unchanged")
    _hide()

    var steps := _doc.history.step_count()
    assert_true(SaFilterApply.apply(ctx, "Invert"), "Apply writes")
    assert_almost_eq(_layer_texel(64, 64).r, 0.75, 1e-5, "Inside the selection the layer is inverted")
    assert_almost_eq(_layer_texel(64, 64).a, 1.0, 1e-5, "with its alpha kept")
    assert_almost_eq(_layer_texel(200, 200).r, 0.25, 1e-5, "outside it in the same chunk it is not")
    assert_almost_eq(_layer_texel(300, 300).r, 0.25, 1e-5, "nor in a chunk the selection leaves out")
    assert_eq(_doc.history.step_count(), steps + 1, "as one history step")
    assert_true(_doc.undo(), "which undoes")
    assert_almost_eq(_layer_texel(64, 64).r, 0.25, 1e-5, "back to what was there")


func test_apply_commits_what_the_preview_showed() -> void:
    var ctx := _run()
    _show(ctx)
    var previewed := _output_texel(10, 10)
    _hide()
    assert_true(SaFilterApply.apply(ctx, "Invert"), "Apply writes")
    _composite()
    var applied := _output_texel(10, 10)
    assert_almost_eq(applied.r, previewed.r, 1e-3, "The canvas shows what the preview showed")
    assert_almost_eq(applied.b, previewed.b, 1e-3, "channel for channel")


func test_a_locked_layer_is_not_written() -> void:
    var ctx := _run()
    _doc.active_layer.is_locked = true
    var steps := _doc.history.step_count()
    assert_false(SaFilterApply.apply(ctx, "Invert"), "Apply refuses a locked layer")
    assert_almost_eq(_layer_texel(10, 10).r, 0.25, 1e-5, "and leaves it as it was")
    assert_eq(_doc.history.step_count(), steps, "with no step")
