## A blur on the layer being painted reads the chunks beside the one it draws
## from with the live stroke in them, and not as the layer without it. The active layer's own chunks hold no
## stroke until it commits, so
## a neighbourhood pass read the chunk beside it from the layer and dimmed the
## stroke within its reach of every seam, and a stroke along a seam nearly
## disappeared. The compositor keeps the layer and the stroke composited
## together over the ring of the dirty set now, in a halo the chain reads.
##
## The picture is two chunks side by side on the active layer, red and green,
## with the box blur attached and the stroke's own buffer painted yellow over
## the second. The same picture with the yellow already in the layer is what the
## commit will produce, so the row across the seam has to read the same whether
## the pen is down or up.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const BoxBlurFilter = preload("res://modules/sara-base-modules/base/usual/box_blur_filter.gd")

const REQUIRES_GPU := true

const MODULE_DIR := "res://modules/sara-base-modules/base"
const KEY: StringName = &"sara-base-modules.box_blur"
const RADIUS := 8
const RED := Color(1.0, 0.0, 0.0, 1.0)
const GREEN := Color(0.0, 1.0, 0.0, 1.0)
const YELLOW := Color(1.0, 0.8, 0.2, 1.0)
const ROW := 128
## The row across the seam, and one pixel inside it: the last texel of the left
## chunk, which reads the chunk the stroke is painted in for its neighbours.
const FIRST := SaChunk.SIZE - 40
const LAST := SaChunk.SIZE + 40
const SEAM := Vector2i(SaChunk.SIZE - 1, ROW)
## A sliver of that chunk along its left edge, the shape a dab redraws.
const SLIVER := Rect2i(0, ROW - 20, 6, 40)

var _easel: SaEasel = null


func after_each() -> void:
    if _easel != null:
        _easel.free()
    _easel = null


## An easel holding red and green side by side on one layer with the box blur
## attached to it, and the layer active. With *stroke* the stroke buffer holds
## the yellow over the green chunk alone, which is the picture the commit will
## leave. With no stroke the yellow is in the layer's own chunk already, which
## is the same picture painted by hand.
func _bench(stroke: bool, size := Vector2i(2 * SaChunk.SIZE, SaChunk.SIZE)) -> SaEasel:
    var made := Bench.easel(size)
    var doc := made.document
    ModuleLoader.module_dirs[&"sara-base-modules"] = MODULE_DIR
    var blur := BoxBlurFilter.new()
    made.compositor.filter_chain.registry.register(blur, &"sara-base-modules")
    var layer := doc.get_node("Background") as SaLayer
    for grid_pos: Vector2i in layer.chunks.keys():
        layer.chunks.erase(grid_pos)
    layer.get_or_create_chunk(Vector2i(0, 0)).clear(RED)
    layer.get_or_create_chunk(Vector2i(1, 0)).clear(GREEN if stroke else YELLOW)
    doc.set_active_layer(layer)
    SaFilterOps.new(doc).attach(layer, KEY, {"radius": RADIUS})
    if stroke:
        doc.stroke_layer.get_or_create_chunk(Vector2i(1, 0)).clear(YELLOW)
        doc.stroke_layer.visible = true
    Bench.composite(made)
    return made


## [const ROW] of *texture* from [const FIRST] to [const LAST], read back once.
func _row(texture: SaTexture) -> Array[Color]:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var out: Array[Color] = []
    for x in range(FIRST, LAST):
        out.append(SaFieldSpec.decode_texel(bytes, texture.format, ROW * texture.size.x + x))
    return out


## The worst per-channel distance between two rows of the same length, and the x
## it was at.
func _worst(one: Array[Color], other: Array[Color]) -> Array:
    var worst := 0.0
    var at := -1
    for i in one.size():
        var gap := maxf(maxf(absf(one[i].r - other[i].r), absf(one[i].g - other[i].g)), absf(one[i].b - other[i].b))
        gap = maxf(gap, absf(one[i].a - other[i].a))
        if gap > worst:
            worst = gap
            at = FIRST + i
    return [worst, at]


## The row across the seam with the pen down is the row of the same picture with
## the yellow already in the layer, which is what a commit produces. Without the fix
## the blur read chunk (0, 0)'s neighbour as its green and every texel within
## the reach of the seam was a red-to-yellow gradient mixed with it.
func test_the_row_across_the_seam_reads_the_live_stroke() -> void:
    _easel = _bench(false)
    var painted := _row(_easel.output)
    _easel.free()
    _easel = _bench(true)
    var live := _row(_easel.output)
    var worst := _worst(painted, live)
    assert_true(
        worst[0] < 0.01, "The row under the live stroke is the hand-painted one, worst %.3f at x %d" % [worst[0], worst[1]]
    )


## And the texel one pixel inside the seam reads the same after the commit, the
## proof the neighbour a pass reads while the pen is down is the one the commit
## leaves rather than the layer without its stroke.
func test_the_seam_texel_mid_stroke_is_the_same_after_the_commit() -> void:
    _easel = _bench(true)
    var live := Bench.texel(_easel.output, SEAM)
    _easel.document.commit_stroke()
    Bench.composite(_easel)
    var committed := Bench.texel(_easel.output, SEAM)
    assert_almost_eq(committed.r, live.r, 0.01, "Red at the seam: %s against %s" % [committed, live])
    assert_almost_eq(committed.g, live.g, 0.01, "Green at the seam: %s against %s" % [committed, live])
    assert_almost_eq(committed.b, live.b, 0.01, "Blue at the seam: %s against %s" % [committed, live])
    assert_almost_eq(committed.a, live.a, 0.01, "Alpha at the seam: %s against %s" % [committed, live])


## A redraw of a sliver mid-stroke reads the same picture as the whole redraw:
## the halo a pass reads its neighbours from is filled for the ring of this
## dirty set and dropped where the last one's chunks were.
func test_a_sliver_redrawn_mid_stroke_leaves_the_row_as_it_was() -> void:
    _easel = _bench(true)
    var whole := _row(_easel.output)
    _easel.document.invalidate_chunk_regions({Vector2i(1, 0): SLIVER})
    _easel.process_pending_composite()
    var again := _row(_easel.output)
    var worst := _worst(whole, again)
    assert_true(
        worst[0] < 0.01, "The row after a sliver mid-stroke is the whole redraw's, worst %.3f at x %d" % [worst[0], worst[1]]
    )


## What the composite sweeps is the stroke's own answer: the chunk the pass
## reads beside the dirty one while the pen is down, and nothing at all at rest.
func test_a_blurred_layer_at_rest_sweeps_nothing() -> void:
    _easel = _bench(true)
    var dirty: Dictionary[Vector2i, Rect2i] = {Vector2i(1, 0): Rect2i(0, 0, SaChunk.SIZE, SaChunk.SIZE)}
    assert_true(SaFilterChain.stroke_sweep(_easel.document, dirty).has(Vector2i(1, 0)), "The stroke's own chunk is swept")
    _easel.document.commit_stroke()
    assert_true(SaFilterChain.stroke_sweep(_easel.document, dirty).is_empty(), "and a layer at rest sweeps nothing")
