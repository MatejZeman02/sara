## Showing a large painting's group took 1.4 s to
## settle on a slower machine, and much of it was the walk setting up dispatches again
## that it had set up the frame before. Freeing any `SaTexture` drops every
## uniform set `SaCompute` has cached, and the composite freed textures every
## frame: the strips a shift's neighbours are read through, made again for each
## chunk, the gather of a node a whole-node pass reads, made again for each
## composite, the chain's one padding runner, sized again for each of two
## filters of unlike reach, and its scratch and the compositor's adjustment
## scratches, sized again for an adjustment layer's thumbnail at a sixteenth.
## And the budget learnt a cost high once and then cut every frame to fewer
## chunks than teach it, so the toggle walked two chunks a frame for fourteen
## frames.
##
## So a composite of every chunk repeated, over a shift that reads the whole
## layer, two blurs of unlike reach and two adjustment layers, with a thumbnail
## of the upper adjustment layer drawn between, frees nothing and dispatches no
## more than the one before it, and a frame the budget cut teaches it.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const WholeShiftFilter = preload("res://tests/fixtures/modules/whole-fixture/whole_shift_filter.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(1024, 512)

var _types: SaLayerTypeRegistry


func before_each() -> void:
    _types = Fixtures.make_registries().layer_types
    SaProblems.pending_refusals = PackedStringArray()


## A painting of two painted layers, each under a blur of its own radius, the
## upper one under a shift that reads the whole layer first, and two adjustment
## layers over them, an invert and a blur.
func _painting() -> SaEasel:
    var easel := Bench.easel(SIZE)
    var blur := SaGaussianBlurFilter.new()
    easel.compositor.filter_chain.registry.register(blur, &"sara-base-modules")
    easel.compositor.filter_chain.registry.register(WholeShiftFilter.new(), &"whole-fixture")
    var key := SaFilterRegistry.key_for(&"sara-base-modules", blur)
    var doc := easel.document
    var base := doc.get_node("Background") as SaLayer
    var ops := SaLayerOps.new(doc)
    doc.set_active_layer(base)
    var wide := ops.add()
    wide.name = "Shifted"
    wide.opacity = 0.5
    for grid_pos: Vector2i in SaLayer.grid_positions(SIZE):
        _paint(base, grid_pos, Color(0.125 + 0.1 * float(grid_pos.x), 0.5, 0.25 * float(grid_pos.y), 1.0))
        if grid_pos.x % 2 == 0:
            _paint(wide, grid_pos, Color(0.75, 0.25, 0.125 * float(grid_pos.x), 1.0))
    assert_not_null(SaFilterOps.new(doc).attach(base, key, {"radius": 9.0}), "A wide blur attaches to the background")
    var shift := {"offset_x": 64.0, "offset_y": 0.0, "mode": 0, "reach": SaNeighbourhoodPass.WHOLE_NODE}
    assert_not_null(
        SaFilterOps.new(doc).attach(wide, "whole-fixture.whole_fixture_shift", shift), "A shift attaches to the layer over it"
    )
    assert_not_null(SaFilterOps.new(doc).attach(wide, key, {"radius": 3.0}), "and a narrow blur after it")
    _adjust(doc, "Invert", String(Bench.INVERT), {})
    var soft := _adjust(doc, "Soft", key, {"radius": 2.0})
    doc.set_active_layer(soft)
    Bench.composite(easel)
    return easel


## *layer*'s chunk at *grid_pos* filled with *fill* and a bar across it.
func _paint(layer: SaLayer, grid_pos: Vector2i, fill: Color) -> void:
    var texture := layer.get_or_create_chunk(grid_pos).albedo()
    var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    var image := Image.create_empty(texture.size.x, texture.size.x, false, Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF)
    image.fill(fill)
    image.fill_rect(Rect2i(0, 90 + 20 * grid_pos.x, texture.size.x, 12), Color(0.0625, 0.0625, 0.125, 1.0))
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())


## An adjustment layer above the active one, carrying the filter of *key*.
func _adjust(doc: SaDocument, named: String, key: String, params: Dictionary) -> SaLayer:
    var layer := SaLayerOps.new(doc).add(SaBackdropLayer.TYPE_ID, _types)
    layer.name = named
    assert_not_null(SaFilterOps.new(doc).attach(layer, key, params), "The filter attaches to %s" % named)
    return layer


## The upper adjustment layer's thumbnail, every chunk at a sixteenth, drawn
## the way the layers docker draws it.
func _thumbnail(easel: SaEasel, tree: SaTreeRender, plate: SaTexture) -> void:
    var layer := easel.document.get_node("Soft") as SaLayer
    for grid_pos: Vector2i in SaLayer.grid_positions(SIZE):
        easel.compositor.detail.begin(plate, -Vector2(grid_pos * SaLayer.CHUNK_SIZE), 1.0 / 16.0)
        tree.render_below(plate, grid_pos, layer)
        easel.compositor.detail.end()


func test_a_composite_repeated_with_a_thumbnail_between_frees_no_texture() -> void:
    var easel := _painting()
    var tree := SaTreeRender.new(easel.document)
    var plate := SaTexture.new(Vector2i(SaLayer.CHUNK_SIZE, SaLayer.CHUNK_SIZE), easel.output.format)
    _thumbnail(easel, tree, plate)
    easel.request_full_composite()
    easel.process_pending_composite()
    var epoch := SaTexture.epoch
    var dispatched := SaCompute.dispatches
    easel.request_full_composite()
    easel.process_pending_composite()
    var first := SaCompute.dispatches - dispatched
    assert_true(first > 0, "A composite of every chunk dispatches")
    _thumbnail(easel, tree, plate)
    dispatched = SaCompute.dispatches
    easel.request_full_composite()
    easel.process_pending_composite()
    assert_eq(SaTexture.epoch, epoch, "Neither the composites nor the thumbnail between them freed a texture")
    assert_eq(
        SaCompute.dispatches - dispatched, first, "and the composite after the thumbnail dispatched what the one before it did"
    )
    easel.free()


func test_a_frame_the_budget_cut_teaches_it() -> void:
    var easel := _painting()
    var budget := easel.budget
    # A cost taught high, which pays for one chunk a frame.
    budget.learn(int(SaCompositeBudget.FRAME_USEC) * 64, SaCompositeBudget.LEARNS_FROM, easel.document)
    assert_eq(budget.chunks_per_frame(easel.document), 1, "The budget pays for one chunk a frame")
    var regions: Dictionary[Vector2i, Rect2i] = {}
    for grid_pos: Vector2i in SaLayer.grid_positions(SIZE):
        regions[grid_pos] = Rect2i(Vector2i.ZERO, Vector2i(SaLayer.CHUNK_SIZE, SaLayer.CHUNK_SIZE))
    budget.hold_beyond(regions, easel.backlog, easel.document)
    assert_eq(regions.size(), 1, "so it cuts a whole composite to one chunk")
    # The one chunk cost a millisecond, fewer chunks than teach an uncut composite.
    var taught := budget.usec_per_unit
    budget.learn(1000, regions.size(), easel.document)
    assert_true(budget.usec_per_unit < taught, "and what the cut frame cost teaches it")
    taught = budget.usec_per_unit
    budget.learn(int(SaCompositeBudget.FRAME_USEC) * 64, 1, easel.document)
    assert_eq(budget.usec_per_unit, taught, "while an uncut composite of one chunk teaches nothing")
    easel.free()
