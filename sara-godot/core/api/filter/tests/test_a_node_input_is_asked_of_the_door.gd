## A node's input is asked of the door, `SaNodeInput`, so a
## module that equalizes from it names none of the compositor, the layer stack
## or the tree walk.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Two paint layers hold one chunk each, a chunk apart, and the background is
## emptied. A paint layer's input is its own chunks, a group of both is their
## composite over transparent, and the root is every chunk any layer holds. The
## adjustment layer's backdrop is covered by the base module's Levels suite of
## the adjustment layer, which asks the same door.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const RED := Color(1.0, 0.0, 0.0, 1.0)
const BLUE := Color(0.0, 0.0, 1.0, 1.0)
const LEFT := Vector2i(0, 0)
const RIGHT := Vector2i(2, 0)
## A texel well inside a chunk.
const PROBE := Vector2i(40, 40)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _left: SaLayer = null
var _right: SaLayer = null


func before_each() -> void:
    _easel = Bench.easel(Vector2i(3 * SaChunk.SIZE, SaChunk.SIZE))
    _doc = _easel.document
    var background := _doc.get_node("Background") as SaLayer
    for grid_pos: Vector2i in background.chunks.keys():
        background.chunks.erase(grid_pos)
    _left = _doc.get_node("Layer 1") as SaLayer
    _left.get_or_create_chunk(LEFT).clear(RED)
    _right = SaLayerOps.new(_doc).add()
    _right.get_or_create_chunk(RIGHT).clear(BLUE)
    _doc.update_caches()


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _left = null
    _right = null


func _sorted(positions: Array[Vector2i]) -> Array[Vector2i]:
    var out := positions.duplicate()
    out.sort()
    return out


func test_a_paint_layer_hands_its_own_chunks() -> void:
    var input := SaNodeInput.new(_doc, _left)
    assert_eq(input.positions(), [LEFT] as Array[Vector2i], "A paint layer's input is where it holds paint")
    assert_eq(input.at(LEFT), _left.chunks[LEFT].albedo(), "handed as the chunk's own albedo, nothing composited")
    assert_eq(input.at(RIGHT), null, "and nothing where it holds none")


func test_a_group_hands_its_members_composited() -> void:
    var group := SaLayerOps.new(_doc).group_layers([_left, _right])
    _doc.update_caches()
    var input := SaNodeInput.new(_doc, group)
    assert_eq(_sorted(input.positions()), [LEFT, RIGHT] as Array[Vector2i], "A group's input covers every member's chunks")
    assert_true(Bench.texel(input.at(LEFT), PROBE).is_equal_approx(RED), "the left member where it paints")
    assert_true(Bench.texel(input.at(RIGHT), PROBE).is_equal_approx(BLUE), "and the right one where it does")


func test_the_root_hands_every_layer() -> void:
    var input := SaNodeInput.new(_doc, null)
    assert_eq(_sorted(input.positions()), [LEFT, RIGHT] as Array[Vector2i], "The root's input covers every layer's chunks")
    assert_true(Bench.texel(input.at(RIGHT), PROBE).is_equal_approx(BLUE), "composited over transparent")
    assert_eq(Bench.texel(input.at(Vector2i(1, 0)), PROBE).a, 0.0, "and transparent where nothing paints")


func test_a_record_is_found_on_its_node() -> void:
    var on_layer := SaFilterOps.new(_doc).attach(_left, &"missing.filter", {})
    assert_eq(SaNodeInput.node_of(_doc, on_layer), [true, _left], "A record on a layer hangs on that layer")
    assert_eq(SaNodeInput.node_of(_doc, SaAttachedFilter.new()), [false, null], "and a stray record hangs nowhere")
    assert_eq(SaNodeInput.node_of(null, on_layer), [false, null], "and nothing is found without a document")
