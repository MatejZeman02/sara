## The noise brush picks paint up and drags it along, through the stamp's own
## smudge stage.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `test_smudge_stage.gd` holds the pickup kernel to its numbers, and this suite
## holds the noise brush to the stage: its settings carry the stamp's options,
## its pages show them, and a stroke that starts in red paint and runs out onto
## bare canvas lays red past the edge where the same stroke without the stage
## lays the brush's blue. That stroke reads its own layer, with Sample Merged
## off, because the composite past the red is the canvas's grey backdrop, which
## a merged pickup takes in as paint. Sample Merged keeps its meaning, so a
## stroke on an empty layer above the red lays the red only while it reads the
## composite.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")

const RED := Color(1.0, 0.0, 0.0, 1.0)
const BLUE := Color(0.0, 0.0, 1.0, 1.0)
## The row the strokes run along, in document pixels.
const ROW := 40.0
## How far past the red's edge the stroke runs out onto bare canvas.
const RUN := 40.0
## Where the texel the suite reads stands past the edge.
const PAST := 20.0

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null
## The red's right edge, one chunk wide, in document pixels.
var _edge: float = 0.0


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(512, 256))
    var layer := _surface.easel.document.active_layer
    var chunk := layer.get_or_create_chunk(Vector2i(0, 0))
    chunk.clear(RED)
    _edge = float(chunk.pixel_size())
    _surface.easel.document.invalidate_chunks([Vector2i(0, 0)])
    _composite()
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = 7
    _brush.settings.color = BLUE
    _brush.settings.opacity = 1.0
    _brush.settings.hardness = 1.0
    # No shift, so a full press paints every texel the tip reaches.
    _brush.settings.strength = 0.0
    _brush.settings.radius = 6.0 / 256.0


func after_each() -> void:
    _brush = null
    Fixtures.teardown(_surface)
    _surface = null


func _composite() -> void:
    _surface.easel.request_full_composite()
    _surface.easel.process_pending_composite()


## The stage on at full pickup, the carry laid in full and never fading, so
## what the stroke picked up in the red is what it lays past the edge. The
## colour rate is unticked, a pure smudge, since a fresh brush has it ticked.
func _smudge_on() -> void:
    _brush.settings.smudge_pickup_option.enabled = true
    _brush.settings.smudge_pickup_option.strength = 1.0
    _brush.settings.smudge_color_rate_option.enabled = false


## A stroke from inside the red out onto bare canvas, in samples of four
## pixels, which the brush walks into dabs.
func _stroke() -> void:
    _stroke_between(Vector2(_edge - RUN, ROW), Vector2(_edge + RUN, ROW))


## A stroke from *from* to *to* in twenty samples.
func _stroke_between(from: Vector2, to: Vector2) -> void:
    _brush.begin_stroke(from, 1.0)
    for step in range(1, 21):
        _brush.add_sample(from.lerp(to, step / 20.0), 1.0)
    _brush.end_stroke()


func _texel(layer: SaLayer, at: Vector2) -> Color:
    var pixel := Vector2i(at.floor())
    for grid: Vector2i in layer.chunks:
        var chunk := layer.chunks[grid] as SaChunk
        var side := chunk.pixel_size()
        if Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side)) != grid:
            continue
        @warning_ignore("static_called_on_instance")
        var image := SaExport.get_texture_image_float(layer.get_field(grid))
        return image.get_pixelv(pixel - grid * side)
    return Color.TRANSPARENT


## The texel past the edge on *layer*, where only the stroke has painted.
func _past(layer: SaLayer) -> Color:
    return _texel(layer, Vector2(_edge + PAST, ROW))


func test_a_fresh_noise_brush_has_the_stage_off_at_the_stamps_numbers() -> void:
    var settings: Resource = NoiseBrushSettingsScript.new()
    assert_false(settings.smudge_pickup_option.enabled, "A new noise brush does not smudge")
    assert_almost_eq(settings.smudge_pickup_option.strength, 0.3, 1e-6, "and its pickup waits where the stamp's does")
    assert_true(settings.smudge_color_rate_option.enabled, "its colour rate ticked, as the stamp's is")
    assert_almost_eq(settings.smudge_color_rate_option.strength, 0.5, 1e-6, "at half the brush's colour")
    assert_almost_eq(settings.smudge_length_option.strength, 0.9, 1e-6, "and its smear at a long one")
    assert_almost_eq(settings.smudge_radius, 1.0, 1e-6, "reading no wider than the dab")
    assert_eq(settings.smudge_mode, SaSmudgePage.SMEARING, "dragging rather than averaging")
    assert_true(settings.smudge_sample_merged, "and reading every visible layer, as the stamp does")


func test_the_noise_brush_shows_the_smudge_pages_without_move_height() -> void:
    var keys: Array[StringName] = []
    var pages := {}
    for spec: SaOptionSpec in NoiseModuleScript.options():
        keys.append(spec.key)
        pages[spec.key] = spec.page
    for key: StringName in [&"smudge_pickup_option", &"smudge_color_rate_option", &"smudge_length_option"]:
        assert_true(key in keys, "The noise brush has the %s page" % key)
    for key: StringName in [&"smudge_mode", &"smudge_radius"]:
        assert_eq(pages.get(key, ""), SaSmudgePage.PAGE, "and %s sits on the Colour Rate page" % key)
    assert_eq(pages.get(&"smudge_sample_merged", ""), SaSmudgePage.PICKUP_PAGE, "and Sample Merged on the Smudge Pickup page")
    assert_false(&"smudge_move_height" in keys, "but no Move Height row, since the noise dab lays its own height")


func test_without_the_stage_the_stroke_lays_its_own_colour_past_the_edge() -> void:
    _stroke()
    var past := _past(_surface.easel.document.active_layer)
    assert_almost_eq(past.a, 1.0, 0.01, "The stroke painted the bare canvas past the red")
    assert_almost_eq(past.b, 1.0, 0.01, "in the brush's blue")
    assert_almost_eq(past.r, 0.0, 0.01, "with no red in it")


func test_a_smudge_stroke_drags_the_red_out_onto_the_bare_canvas() -> void:
    _smudge_on()
    _brush.settings.smudge_sample_merged = false
    _brush.begin_stroke(Vector2(_edge - RUN, ROW), 1.0)
    # The press waits for the path, the curve answers a sample late, and a
    # round tip holds back a half width, so the fourth sample
    # is the first that paints.
    _samples()
    assert_not_null(_brush.smudge, "The first stretch painted made the stroke's carry")
    assert_true(_brush.smudge.pickups > 0, "and the pickup ran, %d times" % _brush.smudge.pickups)
    _brush.end_stroke()
    _stroke()
    var past := _past(_surface.easel.document.active_layer)
    assert_almost_eq(past.a, 1.0, 0.01, "The smudge painted the bare canvas past the red at the stroke's opacity")
    assert_true(past.r > 0.9, "in the red it picked up, red %.3f" % past.r)
    assert_true(past.b < 0.1, "rather than the brush's blue, blue %.3f" % past.b)


## The samples after the press up to the first that paints, four pixels apart.
func _samples() -> void:
    for step in range(1, 5):
        _brush.add_sample(Vector2(_edge - RUN + 4.0 * step, ROW), 1.0)


## A stroke well inside the red, on an empty layer above it, and the texel
## under its middle on that layer.
func _stroke_above_the_red() -> Color:
    var upper := SaLayerOps.new(_surface.easel.document).add()
    _composite()
    _stroke_between(Vector2(_edge - 4.0 * RUN, ROW), Vector2(_edge - 2.0 * RUN, ROW))
    return _texel(upper, Vector2(_edge - 3.0 * RUN, ROW))


func test_sample_merged_lays_the_paint_below_an_empty_layer() -> void:
    _smudge_on()
    var merged := _stroke_above_the_red()
    assert_almost_eq(merged.a, 1.0, 0.01, "Reading the composite, the stroke on the empty layer paints")
    assert_true(merged.r > 0.9, "the red below it, red %.3f" % merged.r)
    assert_true(merged.b < 0.1, "and not its own blue, blue %.3f" % merged.b)


func test_without_sample_merged_the_stroke_reads_its_own_layer_alone() -> void:
    _smudge_on()
    _brush.settings.smudge_sample_merged = false
    var alone := _stroke_above_the_red()
    assert_almost_eq(alone.a, 1.0, 0.01, "Reading the layer alone, the stroke still paints")
    assert_true(alone.r < 0.1, "but carries none of the red the layer does not hold, red %.3f" % alone.r)
    assert_true(alone.b > 0.9, "and lays its own blue")


func test_the_mode_reaches_the_carry() -> void:
    _smudge_on()
    _brush.settings.smudge_mode = SaSmudgePage.DULLING
    _brush.begin_stroke(Vector2(_edge - RUN, ROW), 1.0)
    _samples()
    assert_eq(_brush.smudge.mode, SaSmudgePage.DULLING, "A dulling brush's carry dulls")
    _brush.end_stroke()
    assert_null(_brush.smudge, "and the carry goes with the stroke")
