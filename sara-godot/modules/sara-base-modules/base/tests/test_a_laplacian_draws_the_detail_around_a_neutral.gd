## The Laplacian filter draws the second derivative as a grey map
## around a neutral, so a flat area reads the neutral everywhere, the two sides
## of a step read either side of it, and the map laid over the picture in
## Overlay at half opacity steepens the edge.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The filter is a neighbourhood pass of radius one. It lays
## the map over the picture itself unless Show the raw map is ticked, so every
## case here ticks it and reads the raw map. The first three apply it
## to a layer and read the layer, the fourth puts it on an adjustment layer above
## a soft edge and reads the composite. The sharpen the filter does on its
## own is the suite `test_the_laplacian_sharpens_the_picture_itself.gd`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
const NEUTRAL := SaLaplacianFilter.NEUTRAL

const SIZE := Vector2i(512, 256)
const DARK := Color(0.1, 0.1, 0.1, 1.0)
const BRIGHT := Color(0.9, 0.9, 0.9, 1.0)
const FLAT := Color(0.3, 0.6, 0.8, 1.0)

## The column a step changes at, and a row well inside the layer.
const EDGE_X := 128
const ROW := 100
## The strength of the layer in the Overlay case. Overlay multiplies in the
## shadows, so the map has to be strong for the steepening to show.
const STRENGTH := 4.0
## The soft edge: a ramp of RAMP_WIDTH columns from DARK to BRIGHT, one fill each.
const RAMP_FROM := 124
const RAMP_WIDTH := 3

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null


func before_each() -> void:
    _easel = Bench.easel(SIZE)
    _doc = _easel.document
    _layer = _doc.active_layer


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _layer = null


func _step() -> void:
    _layer.fill(DARK)
    _doc.selection.select_rect(Rect2i(EDGE_X, 0, SIZE.x - EDGE_X, SIZE.y))
    _layer.fill(BRIGHT)
    _doc.selection.deselect()


## DARK, then BRIGHT, with RAMP_WIDTH columns of greys between.
func _soft_edge() -> void:
    _layer.fill(DARK)
    for column in RAMP_WIDTH:
        var grey := lerpf(DARK.r, BRIGHT.r, float(column + 1) / float(RAMP_WIDTH + 1))
        _doc.selection.select_rect(Rect2i(RAMP_FROM + column, 0, 1, SIZE.y))
        _layer.fill(Color(grey, grey, grey, 1.0))
    _doc.selection.select_rect(Rect2i(RAMP_FROM + RAMP_WIDTH, 0, SIZE.x - RAMP_FROM - RAMP_WIDTH, SIZE.y))
    _layer.fill(BRIGHT)
    _doc.selection.deselect()


func _apply(strength: float) -> bool:
    var filter := SaLaplacianFilter.new()
    filter.set_parameters({"strength": strength, "raw": true})
    var ctx := SaFilterContext.new(_doc, _layer, OWNER, filter.title())
    if not SaFilterApply.call_run(filter, ctx):
        return false
    return SaFilterApply.apply(ctx, filter.title())


func _texel(x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var texture := _layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(
        bytes, texture.format, (y - grid.y * SaChunk.SIZE) * texture.size.x + (x - grid.x * SaChunk.SIZE)
    )


func test_a_flat_layer_reads_the_neutral_everywhere() -> void:
    _layer.fill(FLAT)

    assert_true(_apply(1.0), "The Laplacian runs over a flat layer")

    for at: Vector2i in [Vector2i(50, 50), Vector2i(200, 100), Vector2i(300, 200), Vector2i(450, 30)]:
        var found := _texel(at.x, at.y)
        for channel in 3:
            assert_almost_eq(found[channel], NEUTRAL, 1e-4, "Channel %d at %s reads the neutral" % [channel, at])
        assert_almost_eq(found.a, 1.0, 1e-4, "and keeps the alpha at %s" % at)


func test_the_two_sides_of_a_step_read_either_side_of_the_neutral() -> void:
    _step()

    assert_true(_apply(1.0), "The Laplacian runs over a step")

    var bright := _texel(EDGE_X, ROW).r
    var dark := _texel(EDGE_X - 1, ROW).r
    assert_true(bright > NEUTRAL + 0.05, "The bright side reads above the neutral, %s" % bright)
    assert_true(dark < NEUTRAL - 0.05, "the dark side below it, %s" % dark)
    assert_almost_eq(bright - NEUTRAL, (BRIGHT.r - DARK.r) * 0.25, 1e-3, "by a quarter of the step")
    assert_almost_eq(dark - NEUTRAL, -(BRIGHT.r - DARK.r) * 0.25, 1e-3, "and the same the other way")
    assert_almost_eq(_texel(EDGE_X - 20, ROW).r, NEUTRAL, 1e-4, "Twenty texels into the dark side it is the neutral")
    assert_almost_eq(_texel(EDGE_X + 20, ROW).r, NEUTRAL, 1e-4, "and twenty into the bright one")


func test_the_strength_scales_the_detail_and_nothing_clamps() -> void:
    _step()
    assert_true(_apply(1.0), "Runs at strength 1")
    var once := _texel(EDGE_X, ROW).r - NEUTRAL
    assert_true(_doc.undo(), "which undoes")

    assert_true(_apply(4.0), "and again at strength 4")

    var more := _texel(EDGE_X, ROW).r - NEUTRAL
    assert_almost_eq(more, once * 4.0, 1e-3, "Four times the strength, four times the detail")
    assert_true(_texel(EDGE_X, ROW).r > 1.0, "which is past one, where a clamping kernel would have stopped")


## The step of the composite's red between the two probe columns.
func _composite_step(from_x: int, to_x: int) -> float:
    Bench.composite(_easel)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(_easel.output.rid, 0)
    var width := _easel.output.size.x
    var low := SaFieldSpec.decode_texel(bytes, _easel.output.format, ROW * width + from_x)
    var high := SaFieldSpec.decode_texel(bytes, _easel.output.format, ROW * width + to_x)
    return high.r - low.r


func test_a_laplacian_layer_in_overlay_at_half_opacity_steepens_a_soft_edge() -> void:
    _soft_edge()
    var own := _texel(RAMP_FROM + RAMP_WIDTH, ROW).r - _texel(RAMP_FROM - 1, ROW).r
    var bare := _composite_step(RAMP_FROM - 1, RAMP_FROM + RAMP_WIDTH)

    var registry := SaFilterRegistry.new()
    var filter := SaLaplacianFilter.new()
    registry.register(filter, OWNER)
    _easel.compositor.filter_chain.registry = registry
    var types := Fixtures.make_registries().layer_types
    var ops := SaLayerOps.new(_doc)
    var adjust := ops.add(SaBackdropLayer.TYPE_ID, types)
    assert_not_null(adjust, "An adjustment layer is added")
    var key := SaFilterRegistry.key_for(OWNER, filter)
    var attached := SaFilterOps.new(_doc).attach(adjust, key, {"strength": STRENGTH, "raw": true})
    assert_not_null(attached, "The Laplacian attaches to it")
    ops.set_blend_mode(adjust, SaLayer.BLEND_MODE.OVERLAY)
    ops.set_opacity(adjust, 0.5)

    var sharpened := _composite_step(RAMP_FROM - 1, RAMP_FROM + RAMP_WIDTH)

    assert_almost_eq(bare, own, 1e-4, "Before the filter layer the composite shows the layer's own step")
    assert_true(own > 0.5, "The layer's own step across the ramp is real, %s" % own)
    assert_true(sharpened > own + 0.02, "The composite's step is larger, %s against the layer's %s" % [sharpened, own])
