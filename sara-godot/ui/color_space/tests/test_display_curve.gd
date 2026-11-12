## The Display page's roll-off graph, against the shader it claims to draw.
##
## The picture is a transcription of `highlight_rolloff` in
## `shaders/canvas/tonemap.gdshader`, and a picture that quietly stops matching
## the thing it illustrates is worse than no picture, so this samples it against
## the table that shader's own header records: filling the canvas at each stored
## value and reading the viewport back.
##
## The numbers: the default knee is white, 1.0, the top of
## the slider, so the knees below reach it, and the chroma loss is measured by
## how far Khronos PBR Neutral's shoulder would have pulled the peak rather than
## by how far the peak stands past the knee, so the shader's own lines asserted
## here are the new ones. The magnitude's table did not move.
extends "res://tests/test_framework.gd"

const SHADER_PATH := "res://shaders/canvas/tonemap.gdshader"

## The measured table from the shader's tuning notes. Read back from an 8-bit
## viewport, so the last digit is quantisation and the tolerance says so.
const MEASURED := [[0.50, 0.502], [0.75, 0.749], [1.00, 1.000], [1.25, 1.000], [1.50, 1.000], [3.00, 1.000]]

## One 8-bit step is 0.0039, and the table is rounded to three places.
const READBACK_TOLERANCE := 0.004

## The knees the sliders can reach, bottom and top of the range, the top being
## the default, and the old default, 0.5, between them.
const KNEES := [0.05, 0.35, 0.5, 0.76, 1.0]

## The default knee, `SaSettingsValues.tonemap_knee`'s.
const DEFAULT_KNEE := 1.0


func test_the_drawn_curve_matches_the_shaders_measured_table() -> void:
    for knee: float in KNEES:
        for pair: Array in MEASURED:
            var stored: float = pair[0]
            var shown := SaCurvePlot.displayed_for_stored(stored, knee)
            assert_almost_eq(shown, pair[1], READBACK_TOLERANCE, "knee %.2f, stored %.2f" % [knee, stored])


## A painted white is display white, whatever the sliders say.
func test_white_stays_white_at_every_knee() -> void:
    for knee: float in KNEES:
        var shown := SaCurvePlot.displayed_for_stored(1.0, knee)
        assert_almost_eq(shown, 1.0, 1e-5, "knee %.2f shows a painted white at %.4f" % [knee, shown])


## The identity region is the property the whole operator is chosen for: a
## stored value under the knee has to come back bit for bit.
func test_everything_below_the_knee_is_returned_untouched() -> void:
    for knee: float in [0.35, 0.5, 0.76]:
        for stored: float in [0.0, 0.1, 0.25, 0.5]:
            var shown := SaCurvePlot.displayed_for_stored(stored, knee)
            assert_almost_eq(shown, stored, 1e-5, "knee %.2f leaves a stored %.2f alone" % [knee, stored])


## And nothing between the knee and white is darkened either, which is the half
## of the promise the old shoulder broke.
func test_nothing_up_to_white_is_darkened() -> void:
    for knee: float in KNEES:
        for stored: float in [0.6, 0.75, 0.9, 1.0]:
            var shown := SaCurvePlot.displayed_for_stored(stored, knee)
            assert_almost_eq(shown, stored, 1e-5, "knee %.2f darkens a stored %.2f to %.4f" % [knee, stored, shown])


## Nothing may exceed display white, and the curve may never turn back on
## itself: both are conditions the operator was picked to satisfy.
func test_the_curve_rises_and_never_passes_white() -> void:
    var previous := -1.0
    for i in 200:
        var stored := SaCurvePlot.STORED_MAX * float(i) / 199.0
        var shown := SaCurvePlot.displayed_for_stored(stored, DEFAULT_KNEE)
        assert_true(shown <= 1.0 + 1e-6, "a stored %.2f shows as %.4f, past white" % [stored, shown])
        assert_true(shown >= previous, "a stored %.2f went backwards: %.4f after %.4f" % [stored, shown, previous])
        previous = shown


## The point of the slider, now that it moves no magnitude: a lower knee starts
## taking chroma earlier, so the same stored red comes out closer to white.
func test_a_lower_knee_takes_chroma_earlier() -> void:
    var low := _chroma(SaCurvePlot.rolled_color(0.9, 0.35, 0.15))
    var high := _chroma(SaCurvePlot.rolled_color(0.9, 0.76, 0.15))
    assert_true(low < high, "knee 0.35 leaves chroma %.4f, knee 0.76 leaves %.4f" % [low, high])


## The stroke's colour is the setting acting on a red highlight, so more
## desaturation has to leave less chroma.
func test_more_desaturation_takes_more_chroma_from_the_stroke() -> void:
    var kept := SaCurvePlot.rolled_color(3.0, DEFAULT_KNEE, 0.0)
    var lost := SaCurvePlot.rolled_color(3.0, DEFAULT_KNEE, 1.0)
    assert_true(_chroma(lost) < _chroma(kept), "chroma %.4f at full desaturation, %.4f at none" % [_chroma(lost), _chroma(kept)])
    assert_eq(SaCurvePlot.rolled_color(0.25, DEFAULT_KNEE, 1.0), SaCurvePlot.COLOR_START, "and below the knee nothing is taken")
    assert_eq(SaCurvePlot.rolled_color(1.0, DEFAULT_KNEE, 1.0), SaCurvePlot.COLOR_START, "nor at the default knee itself")


## GDScript cannot include a `.gdshader`, so the operator is written twice. This
## reads the shader to say when one of the two moved without the other.
func test_the_ceiling_is_still_the_shaders_own() -> void:
    var source := FileAccess.get_file_as_string(SHADER_PATH)
    assert_false(source.is_empty(), "the shader is where the plot says it is")
    assert_true(source.contains("float new_peak = min(peak, 1.0);"), "white is still the ceiling and the whole curve")
    assert_false(source.contains("1.0 - d * d / (peak + d - k)"), "and the shoulder that dimmed white has not come back")
    assert_true(source.contains("float past = max(peak - k, 0.0);"), "the chroma loss is still measured from the knee")
    assert_true(
        source.contains("float pulled = past * past / (past + KHRONOS_SHOULDER);"), "by how far the shoulder pulled the peak"
    )
    assert_true(source.contains("float g = 1.0 - 1.0 / (desat * pulled + 1.0);"), "through the same denominator")
    var shoulder := "const float KHRONOS_SHOULDER = %s;" % str(SaCurvePlot.KHRONOS_SHOULDER)
    assert_true(source.contains(shoulder), "and the shoulder is as wide as the plot's, %s" % shoulder)


## The picture is plotted on the axis the operator moves, so these are
## the assertions that say the line bends: below the knee nothing is taken, at
## the knee the fall starts, and it never turns back up.
func test_the_chroma_line_is_flat_below_the_knee_and_falls_after_it() -> void:
    for knee: float in KNEES:
        var stored_knee := OkhsvConversions.channel_rgb_to_srgb(knee)
        for stored: float in [0.0, stored_knee * 0.5, stored_knee * 0.99]:
            var left := SaCurvePlot.chroma_left(stored, knee, 0.5)
            assert_almost_eq(left, 1.0, 1e-5, "knee %.2f takes chroma at a stored %.3f" % [knee, stored])
        var previous := 1.0
        for i in 60:
            var stored := stored_knee + (SaCurvePlot.STORED_MAX - stored_knee) * float(i) / 59.0
            var left := SaCurvePlot.chroma_left(stored, knee, 0.5)
            assert_true(left <= previous + 1e-6, "knee %.2f turned back up at a stored %.3f" % [knee, stored])
            previous = left
        assert_true(previous < 0.999, "knee %.2f leaves %.4f of the chroma at the top of the axis" % [knee, previous])


## The Knee slider has to move where the line leaves the top, which is the whole
## point: a graph whose shape never changed would be wrong.
func test_a_lower_knee_bends_the_line_earlier() -> void:
    var low := SaCurvePlot.chroma_left(1.5, 0.35, 0.5)
    var high := SaCurvePlot.chroma_left(1.5, 0.76, 0.5)
    assert_true(low < high, "knee 0.35 leaves %.4f at a stored 1.5, knee 0.76 leaves %.4f" % [low, high])


## And Desaturation has to move how steeply it falls, which is the other slider
## the old picture answered only in colour.
func test_more_desaturation_steepens_the_fall() -> void:
    var gentle := SaCurvePlot.chroma_left(2.0, DEFAULT_KNEE, 0.15)
    var steep := SaCurvePlot.chroma_left(2.0, DEFAULT_KNEE, 0.8)
    assert_true(steep < gentle, "0.15 leaves %.4f at a stored 2.0, 0.8 leaves %.4f" % [gentle, steep])
    assert_almost_eq(SaCurvePlot.chroma_left(2.0, DEFAULT_KNEE, 0.0), 1.0, 1e-5, "and none takes nothing at any value")


## The line is the shader's `1 - g` and nothing else, checked against the
## shader's own arithmetic rather than against a number written down here: the
## same `desat * pulled + 1` denominator, with `pulled` the shoulder's
## `past * past / (past + 0.24)`, evaluated in light rather than in stored values.
func test_the_chroma_line_is_the_shaders_own_g() -> void:
    for knee: float in [0.35, 0.5, 0.76, 1.0]:
        for stored: float in [1.0, 1.01, 1.5, 2.0, 3.0, 4.0]:
            for desat: float in [0.0, 0.15, 0.5, 1.0]:
                var peak := OkhsvConversions.channel_srgb_to_rgb(stored)
                var past := maxf(peak - knee, 0.0)
                var g := 1.0 - 1.0 / (desat * past * past / (past + 0.24) + 1.0)
                var left := SaCurvePlot.chroma_left(stored, knee, desat)
                assert_almost_eq(left, 1.0 - g, 1e-6, "knee %.2f, stored %.2f, desat %.2f" % [knee, stored, desat])


static func _chroma(color: Color) -> float:
    return SaOklab.to_polar(SaOklab.from_linear_srgb(Vector3(color.r, color.g, color.b))).y
