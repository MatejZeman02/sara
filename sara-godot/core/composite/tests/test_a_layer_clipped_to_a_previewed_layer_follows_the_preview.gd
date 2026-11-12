## A layer clipped to a previewed layer follows the preview,
## and Cancel and Apply each leave it what the base then shows.
##
## sent the canvas preview and every effect layer through
## `SaPointPreview.drawn`, but a layer clipped to the previewed layer still read
## the base's stored alpha in `SaLayerShown.clip_alpha`: a green
## layer clipped to a red base compositing at alpha 1.0 one texel inside the
## base's edge, where a box blur of radius 4 previewed on the base read 0.556.
## `SaCompositor.clip_alpha` now reads the base's chunk through the same
## `drawn` while the compositor draws a canvas, from the effect layers' refresh
## through the walk, and reads it as stored in every render that writes the
## document.
##
## The painting: three chunks across and two down, the grey background hidden,
## a layer named Base holding opaque red in chunk (0, 0) and a transparent
## chunk at (1, 0), and a green layer above it clipped to it over both chunks.
## A preview is set and cleared the way `SaFilterDialogWindow` sets and clears
## it: the run's pass handed to the compositor, the active layer's chunks
## marked dirty, and the next composite.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const BoxBlurFilter = preload("res://modules/sara-base-modules/base/usual/box_blur_filter.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(768, 512)
const RED := Color(1.0, 0.0, 0.0, 1.0)
const GREEN := Color(0.0, 1.0, 0.0, 1.0)
const CLEAR := Color(0.0, 0.0, 0.0, 0.0)
const TOLERANCE := 1.0e-3
const BLUR_OWNER: StringName = &"sara-base-modules"
const RADIUS := 4
## The last column of the red chunk, whose blur window of nine reaches four
## texels into the transparent chunk beside it, and the first column of that
## chunk, which the blur reaches from five texels of red.
const EDGE := Vector2i(255, 128)
const PAST := Vector2i(256, 128)
## The base's blurred alpha at each: five ninths and four ninths.
const EDGE_ALPHA := 5.0 / 9.0
const PAST_ALPHA := 4.0 / 9.0
const KINDS: Array[String] = ["generated", "adjustment", "grouped", "effect"]


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()


func _painting() -> SaEasel:
    ModuleLoader.module_dirs[BLUR_OWNER] = "res://modules/sara-base-modules/base"
    var easel := Bench.easel(SIZE)
    easel.compositor.filter_chain.registry.register(_blur(), BLUR_OWNER)
    var doc := easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    var base := doc.get_node("Layer 1") as SaLayer
    base.name = "Base"
    doc.set_active_layer(base)
    base.get_or_create_chunk(Vector2i(0, 0)).clear(RED)
    base.get_or_create_chunk(Vector2i(1, 0)).clear(CLEAR)
    var clipped := SaLayerOps.new(doc).add()
    clipped.name = "Clipped"
    clipped.get_or_create_chunk(Vector2i(0, 0)).clear(GREEN)
    clipped.get_or_create_chunk(Vector2i(1, 0)).clear(GREEN)
    SaLayerStack.set_clip_to_below(doc, clipped, true)
    assert_true(SaLayerStack.clip_base(doc, clipped) == base, "The green layer clips to the base")
    doc.set_active_layer(base)
    Bench.composite(easel)
    return easel


func _blur() -> SaFilter:
    var blur := BoxBlurFilter.new()
    blur.write_parameter(&"radius", RADIUS)
    return blur


## The blur run as the dialog runs it on the active layer, and its pass shown
## on the canvas, as a ticked Preview box shows it. Answers the run, which
## Apply writes.
func _preview(easel: SaEasel) -> SaFilterContext:
    var doc := easel.document
    var filter := _blur()
    var ctx := SaFilterContext.new(doc, doc.active_layer, BLUR_OWNER, filter.title(), true)
    assert_true(SaFilterApply.call_run(filter, ctx), "The blur runs clean")
    assert_not_null(ctx.point, "and records a pass the compositor previews")
    easel.compositor.point_preview.set_pass(doc, ctx.point)
    _redraw(easel)
    return ctx


## The preview taken back off, as Cancel takes it.
func _cancel(easel: SaEasel) -> void:
    easel.compositor.point_preview.clear(easel.document)
    _redraw(easel)


## The preview taken off and the run written into the base, as Apply does it.
func _apply(easel: SaEasel, ctx: SaFilterContext) -> void:
    easel.compositor.point_preview.clear(easel.document)
    assert_true(SaFilterApply.apply(ctx, "Box Blur"), "Apply writes the blur into the base")
    _redraw(easel)


static func _redraw(easel: SaEasel) -> void:
    var doc := easel.document
    doc.invalidate_chunks(doc.active_layer.chunks.keys())
    easel.request_composite()
    easel.process_pending_composite()


func test_a_clipped_layer_follows_a_blur_previewed_on_its_base() -> void:
    var easel := _painting()
    var shown := Bench.texel(easel.output, EDGE)
    assert_almost_eq(shown.a, 1.0, TOLERANCE, "Before the preview the green covers the red edge whole, %s" % shown)
    assert_almost_eq(shown.g, 1.0, TOLERANCE, "in green, %s" % shown)
    shown = Bench.texel(easel.output, PAST)
    assert_almost_eq(shown.a, 0.0, TOLERANCE, "and nothing shows past the edge, where the base is clear, %s" % shown)

    # The green covers the base whole, so the group shows green under the
    # base's alpha and none of the red, as a clip group has.
    _preview(easel)
    shown = Bench.texel(easel.output, EDGE)
    assert_almost_eq(shown.a, EDGE_ALPHA, TOLERANCE, "With the blur previewed the green clips to the blurred edge, %s" % shown)
    shown = Bench.texel(easel.output, PAST)
    assert_almost_eq(shown.a, PAST_ALPHA, TOLERANCE, "and shows past it, where the blur carried the red, %s" % shown)
    assert_almost_eq(shown.r, 0.0, TOLERANCE, "in green with none of the red, %s" % shown)
    var base := easel.document.get_node("Base") as SaLayer
    var painted := Bench.texel(base.get_field(Vector2i(0, 0)), EDGE)
    assert_almost_eq(painted.a, 1.0, TOLERANCE, "The preview writes nothing into the base's chunk, %s" % painted)
    easel.free()


func test_cancel_gives_the_clipped_layer_its_look_back() -> void:
    var easel := _painting()
    var before := Bench.texel(easel.output, EDGE)
    _preview(easel)
    _cancel(easel)
    var shown := Bench.texel(easel.output, EDGE)
    assert_true(shown.is_equal_approx(before), "Cancel gives the edge its look back, %s against %s" % [shown, before])
    shown = Bench.texel(easel.output, PAST)
    assert_almost_eq(shown.a, 0.0, TOLERANCE, "and nothing shows past it again, %s" % shown)
    easel.free()


func test_apply_writes_what_the_preview_showed() -> void:
    var easel := _painting()
    var ctx := _preview(easel)
    var previewed := _look(easel)
    _apply(easel, ctx)
    var applied := _look(easel)
    assert_true(
        _same(applied, previewed), "After Apply the canvas shows what the preview showed, %s against %s" % [applied, previewed]
    )
    easel.free()


func test_an_effect_reading_the_group_reads_the_clip_as_previewed() -> void:
    var easel := _painting()
    _make(easel, "effect")
    var effect := easel.document.get_node("Effect") as SaLayer
    _preview(easel)
    var cached := Bench.texel(effect.get_field(Vector2i(0, 0)), EDGE)
    assert_almost_eq(cached.a, EDGE_ALPHA, TOLERANCE, "The effect reads the green clipped to the blurred edge, %s" % cached)
    _cancel(easel)
    cached = Bench.texel(effect.get_field(Vector2i(0, 0)), EDGE)
    assert_almost_eq(cached.a, 1.0, TOLERANCE, "and Cancel gives it the sharp edge back, %s" % cached)
    easel.free()


## A flatten or a merge renders the tree for what it writes into the document,
## and draws no canvas, so the preview is no part of what a clip reads there.
func test_a_render_that_writes_the_document_leaves_the_preview_out_of_a_clip() -> void:
    var easel := _painting()
    var doc := easel.document
    _preview(easel)
    var target := SaTexture.new(Vector2i(SaChunk.SIZE, SaChunk.SIZE), doc.color_space.texel_format())
    easel.compositor.clear_scratch_batch([[target, Rect2i(Vector2i.ZERO, target.size)]])
    SaTreeRender.new(doc).render(target, Vector2i(0, 0))
    var rendered := Bench.texel(target, EDGE)
    assert_almost_eq(rendered.a, 1.0, TOLERANCE, "The render reads the base as it is stored, %s" % rendered)
    assert_almost_eq(rendered.g, 1.0, TOLERANCE, "with the green whole over it, %s" % rendered)
    _cancel(easel)
    easel.free()


## A layer clipped to the base in each of the walk's places and kinds:
## generated, an adjustment, inside an isolated group with the base, where the
## group is the active scope, and read with the base by an effect layer that
## reads their group. Each shows at Apply what it showed in the preview, and
## after Cancel what it showed before.
func test_every_kind_of_clipped_layer_follows_the_preview() -> void:
    for kind: String in KINDS:
        var easel := _painting()
        _make(easel, kind)
        var before := _look(easel)
        var ctx := _preview(easel)
        var previewed := _look(easel)
        assert_false(_same(previewed, before), "%s: the preview changes the look, %s against %s" % [kind, previewed, before])
        _cancel(easel)
        var cancelled := _look(easel)
        assert_true(_same(cancelled, before), "%s: Cancel gives the look back, %s against %s" % [kind, cancelled, before])
        _preview(easel)
        _apply(easel, ctx)
        var applied := _look(easel)
        assert_true(_same(applied, previewed), "%s: Apply shows the preview, %s against %s" % [kind, applied, previewed])
        easel.free()


## *easel*'s painting turned into the case *kind*, with the base active.
func _make(easel: SaEasel, kind: String) -> void:
    var doc := easel.document
    var base := doc.get_node("Base") as SaLayer
    var clipped := doc.get_node("Clipped") as SaLayer
    var ops := SaLayerOps.new(doc)
    match kind:
        "generated":
            clipped.chunks.clear()
            clipped.generator = "background"
            clipped.generator_params = {SaGeneratedLayer.PARAM_COLOR: GREEN}
        "adjustment":
            ops.remove(clipped)
            doc.set_active_layer(base)
            var adjustment := ops.add(SaBackdropLayer.TYPE_ID, Fixtures.make_registries().layer_types)
            assert_not_null(SaFilterOps.new(doc).attach(adjustment, Bench.INVERT), "The invert attaches to the adjustment")
            SaLayerStack.set_clip_to_below(doc, adjustment, true)
        "grouped":
            ops.set_isolated(ops.group_layers([base, clipped]), true)
        "effect":
            var group := ops.group_layers([base, clipped])
            doc.set_active_layer(group)
            var effect := ops.add(SaEffectLayer.TYPE_ID, Fixtures.make_registries().layer_types)
            effect.name = "Effect"
            assert_true(effect.source == group, "The effect reads the group holding the base, made above it")
            assert_not_null(SaFilterOps.new(doc).attach(effect, Bench.INVERT), "The invert attaches to the effect")
    doc.set_active_layer(base)
    Bench.composite(easel)


## The canvas at the two texels the blur moves.
static func _look(easel: SaEasel) -> Array[Color]:
    return [Bench.texel(easel.output, EDGE), Bench.texel(easel.output, PAST)]


static func _same(a: Array[Color], b: Array[Color]) -> bool:
    for i in a.size():
        if not a[i].is_equal_approx(b[i]):
            return false
    return true
