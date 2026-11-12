## A flat menu row has no box to say it is off, so the text has to. A row that
## takes no press is `text_muted` at `DISABLED_ALPHA` and a plain one is
## `text_primary` at `PLAIN_ALPHA`, and the review of 2026-10-18 asked whether
## those two are far enough apart to tell. Its second point was that the comment
## on `DISABLED_ALPHA` leaned on a box a flat list does not draw, so the words are
## held here in every palette, and a disabled hint is held no brighter than a
## live one, which the first point found the other way round.
extends "res://tests/test_framework.gd"

## The least gap of Oklab lightness between a plain row's text and a disabled
## row's, both over the menu's ground.
const MIN_GAP := 0.15

var _saved_theme: String = "default"


func before_each() -> void:
    _saved_theme = SaTheme.palette_id


func after_each() -> void:
    SaTheme.use_named(_saved_theme)


static func _over(ink: Color, alpha: float, ground: Color) -> Color:
    return ground.lerp(ink, alpha)


func test_a_disabled_row_text_is_told_from_a_plain_one_in_every_palette() -> void:
    for id: String in SaTheme.PALETTES:
        SaTheme.use_named(id)
        var palette := SaTheme.palette
        var plain := _over(palette.text_primary, SaChoicePopup.PLAIN_ALPHA, palette.bg_panel)
        var off := _over(palette.text_muted, SaChoicePopup.DISABLED_ALPHA, palette.bg_panel)
        var gap := absf(OkhslConversions.srgb_to_oklch(plain).z - OkhslConversions.srgb_to_oklch(off).z)
        assert_true(gap >= MIN_GAP, "%s: a disabled row is %.3f of lightness from a plain one" % [id, gap])


## The words held above are the ones a disabled row really draws: its button is
## disabled and sets no text colour of its own, so it draws the shared theme's
## `font_disabled_color` for a button, and that is `text_muted`. A list of rows
## with ticks is flat, which is why the box a disabled row has is not drawn.
func test_a_disabled_menu_row_draws_the_muted_text_colour() -> void:
    SaTheme.use_named("default")
    SaUI.init_global_theme(null)
    var popup := SaChoicePopup.new(true, false)
    popup.add_row(&"off", "Off", true, false, "", "", true)
    var button := popup.label_button(&"off")
    assert_true(button.disabled, "the row is a disabled button")
    assert_true(button.flat, "in a flat list, which draws no box to say so")
    assert_false(button.has_theme_color_override("font_disabled_color"), "and sets no colour of its own")
    var shared := SaUI.shared_theme.get_color("font_disabled_color", "Button")
    assert_eq(shared, SaTheme.palette.text_muted, "so it draws text_muted")
    popup.free()


func test_a_disabled_hint_is_never_brighter_than_a_live_one() -> void:
    var popup := SaChoicePopup.new(true, false)
    popup.add_row(&"live", "Live", false, false, "", "Ctrl+L")
    popup.add_row(&"off", "Off", false, false, "", "Ctrl+O", true)
    var live_alpha := _hint_alpha(popup, &"live")
    var off_alpha := _hint_alpha(popup, &"off")
    assert_true(live_alpha > 0.0 and off_alpha > 0.0, "both rows draw a chord")
    assert_true(off_alpha <= live_alpha, "the disabled chord, %.2f, is not above the live one, %.2f" % [off_alpha, live_alpha])
    for base: float in [0.4, 0.55, 0.6, 1.0]:
        assert_true(SaChoiceRow.hint_alpha(base, true) <= SaChoiceRow.hint_alpha(base, false), "at %.2f" % base)
    popup.free()


static func _hint_alpha(popup: SaChoicePopup, id: StringName) -> float:
    var row := popup._rows[id] as SaChoiceRow
    var hint := row.find_child("Hint", true, false) as Label
    return hint.modulate.a if hint != null else -1.0
