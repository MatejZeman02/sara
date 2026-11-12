## Sara's full screen on Android is a few rows short of the display, where the
## tablet draws no bands.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A full screen surface of the display's exact height bands on the Adreno 750
## tablet and one eight rows shorter, held to the top, does not. The project
## opens full screen on Android, the desktop opens as before, and the render
## view is laid out short exactly while the mode is full screen. The `AndroidRuntime`
## singleton is a stand-in here that records each call the window would take.
extends "res://tests/test_framework.gd"

const PROJECT_FILE := "res://project.godot"


## The runtime, its activity and the activity's window in one, each call kept
## in order. A runnable is the callable itself, and the UI thread runs it at
## once, which is the order Android keeps for one thread. The methods carry
## Java's names, which is what the window calls, so gdlint lets them be.
class RuntimeStandIn:
    extends RefCounted

    var calls: Array = []

    func getActivity() -> Object:  # gdlint: ignore=function-name
        calls.append("getActivity")
        return self

    func getWindow() -> Object:  # gdlint: ignore=function-name
        calls.append("getWindow")
        return self

    func createRunnableFromGodotCallable(callable: Callable) -> Callable:  # gdlint: ignore=function-name
        calls.append("createRunnable")
        return callable

    func runOnUiThread(runnable: Callable) -> void:  # gdlint: ignore=function-name
        calls.append("runOnUiThread")
        runnable.call()

    func setGravity(gravity: int) -> void:  # gdlint: ignore=function-name
        calls.append("setGravity %d" % gravity)

    func setLayout(width: int, height: int) -> void:  # gdlint: ignore=function-name
        calls.append("setLayout %d %d" % [width, height])

    func getGodot() -> Object:  # gdlint: ignore=function-name
        return self

    func getRenderView() -> Object:  # gdlint: ignore=function-name
        return self

    func getView() -> Object:  # gdlint: ignore=function-name
        return self

    func getParent() -> Object:  # gdlint: ignore=function-name
        return self

    func setPadding(left: int, top: int, right: int, bottom: int) -> void:  # gdlint: ignore=function-name
        calls.append("setPadding %d %d %d %d" % [left, top, right, bottom])

    func setBackgroundColor(_color: int) -> void:  # gdlint: ignore=function-name
        pass

    ## Only the calls that lay the render view out, which is what a reader of
    ## the screen would see.
    func layouts() -> Array:
        return calls.filter(func(c: String) -> bool: return c.begins_with("setPadding"))


func test_android_opens_full_screen_and_the_desktop_as_before() -> void:
    var config := ConfigFile.new()
    assert_eq(config.load(PROJECT_FILE), OK, "project.godot loads")
    assert_eq(
        config.get_value("display", "window/size/mode.android", -1),
        DisplayServer.WINDOW_MODE_FULLSCREEN,
        "Android opens full screen"
    )
    assert_eq(
        config.get_value("display", "window/size/mode", -1),
        DisplayServer.WINDOW_MODE_MAXIMIZED,
        "and the desktop opens maximised as before"
    )
    assert_eq(SaSettings.screen_mode, "fullscreen", "and the kept choice starts as full screen")


func test_full_screen_lays_the_window_out_eight_rows_short_held_to_the_top() -> void:
    var runtime := RuntimeStandIn.new()
    var window := SaAndroidWindow.new(runtime)
    window.follow(DisplayServer.WINDOW_MODE_FULLSCREEN)
    assert_eq(
        runtime.calls,
        ["getActivity", "createRunnable", "runOnUiThread", "getWindow", "setGravity 48", "setLayout -1 -1", "setPadding 0 0 0 8"],
        "Full screen keeps the window whole and the render view eight rows short, held to the top, on the UI thread"
    )


func test_the_shortening_is_asked_for_exactly_when_the_mode_is_full_screen() -> void:
    var runtime := RuntimeStandIn.new()
    var window := SaAndroidWindow.new(runtime)
    window.follow(DisplayServer.WINDOW_MODE_MAXIMIZED)
    assert_eq(runtime.layouts(), [], "A maximised start asks for nothing")
    window.follow(DisplayServer.WINDOW_MODE_FULLSCREEN)
    window.follow(DisplayServer.WINDOW_MODE_FULLSCREEN)
    assert_eq(runtime.layouts(), ["setPadding 0 0 0 8"], "Full screen asks once, however often it is set")
    window.follow(DisplayServer.WINDOW_MODE_MAXIMIZED)
    assert_eq(runtime.layouts(), ["setPadding 0 0 0 8", "setPadding 0 0 0 0"], "Leaving it gives the whole display back")
    window.follow(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
    assert_eq(runtime.layouts().back(), "setPadding 0 0 0 8", "Exclusive full screen is short too")
    window.follow(DisplayServer.WINDOW_MODE_WINDOWED)
    assert_eq(runtime.layouts().back(), "setPadding 0 0 0 0", "and a windowed mode is not")


func test_the_kept_choice_sets_the_mode_and_lays_the_window_out_for_it() -> void:
    var current := [DisplayServer.WINDOW_MODE_FULLSCREEN]
    var sets: Array = []
    var get_mode := func() -> DisplayServer.WindowMode: return current[0]
    var set_mode := func(mode: DisplayServer.WindowMode) -> void:
        sets.append(mode)
        current[0] = mode
    var runtime := RuntimeStandIn.new()
    var window := SaAndroidWindow.new(runtime)

    window.apply_choice("fullscreen", get_mode, set_mode)
    assert_eq(sets, [], "A start already full screen sets no mode")
    assert_eq(runtime.layouts(), ["setPadding 0 0 0 8"], "and is still laid out eight rows short")

    window.apply_choice("maximised", get_mode, set_mode)
    assert_eq(current[0], DisplayServer.WINDOW_MODE_MAXIMIZED, "A kept maximised wins over the project's full screen")
    assert_eq(runtime.layouts().back(), "setPadding 0 0 0 0", "and the window is the whole display")

    window.apply_choice("fullscreen", get_mode, set_mode)
    assert_eq(current[0], DisplayServer.WINDOW_MODE_FULLSCREEN, "Full screen chosen again is full screen")
    assert_eq(runtime.layouts().back(), "setPadding 0 0 0 8", "and eight rows short once more")
    assert_eq(runtime.layouts().size(), 3, "with one layout for each change and none more")


func test_the_full_screen_toggle_keeps_the_choice_the_window_is_laid_out_from() -> void:
    var saved_mode := SaSettings.screen_mode
    var current := [DisplayServer.WINDOW_MODE_FULLSCREEN]
    var get_mode := func() -> DisplayServer.WindowMode: return current[0]
    var set_mode := func(mode: DisplayServer.WindowMode) -> void: current[0] = mode
    var runtime := RuntimeStandIn.new()
    var window := SaAndroidWindow.new(runtime)
    var toggle := SaAppCommands.Fullscreen.new(get_mode, set_mode)
    toggle.is_android = true
    window.apply_choice(SaSettings.screen_mode, get_mode, set_mode)

    toggle.toggle()
    assert_eq(SaSettings.screen_mode, "maximised", "The command out of full screen keeps maximised")
    window.apply_choice(SaSettings.screen_mode, get_mode, set_mode)
    assert_eq(current[0], DisplayServer.WINDOW_MODE_MAXIMIZED, "and the window is maximised")
    assert_eq(runtime.layouts().back(), "setPadding 0 0 0 0", "over the whole display")

    toggle.toggle()
    assert_eq(SaSettings.screen_mode, "fullscreen", "Pressed again it keeps full screen")
    window.apply_choice(SaSettings.screen_mode, get_mode, set_mode)
    assert_eq(current[0], DisplayServer.WINDOW_MODE_FULLSCREEN, "and the window is full screen")
    assert_eq(runtime.layouts().back(), "setPadding 0 0 0 8", "eight rows short")
    SaSettings.screen_mode = saved_mode


func test_off_android_nothing_is_laid_out() -> void:
    var none := SaAndroidWindow.new(null)
    none.follow(DisplayServer.WINDOW_MODE_FULLSCREEN)
    assert_false(none._shortened, "With no runtime full screen lays nothing out")
    assert_eq(SaAndroidWindow.shared()._runtime, null, "and a desktop run has no runtime")
