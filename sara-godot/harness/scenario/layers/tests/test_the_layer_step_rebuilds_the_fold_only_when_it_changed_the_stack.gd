## The `layer` step rebuilds the fold only when it changed the stack.
##
## The step ended with `document.update_caches()` whatever its keys did, so a
## step that only selected a layer folded the stack twice, once inside
## `SaDocument.set_active_layer` and once at its end, and over ten blur layers
## the second fold cost a second (`BLUR-STACK-COST.md`). A step that selects,
## notes or reads now adds no rebuild to what the selection makes on its own,
## and a step that fills a chunk by hand still rebuilds, because nothing else
## tells the cache that baked the layer.
##
## A rebuild is counted where `SaDocument.update_caches` makes it, in
## `SaLayerFold.rebuild`, by a fold that counts its calls standing in the
## document's own.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The step is real history steps over a real stack, and the fill is read back
## from the composite, so this needs a RenderingDevice.
const REQUIRES_GPU := true

const RED := Color(1.0, 0.0, 0.0, 1.0)
## A texel of chunk (0, 0), the one the fill names.
const AT := Vector2i(10, 10)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _fold: CountingFold = null
var _announced: bool = true


## A fold that counts the rebuilds `SaDocument.update_caches` asks of it.
class CountingFold:
    extends SaLayerFold

    var rebuilds: int = 0

    func rebuild(document: SaDocument, compositor: SaCompositor, visible_rect: Rect2) -> void:
        rebuilds += 1
        super(document, compositor, visible_rect)


## Layer 1 at the bottom, Below over it and Above on top, Above the one
## selected, so Layer 1 and Below are folded into the bottom cache.
func before_each() -> void:
    _announced = SaProblems.announce
    SaProblems.announce = false
    _easel = SaEasel.create_default(Vector2i(512, 256))
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _doc = _easel.document
    SaLayerStep.run(_doc, {"add": "Below"})
    SaLayerStep.run(_doc, {"add": "Above"})
    _doc.fold.release()
    _fold = CountingFold.new()
    _doc.fold = _fold
    _doc.update_caches()


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _fold = null
    SaProblems.announce = _announced


## The rebuilds *spec* run as a layer step makes, and the step's answer.
func _rebuilds_of(spec: Dictionary) -> Array:
    var before := _fold.rebuilds
    var line := SaLayerStep.run(_doc, spec)
    var said: Variant = JSON.parse_string(line.trim_prefix("SaCapture: layer "))
    assert_true(said is Dictionary and not (said as Dictionary).has("error"), "the step answers: %s" % line)
    return [_fold.rebuilds - before, said if said is Dictionary else {}]


## The composite at *at* as it stands, with no rebuild of the caches first, so
## what it shows is what the step left them holding.
func _shown(at: Vector2i) -> Color:
    _easel.request_full_composite()
    _easel.process_pending_composite()
    var texture := _easel.output
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


## A press on a layer's row is `set_active_layer`, which folds nothing and
## leaves the fold owed until a stroke or an idle frame. The
## step that selects the same layer folds no more than the press, where it
## folded twice before the fix.
func test_a_step_that_selects_a_layer_folds_no_more_than_a_press_on_its_row() -> void:
    var below := _doc.get_node("Below") as SaLayer
    var above := _doc.get_node("Above") as SaLayer
    var before := _fold.rebuilds
    _doc.set_active_layer(below)
    var by_press := _fold.rebuilds - before
    assert_eq(by_press, 0, "a press on Below's row folds nothing")
    assert_true(_doc.fold.debt.is_owed(), "and owes the fold")
    _doc.set_active_layer(above)

    var selected := _rebuilds_of({"activate": "Below"})
    assert_eq(_doc.active_layer, below, "the step selected Below")
    assert_eq(selected[0], by_press, "and folded no more than the press: %s" % [selected[1]])

    _doc.set_active_layer(above)
    var found := _rebuilds_of({"add": "Below"})
    assert_eq(_doc.active_layer, below, "an add of a name already there selects that layer")
    assert_eq(found[0], by_press, "and folds no more than the press: %s" % [found[1]])


## A step that reads a layer, notes it or locks it changes nothing the fold
## folds, so it reads no rebuild at all.
func test_a_step_that_reads_notes_or_locks_reads_no_rebuild() -> void:
    var above := _doc.get_node("Above") as SaLayer
    var read := _rebuilds_of({"of": "Below"})
    assert_eq(read[0], 0, "naming Below and doing nothing folds nothing: %s" % [read[1]])
    assert_eq(String(read[1].get("layer", "")), "Below", "and the answer names Below")
    assert_eq(_doc.active_layer, above, "and Above stays selected")

    var noted := _rebuilds_of({"of": "Below", "comment": "the sky, too blue"})
    assert_eq(noted[0], 0, "a note folds nothing: %s" % [noted[1]])
    assert_eq((_doc.get_node("Below") as SaLayer).comment, "the sky, too blue", "and Below carries it")

    var locked := _rebuilds_of({"lock": true})
    assert_eq(locked[0], 0, "a paint lock folds nothing: %s" % [locked[1]])
    assert_true(above.is_locked, "and Above is locked")


## An opacity is what a painter drags on a large file, and the
## step took 1.4 s on 540 layers. `SaLayerOps` marks what the layer draws at
## the layer and `SaFoldDebt` folds it over the frames after, so the step adds
## no rebuild of its own, and the picture still follows once that debt is paid
## the way a frame that draws pays it.
func test_an_opacity_step_adds_no_rebuild_of_its_own_and_the_composite_follows() -> void:
    var ground := _shown(AT)
    var painted := _rebuilds_of({"of": "Above", "fill": [1.0, 0.0, 0.0, 1.0], "chunks": [[0, 0]]})
    assert_eq(painted[0], 1, "the fill rebuilt the fold once: %s" % [painted[1]])
    assert_almost_eq(_shown(AT).r, RED.r, 0.02, "and Above is red over the ground")

    var dimmed := _rebuilds_of({"of": "Above", "opacity": 0.0})
    assert_eq(dimmed[0], 0, "the opacity step folds nothing of its own: %s" % [dimmed[1]])
    assert_almost_eq((_doc.get_node("Above") as SaLayer).opacity, 0.0, 0.001, "and Above is fully transparent")

    SaFoldDebt.before_reading(_doc)
    var shown := _shown(AT)
    assert_true(shown.is_equal_approx(ground), "once the frame pays what the step owed, the ground is back: %s" % shown)


## Fifty opacity steps on one layer are one history step holding no pixels, so
## a slider dragged through the door neither fills the undo list nor copies a
## layer for each position.
func test_fifty_opacity_steps_are_one_history_step_holding_no_bytes() -> void:
    var steps := _doc.history.step_count()
    var bytes := _doc.history.total_bytes()
    var layer_bytes := _doc.history.total_layer_bytes()
    for i in 50:
        SaLayerStep.run(_doc, {"of": "Above", "opacity": 0.4 if i % 2 == 0 else 0.6})
    assert_almost_eq((_doc.get_node("Above") as SaLayer).opacity, 0.6, 0.001, "the last position is the one Above holds")
    assert_eq(_doc.history.step_count() - steps, 1, "and the fifty are one step on the undo list")
    assert_eq(_doc.history.total_bytes() - bytes, 0, "holding no paint")
    assert_eq(_doc.history.total_layer_bytes() - layer_bytes, 0, "and no layer of its own")


## A chunk filled by hand on a layer the bottom cache baked is no stroke, and
## only the step's rebuild folds it in, so the composite shows the new pixel.
func test_a_step_that_fills_a_chunk_rebuilds_and_the_composite_shows_it() -> void:
    var before_fill := _shown(AT)
    assert_false(before_fill.is_equal_approx(RED), "the composite is not red before the fill: %s" % before_fill)

    var filled := _rebuilds_of({"of": "Layer 1", "fill": [1.0, 0.0, 0.0, 1.0], "chunks": [[0, 0]]})
    assert_eq(filled[0], 1, "the fill rebuilt the fold once: %s" % [filled[1]])
    assert_eq(_doc.active_layer, _doc.get_node("Above"), "with Above still selected")

    var shown := _shown(AT)
    assert_almost_eq(shown.r, RED.r, 0.02, "the composite shows the fill, red: %s" % shown)
    assert_almost_eq(shown.g, RED.g, 0.02, "green: %s" % shown)
    assert_almost_eq(shown.b, RED.b, 0.02, "blue: %s" % shown)
    assert_almost_eq(shown.a, RED.a, 0.02, "alpha: %s" % shown)
