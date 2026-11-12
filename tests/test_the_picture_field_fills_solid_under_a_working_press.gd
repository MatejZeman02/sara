## The Picture field keeps its texture over the press a painter
## works at, the way grain does.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The Done when of the row: a stroke of each shipped pattern at a press of 0.3
## and 0.8, Strength at its default as it ships, reads a spread of paint over
## the stroke's core at both presses, and less paint at the lighter one. The
## press is the cut itself and Strength shifts nothing by default, so this is
## the design's own reading of a pattern. A pattern must not read solid at 0.8, or empty
## at 0.2, though its greys sit in a narrow band of their own and the
## cut only meets them there. The painted stroke is read off the layer, so it is
## what the kernel did.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseFieldsScript = preload("res://modules/sara-noise-brush-engine/noise_fields.gd")
const NoiseFieldBindingScript = preload("res://modules/sara-noise-brush-engine/dab_list/noise_field_binding.gd")

## Four of the patterns `res://patterns` ships. Canvas Scumble is left out,
## because its hollows are nought by design and its preset is cut for them.
const PATTERNS: Array[String] = ["Paper Grain", "Canvas Weave", "Lit Grain", "Dot Screen"]
const RADIUS := 24.0
const FROM := Vector2(20.0, 60.0)
const TO := Vector2(220.0, 60.0)
## The stroke's core, away from its ends and inside the tip's hard edge.
const CORE := Rect2i(50, 50, 140, 21)
## The least standard deviation of alpha over the core that reads as a texture
## rather than a solid stroke. Grain measures 0.183, and a solid picture
## stroke at 0.02 to 0.03 of lightness.
const SPREAD := 0.1

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = 7
    _brush.settings.color = Color(0.2, 0.4, 0.8, 1.0)
    _brush.settings.opacity = 1.0
    _brush.settings.hardness = 1.0
    _brush.settings.radius = RADIUS / 256.0
    _brush.settings.texture_field = "picture"
    _brush.settings.picture_scale = 1.0
    _brush.settings.randomness = 0.0
    _brush.settings.texture_drift = 0.0


func after_each() -> void:
    _brush = null
    Fixtures.teardown(_surface)
    _surface = null


## Every shipped pattern is a texture at a light press and a firm one, and the
## light one lays less paint.
func test_every_shipped_pattern_keeps_its_texture_at_a_light_and_a_firm_press() -> void:
    assert_eq(_brush.settings.strength, 0.0, "Strength shifts nothing, as it ships")
    assert_false(_brush.settings.strength_option.enabled, "and its curve follows no pen, the pressure being the cut")
    for pattern: String in PATTERNS:
        _brush.settings.picture_name = pattern
        var light := _painted(0.3)
        var firm := _painted(0.8)
        assert_true(_brush.field_binding.picture != null, "%s binds (%s)" % [pattern, _brush.field_binding.error])
        assert_true(light.y > SPREAD, "%s at a press of 0.3 is a texture, spread %.3f, paint %.3f" % [pattern, light.y, light.x])
        assert_true(firm.y > SPREAD, "%s at a press of 0.8 is a texture, spread %.3f, paint %.3f" % [pattern, firm.y, firm.x])
        assert_true(light.x < firm.x, "%s lays less paint at 0.3 than at 0.8, %.3f against %.3f" % [pattern, light.x, firm.x])


## The tone range is the grey the pattern's texels sit at less a tail at each
## end, and a flat grey keeps the whole range rather than a stretch to nothing.
func test_the_tone_range_is_read_off_the_mask() -> void:
    var ramp := Image.create(100, 1, false, Image.FORMAT_RF)
    for x in 100:
        ramp.set_pixel(x, 0, Color(0.5 + 0.004 * x, 0.0, 0.0))
    var tone: Vector2 = NoiseFieldBindingScript.tone_of(ramp)
    assert_true(tone.x > 0.5 and tone.x < 0.52, "The low end sits a tail above the darkest texel, %.3f" % tone.x)
    assert_true(tone.y < 0.896 and tone.y > 0.876, "and the high end a tail below the lightest, %.3f" % tone.y)
    var flat := Image.create(8, 8, false, Image.FORMAT_RF)
    flat.fill(Color(0.7, 0.0, 0.0))
    assert_eq(NoiseFieldBindingScript.tone_of(flat), Vector2(0.0, 1.0), "A flat grey keeps nought to one")


## The mean and the standard deviation of alpha over [constant CORE] after one
## stroke at *pressure* on a fresh surface.
func _painted(pressure: float) -> Vector2:
    Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface()
    _brush.surface = _surface
    _brush.begin_stroke(FROM, pressure)
    var steps := 40
    for i in range(1, steps + 1):
        _brush.add_sample(FROM.lerp(TO, float(i) / steps), pressure)
    _brush.end_stroke()
    var layer := _surface.easel.document.active_layer
    var images := {}
    var total := 0.0
    var squares := 0.0
    var count := CORE.size.x * CORE.size.y
    for y in CORE.size.y:
        for x in CORE.size.x:
            var alpha := _alpha(layer, CORE.position + Vector2i(x, y), images)
            total += alpha
            squares += alpha * alpha
    var mean := total / count
    return Vector2(mean, sqrt(maxf(squares / count - mean * mean, 0.0)))


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
