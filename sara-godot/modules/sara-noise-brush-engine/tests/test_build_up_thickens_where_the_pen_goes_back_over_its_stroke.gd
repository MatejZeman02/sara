## Build Up at its top thickens the paint where the pen goes back over its
## stroke, and never paints less than at its bottom.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The path of a matched pair of strokes: right, back left and
## right again, one stroke at [constant PRESSURE]. Bristle Flat and Firm Fill,
## each as it ships less the radius taper, paint it with Build Up at nought
## and at one, on [constant SEEDS] seeds each, since one seed's streaks can
## land where another's holes do. The painted share is read over the stroke's
## box, the texels holding more than [constant PAINTED], and the mean alpha
## over the overlapped part, the stretch all three legs cross whole within
## [constant BODY] of the half-width either side of the path.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")

const PRESETS: Array[String] = ["Bristle Flat", "Firm Fill"]
const PRESSURE := 0.5
const CANVAS := Vector2i(512, 256)
const RADIUS := 24.0
const SPACING := 4.0
const SAMPLE_MS := 8.0
const SEEDS: Array[int] = [7, 19, 31]
## The legs' ends, a leg six radii long, on the canvas's middle row.
const LEFT := 184.0
const RIGHT := 328.0
const ROW := 128.0
## How far in from where the legs turn the overlapped part starts, in radii,
## so a turn's own round end is not read.
const MARGIN := 1.0
const BODY := 0.6
## The alpha a texel holds to count as painted.
const PAINTED := 0.05
## How much more mean alpha Bristle Flat's overlapped part holds at Build Up
## one than at nought. Its strands lie at full alpha on lines a return keeps
## straight, so the gain is paint laid in the gaps between them, and a larger
## one would bend the streaks the reversal's own suite holds straight. Firm
## Fill's one pass already holds the overlap opaque at this pressure, so for
## it the overlap only holds no less.
const THICKER := {"Bristle Flat": 0.04, "Firm Fill": 0.0}

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


## At one the stroke paints at least the share it paints at nought, and its
## overlapped part holds at least [constant THICKER] more mean alpha.
func test_build_up_at_its_top_paints_no_less_and_thickens_the_overlap() -> void:
    for preset: String in PRESETS:
        var low := _reading(preset, 0.0)
        var high := _reading(preset, 1.0)
        var thicker: float = THICKER[preset]
        print(
            (
                "Build Up: %s paints %.3f of its box at 0 and %.3f at 1, the overlap's mean alpha %.3f and %.3f"
                % [preset, low.x, high.x, low.y, high.y]
            )
        )
        assert_true(
            high.x >= low.x, "%s at Build Up 1 paints %.3f of its box, at least the %.3f it paints at 0" % [preset, high.x, low.x]
        )
        assert_true(
            high.y >= low.y + thicker,
            (
                "%s's overlap holds a mean alpha of %.3f at Build Up 1, at least %.2f more than the %.3f at 0"
                % [preset, high.y, thicker, low.y]
            )
        )


## The painted share of the box and the overlap's mean alpha, as the mean over
## [constant SEEDS], of *preset* at Build Up *rate*.
func _reading(preset: String, rate: float) -> Vector2:
    var sum := Vector2.ZERO
    for stroke_seed: int in SEEDS:
        _fresh(preset, rate, stroke_seed)
        _paint(PackedVector2Array([Vector2(LEFT, ROW), Vector2(RIGHT, ROW), Vector2(LEFT, ROW), Vector2(RIGHT, ROW)]))
        sum += Vector2(_painted_share(), _overlap_alpha())
    return sum / SEEDS.size()


func _painted_share() -> float:
    var painted := 0
    var count := 0
    for x in range(int(LEFT - RADIUS), int(RIGHT + RADIUS)):
        for y in range(int(ROW - RADIUS), int(ROW + RADIUS)):
            count += 1
            if _texel(Vector2i(x, y)).a > PAINTED:
                painted += 1
    return float(painted) / count


func _overlap_alpha() -> float:
    var reach := int(RADIUS * BODY)
    var total := 0.0
    var count := 0
    for x in range(int(LEFT + MARGIN * RADIUS), int(RIGHT - MARGIN * RADIUS)):
        for y in range(int(ROW) - reach, int(ROW) + reach + 1):
            count += 1
            total += _texel(Vector2i(x, y)).a
    return total / count


## A fresh canvas and *preset* as it ships without its radius taper, at
## [constant RADIUS], Build Up *rate* and *stroke_seed*, in black.
func _fresh(preset: String, rate: float, stroke_seed: int) -> void:
    _albedo.clear()
    Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(CANVAS)
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = stroke_seed
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == preset:
            var untapered := entry.duplicate(true)
            (untapered["pressure"] as Dictionary).erase("radius")
            _brush.settings = NoisePresetsScript.build(NoiseBrushSettingsScript, untapered)
    _brush.settings.color = Color(0.0, 0.0, 0.0, 1.0)
    _brush.settings.radius = RADIUS / mini(CANVAS.x, CANVAS.y)
    _brush.settings.build_up = rate


## One stroke through the corners of *path* at [constant PRESSURE], a sample
## every [constant SPACING] pixels.
func _paint(path: PackedVector2Array) -> void:
    var clock := 1000.0
    _brush.begin_stroke(path[0], PRESSURE, Vector2.ZERO, clock)
    for leg in range(1, path.size()):
        var from := path[leg - 1]
        var steps := ceili(from.distance_to(path[leg]) / SPACING)
        for i in range(1, steps + 1):
            clock += SAMPLE_MS
            _brush.add_sample(from.lerp(path[leg], float(i) / steps), PRESSURE, Vector2.ZERO, clock)
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
