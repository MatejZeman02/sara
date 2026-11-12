## The noise brush's field drifts along the stroke, by a Drift
## row shared by every field, nought being none.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The Done when of the row, a clause a test: a long stroke painted with drift
## at nought and at full, how far its field slid read at the end. The field is
## read in stroke coordinates, so drift
## slides it along the stroke and takes the slide off the travelled length a
## point carries. The slide is read off the state, and the field under the tip
## is read on the GPU by the probe kernel, which calls the same `noise_field`
## the dab does, so the drift a dab reads is the drift the suite proves. The
## painted stroke is read off the layer for the Bristle field, whose streaks
## stop breaking at full.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")
const NoiseFieldsScript = preload("res://modules/sara-noise-brush-engine/noise_fields.gd")

const CANVAS := Vector2i(512, 256)
const RADIUS := 14.0
## The long stroke, left to right across two chunks, a sample every
## [constant SAMPLE_STEP] pixels as a pen's would come.
const START := Vector2(40.0, 128.0)
const END := Vector2(470.0, 128.0)
const SAMPLE_STEP := 10.0
## The shortest bare run along a row that counts as a streak breaking.
const BREAK := 4
## Half the probe's window, which is the tip's box.
const WINDOW_HALF := 12

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null


func before_each() -> void:
    _surface = Fixtures.make_surface(CANVAS)
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = 11
    _brush.settings.color = Color(0.8, 0.3, 0.1, 1.0)
    _brush.settings.opacity = 1.0
    _brush.settings.hardness = 1.0
    _brush.settings.strength = 0.5
    _brush.settings.strength_option.enabled = false
    _brush.settings.radius = RADIUS / float(mini(CANVAS.x, CANVAS.y))


func after_each() -> void:
    _brush = null
    Fixtures.teardown(_surface)
    _surface = null


## Drift is one row on the Texture page, shared by every field rather than
## hung off one, and a fresh brush starts with none.
func test_the_drift_row_is_on_the_texture_page_for_every_field() -> void:
    var fields: RefCounted = NoiseFieldsScript.new()
    fields.register_shipped()
    var drift: SaOptionSpec = null
    for spec: SaOptionSpec in NoiseModuleScript.options(fields):
        if spec.key == NoiseFieldsScript.DRIFT_KEY:
            drift = spec
    assert_not_null(drift, "The page declares a Drift row")
    assert_eq(drift.page, NoiseFieldsScript.PAGE, "on the Texture page")
    assert_true(drift.shown_when.is_empty(), "shown whichever field is chosen")
    assert_eq(String(drift.enabled_when), "", "and enabled whichever field is chosen")
    assert_eq(_brush.settings.texture_drift, 0.0, "A fresh brush has no drift")


## A long stroke's slide at its end: none at nought, the whole way at full and
## half of it at a half.
func test_a_long_stroke_slides_its_field_by_the_drift_row() -> void:
    var run := (END - START).length()
    for drift: float in [0.0, 0.5, 1.0]:
        _brush.settings.texture_drift = drift
        _stroke()
        # The stroke's last point is the pen's last sample, since every chord
        # of the curve ends in a point, so the slide is the whole run.
        var slack: float = 0.01
        var slide := _brush.field_slide
        assert_true(
            absf(slide - run * drift) <= slack,
            "At drift %.1f the field slides %.3f over a stroke of %.1f, within %.2f" % [drift, slide, run, slack]
        )


## At full drift the field under the tip at the stroke's end is the field that
## was under it at the start, read by the kernel at the travelled length the
## last point carries, and at nought it is another.
func test_the_field_under_the_tip_rides_with_it_at_full() -> void:
    _brush.settings.texture_field = NoiseFieldsScript.GRAIN
    for drift: float in [0.0, 1.0]:
        _brush.settings.texture_drift = drift
        _stroke()
        var along := _brush.stroke_info.total_length - _brush.field_slide
        var at_start := _probe(Vector2i(START), 0.0)
        var at_end := _probe(Vector2i(END), along)
        var gap := 0.0
        for index in at_start.size():
            gap = maxf(gap, absf(at_start[index] - at_end[index]))
        if drift > 0.0:
            assert_true(gap < 0.001, "At full drift the tip reads the same grain at both ends, %.5f apart" % gap)
        else:
            assert_true(gap > 0.2, "At nought the tip has moved on to other grain, %.3f apart" % gap)


## The painted stroke: Bristle streaks break and start again along a still
## field, and at full drift each streak runs the stroke's length unbroken.
func test_full_drift_draws_the_bristles_out_along_the_stroke() -> void:
    _brush.settings.texture_field = NoiseFieldsScript.BRISTLE
    _brush.settings.bristle_length = 0.5
    _brush.settings.strength = 0.3
    var breaks := {}
    for drift: float in [0.0, 1.0]:
        Fixtures.teardown(_surface)
        _surface = Fixtures.make_surface(CANVAS)
        _brush.surface = _surface
        _brush.settings.texture_drift = drift
        _stroke()
        breaks[drift] = _breaks_along()
    assert_true(breaks[0.0] > 20, "A still field breaks its streaks along the stroke, %d breaks" % breaks[0.0])
    assert_true(breaks[1.0] * 8 < breaks[0.0], "and full drift draws them out, %d breaks against %d" % [breaks[1.0], breaks[0.0]])


## Paints the long stroke.
func _stroke() -> void:
    _brush.begin_stroke(START, 1.0)
    var at := START
    while at.x < END.x:
        at.x = minf(at.x + SAMPLE_STEP, END.x)
        _brush.add_sample(at, 1.0)
    _brush.end_stroke()


## The field's pressure map over the tip's box about *centre*, where the
## stroke's travelled length less the slide is *along*, as the stroke reads it
## there.
func _probe(centre: Vector2i, along: float) -> PackedFloat32Array:
    var window := Rect2i(centre - Vector2i(WINDOW_HALF, WINDOW_HALF), 2 * Vector2i(WINDOW_HALF, WINDOW_HALF))
    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(_brush.probe_field(window, Vector2(centre), Vector2(1.0, 0.0), along, RADIUS))
    var out := PackedFloat32Array()
    for y in image.get_height():
        for x in image.get_width():
            out.append(image.get_pixel(x, y).r)
    return out


## How many times a row of texels inside the stroke breaks over the stroke's
## middle: a bare run of at least [constant BREAK] texels with paint either
## side, summed over the rows. A shorter gap is the edge of a streak read at
## the walk's step, which the wash leaves as a comb of specks, not a break.
func _breaks_along() -> int:
    var layer := _surface.easel.document.active_layer
    var images := {}
    var count := 0
    var reach := int(RADIUS * 0.6)
    for y in range(int(START.y) - reach, int(START.y) + reach + 1):
        var painted_before := false
        var bare := 0
        for x in range(int(START.x + 2.0 * RADIUS), int(END.x - 2.0 * RADIUS)):
            if _alpha(layer, Vector2i(x, y), images) > 0.5:
                if painted_before and bare >= BREAK:
                    count += 1
                painted_before = true
                bare = 0
            else:
                bare += 1
    return count


func _alpha(layer: SaLayer, pixel: Vector2i, images: Dictionary) -> float:
    for grid: Vector2i in layer.chunks:
        var side := (layer.chunks[grid] as SaChunk).pixel_size()
        var here := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
        if not layer.chunks.has(here):
            return 0.0
        if not images.has(here):
            @warning_ignore("static_called_on_instance")
            images[here] = SaExport.get_texture_image_float(layer.get_field(here))
        return (images[here] as Image).get_pixelv(pixel - here * side).a
    return 0.0
