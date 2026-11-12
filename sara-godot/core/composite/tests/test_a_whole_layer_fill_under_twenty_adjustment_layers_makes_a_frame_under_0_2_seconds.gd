## A whole-layer fill under adjustment layers, composited by
## the easel's frame a few chunks at a time as [SaCompositeBudget] spreads it,
## ends on the picture one composite of every chunk draws, texel for texel.
##
## The painting is eight chunks, each an opaque colour with a bar across it, so
## every chunk edge is a step the blurs above it smooth, and a chunk drawn
## without its neighbour's backdrop would show as a band. Over it a layer at
## half opacity is filled whole, under three adjustment layers, a blur, an
## invert and a second blur. One easel composites the fill at once, the way
## every reader does. The other is taught a cost that pays for one chunk a
## frame and composites it the way its own frame does, until nothing is held.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(1024, 512)
const FILL := Color(0.3, 0.5, 0.7, 1.0)
const BAR := Color(0.0625, 0.0625, 0.125, 1.0)

var _types: SaLayerTypeRegistry


func before_each() -> void:
    _types = Fixtures.make_registries().layer_types
    SaProblems.pending_refusals = PackedStringArray()


## The painting of the header, composited, with the half-opaque layer active.
func _painting() -> SaEasel:
    var easel := Bench.easel(SIZE)
    easel.compositor.filter_chain.registry.register(SaGaussianBlurFilter.new(), &"sara-base-modules")
    var doc := easel.document
    var base := doc.get_node("Background") as SaLayer
    for grid_pos: Vector2i in base.chunks.keys():
        base.chunks.erase(grid_pos)
    for grid_pos: Vector2i in SaLayer.grid_positions(SIZE):
        var shade := 0.125 + 0.1 * float(grid_pos.x) + 0.25 * float(grid_pos.y)
        _paint(base.get_or_create_chunk(grid_pos).albedo(), grid_pos, Color(shade, 0.75 - shade * 0.5, 0.5, 1.0))
    doc.set_active_layer(base)
    var ops := SaLayerOps.new(doc)
    var paint := ops.add()
    paint.name = "Paint"
    paint.opacity = 0.5
    _adjust(doc, "Blur", SaFilterRegistry.key_for(&"sara-base-modules", SaGaussianBlurFilter.new()), {"radius": 6.0})
    _adjust(doc, "Invert", String(Bench.INVERT), {})
    _adjust(doc, "Soft", SaFilterRegistry.key_for(&"sara-base-modules", SaGaussianBlurFilter.new()), {"radius": 3.0})
    doc.set_active_layer(paint)
    Bench.composite(easel)
    return easel


## An adjustment layer above the active one, carrying the filter of *key*.
func _adjust(doc: SaDocument, named: String, key: String, params: Dictionary) -> void:
    var layer := SaLayerOps.new(doc).add(SaBackdropLayer.TYPE_ID, _types)
    layer.name = named
    assert_not_null(SaFilterOps.new(doc).attach(layer, key, params), "The filter attaches to %s" % named)


## *texture*, the chunk at *grid_pos*, filled with *fill* and a bar across it.
func _paint(texture: SaTexture, grid_pos: Vector2i, fill: Color) -> void:
    var side := texture.size.x
    var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    var image := Image.create_empty(side, side, false, Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF)
    image.fill(fill)
    image.fill_rect(Rect2i(0, 100 + 20 * grid_pos.x, side, 12), BAR)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())


static func _bytes(texture: SaTexture) -> PackedByteArray:
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)


func test_the_fill_spread_over_frames_ends_on_the_picture_one_composite_draws() -> void:
    var whole := _painting()
    var before := _bytes(whole.output)
    whole.document.fill_layer(FILL)
    whole.process_pending_composite()
    var want := _bytes(whole.output)
    assert_false(want == before, "The fill changes the picture")
    whole.free()

    var spread := _painting()
    assert_eq(_bytes(spread.output), before, "The two easels start on one picture")
    assert_eq(SaCompositeBudget.weight(spread.document), 4, "Three adjustment layers are drawn over the canvas")
    # A cost that pays for one chunk a frame, taught the way a composite does.
    spread.budget.learn(int(SaCompositeBudget.FRAME_USEC) * 64, SaCompositeBudget.LEARNS_FROM, spread.document)
    assert_eq(spread.budget.chunks_per_frame(spread.document), 1, "The budget pays for one chunk a frame")
    spread.document.fill_layer(FILL)
    var count_at := spread.composite_count
    spread.process_pending_composite(true)
    assert_false(spread.backlog.is_empty(), "The first frame holds what it cannot pay for")
    assert_false(_bytes(spread.output) == want, "and the picture is not finished after it")
    var frames := 1
    while not spread.backlog.is_empty() and frames < 64:
        spread.process_pending_composite(true)
        frames += 1
    assert_true(spread.backlog.is_empty(), "Every held chunk is composited in the end")
    # Over more than one frame, and not a frame a chunk: a frame the budget cut
    # teaches it what the frame cost, which here is far under the cost taught.
    assert_true(spread.composite_count - count_at > 1, "over more than one frame")
    assert_eq(_bytes(spread.output), want, "The picture is the one composite's texel for texel")
    spread.free()


func test_a_reader_s_composite_is_never_cut() -> void:
    var easel := _painting()
    easel.budget.learn(int(SaCompositeBudget.FRAME_USEC) * 64, SaCompositeBudget.LEARNS_FROM, easel.document)
    easel.document.fill_layer(FILL)
    easel.process_pending_composite()
    assert_true(easel.backlog.is_empty(), "A composite called without the budget holds nothing back")
    easel.free()


func test_nothing_is_held_before_a_composite_taught_the_cost() -> void:
    var budget := SaCompositeBudget.new()
    assert_eq(budget.chunks_per_frame(null), -1, "An untaught budget pays for everything")
    budget.learn(1000000, SaCompositeBudget.LEARNS_FROM - 1, null)
    assert_eq(budget.chunks_per_frame(null), -1, "and a composite of too few chunks teaches it nothing")
