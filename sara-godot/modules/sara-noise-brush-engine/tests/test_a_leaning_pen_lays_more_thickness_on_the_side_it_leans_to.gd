## A leaning pen lays more thickness on the side it leans to.
## the Tilt Thickness row ramps the height across a dab along the pen's lean,
## more on the edge the pen leans to and less on the opposite one, in a
## straight line, the difference growing as the pen lays down and nought for
## an upright pen.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Every dab here is a tap over a flat height: the field's lightness held at a
## half by a relief of nought, Thickness with its sensors off, a press below
## the pile's threshold so no edge piles, and a shift low enough that every
## texel the tip reaches takes paint. The tip is round and the stretch off, so
## the tip reaches [constant RADIUS] pixels every way and the ramp is read
## against that, except in the one case that reads it against the stretched
## tip. The height is read off the surface the view sums, so it is what the
## kernel wrote, a little inside the tip's rim on both sides of the centre,
## where the tip still covers fully.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")

const RADIUS := 14.0
const CENTRE := Vector2i(128, 128)
## How far either side of the centre the height is read, in pixels, two
## inside the rim.
const EDGE := 12
## The brush's height at full lightness, and with the field flat at a half.
const THICKNESS := 1.0
const FLAT_HEIGHT := 0.5
## A press below the pile's threshold of 0.7.
const PRESSURE := 0.5
## Two leans in degrees, one along x and one along y, each 30 degrees off
## upright on its axis, an elevation of two thirds. And a pen laid flat.
const LEAN_X := Vector2(30.0, 0.0)
const LEAN_Y := Vector2(0.0, 30.0)
const FLAT_X := Vector2(60.0, 0.0)
## How near a read height must come to the one worked out, in virtual
## millimetres, a little over the half float the view sums in.
const NEAR := 0.006

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null


func before_each() -> void:
    _fresh()


func after_each() -> void:
    _brush = null
    Fixtures.teardown(_surface)
    _surface = null


## A fresh preset lays every texel of a dab at one height, so the shipped
## presets keep their look, and the row's option reads the elevation along a
## falling line, nought upright and one laid flat, on a curve page of its own.
func test_a_fresh_preset_leans_nothing_and_reads_the_elevation() -> void:
    var fresh := NoiseBrushSettingsScript.new()
    assert_almost_eq(fresh.thickness_lean, 0.0, 0.0, "Tilt Thickness starts at nought")
    var option: SaCurveOption = fresh.thickness_lean_option
    assert_true(option.enabled, "Its option is on")
    var ids: Array = []
    for sensor: SaSensor in option.sensors.values():
        if sensor.active:
            ids.append(sensor.id)
    assert_eq(ids, [SaSensor.Id.TILT_ELEVATION], "and reads the elevation alone")
    assert_true(fresh.options().has("thickness_lean"), "which the door's dynamics prepares at the press")
    var labels := {}
    var row_page := ""
    for spec: SaOptionSpec in NoiseModuleScript.options():
        if spec.kind == SaOptionSpec.Kind.CURVE_OPTION:
            labels[spec.key] = spec.label
        if spec.key == NoiseModuleScript.THICKNESS_LEAN_KEY:
            row_page = spec.page
            assert_almost_eq(spec.min_value, -1.0, 0.0, "The row reaches minus one, the other edge the heavier")
            assert_almost_eq(spec.max_value, 1.0, 0.0, "and one")
    assert_eq(row_page, NoiseModuleScript.PAGE, "The row is on the brush's own page")
    assert_eq(labels.get(NoiseModuleScript.THICKNESS_LEAN_OPTION, ""), "Tilt Thickness", "and its option on a curve page")


## The state hands the kernel the unit vector along the lean times the row
## times the option's answer, the other way for a row below nought, and
## nothing for an upright pen.
func test_the_point_carries_the_lean_times_its_share() -> void:
    _brush.settings.thickness_lean = 0.8
    var info := SaStrokeInfo.new()
    info.tilt_x = LEAN_Y.x
    info.tilt_y = LEAN_Y.y
    var share := 0.8 * (1.0 - SaSensor.tilt_elevation(LEAN_Y.x, LEAN_Y.y))
    var lean: Vector2 = _brush.lean_for(info)
    assert_almost_eq(lean.x, 0.0, 0.0001, "A lean along y has nothing along x")
    assert_almost_eq(lean.y, share, 0.001, "and the row's share of the elevation's falling line along y, %.4f" % share)
    _brush.settings.thickness_lean = -0.8
    assert_almost_eq(_brush.lean_for(info).y, -share, 0.001, "Below nought it points the other way")
    info.tilt_x = 0.0
    info.tilt_y = 0.0
    assert_eq(_brush.lean_for(info), Vector2.ZERO, "and an upright pen has none")


## The Done when's suite: a dab with the pen leaning along x at an elevation of
## two thirds, the row at one, lays the edge it leans to higher by the row's
## share of the falling line and the opposite edge lower by as much, in a
## straight line through the middle, which stands where it stood with the row
## at nought. Nothing ramps across the lean.
func test_a_leaning_dab_lays_more_on_the_side_it_leans_to() -> void:
    _brush.settings.thickness_lean = 0.0
    _tap(LEAN_X)
    var even := _heights_along(Vector2i(1, 0))
    _fresh()
    _brush.settings.thickness_lean = 1.0
    _tap(LEAN_X)
    var ramp := _heights_along(Vector2i(1, 0))
    var share := 1.0 - SaSensor.tilt_elevation(LEAN_X.x, LEAN_X.y)
    var rise := FLAT_HEIGHT * share * EDGE / RADIUS
    assert_almost_eq(even.x, FLAT_HEIGHT, NEAR, "With the row at nought the edge behind the lean stands at the flat height")
    assert_almost_eq(even.z, FLAT_HEIGHT, NEAR, "and so does the edge it leans to, %s" % even)
    assert_almost_eq(ramp.y, even.y, NEAR, "The middle stands where it stood, %.4f" % even.y)
    assert_almost_eq(ramp.z, FLAT_HEIGHT + rise, NEAR, "The edge the pen leans to stands higher by %.4f, read %s" % [rise, ramp])
    assert_almost_eq(ramp.x, FLAT_HEIGHT - rise, NEAR, "and the opposite edge lower by as much")
    var across := _heights_along(Vector2i(0, 1))
    assert_almost_eq(across.x, across.z, NEAR, "Across the lean both edges stand alike, %s" % across)


## The difference grows as the pen lays down: a pen laid flat ramps the dab by
## the row's whole amount, a third more than the lean of two thirds' elevation
## ramps by its share of a third.
func test_the_difference_grows_as_the_pen_lays_down() -> void:
    _brush.settings.thickness_lean = 0.6
    _tap(FLAT_X)
    var flat := _heights_along(Vector2i(1, 0))
    var rise := FLAT_HEIGHT * 0.6 * EDGE / RADIUS
    assert_almost_eq(
        flat.z, FLAT_HEIGHT + rise, NEAR, "Laid flat the edge it leans to stands higher by the row's whole share, %s" % flat
    )
    assert_almost_eq(flat.x, FLAT_HEIGHT - rise, NEAR, "and the opposite edge lower by it")
    _fresh()
    _brush.settings.thickness_lean = 0.6
    _tap(LEAN_X)
    var steeper := _heights_along(Vector2i(1, 0))
    assert_true(
        flat.z - flat.x > (steeper.z - steeper.x) * 1.5,
        "Laid flat it ramps further than at two thirds upright, %s against %s" % [flat, steeper]
    )


## An upright pen lays an even dab whatever the row says.
func test_an_upright_pen_lays_an_even_dab() -> void:
    _brush.settings.thickness_lean = 1.0
    _tap(Vector2.ZERO)
    var along := _heights_along(Vector2i(1, 0))
    var across := _heights_along(Vector2i(0, 1))
    for height: float in [along.x, along.y, along.z, across.x, across.z]:
        assert_almost_eq(height, FLAT_HEIGHT, NEAR, "Every texel stands at the flat height, %s and %s" % [along, across])


## A lean along y ramps the dab along y, and a row below nought puts the
## heavier edge on the other side.
func test_the_ramp_follows_the_lean_and_turns_round_below_nought() -> void:
    _brush.settings.thickness_lean = 1.0
    _tap(LEAN_Y)
    var down := _heights_along(Vector2i(0, 1))
    var across := _heights_along(Vector2i(1, 0))
    assert_true(down.z > down.y + 0.05 and down.y > down.x + 0.05, "A lean down the canvas lays more lower down, %s" % down)
    assert_almost_eq(across.x, across.z, NEAR, "and nothing across it, %s" % across)
    _fresh()
    _brush.settings.thickness_lean = -1.0
    _tap(LEAN_Y)
    var turned := _heights_along(Vector2i(0, 1))
    assert_almost_eq(
        turned.x, down.z, NEAR, "Below nought the edge behind the lean stands where the leaning edge stood, %s" % turned
    )
    assert_almost_eq(turned.z, down.x, NEAR, "and the leaning edge where it stood")


## With the stretch on the tip grows along the lean, and the ramp spans the
## stretched tip, so the same pixels out stand nearer the middle's height.
func test_the_ramp_spans_the_stretched_tip() -> void:
    _brush.settings.stretch_option.enabled = true
    _brush.settings.thickness_lean = 1.0
    _tap(LEAN_X)
    var ramp := _heights_along(Vector2i(1, 0))
    var share := 1.0 - SaSensor.tilt_elevation(LEAN_X.x, LEAN_X.y)
    var reach := RADIUS * (1.0 + share * NoiseBrushSettingsScript.TILT_STRETCH)
    var rise := FLAT_HEIGHT * share * EDGE / reach
    assert_almost_eq(
        ramp.z,
        FLAT_HEIGHT + rise,
        NEAR,
        "The edge it leans to stands higher by %.4f over a tip %.2f pixels long, %s" % [rise, reach, ramp]
    )
    assert_almost_eq(ramp.x, FLAT_HEIGHT - rise, NEAR, "and the opposite edge lower by as much")


## A brush on a fresh document whose own height is the flat height wherever
## it covers, with the stretch off so the tip stays round.
func _fresh() -> void:
    if _surface != null:
        Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface()
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = 7
    _brush.settings.color = Color(0.2, 0.4, 0.8, 1.0)
    _brush.settings.opacity = 1.0
    _brush.settings.hardness = 1.0
    _brush.settings.strength = -1.0
    _brush.settings.strength_option.enabled = false
    _brush.settings.radius = RADIUS / 256.0
    _brush.settings.texture_field = "grain"
    _brush.settings.texture_channels = 2
    _brush.settings.texture_relief = 0.0
    _brush.settings.thickness = THICKNESS
    _brush.settings.thickness_option.enabled = false
    _brush.settings.stretch_option.enabled = false


## One tap at the centre, the pen leaning *tilt* degrees.
func _tap(tilt: Vector2) -> void:
    _brush.begin_stroke(Vector2(CENTRE), PRESSURE, tilt)
    _brush.end_stroke()


## The surface the view sums at [constant EDGE] pixels behind the centre along
## *axis*, at the centre and as far in front, as x, y and z.
func _heights_along(axis: Vector2i) -> Vector3:
    var easel := _surface.easel
    easel.request_full_composite()
    easel.process_pending_composite()
    var heights := easel.relief.heights
    if heights == null:
        return Vector3.ZERO
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(heights.rid, 0)
    var read := func(at: Vector2i) -> float: return bytes.decode_half((at.y * heights.size.x + at.x) * 2)
    return Vector3(read.call(CENTRE - axis * EDGE), read.call(CENTRE), read.call(CENTRE + axis * EDGE))
