## The View menu's actual pixels divide the interface scale out, the same as the
## chord beside it. The row was Zoom to 100%, which put it on
## 1.25 device pixels a texel, and it is now split into Reset
## Zoom, which shows what the Display page's Ctrl+0 row names, and Actual
## Pixels, one texel per device pixel, the arithmetic below, which reads Pixels
## 100%.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The arithmetic on a real view, the menu row on the running app.** The
## menu's handler finds its view through the current scene's main canvas, and a
## suite runs with no scene and no tree, so the row itself is pressed by
## `scenarios/the-view-menus-hundred-per-cent.json` at an interface scale of
## 1.25 and its dump reads the zoom. What is stated here is the two numbers the
## handler chooses between, on a view whose content scale is set, and
## that the handler and the command now name the same call.
extends "res://tests/test_framework.gd"

const VIEW_MENU := "res://ui/menus/view_menu.gd"
const COMMANDS := "res://ui/shortcuts/shortcut_commands.gd"


## A view with a fixed size and interface scale that keeps the zoom and the pan
## it is given, which is everything `zoom_at` reads and writes.
class ScaledView:
    extends SaView

    # Plain members rather than private ones read back by a getter, which the
    # house rule and `test_privates_rule` both refuse: the view's API is the
    # overridden methods, and these are only where a fake view keeps its state.
    var zoom_value: float = 1.0
    var pan_value: Vector2 = Vector2.ZERO
    var content_scale: float = 1.0

    func _init(scale: float, start_zoom: float) -> void:
        content_scale = scale
        zoom_value = start_zoom

    func get_zoom() -> float:
        return zoom_value

    func set_zoom(value: float) -> void:
        zoom_value = value

    func get_pan() -> Vector2:
        return pan_value

    func set_pan(value: Vector2) -> void:
        pan_value = value

    func get_viewport_size() -> Vector2:
        return Vector2(1600.0, 900.0)

    func get_content_scale() -> float:
        return content_scale


func test_at_an_interface_scale_of_1_25_a_hundred_per_cent_is_a_zoom_of_0_8() -> void:
    var view := ScaledView.new(1.25, 0.5)
    view.zoom_to_actual_pixels(view.get_viewport_size() * 0.5)
    assert_almost_eq(view.get_zoom(), 0.8, 1e-6, "One texel per device pixel is 1 over 1.25")

    var logical := ScaledView.new(1.25, 0.5)
    logical.zoom_at(1.0, logical.get_viewport_size() * 0.5)
    assert_almost_eq(logical.get_zoom(), 1.0, 1e-6, "which the menu used to land on instead, 1.25 device pixels a texel")


func test_at_an_interface_scale_of_one_the_two_agree() -> void:
    var view := ScaledView.new(1.0, 0.5)
    view.zoom_to_actual_pixels(view.get_viewport_size() * 0.5)
    assert_almost_eq(view.get_zoom(), 1.0, 1e-6, "On a plain display both are one, which is why nobody saw the row drift")


func test_the_middle_of_the_view_stays_on_the_same_document_point() -> void:
    var view := ScaledView.new(1.25, 0.37)
    var middle := view.get_viewport_size() * 0.5
    var before := view.screen_to_document(middle)
    view.zoom_to_actual_pixels(middle)
    var after := view.screen_to_document(middle)
    assert_almost_eq(after.x, before.x, 1e-3, "The menu zooms about the middle, so the point under it stays in x")
    assert_almost_eq(after.y, before.y, 1e-3, "and in y")


## The menu's rows are the commands now, so the two cannot drift: each row is
## drawn from its command and a press runs that command's handler, which is
## read as source because it cannot be pressed in a suite without the router's
## canvas.
func test_the_menu_row_and_the_command_call_the_same_zoom() -> void:
    var menu := FileAccess.get_file_as_string(VIEW_MENU)
    assert_true(menu.contains('[ID_ZOOM_100, &"view_zoom_100"]'), "The menu's Reset Zoom row is the command")
    assert_true(menu.contains('[ID_ACTUAL_PIXELS, &"view_actual_pixels"]'), "and so is its Actual Pixels row")
    assert_false(menu.contains("zoom_to"), "and the menu holds no zoom of its own to drift")

    var commands := FileAccess.get_file_as_string(COMMANDS)
    var reset := commands.substr(commands.find("func _reset_zoom"), 400)
    var asked := "view.reset(_document_size(), true)"
    assert_true(reset.contains(asked), "Reset Zoom is the call a new document opens with, asked to toggle")
    var actual := commands.substr(commands.find("func _actual_pixels"), 400)
    assert_true(actual.contains("zoom_to_actual_pixels"), "and Actual Pixels the arithmetic above")
