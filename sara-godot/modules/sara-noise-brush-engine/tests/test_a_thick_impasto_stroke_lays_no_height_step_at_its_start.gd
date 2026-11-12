## A thick impasto stroke lays no height step at its start, because its first
## points take the first speed the smoother measures.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Thickness's option reads the Speed sensor, from one at rest to a half at the
## brush's fast speed. A stroke's first sample has no pair to measure a speed
## between, so its point laid the full thickness and every later one less, and
## the kernel drew the difference as a slope over the first segment, a flat
## dark rectangle one point step long in a palette knife picture. Each
## stroke here is Thick Impasto's Thickness of 9 under the option a fresh
## preset carries, painted at a steady pen rate with its samples 4, 12.3 and 30
## pixels apart, and the height the layer holds along the stroke's start is
## read against the height the body holds. The field's relief is nought and
## its shift too, so every texel the tip covers stands at the thickness the
## point answered, and a step is the speed's alone.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseStretchScript = preload("res://modules/sara-noise-brush-engine/dab_list/noise_stretch.gd")

## The tip's radii in pixels: the preset's own, whose step is short enough
## that the points of the smoother's first five pixels are taken before it reads
## a speed, and a wider one, which takes none.
const RADII: Array[float] = [7.68, 40.0]
## Thick Impasto's thickness, in virtual millimetres.
const THICKNESS := 9.0
## Where the strokes press, each radius on its own row of the canvas.
const FROM := Vector2(50.0, 50.0)
const ROWS := 120.0
## A pen's steady report rate, in milliseconds between samples, so a wider
## spacing is a faster hand.
const RATE_MS := 8.0
## How long each stroke runs, in pixels, so its body is well clear of its ends.
const LENGTH := 330.0

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null


## Keeps the thickness every point it sends answered, in the order sent, and
## where along the stroke each lies and how far along the field it reads: the
## points an update held are sent once the update leaves the stretch empty.
class Recorder:
    extends "res://modules/sara-noise-brush-engine/state_noise_brush.gd"

    var sent: Array[float] = []
    var sent_x: Array[float] = []
    var sent_along: Array[float] = []

    func _send(closing: bool, pressure: float) -> void:
        var points: PackedFloat32Array = dab_list.stretch.points.duplicate()
        super(closing, pressure)
        if not dab_list.stretch.points.is_empty():
            return
        for i in range(0, points.size(), NoiseStretchScript.FLOATS):
            sent.append(points[i + NoiseStretchScript.THICKNESS])
            sent_x.append(points[i + NoiseStretchScript.AT])
            sent_along.append(points[i + NoiseStretchScript.ALONG])


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(512, 256))
    _brush = Recorder.new()
    _brush.surface = _surface
    _brush.stroke_seed = 7
    _brush.settings.color = Color(0.9, 0.7, 0.3, 1.0)
    _brush.settings.opacity = 1.0
    _brush.settings.hardness = 1.0
    _brush.settings.strength = 0.0
    _brush.settings.strength_option.enabled = false
    _brush.settings.texture_field = "grain"
    _brush.settings.texture_channels = 2
    _brush.settings.texture_relief = 0.0
    _brush.settings.texture_drift = 1.0
    _brush.settings.thickness = THICKNESS


func after_each() -> void:
    _brush = null
    Fixtures.teardown(_surface)
    _surface = null


func test_the_brush_s_thickness_falls_with_speed_as_a_fresh_preset_s_does() -> void:
    var option: SaCurveOption = _brush.settings.thickness_option
    assert_true(option.enabled, "Thickness has its option on")
    assert_not_null(option.sensor_for(SaSensor.Id.SPEED), "and it reads the Speed sensor, which stays")


func test_the_first_point_lays_the_thickness_the_second_does_at_4_px() -> void:
    _first_against_second(4.0)


func test_the_first_point_lays_the_thickness_the_second_does_at_12_3_px() -> void:
    _first_against_second(12.3)


func test_the_first_point_lays_the_thickness_the_second_does_at_30_px() -> void:
    _first_against_second(30.0)


func test_the_first_segment_stands_as_high_as_the_body_at_4_px() -> void:
    _first_segment_against_body(4.0)


func test_the_first_segment_stands_as_high_as_the_body_at_12_3_px() -> void:
    _first_segment_against_body(12.3)


func test_the_first_segment_stands_as_high_as_the_body_at_30_px() -> void:
    _first_segment_against_body(30.0)


func test_the_field_drifts_over_the_first_step_as_over_the_body_at_4_px() -> void:
    _first_drift_against_body(4.0)


func test_the_field_drifts_over_the_first_step_as_over_the_body_at_12_3_px() -> void:
    _first_drift_against_body(12.3)


func test_the_field_drifts_over_the_first_step_as_over_the_body_at_30_px() -> void:
    _first_drift_against_body(30.0)


## How far along the field the press's first step moves, for each pixel of
## the stroke, against a step of the body's, within a hundredth, at every
## radius. The Drift row's share slides the field back by a share of every
## step, and its option reads the Speed sensor, so a press answered at rest
## slid the field by the share of a pen at rest over the first step.
func _first_drift_against_body(spacing: float) -> void:
    var option: SaCurveOption = _brush.settings.drift_option
    assert_true(
        option.enabled and option.sensor_for(SaSensor.Id.SPEED) != null, "Drift's option is on and reads the Speed sensor"
    )
    # Half a share, so the option's answer at either speed leaves the field
    # moving rather than held still under the pen.
    _brush.settings.texture_drift = 0.5
    var recorder := _brush as Recorder
    for row in RADII.size():
        _stroke(spacing, row)
        var label := "At %s px under a radius of %s" % [spacing, RADII[row]]
        var count := recorder.sent_x.size()
        assert_true(count > 4, "%s the stroke sent its points" % label)
        if count < 5:
            continue
        var middle := floori(count / 2.0)
        var first := _along_per_pixel(0)
        var body := _along_per_pixel(middle)
        assert_true(body > 0.0 and body < 1.0, "%s the field drifts in the body, %.4f along a pixel" % [label, body])
        assert_true(
            absf(first - body) <= 0.01 * body,
            "%s the first step reads %.4f along a pixel and the body %.4f" % [label, first, body]
        )


## How far along the field the step from the sent point *index* to the next
## moves for each pixel of the stroke it covers.
func _along_per_pixel(index: int) -> float:
    var recorder := _brush as Recorder
    var across := recorder.sent_x[index + 1] - recorder.sent_x[index]
    if across == 0.0:
        return 0.0
    return (recorder.sent_along[index + 1] - recorder.sent_along[index]) / across


## The thickness the press was sent with against the second point's, which
## the first segment is drawn between, at every radius.
func _first_against_second(spacing: float) -> void:
    for row in RADII.size():
        var sent := _stroke(spacing, row)
        var label := "At %s px under a radius of %s" % [spacing, RADII[row]]
        assert_true(sent.size() > 3, "%s the stroke sent its points" % label)
        if sent.size() < 2:
            continue
        assert_true(
            absf(sent[0] - sent[1]) <= 0.01 * sent[1],
            "%s the press lays %.3f and the next point %.3f" % [label, sent[0], sent[1]]
        )
        assert_true(sent[1] < THICKNESS, "%s the speed thins both below the full %s" % [label, THICKNESS])


## The height on the stroke's centre line from half a radius behind the press
## to the first sample, every texel of it, against the body's, each within a
## hundredth of the body's, at every radius. The first point step is inside
## that run at every spacing, since the chord to the first sample is cut into
## steps no longer.
func _first_segment_against_body(spacing: float) -> void:
    var layer := _surface.easel.document.active_layer
    for row in RADII.size():
        _stroke(spacing, row)
        var start := FROM + Vector2(0.0, ROWS * row)
        var label := "At %s px under a radius of %s" % [spacing, RADII[row]]
        var body := _height_at(layer, Vector2i(start + Vector2(LENGTH * 0.5, 0.0)))
        assert_true(body > 0.0, "%s the body stands above the canvas" % label)
        var worst := Vector2i(start)
        var worst_height := body
        for x in range(roundi(start.x - RADII[row] * 0.5), roundi(start.x + spacing) + 1):
            var at := Vector2i(x, roundi(start.y))
            var height := _height_at(layer, at)
            if absf(height - body) > absf(worst_height - body):
                worst = at
                worst_height = height
        assert_true(
            absf(worst_height - body) <= 0.01 * body,
            "%s the start stands at %.3f at %s and the body at %.3f" % [label, worst_height, worst, body]
        )


## A straight stroke [constant LENGTH] pixels long on the canvas's *row*,
## under that row's radius, its samples *spacing* apart at [constant RATE_MS],
## at a full press. Answers the thickness of every point it sent.
func _stroke(spacing: float, row: int) -> Array[float]:
    var recorder := _brush as Recorder
    recorder.sent.clear()
    recorder.sent_x.clear()
    recorder.sent_along.clear()
    _brush.settings.radius = RADII[row] / 256.0
    var start := FROM + Vector2(0.0, ROWS * row)
    var clock := 1000.0
    _brush.begin_stroke(start, 1.0, Vector2.ZERO, clock)
    var walked := spacing
    while walked <= LENGTH:
        clock += RATE_MS
        _brush.add_sample(start + Vector2(walked, 0.0), 1.0, Vector2.ZERO, clock)
        walked += spacing
    _brush.end_stroke()
    return recorder.sent.duplicate()


## The height *layer* holds at the document texel *at*, nought where it holds
## none.
func _height_at(layer: SaLayer, at: Vector2i) -> float:
    var side := 1
    for grid: Vector2i in layer.chunks:
        side = (layer.chunks[grid] as SaChunk).pixel_size()
        break
    var grid := Vector2i(floori(float(at.x) / side), floori(float(at.y) / side))
    var texture := layer.get_field(grid, SaFieldSpec.HEIGHT)
    if texture == null:
        return 0.0
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var local := at - grid * side
    return bytes.decode_half((local.y * texture.size.x + local.x) * 2)
