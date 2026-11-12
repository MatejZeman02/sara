## A stroke reads the surface beneath its layer.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The maintainers' ruling of 2026-10-02: "A stroke reads every visible layer
## below its own, composited, the ground included. The layers above it are not
## affected, only the ones below." `SaStrokeHeights.beneath` answers that
## surface over a chunk, which a stroke's dab binds beside the layer's own
## height, and no engine reads it.
##
## The surface is held against the relief's own sum with the painted layer and
## everything above it hidden, every texel of the chunk, over a paper whose
## tooth the relief adds by its `raise_tooth` rule. A layer below the painted
## one is hidden throughout, and a layer above it stands high enough that its
## height would show in any texel it reached.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## What the half float may leave between two sums of the same heights.
const NEAR := 0.002

var _registries: SaRegistries = null
var _easel: SaEasel = null
var _doc: SaDocument = null


func before_each() -> void:
    _registries = Fixtures.make_registries()
    _easel = SaEasel.create_default(Vector2i(768, 768))
    _easel.compositor.set_registry(_registries.blend_modes)
    _doc = _easel.document
    _easel.process_pending_composite()


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _registries = null


## Gives *layer* a height of *mm* at each texel of the chunk at *grid_pos*.
func _raise(layer: SaLayer, grid_pos: Vector2i, mm: Callable) -> void:
    SaHeightOps.new(_doc).gain(layer)
    var texture := layer.get_or_create_field(grid_pos, SaFieldSpec.HEIGHT)
    var bytes := PackedByteArray()
    bytes.resize(texture.size.x * texture.size.y * 2)
    for y in texture.size.y:
        for x in texture.size.x:
            bytes.encode_half((y * texture.size.x + x) * 2, float(mm.call(x, y)))
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, bytes)
    _doc.invalidate_chunks([grid_pos])


## A paper under the paint when *on_paper*, then a layer of height at a half,
## a hidden layer of height, the painted layer with a height of its own, and a
## high layer above it, answered as [paper, below, hidden, painted, above],
## the paper null when there is none. The painted layer is the active one.
func _stack(on_paper: bool) -> Array[SaLayer]:
    var ops := SaLayerOps.new(_doc)
    var below := _doc.active_layer
    var paper: SaLayer = ops.add(&"paper", _registries.layer_types) if on_paper else null
    _raise(below, Vector2i.ZERO, func(x: int, y: int) -> float: return 0.0625 * float((x + y) % 12))
    below.opacity = 0.5
    _doc.set_active_layer(below)
    var hidden := ops.add()
    _raise(hidden, Vector2i.ZERO, func(_x: int, _y: int) -> float: return 3.0)
    hidden.visible = false
    var painted := ops.add()
    _raise(painted, Vector2i.ZERO, func(_x: int, _y: int) -> float: return 2.0)
    var above := ops.add()
    _raise(above, Vector2i.ZERO, func(_x: int, _y: int) -> float: return 5.0)
    _doc.set_active_layer(painted)
    return [paper, below, hidden, painted, above]


## The relief's summed height over the chunk at *grid_pos*, row by row.
func _relief(grid_pos: Vector2i) -> PackedFloat32Array:
    _easel.request_full_composite()
    _easel.process_pending_composite()
    var heights := _easel.relief.heights
    var found := PackedFloat32Array()
    if heights == null:
        return found
    found.resize(SaChunk.SIZE * SaChunk.SIZE)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(heights.rid, 0)
    var corner := grid_pos * SaChunk.SIZE
    for y in SaChunk.SIZE:
        for x in SaChunk.SIZE:
            found[y * SaChunk.SIZE + x] = bytes.decode_half(((corner.y + y) * heights.size.x + corner.x + x) * 2)
    return found


## Every texel of *texture*, row by row.
func _read(texture: SaTexture) -> PackedFloat32Array:
    var found := PackedFloat32Array()
    if texture == null:
        return found
    found.resize(texture.size.x * texture.size.y)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    for i in found.size():
        found[i] = bytes.decode_half(i * 2)
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


func test_the_surface_beneath_is_the_reliefs_sum_of_the_layers_below_with_the_papers_tooth() -> void:
    var stack := _stack(true)
    var painted := stack[3]
    var above := stack[4]
    var heights := SaStrokeHeights.new(_doc, painted)
    var surface := heights.beneath(Vector2i.ZERO)
    assert_not_null(surface, "The stroke is handed the surface beneath its layer")
    painted.visible = false
    above.visible = false
    var wanted := _relief(Vector2i.ZERO)
    _assert_every_texel(_read(surface), wanted, "It is what the relief sums of the layers below, the paper's tooth included")
    var found := _read(surface)
    var tooth := 0.0
    for y in SaChunk.SIZE:
        for x in SaChunk.SIZE:
            tooth += found[y * SaChunk.SIZE + x] - 0.5 * 0.0625 * float((x + y) % 12)
    assert_true(tooth / found.size() > 0.005, "The paper's tooth stands over the layer below on the whole")
    assert_true(found.size() > 0 and found[5] < 3.0, "and the hidden layer's height is left out")


func test_a_layer_above_and_the_painted_layers_own_height_are_left_out() -> void:
    var stack := _stack(false)
    var painted := stack[3]
    var surface := _read(SaStrokeHeights.new(_doc, painted).beneath(Vector2i.ZERO))
    var everything := _relief(Vector2i.ZERO)
    var over := everything[5] - surface[5]
    assert_almost_eq(over, 2.0 + 5.0, 0.01, "The relief stands the painted and the high layer above the surface beneath")
    stack[2].visible = true
    var shown := _read(SaStrokeHeights.new(_doc, painted).beneath(Vector2i.ZERO))
    assert_almost_eq(shown[5] - surface[5], 3.0, 0.01, "and once the hidden layer shows, its height is under the stroke as well")


func test_the_surface_is_summed_once_a_chunk_for_the_stroke() -> void:
    var stack := _stack(false)
    var heights := SaStrokeHeights.new(_doc, stack[3])
    var first := heights.beneath(Vector2i.ZERO)
    _raise(stack[1], Vector2i.ZERO, func(_x: int, _y: int) -> float: return 9.0)
    assert_true(heights.beneath(Vector2i.ZERO) == first, "A second ask in the same stroke answers the surface the first summed")


func test_where_only_the_paper_lies_below_the_surface_is_its_tooth() -> void:
    var stack := _stack(true)
    var grid := Vector2i(1, 1)
    var surface := SaStrokeHeights.new(_doc, stack[3]).beneath(grid)
    stack[3].visible = false
    stack[4].visible = false
    _assert_every_texel(_read(surface), _relief(grid), "A chunk no layer below holds height in is the paper's tooth alone")


func test_a_layer_with_nothing_beneath_it_stands_on_nought() -> void:
    var layer := _doc.active_layer
    _raise(layer, Vector2i.ZERO, func(_x: int, _y: int) -> float: return 1.0)
    var found := _read(SaStrokeHeights.new(_doc, layer).beneath(Vector2i.ZERO))
    var bare := PackedFloat32Array()
    bare.resize(found.size())
    _assert_every_texel(found, bare, "With no paper and no layer of height below, the surface beneath is nought")
