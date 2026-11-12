## A ribbon pen's dab does not grow with the pressure before the stroke is
## committed.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Ribbon Pen's radius follows the pressure. A pen pressed and held on the spot
## writes a harder press onto the press point, half extents and all, and the
## front laid under the pen took them, so the painter saw a dab grow and shrink
## that the stroke had not committed. Now the front keeps the size it was first
## laid with until a body is laid, and then takes the body's.
##
## **Held still.** The pen presses at 0.2 and is held exactly still, then at
## 0.8 without moving. The front's radius, the half extent it is drawn with,
## is the same at both, and nothing it paints at 0.8 lies farther from the spot
## than that radius and a texel.
##
## **Moved.** The pen then moves at 0.8, a sample a pixel, and a body is laid
## within one radius of the brush's size, 20.48 pixels. The front's radius is
## then the body's at its newest point within a texel, and larger than the
## press's.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")
const NoiseStretchScript = preload("res://modules/sara-noise-brush-engine/dab_list/noise_stretch.gd")

const CANVAS := Vector2i(256, 256)
## The preset's radius as a share of the canvas's side, 20.48 pixels at a full
## press, wide enough to measure in texels.
const RADIUS := 0.08
const SPOT := Vector2(96.0, 128.0)
const LIGHT := 0.2
const HARD := 0.8
const HELD := 12
const TEXEL := 1.0
## The alpha a texel counts as painted from.
const PAINTED := 0.02

var _surface: SaSurface = null


func after_each() -> void:
    Fixtures.teardown(_surface)
    _surface = null


func test_a_pen_held_still_keeps_the_front_s_radius_and_moving_gives_it_the_body_s() -> void:
    var brush := _fresh_brush()
    brush.begin_stroke(SPOT, LIGHT)
    for i in HELD:
        brush.add_sample(SPOT, LIGHT)
    var light: float = brush.dab_list.front.drawn_radius
    assert_true(light > 1.0, "the press at %.1f lays a front of radius %.2f" % [LIGHT, light])
    for i in HELD:
        brush.add_sample(SPOT, HARD)
    var hard: float = brush.dab_list.front.drawn_radius
    assert_eq(hard, light, "held still at %.1f the front keeps the radius it pressed with at %.1f" % [HARD, LIGHT])
    var reach := _painted_reach(_document().stroke_layer, SPOT)
    assert_true(reach <= light + TEXEL, "and paints no farther than %.2f from the spot, %.2f" % [light + TEXEL, reach])
    var to := SPOT
    var full := RADIUS * CANVAS.x
    while brush.dab_list.front.first_laid == NoiseStretchScript.FIRST_NOTHING and to.x < SPOT.x + 2.0 * full:
        to.x += 1.0
        brush.add_sample(to, HARD)
    assert_true(
        to.x - SPOT.x <= full + TEXEL,
        "a body is laid once the pen moved one radius, %.1f pixels, here %.1f" % [full, to.x - SPOT.x]
    )
    var moved: float = brush.dab_list.front.drawn_radius
    var body: float = brush.dab_list.stretch.newest_radius
    assert_true(absf(moved - body) <= TEXEL, "moved one radius the front's radius %.2f is the body's %.2f" % [moved, body])
    assert_true(moved > light + TEXEL, "and the body's at %.1f, larger than the press's %.2f" % [HARD, light])
    brush.end_stroke()


func _fresh_brush() -> StateNoiseBrushScript:
    _surface = Fixtures.make_surface(CANVAS)
    var brush := StateNoiseBrushScript.new()
    brush.surface = _surface
    brush.stroke_seed = 7
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == "Ribbon Pen":
            brush.settings = NoisePresetsScript.build(NoiseBrushSettingsScript, entry)
    brush.settings.radius = RADIUS
    brush.settings.color = Color(0.0, 0.0, 0.0, 1.0)
    return brush


func _document() -> SaDocument:
    return _surface.easel.document


## The farthest painted texel of *layer* from *centre*, in pixels.
func _painted_reach(layer: SaLayer, centre: Vector2) -> float:
    var most := 0.0
    for grid: Vector2i in layer.chunks:
        var side := (layer.chunks[grid] as SaChunk).pixel_size()
        @warning_ignore("static_called_on_instance")
        var image := SaExport.get_texture_image_float(layer.get_field(grid))
        for y in side:
            for x in side:
                if image.get_pixel(x, y).a <= PAINTED:
                    continue
                var at := Vector2(grid * side + Vector2i(x, y)) + Vector2(0.5, 0.5)
                most = maxf(most, at.distance_to(centre))
    return most
