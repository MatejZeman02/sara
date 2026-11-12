## The blend button marks the mode it shows once, and a sync that shows the
## same mode again leaves its list alone.
##
## The tool options bar and docker show the blend mode on every sync, and a mark
## recolours every row of the list, a millisecond a time. A shift-drag synced
## four times a motion, so the mark alone was half of what a resize cost.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const REQUIRES_GPU := true

## What a row wears that no mark would give it, so a row the mark redrew shows.
const STAMP := Color(0.1, 0.9, 0.3)


func _button() -> BlendModeButton:
    var button := BlendModeButton.new()
    button.registry = Fixtures.make_registries().blend_modes
    button.include_hidden_in_layers = true
    button.refresh()
    return button


func _stamp(button: BlendModeButton, mode_id: StringName) -> void:
    button.popup.label_button(mode_id).add_theme_color_override("font_color", STAMP)


func _wears_stamp(button: BlendModeButton, mode_id: StringName) -> bool:
    return button.popup.label_button(mode_id).get_theme_color("font_color") == STAMP


func test_the_same_mode_shown_again_leaves_the_list_alone() -> void:
    var button := _button()
    var modes := button.mode_ids()
    var first: StringName = modes[0]
    var second: StringName = modes[1]

    assert_true(button.select_mode(second), "The second mode is shown")
    assert_true(button.popup.is_marked(second), "and marked")
    var label := button.text
    _stamp(button, first)
    _stamp(button, second)
    assert_true(button.select_mode(second), "Shown again")
    assert_true(_wears_stamp(button, first), "the list is left alone, a row it would have recoloured keeps what it wore")
    assert_true(_wears_stamp(button, second), "and so does the marked one")
    assert_eq(button.text, label, "The label is the mode's still")

    assert_true(button.select_mode(first), "Another mode is shown")
    assert_false(_wears_stamp(button, first), "and the list is marked again")
    assert_true(button.popup.is_marked(first), "on the mode now shown")
    assert_false(button.popup.is_marked(second), "and off the one before")
    button.free()


## A refilled list carries no mark, so the mode the button already showed is
## marked again rather than skipped as already drawn.
func test_a_refilled_list_is_marked_again() -> void:
    var button := _button()
    var second: StringName = button.mode_ids()[1]
    button.select_mode(second)
    button.space = null
    button.refresh()
    assert_eq(button.current, second, "The refill keeps the mode")
    assert_true(button.popup.is_marked(second), "and marks it on the new rows")
    button.free()
