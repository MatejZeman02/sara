## A live stroke under a filter that reads the whole layer shows, every float of
## it, the picture it showed when the stroke's halo was filled over every chunk
## of the layer. The halo holds the layer and the stroke
## composited together only where the stroke holds a chunk now, and the gather
## the pass reads is the layer's own with those laid in, which took the first
## frame of a stroke over a 4000 by 3000 photograph from 60 ms to under 40.
##
## The picture before the change is made here the way the change cannot tell
## apart from it: the stroke buffer holds a transparent chunk at every position
## the layer holds, so the halo is filled over every one of them, exactly as it
## was for every stroke before. The same stroke without them has to match it
## byte for byte, under Lens Correction, Kaleidoscope and Mirror.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Kaleidoscope = preload("res://modules/sara-base-modules/kaleidoscope/kaleidoscope.gd")
const MirrorFilter = preload("res://modules/sara-base-modules/base/usual/mirror_filter.gd")

const REQUIRES_GPU := true

const BASE := &"sara-base-modules"
const CHUNKS := Vector2i(6, 4)
## Where the stroke's buffer holds paint, and a second chunk it reaches later.
const STROKE := Vector2i(1, 1)
const LATER := Vector2i(2, 1)
const PAINT := Color(0.95, 0.75, 0.1, 0.6)
## Lens Correction at the most it takes, whose corner moves 277 pixels on this
## canvas, past what a halo pads, so its pass reads the whole layer.
const LENS_AMOUNT := 30.0

var _easel: SaEasel = null


func after_each() -> void:
    if _easel != null:
        _easel.free()
    _easel = null


## An easel of [const CHUNKS] whose Background holds a colour of its own in
## every chunk, the last one half transparent, with *which*'s filter
## attached and the layer active, composited at rest once so the layer's own
## gather is kept, as it is when a painter starts a stroke.
func _bench(which: String) -> SaEasel:
    var made := Bench.easel(CHUNKS * SaChunk.SIZE)
    var doc := made.document
    var registry := made.compositor.filter_chain.registry
    var key: StringName = &""
    var values := {}
    match which:
        "lens":
            var lens := SaLensCorrectionFilter.new()
            registry.register(lens, BASE)
            key = SaFilterRegistry.key_for(BASE, lens)
            values = {"amount": LENS_AMOUNT, "crop_to_fill": false}
        "kaleidoscope":
            ModuleLoader.module_dirs[&"kaleidoscope"] = "res://modules/sara-base-modules/kaleidoscope"
            registry.register(Kaleidoscope.new(), &"kaleidoscope")
            key = &"kaleidoscope.kaleidoscope"
            values = {"mirrors": 6, "angle": 20.0, "centre_x": 40, "centre_y": 55}
        "mirror":
            var mirror := MirrorFilter.new()
            registry.register(mirror, BASE)
            key = SaFilterRegistry.key_for(BASE, mirror)
            values = {"point_x": 45.0, "point_y": 40.0, "angle": 30.0}
    var layer := doc.get_node("Background") as SaLayer
    for grid_pos: Vector2i in layer.chunks.keys():
        layer.chunks.erase(grid_pos)
    for y in CHUNKS.y:
        for x in CHUNKS.x:
            var alpha := 0.5 if Vector2i(x, y) == CHUNKS - Vector2i.ONE else 1.0
            layer.get_or_create_chunk(Vector2i(x, y)).clear(Color(0.13 * x + 0.1, 0.2 * y + 0.15, 0.9 - 0.13 * x, alpha))
    doc.set_active_layer(layer)
    SaFilterOps.new(doc).attach(layer, key, values)
    Bench.composite(made)
    return made


## Paints [const PAINT] into the stroke buffer at *at*, and with *everywhere* a
## transparent chunk at every other position the layer holds, then redraws what
## a dab there redraws, the way a stroke's frame does.
func _paint(made: SaEasel, at: Vector2i, everywhere: bool) -> void:
    var doc := made.document
    var layer := doc.active_layer
    doc.stroke_layer.get_or_create_chunk(at).clear(PAINT)
    if everywhere:
        for grid_pos: Vector2i in layer.chunks:
            if doc.stroke_layer.get_field(grid_pos) == null:
                doc.stroke_layer.get_or_create_chunk(grid_pos).clear(Color(0.0, 0.0, 0.0, 0.0))
    doc.stroke_layer.visible = true
    doc.invalidate_chunk_regions({at: Rect2i(Vector2i.ZERO, Vector2i(SaChunk.SIZE, SaChunk.SIZE))})
    made.process_pending_composite()


static func _bytes(texture: SaTexture) -> PackedByteArray:
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)


## How many floats of two pictures of one size differ, and the first texel that does.
static func _differing(one: PackedByteArray, other: PackedByteArray, width: int) -> String:
    if one.size() != other.size():
        return "sizes %d and %d" % [one.size(), other.size()]
    var one_floats := one.to_float32_array()
    var other_floats := other.to_float32_array()
    var count := 0
    var first := -1
    for i in one_floats.size():
        if one_floats[i] != other_floats[i]:
            count += 1
            if first < 0:
                @warning_ignore("integer_division")
                first = i / 4
    @warning_ignore("integer_division")
    return "%d floats, the first at texel (%d, %d)" % [count, first % width, first / width] if count > 0 else "none"


func test_each_filter_reads_the_whole_layer_here() -> void:
    for which: String in ["lens", "kaleidoscope", "mirror"]:
        _easel = _bench(which)
        assert_true(SaNeighbourhoodPass.reads_whole(_easel.document.active_layer.filters), "%s reads the whole layer" % which)
        _easel.free()
        _easel = null


## The stroke's first frame and the frame after it reaches one more chunk, each
## against the same frames with the halo filled over every chunk.
func test_a_live_stroke_shows_what_a_halo_over_every_chunk_showed() -> void:
    for which: String in ["lens", "kaleidoscope", "mirror"]:
        _easel = _bench(which)
        _paint(_easel, STROKE, true)
        var before_first := _bytes(_easel.output)
        _paint(_easel, LATER, true)
        var before_later := _bytes(_easel.output)
        var width := _easel.output.size.x
        _easel.free()
        _easel = _bench(which)
        _paint(_easel, STROKE, false)
        var first := _bytes(_easel.output)
        _paint(_easel, LATER, false)
        var later := _bytes(_easel.output)
        assert_true(first == before_first, "%s, the first frame: %s differ" % [which, _differing(first, before_first, width)])
        assert_true(later == before_later, "%s, a later frame: %s differ" % [which, _differing(later, before_later, width)])
        _easel.free()
        _easel = null


## A stroke let go uncommitted leaves the picture the layer showed at rest,
## every float: the layer's own gather took the halo's chunks back off.
func test_a_stroke_let_go_leaves_the_picture_at_rest() -> void:
    for which: String in ["lens", "kaleidoscope", "mirror"]:
        _easel = _bench(which)
        var rest := _bytes(_easel.output)
        var width := _easel.output.size.x
        _paint(_easel, STROKE, false)
        var doc := _easel.document
        for grid_pos: Vector2i in doc.stroke_layer.chunks.keys():
            doc.stroke_layer.set_chunk(grid_pos, null)
        doc.invalidate_chunk_regions({STROKE: Rect2i(Vector2i.ZERO, Vector2i(SaChunk.SIZE, SaChunk.SIZE))})
        _easel.process_pending_composite()
        var after := _bytes(_easel.output)
        assert_true(after == rest, "%s: %s differ" % [which, _differing(after, rest, width)])
        _easel.free()
        _easel = null
