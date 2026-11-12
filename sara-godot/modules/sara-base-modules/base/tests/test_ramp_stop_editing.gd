## A gradient stop's colour and its alpha, which the painter can change
## and read.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## What is here
## is everything that can be asked of a detached control: the row's shape, the
## refusals, and the ramp a fresh gradient opens with. The popup itself is a
## `Window`, and a test that adds one to the tree maps a real OS window and hangs
## the run, so opening it and picking in it is
## `scenarios/gradient-stop-colour-and-alpha.json` on the running app.
##
## In the module's tests, with the control it exercises: the ramp editor is the
## base module's now and a suite over it belongs beside it, which is what the
## runner already discovers under `modules/`.
extends "res://tests/test_framework.gd"


func _control() -> SaColorRampControl:
    var control := SaColorRampControl.new()
    control.bind_ramp(SaColorRamp.from_pair(Color.RED, Color.BLUE))
    return control


## The button has no name because it is gone: the
## swatch is the stop's colour and a press opens a picker, so there is nothing
## left for a word to describe.
func test_the_set_button_is_gone_and_the_swatch_is_the_stop() -> void:
    var control := _control()

    var swatch := control.find_child("StopColor", true, false) as Button

    assert_not_null(swatch, "the row still has a swatch")
    assert_eq(swatch.text, "", "with no word on it")
    assert_false(control.has_method("_take_foreground"), "and the handler that took the foreground is gone")
    var box := swatch.get_theme_stylebox("normal") as StyleBoxFlat
    assert_eq(box.bg_color.to_html(false), Color.RED.to_html(false), "it is painted in the selected stop's colour")
    control.free()


func test_the_swatch_follows_the_selection() -> void:
    var control := _control()

    control.select_stop(1)

    var box := (control.find_child("StopColor", true, false) as Button).get_theme_stylebox("normal") as StyleBoxFlat
    assert_eq(box.bg_color.to_html(false), Color.BLUE.to_html(false), "the far end's colour")
    control.free()


## The alpha is a custom slider so that people know it is an alpha slider. A bare `HSlider` is a groove
## with a knob on it and says
## nothing at all.
func test_the_alpha_is_a_named_factor_slider() -> void:
    var control := _control()

    var alpha := control.find_child("StopAlpha", true, false)

    assert_true(alpha is FactorSlider, "the app's own slider rather than an HSlider")
    assert_eq((alpha as FactorSlider).prefix.strip_edges(), "Alpha:", "and it says what it is")
    assert_almost_eq((alpha as FactorSlider).max_value, 1.0, 1e-6, "over nought to one")
    control.free()


func test_the_alpha_row_reads_back_in_the_dump() -> void:
    var control := _control()
    control.set_selected_alpha(0.25)

    var report := control.stop_report()

    assert_eq(String(report["alpha_row"]["label"]), "Alpha:", "the label a shot cannot show")
    assert_almost_eq(float(report["alpha_row"]["shown"]), 0.25, 1e-4, "and what the slider is showing")
    assert_eq(String(report["swatch"]), Color.RED.to_html(false), "beside the colour the swatch is painted in")
    control.free()


## The popup is the door and the door has to be shut before it can be used. Both
## refusals matter: a capture step that reported a clean pick onto a popup that
## never opened would be the failure this door exists to avoid.
func test_the_popup_refuses_when_there_is_nothing_to_edit() -> void:
    var bare := SaColorRampControl.new()

    assert_false(bare.open_swatch(), "no ramp bound, so there is no stop to pick for")
    assert_false(bare.pick_in_swatch(Color.GREEN), "and nothing to pick in")
    bare.free()

    var control := _control()
    assert_false(control.pick_in_swatch(Color.GREEN), "a pick with the popup shut is refused")
    assert_false(control.close_swatch(), "and shutting a popup that is not up says so")
    control.free()


## The gradient tool builds its ramp from the pair rather than from two
## constants.
func test_a_fresh_gradient_ramp_is_the_pair_it_is_handed() -> void:
    var ramp := SaGradientEnds.new().fresh_ramp(Color(0.2, 0.4, 0.6), Color(0.9, 0.8, 0.1))

    assert_eq(ramp.size(), 2, "two ends")
    assert_eq(ramp.color_of(0).to_html(false), Color(0.2, 0.4, 0.6).to_html(false), "the near one is the foreground")
    assert_eq(ramp.color_of(1).to_html(false), Color(0.9, 0.8, 0.1).to_html(false), "and the far one the background")


## Every stop, the ends and any the bar adds, is edited on the same row. The
## foreground is not the only way to write a colour.
func test_a_stop_the_bar_added_is_edited_the_same_way() -> void:
    var control := _control()

    var added := control.add_stop_at(0.5)
    control.select_stop(added)
    control.set_selected_color(Color.GREEN)
    control.set_selected_alpha(0.5)

    var report := control.stop_report()
    assert_eq(int(report["selected"]), added, "the new stop is the selected one")
    assert_eq(String(report["swatch"]), Color.GREEN.to_html(false), "its colour is what was picked")
    assert_almost_eq(float(control.ramp.color_of(added).a), 0.5, 1e-4, "and its alpha what the slider set")
    control.free()
