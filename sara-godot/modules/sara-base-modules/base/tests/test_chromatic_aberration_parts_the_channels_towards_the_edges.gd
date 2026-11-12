## Chromatic Aberration reads red from a place pushed out from the
## document's centre, blue from the place pushed in towards it and green from
## where it stands, by an amount that falls to nothing at the centre. A white
## square at the centre stays where it was in every channel, a white square near
## a corner has a red fringe on its side towards the centre and a blue one on
## its other, green unmoved, and the filter attached agrees with the layer baked.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## Real dispatches into real chunks.
const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
## A document two chunks wide and high, so a corner square lies far from the centre.
const CHUNKS := 2
const SETTINGS := {"amount": 10}
## The white square's corner and side, in document pixels. Near the top left
## corner, and the same size as the one at the centre. [const HALF] is the
## offset of its middle row and column, the number the side is made from so
## that no line divides one integer by another.
const HALF := 16
const SIDE := 2 * HALF
const NEAR_CORNER := Vector2i(40, 40)
const AT_CENTRE := Vector2i(240, 240)

var _easel: SaEasel = null
var _document: SaDocument = null
var _filter: SaChromaticAberrationFilter = null
var _key: StringName = &""


func before_each() -> void:
    _make_easel()


func after_each() -> void:
    _easel.free()
    _easel = null
    _document = null
    _filter = null


func _make_easel() -> void:
    _easel = SaEasel.create_default(Vector2i(SaChunk.SIZE, SaChunk.SIZE) * CHUNKS)
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var registry := SaFilterRegistry.new()
    _filter = SaChromaticAberrationFilter.new()
    registry.register(_filter, OWNER)
    _key = SaFilterRegistry.key_for(OWNER, _filter)
    _easel.compositor.filter_chain.registry = registry
    _document = _easel.document
    _document.color_space = SaColorSpace.linear_srgb()


## "Layer 1" opaque black in every chunk, with a white square of [const SIDE]
## at document pixel *square_at*, which lies in the chunk it falls in.
func _paint(square_at: Vector2i) -> SaLayer:
    var layer := _document.get_node("Layer 1") as SaLayer
    for y in CHUNKS:
        for x in CHUNKS:
            var grid_pos := Vector2i(x, y)
            var chunk := layer.get_or_create_chunk(grid_pos)
            var side := chunk.pixel_size()
            var local := Rect2i(square_at - grid_pos * SaChunk.SIZE, Vector2i(SIDE, SIDE))
            var values := PackedFloat32Array()
            values.resize(side * side * 4)
            for py in side:
                for px in side:
                    var i := (py * side + px) * 4
                    var white := local.has_point(Vector2i(px, py))
                    values[i] = 1.0 if white else 0.0
                    values[i + 1] = values[i]
                    values[i + 2] = values[i]
                    values[i + 3] = 1.0
            GlobalShaderCompiler.get_rd().texture_update(chunk.field(SaFieldSpec.ALBEDO).rid, 0, values.to_byte_array())
    return layer


## The composite as bytes, read back once.
func _read() -> Array:
    Bench.composite(_easel)
    var texture := _easel.output
    return [GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0), texture]


static func _at(read: Array, at: Vector2i) -> Color:
    var texture := read[1] as SaTexture
    return SaFieldSpec.decode_texel(read[0], texture.format, at.y * texture.size.x + at.x)


## The first and last texel of row *y* in [x0, x1) where channel *channel* is
## past a half, or null when it never is.
static func _extent(read: Array, y: int, x0: int, x1: int, channel: int) -> Variant:
    var first := -1
    var last := -1
    for x in range(x0, x1):
        if _at(read, Vector2i(x, y))[channel] > 0.5:
            if first < 0:
                first = x
            last = x
    if first < 0:
        return null
    return Vector2i(first, last)


func test_a_square_at_the_centre_stays_where_it_was_in_every_channel() -> void:
    SaFilterOps.new(_document).attach(_paint(AT_CENTRE), _key, SETTINGS)
    var read := _read()
    var row := AT_CENTRE.y + HALF
    for channel in 3:
        var found: Variant = _extent(read, row, 200, 320, channel)
        assert_true(found != null, "Channel %d still shows the square" % channel)
        if found == null:
            continue
        var span := found as Vector2i
        var right := AT_CENTRE.x + SIDE - 1
        var left := AT_CENTRE.x
        assert_true(absi(span.x - left) <= 1, "Channel %d starts at %d, within a pixel of %d" % [channel, span.x, left])
        assert_true(absi(span.y - right) <= 1, "Channel %d ends at %d, within a pixel of %d" % [channel, span.y, right])
    var middle := _at(read, AT_CENTRE + Vector2i(HALF, HALF))
    assert_true(middle.r > 0.99 and middle.g > 0.99 and middle.b > 0.99, "and the middle of the square is white: %s" % middle)


func test_a_square_near_a_corner_has_a_red_fringe_one_side_and_a_blue_one_the_other() -> void:
    SaFilterOps.new(_document).attach(_paint(NEAR_CORNER), _key, SETTINGS)
    var read := _read()
    var row := NEAR_CORNER.y + HALF
    var inner := _at(read, Vector2i(NEAR_CORNER.x + SIDE + 2, row))
    assert_true(inner.r > 0.9, "Towards the centre red reaches past the square: %s" % inner)
    assert_true(inner.g < 0.01 and inner.b < 0.01, "and nothing else does: %s" % inner)
    var outer := _at(read, Vector2i(NEAR_CORNER.x - 2, row))
    assert_true(outer.b > 0.9, "Towards the corner blue reaches past the square: %s" % outer)
    assert_true(outer.g < 0.01 and outer.r < 0.01, "and nothing else does: %s" % outer)
    var green_in: Variant = _extent(read, row, 0, 200, 1)
    assert_true(green_in != null, "Green still shows the square")
    if green_in != null:
        var span := green_in as Vector2i
        assert_eq(span, Vector2i(NEAR_CORNER.x, NEAR_CORNER.x + SIDE - 1), "Green is exactly where the square was")
    var red := _extent(read, row, 0, 200, 0) as Vector2i
    var blue := _extent(read, row, 0, 200, 2) as Vector2i
    assert_true(red.x > blue.x and red.y > blue.y, "Red lies nearer the centre than blue: %s against %s" % [red, blue])


func test_no_amount_leaves_the_square_alone() -> void:
    SaFilterOps.new(_document).attach(_paint(NEAR_CORNER), _key, {"amount": 0})
    var read := _read()
    var row := NEAR_CORNER.y + HALF
    for channel in 3:
        var span := _extent(read, row, 0, 200, channel) as Vector2i
        assert_eq(span, Vector2i(NEAR_CORNER.x, NEAR_CORNER.x + SIDE - 1), "Channel %d is where it was" % channel)


func test_the_attached_filter_is_the_baked_layer_over_the_corner_square() -> void:
    SaFilterOps.new(_document).attach(_paint(NEAR_CORNER), _key, SETTINGS)
    var attached := _read()
    var attached_values: Array[Color] = []
    for y in SaChunk.SIZE:
        for x in SaChunk.SIZE:
            attached_values.append(_at(attached, Vector2i(x, y)))
    _easel.free()
    _make_easel()
    var whole := _paint(NEAR_CORNER)
    _filter.set_parameters(SETTINGS)
    var ctx := SaFilterContext.new(_document, whole, OWNER, _filter.title(), false)
    assert_true(SaFilterApply.call_run(_filter, ctx), "The run records a pass")
    assert_true(SaFilterApply.apply(ctx, _filter.title()), "which Apply bakes into the layer")
    var baked := _read()
    var worst := 0.0
    var index := 0
    for y in SaChunk.SIZE:
        for x in SaChunk.SIZE:
            var a := attached_values[index]
            var b := _at(baked, Vector2i(x, y))
            worst = maxf(worst, maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))))
            index += 1
    assert_true(worst < 1e-4, "The attached composite is the baked layer's, off by %f" % worst)
    var fringe: Color = attached_values[(NEAR_CORNER.y + HALF) * SaChunk.SIZE + NEAR_CORNER.x + SIDE + 2]
    assert_true(fringe.r > 0.9, "and the fringe is there to agree on: %s" % fringe)


func test_it_is_listed_under_distort_and_found_by_its_name() -> void:
    var filter := SaChromaticAberrationFilter.new()
    assert_eq(filter.family(), &"distort", "It is a Distort filter")
    assert_eq(filter.title(), "Chromatic Aberration", "called Chromatic Aberration")
    assert_false(filter.finishes(), "and it runs where it stands in a chain")
    assert_eq(SaChromaticAberrationFilter.reach(10.0), 11, "Its halo is the largest shift and a texel")
