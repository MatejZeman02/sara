## Apply under a selection: a filter writes through the mask
## rather than only over the run's rectangle.
##
## Every assertion reads the layer back through `SaExport`, the same door
## `test_filter_apply.gd` reads through, because a chunk written at the wrong
## offset is a plausible picture and not an error.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const SaExportScript = preload("res://core/export/sa_export.gd")

const RED := Color(1.0, 0.0, 0.0, 1.0)
const GREEN := Color(0.0, 1.0, 0.0, 1.0)

## An ellipse well inside chunk (1, 1) of a 1024 by 1024 canvas, so the
## feathered edge never reaches a chunk seam.
const ELLIPSE_RECT := Rect2i(300, 300, 100, 100)
const FEATHER_RADIUS := 12

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(1024, 1024))
    _doc = _easel.document
    _layer = _doc.active_layer
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 1), Vector2i(2, 2), Vector2i(1, 2), Vector2i(2, 1)]:
        _layer.get_or_create_chunk(grid_pos).clear(RED)


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _layer = null


func _texel(texture: SaTexture, x: int, y: int) -> Color:
    var image := SaExportScript.get_texture_image_float(texture)
    return image.get_pixel(x, y)


## One texel of the layer, in document coordinates.
func _layer_texel(x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var texture := _layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    return _texel(texture, x - grid.x * SaChunk.SIZE, y - grid.y * SaChunk.SIZE)


## A context whose run has already produced a flat green result over whatever
## `layer_pixels` answers, which under an active selection is the selection's
## own bounds rather than the layer's whole allocated reach.
func _shown_green_over_selection() -> SaFilterContext:
    var ctx := SaFilterContext.new(_doc, _layer)
    var result := ctx.blank_like(ctx.layer_pixels(0))
    result.clear(GREEN)
    ctx.show(result)
    return ctx


func test_apply_under_a_feathered_ellipse_stops_at_the_mask_and_not_at_the_rectangle() -> void:
    _doc.selection.select_ellipse(ELLIPSE_RECT)
    SaSelectionFilters.feather(_doc.selection, FEATHER_RADIUS, _doc.canvas_size)
    var ctx := _shown_green_over_selection()

    assert_true(SaFilterApply.apply(ctx, "Box blur"), "The apply wrote")

    var inside := _layer_texel(350, 350)
    assert_almost_eq(inside.g, 1.0, 1e-2, "At the ellipse's centre the layer is fully the result")
    assert_almost_eq(inside.r, 0.0, 1e-2, "and none of what it was")

    var outside := _layer_texel(270, 270)
    assert_almost_eq(outside.r, 1.0, 1e-3, "Well outside the ellipse and its feather the layer is untouched")
    assert_almost_eq(outside.g, 0.0, 1e-3, "and none of the result reached it")

    var on_feather := _layer_texel(ELLIPSE_RECT.position.x + ELLIPSE_RECT.size.x, 350)
    assert_true(on_feather.r > 0.05 and on_feather.r < 0.95, "On the feather the layer holds neither pure red")
    assert_true(on_feather.g > 0.05 and on_feather.g < 0.95, "nor pure green, but a blend of the two")


func test_apply_under_a_selection_still_records_one_undo_step() -> void:
    _doc.selection.select_ellipse(ELLIPSE_RECT)
    var ctx := _shown_green_over_selection()

    SaFilterApply.apply(ctx, "Box blur")

    assert_true(_doc.undo_redo.has_undo(), "One step, and there was none before")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Box blur", "named after the filter and not after the door")


func test_undo_under_a_selection_puts_the_pixels_back() -> void:
    _doc.selection.select_ellipse(ELLIPSE_RECT)
    var ctx := _shown_green_over_selection()
    SaFilterApply.apply(ctx, "Box blur")

    assert_true(_doc.undo(), "which undoes")

    var inside := _layer_texel(350, 350)
    assert_almost_eq(inside.r, 1.0, 1e-3, "and the layer is red again at the centre")
    assert_almost_eq(inside.g, 0.0, 1e-3, "with none of the result left")


func test_a_chunk_inside_the_selections_bounding_box_but_outside_the_selection_is_untouched() -> void:
    # Two small rectangles far apart put chunk (1, 2) inside the union of their
    # bounding boxes without a single selected pixel in it, which is the chunk
    # `selection.texture_for` answers null for and a masked apply must skip
    # rather than allocate a snapshot for.
    _doc.selection.select_rect(Rect2i(260, 260, 10, 10))
    _doc.selection.select_rect(Rect2i(760, 760, 10, 10), SaSelection.Mode.ADD)
    var ctx := _shown_green_over_selection()

    assert_true(SaFilterApply.apply(ctx, "Box blur"), "The apply wrote")

    var in_first := _layer_texel(264, 264)
    assert_almost_eq(in_first.g, 1.0, 1e-2, "The first rectangle got the result")
    var in_second := _layer_texel(764, 764)
    assert_almost_eq(in_second.g, 1.0, 1e-2, "and so did the second, across the gap between them")
    var between := _layer_texel(300, 600)
    assert_almost_eq(between.r, 1.0, 1e-3, "The chunk between them, inside the bounding box and outside both, is untouched")
    assert_almost_eq(between.a, 1.0, 1e-3, "and was never allocated fresh, since it was already the red chunk from before_each")
