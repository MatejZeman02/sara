## A slider's empty track and its fill stand apart in lightness on every
## palette, so its value reads at a glance.
##
## The fill and the handle are the gauge and stay. What moves is the
## track: `SaPalette.derive_states` steps it in Oklab lightness until the fill
## holds `SaPalette.SLIDER_CONTRAST` on it. What is held here is that rule over
## every palette Sara ships, and the helper it is made of.
extends "res://tests/test_framework.gd"

var _saved_theme: String = "default"


func before_each() -> void:
    _saved_theme = SaTheme.palette_id


func after_each() -> void:
    SaTheme.use_named(_saved_theme)


func test_the_fill_stands_three_to_one_on_the_track_in_every_palette() -> void:
    assert_true(SaPalette.SLIDER_CONTRAST >= 3.0, "the rule asks for 3 to 1 at the least")
    for id: String in SaTheme.PALETTES:
        SaTheme.use_named(id)
        var palette := SaTheme.palette
        for fill: String in ["slider_handle", "slider_hover"]:
            var ratio := SaPalette.contrast_ratio(palette.get(fill), palette.slider_track)
            assert_true(ratio >= 3.0, "%s: %s on slider_track holds %.2f to 1" % [id, fill, ratio])


func test_the_fill_and_handle_are_not_moved() -> void:
    for id: String in SaTheme.PALETTES:
        SaTheme.use_named(id)
        var palette := SaTheme.palette
        for fill: String in ["slider_handle", "slider_hover"]:
            if palette.overridden_states.has(fill):
                continue
            assert_eq(palette.get(fill), palette.accent_gauge, "%s: %s is still the gauge" % [id, fill])


func test_the_track_keeps_its_ramp_where_it_already_stands_apart() -> void:
    var palette := SaPalette.new()
    palette.bg_slider = Color("#101010")
    palette.accent_gauge = Color("#A0E0B0")
    palette.derive_states()
    assert_eq(palette.slider_track, palette.bg_slider, "a track already 3 to 1 from the fill is its base")


func test_the_track_steps_away_from_a_fill_it_sits_close_to() -> void:
    var palette := SaPalette.new()
    palette.bg_slider = Color("#5A5A5A")
    palette.accent_gauge = Color("#6A7A6E")
    palette.derive_states()
    var ratio := SaPalette.contrast_ratio(palette.accent_gauge, palette.slider_track)
    assert_true(ratio >= SaPalette.SLIDER_CONTRAST, "a close track is moved to %.2f to 1" % ratio)
    assert_true(
        OkhslConversions.srgb_to_oklch(palette.slider_track).z < OkhslConversions.srgb_to_oklch(palette.bg_slider).z,
        "a track darker than its fill goes darker"
    )


func test_a_track_that_cannot_clear_on_its_side_crosses_to_the_other() -> void:
    # A fill at a luminance of about 0.35 leaves no lighter colour 3 to 1 from
    # it, so a track just over it has to cross under it.
    var fill := Color("#A0A0A0")
    var track := SaPalette.apart_from(Color("#B0B0B0"), fill, 3.0)
    var ratio := SaPalette.contrast_ratio(fill, track)
    assert_true(ratio >= 3.0, "the track crosses to %.2f to 1" % ratio)


func test_a_track_the_painter_set_is_left_where_they_set_it() -> void:
    var palette := SaPalette.new()
    palette.slider_track = Color("#606060")
    palette.accent_gauge = Color("#646464")
    palette.hold_state("slider_track")
    palette.derive_states()
    assert_eq(palette.slider_track, Color("#606060"), "an overridden track is not derived")
