## A noise stroke at a working press lays paint over most of its body, and a
## light one keeps its holes.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A noise stroke at a press a painter works at has to lay enough opaque paint
## to paint with, and still be "quite opaque but not everywhere". Grain Round
## and Bristle Flat, each as it ships less the radius taper so the body is one
## width at every press, paint one level stroke at each of
## [constant PRESSURES] on a fresh canvas, and the share of the core's texels
## painted at least [constant PAINTED] is read off the layer. The core is the
## stroke less [constant END_MARGIN] radii at either end and less everything
## past [constant BODY] of the half-width, inside the rim Hardness thins.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")

const PRESETS: Array[String] = ["Grain Round", "Bristle Flat"]
const PRESSURES: Array[float] = [0.3, 0.5, 0.8]
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
## The share of the core painted at 0.8 a stroke has to pass. On this seed on
## the reference card, Grain Round paints 0.485, 0.701 and 0.929 at
## 0.3, 0.5 and 0.8 and Bristle Flat 0.206, 0.366 and 0.909. A bristle whose
## gap needs the full press paints 0.269 at 0.8, so three quarters is most of
## the body with room for a seed or a card to move it.
const MOST := 0.75
## The share at 0.8 that would read as a solid fill rather than an opaque
## stroke with holes, which the design keeps.
const SOLID := 0.98
## How much less of the core a light press of 0.3 paints than the working one.
const HOLES := 0.3

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


## The share at a working press is most of the body and below all of it, it
## rises with the press, and a light press leaves clearly more holes.
func test_a_working_press_paints_most_of_the_body_and_a_light_one_keeps_its_holes() -> void:
    for preset: String in PRESETS:
        var shares: Array[float] = []
        for pressure: float in PRESSURES:
            shares.append(_painted_share(preset, pressure))
        print("Body: %s paints %s of its core at %s" % [preset, shares, PRESSURES])
        var light := shares[0]
        var working := shares[-1]
        assert_true(working > MOST, "%s at %.1f paints %.3f of its core, more than %.2f" % [preset, PRESSURES[-1], working, MOST])
        assert_true(
            working < SOLID,
            "%s at %.1f paints %.3f, below %.2f, so it is not a solid fill" % [preset, PRESSURES[-1], working, SOLID]
        )
        for at in range(1, shares.size()):
            assert_true(
                shares[at] > shares[at - 1],
                (
                    "%s paints %.3f at %.1f, more than %.3f at %.1f"
                    % [preset, shares[at], PRESSURES[at], shares[at - 1], PRESSURES[at - 1]]
                )
            )
        assert_true(
            working - light >= HOLES,
            (
                "%s at %.1f paints %.3f, at least %.2f less than %.3f at %.1f"
                % [preset, PRESSURES[0], light, HOLES, working, PRESSURES[-1]]
            )
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
