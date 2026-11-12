## The edge of a noise stroke is not one unit repeated.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The outline of a long noise stroke should read as a brush that runs out of
## paint in places, not as one tuft stamped over and over. Grain Round and
## Bristle Flat, each as it ships less the radius taper, paint one level stroke
## of [constant LENGTH] pixels at a press of [constant PRESSURE], and the
## outline on each side is read as the distance from the path to the outermost
## texel painted at least [constant PAINTED], at every texel along the stroke.
## Its autocorrelation about its mean, at every lag from one `grain_scale` to
## one tip width, stays under [constant REPEAT], and its spread at the scales
## of one tip width and of four stays over [constant WANDER_ONE] and [constant WANDER_FOUR] pixels, so the edge is
## neither a pattern nor smooth.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")

const PRESETS: Array[String] = ["Grain Round", "Bristle Flat"]
const PRESSURE := 0.8
const CANVAS := Vector2i(1024, 256)
const RADIUS := 30.0
const LENGTH := 600
const FROM := Vector2(212.0, 128.0)
const SPACING := 4.0
const SAMPLE_MS := 8.0
const SEED := 7
## The alpha a texel holds to count as painted.
const PAINTED := 0.5
## The greatest autocorrelation of an outline at any lag from one grain scale
## to one tip width. Before the edge moved, on this seed on
## the reference card, Bristle Flat's outline was one line at one distance on both sides,
## the most a correlation can be, which this suite reads as 1.000, and Grain
## Round's read 0.151 and 0.112. After, the four read 0.181, 0.082, 0.202 and
## 0.101. One 600 pixel outline of noise with no repeat in it reads up to
## about 0.2 at some lag on its own, as the tunings that moved only the
## nicks' sizes showed, so the bound is that and a little room. Grain Round's
## fault before was not a repeat by this measure but an edge too smooth to
## read as a brush, which the spread below catches.
const REPEAT := 0.25
## The least spread, in pixels, of an outline smoothed over one tip width.
## Before, Grain Round's read 0.28 and 0.17 and Bristle Flat's nothing, and
## after, the four read 1.47, 1.34, 1.72 and 1.85.
const WANDER_ONE := 0.75
## The least spread, in pixels, of an outline smoothed over four tip widths.
## Before, Grain Round's read 0.09 and 0.05 and Bristle Flat's nothing, and
## after, 0.40, 0.40, 0.47 and 0.76.
const WANDER_FOUR := 0.25

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


## Neither side of either preset's stroke repeats one unit, and neither is
## smooth over a tip width or four.
func test_the_outline_has_no_length_at_which_it_repeats_and_is_not_smooth() -> void:
    for preset: String in PRESETS:
        _albedo.clear()
        Fixtures.teardown(_surface)
        _surface = Fixtures.make_surface(CANVAS)
        _use(preset)
        _stroke()
        var shortest := maxi(1, roundi(_brush.settings.grain_scale))
        var longest := roundi(2.0 * RADIUS)
        for side: int in [-1, 1]:
            var outline := _outline(side)
            var repeat := _greatest_correlation(outline, shortest, longest)
            var one := _spread(_smoothed(outline, longest))
            var four := _spread(_smoothed(outline, 4 * longest))
            print(
                (
                    # gdlint:ignore=max-line-length
                    "Edge: %s side %d, autocorrelation at most %.3f over lags %d to %d, spread %.2f px over one tip width and %.2f over four"
                    % [preset, side, repeat, shortest, longest, one, four]
                )
            )
            assert_true(repeat < REPEAT, "%s side %d correlates %.3f with itself, under %.2f" % [preset, side, repeat, REPEAT])
            assert_true(
                one > WANDER_ONE, "%s side %d spreads %.2f px over a tip width, more than %.2f" % [preset, side, one, WANDER_ONE]
            )
            assert_true(
                four > WANDER_FOUR,
                "%s side %d spreads %.2f px over four tip widths, more than %.2f" % [preset, side, four, WANDER_FOUR]
            )


## The distance from the path to the outermost painted texel on *side*, one
## to a texel along the stroke, nought where the side lays nothing.
func _outline(side: int) -> PackedFloat32Array:
    var outline := PackedFloat32Array()
    var reach := int(RADIUS) + 4
    for x in range(int(FROM.x), int(FROM.x) + LENGTH):
        var far := 0.0
        for d in range(reach, 0, -1):
            if _texel(Vector2i(x, int(FROM.y) + side * d)).a >= PAINTED:
                far = d
                break
        outline.append(far)
    return outline


## The greatest autocorrelation of *values* about their mean at a lag from
## *shortest* to *longest*.
static func _greatest_correlation(values: PackedFloat32Array, shortest: int, longest: int) -> float:
    var mean := _mean(values)
    var power := 0.0
    for v: float in values:
        power += (v - mean) * (v - mean)
    if power <= 0.0:
        return 1.0
    var greatest := -1.0
    for lag in range(shortest, longest + 1):
        var sum := 0.0
        for i in range(values.size() - lag):
            sum += (values[i] - mean) * (values[i + lag] - mean)
        greatest = maxf(greatest, sum / power)
    return greatest


## *values* averaged over a window of *width*, one to each full window.
static func _smoothed(values: PackedFloat32Array, width: int) -> PackedFloat32Array:
    var out := PackedFloat32Array()
    var sum := 0.0
    for i in range(values.size()):
        sum += values[i]
        if i >= width:
            sum -= values[i - width]
        if i >= width - 1:
            out.append(sum / width)
    return out


static func _mean(values: PackedFloat32Array) -> float:
    var sum := 0.0
    for v: float in values:
        sum += v
    return sum / maxi(values.size(), 1)


## The standard deviation of *values*.
static func _spread(values: PackedFloat32Array) -> float:
    var mean := _mean(values)
    var sum := 0.0
    for v: float in values:
        sum += (v - mean) * (v - mean)
    return sqrt(sum / maxi(values.size(), 1))


## *preset* as it ships without its radius taper, at [constant RADIUS] and
## [constant SEED], in black.
func _use(preset: String) -> void:
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = SEED
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == preset:
            var untapered := entry.duplicate(true)
            (untapered["pressure"] as Dictionary).erase("radius")
            _brush.settings = NoisePresetsScript.build(NoiseBrushSettingsScript, untapered)
    _brush.settings.color = Color(0.0, 0.0, 0.0, 1.0)
    _brush.settings.radius = RADIUS / mini(CANVAS.x, CANVAS.y)


## The level stroke of [constant LENGTH] at [constant PRESSURE], a sample
## every [constant SPACING] pixels.
func _stroke() -> void:
    var to := FROM + Vector2(LENGTH, 0.0)
    var clock := 1000.0
    _brush.begin_stroke(FROM, PRESSURE, Vector2.ZERO, clock)
    var steps := ceili(LENGTH / SPACING)
    for i in range(1, steps + 1):
        clock += SAMPLE_MS
        _brush.add_sample(FROM.lerp(to, float(i) / steps), PRESSURE, Vector2.ZERO, clock)
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
