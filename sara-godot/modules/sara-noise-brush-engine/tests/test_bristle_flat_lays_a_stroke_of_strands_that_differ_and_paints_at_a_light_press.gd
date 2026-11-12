## Bristle Flat lays a stroke of strands that differ in width and spacing
## across the brush, so it reads as hairs and not as a comb, and a light press
## lays some of them.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Bristle Flat as it ships less its radius taper, so the body is one width,
## paints one level stroke in a mid brown. Every [constant STEP] pixels along
## the body a column is read across it, inside [constant BODY] of the
## half-width, and each run of texels painted at least [constant PAINTED] is a
## strand, or strands that merged. Its width is the run's length and the gap to
## the next is the distance between their middles. The painted share is read
## over the body's core, as the near zero pressure suite reads it.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")

const PRESET := "Bristle Flat"
## The press the widths are read at, and the least spread of them as a share
## of their mean.
const WORKING := 0.5
const WIDTH_SPREAD := 0.15
## A light press and the least share of the core it paints, and a lighter one.
const LIGHT := 0.4
const LEAST_AT_LIGHT := 0.25
const LIGHTEST := 0.15
const LEAST_AT_LIGHTEST := 0.03
## The least share of the texels across a column two strokes of other seeds
## paint differently, so the strands are drawn for each stroke.
const SEEDS_DIFFER := 0.2
## The canvas, the tip's radius, the stroke's ends, the gap between two samples
## in pixels and in milliseconds, and the stroke's seed.
const CANVAS := Vector2i(1024, 256)
const RADIUS := 30.0
const FROM := Vector2(60.0, 128.0)
const TO := Vector2(964.0, 128.0)
const SPACING := 4.0
const SAMPLE_MS := 8.0
const SEED := 7
## How many radii from each end the body is read from, the share of the
## half-width the strands are read across and the share the cover is read
## over, the gap between two columns, and the alpha a texel holds to be painted.
const END_MARGIN := 2.0
const BODY := 0.8
const CORE := 0.6
const STEP := 6
const PAINTED := 0.5
const COLOUR := Color(0.55, 0.32, 0.18, 1.0)

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null
var _albedo: Dictionary = {}


func before_each() -> void:
    _surface = Fixtures.make_surface(CANVAS)


func after_each() -> void:
    _brush = null
    _albedo.clear()
    Fixtures.teardown(_surface)
    _surface = null


func test_the_strands_across_the_brush_differ_in_width() -> void:
    _paint(WORKING, SEED)
    var widths: Array[float] = []
    var gaps: Array[float] = []
    for x in _columns():
        var middles: Array[float] = []
        for run: Vector2 in _runs(x):
            widths.append(run.y - run.x + 1.0)
            middles.append(0.5 * (run.x + run.y))
        for i in range(1, middles.size()):
            gaps.append(middles[i] - middles[i - 1])
    var spread := _spread(widths) / maxf(_mean(widths), 1e-6)
    print(
        (
            "Bristle Flat at %.1f: %d strands, widths mean %.2f spread %.3f, %d gaps mean %.2f spread %.3f"
            % [WORKING, widths.size(), _mean(widths), spread, gaps.size(), _mean(gaps), _spread(gaps) / maxf(_mean(gaps), 1e-6)]
        )
    )
    assert_true(widths.size() > 100, "At %.1f the body holds %d strands, more than 100" % [WORKING, widths.size()])
    assert_true(
        spread >= WIDTH_SPREAD,
        "At %.1f the strands' widths spread by %.3f of their mean, at least %.2f" % [WORKING, spread, WIDTH_SPREAD]
    )


func test_a_light_press_lays_some_strands_and_a_lighter_one_a_few() -> void:
    var lightest := _cover(LIGHTEST)
    var light := _cover(LIGHT)
    print("Bristle Flat paints %.3f of its core at %.2f and %.3f at %.2f" % [lightest, LIGHTEST, light, LIGHT])
    assert_true(
        lightest >= LEAST_AT_LIGHTEST,
        "At %.2f Bristle Flat paints %.3f of its core, at least %.2f" % [LIGHTEST, lightest, LEAST_AT_LIGHTEST]
    )
    assert_true(
        light >= LEAST_AT_LIGHT, "At %.2f Bristle Flat paints %.3f of its core, at least %.2f" % [LIGHT, light, LEAST_AT_LIGHT]
    )


func test_two_strokes_lay_their_strands_in_other_places() -> void:
    _paint(WORKING, SEED)
    var first := _painted_rows()
    _paint(WORKING, SEED + 1)
    var second := _painted_rows()
    var differ := 0
    for i in first.size():
        if first[i] != second[i]:
            differ += 1
    var share := float(differ) / maxi(first.size(), 1)
    print("Two seeds paint %.3f of the body's texels differently" % share)
    assert_true(
        share >= SEEDS_DIFFER,
        "Two strokes of other seeds paint %.3f of the body's texels differently, at least %.2f" % [share, SEEDS_DIFFER]
    )


## The columns the body is read at.
func _columns() -> Array[int]:
    var columns: Array[int] = []
    for x in range(int(FROM.x + END_MARGIN * RADIUS), int(TO.x - END_MARGIN * RADIUS), STEP):
        columns.append(x)
    return columns


## Whether each texel of the body's columns is painted, column by column.
func _painted_rows() -> Array[bool]:
    var reach := int(RADIUS * BODY)
    var painted: Array[bool] = []
    for x in _columns():
        for y in range(int(FROM.y) - reach, int(FROM.y) + reach + 1):
            painted.append(_texel(Vector2i(x, y)).a >= PAINTED)
    return painted


## The share of the core painted by a stroke at *pressure*.
func _cover(pressure: float) -> float:
    _paint(pressure, SEED)
    var reach := int(RADIUS * CORE)
    var painted := 0
    var count := 0
    for x in range(int(FROM.x + END_MARGIN * RADIUS), int(TO.x - END_MARGIN * RADIUS)):
        for y in range(int(FROM.y) - reach, int(FROM.y) + reach + 1):
            count += 1
            if _texel(Vector2i(x, y)).a >= PAINTED:
                painted += 1
    return float(painted) / count


## The runs of painted texels across the body at column *x*, each its first
## and last row, leaving out a run that touches the read's edge.
func _runs(x: int) -> Array[Vector2]:
    var reach := int(RADIUS * BODY)
    var top := int(FROM.y) - reach
    var size := 2 * reach + 1
    var runs: Array[Vector2] = []
    var at := 0
    while at < size:
        if _texel(Vector2i(x, top + at)).a < PAINTED:
            at += 1
            continue
        var start := at
        while at < size and _texel(Vector2i(x, top + at)).a >= PAINTED:
            at += 1
        if start > 0 and at < size:
            runs.append(Vector2(top + start, top + at - 1))
    return runs


func _mean(values: Array[float]) -> float:
    if values.is_empty():
        return 0.0
    var total := 0.0
    for value: float in values:
        total += value
    return total / values.size()


func _spread(values: Array[float]) -> float:
    var mean := _mean(values)
    var total := 0.0
    for value: float in values:
        total += (value - mean) * (value - mean)
    return sqrt(total / maxi(values.size(), 1))


## A stroke at *pressure* and *at_seed* on a fresh canvas, in [constant PRESET]
## as it ships without its radius taper, at [constant RADIUS].
func _paint(pressure: float, at_seed: int) -> void:
    _albedo.clear()
    Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(CANVAS)
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = at_seed
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == PRESET:
            var untapered := entry.duplicate(true)
            (untapered["pressure"] as Dictionary).erase("radius")
            _brush.settings = NoisePresetsScript.build(NoiseBrushSettingsScript, untapered)
    _brush.settings.color = COLOUR
    _brush.settings.radius = RADIUS / mini(CANVAS.x, CANVAS.y)
    var clock := 1000.0
    _brush.begin_stroke(FROM, pressure, Vector2.ZERO, clock)
    var steps := ceili(FROM.distance_to(TO) / SPACING)
    for i in range(1, steps + 1):
        clock += SAMPLE_MS
        _brush.add_sample(FROM.lerp(TO, float(i) / steps), pressure, Vector2.ZERO, clock)
    _brush.end_stroke()


## The active layer's texel at *pixel*.
func _texel(pixel: Vector2i) -> Color:
    var layer := _surface.easel.document.active_layer
    for grid: Vector2i in layer.chunks:
        var side := (layer.chunks[grid] as SaChunk).pixel_size()
        var here := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
        if not layer.chunks.has(here):
            return Color.TRANSPARENT
        if not _albedo.has(here):
            @warning_ignore("static_called_on_instance")
            _albedo[here] = SaExport.get_texture_image_float(layer.get_field(here))
        return (_albedo[here] as Image).get_pixelv(pixel - here * side)
    return Color.TRANSPARENT
