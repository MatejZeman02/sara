## A Gaussian blur of radius 100 fades out where its reach ends,
## with no step there, in what Apply writes and in what the compositor shows of
## the same filter attached, which is what the canvas preview draws.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The box seen at the edge was the bell's own edge. Sigma is a third of the reach,
## so the last tap the walk takes weighs exp(-4.5) of the centre's, a ninetieth,
## and the first it does not take weighs nothing. Down a column below a thin
## stroke that is a step ten times the steps before it, and the walk being
## separable makes the reach a square, so round a dot or a stroke the step runs
## round a box. Below a broad stroke the values do not step but their slope
## does, the same edge one sum later.
##
## Each case paints a stroke across a canvas three chunks wide, reads one column
## of alpha across the edge of the reach, from six texels inside it to four
## past, and reads each step against the two beside it. The stroke is white at
## four times the display's white with alpha one, and the column is read in its
## alpha, which the blur spreads by its weights alone.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
## The radius at which the box shows.
const RADIUS := 100
const CHUNKS_ACROSS := 3
## The stroke's lowest row and the column read below it, both in the middle
## chunk, and the stroke's span, which passes the column by more than the reach
## on either side so every tap of a row across lands on paint.
const STROKE_ROW := 300
const COLUMN := 384
const FROM := 64
const TO := 704
const BRIGHT := Color(4.0, 4.0, 4.0, 1.0)
## The broad stroke's height in rows, enough that its top row lies past the
## reach of every texel read, so the column reads the stroke's lower edge alone.
const BROAD := 24
## The first and last distance below the stroke read, the reach's edge between.
const NEAREST := RADIUS - 6
const FURTHEST := RADIUS + 4
## How far a step may stand above the larger of its neighbours and still count
## as none. A step at radius 100 is about 1e-5 of alpha, the box was 1.3e-4,
## and the float error of a column read is under 1e-9.
const TOLERANCE := 0.000001

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null


func before_each() -> void:
    _easel = Bench.easel(Vector2i.ONE * CHUNKS_ACROSS * SaChunk.SIZE)
    _doc = _easel.document
    _layer = _doc.get_node("Background") as SaLayer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _layer = null


## A stroke *rows* high whose lowest row is [const STROKE_ROW], from
## [const FROM] to [const TO], uploaded into each chunk of its row, since the
## brush is not what this suite is about.
func _paint_stroke(rows: int) -> void:
    var top := STROKE_ROW - rows + 1
    @warning_ignore("integer_division")
    var chunk_row := STROKE_ROW / SaChunk.SIZE
    for column in CHUNKS_ACROSS:
        var grid_pos := Vector2i(column, chunk_row)
        var texture := _layer.get_or_create_chunk(grid_pos).albedo()
        assert_eq(texture.format, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, "The bench document is F32")
        var corner := grid_pos * SaChunk.SIZE
        var values := PackedFloat32Array()
        values.resize(texture.size.x * texture.size.y * 4)
        for y in range(top, STROKE_ROW + 1):
            for x in range(maxi(FROM, corner.x), mini(TO, corner.x + SaChunk.SIZE)):
                var i := (y - corner.y) * texture.size.x + (x - corner.x)
                values[i * 4] = BRIGHT.r
                values[i * 4 + 1] = BRIGHT.g
                values[i * 4 + 2] = BRIGHT.b
                values[i * 4 + 3] = BRIGHT.a
        GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, values.to_byte_array())
        _layer.mark_unresolved(grid_pos)


## The alpha of *texture* down [const COLUMN], from [const NEAREST] below the
## stroke to [const FURTHEST], *corner* being the document pixel its first
## texel stands for.
func _column(texture: SaTexture, corner: Vector2i) -> PackedFloat32Array:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var out := PackedFloat32Array()
    for distance in range(NEAREST, FURTHEST + 1):
        var at := Vector2i(COLUMN, STROKE_ROW + distance) - corner
        out.append(SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x).a)
    return out


## What Apply writes, in the chunk under the column.
func _applied(rows: int) -> PackedFloat32Array:
    _paint_stroke(rows)
    var filter := SaGaussianBlurFilter.new()
    filter.set_parameters({"radius": RADIUS})
    var ctx := SaFilterContext.new(_doc, _layer, OWNER, filter.title())
    assert_true(SaFilterApply.call_run(filter, ctx), "The blur records its pass")
    assert_true(SaFilterApply.apply(ctx, filter.title()), "which Apply walks over the layer")
    @warning_ignore("integer_division")
    var grid_pos := Vector2i(COLUMN, STROKE_ROW + RADIUS) / SaChunk.SIZE
    return _column(_layer.get_field(grid_pos), grid_pos * SaChunk.SIZE)


## What the compositor shows of the same blur attached to the layer.
func _attached(rows: int) -> PackedFloat32Array:
    _paint_stroke(rows)
    var filter := SaGaussianBlurFilter.new()
    _easel.compositor.filter_chain.registry.register(filter, OWNER)
    var key := SaFilterRegistry.key_for(OWNER, filter)
    SaFilterOps.new(_doc).attach(_layer, key, {"radius": float(RADIUS)})
    Bench.composite(_easel)
    assert_eq(_easel.output.format, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, "The bench composites in F32")
    return _column(_easel.output, Vector2i.ZERO)


## The fall from each distance to the next, *values* read outwards.
static func _falls(values: PackedFloat32Array) -> PackedFloat32Array:
    var out := PackedFloat32Array()
    for i in values.size() - 1:
        out.append(values[i] - values[i + 1])
    return out


## Each fall of *falls* no larger than the larger of the two beside it, which
## is the edge of the reach read as no edge at all. *nearest* is the distance
## the first fall starts at, for the message.
func _assert_no_step(falls: PackedFloat32Array, nearest: int, what: String) -> void:
    for i in range(1, falls.size() - 1):
        var beside := maxf(falls[i - 1], falls[i + 1])
        assert_true(
            falls[i] <= beside + TOLERANCE,
            (
                "%s falls %.9f from %d to %d below the stroke, against %.9f and %.9f either side"
                % [what, falls[i], nearest + i, nearest + i + 1, falls[i - 1], falls[i + 1]]
            )
        )


## The column holds paint up to the reach and none past it, so the window does
## straddle the reach's edge.
func _assert_straddles(values: PackedFloat32Array, what: String) -> void:
    var at_reach := values[RADIUS - NEAREST]
    var past := values[RADIUS - NEAREST + 1]
    assert_true(at_reach > 0.0, "%s reaches %d below the stroke, %.9f" % [what, RADIUS, at_reach])
    assert_almost_eq(past, 0.0, 0.000000001, "%s and nothing past it" % what)


func test_apply_ends_a_thin_strokes_blur_without_a_step() -> void:
    var values := _applied(1)
    _assert_straddles(values, "What Apply wrote below a thin stroke")
    _assert_no_step(_falls(values), NEAREST, "What Apply wrote below a thin stroke")


func test_the_attached_blur_ends_a_thin_strokes_blur_without_a_step() -> void:
    var values := _attached(1)
    _assert_straddles(values, "The composite below a thin stroke")
    _assert_no_step(_falls(values), NEAREST, "The composite below a thin stroke")


## Below a broad stroke the column is a sum of the bell's weights, so the bell's
## edge shows in the slope, and the falls read as values are what is read.
func test_apply_ends_a_broad_strokes_blur_without_a_kink() -> void:
    var values := _applied(BROAD)
    _assert_straddles(values, "What Apply wrote below a broad stroke")
    _assert_no_step(_falls(_falls(values)), NEAREST, "The slope of what Apply wrote below a broad stroke")


func test_the_attached_blur_ends_a_broad_strokes_blur_without_a_kink() -> void:
    var values := _attached(BROAD)
    _assert_straddles(values, "The composite below a broad stroke")
    _assert_no_step(_falls(_falls(values)), NEAREST, "The slope of the composite below a broad stroke")
