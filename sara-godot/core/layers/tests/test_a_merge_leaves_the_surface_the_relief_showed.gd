## A merge leaves the surface the relief showed.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A layer's height is signed, a painter's ruling of 2026-10-02: it stores
## what its strokes changed of the surface beneath it, so a stroke that
## levelled a lower layer's bump holds a negative height there. The view adds
## the heights of the layers that show, each by its opacity and its mask, and
## Merge Down and Flatten mixed two heights by the upper paint's alpha, so a
## merge changed the surface the painter had been looking at and threw away a
## negative height's levelling. They add now, weighted as the view weights.
##
## Each case reads the relief's summed height back before the merge and the
## merged layer's height after it, every texel of the chunk, under a layer of
## positive height and one of negative height, at part opacity and one of
## them masked.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## What the half float and the order the GPU adds in may leave between the
## relief's sum and the merge's, a step of a half float at a few millimetres.
const NEAR := 0.004

var _registries: SaRegistries = null
var _easel: SaEasel = null
var _doc: SaDocument = null


func before_each() -> void:
    _registries = Fixtures.make_registries()
    _easel = SaEasel.create_default(Vector2i(768, 768))
    _easel.compositor.set_registry(_registries.blend_modes)
    _doc = _easel.document


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _registries = null


## Gives *layer* paint and a height over the chunk at the origin, *mm* of the
## texel at each position.
func _raise(layer: SaLayer, mm: Callable) -> void:
    SaHeightOps.new(_doc).gain(layer)
    layer.get_or_create_chunk(Vector2i.ZERO).albedo().clear(Color(0.4, 0.3, 0.2, 1.0))
    var texture := layer.get_or_create_field(Vector2i.ZERO, SaFieldSpec.HEIGHT)
    var bytes := PackedByteArray()
    bytes.resize(texture.size.x * texture.size.y * 2)
    for y in texture.size.y:
        for x in texture.size.x:
            bytes.encode_half((y * texture.size.x + x) * 2, float(mm.call(x, y)))
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, bytes)
    _doc.invalidate_chunks([Vector2i.ZERO])


## Masks *layer* by a half over the left half of the chunk at the origin, and
## whole over the rest.
func _mask_left_half(layer: SaLayer) -> void:
    layer.add_mask()
    var texture := layer.mask.get_or_create(Vector2i.ZERO)
    var bytes := PackedByteArray()
    bytes.resize(texture.size.x * texture.size.y * 4)
    for y in texture.size.y:
        for x in texture.size.x:
            bytes.encode_float((y * texture.size.x + x) * 4, 0.5 if x * 2 < texture.size.x else 1.0)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, bytes)
    _doc.invalidate_chunks([Vector2i.ZERO])


## A bottom layer with a height, a layer of positive height over it at three
## quarters and masked, and one of negative height over that at a half.
func _three_layers() -> Array[SaLayer]:
    var bottom := _doc.active_layer
    _raise(bottom, func(x: int, _y: int) -> float: return 0.5 + float(x % 16) * 0.125)
    var raised := SaLayerOps.new(_doc).add()
    _raise(raised, func(_x: int, y: int) -> float: return 0.5 * float(y % 8))
    raised.opacity = 0.75
    _mask_left_half(raised)
    var levelled := SaLayerOps.new(_doc).add()
    _raise(levelled, func(x: int, _y: int) -> float: return -8.0 if x >= 128 else -0.25)
    levelled.opacity = 0.5
    return [bottom, raised, levelled]


## The relief's summed height over the chunk at the origin, row by row.
func _relief() -> PackedFloat32Array:
    _easel.request_full_composite()
    _easel.process_pending_composite()
    var heights := _easel.relief.heights
    var found := PackedFloat32Array()
    if heights == null:
        return found
    found.resize(SaChunk.SIZE * SaChunk.SIZE)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(heights.rid, 0)
    for y in SaChunk.SIZE:
        for x in SaChunk.SIZE:
            found[y * SaChunk.SIZE + x] = bytes.decode_half((y * heights.size.x + x) * 2)
    return found


## *layer*'s own height over the chunk at the origin, row by row.
func _own(layer: SaLayer) -> PackedFloat32Array:
    var found := PackedFloat32Array()
    var texture := layer.get_field(Vector2i.ZERO, SaFieldSpec.HEIGHT)
    if texture == null:
        return found
    found.resize(SaChunk.SIZE * SaChunk.SIZE)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    for y in SaChunk.SIZE:
        for x in SaChunk.SIZE:
            found[y * SaChunk.SIZE + x] = bytes.decode_half((y * texture.size.x + x) * 2)
    return found


## Holds every texel of *found* within [constant NEAR] of *wanted*, naming the
## first that is not and how many are not.
func _assert_every_texel(found: PackedFloat32Array, wanted: PackedFloat32Array, what: String) -> void:
    assert_eq(found.size(), wanted.size(), "%s reads a whole chunk" % what)
    if found.size() != wanted.size():
        return
    var off := 0
    var first := ""
    for i in wanted.size():
        if absf(found[i] - wanted[i]) > NEAR:
            if off == 0:
                var at := Vector2i(i % SaChunk.SIZE, floori(float(i) / SaChunk.SIZE))
                first = " first at %s, %.4f against %.4f" % [at, found[i], wanted[i]]
            off += 1
    assert_eq(off, 0, "%s at every texel%s" % [what, first])


func test_two_merges_down_leave_the_sum_the_relief_showed() -> void:
    var layers := _three_layers()
    var bottom := layers[0]
    var shown := _relief()
    assert_almost_eq(shown[200], 1.5 - 4.0, NEAR, "The relief adds the negative height, so the surface stands below nought")
    var ops := SaLayerOps.new(_doc)
    assert_true(ops.merge_down(layers[1]), "The raised layer merges down")
    assert_true(ops.merge_down(layers[2]), "and the levelled one after it")
    var merged := _own(bottom)
    _assert_every_texel(merged, shown, "The merged height is the sum the relief showed")
    assert_almost_eq(merged[200], -2.5, NEAR, "a negative height where the levelling went deeper than the paint")
    _assert_every_texel(_relief(), shown, "and the relief shows the surface it showed")
    assert_true(_doc.undo(), "Undo takes the second merge back")
    assert_true(_doc.undo(), "and the first")
    assert_almost_eq(_own(bottom)[200], 1.5, NEAR, "and the bottom layer's own height with them")


func test_a_flatten_leaves_the_sum_the_relief_showed() -> void:
    var layers := _three_layers()
    # The bottom layer at part opacity as well, since a flatten adds every
    # layer onto bare and its own height is weighted like the rest.
    layers[0].opacity = 0.8
    var shown := _relief()
    assert_true(SaLayerOps.new(_doc).flatten(), "The stack flattens")
    var flat := SaLayerOps.new(_doc).layers()[0]
    _assert_every_texel(_own(flat), shown, "The flattened height is the sum the relief showed")
    _assert_every_texel(_relief(), shown, "and the relief shows the surface it showed")


func test_a_hidden_layer_adds_nothing_to_a_flatten() -> void:
    var layers := _three_layers()
    layers[2].visible = false
    var shown := _relief()
    assert_true(SaLayerOps.new(_doc).flatten(), "The stack flattens")
    var flat := SaLayerOps.new(_doc).layers()[0]
    _assert_every_texel(_own(flat), shown, "The hidden negative height is left out, as the relief left it")
