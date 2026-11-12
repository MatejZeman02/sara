## The live stroke's scratch holds its composite as far as the layer's filters
## read it, and not over the dirty region alone. Two chunks of
## the active layer, red and green, the box blur attached at radius 8, and a
## stroke buffer with a chunk over each, so both go through a pooled scratch. A
## whole composite leaves the red chunk in the pool's first slot. Then the green
## chunk alone is composited over a small region, which hands it that slot: the
## blur reads eight texels past the region, and before the scratch held them those were the red the
## slot still held, mixed into the band along the region's edge.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const BoxBlurFilter = preload("res://modules/sara-base-modules/base/usual/box_blur_filter.gd")

const REQUIRES_GPU := true

const MODULE_DIR := "res://modules/sara-base-modules/base"
const KEY: StringName = &"sara-base-modules.box_blur"
const RADIUS := 8
const RED := Color(1.0, 0.0, 0.0, 1.0)
const GREEN := Color(0.0, 1.0, 0.0, 1.0)
const CLEAR := Color(0.0, 0.0, 0.0, 0.0)
const REGION := Rect2i(96, 96, 64, 64)

var _easel: SaEasel = null
var _doc: SaDocument = null


func before_each() -> void:
    _easel = Bench.easel(Vector2i(2 * SaChunk.SIZE, SaChunk.SIZE))
    _doc = _easel.document
    ModuleLoader.module_dirs[&"sara-base-modules"] = MODULE_DIR
    var blur := BoxBlurFilter.new()
    _easel.compositor.filter_chain.registry.register(blur, &"sara-base-modules")
    var layer := _doc.get_node("Background") as SaLayer
    for grid_pos: Vector2i in layer.chunks.keys():
        layer.chunks.erase(grid_pos)
    layer.get_or_create_chunk(Vector2i(0, 0)).clear(RED)
    layer.get_or_create_chunk(Vector2i(1, 0)).clear(GREEN)
    _doc.set_active_layer(layer)
    SaFilterOps.new(_doc).attach(layer, KEY, {"radius": RADIUS})
    # A stroke that has painted nothing yet still sends both chunks through the
    # stroke branch, which is all this needs of one.
    _doc.stroke_layer.get_or_create_chunk(Vector2i(0, 0)).clear(CLEAR)
    _doc.stroke_layer.get_or_create_chunk(Vector2i(1, 0)).clear(CLEAR)


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null


func test_a_region_of_one_chunk_reads_nothing_of_the_chunk_the_slot_held() -> void:
    Bench.composite(_easel)
    var whole := Rect2(Vector2.ZERO, Vector2(_doc.canvas_size))
    _easel.compositor.composite_chunks(_easel.output, _doc, {Vector2i(1, 0): REGION}, whole)
    for at: Vector2i in [REGION.position, REGION.end - Vector2i.ONE, REGION.get_center()]:
        var read := Bench.texel(_easel.output, at + Vector2i(SaChunk.SIZE, 0))
        assert_almost_eq(read.g, 1.0, 0.01, "The green chunk is still green at %s, %s" % [at, read])
        assert_almost_eq(read.r, 0.0, 0.01, "with none of the red the scratch held before it, %s" % read)
