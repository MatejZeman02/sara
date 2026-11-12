## A noise stroke's first dab lays no more paint than the body after it, in
## every stock preset.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A pen's press carries no pressure, so it waits for the first sample's. A pen
## held still past [constant StateNoiseBrushScript.PRESS_WAIT_MS] laid its
## press at a tap's full pressure instead, since its hover reported none, and
## the stroke opened on a blot of full paint and a first segment drawn down
## from it. On the reference card at [constant LIGHT], Bristle Flat's first
## [constant WINDOW] pixels held a mean alpha of 0.164 where its densest body
## window held 0.001, Wet Into Wet's 0.175 where a pen that moved at once laid
## 0.001, Wood Grain laid 0.050 where its body lays nothing at that press, and
## Watery Lift's body, whose opacity reads the pressure against the stroke's
## peak, fell from 0.417 to 0.188.
## Each preset here paints one level stroke at [constant LIGHT] whose pen rests
## on the press past the wait, and one whose pen moves at once, and reads the
## mean alpha of the stroke's first [constant WINDOW] pixels against every
## window of the body. A press that starts firm and lightens still opens dark.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")

const CANVAS := Vector2i(512, 256)
const FROM := Vector2(60.0, 128.0)
const TO := Vector2(420.0, 128.0)
const SPACING := 4.0
const SAMPLE_MS := 8.0
const SEED := 7
## The steady light pressure the level strokes are drawn at.
const LIGHT := 0.45
## The press a firm start opens at before it lightens to [constant LIGHT] over
## [constant EASE] samples.
const FIRM := 1.0
const EASE := 30
## How long along the stroke a window of the reading is, in document pixels.
const WINDOW := 20
## How far either side of the stroke's line the reading reaches, beyond the
## tip's radius.
const BAND := 4
## How much more alpha, in the mean, the first window may hold than the
## densest window of the body, for the grain's wander. A blot read 0.007 to
## 0.16 above it, and a press laid at the first sample's pressure reads the
## same to four places whether the pen rested or moved.
const SLACK := 0.01

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null
var _albedo: Dictionary = {}


func after_each() -> void:
    _brush = null
    _albedo.clear()
    if _surface != null:
        Fixtures.teardown(_surface)
    _surface = null


## A pen that rests on its press past the wait opens no denser than its body,
## and opens as the same stroke does whose pen moved at once.
func test_every_stock_preset_s_first_dab_is_within_its_body_after_a_held_press() -> void:
    for entry: Dictionary in NoisePresetsScript.entries():
        var name := String(entry["name"])
        var held := _windows(entry, true, _level())
        var moved := _windows(entry, false, _level())
        var body := _densest(held)
        print(
            (
                "First dab: %s opens at %.4f after a held press and %.4f after a moving one, the body's densest window %.4f"
                % [name, held[0], moved[0], body]
            )
        )
        assert_true(
            held[0] <= body + SLACK,
            "%s's first %d px after a held press hold %.4f, no more than its body's %.4f" % [name, WINDOW, held[0], body]
        )
        assert_true(
            moved[0] <= _densest(moved) + SLACK,
            (
                "%s's first %d px after a moving press hold %.4f, no more than its body's %.4f"
                % [name, WINDOW, moved[0], _densest(moved)]
            )
        )
        assert_almost_eq(held[0], moved[0], SLACK, "%s opens as a pen that moved at once opens" % name)


## A press that starts firm and lightens opens denser than the light body after
## it, and denser than the same stroke drawn light from its press: the first
## sample answers the press with the reading it gave.
func test_a_firm_press_that_lightens_still_opens_dark() -> void:
    for name: String in ["Wet Into Wet", "Grain Round", "Bristle Flat"]:
        var entry := _entry(name)
        var firm := _windows(entry, true, _easing())
        var light := _windows(entry, true, _level())
        var late := _mean(firm.slice(firm.size() - 6))
        print("Firm start: %s opens at %.4f, its late body %.4f, a light start %.4f" % [name, firm[0], late, light[0]])
        assert_true(firm[0] > late, "%s's firm start, %.4f, is darker than its light body, %.4f" % [name, firm[0], late])
        assert_true(firm[0] > light[0], "%s's firm start, %.4f, is darker than a light one, %.4f" % [name, firm[0], light[0]])


## The pressures of a level stroke.
func _level() -> Array[float]:
    var out: Array[float] = []
    out.resize(_steps())
    out.fill(LIGHT)
    return out


## The pressures of a stroke that opens at [constant FIRM] and eases to
## [constant LIGHT].
func _easing() -> Array[float]:
    var out: Array[float] = []
    for i in _steps():
        out.append(lerpf(FIRM, LIGHT, minf(1.0, float(i) / EASE)))
    return out


func _steps() -> int:
    return ceili(FROM.distance_to(TO) / SPACING)


func _entry(name: String) -> Dictionary:
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == name:
            return entry
    assert_true(false, "A stock preset is called %s" % name)
    return {}


## The mean alpha of each window of [constant WINDOW] pixels along the stroke
## *entry* paints in black on a fresh canvas at *pressures*, from where its
## paint can first reach, a radius before the press, to a radius before its
## end. A pen *held* on its press rests there past the wait before it moves.
func _windows(entry: Dictionary, held: bool, pressures: Array[float]) -> Array[float]:
    _albedo.clear()
    if _surface != null:
        Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(CANVAS)
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = SEED
    _brush.settings = NoisePresetsScript.build(NoiseBrushSettingsScript, entry)
    _brush.settings.color = Color(0.0, 0.0, 0.0, 1.0)
    var clock := 1000.0
    _brush.begin_stroke(FROM, 0.0, Vector2.ZERO, clock, true)
    if held:
        clock += 2.0 * StateNoiseBrushScript.PRESS_WAIT_MS
        assert_true(_brush.lay_waited_press(clock), "The press was laid by the wait")
    for i in pressures.size():
        clock += SAMPLE_MS
        _brush.add_sample(FROM.lerp(TO, float(i + 1) / pressures.size()), pressures[i], Vector2.ZERO, clock)
    _brush.end_stroke()
    var radius := ceili(_brush.get_cursor_radius())
    var reach := radius + BAND
    var out: Array[float] = []
    var x := int(FROM.x) - radius
    while x + WINDOW <= int(TO.x) - radius:
        var sum := 0.0
        for column in range(x, x + WINDOW):
            for y in range(int(FROM.y) - reach, int(FROM.y) + reach + 1):
                sum += _texel(Vector2i(column, y)).a
        out.append(sum / (WINDOW * (2 * reach + 1)))
        x += WINDOW
    _brush = null
    return out


## The densest window of the body, every window after the first.
static func _densest(windows: Array[float]) -> float:
    var most := 0.0
    for at in range(1, windows.size()):
        most = maxf(most, windows[at])
    return most


static func _mean(values: Array[float]) -> float:
    var sum := 0.0
    for value in values:
        sum += value
    return sum / maxi(1, values.size())


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
