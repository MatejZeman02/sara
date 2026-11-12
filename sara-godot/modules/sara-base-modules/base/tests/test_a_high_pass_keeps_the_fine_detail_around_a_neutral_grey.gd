## The High Pass filter draws the picture less its Gaussian blur
## around a neutral grey, so a flat colour reads the neutral everywhere, the two
## sides of an edge read either side of it and add back, with the Gaussian blur
## at the same radius, to the picture, an edge above one reads past the neutral
## by its whole difference, and a layer of the map in Soft Light steepens an
## edge.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The filter lays the map over the picture itself unless Show the raw map is
## ticked, so every case here ticks it and reads the raw map. The first four apply the filter to a layer
## and read the layer,
## the edge on the seam between two chunks so the padding the pass gathers is
## read as well. The last puts it on a filter layer above a soft edge and reads
## the composite. The sharpen the filter does on its own is the suite
## `test_the_high_pass_sharpens_the_picture_itself.gd`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
const NEUTRAL := SaHighPassFilter.NEUTRAL

const SIZE := Vector2i(512, 256)
const DARK := Color(0.1, 0.2, 0.3, 1.0)
const BRIGHT := Color(0.9, 0.7, 0.5, 1.0)
## An edge above one, which a clamping kernel would cut short.
const HOT := Color(4.0, 3.0, 2.0, 1.0)
const FLAT := Color(0.3, 0.6, 0.8, 1.0)

## The column a step changes at, on the seam between the first two chunks, and
## a row well inside the layer.
const EDGE_X := SaChunk.SIZE
const ROW := 100
const RADIUS := 6
## The soft edge of the Soft Light case: RAMP_WIDTH columns of greys from DARK
## to BRIGHT, one fill each.
const RAMP_FROM := 124
const RAMP_WIDTH := 3
const GREY_DARK := 0.1
const GREY_BRIGHT := 0.9

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


func _step(low: Color, high: Color) -> void:
    _layer.fill(low)
    _doc.selection.select_rect(Rect2i(EDGE_X, 0, SIZE.x - EDGE_X, SIZE.y))
    _layer.fill(high)
    _doc.selection.deselect()


## GREY_DARK, then GREY_BRIGHT, with RAMP_WIDTH columns of greys between.
func _soft_edge() -> void:
    _layer.fill(Color(GREY_DARK, GREY_DARK, GREY_DARK, 1.0))
    for column in RAMP_WIDTH:
        var grey := lerpf(GREY_DARK, GREY_BRIGHT, float(column + 1) / float(RAMP_WIDTH + 1))
        _doc.selection.select_rect(Rect2i(RAMP_FROM + column, 0, 1, SIZE.y))
        _layer.fill(Color(grey, grey, grey, 1.0))
    _doc.selection.select_rect(Rect2i(RAMP_FROM + RAMP_WIDTH, 0, SIZE.x - RAMP_FROM - RAMP_WIDTH, SIZE.y))
    _layer.fill(Color(GREY_BRIGHT, GREY_BRIGHT, GREY_BRIGHT, 1.0))
    _doc.selection.deselect()


## *filter* at *radius*, the High Pass with its raw map ticked. The Gaussian
## blur has no row of that key and ignores it.
func _apply(filter: SaFilter, radius: int) -> bool:
    filter.set_parameters({"radius": radius, "raw": true})
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


## The row's texels from RADIUS + 2 before the edge to RADIUS + 2 after it.
func _row() -> Array[Color]:
    var out: Array[Color] = []
    for x in range(EDGE_X - RADIUS - 2, EDGE_X + RADIUS + 2):
        out.append(_texel(x, ROW))
    return out


## The high pass over the row, the picture the undo puts back, and the Gaussian
## blur at the same radius, in that order.
func _three_rows() -> Array:
    assert_true(_apply(SaHighPassFilter.new(), RADIUS), "The High Pass runs over the step")
    var high := _row()
    assert_true(_doc.undo(), "which undoes")
    var picture := _row()
    assert_true(_apply(SaGaussianBlurFilter.new(), RADIUS), "and the Gaussian blur runs at the same radius")
    return [high, picture, _row()]


func _assert_adds_back(rows: Array) -> void:
    var high: Array[Color] = rows[0]
    var picture: Array[Color] = rows[1]
    var blurred: Array[Color] = rows[2]
    for i in high.size():
        for channel in 3:
            var sum: float = high[i][channel] - NEUTRAL + blurred[i][channel]
            assert_almost_eq(
                sum,
                picture[i][channel],
                1e-4,
                "At x %d channel %d the map less the neutral plus the blur is the picture" % [EDGE_X - RADIUS - 2 + i, channel]
            )


func test_a_flat_colour_reads_the_neutral_everywhere() -> void:
    _layer.fill(FLAT)

    assert_true(_apply(SaHighPassFilter.new(), RADIUS), "The High Pass runs over a flat layer")

    var probes: Array[Vector2i] = [
        Vector2i(0, 0), Vector2i(50, 50), Vector2i(EDGE_X - 1, ROW), Vector2i(EDGE_X, ROW), Vector2i(SIZE.x - 1, SIZE.y - 1)
    ]
    for at: Vector2i in probes:
        var found := _texel(at.x, at.y)
        for channel in 3:
            assert_almost_eq(found[channel], NEUTRAL, 1e-4, "Channel %d at %s reads the neutral" % [channel, at])
        assert_almost_eq(found.a, 1.0, 1e-4, "and keeps the alpha at %s" % at)


## The neutral is the mid grey of the document's RGB view, so an Oklab document
## stores it as that grey's Oklab rather than as three halves, which would show
## as a colour.
func test_on_an_oklab_document_a_flat_colour_reads_the_grey_of_its_rgb_view() -> void:
    _easel.free()
    var space := SaColorSpace.oklab()
    _easel = SaEasel.create_default(SIZE, null, space)
    _doc = _easel.document
    _layer = _doc.active_layer
    _layer.fill(space.from_display(FLAT))

    assert_true(_apply(SaHighPassFilter.new(), RADIUS), "The High Pass runs over a flat Oklab layer")

    var grey := space.from_display(Color(NEUTRAL, NEUTRAL, NEUTRAL, 1.0))
    for at: Vector2i in [Vector2i(50, 50), Vector2i(EDGE_X, ROW)]:
        var found := _texel(at.x, at.y)
        for channel in 3:
            assert_almost_eq(found[channel], grey[channel], 1e-3, "Channel %d at %s is the grey's Oklab" % [channel, at])


func test_an_edge_reads_either_side_of_the_neutral_and_adds_back_with_the_blur() -> void:
    _step(DARK, BRIGHT)

    var rows := _three_rows()

    var high: Array[Color] = rows[0]
    var at_edge := RADIUS + 2
    for channel in 3:
        var bright: Color = high[at_edge]
        assert_true(
            bright[channel] > NEUTRAL + 0.02, "The bright side reads above the neutral in channel %d, %s" % [channel, bright]
        )
        assert_true(high[at_edge - 1][channel] < NEUTRAL - 0.02, "the dark side below it, %s" % high[at_edge - 1])
        assert_almost_eq(high[0][channel], NEUTRAL, 1e-4, "Past the radius on the dark side it is the neutral")
        assert_almost_eq(high[high.size() - 1][channel], NEUTRAL, 1e-4, "and past it on the bright one")
    _assert_adds_back(rows)


func test_an_edge_above_one_reads_past_the_neutral_by_its_whole_difference() -> void:
    _step(DARK, HOT)

    var rows := _three_rows()

    var high: Array[Color] = rows[0]
    var at_edge := RADIUS + 2
    assert_true(high[at_edge].r > 1.0, "The bright side of the edge reads past one, %s" % high[at_edge])
    assert_true(high[at_edge - 1].r < 0.0, "and the dark side below zero, %s" % high[at_edge - 1])
    _assert_adds_back(rows)


## The step of the composite's red between the two probe columns.
func _composite_step(from_x: int, to_x: int) -> float:
    Bench.composite(_easel)
    return _composite_red(to_x) - _composite_red(from_x)


func _composite_red(x: int) -> float:
    return Bench.texel(_easel.output, Vector2i(x, ROW)).r


func test_a_high_pass_layer_in_soft_light_steepens_a_soft_edge() -> void:
    _soft_edge()
    var own := _texel(RAMP_FROM + RAMP_WIDTH, ROW).r - _texel(RAMP_FROM - 1, ROW).r
    var bare := _composite_step(RAMP_FROM - 1, RAMP_FROM + RAMP_WIDTH)
    var far := _composite_red(SIZE.x - 20)

    var registry := SaFilterRegistry.new()
    var filter := SaHighPassFilter.new()
    registry.register(filter, OWNER)
    _easel.compositor.filter_chain.registry = registry
    var types := Fixtures.make_registries().layer_types
    var ops := SaLayerOps.new(_doc)
    var layer := ops.add(SaBackdropLayer.TYPE_ID, types)
    assert_not_null(layer, "A filter layer is added")
    var key := SaFilterRegistry.key_for(OWNER, filter)
    assert_not_null(SaFilterOps.new(_doc).attach(layer, key, {"radius": RADIUS, "raw": true}), "The High Pass attaches to it")
    ops.set_blend_mode(layer, SaLayer.BLEND_MODE.SOFT_LIGHT)

    var sharpened := _composite_step(RAMP_FROM - 1, RAMP_FROM + RAMP_WIDTH)

    assert_almost_eq(bare, own, 1e-4, "Before the filter layer the composite shows the layer's own step")
    assert_true(sharpened > own + 0.02, "The composite's step is larger, %s against the layer's %s" % [sharpened, own])
    assert_almost_eq(_composite_red(SIZE.x - 20), far, 1e-4, "and a flat area far from the edge is left as it was")
