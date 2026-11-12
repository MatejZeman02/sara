## Vignette darkens the picture towards the document's edges, in
## light, measured from the document's centre. A flat layer comes out brightest
## in the middle, darker at the middle of an edge and darkest in a corner, a
## layer painted in one corner chunk alone is darkened as that chunk of a whole
## layer is, and a negative amount brightens the edges.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## Real dispatches into real chunks.
const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
const GREY := 0.5
## A document two chunks wide and high, so a corner chunk lies far from the centre.
const CHUNKS := 2
## The texels read of a chunk, one in STRIDE across and down, which is every one.
const STRIDE := 1
const SETTINGS := {"amount": 80.0, "start": 0.0, "softness": 100.0}

var _easel: SaEasel = null
var _document: SaDocument = null
var _key: StringName = &""


func before_each() -> void:
    _make_easel()


func after_each() -> void:
    _easel.free()
    _easel = null
    _document = null


func _make_easel() -> void:
    _easel = SaEasel.create_default(Vector2i(SaChunk.SIZE, SaChunk.SIZE) * CHUNKS)
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var registry := SaFilterRegistry.new()
    var vignette := SaVignetteFilter.new()
    registry.register(vignette, OWNER)
    _key = SaFilterRegistry.key_for(OWNER, vignette)
    _easel.compositor.filter_chain.registry = registry
    _document = _easel.document
    _document.color_space = SaColorSpace.linear_srgb()


## "Layer 1" with the chunks of *grid* at *value*, opaque.
func _paint(grid: Array[Vector2i], value: float) -> SaLayer:
    var layer := _document.get_node("Layer 1") as SaLayer
    for grid_pos: Vector2i in grid:
        layer.get_or_create_chunk(grid_pos).clear(Color(value, value, value, 1.0))
    return layer


func _all_chunks() -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    for y in CHUNKS:
        for x in CHUNKS:
            out.append(Vector2i(x, y))
    return out


## The composite as bytes, read back once.
func _read() -> Array:
    Bench.composite(_easel)
    var texture := _easel.output
    return [GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0), texture]


static func _red(read: Array, at: Vector2i) -> float:
    var texture := read[1] as SaTexture
    return SaFieldSpec.decode_texel(read[0], texture.format, at.y * texture.size.x + at.x).r


## The document pixel the fractions *across* and *down* a canvas of *size*
## point at, rounded down, so that no line divides one integer by another.
static func _spot(size: Vector2i, across: float, down: float) -> Vector2i:
    return Vector2i(floori(size.x * across), floori(size.y * down))


## What the kernel's falloff gives at document pixel *at* of a canvas of *size*,
## in doubles here and floats there.
static func _gain(at: Vector2i, size: Vector2i, settings: Dictionary) -> float:
    var centre := Vector2(size) * 0.5
    var d := (Vector2(at) + Vector2(0.5, 0.5) - centre).length() / centre.length()
    var start := float(settings["start"]) / 100.0
    var far := start + maxf(float(settings["softness"]) / 100.0, 0.01) * (1.0 - start)
    var t := smoothstep(start, maxf(far, start + 0.0001), d)
    return 1.0 - float(settings["amount"]) / 100.0 * t


func test_the_centre_is_unchanged_and_the_edges_fall_away() -> void:
    var layer := _paint(_all_chunks(), GREY)
    SaFilterOps.new(_document).attach(layer, _key, SETTINGS)
    var read := _read()
    var size := _document.canvas_size
    var centre := _red(read, _spot(size, 0.5, 0.5))
    var edge := _red(read, _spot(size, 0.0, 0.5))
    var corner := _red(read, Vector2i(0, 0))
    assert_true(absf(centre - GREY) < 1e-3, "The centre is unchanged: %f" % centre)
    assert_true(edge < centre, "The middle of an edge is darker than the centre: %f against %f" % [edge, centre])
    assert_true(corner < edge, "and a corner is darker than that: %f against %f" % [corner, edge])
    var spots: Array[Vector2i] = [Vector2i(0, 0), _spot(size, 0.0, 0.5), _spot(size, 0.25, 0.25), size - Vector2i.ONE]
    for at in spots:
        var wanted := GREY * _gain(at, size, SETTINGS)
        var got := _red(read, at)
        assert_true(absf(got - wanted) < 1e-3, "%s is the light scaled by the gain: %f against %f" % [at, got, wanted])


func test_a_negative_amount_brightens_the_edges() -> void:
    var layer := _paint(_all_chunks(), GREY)
    SaFilterOps.new(_document).attach(layer, _key, {"amount": -50.0, "start": 0.0, "softness": 100.0})
    var read := _read()
    var size := _document.canvas_size
    assert_true(absf(_red(read, _spot(size, 0.5, 0.5)) - GREY) < 1e-3, "The centre is unchanged")
    var corner := _red(read, Vector2i(0, 0))
    assert_true(corner > GREY * 1.4, "and a corner is brighter than the light it had: %f" % corner)


func test_start_keeps_the_middle_clear() -> void:
    var layer := _paint(_all_chunks(), GREY)
    SaFilterOps.new(_document).attach(layer, _key, {"amount": 100.0, "start": 60.0, "softness": 50.0})
    var read := _read()
    var size := _document.canvas_size
    var inside := _red(read, _spot(size, 0.5, 0.25))
    var corner := _red(read, Vector2i(0, 0))
    assert_true(absf(inside - GREY) < 1e-3, "Inside the start the light is untouched")
    assert_true(corner < 1e-3, "and a corner at full amount is black: %f" % corner)


func test_a_corner_chunk_alone_is_darkened_as_the_whole_layers_chunk_is() -> void:
    var corner := Vector2i(CHUNKS - 1, CHUNKS - 1)
    var alone: Array[Vector2i] = [corner]
    SaFilterOps.new(_document).attach(_paint(alone, GREY), _key, SETTINGS)
    var attached := _read()
    var from := corner * SaChunk.SIZE
    var attached_values: Array[float] = []
    for y in range(0, SaChunk.SIZE, STRIDE):
        for x in range(0, SaChunk.SIZE, STRIDE):
            attached_values.append(_red(attached, from + Vector2i(x, y)))
    _easel.free()
    _make_easel()
    var whole := _paint(_all_chunks(), GREY)
    assert_true(SaFilterOps.new(_document).apply_once(whole, _key, SETTINGS, "Vignette"), "The whole layer bakes")
    var baked := _read()
    var worst := 0.0
    var index := 0
    for y in range(0, SaChunk.SIZE, STRIDE):
        for x in range(0, SaChunk.SIZE, STRIDE):
            worst = maxf(worst, absf(attached_values[index] - _red(baked, from + Vector2i(x, y))))
            index += 1
    assert_true(worst < 1e-4, "The corner chunk of the attached layer is the baked layer's chunk, off by %f" % worst)
    var last: float = attached_values[attached_values.size() - 1]
    assert_true(last < GREY - 0.05, "and its far end is darker than the light it had: %f" % last)


func test_an_oklab_document_scales_its_coordinates_by_the_cube_root_of_the_gain() -> void:
    _document.color_space = SaColorSpace.oklab()
    var layer := _paint(_all_chunks(), 0.0)
    for grid_pos in _all_chunks():
        layer.get_or_create_chunk(grid_pos).clear(Color(0.6, 0.0, 0.0, 1.0))
    SaFilterOps.new(_document).attach(layer, _key, SETTINGS)
    var read := _read()
    var size := _document.canvas_size
    var wanted := 0.6 * pow(_gain(Vector2i(0, 0), size, SETTINGS), 1.0 / 3.0)
    var corner := _red(read, Vector2i(0, 0))
    assert_true(absf(corner - wanted) < 2e-3, "L at a corner is the cube root of the gain: %f against %f" % [corner, wanted])
    assert_true(absf(_red(read, _spot(size, 0.5, 0.5)) - 0.6) < 1e-3, "and L at the centre is unchanged")


func test_it_is_listed_under_stylize_and_found_by_its_name() -> void:
    var filter := SaVignetteFilter.new()
    assert_eq(filter.family(), &"stylize", "It is a Stylize filter")
    assert_eq(filter.title(), "Vignette", "called Vignette")
    assert_false(filter.finishes(), "and it runs where it stands in a chain")
