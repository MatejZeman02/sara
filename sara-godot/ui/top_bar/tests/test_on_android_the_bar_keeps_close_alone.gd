## On Android the top bar keeps the maximise square and close, and minimise is gone.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## On Android the maximise square toggles between maximised under the system
## bars and full screen, and minimise does nothing there. The platform is taken
## through `os_name_override`, as the bar's other suites take macOS.
extends "res://tests/test_framework.gd"


func test_on_android_the_bar_keeps_close_alone() -> void:
    var buttons := SaTopBarWindowButtons.new()
    EventBus.add_child(buttons)
    buttons.os_name_override = "Android"
    buttons.apply_settings()
    assert_false(buttons.minimize_btn.visible, "On Android minimise is gone, the system owns the window")
    assert_true(buttons.maximize_btn.visible, "and maximise stays, so full screen is one press away")
    assert_true(buttons.close_btn.visible, "and close stays, since it asks about unsaved work")
    var shown: Array = (buttons.report()["buttons"] as Array).filter(func(b: Dictionary) -> bool: return b["visible"])
    assert_eq(shown.map(func(b: Dictionary) -> String: return b["name"]), ["MaximizeBtn", "CloseBtn"], "and the report says so")
    buttons.os_name_override = "Linux"
    buttons.apply_settings()
    assert_true(buttons.minimize_btn.visible and buttons.maximize_btn.visible, "On Linux all three stand as before")
    buttons.free()
