## A move of the gradient is a handful of compute lists, not
## three for every chunk of the canvas, and the ramp's texels are built again
## only when a stop changes.
##
## The canvas is twelve chunks, so the live stroke over it is two runs of
## `SaCompositor.SCRATCH_RUN` and the second run's slots are the first's again.
## What the staged composite shows is checked against the ramp the release lays
## into the layer, over a painted layer and with a translucent ramp, so a stage
## that dropped the layer or the stroke would read as a different colour.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const SIZE := Vector2i(1024, 768)
const CHUNKS: int = 12
const FROM := Vector2(0.5, 0.0)
const TO := Vector2(1024.5, 0.0)
## A texel in the second run of chunks, the last chunk of the canvas.
const PROBE := Vector2i(900, 700)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _pass: SaGradient = null


func before_each() -> void:
    _easel = SaEasel.create_default(SIZE)
    _doc = _easel.document
    _doc.fill_layer(Color(0.8, 0.2, 0.1, 1.0))
    _easel.process_pending_composite()
    _pass = SaGradient.new(_doc)


func after_each() -> void:
    _pass = null
    _easel.free()
    _easel = null
    _doc = null


func _translucent_ramp() -> SaColorRamp:
    return SaColorRamp.from_pair(Color(0.0, 0.0, 0.0, 0.5), Color(1.0, 1.0, 1.0, 0.5))


func _preview(ramp: SaColorRamp) -> void:
    _pass.preview(FROM, TO, ramp, SaGradient.Shape.LINEAR, SaGradient.Repeat.NONE)


func _shown_at(at: Vector2i) -> Color:
    var output := _easel.output
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(output.rid, 0)
    return SaFieldSpec.decode_texel(bytes, output.format, at.y * output.size.x + at.x)


func _composite_lists() -> int:
    return int((SaCompute.kernel_counters().get("composite/composite", {}) as Dictionary).get("lists", 0))


func test_a_move_walks_every_chunk_in_one_list() -> void:
    _doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    var ramp := _translucent_ramp()
    _preview(ramp)
    var lists_before := SaCompute.lists
    var dispatches_before := SaCompute.dispatches
    _preview(ramp)
    assert_eq(SaCompute.dispatches - dispatches_before, CHUNKS, "A move dispatches the ramp once over every chunk")
    assert_eq(SaCompute.lists - lists_before, 1, "and all of them in one list, where it was a list a chunk")


func test_the_live_stroke_composites_a_list_a_stage() -> void:
    _doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    _preview(_translucent_ramp())
    var composite_before := _composite_lists()
    _easel.process_pending_composite()
    var runs := ceili(float(CHUNKS) / float(SaCompositor.SCRATCH_RUN))
    # The layer into the scratches and the stroke over them, a list each a run,
    # the scratches onto the canvas a third, and one for the tier below.
    assert_eq(_composite_lists() - composite_before, 3 * runs + 1, "Three composite lists a run and one for the tier below")


func test_the_staged_composite_shows_what_the_release_lays() -> void:
    var ramp := _translucent_ramp()
    _doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    _preview(ramp)
    _easel.process_pending_composite()
    var previewed := _shown_at(PROBE)

    _pass.clear_preview()
    var laid := _pass.apply(_doc.active_layer, FROM, TO, ramp, SaGradient.Shape.LINEAR, SaGradient.Repeat.NONE, false)
    assert_true(laid, "The release lays the ramp")
    _easel.process_pending_composite()
    var committed := _shown_at(PROBE)

    assert_true(absf(previewed.g - 0.2) > 0.1, "The preview shows the ramp over the layer, not the layer alone")
    for channel in 4:
        assert_almost_eq(previewed[channel], committed[channel], 2e-3, "and what the release lays, channel %d" % channel)


func test_the_ramp_is_built_again_only_when_a_stop_changes() -> void:
    var ramp := _translucent_ramp()
    _doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    _preview(ramp)
    var built: Array = _pass._ramp_key.duplicate(true)
    _preview(ramp)
    assert_eq(_pass._ramp_key, built, "A move that changes no stop keeps the ramp it built")

    # Edited in place, the way the ramp control edits it, with nothing telling
    # the pass: the release still lays the edited colour.
    ramp.set_stop_color(1, Color(1.0, 0.0, 0.0, 0.5))
    _pass.clear_preview()
    _pass.apply(_doc.active_layer, FROM, TO, ramp, SaGradient.Shape.LINEAR, SaGradient.Repeat.NONE, true)
    assert_false(_pass._ramp_key == built, "An edited stop builds the ramp again")
    @warning_ignore("integer_division")
    var grid := Vector2i(PROBE.x / SaChunk.SIZE, PROBE.y / SaChunk.SIZE)
    var texture := _doc.active_layer.get_field(grid)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var local := PROBE - grid * SaChunk.SIZE
    var texel := SaFieldSpec.decode_texel(bytes, texture.format, local.y * texture.size.x + local.x)
    assert_true(texel.r > texel.g + 0.2, "and lays it: the far end reads red, not the white it was")
