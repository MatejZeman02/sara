## A merge bakes both layers' opacity into the paint and leaves the result at
## 100 per cent.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The merged layer kept the lower layer's opacity, so the upper paint showed
## at that opacity too once it was in. The maintainers' pick of 2026-10-11 was
## "Bake both, result 100%": the lower layer's opacity goes into its paint
## before the uppers do, and the merged layer reads 100 per cent with the
## canvas as it was. Each case reads the easel's output before the merge,
## after it, after one undo and after the redo.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const GROUND := Color(0.1, 0.3, 0.7, 1.0)
const LOWER := Color(0.8, 0.2, 0.1, 1.0)
const MIDDLE := Color(0.9, 0.8, 0.1, 0.7)
const UPPER := Color(0.2, 0.9, 0.4, 0.6)
## One point in each chunk of the picture.
const POINTS: Array[Vector2i] = [Vector2i(40, 10), Vector2i(300, 200)]
## What the float round trip through the kernels may leave on a texel.
const NEAR := 0.01

var _easel: SaEasel
var _doc: SaDocument
var _ops: SaLayerOps


func before_each() -> void:
    _easel = Bench.easel(Vector2i(512, 256))
    _doc = _easel.document
    _ops = SaLayerOps.new(_doc)
    _doc.fill_layer(GROUND, _ops.layers()[0])


func after_each() -> void:
    _ops = null
    _doc = null
    _easel.free()
    _easel = null


## A layer filled with *color* at *opacity* above the active one.
func _painted(color: Color, opacity: float) -> SaLayer:
    var layer := _ops.add()
    _doc.fill_layer(color, layer)
    layer.opacity = opacity
    return layer


func _output() -> Array:
    Bench.composite(_easel)
    var found: Array = []
    for at in POINTS:
        found.append(Bench.texel(_easel.output, at))
    return found


func _same(before: Array, after: Array, what: String) -> void:
    for i in before.size():
        var was: Color = before[i]
        var now: Color = after[i]
        var moved := maxf(maxf(absf(was.r - now.r), absf(was.g - now.g)), maxf(absf(was.b - now.b), absf(was.a - now.a)))
        assert_true(moved < NEAR, "%s, point %d: %s became %s" % [what, i, was, now])


## Merges *top* down, or *picked* into the lowest of them, and holds the
## canvas and the merged layer's opacity through the merge, one undo and the
## redo. *opacities* are the layers' own, bottom first, which undo puts back.
func _merges_as_shown(top: SaLayer, picked: Array, layers: Array[SaLayer]) -> void:
    var opacities: Array[float] = []
    for layer in layers:
        opacities.append(layer.opacity)
    var lower := layers[0]
    var before := _output()
    assert_true(_ops.merge_down(top, picked), "The merge runs")
    assert_almost_eq(lower.opacity, 1.0, 0.0001, "The merged layer reads 100 per cent")
    _same(before, _output(), "and the canvas looks as it did")
    assert_true(_doc.undo(), "One undo")
    for i in layers.size():
        assert_eq(layers[i].get_parent(), _doc, "puts layer %d back" % i)
        assert_almost_eq(layers[i].opacity, opacities[i], 0.0001, "with its opacity, layer %d" % i)
    _same(before, _output(), "with the picture it had")
    assert_true(_doc.redo(), "Redo")
    assert_almost_eq(lower.opacity, 1.0, 0.0001, "merges to 100 per cent again")
    _same(before, _output(), "and to the same picture")


func test_a_full_layer_onto_a_part_one_reads_100_per_cent() -> void:
    var lower := _painted(LOWER, 0.4)
    var upper := _painted(UPPER, 1.0)
    _merges_as_shown(upper, [], [lower, upper])


func test_a_part_layer_onto_a_full_one_reads_100_per_cent() -> void:
    var lower := _painted(LOWER, 1.0)
    var upper := _painted(UPPER, 0.4)
    _merges_as_shown(upper, [], [lower, upper])


func test_three_picked_rows_merge_into_the_lowest_at_100_per_cent() -> void:
    var lower := _painted(LOWER, 0.4)
    var middle := _painted(MIDDLE, 0.7)
    var upper := _painted(UPPER, 0.5)
    _merges_as_shown(upper, [lower, middle, upper], [lower, middle, upper])


## The lower layer's mode stays its own, and its opacity baked into its alpha
## draws through that mode as the opacity did, since the kernels take the
## opacity as a factor on the alpha for every mode.
func test_a_multiply_lower_layer_keeps_its_mode_and_its_look() -> void:
    var lower := _painted(LOWER, 0.4)
    _ops.set_blend_mode(lower, &"multiply")
    var upper := _painted(UPPER, 1.0)
    upper.visible = false
    _merges_as_shown(upper, [], [lower, upper])
    assert_eq(lower.get_blend_mode_name(), &"multiply", "The merged layer is still Multiply")


## The relief weights a layer's height by its opacity, so the bake weights the
## lower layer's height the same way and the merged surface is the one shown.
func test_the_lower_layers_height_is_weighted_by_its_opacity() -> void:
    var lower := _painted(LOWER, 0.5)
    var upper := _painted(UPPER, 1.0)
    for pair: Array in [[lower, 2.0], [upper, 1.0]]:
        var layer: SaLayer = pair[0]
        SaHeightOps.new(_doc).gain(layer)
        for grid_pos: Vector2i in layer.chunks:
            layer.get_or_create_field(grid_pos, SaFieldSpec.HEIGHT).clear(Color(pair[1], 0, 0, 0))
    _doc.invalidate_chunks([Vector2i.ZERO, Vector2i(1, 0)])
    assert_true(_ops.merge_down(upper), "The merge runs")
    var texture := lower.get_field(Vector2i.ZERO, SaFieldSpec.HEIGHT)
    assert_not_null(texture, "The merged layer holds a height")
    if texture == null:
        return
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    assert_almost_eq(bytes.decode_half(0), 2.0 * 0.5 + 1.0, 0.004, "its own height at half and the upper's whole")
