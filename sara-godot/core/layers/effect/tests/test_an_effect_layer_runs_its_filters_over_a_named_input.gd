## An effect layer whose input is another named node holds that
## node's composite as a cache, refreshed only where the input moved, allocated
## only where the input shows something, run through its own records, baked by a
## flatten and saved as its recipe.
##
## The painting: three chunks across and two down, the grey background hidden,
## a layer named Source holding opaque paint in three chunks, and an effect
## layer above it reading Source through the fixture invert.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(768, 512)
const HELD: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]
const PAINT := Color(0.25, 0.5, 0.75, 1.0)
const INVERTED := Color(0.75, 0.5, 0.25, 1.0)
const STROKE := Color(0.875, 0.125, 0.375, 1.0)
const SENTINEL := Color(0.0, 1.0, 0.0, 1.0)
const TOLERANCE := 1.0e-4

var _types: SaLayerTypeRegistry


func before_each() -> void:
    _types = Fixtures.make_registries().layer_types
    SaProblems.pending_refusals = PackedStringArray()


## The painting of the header, Source active below the effect layer, which is
## made above it and so reads it.
func _painting() -> SaEasel:
    var easel := Bench.easel(SIZE)
    var doc := easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    var source := doc.get_node("Layer 1") as SaLayer
    source.name = "Source"
    doc.set_active_layer(source)
    for grid_pos in HELD:
        source.get_or_create_chunk(grid_pos).clear(PAINT)
    var effect := SaLayerOps.new(doc).add(SaEffectLayer.TYPE_ID, _types)
    effect.name = "Effect"
    assert_not_null(SaFilterOps.new(doc).attach(effect, Bench.INVERT), "The invert attaches to the effect layer")
    doc.set_active_layer(source)
    Bench.composite(easel)
    return easel


## One hard dab of *color* at *pos* on the active layer, begun and committed
## as a stroke is.
static func _stroke(doc: SaDocument, pos: Vector2, radius: float, color: Color) -> void:
    var compute := PaintKernel.compute()
    doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    var region := Rect2(pos.x - radius, pos.y - radius, radius * 2.0, radius * 2.0)
    var paint := SaPaintContext.for_region(doc, region, false)
    paint.dispatch_batch(
        compute,
        "paint",
        func(target: SaPaintContext.Target) -> void:
            compute.set_texture(0, target.texture.rid)
            compute.set_push_constant_float_array(
                PaintKernel.pack_params(paint.local_point(target, pos), target.render_offset, color, radius, 1.0, 1.0, 1.0)
            )
    )
    paint.commit_invalidation()
    doc.commit_stroke()


static func _keys(layer: SaLayer) -> Array[Vector2i]:
    var found: Array[Vector2i] = []
    found.assign(layer.chunks.keys())
    found.sort()
    return found


static func _near(a: Color, b: Color) -> bool:
    return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a))) <= TOLERANCE


static func _bytes(texture: SaTexture) -> PackedByteArray:
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)


## The widest gap between two canvases over a sparse grid of texels, read
## premultiplied, since a texel with no alpha has no colour to compare.
static func _worst(a: PackedByteArray, b: PackedByteArray, format: int) -> float:
    var worst := 0.0
    for y in range(0, SIZE.y, 7):
        for x in range(0, SIZE.x, 7):
            var i := y * SIZE.x + x
            var p := SaFieldSpec.decode_texel(a, format, i)
            var q := SaFieldSpec.decode_texel(b, format, i)
            var gaps := [absf(p.r * p.a - q.r * q.a), absf(p.g * p.a - q.g * q.a), absf(p.b * p.a - q.b * q.a), absf(p.a - q.a)]
            worst = maxf(worst, gaps.max())
    return worst


static func _layers(doc: SaDocument) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for child in doc.get_children():
        if child is SaLayer:
            found.append(child)
    return found


func _refused(said: String, what: String) -> void:
    var lines := "\n".join(SaProblems.pending_refusals)
    assert_true(lines.contains(said), "%s, with its sentence: %s" % [what, lines])
    SaProblems.pending_refusals = PackedStringArray()


func test_it_holds_its_input_where_the_input_holds_paint_and_nothing_elsewhere() -> void:
    var easel := _painting()
    var doc := easel.document
    var effect := doc.get_node("Effect") as SaLayer
    var source := doc.get_node("Source") as SaLayer
    assert_true(effect.is_effect() and effect.source == source, "A new effect layer reads the layer it was made above")
    assert_true(effect.refuses_paint(), "and takes no paint")
    assert_eq(_keys(effect), _keys(source), "It holds a chunk exactly where its input does")
    for grid_pos in HELD:
        var cached := Bench.texel(effect.get_field(grid_pos), Vector2i(40, 40))
        assert_true(_near(cached, PAINT), "Its chunk at %s holds the input's paint, %s" % [grid_pos, cached])
    var shown := Bench.texel(easel.output, Vector2i(300, 100))
    assert_true(_near(shown, INVERTED), "and the canvas shows it through its own record, %s" % shown)
    var empty := Bench.texel(easel.output, Vector2i(600, 400))
    assert_true(empty.a <= TOLERANCE, "Where the input holds nothing the canvas holds nothing, %s" % empty)
    easel.free()


func test_a_stroke_on_the_input_moves_only_the_chunks_it_crosses() -> void:
    var easel := _painting()
    var doc := easel.document
    var effect := doc.get_node("Effect") as SaLayer
    for grid_pos in HELD:
        effect.chunks[grid_pos].clear(SENTINEL)
    # Across the edge between the two top chunks.
    _stroke(doc, Vector2(256.0, 100.0), 12.0, STROKE)
    easel.process_pending_composite()
    # The commit shows the band the stroke painted and not its whole chunks.
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0)]:
        var far := Bench.texel(effect.get_field(grid_pos), Vector2i(128, 200))
        assert_true(
            _near(far, SENTINEL), "The chunk at %s the stroke crossed is rewritten only where it painted, %s" % [grid_pos, far]
        )
    var struck := Bench.texel(effect.get_field(Vector2i(1, 0)), Vector2i(0, 100))
    assert_true(_near(struck, STROKE), "holding the stroke, %s" % struck)
    var untouched := Bench.texel(effect.get_field(Vector2i(0, 1)), Vector2i(128, 128))
    assert_true(_near(untouched, SENTINEL), "The chunk the stroke did not cross is not rewritten, %s" % untouched)
    # A stroke where the input held nothing gives the effect one chunk there.
    _stroke(doc, Vector2(640.0, 400.0), 12.0, STROKE)
    easel.process_pending_composite()
    var wanted: Array[Vector2i] = HELD.duplicate()
    wanted.append(Vector2i(2, 1))
    wanted.sort()
    assert_eq(_keys(effect), wanted, "A stroke on empty canvas allocates the one chunk it lands in")
    var shown := Bench.texel(easel.output, Vector2i(640, 400))
    assert_true(_near(shown, Color(1.0 - STROKE.r, 1.0 - STROKE.g, 1.0 - STROKE.b, 1.0)), "shown inverted, %s" % shown)
    easel.free()


func test_a_refresh_writes_only_the_dirty_region_of_a_chunk() -> void:
    var easel := _painting()
    var doc := easel.document
    var effect := doc.get_node("Effect") as SaLayer
    effect.chunks[Vector2i(0, 0)].clear(SENTINEL)
    # Named at the input, because a change at no layer over an input nothing
    # moved is one the refresh skips, `SaEffectStamps`.
    doc.invalidate_chunk_regions({Vector2i(0, 0): Rect2i(0, 0, 32, 32)}, doc.get_node("Source") as SaLayer)
    easel.process_pending_composite()
    var inside := Bench.texel(effect.get_field(Vector2i(0, 0)), Vector2i(10, 10))
    var outside := Bench.texel(effect.get_field(Vector2i(0, 0)), Vector2i(100, 100))
    assert_true(_near(inside, PAINT), "Inside the dirty region the cache is its input, %s" % inside)
    assert_true(_near(outside, SENTINEL), "and outside it untouched, %s" % outside)
    easel.free()


func test_an_erased_input_chunk_takes_the_effects_with_it() -> void:
    var easel := _painting()
    var doc := easel.document
    var source := doc.get_node("Source") as SaLayer
    var effect := doc.get_node("Effect") as SaLayer
    source.set_chunk(Vector2i(0, 1), null)
    doc.invalidate_chunks([Vector2i(0, 1)])
    easel.process_pending_composite()
    assert_false(effect.chunks.has(Vector2i(0, 1)), "The effect drops the chunk its input dropped")
    assert_eq(_keys(effect), _keys(source), "and holds what its input holds")
    easel.free()


func test_it_reads_a_group_as_the_group_composites() -> void:
    var easel := _painting()
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    var source := doc.get_node("Source") as SaLayer
    doc.set_active_layer(source)
    var group := ops.group_active()
    doc.set_active_layer(source)
    var over := ops.add()
    over.name = "Over"
    over.get_or_create_chunk(Vector2i(1, 1)).clear(STROKE)
    assert_true(SaLayerStack.parent_of(over) == group, "The layer made above a member is a member")
    var effect := doc.get_node("Effect") as SaLayer
    assert_true(SaEffectLayer.read(doc, effect, group), "The effect reads the group")
    Bench.composite(easel)
    var wanted: Array[Vector2i] = HELD.duplicate()
    wanted.append(Vector2i(1, 1))
    wanted.sort()
    assert_eq(_keys(effect), wanted, "It holds a chunk wherever a member does")
    var cached := Bench.texel(effect.get_field(Vector2i(1, 1)), Vector2i(20, 20))
    assert_true(_near(cached, STROKE), "each holding the group's composite, %s" % cached)
    assert_true(doc.undo(), "The pick is one step")
    assert_true(effect.source == source, "whose undo reads the layer again")
    easel.free()


func test_what_it_cannot_read_or_take_is_refused_with_a_sentence() -> void:
    var easel := _painting()
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    var effect := doc.get_node("Effect") as SaLayer
    SaProblems.announce = false
    assert_false(SaEffectLayer.read(doc, effect, effect), "Reading itself is refused")
    _refused("'Effect' shows this layer, so reading it would read itself.", "Reading itself")
    doc.set_active_layer(effect)
    var above := ops.add()
    assert_false(SaLayerRefusals.new(doc).can_take(above, effect), "Nothing merges onto an effect layer")
    assert_false(SaFilterOps.new(doc).flatten(effect, effect.filters[0]), "and its record does not flatten into its cache")
    _refused("holds no paint to write into", "Flattening its record")
    doc.set_active_layer(effect)
    var group := ops.group_active()
    assert_false(SaEffectLayer.read(doc, effect, group), "Reading the group that holds it is refused")
    _refused("so reading it would read itself.", "Reading its own group")
    SaProblems.announce = true
    easel.free()


func test_a_flatten_bakes_it_into_ordinary_pixels() -> void:
    var easel := _painting()
    var doc := easel.document
    var before := _bytes(easel.output)
    assert_true(SaLayerOps.new(doc).flatten(), "The flatten runs")
    assert_eq(_layers(doc).size(), 1, "One layer is left")
    var left := _layers(doc)[0]
    assert_false(left.is_effect(), "and it is a paint layer")
    Bench.composite(easel)
    var worst := _worst(before, _bytes(easel.output), easel.output.format)
    assert_true(worst <= TOLERANCE, "The flattened canvas is the canvas before it, worst %s" % worst)
    easel.free()


func test_a_merge_down_bakes_it_into_the_layer_below() -> void:
    var easel := _painting()
    var doc := easel.document
    var before := _bytes(easel.output)
    var effect := doc.get_node("Effect") as SaLayer
    assert_true(SaLayerOps.new(doc).merge_down(effect), "The effect merges down onto its input")
    assert_null(doc.get_node_or_null("Effect"), "and is gone")
    Bench.composite(easel)
    var worst := _worst(before, _bytes(easel.output), easel.output.format)
    assert_true(worst <= TOLERANCE, "The canvas after the merge is the canvas before it, worst %s" % worst)
    var baked := Bench.texel((doc.get_node("Source") as SaLayer).get_field(Vector2i(0, 0)), Vector2i(40, 40))
    assert_true(_near(baked, INVERTED), "The layer below holds its pixels, %s" % baked)
    easel.free()


func test_it_saves_as_its_recipe_in_a_file_stamped_eight() -> void:
    var easel := _painting()
    var doc := easel.document
    var effect := doc.get_node("Effect") as SaLayer
    effect.add_mask(1.0).get_or_create(Vector2i(0, 0)).clear(Color(0.0, 0.0, 0.0, 0.0))
    Bench.composite(easel)
    assert_eq(SaSadFile.version_for(doc), 8, "A document holding an effect layer is version 8")
    var path := ProjectSettings.globalize_path(SaDataRoot.path("k4_effect_layer.sad"))
    assert_eq(SaExport.save_sad(doc, path), OK, "It saves")
    var loaded := Bench.easel(SIZE)
    assert_eq(SaExport.load_sad(loaded.document, path, loaded.compositor), OK, "It opens")
    DirAccess.remove_absolute(path)
    _types.rebind(_layers(loaded.document))
    var reopened := loaded.document.get_node("Effect") as SaLayer
    assert_true(reopened != null and reopened.is_effect(), "as an effect layer")
    assert_true(reopened.source == loaded.document.get_node("Source"), "reading its input by name")
    assert_eq(reopened.filters.size(), 1, "holding its record")
    assert_true(reopened.mask != null and reopened.mask.is_own(), "and its mask")
    Bench.composite(loaded)
    var held: Array[Vector2i] = HELD.duplicate()
    held.sort()
    assert_eq(_keys(reopened), held, "Its cache is made again where its input holds paint")
    var worst := _worst(_bytes(easel.output), _bytes(loaded.output), easel.output.format)
    assert_true(worst <= TOLERANCE, "The output reads the same, worst %s" % worst)
    easel.free()
    loaded.free()


func test_one_folded_into_an_isolated_group_follows_its_input() -> void:
    var easel := _painting()
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    var effect := doc.get_node("Effect") as SaLayer
    var source := doc.get_node("Source") as SaLayer
    doc.set_active_layer(effect)
    var group := ops.group_active()
    ops.set_isolated(group, true)
    doc.set_active_layer(source)
    Bench.composite(easel)
    assert_true(doc.fold.folds_effect(effect), "The isolated group's cache holds the effect layer")
    _stroke(doc, Vector2(100.0, 100.0), 12.0, STROKE)
    easel.process_pending_composite()
    doc.update_caches()
    easel.process_pending_composite()
    var shown := Bench.texel(easel.output, Vector2i(100, 100))
    var over := Color(1.0 - STROKE.r, 1.0 - STROKE.g, 1.0 - STROKE.b, 1.0)
    assert_true(_near(shown, over), "After the rebuild it asked for the canvas shows the stroke through it, %s" % shown)
    easel.free()
