## The roll-off's Knee goes above 1.0, and the two halves of
## every colour picture touch as mirror images.
##
## The tonemapper Knee may go above 1 and opens at 1, and every colour picture
## shows its two halves mirrored so they touch and the difference is clear.
## This reads both
## knees, the view's and the Tonemap filter's, kept above 1.0 and opening at
## 1.0, the operator unmoved at 1.0 and under, a colour between white and a
## higher knee keeping its chroma, and both pairs built touching and mirrored.
##
## No GPU. The operator is read through `SaCurvePlot.rolled`, the transcription
## `test_the_rolloff_leaves_every_colour_the_display_can_show_alone` holds to
## the view and the export colour by colour.
extends "res://tests/test_framework.gd"

const OWNER: StringName = &"sara-base-modules"

## A knee above 1.0 and inside the top, 4.0.
const HIGH_KNEE := 2.5

## The knees at and under 1.0 whose colours must not move.
const KNEES_TODAY: Array[float] = [0.05, 0.35, 0.5, 0.76, 0.99, 1.0]

## Stored channel values the colours are built from, every combination of
## three, below black and well past white among them.
const CHANNELS: Array[float] = [-0.1, 0.0, 0.3, 0.7, 1.0, 1.2, 2.0, 3.0]

## The md5 of every colour `SaCurvePlot.rolled` gave for `KNEES_TODAY` and
## `CHANNELS` at a desaturation of 0.15, each channel rounded to 1e-4, measured
## at the integration tip `c5328a644` before the knee could pass 1.0.
const TODAY_MD5 := "1882c01d0729d8457773cf25f6d3ebab"

var _filter: SaTonemapFilter = null
var _registry: SaFilterRegistry = null
var _host: VBoxContainer = null
var _dialog: SaDialog = null
var _knee_before := 1.0


func before_each() -> void:
    _knee_before = SaSettings.tonemap_knee
    _registry = SaFilterRegistry.new()
    _filter = SaTonemapFilter.new()
    _registry.register(_filter, OWNER)
    _host = VBoxContainer.new()
    _dialog = SaDialog.for_filter(_filter)
    _dialog.realize(_host)


func after_each() -> void:
    SaSettings.tonemap_knee = _knee_before
    if _host != null:
        _host.free()
        _host = null
    _dialog = null
    _filter = null
    _registry = null


## Every colour the operator gives at *knees*, one line each.
func _table(knees: Array[float]) -> String:
    var lines := PackedStringArray()
    for knee: float in knees:
        for r: float in CHANNELS:
            for g: float in CHANNELS:
                for b: float in CHANNELS:
                    var shown := SaCurvePlot.rolled(Color(r, g, b), knee, 0.15)
                    lines.append("%.4f %.4f %.4f" % [shown.r, shown.g, shown.b])
    return "\n".join(lines)


func test_a_fresh_settings_store_and_a_fresh_dialog_hold_1_0() -> void:
    var fresh := SaSettingsValues.new()
    assert_eq(fresh.tonemap_knee, 1.0, "A fresh settings store holds a knee of 1.0")
    fresh.free()
    assert_eq(float(_dialog.row(&"knee").read()), 1.0, "and a fresh Tonemap dialog does")
    assert_eq(float(SaTonemapFilter.DEFAULTS["knee"]), 1.0, "from the filter's own defaults")


func test_the_views_knee_is_kept_above_1_0() -> void:
    var values := SaSettingsValues.new()
    values.tonemap_knee = HIGH_KNEE
    assert_eq(values.tonemap_knee, HIGH_KNEE, "The view's knee keeps %s" % HIGH_KNEE)
    values.tonemap_knee = 9.0
    assert_eq(values.tonemap_knee, SaSettingsValues.TONEMAP_KNEE_TOP, "and stops at its top")
    values.tonemap_knee = 1.0
    assert_eq(values.tonemap_knee, 1.0, "and a typed 1.0 is 1.0")
    values.free()


func test_the_display_pages_knee_slider_reaches_above_1_0_and_1_0_exactly() -> void:
    var display := SaDisplayPage.new()
    var knee := display.page.row(&"knee")
    assert_not_null(knee, "Display carries the Knee row")
    if knee == null:
        display.free()
        return
    assert_eq(knee.max_value, SaSettingsValues.TONEMAP_KNEE_TOP, "Its slider reaches the top")
    knee.write(HIGH_KNEE)
    assert_eq(SaSettings.tonemap_knee, HIGH_KNEE, "a written knee above 1.0 is the view's")
    knee.write(1.0)
    assert_eq(SaSettings.tonemap_knee, 1.0, "and a typed 1.0 lands on 1.0")
    assert_not_null(knee.control, "The row has its slider")
    knee.drive(1.37)
    assert_almost_eq(SaSettings.tonemap_knee, 1.37, 1e-9, "A drag above 1.0 is the view's knee")
    knee.drive(1.0)
    assert_eq(SaSettings.tonemap_knee, 1.0, "and a drag back lands on 1.0")
    display.free()


func test_the_filters_knee_is_kept_above_1_0_and_a_drag_lands_on_1_0() -> void:
    var row := _dialog.row(&"knee")
    assert_eq(row.max_value, SaTonemapFilter.KNEE_TOP, "The dialog's Knee reaches the filter's top")
    assert_true(SaTonemapFilter.KNEE_TOP > 1.0, "which is above 1.0")
    row.write(HIGH_KNEE)
    assert_eq(float(row.read()), HIGH_KNEE, "A written knee above 1.0 is kept")
    assert_eq(float(_dialog.describe()["rolloff"]["knee"]), HIGH_KNEE, "and the curve is drawn at it")
    row.drive(1.37)
    row.drive(1.0)
    assert_eq(float(row.read()), 1.0, "A drag back lands on 1.0, not a hair off it")


func test_the_operator_at_1_0_and_under_gives_todays_colours() -> void:
    assert_eq(_table(KNEES_TODAY).md5_text(), TODAY_MD5, "Every colour at a knee of 1.0 and under is as it was")


func test_a_colour_between_white_and_a_higher_knee_keeps_more_chroma() -> void:
    for stored: Color in [Color(1.2, 0.2, 0.1), Color(0.1, 1.3, 0.4), Color(0.2, 0.3, 1.25)]:
        assert_true(maxf(stored.r, maxf(stored.g, stored.b)) < HIGH_KNEE, "%s stands under the high knee" % stored)
        var at_one := _chroma(SaCurvePlot.rolled(stored, 1.0, 0.15))
        var at_high := _chroma(SaCurvePlot.rolled(stored, HIGH_KNEE, 0.15))
        assert_true(at_high > at_one + 0.01, "%s keeps chroma %.4f at %s over %.4f at 1.0" % [stored, at_high, HIGH_KNEE, at_one])


func test_a_colour_under_a_higher_knee_still_lands_under_white() -> void:
    var shown := SaCurvePlot.rolled(Color(1.6, 0.3, 0.2), HIGH_KNEE, 0.15)
    assert_true(maxf(shown.r, maxf(shown.g, shown.b)) <= 1.0 + 1e-4, "Its peak is brought to white, %s" % shown)
    assert_almost_eq(SaCurvePlot.displayed_for_stored(1.5, HIGH_KNEE), 1.0, 1e-6, "and the magnitude line is flat at white")


func test_both_pairs_touch_with_the_plain_half_mirrored() -> void:
    var display := SaDisplayPage.new()
    var pairs: Array[HBoxContainer] = [display._gamut.get_parent() as HBoxContainer, _dialog._rolloff.pair]
    for pair: HBoxContainer in pairs:
        assert_not_null(pair, "The pair is a row of two")
        assert_eq(pair.get_child_count(), 2, "of two halves")
        assert_eq(pair.get_theme_constant("separation"), 0, "touching, with no gap")
        var operated := pair.get_child(0) as SaGamutPreview
        var plain := pair.get_child(1) as SaGamutPreview
        assert_false(operated.flip_h, "the operated half the way round it was baked")
        assert_true(plain.flip_h, "and the plain half mirrored left to right")
    assert_true(display._gamut_plain == display._gamut.get_parent().get_child(1), "On Display the plain half is the mirrored one")
    display.free()


func _chroma(shown: Color) -> float:
    var lab := SaOklab.from_linear_srgb(OkhsvConversions.srgb_transfer_function_inv(Vector3(shown.r, shown.g, shown.b)))
    return Vector2(lab.y, lab.z).length()
