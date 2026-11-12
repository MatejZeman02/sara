## A filter's canvas preview reaches the effect layers that read
## its layer, and clearing it, which is what Cancel does, puts them back.
##
## Bug 5 of the hunt of 2026-10-08: with Preview on canvas ticked, a blur on the
## photograph blurred the corners where the photograph showed directly while
## the kaleidoscope above kept the sharp photograph until Apply. The walk ran
## the previewed pass where it drew the active layer, and `SaEffectLayer` read
## its input's committed chunks. Both now read the layer through
## `SaPointPreview.drawn`, and an effect reading a group asks its tree render
## for the same.
##
## The painting: three chunks across and two down, the grey background hidden,
## a layer named Source holding red in chunk (0, 0) and blue in (1, 0) and
## (0, 1), and an effect layer above it reading Source through the fixture
## invert. A preview is set and cleared the way `SaFilterDialogWindow` sets and
## clears it: the run's pass handed to the compositor, the active layer's chunks
## marked dirty, and the next composite.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const BoxBlurFilter = preload("res://modules/sara-base-modules/base/usual/box_blur_filter.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const InvertFilter = preload("res://tests/fixtures/modules/point-fixture/invert_filter.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(768, 512)
const RED := Color(1.0, 0.0, 0.0, 1.0)
const BLUE := Color(0.0, 0.0, 1.0, 1.0)
const GREEN := Color(0.0, 1.0, 0.0, 1.0)
## Red through the fixture invert.
const CYAN := Color(0.0, 1.0, 1.0, 1.0)
const TOLERANCE := 1.0e-3
const BLUR_OWNER: StringName = &"sara-base-modules"
const RADIUS := 4
## A texel deep in the red chunk, and the last column of it, beside the blue.
const ON_RED := Vector2i(100, 100)
const SEAM := Vector2i(255, 128)


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()


func _painting() -> SaEasel:
    ModuleLoader.module_dirs[BLUR_OWNER] = "res://modules/sara-base-modules/base"
    var easel := Bench.easel(SIZE)
    easel.compositor.filter_chain.registry.register(_blur(), BLUR_OWNER)
    var doc := easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    var source := doc.get_node("Layer 1") as SaLayer
    source.name = "Source"
    doc.set_active_layer(source)
    source.get_or_create_chunk(Vector2i(0, 0)).clear(RED)
    source.get_or_create_chunk(Vector2i(1, 0)).clear(BLUE)
    source.get_or_create_chunk(Vector2i(0, 1)).clear(BLUE)
    var effect := SaLayerOps.new(doc).add(SaEffectLayer.TYPE_ID, Fixtures.make_registries().layer_types)
    effect.name = "Effect"
    assert_true(effect.source == source, "The effect layer reads the layer it was made above")
    assert_not_null(SaFilterOps.new(doc).attach(effect, Bench.INVERT), "The invert attaches to the effect layer")
    doc.set_active_layer(source)
    Bench.composite(easel)
    return easel


func _blur() -> SaFilter:
    var blur := BoxBlurFilter.new()
    blur.write_parameter(&"radius", RADIUS)
    return blur


## *filter* run as the dialog runs it on the active layer, and its pass shown
## on the canvas, as a ticked Preview box shows it.
func _preview(easel: SaEasel, filter: SaFilter, owner: StringName) -> void:
    var doc := easel.document
    var ctx := SaFilterContext.new(doc, doc.active_layer, owner, filter.title(), true)
    assert_true(SaFilterApply.call_run(filter, ctx), "%s runs clean" % filter.title())
    assert_not_null(ctx.point, "and records a pass the compositor previews")
    easel.compositor.point_preview.set_pass(doc, ctx.point)
    _redraw(easel)


## The preview taken back off, as Cancel takes it.
func _cancel(easel: SaEasel) -> void:
    easel.compositor.point_preview.clear(easel.document)
    _redraw(easel)


static func _redraw(easel: SaEasel) -> void:
    var doc := easel.document
    doc.invalidate_chunks(doc.active_layer.chunks.keys())
    easel.request_composite()
    easel.process_pending_composite()


static func _near(a: Color, b: Color) -> bool:
    return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a))) <= TOLERANCE


## What *effect* holds at *at*, in document pixels: its input as it drew it.
static func _cached(effect: SaLayer, at: Vector2i) -> Color:
    @warning_ignore("integer_division")
    var grid_pos := Vector2i(at.x / SaChunk.SIZE, at.y / SaChunk.SIZE)
    return Bench.texel(effect.get_field(grid_pos), at - grid_pos * SaChunk.SIZE)


func test_a_previewed_point_pass_reaches_the_effect_and_cancel_puts_it_back() -> void:
    var easel := _painting()
    var effect := easel.document.get_node("Effect") as SaLayer
    var cached := _cached(effect, ON_RED)
    assert_true(_near(cached, RED), "Before the preview the effect holds its input's red, %s" % cached)
    var shown := Bench.texel(easel.output, ON_RED)
    assert_true(_near(shown, CYAN), "and the canvas shows it through the effect's invert, %s" % shown)

    _preview(easel, InvertFilter.new(), Bench.OWNER)
    cached = _cached(effect, ON_RED)
    assert_true(_near(cached, CYAN), "With an invert previewed on the input the effect reads it inverted, %s" % cached)
    shown = Bench.texel(easel.output, ON_RED)
    assert_true(_near(shown, RED), "and the canvas shows the preview through the effect, inverted back, %s" % shown)
    var source := easel.document.get_node("Source") as SaLayer
    var painted := Bench.texel(source.get_field(Vector2i(0, 0)), ON_RED)
    assert_true(_near(painted, RED), "The preview writes nothing into the input's chunk, %s" % painted)

    _cancel(easel)
    cached = _cached(effect, ON_RED)
    assert_true(_near(cached, RED), "Cancel brings the input's own red back into the effect, %s" % cached)
    shown = Bench.texel(easel.output, ON_RED)
    assert_true(_near(shown, CYAN), "and the canvas back to the effect of the plain input, %s" % shown)
    easel.free()


func test_a_previewed_blur_reaches_the_effect_across_the_seam() -> void:
    var easel := _painting()
    var effect := easel.document.get_node("Effect") as SaLayer
    _preview(easel, _blur(), BLUR_OWNER)
    var cached := _cached(effect, SEAM)
    assert_almost_eq(cached.r, 5.0 / 9.0, TOLERANCE, "The effect reads the blurred input, red from its own chunk, %s" % cached)
    assert_almost_eq(cached.b, 4.0 / 9.0, TOLERANCE, "and blue from the chunk beside it, %s" % cached)
    _cancel(easel)
    cached = _cached(effect, SEAM)
    assert_true(_near(cached, RED), "Cancel brings the sharp edge back, %s" % cached)
    easel.free()


func test_a_preview_on_another_layer_leaves_the_effect_as_it_is() -> void:
    var easel := _painting()
    var doc := easel.document
    var other := SaLayerOps.new(doc).add()
    other.name = "Other"
    other.get_or_create_chunk(Vector2i(0, 0)).clear(GREEN)
    doc.set_active_layer(other)
    Bench.composite(easel)
    var effect := doc.get_node("Effect") as SaLayer
    _preview(easel, InvertFilter.new(), Bench.OWNER)
    var cached := _cached(effect, ON_RED)
    assert_true(_near(cached, RED), "A preview on a layer the effect does not read leaves it its input, %s" % cached)
    _cancel(easel)
    easel.free()


func test_an_effect_reading_a_group_reads_the_preview_on_a_member() -> void:
    var easel := _painting()
    var doc := easel.document
    var source := doc.get_node("Source") as SaLayer
    var group := SaLayerOps.new(doc).group_active()
    var effect := doc.get_node("Effect") as SaLayer
    assert_true(SaEffectLayer.read(doc, effect, group), "The effect reads the group holding the input")
    doc.set_active_layer(source)
    Bench.composite(easel)
    _preview(easel, InvertFilter.new(), Bench.OWNER)
    var cached := _cached(effect, ON_RED)
    assert_true(_near(cached, CYAN), "An invert previewed on a member reaches the effect reading the group, %s" % cached)

    # A flatten or a merge renders the tree for what it writes into the
    # document, and the preview is not part of the document.
    var target := SaTexture.new(Vector2i(SaChunk.SIZE, SaChunk.SIZE), doc.color_space.texel_format())
    easel.compositor.clear_scratch_batch([[target, Rect2i(Vector2i.ZERO, target.size)]])
    SaTreeRender.new(doc).render_members(target, group, Vector2i(0, 0))
    var rendered := Bench.texel(target, ON_RED)
    assert_true(_near(rendered, RED), "A render that was not asked for the preview leaves it out, %s" % rendered)

    _cancel(easel)
    cached = _cached(effect, ON_RED)
    assert_true(_near(cached, RED), "Cancel brings the member's own red back, %s" % cached)
    easel.free()
