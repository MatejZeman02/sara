## A gradient colour source picks each dab's colour off the preset's ramp.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A gradient colour source joins the plain one. It
## is Krita's `gradient` value of `ColorSource/Type`, where Krita's
## `selectColor(mix)` picks `colorAt(mix)`, so a pressure curve on Mix walks the
## stroke along the gradient.
##
## **The dabs are built the way the brush builds them.** `SaDynamics` turns a
## pressure sample into the dab's Mix, and `SaColorDynamics.apply` is handed the
## source and `gradient_ramp` off the settings, as `state_brush.gd` hands them.
## The last cases paint through the brush itself and read the canvas, so the one
## line the brush changed is under a texel as well as under arithmetic.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice for the cases that paint. The runner skips this suite
## without one.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

const RED := Color(1.0, 0.0, 0.0, 1.0)
const BLUE := Color(0.0, 0.0, 1.0, 1.0)

## The painting colour, which a gradient source does not paint, so a green
## anywhere in a reading says the plain path answered.
const PAINTING := Color(0.1, 0.8, 0.2, 1.0)

## The background, white, so a Mix still blending towards it would lift the
## middle of a red to blue ramp towards pink, which a reading would see.
const BACKGROUND := Color(1.0, 1.0, 1.0, 1.0)

## How far the Value option lifts every dab, in Oklab lightness.
const VALUE := 0.2


func _ramp() -> SaColorRamp:
    return SaColorRamp.from_pair(RED, BLUE)


## A brush on a gradient source over the red to blue ramp, its Mix on
## pressure at full strength.
func _settings() -> SaStampBrushSettings:
    var settings := SaStampBrushSettings.new()
    settings.color = PAINTING
    settings.background_color = BACKGROUND
    settings.color_source = SaColorDynamics.Source.GRADIENT
    settings.gradient = _ramp().to_array()
    _drive(settings.mix_option, 1.0, SaSensor.Id.PRESSURE)
    return settings


func _drive(option: SaCurveOption, strength: float, sensor: SaSensor.Id) -> void:
    option.enabled = true
    option.strength = strength
    option.set_sensor(SaSensor.create(sensor, true))


func _sample(pressure: float) -> SaStrokeInfo:
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 4242)
    info.hovering = false
    info.pressure = pressure
    return info


## The dab *settings* builds at *pressure*, its colour picked the way line 608
## of `state_brush.gd` picks it.
func _paint(settings: SaStampBrushSettings, dab: SaDabParams) -> Color:
    return SaColorDynamics.apply(
        settings.color, dab, settings.background_color, null, settings.color_source, settings.gradient_ramp
    )


func _assert_color(got: Color, want: Color, tolerance: float, message: String) -> void:
    assert_almost_eq(got.r, want.r, tolerance, "%s, red" % message)
    assert_almost_eq(got.g, want.g, tolerance, "%s, green" % message)
    assert_almost_eq(got.b, want.b, tolerance, "%s, blue" % message)


func _lightness(color: Color) -> float:
    var curve := SaTransferFunction.srgb()
    return SaOklab.from_linear_srgb(Vector3(curve.decode(color.r), curve.decode(color.g), curve.decode(color.b))).x


# --- The pick -----------------------------------------------------------------


## The Done-when's first clause: Mix at nought, a half and one over a red to
## blue ramp reads red, the ramp's middle and blue. The middle is the ramp's
## own, its Oklab middle, and not the channels' halfway purple, nor the pink a
## blend towards the white background would make of it.
func test_mix_at_nought_a_half_and_one_reads_red_the_middle_and_blue() -> void:
    var settings := _settings()
    var dynamics := SaDynamics.new(settings)
    var middle := _ramp().display_at(0.5)

    var low := dynamics.evaluate(_sample(0.0), 40.0)
    var half := dynamics.evaluate(_sample(0.5), 40.0)
    var full := dynamics.evaluate(_sample(1.0), 40.0)
    assert_almost_eq(low.mix, 0.0, 1e-5, "No pressure is a Mix of nought")
    assert_almost_eq(half.mix, 0.5, 1e-5, "half pressure a half")
    assert_almost_eq(full.mix, 1.0, 1e-5, "and full pressure one")

    _assert_color(_paint(settings, low), RED, 1e-5, "A Mix of nought takes the ramp's start")
    _assert_color(_paint(settings, half), middle, 1e-5, "a half its middle")
    _assert_color(_paint(settings, full), BLUE, 1e-5, "and one its end")
    var straight := RED.lerp(BLUE, 0.5)
    assert_true(absf(middle.r - straight.r) + absf(middle.b - straight.b) > 0.05, "The middle is Oklab's and not the channels'")
    var pink := middle.lerp(BACKGROUND, 0.5)
    assert_true(absf(_paint(settings, half).g - pink.g) > 0.1, "and not blended half way to the white background")


## Mix is spent on the position, so it blends towards the background no longer.
## The end of the ramp is blue under a white background, where a plain source
## at the same Mix paints the background itself.
func test_the_mix_no_longer_blends_towards_the_background() -> void:
    var settings := _settings()
    var full := SaDynamics.new(settings).evaluate(_sample(1.0), 40.0)

    _assert_color(_paint(settings, full), BLUE, 1e-5, "A gradient source at a full Mix paints the ramp's end")
    settings.color_source = SaColorDynamics.Source.PLAIN
    assert_eq(_paint(settings, full), BACKGROUND, "where a plain one at the same Mix paints the background")


## A Mix switched off reads nought, so a brush put on Gradient without touching
## Mix paints the ramp's start rather than its painting colour.
func test_a_mix_switched_off_paints_the_ramp_s_start() -> void:
    var settings := _settings()
    settings.mix_option.enabled = false

    _assert_color(_paint(settings, SaDynamics.new(settings).evaluate(_sample(1.0), 40.0)), RED, 1e-5, "The start")


## The Done-when's second half: a Value option on top moves each of the three
## as it moves a plain colour. The plain colour is the ramp's own pick at the
## same Mix, handed in plain with no Mix, so the two calls differ in the source
## alone, and they agree to the float.
func test_a_value_option_moves_each_as_it_moves_a_plain_colour() -> void:
    var settings := _settings()
    _drive(settings.value_option, VALUE, SaSensor.Id.TILT_X)
    var dynamics := SaDynamics.new(settings)
    for pressure: float in [0.0, 0.5, 1.0]:
        var dab := dynamics.evaluate(_sample(pressure), 40.0)
        assert_almost_eq(dab.value_shift, VALUE, 1e-5, "An upright pen reads the whole Value at %.1f" % pressure)
        var picked := SaColorDynamics.ramp_at(_ramp(), dab.mix)
        var plain := SaDabParams.new()
        plain.value_shift = dab.value_shift

        var moved := _paint(settings, dab)
        _assert_color(
            moved, SaColorDynamics.apply(picked, plain), 1e-6, "Value moves the pick at %.1f as a plain colour" % pressure
        )
        var lift := _lightness(moved) - _lightness(picked)
        assert_almost_eq(lift, VALUE, 1e-4, "by the Value's own lightness at %.1f" % pressure)


## Hue, Saturation and Darken follow the same way: the gradient answers a
## colour, and the options downstream of the source never learn which source
## it was.
func test_hue_saturation_and_darken_move_the_pick_as_a_plain_colour() -> void:
    var settings := _settings()
    var dab := SaDynamics.new(settings).evaluate(_sample(0.5), 40.0)
    dab.hue_shift = 0.1
    dab.saturation_shift = -0.2
    dab.darken = 0.3
    var plain := SaDabParams.new()
    plain.hue_shift = dab.hue_shift
    plain.saturation_shift = dab.saturation_shift
    plain.darken = dab.darken

    var want := SaColorDynamics.apply(SaColorDynamics.ramp_at(_ramp(), 0.5), plain, BACKGROUND)
    _assert_color(_paint(settings, dab), want, 1e-6, "The three move the middle as they move a plain colour")


## A preset whose gradient field is empty walks the painting colour to the
## background, the field's default, and the pick follows the pair.
func test_an_empty_gradient_walks_the_painting_colour_to_the_background() -> void:
    var settings := _settings()
    settings.gradient = []
    var dynamics := SaDynamics.new(settings)

    _assert_color(_paint(settings, dynamics.evaluate(_sample(0.0), 40.0)), PAINTING, 1e-5, "Nought is the painting colour")
    _assert_color(_paint(settings, dynamics.evaluate(_sample(1.0), 40.0)), BACKGROUND, 1e-5, "and one the background")


## A plain source never asks for the ramp, so a plain brush builds no ramp per
## dab, and the colour it answers is the one it answered before this row.
func test_a_plain_source_never_asks_for_the_ramp() -> void:
    var asked: Array[int] = [0]
    var ramp := func() -> SaColorRamp:
        asked[0] += 1
        return _ramp()
    var dab := SaDabParams.new()
    dab.mix = 0.5

    var plain := SaColorDynamics.apply(PAINTING, dab, BACKGROUND, null, SaColorDynamics.Source.PLAIN, ramp)
    assert_eq(asked[0], 0, "A plain source never builds the ramp")
    assert_eq(plain, SaColorDynamics.apply(PAINTING, dab, BACKGROUND), "and paints what it painted with no source named")
    SaColorDynamics.apply(PAINTING, dab, BACKGROUND, null, SaColorDynamics.Source.GRADIENT, ramp)
    assert_eq(asked[0], 1, "where a gradient source asks once a dab")


## The ramp's stops are picked colours, so they name the document's gamut, as
## Gradient Map reads them. A Display P3 document's ramp from P3's red starts at
## the triple 1, 0, 0, which the brush then carries through P3's own matrix.
func test_a_wide_gamut_ramp_starts_at_its_own_red() -> void:
    var space := SaColorSpace.display_p3()
    var start := SaColorDynamics.ramp_at(_ramp(), 0.0, space)

    _assert_color(start, RED, 1e-5, "P3's red comes back as the triple it was picked as")
    var srgb_middle := SaColorDynamics.ramp_at(_ramp(), 0.5)
    var p3_middle := SaColorDynamics.ramp_at(_ramp(), 0.5, space)
    assert_true(absf(srgb_middle.r - p3_middle.r) + absf(srgb_middle.b - p3_middle.b) > 1e-3, "and its middle is walked in P3")


## The source names itself for a dump, and the Colour page lists it.
func test_the_source_names_itself_and_the_colour_page_lists_it() -> void:
    assert_eq(SaColorDynamics.source_name(SaColorDynamics.Source.GRADIENT), "gradient", "Gradient names itself")
    assert_eq(SaColorDynamics.Source.PLAIN, 0, "and Plain stays the stored 0, so no preset changes source")
    var row: SaOptionSpec = null
    for spec: SaOptionSpec in SaColorPage.rows():
        if spec.key == &"color_source":
            row = spec
    assert_not_null(row, "The Colour page has its source row")
    if row != null:
        var listed := {}
        for choice: Dictionary in row.choices:
            listed[choice["id"]] = choice["label"]
        assert_eq(listed.get(SaColorDynamics.Source.GRADIENT, ""), "Gradient", "which lists Gradient under its name")
        assert_eq(listed.get(SaColorDynamics.Source.PLAIN, ""), "Plain", "after Plain")


# --- Through the brush --------------------------------------------------------


## A brush on the gradient source over a hard, full-flow tip, stamping one dab
## at *pressure* at the middle of a fresh 256 square, and the centre texel.
func _stamp(pressure: float) -> Dictionary:
    var surface := Fixtures.make_surface()
    var brush := StateBrushScript.new()
    brush.surface = surface
    var settings: SaStampBrushSettings = brush.settings
    settings.color = PAINTING
    settings.background_color = BACKGROUND
    settings.color_source = SaColorDynamics.Source.GRADIENT
    settings.gradient = _ramp().to_array()
    _drive(settings.mix_option, 1.0, SaSensor.Id.PRESSURE)
    settings.radius = 20.0 / surface.get_canvas_size().x
    settings.hardness = GammaFloat.new(1.0, 1.0)
    settings.opacity_by_pressure = false
    # What a stroke's start does, without the document's stroke it opens: the
    # evaluator reads no options until it is handed the settings.
    brush.dynamics.settings = settings
    brush.dynamics.begin_stroke()
    brush.stroke_info.begin(Vector2(128.0, 128.0), 4242)

    brush._stamp_brush(Vector2(128.0, 128.0), pressure)

    var out := {"mix": brush.last_dab.mix if brush.last_dab != null else -1.0, "texel": Color(0, 0, 0, 0)}
    var space: SaColorSpace = surface.get_document().color_space
    out["want"] = space.from_display(SaColorDynamics.ramp_at(_ramp(), float(out["mix"]), space))
    var chunk: SaTexture = surface.get_document().stroke_layer.get_field(Vector2i(0, 0))
    if chunk != null:
        var data := GlobalShaderCompiler.get_rd().texture_get_data(chunk.rid, 0).to_float32_array()
        var at := (128 * 256 + 128) * 4
        out["texel"] = Color(data[at], data[at + 1], data[at + 2], data[at + 3])
    surface.get_document().free()
    surface.easel.free()
    return out


## The scenario's stroke in two dabs: full pressure paints the ramp's end and
## half pressure what the ramp holds at the dab's Mix, on the canvas.
func test_the_brush_paints_each_dab_off_the_ramp() -> void:
    var full := _stamp(1.0)
    assert_almost_eq(float(full["mix"]), 1.0, 1e-3, "A full pressure dab reads a Mix of one")
    var texel: Color = full["texel"]
    assert_true(texel.a > 0.99, "and paints opaque at its centre")
    _assert_color(texel, BLUE, 1e-3, "in the ramp's blue rather than the painting colour")

    var half := _stamp(0.5)
    var middle: Color = half["texel"]
    assert_true(middle.a > 0.0, "A half pressure dab paints")
    if middle.a > 0.0:
        var straight := Color(middle.r / middle.a, middle.g / middle.a, middle.b / middle.a)
        _assert_color(straight, half["want"], 2e-3, "what the ramp holds at its Mix of %.3f" % float(half["mix"]))
