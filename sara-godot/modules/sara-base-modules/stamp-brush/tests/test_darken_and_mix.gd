## Darken and Mix, and the page the five colour options share.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `test_color_dynamics.gd` beside this covers the three offsets. The two amounts
## are here because they are a different kind of reading: an offset is signed and
## read through `_offset_like`, an amount is one-sided and read through
## `_amount_like`, and the case that says so is the one where an option at half
## strength answers half the amount rather than half a shift downwards.
##
## **The Done-when's own clause is the last case.** "Mix at one paints the
## background colour", to the bit rather than to a tolerance: the mix is a
## straight lerp on the channels and a mix of one has to answer the other end of
## it exactly, or the top of the option's range means "nearly the background",
## which is not a range a painter can reach the end of.
##
## Everything here drives `SaDynamics` over a fixed sample rather than painting.
## What a dab does with two numbers is arithmetic, and the stroke they make is
## `scenarios/darken-and-mix-and-the-colour-page.json`.
extends "res://tests/test_framework.gd"

## By path rather than by `class_name`, the way `test_brush_options.gd` reaches
## the same file: the module has none, being loaded through `SaRegistries`.
const ModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")

## The picked colour every case starts from, the same as
## `test_color_dynamics.gd`, so the two files read the same blue and a number in
## one can be compared with a number in the other.
const PICKED := Color(0.25, 0.35, 0.75, 1.0)

## The background Mix blends towards: a warm near-white, chosen so no channel is
## at either end and a partial mix moves all three in a direction a reader can
## check by hand.
const BACKGROUND := Color(0.9, 0.8, 0.6, 1.0)


func _settings() -> SaStampBrushSettings:
    return SaStampBrushSettings.new()


func _sample(pressure: float) -> SaStrokeInfo:
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 4242)
    info.hovering = false
    info.pressure = pressure
    return info


## An option switched on with one sensor under it, which is the shape
## `_modulates` asks for and the only shape that moves a colour.
func _drive(option: SaCurveOption, strength: float, sensor: SaSensor.Id = SaSensor.Id.PRESSURE) -> void:
    option.enabled = true
    option.strength = strength
    option.set_sensor(SaSensor.create(sensor, true))


# --- The two readings ---------------------------------------------------------


## A fresh brush darkens nothing and mixes nothing, which is what keeps every
## texel a preset painted before this unit exactly where it was.
func test_a_fresh_settings_resource_darkens_and_mixes_nothing() -> void:
    var dynamics := SaDynamics.new(_settings())
    var dab := dynamics.evaluate(_sample(0.8), 40.0)

    assert_almost_eq(dab.darken, 0.0, 1e-9, "A fresh brush darkens nothing")
    assert_almost_eq(dab.mix, 0.0, 1e-9, "and mixes nothing")
    assert_eq(SaColorDynamics.apply(PICKED, dab, BACKGROUND), PICKED, "so the picked colour comes back exactly, not nearly")


## An option that is on with nothing under it is a constant, and a constant
## amount here is a stroke painted one shade darker from end to end rather than
## a stroke that varies. The rule for rotation, applied to both.
func test_an_option_with_no_sensor_moves_nothing() -> void:
    var settings := _settings()
    settings.darken_option.enabled = true
    settings.darken_option.strength = 1.0
    settings.mix_option.enabled = true
    settings.mix_option.strength = 1.0
    var dab := SaDynamics.new(settings).evaluate(_sample(1.0), 40.0)

    assert_almost_eq(dab.darken, 0.0, 1e-9, "Darken on with no sensor is not a modulation")
    assert_almost_eq(dab.mix, 0.0, 1e-9, "and neither is Mix")


## The reading is the sensor's own, on 0 to 1, and not moved onto -1 to 1 the way
## an offset is. This is the case that separates `_amount_like` from
## `_offset_like`: at half pressure an offset reads nought and an amount reads a
## half.
func test_an_amount_reads_the_sensor_straight_and_not_as_an_offset() -> void:
    var settings := _settings()
    _drive(settings.darken_option, 1.0)
    _drive(settings.value_option, 1.0)
    var dynamics := SaDynamics.new(settings)

    var half := dynamics.evaluate(_sample(0.5), 40.0)
    assert_almost_eq(half.darken, 0.5, 1e-5, "Half pressure is half the darkening")
    assert_almost_eq(half.value_shift, 0.0, 1e-5, "where half pressure is no value offset at all")

    var full := dynamics.evaluate(_sample(1.0), 40.0)
    assert_almost_eq(full.darken, 1.0, 1e-5, "and full pressure is all of it")


## The strength is how much of the amount this brush spends, so half strength is
## half the darkening at every pressure rather than a different curve.
func test_the_strength_scales_the_amount() -> void:
    var settings := _settings()
    _drive(settings.mix_option, 0.4)
    var dynamics := SaDynamics.new(settings)

    assert_almost_eq(dynamics.evaluate(_sample(1.0), 40.0).mix, 0.4, 1e-5, "Strength 0.4 at full pressure")
    assert_almost_eq(dynamics.evaluate(_sample(0.5), 40.0).mix, 0.2, 1e-5, "and half of that at half pressure")


# --- What the two amounts do to a colour --------------------------------------


## Darken is a multiply on the channels, Krita's own arithmetic, so a darken of
## one is black and a half is half of every channel.
func test_darken_multiplies_the_channels_towards_black() -> void:
    var dab := SaDabParams.new()
    dab.darken = 0.5
    var half := SaColorDynamics.apply(PICKED, dab, BACKGROUND)

    assert_almost_eq(half.r, PICKED.r * 0.5, 1e-6, "Half the red")
    assert_almost_eq(half.g, PICKED.g * 0.5, 1e-6, "half the green")
    assert_almost_eq(half.b, PICKED.b * 0.5, 1e-6, "and half the blue")

    dab.darken = 1.0
    var black := SaColorDynamics.apply(PICKED, dab, BACKGROUND)
    assert_almost_eq(black.r + black.g + black.b, 0.0, 1e-6, "and a darken of one is black")


## Nothing clamps to the display cube, which is hard rule 5. A colour the
## exposure row has already pushed past one darkens from where it is rather than
## from the top of the cube.
func test_darken_leaves_a_colour_above_one_above_one() -> void:
    var dab := SaDabParams.new()
    dab.darken = 0.5
    var bright := SaColorDynamics.apply(Color(3.0, 2.0, 1.0, 1.0), dab, BACKGROUND)

    assert_almost_eq(bright.r, 1.5, 1e-6, "Half of three is still above one")
    assert_almost_eq(bright.g, 1.0, 1e-6, "half of two is one")
    assert_almost_eq(bright.b, 0.5, 1e-6, "and half of one is a half")


## The Done-when's own clause, to the bit: a mix of one paints the background.
func test_mix_at_one_paints_the_background_colour() -> void:
    var dab := SaDabParams.new()
    dab.mix = 1.0
    var mixed := SaColorDynamics.apply(PICKED, dab, BACKGROUND)

    assert_almost_eq(mixed.r, BACKGROUND.r, 1e-6, "The background's red")
    assert_almost_eq(mixed.g, BACKGROUND.g, 1e-6, "its green")
    assert_almost_eq(mixed.b, BACKGROUND.b, 1e-6, "and its blue")


## A mix of a half is halfway between the two colours, channel by channel, which
## is what a blend towards the background has to mean in the middle of its range.
func test_mix_halfway_is_halfway_between_the_pair() -> void:
    var dab := SaDabParams.new()
    dab.mix = 0.5
    var mixed := SaColorDynamics.apply(PICKED, dab, BACKGROUND)

    assert_almost_eq(mixed.r, (PICKED.r + BACKGROUND.r) * 0.5, 1e-6, "Halfway in red")
    assert_almost_eq(mixed.g, (PICKED.g + BACKGROUND.g) * 0.5, 1e-6, "in green")
    assert_almost_eq(mixed.b, (PICKED.b + BACKGROUND.b) * 0.5, 1e-6, "and in blue")


## Darken then mix, and not the other way round. A full mix beside a full darken
## still paints the background, because the darkening happens to the painting
## colour and not to the pair.
func test_the_order_leaves_the_background_reachable_under_any_darken() -> void:
    var dab := SaDabParams.new()
    dab.darken = 1.0
    dab.mix = 1.0
    var mixed := SaColorDynamics.apply(PICKED, dab, BACKGROUND)

    assert_almost_eq(mixed.r, BACKGROUND.r, 1e-6, "A full mix is the background whatever the darken is")
    assert_almost_eq(mixed.g, BACKGROUND.g, 1e-6, "in green")
    assert_almost_eq(mixed.b, BACKGROUND.b, 1e-6, "and in blue")


## Coverage is the opacity option's answer one step earlier, so a mix towards a
## transparent background is a mix of colour and not of alpha.
func test_the_mix_leaves_the_dab_s_own_alpha() -> void:
    var dab := SaDabParams.new()
    dab.mix = 1.0
    var mixed := SaColorDynamics.apply(Color(0.25, 0.35, 0.75, 0.4), dab, Color(0.9, 0.8, 0.6, 0.0))

    assert_almost_eq(mixed.a, 0.4, 1e-6, "The dab keeps its own alpha")


## The three offsets happen first and in Oklab, the two amounts after and on the
## channels, so a value offset and a darken on one dab compose rather than one
## overwriting the other.
func test_an_offset_and_an_amount_compose_in_that_order() -> void:
    var lifted := SaDabParams.new()
    lifted.value_shift = 0.2
    var bright := SaColorDynamics.apply(PICKED, lifted, BACKGROUND)

    var both := SaDabParams.new()
    both.value_shift = 0.2
    both.darken = 0.5
    var darkened := SaColorDynamics.apply(PICKED, both, BACKGROUND)

    assert_almost_eq(darkened.r, bright.r * 0.5, 1e-6, "The darken multiplies the lifted colour")
    assert_almost_eq(darkened.g, bright.g * 0.5, 1e-6, "in green")
    assert_almost_eq(darkened.b, bright.b * 0.5, 1e-6, "and in blue")


# --- What the dab and the settings say about themselves ------------------------


## A dump has to carry the two numbers, because a scenario's claim is about a
## stroke and the dab report is what says which dab painted which part of it.
func test_the_dab_report_carries_the_two_amounts() -> void:
    var settings := _settings()
    _drive(settings.darken_option, 1.0)
    _drive(settings.mix_option, 0.5)
    var report := SaDynamics.new(settings).evaluate(_sample(0.6), 40.0).report()

    assert_true(report.has("darken"), "The report names the darken")
    assert_true(report.has("mix"), "and the mix")
    assert_almost_eq(float(report["darken"]), 0.6, 1e-5, "and the darken is the reading")
    assert_almost_eq(float(report["mix"]), 0.3, 1e-5, "and the mix is the reading times its strength")


## Both options are in the settings' own list, which is what the editor builds a
## page from and what a dump reports.
func test_the_two_options_are_in_the_settings_list() -> void:
    var options := _settings().options()

    assert_true(options.has("darken"), "Darken is an option of the brush")
    assert_true(options.has("mix"), "and so is Mix")
    assert_true(options["darken"] is SaCurveOption, "and it is a curve option")
    assert_true(options["mix"] is SaCurveOption, "and so is the other")


## The background is a field on the settings and not a reach into the store, so
## the dab pipeline still asks one resource for everything it paints from.
func test_the_settings_hold_the_background_colour() -> void:
    var settings := _settings()

    assert_eq(settings.background_color, SaColorStore.DEFAULT_BACKGROUND, "A fresh resource holds the pair's default")
    settings.background_color = BACKGROUND
    assert_eq(settings.background_color, BACKGROUND, "and it takes what the module writes onto it")


## No preset carries the background, because the pair is the painter's and not
## the brush's. A stored property would come back on load and paint towards a
## colour the painter cannot see in the picker.
func test_no_preset_stores_the_background_colour() -> void:
    var settings := _settings()
    settings.background_color = BACKGROUND
    var copy: Resource = settings.duplicate(true)

    assert_eq(
        copy.background_color,
        SaColorStore.DEFAULT_BACKGROUND,
        "A duplicate is born on the default, so nothing serialised carries the pair"
    )


# --- The page the five options share ------------------------------------------


## The page declares five curve options and one
## enum row.
func test_the_page_declares_five_curve_options_and_one_enum_row() -> void:
    var specs: Array[SaOptionSpec] = []
    specs.assign(ModuleScript.brush_options())
    var curves: Array[String] = []
    var plain: Array[String] = []
    for spec: SaOptionSpec in specs:
        if spec.page != SaColorPage.PAGE:
            continue
        if spec.kind == SaOptionSpec.Kind.CURVE_OPTION:
            curves.append(spec.label)
        else:
            plain.append("%s:%d" % [spec.label, spec.kind])

    assert_eq(curves, ["Hue", "Saturation", "Value", "Darken", "Mix"] as Array[String], "Five curve options, in order")
    var rows: Array[String] = ["Colour source:%d" % SaOptionSpec.Kind.ENUM, "Gradient:%d" % SaOptionSpec.Kind.CUSTOM]
    assert_eq(plain, rows, "and one enum row above them, with the Gradient row under it")


## The source is not on General. A row that explains five options belongs above
## them rather than a page away, and a row on two pages is two rows.
func test_the_colour_source_is_on_the_page_and_not_on_general() -> void:
    var specs: Array[SaOptionSpec] = []
    specs.assign(ModuleScript.brush_options())
    var found := 0
    for spec: SaOptionSpec in specs:
        if spec.key != &"color_source":
            continue
        found += 1
        assert_eq(spec.page, SaColorPage.PAGE, "The source names the colour page")

    assert_eq(found, 1, "and it is declared once")


## The five name one page, which is what gathers them, and every other curve
## option still names none and is therefore its own page.
func test_only_the_colour_options_name_a_page() -> void:
    var specs: Array[SaOptionSpec] = []
    specs.assign(ModuleScript.brush_options())
    for spec: SaOptionSpec in specs:
        if spec.kind != SaOptionSpec.Kind.CURVE_OPTION:
            continue
        var named := not spec.page.is_empty()
        assert_eq(named, SaColorPage.owns(spec.key), "%s names a page only if it is a colour option" % spec.key)
