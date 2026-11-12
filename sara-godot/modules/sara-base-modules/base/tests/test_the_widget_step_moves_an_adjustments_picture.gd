## A scenario's widget step on an adjustment's slider moves the pass the way a
## drag does.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The step `{"filter": {"widget": "contrast", "value": 100}}` printed `moved
## contrast -> 100.0` and the picture stayed where it was. An adjustment's
## number row is a custom row whose control is a box around the slider, and a
## box that answered no door was driven by the row's own write: the row's
## number moved and a rerun was asked for, while the filter's value, which the
## slider's signal writes, never changed. The box answers the door now, so the
## step moves the slider and raises the signal a drag raises.
##
## `scenarios/a-filter-steps-widget-moves-brightness-and-contrasts-picture-too.json`
## is the half on a running app, reading the red layer's texel move.
extends "res://tests/test_framework.gd"


func _drive(filter: SaAdjustFilter, moves: Dictionary) -> Dictionary:
    var host := VBoxContainer.new()
    var dialog := SaDialog.for_filter(filter)
    dialog.realize(host)
    var said: Array = []
    for key: String in moves:
        said.append(SaFilterDialogWindow._drive(dialog.row(StringName(key)), {"widget": key, "value": moves[key]}))
    var pending := dialog.rerun_pending
    dialog.flush_rerun()
    var runs := dialog.runs
    host.free()
    return {"said": said, "pending": pending, "runs": runs}


func test_the_widget_step_moves_contrast_in_the_pass() -> void:
    var filter := SaBrightnessContrastFilter.new()
    assert_almost_eq(float(filter.values()["contrast"]), 1.0, 1e-6, "Contrast opens as the identity exponent")
    var driven := _drive(filter, {"contrast": 100.0})
    assert_eq(String(driven["said"][0]), "contrast -> 100.0", "The step says what the slider holds")
    assert_true(bool(driven["pending"]), "and asks for a rerun")
    assert_eq(int(driven["runs"]), 1, "which runs once")
    assert_almost_eq(float(filter.parameters()["contrast"]), 100.0, 1e-6, "The record keeps the slider's number")
    var top := 1.0 + SaBrightnessContrastFilter.LIGHT_2_CONTRAST_REACH
    assert_almost_eq(float(filter.values()["contrast"]), top, 1e-6, "and the pass is handed the exponent at the reach's end")


func test_the_widget_step_moves_brightness_in_the_pass() -> void:
    var filter := SaBrightnessContrastFilter.new()
    assert_almost_eq(float(filter.values()["brightness"]), 1.0, 1e-6, "Brightness opens as a factor of one")
    _drive(filter, {"brightness": 50.0})
    assert_almost_eq(float(filter.parameters()["brightness"]), 50.0, 1e-6, "The record keeps the slider's number")
    var stops := SaBrightnessContrastFilter.LIGHT_2_STOPS_UP / 2.0
    assert_almost_eq(float(filter.values()["brightness"]), pow(2.0, stops), 1e-4, "and the pass is handed half the stops")


## The box is shared by the three slider adjustments, so the step reaches each.
func test_every_slider_adjustment_answers_the_step() -> void:
    var filters: Array[SaAdjustFilter] = [
        SaBrightnessContrastFilter.new(), SaHueSaturationLightnessFilter.new(), SaColorBalanceFilter.new()
    ]
    for filter in filters:
        for row: Dictionary in filter.rows():
            if String(row.get("type", "slider")) != "slider":
                continue
            var key := String(row["key"])
            var wanted := float(row["max"])
            _drive(filter, {key: wanted})
            assert_almost_eq(float(filter.parameters()[key]), wanted, 1e-6, "%s's %s moved" % [filter.title(), key])
