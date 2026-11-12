## A right press on a layer row reaches the docker and opens the actions menu.
##
## The defect was one engine rule, measured rather than assumed. A mouse event
## walks up the control chain from whatever it landed on and stops at the first
## control whose `mouse_filter` is STOP, so a `PanelContainer`, which is born
## STOP, ate every right press that landed on it. The menu opened from the empty
## space under the rows, where the chain runs through containers and the list,
## which are PASS, and never from a row, which is the row the menu is about. The
## row is PASS since d4, so a press it does not answer keeps travelling up to
## `LayersDocker._on_control_gui_input`.
##
## The delivery is a scenario, because a docker is a `Window` and no test can put
## one in this suite's tree:
## `sara-godot/scenarios/a-rename-dialog-for-a-layer-carrying-its-note.json`
## presses at the first row's own reported centre, which bought nothing
## this and names `LayerActionsMenu` with that row selected after it. What is
## pinned here is the filter each control on the row carries, which is what the
## engine reads.
extends "res://tests/test_framework.gd"


func _row(is_group: bool = false) -> SaLayerRowView:
    return SaLayerRowView.new("Sky", 0, is_group, 0)


## A press the row has no use for keeps going: nothing between the pointer and
## the docker is STOP except the controls that answer a press of their own.
func test_nothing_on_a_row_swallows_a_press_it_does_not_answer() -> void:
    var item := _row()
    var row: Control = item
    assert_eq(row.mouse_filter, Control.MOUSE_FILTER_PASS, "the row itself lets the press through")

    for node in row.find_children("*", "Control", true, false):
        var control := node as Control
        if control == null or not control.visible:
            continue
        if control is BaseButton or control is Range or control is LineEdit:
            continue
        assert_true(
            control.mouse_filter != Control.MOUSE_FILTER_STOP,
            "a %s on the row must not take a press the row does not want" % control.get_class()
        )

    row.free()


## And the controls that do answer a press still get it: the eye and the three
## locks are buttons, while the name and the picture take no press at all, so a
## press on the name is a press on the row.
func test_the_controls_that_answer_a_press_still_take_their_own() -> void:
    var item := _row()
    assert_eq(item.eye_btn.mouse_filter, Control.MOUSE_FILTER_STOP, "the eye answers its own press")

    var toggles: Dictionary = item.toggles
    assert_eq(toggles.size(), 3, "three locks, whatever the layer's flags are")
    for which: StringName in toggles:
        assert_eq((toggles[which] as Button).mouse_filter, Control.MOUSE_FILTER_STOP, "%s answers its own press" % which)

    assert_eq(item.lbl.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the name is not a press target")
    assert_eq(item.thumb.mouse_filter, Control.MOUSE_FILTER_IGNORE, "and neither is the picture")

    item.free()


## A group's fold mark is a button too, so a right press on it stays where a
## left press lands, on the mark rather than on the drawer behind it.
func test_a_groups_fold_mark_still_takes_its_own_press() -> void:
    var item := _row(true)
    var disclose: Button = item.disclose
    assert_not_null(disclose, "a group's row carries a fold mark")
    if disclose != null:
        assert_eq(disclose.mouse_filter, Control.MOUSE_FILTER_STOP, "and it answers its own press")
    item.free()
