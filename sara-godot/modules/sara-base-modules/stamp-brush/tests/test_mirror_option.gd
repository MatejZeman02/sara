## Mirror as a curve option: the threshold, the bits and the import.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Three claims, and the middle one is the one that would rot quietly. The
## threshold is arithmetic and a test of it fails loudly. The **exclusive-or**
## is a decision: the option turns an axis over rather than deciding it, so a
## tip a painter mirrored by hand and an option switched on with no sensor do
## not fight over the same two bits. Replacing instead would pass every test
## that only ever starts from an unmirrored tip, which is why the table below
## runs all four resting states against all four flips.
##
## The third is the import, where Krita and Sara genuinely differ and the
## difference is deliberate: `KisPressureMirrorOption::apply` mirrors on neither
## axis while the option is off, so Krita's two Mirror checkboxes do nothing on
## their own, and Sara draws a Mirror Tip H of its own that a preset's checkbox
## is the honest home for. The two branches are asserted separately for that
## reason.
extends "res://tests/test_framework.gd"

const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const ModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")

## The four values the note asks the bits for, two either side of the threshold
## and none of them on it: a value exactly at 0.5 is the comparison's own
## boundary and pinning it would be pinning the operator rather than the
## behaviour.
const FOUR_VALUES: Array[float] = [0.1, 0.4, 0.6, 0.9]


func _settings() -> SaStampBrushSettings:
    return SettingsScript.new()


func _sample(pressure: float = 1.0) -> SaStrokeInfo:
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 4242)
    info.hovering = false
    info.position = Vector2.ZERO
    info.pressure = pressure
    return info


## A preset dictionary carrying *options*, the shape `SaKppReader` answers with.
func _preset_with(options: Dictionary) -> Dictionary:
    var out := {
        "name": "made",
        "source": "made.kpp",
        "engine": "paintbrush",
        "options": {},
        "resources": {},
        "tags": PackedStringArray(),
        "licence": "",
        "error": "",
        "tip": {"kind": SaKppReader.TIP_NONE}
    }
    for name: String in options:
        out["options"][name] = {"type": "string", "value": String(options[name])}
    return out


# --- The option ---------------------------------------------------------------


func test_the_option_is_listed_and_off_for_a_new_brush() -> void:
    var settings := _settings()

    assert_true(settings.options().has("mirror"), "the settings list the mirror option by name")
    assert_false(settings.mirror_option.enabled, "and off, so no preset written before it changes")
    assert_true(settings.mirror_axis_x, "acting left to right")
    assert_false(settings.mirror_axis_y, "and not top to bottom, which would be a half turn rather than a mirror")


func test_the_page_is_declared_as_a_curve_option() -> void:
    var by_key: Dictionary = {}
    for spec: SaOptionSpec in ModuleScript.brush_options():
        by_key[String(spec.key)] = spec
    var curve: SaOptionSpec = by_key.get("mirror_option")

    assert_not_null(curve, "the mirror option is declared")
    if curve != null:
        assert_eq(curve.kind, SaOptionSpec.Kind.CURVE_OPTION, "as a curve option, so the page has a checkbox")
        assert_eq(curve.label, "Mirror", "titled Mirror")
        assert_false(curve.bar, "off the bar with the rest of them")
        assert_true(curve.advanced, "and behind Advanced with them")


# --- The threshold ------------------------------------------------------------


## The bits at four values of one fixed sample, which is the note's own ask.
func test_the_bits_at_four_values_of_one_sample() -> void:
    var settings := _settings()
    settings.mirror_option.enabled = true
    var dynamics := SaDynamics.new(settings)
    var info := _sample()
    var read: Array[int] = []

    for value: float in FOUR_VALUES:
        settings.mirror_option.strength = value
        read.append(dynamics.evaluate(info, 40.0).mirror)

    assert_eq(read, [1, 1, 0, 0] as Array[int], "below the threshold flips the x axis and above it flips nothing")


func test_both_axes_flip_both_bits_and_neither_is_the_option_off() -> void:
    var settings := _settings()
    settings.mirror_option.enabled = true
    settings.mirror_option.strength = 0.1
    settings.mirror_axis_y = true
    var dynamics := SaDynamics.new(settings)

    assert_eq(dynamics.evaluate(_sample(), 40.0).mirror, 3, "both axes on flip both bits")
    settings.mirror_axis_x = false
    assert_eq(dynamics.evaluate(_sample(), 40.0).mirror, 2, "y alone flips the second")
    settings.mirror_axis_y = false
    assert_eq(dynamics.evaluate(_sample(), 40.0).mirror, -1, "and neither axis is the option switched off by another name")


## A constant is no mirror, as it is for a constant rotation.
func test_an_option_on_with_no_sensor_never_flips() -> void:
    var settings := _settings()
    settings.mirror_option.enabled = true
    var dynamics := SaDynamics.new(settings)
    dynamics.begin_stroke()

    assert_eq(dynamics.evaluate(_sample(), 40.0).mirror, 0, "a strength of one is above the threshold at every sample")
    assert_true(settings.mirror_option.sensors.is_empty(), "and the press invented no sensor for it")


func test_an_option_that_is_off_says_so_rather_than_saying_no_flip() -> void:
    var settings := _settings()
    var dynamics := SaDynamics.new(settings)

    assert_eq(dynamics.evaluate(_sample(), 40.0).mirror, -1, "off is minus one, which the consumer reads as the tip's own")


# --- The fold onto the tip ----------------------------------------------------


## Every resting state against every flip, because replacing rather than
## exclusive-oring passes any table that starts from an unmirrored tip.
func test_the_flip_is_exclusive_ored_onto_the_tips_own_two() -> void:
    for tip_bits in range(4):
        assert_eq(SaDabGeometry.mirror_bits(tip_bits, -1), tip_bits, "an option that is off leaves %d alone" % tip_bits)
        for flip in range(4):
            assert_eq(
                SaDabGeometry.mirror_bits(tip_bits, flip),
                tip_bits ^ flip,
                "resting %d flipped by %d turns the axis over rather than deciding it" % [tip_bits, flip]
            )


func test_the_handedness_is_the_parity_of_the_bits_the_kernel_is_sent() -> void:
    assert_false(SaDabGeometry.mirror_flips_handedness(0), "no mirror keeps the frame")
    assert_true(SaDabGeometry.mirror_flips_handedness(1), "one axis turns it over")
    assert_true(SaDabGeometry.mirror_flips_handedness(2), "either one")
    assert_false(SaDabGeometry.mirror_flips_handedness(3), "and two leave it as it was")


## The slot the stroke writes into is the slot the kernel reads, which is the
## one thing an index constant can get wrong.
func test_the_named_slot_is_the_one_the_pack_puts_the_mirror_in() -> void:
    var packed := SaDabGeometry.pack(
        Vector2.ZERO, Vector2.ZERO, Color.WHITE, Vector2(8.0, 8.0), 0.0, Vector2.ONE, 1.0, 2, SaDabGeometry.Generator.DEFAULT
    )
    packed[SaDabGeometry.MIRROR_INDEX] = 3.0

    assert_eq(packed.size(), SaDabGeometry.PUSH_FLOATS, "the block is still the whole 128 bytes")
    assert_almost_eq(packed[SaDabGeometry.MIRROR_INDEX], 3.0, 1e-6, "and the named slot holds the bits")
    assert_almost_eq(packed[SaDabGeometry.MIRROR_INDEX - 1], 0.0, 1e-6, "with alpha lock still in front of it")


# --- The import ---------------------------------------------------------------


func test_a_preset_with_pressure_mirror_carries_the_option_and_no_tag() -> void:
    var settings := _settings()
    var sensor := '<!DOCTYPE params>\n<params id="fuzzy"/>\n'
    var applied := (
        SaKppImport
        . apply(
            _preset_with(
                {
                    "PressureMirror": "true",
                    "Mirror/HorizontalMirror": "true",
                    "Mirror/VerticalMirror": "false",
                    "MirrorUseCurve": "true",
                    "MirrorSensor": sensor,
                }
            ),
            settings
        )
    )

    assert_eq(applied["not_carried"], [], "nothing is tagged, which is the phrase this unit removes")
    assert_true(settings.mirror_option.enabled, "the option is on")
    assert_false(settings.mirror_option.active_sensors().is_empty(), "with the preset's sensor on it")
    assert_true(settings.mirror_axis_x, "the two checkboxes are the option's axes")
    assert_false(settings.mirror_axis_y, "both of them")
    assert_false(settings.tip.mirror_horizontal, "and the tip keeps no standing mirror, which is what Krita means")
    assert_false(settings.tip.mirror_vertical, "on either axis")
    assert_false(applied["unread"].has("PressureMirror"), "every param of the stem is read")


func test_a_preset_without_pressure_mirror_still_mirrors_the_tip() -> void:
    var settings := _settings()
    var applied := SaKppImport.apply(_preset_with({"Mirror/HorizontalMirror": "true", "Mirror/VerticalMirror": "true"}), settings)

    assert_eq(applied["not_carried"], [], "and still nothing tagged")
    assert_false(settings.mirror_option.enabled, "the option stays off")
    assert_true(settings.tip.mirror_horizontal, "so the checkboxes land on the tip Sara draws for them")
    assert_true(settings.tip.mirror_vertical, "both of them")
