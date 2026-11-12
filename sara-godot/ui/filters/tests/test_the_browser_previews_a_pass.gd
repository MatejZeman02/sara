## The filter browser's picture of a filter that records a pass. A point
## filter and a neighbourhood filter show no texture, they record a
## pass the canvas runs, so the browser runs that pass over the layer's chunks
## into a picture of its own. The point filter is an invert fixture,
## built here, and the neighbourhood one is the box blur. Every case reads the
## picture's texels and then the layer's, which must be what they were.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const InvertFilter = preload("res://tests/fixtures/modules/point-fixture/invert_filter.gd")
const BoxBlurFilter = preload("res://modules/sara-base-modules/base/usual/box_blur_filter.gd")

const REQUIRES_GPU := true

const GREY := Color(0.25, 0.5, 0.75, 1.0)
const RADIUS := 4

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null


func before_each() -> void:
    # Two chunks across and two down, with only (0, 0) painted, so the picture
    # has a painted chunk, a seam and positions no chunk answers for.
    _easel = Bench.easel(Vector2i(2 * SaChunk.SIZE, 2 * SaChunk.SIZE))
    _doc = _easel.document
    _layer = _doc.active_layer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)
    _layer.get_or_create_chunk(Vector2i(0, 0)).clear(GREY)


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _layer = null


func _run_invert() -> SaFilterContext:
    var ctx := SaFilterContext.new(_doc, _layer, &"point-fixture", "Invert", true)
    assert_true(SaFilterApply.call_run(InvertFilter.new(), ctx), "The invert's run is clean")
    return ctx


func _run_blur() -> SaFilterContext:
    ModuleLoader.module_dirs[&"sara-base-modules"] = "res://modules/sara-base-modules/base"
    var blur := BoxBlurFilter.new()
    blur.write_parameter(&"radius", RADIUS)
    var ctx := SaFilterContext.new(_doc, _layer, &"sara-base-modules", "Box blur", true)
    assert_true(SaFilterApply.call_run(blur, ctx), "The blur's run is clean")
    return ctx


func _layer_texel(at: Vector2i) -> Color:
    return Bench.texel(_layer.get_field(Vector2i(0, 0)), at)


func test_a_point_pass_is_evaluated_into_a_picture() -> void:
    var steps := _doc.history.step_count()
    var ctx := _run_invert()
    assert_null(ctx.shown, "The run showed nothing, it recorded a pass")
    var picture := SaFilterBrowser.picture_of(ctx)
    assert_not_null(picture, "and the browser still has a picture")
    if picture == null:
        return
    assert_eq(ctx.shown_rect, Rect2i(0, 0, SaChunk.SIZE, SaChunk.SIZE), "covering the painted chunk")
    var texel := Bench.texel(picture, Vector2i(10, 10))
    assert_almost_eq(texel.r, 0.75, 1e-4, "The picture is the invert: %s" % texel)
    assert_almost_eq(texel.b, 0.25, 1e-4, "in every channel")
    assert_almost_eq(texel.a, 1.0, 1e-4, "with the alpha kept")
    var corner := Bench.texel(picture, Vector2i(SaChunk.SIZE - 1, SaChunk.SIZE - 1))
    assert_almost_eq(corner.g, 0.5, 1e-4, "to the chunk's far corner")
    assert_almost_eq(_layer_texel(Vector2i(10, 10)).r, 0.25, 1e-6, "while the layer is what it was")
    assert_eq(_layer.chunks.size(), 1, "with no chunk allocated")
    assert_eq(_doc.history.step_count(), steps, "and no history step")


func test_a_point_pass_under_a_selection_is_mixed_by_it() -> void:
    _doc.selection.select_rect(Rect2i(0, 0, 64, 64))
    var ctx := _run_invert()
    var picture := SaFilterBrowser.picture_of(ctx)
    assert_not_null(picture, "The selection's picture exists")
    if picture == null:
        return
    assert_eq(ctx.shown_rect, Rect2i(0, 0, 64, 64), "over the selection's bounds")
    assert_almost_eq(Bench.texel(picture, Vector2i(10, 10)).r, 0.75, 1e-4, "inverted inside it")
    assert_almost_eq(_layer_texel(Vector2i(10, 10)).r, 0.25, 1e-6, "and the layer untouched")


func test_a_neighbourhood_pass_reads_across_into_the_unpainted_chunk() -> void:
    var steps := _doc.history.step_count()
    var ctx := _run_blur()
    assert_true(ctx.point is SaNeighbourhoodPass, "The box blur recorded a neighbourhood pass")
    var picture := SaFilterBrowser.picture_of(ctx)
    assert_not_null(picture, "and the browser has a picture of it")
    if picture == null:
        return
    assert_eq(ctx.shown_rect.size, Vector2i(SaChunk.SIZE + RADIUS, SaChunk.SIZE + RADIUS), "grown by the radius")
    var middle := Bench.texel(picture, Vector2i(100, 100))
    assert_almost_eq(middle.b, 0.75, 1e-4, "Inside the paint the box reads grey: %s" % middle)
    var past := Bench.texel(picture, Vector2i(SaChunk.SIZE + 1, 100))
    assert_true(past.a > 0.0 and past.a < 1.0, "Past the edge it carries some of the paint: %s" % past)
    var edge := Bench.texel(picture, Vector2i(SaChunk.SIZE + RADIUS - 1, 100))
    assert_true(edge.a < past.a, "and less of it at the halo's reach: %s" % edge)
    assert_eq(_layer.chunks.size(), 1, "The layer allocated nothing for the picture")
    assert_eq(_doc.history.step_count(), steps, "and recorded no step")


func test_a_run_that_showed_a_texture_is_that_texture() -> void:
    var ctx := SaFilterContext.new(_doc, _layer, &"", "Shown", true)
    var pixels := ctx.layer_pixels()
    ctx.show(pixels)
    assert_eq(SaFilterBrowser.picture_of(ctx), pixels, "A shown texture is the picture, untouched")
    assert_null(SaFilterBrowser.picture_of(null), "and no run is no picture")
