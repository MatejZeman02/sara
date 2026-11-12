## How much a soft Airbrush or Wash pass changes finished paint is measured.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The notes found Airbrush at opacity 0.5 and Wash at 0.35, in short strokes at
## pressure 0.5 to 0.6, hardly darkening the basket's sides. This suite lays the
## script's two passes through the real brush over a ground of the basket's mid
## brown, with the painter's pressure correction made a straight line, and reads
## the colour at the middle of the dash and the alpha it lays. It then lays the
## same dash with one factor taken away at a time, so the figure for the factor
## that took most is an assertion and a later change that moves one fails here.
##
## **Alpha is read from the red channel**, as the share of the way from the
## ground to the paint the texel has come, and the other two channels are held
## to the same share, so a texel that is a mix of the two and nothing else
## passes and a hue neither holds fails.
##
## The dash is the script's `p_shade`: four waypoints along 40 px for Airbrush
## at pressure 0.6 and along 34 px for Wash at 0.5, the ends at three quarters
## of it, one event a frame with the brush ticked as the tool machine ticks it.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")

static var scratch_dir: String = SaDataRoot.path("test_c4_soft_pass")

## The basket's mid brown, in 8-bit steps.
const GROUND := Color(139.0 / 255.0, 94.0 / 255.0, 52.0 / 255.0, 1.0)
const DARK := Color(0.1, 0.1, 0.1, 1.0)
const LIGHT := Color(0.9, 0.9, 0.9, 1.0)

## The dash's middle, inside the one chunk of the 256 px canvas.
const MIDDLE := Vector2(128, 128)
const FRAME := 1.0 / 60.0

## What each pass asks of the brush, from `p_shade`.
const PASSES: Dictionary = {
    "Airbrush": {"radius_px": 26.0, "opacity": 0.5, "length": 40.0, "pressure": 0.6},
    "Wash": {"radius_px": 16.0, "opacity": 0.35, "length": 34.0, "pressure": 0.5},
}

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _was_correction := PackedFloat32Array()


func before_each() -> void:
    _was_correction = SaTablet.correction
    SaTablet.correction = PackedFloat32Array()


func after_each() -> void:
    SaTablet.correction = _was_correction
    if _surface != null:
        Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    if DirAccess.dir_exists_absolute(scratch_dir):
        for file_name: String in DirAccess.get_files_at(scratch_dir):
            DirAccess.remove_absolute(scratch_dir.path_join(file_name))
        DirAccess.remove_absolute(scratch_dir)


## The alpha each pass lays at the dash's middle, and
## with each factor taken away in turn. `base` is the pass as the script lays
## it, `pressure` the same dash at pressure 1.0, `opacity` at the preset's own
## opacity (1.0 for Airbrush and 0.7 for Wash), `texture` with Wash's Canvas
## Weave off (Airbrush names none, so it is the base), `clock` with the airbrush
## clock off, and `flow` with the preset's flow raised to 1.0. Airbrush's base,
## opacity, texture and clock follow the shipped Airbrush, whose opacity curve
## is a nine point bend.
const ALPHAS: Dictionary = {
    "Airbrush": {"base": 0.3291, "pressure": 0.5209, "opacity": 0.5549, "texture": 0.3291, "clock": 0.3291, "flow": 0.9796},
    "Wash": {"base": 0.0652, "pressure": 0.1456, "opacity": 0.1304, "texture": 0.0705, "clock": 0.0652, "flow": 0.1407},
}

## The colour at the middle in 8-bit steps under the dark grey for the same
## cases, which the alphas give by the mix and which is held on its own so a
## change to the ground or the grey cannot move both unseen.
const COLOURS: Dictionary = {
    "Airbrush":
    {
        "base": [102, 71, 43],
        "pressure": [80, 58, 38],
        "opacity": [76, 55, 37],
        "texture": [102, 71, 43],
        "clock": [102, 71, 43],
        "flow": [28, 27, 26]
    },
    "Wash":
    {
        "base": [132, 90, 50],
        "pressure": [122, 84, 48],
        "opacity": [124, 85, 49],
        "texture": [131, 89, 50],
        "clock": [132, 90, 50],
        "flow": [123, 84, 48]
    },
}

## Half a step of 255 and a little over, for the colours.
const COLOUR_TOLERANCE := 1.0

## Tight enough that a changed curve or flow fails it and loose enough for the
## float texture's rounding, which the three runs measured agreed to 1e-6.
const TOLERANCE := 0.01

## Each factor as the change `_lay` takes it away by.
const CHANGES: Dictionary = {
    "pressure": {"pressure": 1.0},
    "opacity": {"own_opacity": true},
    "texture": {"texture": false},
    "clock": {"clock": false},
    "flow": {"flow": 1.0},
}


## The first clause: the pass as the script lays it, in two greys, is a mix of
## the grey and the brown and nothing else, and lays the alpha measured. Every
## channel gives the one share, so no hue neither holds.
func test_a_pass_lays_a_mix_of_its_grey_and_the_ground() -> void:
    for pass_name: String in PASSES:
        for paint: Color in [DARK, LIGHT]:
            var figure := _lay(pass_name, paint, {})
            var alpha: float = figure["alpha"]
            assert_almost_eq(alpha, float(ALPHAS[pass_name]["base"]), TOLERANCE, "%s in %s lays its alpha" % [pass_name, paint])
            if paint == DARK:
                _assert_colour(figure["texel"], COLOURS[pass_name]["base"], "%s in the dark grey" % pass_name)
            assert_almost_eq(float(figure["g"]), alpha, 0.002, "%s in %s: green shares the alpha" % [pass_name, paint])
            assert_almost_eq(float(figure["b"]), alpha, 0.002, "%s in %s: blue shares the alpha" % [pass_name, paint])


## The second clause: each factor taken away, one at a time, moves the alpha to
## the figure measured, which is what makes a later change to one fail.
func test_each_factor_taken_away_lays_its_measured_alpha() -> void:
    for pass_name: String in PASSES:
        for factor: String in CHANGES:
            var figure := _lay(pass_name, DARK, CHANGES[factor])
            var expected: float = ALPHAS[pass_name][factor]
            _assert_colour(figure["texel"], COLOURS[pass_name][factor], "%s without %s" % [pass_name, factor])
            assert_almost_eq(float(figure["alpha"]), expected, TOLERANCE, "%s without %s" % [pass_name, factor])
            assert_almost_eq(
                float(figure["g"]), float(figure["alpha"]), 0.002, "%s without %s: green shares the alpha" % [pass_name, factor]
            )
            assert_almost_eq(
                float(figure["b"]), float(figure["alpha"]), 0.002, "%s without %s: blue shares the alpha" % [pass_name, factor]
            )


## Whether each brush lays what its settings say. Airbrush builds up, so it
## lays a little over the opacity times the pressure, 0.5 of 0.6. Wash caps at
## that product, 0.35 of 0.5, whatever the flow, and a dash this short reaches
## a little over a third of the cap.
func test_airbrush_builds_past_its_cap_and_wash_stays_under_it() -> void:
    var airbrush := _lay("Airbrush", DARK, {})
    assert_true(float(airbrush["alpha"]) > 0.5 * 0.6, "Airbrush builds up past opacity times pressure")
    var wash := _lay("Wash", DARK, {})
    assert_true(float(wash["alpha"]) < 0.35 * 0.5, "Wash lays under opacity times pressure")
    var wash_flooded := _lay("Wash", DARK, {"flow": 1.0})
    assert_true(float(wash_flooded["alpha"]) <= 0.35 * 0.5 + TOLERANCE, "and at flow 1.0 still within it")


func _assert_colour(texel: Color, expected: Array, what: String) -> void:
    assert_almost_eq(texel.r * 255.0, float(expected[0]), COLOUR_TOLERANCE, "%s: red" % what)
    assert_almost_eq(texel.g * 255.0, float(expected[1]), COLOUR_TOLERANCE, "%s: green" % what)
    assert_almost_eq(texel.b * 255.0, float(expected[2]), COLOUR_TOLERANCE, "%s: blue" % what)


## One dash of *pass_name* in *paint* with the *change* taken away, read at its
## middle: the texel and the alpha it lays.
func _lay(pass_name: String, paint: Color, change: Dictionary) -> Dictionary:
    if _surface != null:
        Fixtures.teardown(_surface, _machine)
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    var brush: Object = _machine.active_tool
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(brush.settings, ShippedPresetsScript)
    assert_true(store.apply_preset(pass_name, brush.settings), "%s loads" % pass_name)
    var ask: Dictionary = PASSES[pass_name]
    var settings: SaStampBrushSettings = brush.settings
    settings.radius = float(ask["radius_px"]) / 256.0
    settings.color = paint
    settings.opacity = float(ask["opacity"])
    var pressure := float(ask["pressure"])
    if change.has("own_opacity"):
        settings.opacity = 1.0 if pass_name == "Airbrush" else 0.7
    if change.has("pressure"):
        pressure = float(change["pressure"])
    if change.has("texture"):
        settings.pattern_name = ""
        settings.texture_option.enabled = false
    if change.has("clock"):
        settings.airbrush_enabled = false
    if change.has("flow"):
        settings.flow = GammaFloat.new(float(change["flow"]), 1.0)
    var document := _surface.easel.document
    document.active_layer.get_or_create_chunk(Vector2i(0, 0)).clear(GROUND)
    var was := SaColors.foreground
    SaColors.foreground = paint
    _dash(brush, float(ask["length"]), pressure)
    SaColors.foreground = was
    return _read(document.active_layer, paint)


func _dash(brush: Object, length: float, pressure: float) -> void:
    var view := _surface.view
    var points: Array[Vector2] = []
    for i in 4:
        points.append(MIDDLE + Vector2(-length * 0.5 + length * float(i) / 3.0, 0.0))
    var pressures: Array[float] = [pressure * 0.75, pressure, pressure, pressure * 0.75]
    view.mouse_position = points[0]
    _motion(brush, points[0], pressures[0], 0)
    brush.tick(FRAME)
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = points[0]
    brush.handle_input(press)
    brush.tick(FRAME)
    for i in range(1, 4):
        _motion(brush, points[i], pressures[i], MOUSE_BUTTON_MASK_LEFT)
        brush.tick(FRAME)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    release.position = points[3]
    brush.handle_input(release)
    var frames := 0
    while brush.is_drawing and frames < 600:
        brush.tick(FRAME)
        frames += 1


func _motion(brush: Object, at: Vector2, pressure: float, mask: int) -> void:
    _surface.view.mouse_position = at
    var motion := InputEventMouseMotion.new()
    motion.position = at
    motion.button_mask = mask
    motion.pressure = pressure
    brush.handle_input(motion)


func _read(layer: SaLayer, paint: Color) -> Dictionary:
    var chunk: SaChunk = layer.chunks[Vector2i(0, 0)]
    var texture := chunk.albedo()
    var format := Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var edge := chunk.pixel_size()
    var image := Image.create_from_data(edge, edge, false, format, bytes)
    var texel := image.get_pixel(int(MIDDLE.x), int(MIDDLE.y))
    var alpha := (GROUND.r - texel.r) / (GROUND.r - paint.r)
    var green := (GROUND.g - texel.g) / (GROUND.g - paint.g)
    var blue := (GROUND.b - texel.b) / (GROUND.b - paint.b)
    return {"texel": texel, "alpha": alpha, "g": green, "b": blue}
