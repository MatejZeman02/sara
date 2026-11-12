## The top bar's three window buttons, in whichever order the setting asks for.
##
## `ui/top_bar/tests/test_top_menu_bar.gd` already pins the two orders and which end of the
## row the group sits at. What is unpinned here is the rest of the behaviour and
## the state dump the scenario reads: that Left is
## not merely a move but the macOS look, three coloured traffic lights with no
## glyph on them, and that Right restores the icon buttons rather than leaving
## dots behind after a round trip.
extends "res://tests/test_framework.gd"

## The three lights, in the order a Mac draws them. Read off Apple's own
## palette, and repeated here rather than imported so a change to either side
## has to be made twice on purpose.
const MACOS_LIGHTS := [
    ["CloseBtn", "#ff5f57"],
    ["MinimizeBtn", "#ffbd2e"],
    ["MaximizeBtn", "#28c840"],
]


func before_each() -> void:
    SaSettings.window_button_position = "auto"
    SaSettings.window_button_style = "auto"


func after_each() -> void:
    SaSettings.window_button_position = "auto"
    SaSettings.window_button_style = "auto"


func _make_bar() -> TopMenuBar:
    var bar := TopMenuBar.new()
    bar._ready()
    return bar


## What the scenario's state dump reads, so a picture of a title bar does not
## have to carry the claim. Twelve pixels of a 1920 wide shot say which edge and
## nothing about the order or the colours.
func test_the_dump_names_the_order_the_side_and_the_three_lights() -> void:
    SaSettings.window_button_position = "left"
    SaSettings.window_button_style = "lights"
    var bar := _make_bar()

    var state := bar.window_buttons.report()
    assert_eq(state.get("setting"), "left", "the dump repeats the setting")
    assert_eq(state.get("side"), "left", "and the side it resolved to")
    assert_eq(state.get("style_setting"), "lights", "the look's setting")
    assert_eq(state.get("style"), "lights", "and the look it resolved to")
    assert_eq(state.get("index_in_row"), 0, "the group is the first thing on the row")
    for i in MACOS_LIGHTS.size():
        var wanted: Array = MACOS_LIGHTS[i]
        var button: Dictionary = state["buttons"][i]
        assert_eq(button["name"], wanted[0], "light %d is %s" % [i, wanted[0]])
        assert_true(button["dot"], "%s is drawn as a dot" % wanted[0])
        assert_eq(button["dot_color"], wanted[1], "%s is the wrong colour" % wanted[0])

    bar.free()


## Right is icon buttons, not dots. The dump says so with the same two fields,
## which is what makes the pair of shots in the scenario readable.
func test_right_reports_icon_buttons_and_no_colours() -> void:
    SaSettings.window_button_position = "right"
    var bar := _make_bar()

    var state := bar.window_buttons.report()
    assert_eq(state.get("side"), "right", "the side is right")
    assert_eq(state.get("index_in_row"), state.get("row_children") - 1, "the group is the last thing on the row")
    for button: Dictionary in state["buttons"]:
        assert_false(button["dot"], "%s is drawn as a dot on the right" % button["name"])
        assert_eq(button["dot_color"], "", "%s kept a colour on the right" % button["name"])

    bar.free()


## The round trip, which is the failure a one-way test would miss: a bar that
## went Left and came back Right must be icon buttons again, because the dots
## are theme overrides and an override outlives the setting that added it.
func test_going_left_and_back_leaves_no_dots_behind() -> void:
    var bar := _make_bar()

    SaSettings.window_button_position = "left"
    SaSettings.window_button_style = "lights"
    bar.apply_layout_settings()
    assert_true(bar.window_buttons.report()["buttons"][0]["dot"], "Lights did not draw dots")

    SaSettings.window_button_position = "right"
    SaSettings.window_button_style = "icons"
    bar.apply_layout_settings()
    for button: Dictionary in bar.window_buttons.report()["buttons"]:
        assert_false(button["dot"], "%s is still a dot after coming back" % button["name"])

    bar.free()


## And the icons come back with it, not only the shape. A button with no icon
## and no dot is an empty rectangle, which is the state the round trip could
## leave and a screenshot at 1920 would not show.
func test_the_icons_come_back_with_the_windows_order() -> void:
    SaSettings.window_button_position = "left"
    SaSettings.window_button_style = "lights"
    var bar := _make_bar()

    SaSettings.window_button_position = "right"
    SaSettings.window_button_style = "icons"
    bar.apply_layout_settings()
    for name: String in ["MinimizeBtn", "MaximizeBtn", "CloseBtn"]:
        var btn := bar.window_buttons.get_node(name) as Button
        assert_true(btn.icon != null or not btn.text.is_empty(), "%s is drawn as nothing" % name)

    bar.free()


## The two settings are two: the edge decides the order and the
## look decides the drawing, so GNOME's buttons on the left are icons in the
## close-first order, and lights on the right are dots in the Windows order.
## Auto for the look follows the platform the way Auto for the edge does.
func test_the_edge_and_the_look_are_chosen_apart() -> void:
    SaSettings.window_button_position = "left"
    SaSettings.window_button_style = "icons"
    var bar := _make_bar()
    var state := bar.window_buttons.report()
    assert_eq(state["order"], ["CloseBtn", "MinimizeBtn", "MaximizeBtn"], "left is close first")
    for button: Dictionary in state["buttons"]:
        assert_false(button["dot"], "%s is a dot with the look on icons" % button["name"])

    SaSettings.window_button_position = "right"
    SaSettings.window_button_style = "lights"
    bar.apply_layout_settings()
    state = bar.window_buttons.report()
    assert_eq(state["order"], ["MinimizeBtn", "MaximizeBtn", "CloseBtn"], "right is close last")
    for button: Dictionary in state["buttons"]:
        assert_true(button["dot"], "%s is an icon with the look on lights" % button["name"])

    SaSettings.window_button_style = "auto"
    bar.window_buttons.os_name_override = "macOS"
    bar.apply_layout_settings()
    assert_eq(bar.window_buttons.report()["style"], "lights", "Auto is the lights on a Mac")
    bar.window_buttons.os_name_override = "Linux"
    bar.apply_layout_settings()
    assert_eq(bar.window_buttons.report()["style"], "icons", "and the icons elsewhere")

    bar.free()
