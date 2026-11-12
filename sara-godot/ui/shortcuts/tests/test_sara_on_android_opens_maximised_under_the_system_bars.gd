## Sara on Android opens maximised under the system bars.
##
## On Android the square button on the top bar and View full screen toggle
## between maximised under the system bars and full screen, and the choice is
## kept across starts. Full screen opens first, a few rows short of the display,
## which the settings suite beside it checks.
extends "res://tests/test_framework.gd"

const PROJECT_FILE := "res://project.godot"


## project.godot sets the Android window mode to full screen (3) and leaves the
## desktop mode maximised (2).
func test_project_godot_window_modes() -> void:
    var config := ConfigFile.new()
    assert_eq(config.load(PROJECT_FILE), OK, "project.godot loads")
    var android_mode: int = config.get_value("display", "window/size/mode.android", -1)
    var desktop_mode: int = config.get_value("display", "window/size/mode", -1)
    assert_eq(android_mode, DisplayServer.WINDOW_MODE_FULLSCREEN, "Android opens full screen")
    assert_eq(desktop_mode, DisplayServer.WINDOW_MODE_MAXIMIZED, "Desktop window mode stays unchanged")


## The screen mode setting defaults to full screen.
func test_screen_mode_setting_default() -> void:
    assert_eq(SaSettings.screen_mode, "fullscreen", "The screen mode defaults to full screen")


## Full screen targets on Android toggle between maximised and full screen.
func test_android_fullscreen_targets() -> void:
    var target_in := SaAppCommands.fullscreen_target(
        DisplayServer.WINDOW_MODE_MAXIMIZED, DisplayServer.WINDOW_MODE_MAXIMIZED, true
    )
    assert_eq(target_in, DisplayServer.WINDOW_MODE_FULLSCREEN, "Maximised goes to full screen")

    var target_out := SaAppCommands.fullscreen_target(
        DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_MAXIMIZED, true
    )
    assert_eq(target_out, DisplayServer.WINDOW_MODE_MAXIMIZED, "Full screen restores to maximised")

    var target_out_from_windowed_restore := SaAppCommands.fullscreen_target(
        DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_WINDOWED, true
    )
    assert_eq(
        target_out_from_windowed_restore,
        DisplayServer.WINDOW_MODE_MAXIMIZED,
        "A windowed restore falls back to maximised on Android"
    )


## Toggling full screen on Android keeps the painter's choice in preferences.
func test_android_fullscreen_toggle_persists_choice() -> void:
    var saved_mode := SaSettings.screen_mode
    var current := [DisplayServer.WINDOW_MODE_MAXIMIZED]

    var get_mode := func() -> DisplayServer.WindowMode: return current[0]
    var set_mode := func(mode: DisplayServer.WindowMode) -> void: current[0] = mode

    var toggle := SaAppCommands.Fullscreen.new(get_mode, set_mode)
    toggle.is_android = true

    toggle.toggle()
    assert_eq(current[0], DisplayServer.WINDOW_MODE_FULLSCREEN, "Toggle moves to full screen")
    assert_eq(SaSettings.screen_mode, "fullscreen", "Preference records fullscreen")

    toggle.toggle()
    assert_eq(current[0], DisplayServer.WINDOW_MODE_MAXIMIZED, "Toggle returns to maximised")
    assert_eq(SaSettings.screen_mode, "maximised", "Preference records maximised")

    SaSettings.screen_mode = saved_mode


## Top bar buttons on Android show the maximize square and hide minimise.
func test_top_bar_window_buttons_on_android() -> void:
    var buttons := SaTopBarWindowButtons.new()
    buttons.os_name_override = "Android"
    buttons.apply_settings()

    assert_true(buttons.maximize_btn.visible, "The maximize square button is visible on Android")
    assert_false(buttons.minimize_btn.visible, "Minimise stays hidden on Android")
    assert_true(buttons.close_btn.visible, "Close stays visible on Android")

    var hint_when_maximised := SaTopBarWindowButtons.maximize_hint("Android")
    assert_true(
        hint_when_maximised == "Fill the screen" or hint_when_maximised == "Restore the window under the system bars",
        "Hint returns an expected phrase"
    )

    buttons.free()
