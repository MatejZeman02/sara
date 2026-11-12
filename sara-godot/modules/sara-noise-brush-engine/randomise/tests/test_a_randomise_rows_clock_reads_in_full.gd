## A randomise row's clock reads in full, Along the stroke and
## Per stroke, with Per dab no longer a clock.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The note read "Per..." on every randomise row of the Brush Editor's General
## page, whatever its width. The choice had a fixed floor of 76 logical pixels
## and the amount slider beside it took the rest, and 76 does not hold "Per
## stroke" beside the arrow at the app's font. Now the choice asks for its
## longest label as drawn, its arrow included, which is "Along the stroke".
##
## Each label is measured here by a paragraph of this suite's own, in the font
## and at the size the button draws with, so the control cannot pass by
## agreeing with itself. The control is built through its row's spec under a
## host themed with the app's theme, in the real tree under an autoload as
## the docker's own suite puts it, because a detached
## control hears no theme change and the width is fitted on one. Its row is
## sorted by hand at the narrowest it asks for, because a suite cannot await
## the frame a `queue_sort` is answered on. The running app's proof is
## `scenarios/a-randomise-rows-per-dab-and-per-stroke-read-in-full.json`.
extends "res://tests/test_framework.gd"

const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")

var _kept_theme: Theme = null
var _kept_scale: float = 1.0
var _kept_font_scale: float = 1.0
## The themed control the built row sits under, in the tree while a test runs.
var _host: Control = null


func before_each() -> void:
    _kept_theme = SaUI.shared_theme
    _kept_scale = SaUI.user_scale
    _kept_font_scale = SaUI.user_font_scale


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    SaUI.shared_theme = _kept_theme
    SaUI.user_scale = _kept_scale
    SaUI.user_font_scale = _kept_font_scale


## Both labels fit whole at UI scales 1 and 2, at the default font size and at
## a larger one, on the row laid out at the narrowest it asks for.
func test_both_labels_fit_whole_at_ui_scales_one_and_two() -> void:
    for ui_scale: float in [1.0, 2.0]:
        for font_scale: float in [1.0, 1.5]:
            SaUI.user_scale = ui_scale
            SaUI.user_font_scale = font_scale
            SaUI.init_global_theme(null)
            var control := _built()
            var clock := control.find_child("HardnessRandomClock", true, false) as SaChoiceButton
            var context := "at UI scale %s and font scale %s" % [ui_scale, font_scale]
            assert_eq(
                clock.choice_labels(),
                ["Along the stroke", "Per stroke"] as Array[String],
                "The clock offers its two labels %s" % context
            )
            assert_not_null(clock.icon, "and draws its arrow, which the room below leaves out")
            for label: String in clock.choice_labels():
                assert_true(
                    _room_for_text(clock) >= _text_width(clock, label),
                    "'%s' fits whole %s, %d of room for %d" % [label, context, _room_for_text(clock), _text_width(clock, label)]
                )
            _host.free()
            _host = null


## The width follows the font rather than a constant: a larger font size
## widens the choice, which a fixed floor never did.
func test_the_width_follows_the_font_size() -> void:
    SaUI.user_font_scale = 1.0
    SaUI.init_global_theme(null)
    var control := _built()
    var clock := control.find_child("HardnessRandomClock", true, false) as SaChoiceButton
    var plain := clock.custom_minimum_size.x
    clock.add_theme_font_size_override(&"font_size", SaUI.get_font_size() * 2)
    assert_true(
        clock.custom_minimum_size.x > plain, "Twice the font asks for more, %d against %d" % [clock.custom_minimum_size.x, plain]
    )
    assert_almost_eq(
        clock.custom_minimum_size.x, SaRandomiseControl.fitting_width(clock), 0.5, "and asks for exactly what it now measures"
    )


## Hardness's randomise control as the page builds it, themed with the app's
## theme and sorted at the narrowest width it asks for.
func _built() -> SaRandomiseControl:
    var spec: SaOptionSpec = null
    for candidate: SaOptionSpec in NoiseModuleScript.options():
        if candidate.key == &"hardness_random":
            spec = candidate
    assert_not_null(spec, "The page declares Hardness's randomise row")
    _host = Control.new()
    _host.theme = SaUI.shared_theme
    _host.name = "D80RandomiseTestHost"
    EventBus.add_child(_host)
    var control: SaRandomiseControl = spec.build_control.call(spec, Callable())
    _host.add_child(control)
    control.size = Vector2(control.get_combined_minimum_size().x, control.get_combined_minimum_size().y)
    control.notification(Container.NOTIFICATION_SORT_CHILDREN)
    return control


## The width *button* leaves its text: its laid-out width less the chrome's
## margins and the arrow with its gap, as the engine's button draws them.
func _room_for_text(button: Button) -> float:
    var room := button.size.x - button.get_theme_stylebox(&"normal").get_minimum_size().x
    if button.icon != null:
        room -= button.icon.get_width() + button.get_theme_constant(&"h_separation")
    return room


## *text* as *control* draws it, by a paragraph of this suite's own.
func _text_width(control: Control, text: String) -> float:
    var paragraph := TextParagraph.new()
    paragraph.add_string(text, control.get_theme_font(&"font"), control.get_theme_font_size(&"font_size"))
    return paragraph.get_size().x
