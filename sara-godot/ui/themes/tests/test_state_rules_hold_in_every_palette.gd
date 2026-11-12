## A hover is seen, a press is told from the hover, and the
## text on an accent is read, in every palette Sara ships.
##
## A state derives from its ramp, and a ramp is whatever the painter chose. Pink
## had a hover at 1.09 to 1 from its rest and Paper White's was 1.2 to 1, which is
## a control that does not answer the pointer. `SaPalette.derive_states` now moves
## a hover a fixed step of Oklab lightness away from its rest, keeps a pressed
## state under its hover, and moves a ground that carries text until the text
## reads. What is held here is those three rules over all six palettes, and the
## helpers they are made of.
extends "res://tests/test_framework.gd"

## Half a step is allowed to be lost to the edge of the sRGB gamut, where a colour
## that is nearly white or nearly black cannot move the whole way.
const SLACK := 0.5

var _saved_theme: String = "default"


func before_each() -> void:
    _saved_theme = SaTheme.palette_id


func after_each() -> void:
    SaTheme.use_named(_saved_theme)


static func _lightness(color: Color) -> float:
    return OkhslConversions.srgb_to_oklch(color).z


func test_a_hover_steps_away_from_its_rest_in_every_palette() -> void:
    for id: String in SaTheme.PALETTES:
        SaTheme.use_named(id)
        var palette := SaTheme.palette
        var toward := _lightness(palette.text_primary)
        for key: String in SaPalette.HOVER_FROM:
            if palette.overridden_states.has(key):
                continue
            var rest: Color = palette.get(String(SaPalette.HOVER_FROM[key]))
            var hover: Color = palette.get(key)
            var moved := _lightness(hover) - _lightness(rest)
            var wanted := 1.0 if toward > _lightness(rest) else -1.0
            assert_true(
                moved * wanted >= SaPalette.HOVER_STEP * SLACK,
                "%s: %s moves toward the text by at least half a step, %.3f" % [id, key, moved * wanted]
            )


func test_a_pressed_state_sits_under_its_hover_in_every_palette() -> void:
    for id: String in SaTheme.PALETTES:
        SaTheme.use_named(id)
        var palette := SaTheme.palette
        for key: String in SaPalette.PRESSED_UNDER:
            if palette.overridden_states.has(key):
                continue
            var hover: Color = palette.get(String(SaPalette.PRESSED_UNDER[key]))
            var gap := _lightness(hover) - _lightness(palette.get(key))
            assert_true(gap >= SaPalette.PRESS_GAP - 0.01, "%s: %s is %.3f of lightness under its hover" % [id, key, gap])


func test_the_text_on_an_accent_reads_in_every_palette() -> void:
    for id: String in SaTheme.PALETTES:
        SaTheme.use_named(id)
        var palette := SaTheme.palette
        for key: String in SaPalette.TEXT_GROUNDS:
            if palette.overridden_states.has(key):
                continue
            var ratio := SaPalette.contrast_ratio(palette.text_primary, palette.get(key))
            assert_true(ratio >= SaPalette.TEXT_CONTRAST - 0.05, "%s: text on %s holds %.2f to 1" % [id, key, ratio])


func test_the_slider_keeps_the_gauge_for_its_handle() -> void:
    for id: String in SaTheme.PALETTES:
        SaTheme.use_named(id)
        var palette := SaTheme.palette
        if palette.overridden_states.has("slider_handle"):
            continue
        assert_eq(palette.slider_handle, palette.accent_gauge, "%s: the handle is the gauge, no rule moves it" % id)


func test_stepped_moves_toward_the_colour_it_is_given() -> void:
    var grey := Color(0.4, 0.4, 0.4)
    assert_true(_lightness(SaPalette.stepped(grey, Color.WHITE, 0.1)) > _lightness(grey) + 0.08, "toward white is lighter")
    assert_true(_lightness(SaPalette.stepped(grey, Color.BLACK, 0.1)) < _lightness(grey) - 0.08, "toward black is darker")


func test_below_lowers_a_colour_only_when_it_is_too_close() -> void:
    var above := Color(0.5, 0.5, 0.5)
    var near := Color(0.49, 0.49, 0.49)
    var lowered := SaPalette.below(near, above, 0.06)
    assert_true(_lightness(lowered) <= _lightness(above) - 0.05, "a colour near the one above is lowered")
    var far := Color(0.1, 0.1, 0.1)
    assert_eq(SaPalette.below(far, above, 0.06), far, "a colour already under it is returned as it is")


func test_with_contrast_moves_a_ground_only_until_the_text_reads() -> void:
    var pale := Color(0.8, 0.8, 0.8)
    var moved := SaPalette.with_contrast(pale, Color.WHITE, 4.5)
    assert_true(SaPalette.contrast_ratio(Color.WHITE, moved) >= 4.5, "white now holds 4.5 on it")
    assert_true(SaPalette.contrast_ratio(Color.WHITE, moved) < 5.0, "and it moved no further than that needs")
    var dark := Color(0.1, 0.1, 0.1)
    assert_eq(SaPalette.with_contrast(dark, Color.WHITE, 4.5), dark, "a ground that already reads is returned as it is")
    assert_true(absf(SaPalette.contrast_ratio(Color.WHITE, Color.BLACK) - 21.0) < 0.01, "and the ratio of white to black is 21")


## The focus ring is the selected border, and a ring that does not stand out from
## the field it rings is no ring. 3 to 1 is the line the WCAG sets for a graphic
## that carries meaning.
func test_the_focus_ring_is_seen_on_a_field_and_on_a_switched_off_toggle_in_every_palette() -> void:
    for id: String in SaTheme.PALETTES:
        SaTheme.use_named(id)
        var palette := SaTheme.palette
        for ground: String in ["bg_input", "toggle_off"]:
            var ratio := SaPalette.contrast_ratio(palette.border_selected, palette.get(ground))
            assert_true(ratio >= 3.0, "%s: the ring holds %.2f to 1 on %s" % [id, ratio, ground])


## A hover rim is not the focus rim, or a painter cannot tell a pointer over a
## control from a keyboard on it.
func test_a_hover_rim_is_not_the_focus_rim_in_every_palette() -> void:
    for id: String in SaTheme.PALETTES:
        SaTheme.use_named(id)
        var palette := SaTheme.palette
        assert_true(palette.border_hover != palette.border_selected, "%s: hover and focus rims are two colours" % id)
        assert_true(
            SaTheme.make_toggle_style("hover").border_color != SaTheme.make_toggle_style("focus").border_color,
            "%s: and so are the boxes" % id
        )


## A switch that is On wears the accent, so an On switch reads as the one thing
## on the page that is lit.
func test_a_switch_that_is_on_is_the_accent_and_the_title_bar_too() -> void:
    for id: String in SaTheme.PALETTES:
        SaTheme.use_named(id)
        var palette := SaTheme.palette
        if not palette.overridden_states.has("switch_pressed"):
            assert_eq(SaPalette.STATE_BASES["switch_pressed"], "accent_primary", "%s: an On switch is based on the accent" % id)
        var bar := SaTheme.make_drag_bar_style() as StyleBoxFlat
        assert_eq(bar.bg_color, palette.title_bar, "%s: a docker's title bar draws the title_bar field" % id)


## A scrollbar grabber is one hue in three steps of lightness: rest, hover, press.
func test_a_scrollbar_grabber_steps_in_one_hue_in_every_palette() -> void:
    for id: String in SaTheme.PALETTES:
        SaTheme.use_named(id)
        var palette := SaTheme.palette
        if palette.overridden_states.has("scrollbar_hover") or palette.overridden_states.has("scrollbar_pressed"):
            continue
        var rest := _lightness(palette.scrollbar_grabber)
        var hover := _lightness(palette.scrollbar_hover)
        var pressed := _lightness(palette.scrollbar_pressed)
        var wanted := 1.0 if _lightness(palette.text_primary) > rest else -1.0
        assert_true((hover - rest) * wanted > 0.04, "%s: the hover is past the rest" % id)
        assert_true((pressed - hover) * wanted > 0.04, "%s: and the press is past the hover" % id)
