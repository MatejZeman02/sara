## Three blur adjustment layers over a painting, composited by
## one easel that keeps what each layer showed and by one that runs every layer
## over the whole set the walk draws, read texel for texel after every change
## the row names: a stroke below the stack, a record's radius, a mask painted on
## a layer of it, its blend mode and its opacity, each followed by a stroke so
## the cache is read again after the change, and a live transform on the
## painting below, which came after the cache.
##
## The painting is six chunks, each an opaque colour of its own with a bar
## across it, so every chunk edge is a step each blur smooths, and the strokes
## cross chunk edges, where a blur carries a change into the chunk beside it.
##
## of the same plan adds what runs when a change names the layer it moved
## at: an opacity on the top blur and a mask stroke on it run no blur below it,
## and an undo on the painting under the stack reads as before the stroke.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(768, 512)
const RADII: Array[float] = [3.0, 6.0, 10.0]
const BAR := Color(0.0625, 0.0625, 0.125, 1.0)
const STROKES: Array[Rect2i] = [
    Rect2i(236, 90, 60, 40),
    Rect2i(490, 236, 40, 50),
    Rect2i(120, 300, 30, 30),
    Rect2i(600, 120, 50, 20),
    Rect2i(250, 240, 20, 30),
    Rect2i(380, 400, 70, 40),
]
const INK: Array[Color] = [
    Color(1.0, 0.875, 0.125, 1.0),
    Color(0.125, 0.875, 0.75, 1.0),
    Color(0.875, 0.125, 0.5, 1.0),
]

var _types: SaLayerTypeRegistry
## The background of each easel as it is painted, one image a chunk, keyed by
## the easel's instance id and then the grid position.
var _painted: Dictionary[int, Dictionary] = {}


func before_each() -> void:
    _types = Fixtures.make_registries().layer_types
    _painted = {}


## The painting with the three blurs above the background, which is active,
## and a paint layer over them all, kept by the cache with *caching*.
func _stack(caching: bool) -> SaEasel:
    var easel := Bench.easel(SIZE)
    easel.compositor.filter_chain.registry.register(SaGaussianBlurFilter.new(), &"sara-base-modules")
    if not caching:
        easel.compositor.adjustment = SaBackdropLayer.new(false)
    var doc := easel.document
    var base := doc.get_node("Background") as SaLayer
    var images: Dictionary[Vector2i, Image] = {}
    for grid_pos: Vector2i in base.chunks.keys():
        base.chunks.erase(grid_pos)
    for x in 3:
        for y in 2:
            var grid_pos := Vector2i(x, y)
            var texture := base.get_or_create_chunk(grid_pos).albedo()
            var image := Image.create_empty(texture.size.x, texture.size.y, false, _image_format(texture))
            image.fill(Color(0.125 + 0.25 * x, 0.25 + 0.5 * y, 0.875 - 0.25 * x, 1.0))
            image.fill_rect(Rect2i(0, 80 + 30 * x + 20 * y, texture.size.x, 12), BAR)
            GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
            images[grid_pos] = image
    _painted[easel.get_instance_id()] = images
    var ops := SaLayerOps.new(doc)
    doc.set_active_layer(base)
    # Each layer added goes above the active one and is made active, so the
    # stack builds upwards in order.
    for i in RADII.size():
        var layer := ops.add(SaBackdropLayer.TYPE_ID, _types)
        layer.name = "Blur %d" % i
        var key := SaFilterRegistry.key_for(&"sara-base-modules", SaGaussianBlurFilter.new())
        assert_not_null(SaFilterOps.new(doc).attach(layer, key, {"radius": RADII[i]}), "Blur %d attaches" % i)
    var above := ops.add()
    above.name = "Above"
    var ink := above.get_or_create_chunk(Vector2i(1, 1)).albedo()
    var over := Image.create_empty(ink.size.x, ink.size.y, false, _image_format(ink))
    over.fill(Color(0, 0, 0, 0))
    over.fill_rect(Rect2i(40, 40, 100, 60), Color(0.5, 0.0, 0.25, 0.5))
    GlobalShaderCompiler.get_rd().texture_update(ink.rid, 0, over.get_data())
    doc.set_active_layer(base)
    Bench.composite(easel)
    return easel


## Paints *rect*, in document pixels, in *colour* into the background of
## *easel* and marks its regions as a dab does, at the background, nothing else
## dirty. *recorded* makes it one history step, as a stroke's commit does.
func _stroke(easel: SaEasel, rect: Rect2i, colour: Color, recorded: bool = false) -> void:
    var doc := easel.document
    var base := doc.get_node("Background") as SaLayer
    var images: Dictionary = _painted[easel.get_instance_id()]
    var regions: Dictionary[Vector2i, Rect2i] = {}
    var undo_data: Dictionary[Vector2i, Variant] = {}
    for grid_pos: Vector2i in images:
        var side := SaLayer.CHUNK_SIZE
        var local := Rect2i(rect.position - grid_pos * side, rect.size).intersection(Rect2i(0, 0, side, side))
        if not local.has_area():
            continue
        undo_data[grid_pos] = base.duplicate_chunk(grid_pos)
        var image: Image = images[grid_pos]
        image.fill_rect(local, colour)
        GlobalShaderCompiler.get_rd().texture_update(base.get_field(grid_pos).rid, 0, image.get_data())
        regions[grid_pos] = local
        # A layer drawn through a live transform hears of its paint changing as
        # an undo tells it, so the map's cache is made again there.
        if base.live_transform != null:
            base.mark_unresolved(grid_pos)
    if recorded:
        doc.record_pixel_step("Stroke", base, undo_data)
    doc.invalidate_chunk_regions(regions, base)
    easel.process_pending_composite()


## One hard dab on the top blur's mask across the edge of chunks (0,0) and
## (1,0), through the paint context and the stroke's commit as a brush paints
## it, with a composite between the dab and the commit as a frame of the stroke
## would make. Answers the blurs each composite dispatched.
func _mask_stroke(easel: SaEasel) -> Array[int]:
    var doc := easel.document
    doc.mask_target = _layer(doc, 2).mask
    var compute := PaintKernel.compute()
    var pos := Vector2(250, 100)
    var radius := 20.0
    var ran: Array[int] = []
    SaCompute.reset_counters()
    doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    var paint := SaPaintContext.for_region(doc, Rect2(pos - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false)
    paint.dispatch_batch(
        compute,
        "paint",
        func(target: SaPaintContext.Target) -> void:
            compute.set_texture(0, target.texture.rid)
            compute.set_push_constant_float_array(
                PaintKernel.pack_params(
                    paint.local_point(target, pos), target.render_offset, Color(0.25, 0, 0, 1), radius, 1.0, 1.0, 1.0
                )
            )
    )
    paint.commit_invalidation()
    easel.process_pending_composite()
    ran.append(_blurs())
    SaCompute.reset_counters()
    doc.commit_stroke()
    doc.mask_target = null
    easel.process_pending_composite()
    ran.append(_blurs())
    return ran


## Runs *change* on each easel's document and composites what it made dirty,
## after the cache update it asked for, which the end of the frame would run.
func _both(easels: Array[SaEasel], change: Callable) -> void:
    for easel in easels:
        change.call(easel.document)
        easel.document._flush_cache_update()
        easel.process_pending_composite()


## The two outputs read texel for texel, the worst texel named when they differ.
func _same(easels: Array[SaEasel], what: String) -> void:
    var got := _bytes(easels[0].output)
    var want := _bytes(easels[1].output)
    if got == want:
        assert_true(true, what)
        return
    var worst := 0.0
    var worst_at := Vector2i.ZERO
    var texture := easels[0].output
    for y in texture.size.y:
        for x in texture.size.x:
            var index := y * texture.size.x + x
            var a := SaFieldSpec.decode_texel(got, texture.format, index)
            var b := SaFieldSpec.decode_texel(want, texture.format, index)
            var off := maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))
            if off > worst:
                worst = off
                worst_at = Vector2i(x, y)
    assert_true(false, "%s, worst %s at %s" % [what, worst, worst_at])


func _layer(doc: SaDocument, index: int) -> SaLayer:
    return doc.get_node("Blur %d" % index) as SaLayer


## The blur's dispatches since the counters were reset, or its *tally*.
static func _blurs(tally: String = "dispatches") -> int:
    var total := 0
    for key: String in SaCompute.by_kernel:
        if key.contains("gaussian_blur"):
            total += int(SaCompute.by_kernel[key].get(tally, 0))
    return total


static func _image_format(texture: SaTexture) -> Image.Format:
    return Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF


static func _bytes(texture: SaTexture) -> PackedByteArray:
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)


func test_at_rest_and_under_strokes_below_the_stack_the_two_read_the_same() -> void:
    var easels: Array[SaEasel] = [_stack(true), _stack(false)]
    _same(easels, "At rest the cached stack reads as the uncached one")
    for i in 3:
        for easel in easels:
            _stroke(easel, STROKES[i], INK[i])
        _same(easels, "After stroke %d below the stack" % i)
    for easel in easels:
        easel.free()


func test_a_stroke_below_runs_each_layer_over_the_stroke_grown_by_the_reach_up_to_it() -> void:
    var cached := _stack(true)
    var plain := _stack(false)
    _stroke(cached, STROKES[0], INK[0])
    _stroke(plain, STROKES[0], INK[0])
    SaCompute.reset_counters()
    _stroke(cached, STROKES[1], INK[1])
    var with_cache := _blurs()
    var with_groups := _blurs("workgroups")
    SaCompute.reset_counters()
    _stroke(plain, STROKES[1], INK[1])
    var without := _blurs("workgroups")
    var cache := cached.compositor.adjustment.sweep.cache
    assert_eq(cache.steps.size(), RADII.size(), "Each of the three blurs is a step the cache plans")
    var side := SaLayer.CHUNK_SIZE
    # The document grows a dab's region by the widest halo in the tree before
    # the walk sees it, so that is what moved below the bottom blur.
    var spread := int(RADII.max())
    var runs := 0
    for i in RADII.size():
        spread += int(RADII[i])
        var step: SaAdjustmentCache.Step = cache.steps[_layer(cached.document, i).get_instance_id()]
        var reached := Rect2i(STROKES[1].position, STROKES[1].size).grow(spread)
        for grid_pos: Vector2i in step.runs:
            var region: Rect2i = step.runs[grid_pos]
            var placed := Rect2i(grid_pos * side + region.position, region.size)
            assert_true(reached.encloses(placed), "Blur %d runs at %s inside the dirty set grown by %d" % [i, grid_pos, spread])
        runs += step.runs.size()
    assert_eq(with_cache, runs, "One blur a chunk each layer runs at")
    assert_true(with_groups < without, "Less blurring with the cache, %d workgroups, than without, %d" % [with_groups, without])
    var expected := 0
    for i in RADII.size():
        var step: SaAdjustmentCache.Step = cache.steps[_layer(cached.document, i).get_instance_id()]
        expected += step.store.positions().size()
    # A kept chunk is a chunk of the canvas's texels, so the bytes held over
    # the canvas's bytes are the chunks kept over the canvas's area.
    var held := cache.held_bytes() * SIZE.x * SIZE.y
    assert_eq(held, expected * side * side * cached.output.bytes, "Each kept chunk is one chunk of the canvas's texels")
    cached.free()
    plain.free()


func test_a_records_radius_reads_the_same_and_so_does_the_stroke_after_it() -> void:
    var easels: Array[SaEasel] = [_stack(true), _stack(false)]
    _stroke(easels[0], STROKES[0], INK[0])
    _stroke(easels[1], STROKES[0], INK[0])
    _both(easels, func(doc: SaDocument) -> void: SaFilterOps.new(doc).set_parameters(_layer(doc, 1).filters[0], {"radius": 9.0}))
    _same(easels, "After the middle blur's radius changed")
    for easel in easels:
        _stroke(easel, STROKES[2], INK[1])
    _same(easels, "and after a stroke below it")
    _both(easels, func(doc: SaDocument) -> void: SaFilterOps.new(doc).set_enabled(_layer(doc, 0).filters[0], false))
    _same(easels, "After the bottom blur was switched off")
    for easel in easels:
        _stroke(easel, STROKES[3], INK[2])
    _same(easels, "and after a stroke below it")
    for easel in easels:
        easel.free()


func test_a_mask_painted_on_a_layer_of_the_stack_reads_the_same() -> void:
    var easels: Array[SaEasel] = [_stack(true), _stack(false)]
    _both(easels, func(doc: SaDocument) -> void: SaMaskOps.new(doc).add(_layer(doc, 1)))
    _same(easels, "After a mask was added to the middle blur")
    for easel in easels:
        _stroke(easel, STROKES[0], INK[0])
    _same(easels, "and after a stroke below it")
    # Painted as a brush on the mask paints it: the coverage written over a
    # region across a chunk edge, and that region marked, no fold rebuilt.
    for easel in easels:
        var doc := easel.document
        var mask := _layer(doc, 1).mask
        var regions: Dictionary[Vector2i, Rect2i] = {}
        for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0)]:
            var coverage := mask.get_or_create(grid_pos)
            var image := Image.create_empty(coverage.size.x, coverage.size.y, false, Image.FORMAT_RF)
            image.fill(Color(1, 0, 0, 0))
            var local := Rect2i(Vector2i(200, 150) - grid_pos * SaLayer.CHUNK_SIZE, Vector2i(120, 60))
            local = local.intersection(Rect2i(Vector2i.ZERO, coverage.size))
            image.fill_rect(local, Color(0.25, 0, 0, 0))
            GlobalShaderCompiler.get_rd().texture_update(coverage.rid, 0, image.get_data())
            regions[grid_pos] = local
        doc.invalidate_chunk_regions(regions)
        easel.process_pending_composite()
    _same(easels, "After the mask was painted over a chunk edge")
    for easel in easels:
        _stroke(easel, STROKES[4], INK[1])
    _same(easels, "and after a stroke below it")
    for easel in easels:
        easel.free()


func test_a_blend_mode_and_an_opacity_read_the_same() -> void:
    var easels: Array[SaEasel] = [_stack(true), _stack(false)]
    _stroke(easels[0], STROKES[0], INK[0])
    _stroke(easels[1], STROKES[0], INK[0])
    _both(easels, func(doc: SaDocument) -> void: SaLayerOps.new(doc).set_blend_mode(_layer(doc, 2), SaLayer.BLEND_MODE.MULTIPLY))
    _same(easels, "After the top blur went to Multiply")
    for easel in easels:
        _stroke(easel, STROKES[1], INK[1])
    _same(easels, "and after a stroke below it")
    _both(easels, func(doc: SaDocument) -> void: SaLayerOps.new(doc).set_opacity(_layer(doc, 1), 0.4))
    _same(easels, "After the middle blur's opacity went to 40%")
    for easel in easels:
        _stroke(easel, STROKES[5], INK[2])
    _same(easels, "and after a stroke below it")
    for easel in easels:
        easel.free()


func test_a_window_drops_what_it_no_longer_reaches_and_reads_the_same_as_it_pans() -> void:
    var easels: Array[SaEasel] = [_stack(true), _stack(false)]
    var shown: Array[Rect2] = [Rect2(0, 0, 100, 100)]
    for easel in easels:
        easel.shown_rect = func() -> Rect2: return shown[0]
    for easel in easels:
        _stroke(easel, STROKES[0], INK[0])
    _same(easels, "Under a window over the top left, after a stroke across its edge")
    # The window is the view grown by a chunk, the four chunks at the top left,
    # and a blur keeps a chunk only where the window holds every chunk its
    # output there reads, the left column for the reach of all three.
    var cache := easels[0].compositor.adjustment.sweep.cache
    for i in RADII.size():
        var step: SaAdjustmentCache.Step = cache.steps[_layer(easels[0].document, i).get_instance_id()]
        var kept := step.store.positions()
        kept.sort()
        assert_eq(kept, [Vector2i(0, 0), Vector2i(0, 1)], "Blur %d keeps the column the window reaches round" % i)
    for easel in easels:
        _stroke(easel, STROKES[2], INK[1])
    _same(easels, "after a second stroke")
    shown[0] = Rect2(500, 200, 200, 200)
    for easel in easels:
        _stroke(easel, STROKES[3], INK[2])
    _same(easels, "Panned to the right, with what the window held back drawn")
    for easel in easels:
        easel.shown_rect = Callable()
        easel.process_pending_composite()
        easel.flush()
    _same(easels, "and with the whole canvas shown again")
    for easel in easels:
        easel.free()


func test_a_live_transform_on_the_painting_below_reads_the_same() -> void:
    var easels: Array[SaEasel] = [_stack(true), _stack(false)]
    var maps: Array[Variant] = [
        SaLiveTransform.composed(Vector2(37, 21), 0.0, Vector2.ONE, Vector2.ZERO),
        SaLiveTransform.composed(Vector2(-50, 12), 30.0, Vector2(1.25, 1.25), Vector2(384, 256)),
        null,
    ]
    var said: Array[String] = [
        "the painting under the stack moved by 37 and 21",
        "it turned by 30 degrees and grew by a quarter",
        "the map was taken off",
    ]
    for i in maps.size():
        var before := _bytes(easels[0].output)
        _both(
            easels,
            func(doc: SaDocument) -> void:
                assert_true(
                    SaLiveTransform.put(doc, doc.get_node("Background") as SaLayer, maps[i]), "The map is put, as %s" % said[i]
                )
        )
        assert_true(_bytes(easels[0].output) != before, "The picture moved when %s" % said[i])
        _same(easels, "After %s" % said[i])
        for easel in easels:
            _stroke(easel, STROKES[i], INK[i])
        _same(easels, "and after the painting's paint changed under it")
        var cache := easels[0].compositor.adjustment.sweep.cache
        assert_eq(cache.steps.size(), RADII.size(), "and every blur ran through the cache when %s" % said[i])
    for easel in easels:
        easel.free()


## The step the cache of *easel* planned for blur *index* in the last walk.
func _step(easel: SaEasel, index: int) -> SaAdjustmentCache.Step:
    var cache := easel.compositor.adjustment.sweep.cache
    return cache.steps[_layer(easel.document, index).get_instance_id()]


func test_an_opacity_on_the_top_blur_runs_the_top_blur_alone_over_its_six_chunks() -> void:
    var easels: Array[SaEasel] = [_stack(true), _stack(false)]
    for easel in easels:
        _stroke(easel, STROKES[0], INK[0])
    var cached: Array[SaEasel] = [easels[0]]
    var plain: Array[SaEasel] = [easels[1]]
    var opacity := func(doc: SaDocument) -> void: SaLayerOps.new(doc).set_opacity(_layer(doc, 2), 0.4)
    SaCompute.reset_counters()
    _both(cached, opacity)
    var ran := _blurs()
    SaCompute.reset_counters()
    _both(plain, opacity)
    var without := _blurs()
    assert_true(_step(easels[0], 0).runs.is_empty(), "The bottom blur, under the write, runs nowhere")
    assert_true(_step(easels[0], 1).runs.is_empty(), "nor does the middle one")
    assert_eq(_step(easels[0], 2).runs.size(), 6, "The top blur runs over the six chunks it draws on")
    assert_eq(ran, 6, "Six blurs in all, where a run without the cache ran eighteen, and %d without the cache" % without)
    _same(easels, "After the top blur's opacity went to 40%")
    for easel in easels:
        _stroke(easel, STROKES[1], INK[1])
    _same(easels, "and after a stroke below it")
    for easel in easels:
        easel.free()


func test_a_mask_stroke_on_the_top_blur_runs_no_blur_below_it() -> void:
    var easels: Array[SaEasel] = [_stack(true), _stack(false)]
    _both(easels, func(doc: SaDocument) -> void: SaMaskOps.new(doc).add(_layer(doc, 2)))
    for easel in easels:
        _stroke(easel, STROKES[0], INK[0])
    _same(easels, "With a mask on the top blur and a stroke below it")
    var cached: Array[int] = _mask_stroke(easels[0])
    assert_true(_step(easels[0], 0).runs.is_empty(), "At the commit the bottom blur runs nowhere")
    assert_true(_step(easels[0], 1).runs.is_empty(), "nor the middle one")
    assert_false(_step(easels[0], 2).runs.is_empty(), "and the top blur runs where its mask moved")
    assert_eq(cached[1], _step(easels[0], 2).runs.size(), "Its blurs at the commit are the top blur's alone")
    assert_true(cached[0] > 0 and cached[0] <= 2, "Mid-stroke the top blur alone runs, over the two chunks the dab crossed")
    _mask_stroke(easels[1])
    _same(easels, "After the mask stroke on the top blur")
    for easel in easels:
        _stroke(easel, STROKES[4], INK[1])
    _same(easels, "and after a stroke below it")
    for easel in easels:
        easel.free()


## The undo of a stroke on the painting under the three blurs, with the
## painting active, and again with the layer above the stack active, which
## folds the painting and the blurs into the cache below it: the undo folds
## that cache again, where before the fix it showed the stroke until a rebuild.
func test_an_undo_on_the_bottom_layer_clears_the_chunks_above_it() -> void:
    for active: String in ["Background", "Above"]:
        var easels: Array[SaEasel] = [_stack(true), _stack(false)]
        for easel in easels:
            easel.document.set_active_layer(easel.document.get_node(active) as SaLayer)
            easel.process_pending_composite()
        var before := _bytes(easels[0].output)
        _same(easels, "With %s active, before the stroke" % active)
        for easel in easels:
            easel.document.set_active_layer(easel.document.get_node("Background") as SaLayer)
            _stroke(easel, STROKES[1], INK[1], true)
            easel.document.set_active_layer(easel.document.get_node(active) as SaLayer)
            easel.process_pending_composite()
        assert_true(_bytes(easels[0].output) != before, "The stroke shows with %s active" % active)
        _both(easels, func(doc: SaDocument) -> void: assert_true(doc.undo(), "The stroke is a step to undo"))
        _same(easels, "After the undo on the bottom layer with %s active, cached and uncached" % active)
        assert_true(_bytes(easels[0].output) == before, "and the picture is the one before the stroke")
        assert_true(_bytes(easels[1].output) == before, "uncached as well")
        if active == "Background":
            for i in RADII.size():
                assert_false(_step(easels[0], i).runs.is_empty(), "Blur %d, above the undo, ran again" % i)
        for easel in easels:
            easel.free()
