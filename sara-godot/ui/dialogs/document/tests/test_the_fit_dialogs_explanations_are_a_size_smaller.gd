## The sentence under each row of the fit dialog is a size smaller than the
## row's title.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## When the dialog was a grid its hints asked for 0.8 of the size through
## `SaUI.FONT_SCALE_META`. That meta is read
## by the theme pass alone, and a dialog never runs the theme pass (the comment
## on `SaDialogWindow._on_ui_font_scale_changed` says why), so the fraction was
## asked for and never applied and the hints drew at the rows' size. The rows are
## now a page, whose hints `SaSettingsRows.hint_label` sizes with an
## override of their own, and this holds that: the size the label carries is
## what it draws at, at every interface scale, because the scale is the window's
## `content_scale_factor` and multiplies the title and the hint alike.
extends "res://tests/test_framework.gd"

const SCALES: Array[float] = [1.0, 1.5, 2.0]

var _saved_override: float = -1.0
var _saved_user: float = 1.0


func before_each() -> void:
    _saved_override = SaUI.os_scale_override
    _saved_user = SaUI.user_scale


func after_each() -> void:
    SaUI.os_scale_override = _saved_override
    SaUI.user_scale = _saved_user


func test_every_explanation_is_a_step_below_its_title_at_three_scales() -> void:
    SaUI.os_scale_override = 1.0
    for ui_scale: float in SCALES:
        SaUI.user_scale = ui_scale
        var dialog := SaImportFitDialog.new()
        dialog.apply_window_scale()
        assert_almost_eq(dialog.content_scale_factor, ui_scale, 0.0001, "The window scales its content at %s" % ui_scale)
        for key: StringName in [&"space", &"fit", &"depth"]:
            var line := dialog.page.row(key).line
            var title := line.find_child("Title", true, false) as Label
            var hint := line.find_child("*Hint", true, false) as Label
            assert_not_null(hint, "The %s row has its sentence" % key)
            var title_size := title.get_theme_font_size("font_size")
            var hint_size := hint.get_theme_font_size("font_size")
            # The title's own number is the theme's, which a headless run never
            # builds, so what is held here is the hint's and the order of the two.
            assert_eq(
                hint_size,
                SaSettingsRows.font_size(SaSettingsRows.HINT_SCALE),
                "and its sentence the hint size in logical units, not a fraction nobody applies"
            )
            assert_true(
                hint_size * dialog.content_scale_factor < title_size * dialog.content_scale_factor,
                "so the %s sentence draws smaller than its title at %s" % [key, ui_scale]
            )
        dialog.free()


## The open question shows the space and depth rows with the same sentences,
## so the dialog Open the picture is held as well as the fit.
func test_the_open_question_keeps_its_smaller_sentences() -> void:
    SaUI.os_scale_override = 1.0
    SaUI.user_scale = 1.0
    var dialog := SaImportFitDialog.new()
    dialog.configure_open(Vector2i(64, 64))
    for key: StringName in [&"space", &"depth"]:
        var line := dialog.page.row(key).line
        var title := line.find_child("Title", true, false) as Label
        var hint := line.find_child("*Hint", true, false) as Label
        assert_true(
            hint.get_theme_font_size("font_size") < title.get_theme_font_size("font_size"),
            "The %s sentence is smaller than its title when a picture is opened" % key
        )
    dialog.free()
