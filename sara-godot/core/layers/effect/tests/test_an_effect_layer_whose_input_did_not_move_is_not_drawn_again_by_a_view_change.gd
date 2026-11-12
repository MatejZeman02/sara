## A view change or a layer action on a large painting holds
## no frame for more than a tenth of a second.
##
## A view change marks every chunk dirty at no layer, and the refresh drew all
## 219 effect layers of a large painting over every chunk again, 260 to 626 ms
## of one frame, for caches that already held their inputs. A view change now
## marks through `SaDocument.reveal_all_allocated_chunks`, `SaEffectStamps`
## keeps where each cache was drawn whole and from what, and the refresh skips
## those chunks while the input stands as it did and only a reveal marked
## them. Any other mark at no layer is drawn again, since a module may have
## written the chunk in place. Each test marks the cache with a colour no
## input draws and reads whether the refresh wrote over it.
##
## The painting: three chunks across and two down, the background hidden, a
## layer Paint holding opaque paint in three chunks inside a group Shared, and
## an effect layer above reading Shared through the fixture invert.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(768, 512)
const HELD: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]
const AT := Vector2i(0, 0)
const PAINT := Color(0.25, 0.5, 0.75, 1.0)
const LATER := Color(0.875, 0.125, 0.375, 1.0)
const SENTINEL := Color(0.0, 1.0, 0.0, 1.0)
const TOLERANCE := 1.0e-4

var _types: SaLayerTypeRegistry


func before_each() -> void:
    _types = Fixtures.make_registries().layer_types
    SaProblems.pending_refusals = PackedStringArray()


func _painting() -> SaEasel:
    var easel := Bench.easel(SIZE)
    var doc := easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    var paint := doc.get_node("Layer 1") as SaLayer
    paint.name = "Paint"
    for grid_pos in HELD:
        paint.get_or_create_chunk(grid_pos).clear(PAINT)
    var shared := SaLayerOps.new(doc).group_layers([paint])
    shared.name = "Shared"
    doc.set_active_layer(shared)
    var effect := SaLayerOps.new(doc).add(SaEffectLayer.TYPE_ID, _types)
    effect.name = "Effect"
    assert_not_null(SaFilterOps.new(doc).attach(effect, Bench.INVERT), "The invert attaches to the effect layer")
    if SaEffectLayer.input_of(effect) != shared:
        SaEffectLayer.read(doc, effect, shared)
    assert_eq(SaEffectLayer.input_of(effect), shared, "The effect reads Shared")
    doc.set_active_layer(paint)
    Bench.composite(easel)
    return easel


## The effect's cache at [constant AT], marked with [constant SENTINEL] so a
## refresh that writes it shows.
static func _marked(doc: SaDocument) -> SaLayer:
    var effect := doc.get_node("Effect") as SaLayer
    effect.chunks[AT].clear(SENTINEL)
    return effect


static func _cache(effect: SaLayer) -> Color:
    return Bench.texel(effect.get_field(AT), Vector2i(10, 10))


static func _near(a: Color, b: Color) -> bool:
    return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a))) <= TOLERANCE


func test_every_chunk_marked_at_no_layer_with_nothing_moved_leaves_the_cache_as_it_was() -> void:
    var easel := _painting()
    var doc := easel.document
    var effect := doc.get_node("Effect") as SaLayer
    assert_true(_near(_cache(effect), PAINT), "The cache holds its input, %s" % _cache(effect))
    _marked(doc)
    # What a zoom, a pan or a turn of the view asks, through `SaToolMachine`.
    doc.reveal_all_allocated_chunks()
    easel.process_pending_composite()
    assert_true(_near(_cache(effect), SENTINEL), "A view change draws no input again, %s" % _cache(effect))
    easel.free()


func test_paint_a_filter_applies_in_place_and_marks_at_no_layer_is_drawn_again() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    var effect := _marked(doc)
    # What `SaFilterApply` does: the chunk written in place, one pixel step,
    # and the chunks marked at no layer.
    var before := paint.duplicate_chunk(AT)
    paint.chunks[AT].clear(LATER)
    doc.record_pixel_step("Apply", paint, {AT: before})
    doc.invalidate_chunks([AT])
    easel.process_pending_composite()
    assert_true(_near(_cache(effect), LATER), "The cache follows the paint, %s" % _cache(effect))
    easel.free()


func test_a_member_s_opacity_written_and_marked_at_no_layer_is_drawn_again() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    var effect := _marked(doc)
    paint.opacity = 0.5
    doc.reveal_all_allocated_chunks()
    easel.process_pending_composite()
    assert_false(_near(_cache(effect), SENTINEL), "A member's opacity moves the group the effect reads")
    easel.free()


func test_a_chunk_dropped_from_the_input_is_dropped_from_the_cache() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    var effect := _marked(doc)
    paint.set_chunk(AT, null)
    doc.reveal_all_allocated_chunks()
    easel.process_pending_composite()
    assert_false(effect.chunks.has(AT), "The effect lets go of the chunk its input let go of")
    easel.free()


func test_a_history_step_that_moved_nothing_it_can_see_draws_every_effect_again() -> void:
    var easel := _painting()
    var doc := easel.document
    var effect := _marked(doc)
    # A step that wrote in place and named nothing, which only the history says.
    doc.history.commit("Unseen", func() -> void: pass, {})
    doc.reveal_all_allocated_chunks()
    easel.process_pending_composite()
    assert_true(_near(_cache(effect), PAINT), "The cache is its input again, %s" % _cache(effect))
    easel.free()


func test_a_written_part_of_a_chunk_leaves_no_stamp_and_the_next_mark_draws_it_whole() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    var effect := _marked(doc)
    doc.invalidate_chunk_regions({AT: Rect2i(0, 0, 32, 32)}, paint)
    easel.process_pending_composite()
    var outside := Bench.texel(effect.get_field(AT), Vector2i(100, 100))
    assert_true(_near(outside, SENTINEL), "A region named at Paint writes that region alone, %s" % outside)
    doc.reveal_all_allocated_chunks()
    easel.process_pending_composite()
    outside = Bench.texel(effect.get_field(AT), Vector2i(100, 100))
    assert_true(_near(outside, PAINT), "and the chunk it wrote part of is drawn whole at the next mark, %s" % outside)
    easel.free()


func test_paint_written_in_place_and_marked_at_no_layer_with_nothing_else_is_drawn_again() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    var effect := _marked(doc)
    # What a module that paints a chunk it already held does: no step, no
    # name, and a mark at no layer, which counts as a change below every layer.
    paint.chunks[AT].clear(LATER)
    doc.invalidate_all_allocated_chunks()
    easel.process_pending_composite()
    assert_true(_near(_cache(effect), LATER), "A mark at no layer draws the cache again, %s" % _cache(effect))
    easel.free()


func test_a_reveal_in_the_frame_of_a_mark_at_no_layer_skips_nothing_the_mark_reached() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    var effect := _marked(doc)
    paint.chunks[AT].clear(LATER)
    doc.invalidate_chunks([AT])
    doc.reveal_all_allocated_chunks()
    easel.process_pending_composite()
    assert_true(_near(_cache(effect), LATER), "The mark wins over the reveal after it, %s" % _cache(effect))
    _marked(doc)
    paint.chunks[AT].clear(PAINT)
    doc.reveal_all_allocated_chunks()
    doc.invalidate_chunks([AT])
    easel.process_pending_composite()
    assert_true(_near(_cache(effect), PAINT), "and over the reveal before it, %s" % _cache(effect))
    easel.free()


func test_a_reveal_names_the_chunks_it_alone_marked_as_still() -> void:
    var easel := _painting()
    var doc := easel.document
    doc.reveal_all_allocated_chunks()
    doc.invalidate_chunks([AT])
    doc.consume_dirty_chunks()
    assert_false(doc.still.has(AT), "A chunk another mark reached is not still")
    assert_true(doc.still.has(Vector2i(1, 0)), "A chunk only the reveal reached is, %s" % [doc.still.keys()])
    doc.invalidate_all_allocated_chunks()
    doc.consume_dirty_chunks()
    assert_true(doc.still.is_empty(), "and a mark at no layer leaves none, %s" % [doc.still.keys()])
    easel.free()


func test_a_layer_moved_beside_the_input_leaves_the_cache_as_it_was() -> void:
    var easel := _painting()
    var doc := easel.document
    var effect := doc.get_node("Effect") as SaLayer
    doc.set_active_layer(effect)
    var other := SaLayerOps.new(doc).add()
    other.get_or_create_chunk(AT).clear(LATER)
    Bench.composite(easel)
    _marked(doc)
    # A move of the stack, which the fold's debt marks as a reveal.
    assert_true(SaLayerOps.new(doc).move(other, -1), "The other layer moves down")
    _drawn(easel)
    assert_true(_near(_cache(effect), SENTINEL), "A move beside the input draws no input again, %s" % _cache(effect))
    easel.free()


## Paint at the top level, a layer Upper above it holding [constant LATER] at
## [constant AT], and an effect above both reading Paint alone.
func _merging() -> SaEasel:
    var easel := Bench.easel(SIZE)
    var doc := easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    var paint := doc.get_node("Layer 1") as SaLayer
    paint.name = "Paint"
    for grid_pos in HELD:
        paint.get_or_create_chunk(grid_pos).clear(PAINT)
    var upper := SaLayerOps.new(doc).add()
    upper.name = "Upper"
    upper.get_or_create_chunk(AT).clear(LATER)
    var effect := SaLayerOps.new(doc).add(SaEffectLayer.TYPE_ID, _types)
    effect.name = "Effect"
    assert_not_null(SaFilterOps.new(doc).attach(effect, Bench.INVERT), "The invert attaches to the effect layer")
    SaEffectLayer.read(doc, effect, paint)
    assert_eq(SaEffectLayer.input_of(effect), paint, "The effect reads Paint")
    doc.set_active_layer(paint)
    Bench.composite(easel)
    return easel


func test_a_merge_into_the_input_draws_the_cache_again() -> void:
    var easel := _merging()
    var doc := easel.document
    var effect := doc.get_node("Effect") as SaLayer
    assert_true(_near(_cache(effect), PAINT), "The cache holds Paint, %s" % _cache(effect))
    _marked(doc)
    # The merge writes Paint in place and marks only through the fold's debt.
    assert_true(SaLayerOps.new(doc).merge_down(doc.get_node("Upper") as SaLayer), "Upper merges down")
    _drawn(easel)
    assert_true(_near(_cache(effect), LATER), "The merged paint reaches the cache, %s" % _cache(effect))
    _marked(doc)
    assert_true(doc.undo(), "The merge undoes")
    _drawn(easel)
    assert_true(_near(_cache(effect), PAINT), "and so does the undo, %s" % _cache(effect))
    easel.free()


func test_a_step_holding_pixels_no_layer_said_it_moved_for_draws_every_effect_again() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    var effect := _marked(doc)
    # A step that wrote Paint in place and told nobody, beside a change that
    # moves the stack's signature but not the input's, as a merge's does.
    var before := paint.duplicate_chunk(AT)
    paint.chunks[AT].clear(LATER)
    doc.history.commit("Unheard", func() -> void: pass, {AT: before})
    (doc.get_node("Background") as SaLayer).opacity = 0.5
    doc.reveal_all_allocated_chunks()
    easel.process_pending_composite()
    assert_true(_near(_cache(effect), LATER), "The step's pixels reach the cache, %s" % _cache(effect))
    easel.free()


## The frames a change takes to show, its debt paid and its marks drawn, with
## no rebuild of this suite's own.
static func _drawn(easel: SaEasel) -> void:
    for frame in 3:
        easel.process_pending_composite()


func test_a_member_of_the_input_deleted_draws_the_cache_again() -> void:
    var easel := _painting()
    var doc := easel.document
    var paint := doc.get_node("Paint") as SaLayer
    doc.set_active_layer(paint)
    var upper := SaLayerOps.new(doc).add()
    upper.get_or_create_chunk(AT).clear(LATER)
    Bench.composite(easel)
    var effect := doc.get_node("Effect") as SaLayer
    assert_eq(SaLayerStack.parent_of(upper), doc.get_node("Shared"), "The new layer is a member of Shared")
    assert_true(_near(_cache(effect), LATER), "The cache shows the member on top, %s" % _cache(effect))
    _marked(doc)
    assert_true(SaLayerOps.new(doc).remove(upper), "The member is deleted")
    _drawn(easel)
    assert_true(_near(_cache(effect), PAINT), "The cache shows Paint again, %s" % _cache(effect))
    easel.free()
