## An effect layer whose input is deleted goes empty, with no
## script error, and the delete's undo brings the effect back.
##
## Bug 2 of the hunt of 2026-10-08: with its input deleted, `_refresh_one`
## assigned an untyped `{}` to a typed dictionary, the assignment raised a
## script error on every redraw and ended the refresh before it dropped a chunk,
## so the canvas kept the effect of the deleted layer. The run's own check on
## `SCRIPT ERROR` in the log fails this suite if the error comes back, and the
## chunks and the canvas read below say what the refresh did.
##
## The painting: three chunks across and two down, the grey background hidden,
## a layer named Source holding opaque paint in three chunks, and an effect
## layer above it reading Source through the fixture invert, the painting of
## `test_an_effect_layer_runs_its_filters_over_a_named_input.gd`. Every
## composite after the first is the pending one, so what the delete invalidated
## is all the refresh is handed, as in the running app.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(768, 512)
## In the order `_keys` sorts them.
const HELD: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0)]
const PAINT := Color(0.25, 0.5, 0.75, 1.0)
const INVERTED := Color(0.75, 0.5, 0.25, 1.0)
const STROKE := Color(0.875, 0.125, 0.375, 1.0)
const TOLERANCE := 1.0e-4
## A texel of the input's paint, and one of the stroke painted after the delete
## where the input held nothing.
const ON_PAINT := Vector2i(300, 100)
const ON_STROKE := Vector2i(640, 400)
const NONE: Array[Vector2i] = []

var _types: SaLayerTypeRegistry


func before_each() -> void:
    _types = Fixtures.make_registries().layer_types
    SaProblems.pending_refusals = PackedStringArray()


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


func test_the_effect_of_a_deleted_input_drops_every_chunk_and_shows_nothing() -> void:
    var easel := _painting()
    var doc := easel.document
    var source := doc.get_node("Source") as SaLayer
    var effect := doc.get_node("Effect") as SaLayer
    assert_eq(_keys(effect), HELD, "Before the delete the effect holds a chunk where its input does")
    assert_true(_near(Bench.texel(easel.output, ON_PAINT), INVERTED), "and the canvas shows the input inverted")
    assert_true(SaLayerOps.new(doc).remove(source), "The input is deleted")
    easel.process_pending_composite()
    assert_null(SaEffectLayer.input_of(effect), "The effect reads nothing once its input has left the document")
    assert_eq(_keys(effect), NONE, "and holds no chunk")
    var shown := Bench.texel(easel.output, ON_PAINT)
    assert_true(shown.a <= TOLERANCE, "Where the deleted input was, the canvas holds nothing, %s" % shown)
    easel.free()


func test_a_layer_painted_after_the_delete_shows_alone() -> void:
    var easel := _painting()
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    var effect := doc.get_node("Effect") as SaLayer
    assert_true(ops.remove(doc.get_node("Source") as SaLayer), "The input is deleted")
    easel.process_pending_composite()
    var paint := ops.add()
    paint.name = "Paint"
    doc.set_active_layer(paint)
    _stroke(doc, Vector2(ON_STROKE), 12.0, STROKE)
    easel.process_pending_composite()
    assert_eq(_keys(effect), NONE, "A stroke on another layer gives the effect with no input no chunk")
    var struck := Bench.texel(easel.output, ON_STROKE)
    assert_true(_near(struck, STROKE), "The stroke shows as painted, not inverted, %s" % struck)
    var gone := Bench.texel(easel.output, ON_PAINT)
    assert_true(gone.a <= TOLERANCE, "and nothing of the deleted input comes back with it, %s" % gone)
    easel.free()


func test_the_deletes_undo_brings_the_input_and_its_effect_back() -> void:
    var easel := _painting()
    var doc := easel.document
    var source := doc.get_node("Source") as SaLayer
    var effect := doc.get_node("Effect") as SaLayer
    assert_true(SaLayerOps.new(doc).remove(source), "The input is deleted")
    easel.process_pending_composite()
    assert_true(doc.undo(), "The delete is one step")
    easel.process_pending_composite()
    assert_true(SaEffectLayer.input_of(effect) == source, "whose undo puts the input back where the effect reads it")
    assert_eq(_keys(effect), HELD, "The effect holds a chunk where its input does again")
    var shown := Bench.texel(easel.output, ON_PAINT)
    assert_true(_near(shown, INVERTED), "and the canvas shows the input inverted again, %s" % shown)
    easel.free()


func test_an_effect_pointed_at_nothing_goes_empty_and_its_undo_reads_again() -> void:
    var easel := _painting()
    var doc := easel.document
    var source := doc.get_node("Source") as SaLayer
    var effect := doc.get_node("Effect") as SaLayer
    assert_true(SaEffectLayer.read(doc, effect, null), "The effect is pointed at nothing, as the Input list's None does")
    easel.process_pending_composite()
    assert_eq(_keys(effect), NONE, "An effect with no input holds no chunk")
    var shown := Bench.texel(easel.output, ON_PAINT)
    assert_true(_near(shown, PAINT), "and the canvas shows the layer below it as painted, not inverted, %s" % shown)
    assert_true(doc.undo(), "The pick is one step")
    easel.process_pending_composite()
    assert_true(effect.source == source, "whose undo reads the input again")
    assert_eq(_keys(effect), HELD, "with its chunks back")
    easel.free()
