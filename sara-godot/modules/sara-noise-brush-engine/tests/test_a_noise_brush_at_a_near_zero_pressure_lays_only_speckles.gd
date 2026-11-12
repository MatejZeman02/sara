## A noise brush at a near zero pressure lays only speckles.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## At a pressure near zero a Sea Sponge stroke paints almost nothing, only some
## speckles. Each preset paints one level stroke at
## each of [constant PRESSURES] on a fresh canvas, as it ships less the radius
## taper so the body is one width at every press, and the share of the core's
## texels painted at least [constant PAINTED] is read off the layer. The core is
## the stroke less [constant END_MARGIN] radii at either end and less
## everything past [constant BODY] of the half-width, as the body-share suite reads it.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")

## The two presets the row names, Firm Fill the most solid and Sea Sponge the
## the one that matters most for speckles.
const PRESETS: Array[String] = ["Firm Fill", "Sea Sponge"]
## The presets whose shares are printed as a table.
const TABLE: Array[String] = ["Firm Fill", "Smeary Flat", "Sea Sponge", "Ribbon Pen", "Graphite Pencil", "Bristle Flat"]
const PRESSURES: Array[float] = [0.05, 0.15, 0.3, 0.5]
## The most of the core a press of 0.05 and of 0.15 may paint.
const MOST_AT_NEAR_ZERO := 0.10
const MOST_AT_LIGHT := 0.25
## The share each of [constant PRESETS] paints at 0.5 with the cut alone, on
## this seed on the reference card, which the speck curve leaves open
## from a half up, and how far the share may move from it.
const BEFORE_AT_HALF: Dictionary = {"Firm Fill": 1.0, "Sea Sponge": 0.980}
const HALF_KEPT := 0.03
const CANVAS := Vector2i(1024, 256)
const RADIUS := 30.0
const FROM := Vector2(60.0, 128.0)
const TO := Vector2(964.0, 128.0)
const SPACING := 4.0
const SAMPLE_MS := 8.0
const SEED := 7
const END_MARGIN := 2.0
const BODY := 0.6
## The alpha a texel holds to count as painted.
const PAINTED := 0.5

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


## The table of cover at the four pressures, printed for the record.
func test_the_cover_of_every_preset_at_the_four_pressures_is_printed() -> void:
    for preset: String in TABLE:
        var shares: Array[String] = []
        for pressure: float in PRESSURES:
            shares.append("%.3f" % _painted_share(preset, pressure))
        print("Cover: %s at %s paints %s" % [preset, PRESSURES, shares])
    assert_true(true, "the table is printed")


## A near zero press lays only specks, a light one a quarter of the body at
## most, and a press of a half lays what the cut alone lays.
func test_a_near_zero_press_lays_specks_and_a_working_one_is_as_it_was() -> void:
    for preset: String in PRESETS:
        var near_zero := _painted_share(preset, 0.05)
        var light := _painted_share(preset, 0.15)
        var half := _painted_share(preset, 0.5)
        assert_true(
            near_zero <= MOST_AT_NEAR_ZERO,
            "%s at 0.05 paints %.3f of its core, at most %.2f" % [preset, near_zero, MOST_AT_NEAR_ZERO]
        )
        assert_true(light <= MOST_AT_LIGHT, "%s at 0.15 paints %.3f of its core, at most %.2f" % [preset, light, MOST_AT_LIGHT])
        var before: float = BEFORE_AT_HALF[preset]
        assert_true(
            absf(half - before) <= HALF_KEPT,
            "%s at 0.5 paints %.3f of its core, within %.2f of the cut's own %.3f" % [preset, half, HALF_KEPT, before]
        )


## The share of the core painted by *preset* at *pressure* on a fresh canvas.
func _painted_share(preset: String, pressure: float) -> float:
    _albedo.clear()
    Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(CANVAS)
    _use(preset)
    _stroke(pressure)
    var reach := int(RADIUS * BODY)
    var first := int(FROM.x + END_MARGIN * RADIUS)
    var last := int(TO.x - END_MARGIN * RADIUS)
    var painted := 0
    var count := 0
    for x in range(first, last):
        for y in range(int(FROM.y) - reach, int(FROM.y) + reach + 1):
            count += 1
            if _texel(Vector2i(x, y)).a >= PAINTED:
                painted += 1
    return float(painted) / count


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


## The level stroke at *pressure* all the way, a sample every
## [constant SPACING] pixels.
func _stroke(pressure: float) -> void:
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
