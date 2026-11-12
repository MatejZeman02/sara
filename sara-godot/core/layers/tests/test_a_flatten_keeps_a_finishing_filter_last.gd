## A flatten takes the records the chain runs up to and
## including the flattened one, in the chain's order, so a finishing filter
## stays last. Brightness/Contrast and the dither are attached in both orders
## on a layer, a group and the root, each is flattened in turn, and the
## composite after the flatten is the composite before it, with the records
## the chain runs after the flattened one still attached. The sentence names
## what the flatten takes, and one undo brings back every record at its place
## and every texel.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Brightness/Contrast is the plain record because its output is off the
## dither's grid, so baking it after the dither, as the array order did, moves
## every texel.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## Real dispatches into real chunks.
const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
const GREY := 0.43
## How far a texel after the flatten may sit from the one before it.
const SAME := 1e-4
## The texels read of the canvas, one in STRIDE across and down.
const STRIDE := 5

var _easel: SaEasel = null
var _document: SaDocument = null
var _ops: SaFilterOps = null
var _dither_key: StringName = &""
var _brighten_key: StringName = &""


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(SaChunk.SIZE * 2, SaChunk.SIZE))
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var registry := SaFilterRegistry.new()
    var dither := SaDitherFilter.new()
    var brighten := SaBrightnessContrastFilter.new()
    registry.register(dither, OWNER)
    registry.register(brighten, OWNER)
    _dither_key = SaFilterRegistry.key_for(OWNER, dither)
    _brighten_key = SaFilterRegistry.key_for(OWNER, brighten)
    _easel.compositor.filter_chain.registry = registry
    _document = _easel.document
    _ops = SaFilterOps.new(_document)


func after_each() -> void:
    _ops = null
    _easel.free()
    _easel = null
    _document = null


## "Layer 1" holding both chunks of the canvas at the grey, opaque.
func _paint() -> SaLayer:
    var layer := _document.get_node("Layer 1") as SaLayer
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0)]:
        layer.get_or_create_chunk(grid_pos).clear(Color(GREY, GREY, GREY, 1.0))
    return layer


## The red channel of the composite at every STRIDE-th texel.
func _composite_samples() -> PackedFloat32Array:
    Bench.composite(_easel)
    var texture := _easel.output
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var out := PackedFloat32Array()
    for y in range(0, texture.size.y, STRIDE):
        for x in range(0, texture.size.x, STRIDE):
            out.append(SaFieldSpec.decode_texel(bytes, texture.format, y * texture.size.x + x).r)
    return out


## How many of *found* sit further than SAME from *expected*.
static func _moved(found: PackedFloat32Array, expected: PackedFloat32Array) -> int:
    var count := 0
    for i in expected.size():
        if absf(found[i] - expected[i]) > SAME:
            count += 1
    return count


## The pair on *node* in the order *dither_first* says, one of them flattened
## as *flatten_dither* says, and the composite, the list, the sentence and the
## undo read against what the chain ran before.
func _case(node: SaLayer, dither_first: bool, flatten_dither: bool, where: String) -> void:
    var dither_values := {"levels": 4, "pattern": "bayer", "strength": 100.0}
    var brighten_values := {"brightness": 37.0, "contrast": 0.0}
    var dither: SaAttachedFilter = null
    var brighten: SaAttachedFilter = null
    if dither_first:
        dither = _ops.attach(node, _dither_key, dither_values)
        brighten = _ops.attach(node, _brighten_key, brighten_values)
    else:
        brighten = _ops.attach(node, _brighten_key, brighten_values)
        dither = _ops.attach(node, _dither_key, dither_values)
    var name := (
        "%s, %s first, flattening the %s"
        % [where, "dither" if dither_first else "brightener", "dither" if flatten_dither else "brightener"]
    )
    var order := _ops.filters_of(node).duplicate()
    var before := _composite_samples()
    var flattened := dither if flatten_dither else brighten

    var said := _ops.flatten_sentence(node, flattened)
    if flatten_dither:
        assert_true(said.contains("2 filters"), "The sentence names both records, %s: %s" % [name, said])
    else:
        assert_true(said.contains("this filter"), "The sentence names the brightener alone, %s: %s" % [name, said])

    assert_true(_ops.flatten(node, flattened), "The flatten runs, %s" % name)
    var left := _ops.filters_of(node)
    if flatten_dither:
        assert_true(left.is_empty(), "Nothing is left attached, %s: %d" % [name, left.size()])
    else:
        assert_eq(left.size(), 1, "One record is left attached, %s" % name)
        assert_true(left.has(dither), "and it is the dither the chain runs after, %s" % name)
    var after := _composite_samples()
    assert_eq(_moved(after, before), 0, "No texel moves at the flatten, %s" % name)

    assert_true(_document.undo(), "The flatten undoes, %s" % name)
    var back := _ops.filters_of(node)
    assert_eq(back.size(), order.size(), "The undo brings back every record, %s" % name)
    for i in mini(back.size(), order.size()):
        assert_true(back[i] == order[i], "each at its place, %s, index %d" % [name, i])
    assert_eq(_moved(_composite_samples(), before), 0, "and every texel, %s" % name)


func test_a_layer_with_the_dither_first_flattens_the_brightener() -> void:
    _case(_paint(), true, false, "layer")


func test_a_layer_with_the_dither_first_flattens_the_dither() -> void:
    _case(_paint(), true, true, "layer")


func test_a_layer_with_the_dither_last_flattens_the_brightener() -> void:
    _case(_paint(), false, false, "layer")


func test_a_layer_with_the_dither_last_flattens_the_dither() -> void:
    _case(_paint(), false, true, "layer")


func test_a_group_with_the_dither_first_flattens_the_brightener() -> void:
    _case(SaLayerOps.new(_document).group_layers([_paint()]), true, false, "group")


func test_a_group_with_the_dither_first_flattens_the_dither() -> void:
    _case(SaLayerOps.new(_document).group_layers([_paint()]), true, true, "group")


func test_a_group_with_the_dither_last_flattens_the_brightener() -> void:
    _case(SaLayerOps.new(_document).group_layers([_paint()]), false, false, "group")


func test_a_group_with_the_dither_last_flattens_the_dither() -> void:
    _case(SaLayerOps.new(_document).group_layers([_paint()]), false, true, "group")


func test_the_root_with_the_dither_first_flattens_the_brightener() -> void:
    _paint()
    _case(null, true, false, "root")


func test_the_root_with_the_dither_first_flattens_the_dither() -> void:
    _paint()
    _case(null, true, true, "root")


func test_the_root_with_the_dither_last_flattens_the_brightener() -> void:
    _paint()
    _case(null, false, false, "root")


func test_the_root_with_the_dither_last_flattens_the_dither() -> void:
    _paint()
    _case(null, false, true, "root")
