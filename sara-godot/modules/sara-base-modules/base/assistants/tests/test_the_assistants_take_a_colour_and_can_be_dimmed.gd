## The assistants are drawn in the colour the painter picks and as strongly as
## they ask, and Snap off leaves them on screen holding nothing.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"


func before_each() -> void:
    SaAssistants.switches = SaAssistants.Switches.new()


func after_each() -> void:
    SaAssistants.switches = null


func test_the_default_colour_is_the_violet_and_full_strength() -> void:
    assert_eq(SaAssistants.tint(), SaAssistants.COLOR, "a fresh switch draws the violet the guides always had")


func test_a_picked_colour_is_drawn() -> void:
    SaAssistants.switches.tint = 1
    assert_eq(Color(SaAssistants.tint(), 1.0), Color(SaAssistants.TINTS[1], 1.0), "the second colour is the one drawn")


func test_dimming_lowers_the_alpha_and_keeps_the_colour() -> void:
    SaAssistants.switches.strength = 0.5
    var dimmed := SaAssistants.tint()
    assert_almost_eq(dimmed.a, SaAssistants.COLOR.a * 0.5, 0.001, "half strength halves the alpha")
    assert_eq(Color(dimmed, 1.0), Color(SaAssistants.COLOR, 1.0), "and the colour stays")


func test_the_options_offer_a_colour_and_a_strength() -> void:
    var keys: Array[StringName] = []
    for spec: SaOptionSpec in SaAssistants.options():
        keys.append(spec.key)
    assert_true(&"assistants_tint" in keys, "the Colour row is offered")
    assert_true(&"assistants_strength" in keys, "and the Strength row")
    assert_eq(SaAssistants.TINTS.size(), SaAssistants.TINT_NAMES.size(), "every colour has a name")


func test_snap_off_keeps_the_guides_shown_and_holding_nothing() -> void:
    var switches := SaAssistants.switches
    switches.snap = false
    var guides := SaAssistants.Guides.new(switches)
    assert_true(switches.shown, "the guides are still on screen")
    assert_true(guides._holding() == false, "and they hold no stroke")
