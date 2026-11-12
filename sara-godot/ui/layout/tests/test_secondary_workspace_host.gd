## The secondary workspace is a native window that remembers where it was.
##
## The host itself is never added to the tree here, because a Window in the
## tree maps a real OS window and the runner hangs on it. What can be proved
## detached is proved: the window asks Godot for a native one, the placement
## rule picks the remembered rectangle only while a screen still holds it, and
## the two settings reach the profile under their keys.
extends "res://tests/test_framework.gd"

const LEFT := Rect2i(0, 0, 1920, 1080)
const RIGHT := Rect2i(1920, 0, 3840, 2160)

var _saved_screen: int = -1
var _saved_rect := Rect2i()


func before_each() -> void:
    _saved_screen = SaSettings.secondary_workspace_screen
    _saved_rect = SaSettings.secondary_workspace_rect


func after_each() -> void:
    SaSettings.secondary_workspace_screen = _saved_screen
    SaSettings.secondary_workspace_rect = _saved_rect


func test_the_host_asks_for_a_native_window() -> void:
    var host := SecondaryWorkspaceHost.new()
    assert_true(host.force_native, "the host is native whatever the root embeds")
    host.free()


func test_nothing_remembered_means_centre() -> void:
    var usable: Array[Rect2i] = [LEFT, RIGHT]
    assert_eq(SecondaryWorkspaceHost.placement(Rect2i(), -1, usable), Rect2i(), "an empty memory centres the host")


func test_a_rectangle_on_its_screen_is_kept() -> void:
    var usable: Array[Rect2i] = [LEFT, RIGHT]
    var on_right := Rect2i(2000, 100, 1280, 720)
    assert_eq(SecondaryWorkspaceHost.placement(on_right, 1, usable), on_right, "the second monitor's rectangle comes back")


func test_a_rectangle_on_a_renumbered_screen_is_kept() -> void:
    var usable: Array[Rect2i] = [LEFT, RIGHT]
    var on_right := Rect2i(2000, 100, 1280, 720)
    var moved := SecondaryWorkspaceHost.placement(on_right, 0, usable)
    assert_eq(moved, on_right, "a screen index that moved does not lose the place")
    var past := SecondaryWorkspaceHost.placement(on_right, 7, usable)
    assert_eq(past, on_right, "nor does one past the count")


func test_a_rectangle_on_no_screen_centres() -> void:
    var usable: Array[Rect2i] = [LEFT]
    var unplugged := Rect2i(2000, 100, 1280, 720)
    var placed := SecondaryWorkspaceHost.placement(unplugged, 1, usable)
    assert_eq(placed, Rect2i(), "a monitor that is gone is not a place to open on")


func test_the_place_reaches_the_profile() -> void:
    SaSettings.secondary_workspace_screen = 1
    SaSettings.secondary_workspace_rect = Rect2i(2000, 100, 1280, 720)
    assert_eq(int(SaSettings.config.get_value("ui", "secondary_workspace_screen")), 1, "the screen is written under its key")
    assert_eq(
        SaSettings.config.get_value("ui", "secondary_workspace_rect") as Rect2i,
        Rect2i(2000, 100, 1280, 720),
        "and so is the rectangle"
    )
