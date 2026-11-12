## A Sara left idle draws nothing and still took half a core, and the cursor
## overlays were that half core.
##
## Left alone for an hour, Sara took 0.46 of a core, all on the main
## thread, with no frame drawn. Measured per `_process`, the nineteen
## `CursorOverlay` steps were 0.55 of the 0.57 a plain Sara took, and turning
## every other script's step off moved nothing. Two things were done every frame
## that had nothing to do. Every overlay ran the process-wide OS cursor sync,
## which gives one answer for all of them, and the overlays of hidden windows,
## the Filter dialogs, the Message box and every closed docker, asked for a ring
## nobody could see.
##
## A test cannot await a frame, so every suite here runs inside one, which is
## what makes the once-a-frame half testable: whatever was synced this frame
## stays synced for the rest of the suite.
extends "res://tests/test_framework.gd"

var _host: Node = null
var _previous_mode: String = "auto"
var _previous_mouse_mode: int = Input.MOUSE_MODE_VISIBLE


func before_each() -> void:
    _previous_mode = SaSettings.software_cursor
    _previous_mouse_mode = Input.get_mouse_mode()
    _host = Node.new()
    _host.name = "IdleCursorOverlayTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaSettings.software_cursor = _previous_mode
    if _host != null:
        _host.free()
        _host = null
    # Process-wide, so a pointer this suite hid would stay hidden for the
    # suites after it.
    if Input.get_mouse_mode() != _previous_mouse_mode:
        Input.set_mouse_mode(_previous_mouse_mode as Input.MouseMode)


func _window() -> Window:
    var window := Window.new()
    window.borderless = true
    window.size = Vector2i(320, 240)
    window.visible = false
    _host.add_child(window)
    return window


## A hidden window's overlay has nothing to draw, so it does not step, and it
## steps again the moment its window shows.
func test_an_overlay_steps_only_while_its_window_is_shown() -> void:
    if DisplayServer.get_name() == "headless":
        return
    var window := _window()
    var overlay := CursorOverlay.attach_to(window)
    assert_not_null(overlay, "A hidden window takes an overlay like any other")
    assert_false(overlay.is_processing(), "and the overlay of a hidden window does not step")

    window.show()
    assert_true(overlay.is_processing(), "Shown, it steps")
    assert_false(overlay._state_valid, "and its first step draws, whatever it saw before the window hid")

    window.hide()
    assert_false(overlay.is_processing(), "Hidden again, it stops")


## A window shown before its overlay arrives, which is the main window's case
## and a docker's that opens where it was left, steps from the start.
func test_an_overlay_in_a_shown_window_steps_from_the_start() -> void:
    if DisplayServer.get_name() == "headless":
        return
    var window := _window()
    window.show()
    var overlay := CursorOverlay.attach_to(window)
    assert_true(overlay.is_processing(), "An overlay joining a shown window steps at once")


## The overlays' sync runs once a frame, and a caller that changed what it
## depends on still gets a sync of its own.
##
## *Both* always gives the OS pointer back, so a pointer hidden by hand after the
## frame's sync shows which calls ran it: the overlays' call leaves it hidden,
## because the frame was already synced, and the plain call shows it.
func test_the_overlays_sync_once_a_frame_and_a_caller_syncs_at_once() -> void:
    if DisplayServer.get_name() == "headless":
        return
    SaSettings.software_cursor = "both"
    SaCursorPolicy.sync_os_cursor_visibility_this_frame()

    Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
    SaCursorPolicy.sync_os_cursor_visibility_this_frame()
    assert_eq(Input.get_mouse_mode(), Input.MOUSE_MODE_HIDDEN, "A second overlay in the same frame does not sync again")

    SaCursorPolicy.sync_os_cursor_visibility()
    assert_eq(Input.get_mouse_mode(), Input.MOUSE_MODE_VISIBLE, "while the plain sync always runs")
