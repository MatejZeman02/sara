## Preferences fits itself to its host in `_ready`, before it is shown, and with
## subwindows off a window that has not been shown has no display server id.
## Asking which screen that id is on logged `INVALID_SCREEN` on every launch. The frame now asks the screen of
## the window that opens it,
## the main window's when nothing does, and the engine says nothing.
extends "res://tests/test_framework.gd"

## It builds a real Preferences window, and only a run with a RenderingDevice
## has a display server that answers about screens.
const REQUIRES_GPU := true


## The usable rect of the screen the main window is on, which is what a window
## with no opener of its own is measured against.
func _main_screen_rect() -> Rect2i:
    return DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen(DisplayServer.MAIN_WINDOW_ID))


func test_a_window_nobody_has_shown_measures_the_main_windows_screen() -> void:
    var window := SaSettingsWindow.new()
    var frame := SaSettingsFrame.new()
    frame.attach(window)
    assert_eq(window.get_window_id(), DisplayServer.INVALID_WINDOW_ID, "A window never shown has no display server id")

    var errors := SaErrorCatcher.new()
    OS.add_logger(errors)
    var host := frame.host_rect()
    OS.remove_logger(errors)

    assert_eq(host, _main_screen_rect(), "so it is measured on the main window's screen")
    assert_eq(errors.described([SaErrorCatcher.ERROR]), PackedStringArray(), "and the engine logs no error")
    window.free()


## The path the launch took: Preferences added to the tree hidden as a window
## of its own, so `_ready` fits it before it has an OS window.
##
## `force_native` stands in for Embed subwindows off, because it gives the one
## window what the preference gives every window and leaves the root alone. The
## root refuses to stop embedding while any embedded window is shown, and a
## window another suite leaves up made that flip fail in a full run, while
## taking that window down changed what a later suite found in the root.
func test_preferences_added_hidden_as_a_window_of_its_own_logs_no_error() -> void:
    var host := Node.new()
    host.name = "ScreenTestHost"
    EventBus.add_child(host)
    var window := SaSettingsWindow.new()
    window.visible = false
    window.force_native = true

    var errors := SaErrorCatcher.new()
    OS.add_logger(errors)
    host.add_child(window)
    var rect := window.frame.host_rect()
    OS.remove_logger(errors)

    assert_false(window.is_embedded(), "It is a window of its own")
    assert_eq(window.get_window_id(), DisplayServer.INVALID_WINDOW_ID, "and it has no id until it is shown")
    assert_eq(rect, _main_screen_rect(), "so it measures the screen of the window that opens it")
    var caught := errors.described([SaErrorCatcher.ERROR])
    assert_eq(caught, PackedStringArray(), "and neither the fit in _ready nor the ask logs an error")

    host.free()
