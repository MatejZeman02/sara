## A row that means nothing under the current setting is dimmed and disabled
##.
##
## The note, 2026-09-07 09:04:22, Tool Options: "Repeat and Wobble options should
## be dimmed when they have None as selected." The standing rule is that **dimmed also means disabled**: a control that is
## greyed and still moves is never what a note asking for dimming meant. So every
## case here asserts both halves, and `row_reads_enabled` is written to fail on
## either.
##
## `scenarios/repeat-rows-disabled-at-none.json` drives the real docker, where
## Steps reads disabled at Repeat None and Mirror and live at Steps, and Wobble
## amount reads disabled at Wobble None and live at Noise.
extends "res://tests/test_framework.gd"

## By path rather than by class name, the way `test_transform_proofs.gd`
## reaches it: the base module has no `class_name`, and a suite that named one
## would be naming a module from the skeleton's tests.
const BASE_MODULE := preload("res://modules/sara-base-modules/base/module.gd")


func _gated(controlling: StringName, values: Array) -> SaOptionSpec:
    var spec := SaOptionSpec.make_float(&"gated", "Gated", 0.0, 1.0, 0.01)
    spec.enabled_when = controlling
    spec.enabled_when_values = values
    return spec


func test_a_spec_with_no_rule_is_always_enabled() -> void:
    var plain := SaOptionSpec.make_float(&"plain", "Plain", 0.0, 1.0, 0.01)
    assert_true(SaOptionSpec.row_is_enabled(plain, null), "No rule, so nothing to be dead under")
    assert_true(SaOptionSpec.row_is_enabled(plain, 3), "whatever else is going on")
    assert_true(SaOptionSpec.row_is_enabled(null, 3), "and a spec that is not there is not a reason to dim")


func test_a_rule_naming_no_values_is_the_same_as_no_rule() -> void:
    var half_declared := _gated(&"gradient_repeat", [])
    assert_true(SaOptionSpec.row_is_enabled(half_declared, 0), "An incomplete rule leaves the row live")


func test_the_row_is_enabled_only_for_the_values_it_named() -> void:
    var spec := _gated(&"gradient_repeat", [3])
    assert_true(SaOptionSpec.row_is_enabled(spec, 3), "Enabled on the value it named")
    assert_false(SaOptionSpec.row_is_enabled(spec, 0), "and dead on None")
    assert_false(SaOptionSpec.row_is_enabled(spec, 1), "and dead on the other two, which its tooltip already said")
    assert_false(SaOptionSpec.row_is_enabled(spec, null), "and dead when nothing answers for the controlling option")


## Both halves, on a control that carries `disabled`.
func test_a_button_is_greyed_and_refuses_the_hand() -> void:
    var spec := _gated(&"gradient_wobble", [1, 2])
    var button := Button.new()

    SaOptionSpec.apply_enabled(button, null, spec, 0)
    assert_true(button.disabled, "Dead, so the hand cannot move it")
    assert_almost_eq(button.modulate.a, SaOptionSpec.DIMMED_ALPHA, 0.001, "and it is dimmed to say so")
    assert_eq(button.focus_mode, Control.FOCUS_NONE, "and Tab cannot reach it either")

    SaOptionSpec.apply_enabled(button, null, spec, 1)
    assert_false(button.disabled, "Live again")
    assert_almost_eq(button.modulate.a, 1.0, 0.001, "and back to its own colour")

    button.free()


## And on a control that carries `editable` instead, which is every `Range`.
func test_a_slider_is_greyed_and_refuses_the_hand() -> void:
    var spec := _gated(&"gradient_repeat", [3])
    var slider := HSlider.new()

    SaOptionSpec.apply_enabled(slider, null, spec, 0)
    assert_false(slider.editable, "A Range says editable rather than disabled")
    assert_almost_eq(slider.modulate.a, SaOptionSpec.DIMMED_ALPHA, 0.001, "and it is dimmed the same way")

    SaOptionSpec.apply_enabled(slider, null, spec, 3)
    assert_true(slider.editable, "Live again")

    slider.free()


## The docker wraps its controls in a labelled row, so the label has to grey with
## the control or half the row says it is live.
func test_the_row_greys_when_there_is_one_rather_than_the_control() -> void:
    var spec := _gated(&"gradient_repeat", [3])
    var row := HBoxContainer.new()
    var label := Label.new()
    var slider := HSlider.new()
    row.add_child(label)
    row.add_child(slider)

    SaOptionSpec.apply_enabled(slider, row, spec, 0)
    assert_almost_eq(row.modulate.a, SaOptionSpec.DIMMED_ALPHA, 0.001, "The whole row greys, label and all")
    assert_almost_eq(slider.modulate.a, 1.0, 0.001, "rather than the control greying twice under it")
    assert_false(slider.editable, "and the control still refuses the hand")

    row.free()


func test_a_dump_reads_a_row_as_dead_on_either_half() -> void:
    var row := HBoxContainer.new()
    var slider := HSlider.new()
    row.add_child(slider)
    assert_true(SaOptionSpec.row_reads_enabled(row), "A plain row reads live")

    slider.editable = false
    assert_false(SaOptionSpec.row_reads_enabled(row), "A row whose control refuses the hand reads dead")

    slider.editable = true
    row.modulate.a = SaOptionSpec.DIMMED_ALPHA
    assert_false(SaOptionSpec.row_reads_enabled(row), "and so does one that is merely greyed")
    assert_true(SaOptionSpec.row_reads_enabled(null), "A row that is not there is nobody's claim")

    row.free()


## The declarations themselves, so a spec that quietly loses its rule is noticed.
func test_the_gradient_declares_both_rules() -> void:
    var specs: Dictionary = {}
    for spec: SaOptionSpec in BASE_MODULE.gradient_options():
        specs[spec.key] = spec

    var steps := specs.get(&"gradient_steps") as SaOptionSpec
    assert_not_null(steps, "The gradient declares Steps")
    assert_eq(steps.enabled_when, &"gradient_repeat", "gated on Repeat")
    assert_true(SaOptionSpec.row_is_enabled(steps, SaGradient.Repeat.STEPS), "live under Steps")
    assert_false(SaOptionSpec.row_is_enabled(steps, SaGradient.Repeat.NONE), "and dead under None, which is the note")

    var amount := specs.get(&"gradient_wobble_amount") as SaOptionSpec
    assert_not_null(amount, "and Wobble amount")
    assert_eq(amount.enabled_when, &"gradient_wobble", "gated on Wobble")
    assert_true(SaOptionSpec.row_is_enabled(amount, SaGradient.Wobble.NOISE), "live under Noise")
    assert_false(SaOptionSpec.row_is_enabled(amount, SaGradient.Wobble.NONE), "and dead under None")
