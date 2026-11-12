## The strip under Sara's full screen on Android takes the colour of Sara's own
## bottom bar.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The bands the Adreno 750 tablet draws follow the surface Godot renders into,
## so the window stays the whole display and the render view is eight rows
## shorter inside it, which leaves the strip below it to the view's parent,
## coloured as the status line is. The `AndroidRuntime` singleton is a stand-in
## here, and so is each Android object the window reaches through it, each
## keeping the state the calls leave it in.
extends "res://tests/test_framework.gd"

## The display's rows on the tablet, landscape.
const DISPLAY_ROWS := 1840


## One Android object the window reaches, which answers the next one along and
## keeps what it is told. The methods carry Java's names, which is what the
## window calls, so gdlint lets them be.
class AndroidStandIn:
    extends RefCounted

    var next: Object = null
    var window: Object = null
    var layout := Vector2i(-2, -2)
    var gravity: int = 0
    var padding := [0, 0, 0, 0]
    var background: int = 0
    var ui_thread_runs: int = 0

    func _init(following: Object = null, own_window: Object = null) -> void:
        next = following
        window = own_window

    func getActivity() -> Object:  # gdlint: ignore=function-name
        return next

    func createRunnableFromGodotCallable(callable: Callable) -> Callable:  # gdlint: ignore=function-name
        return callable

    func runOnUiThread(runnable: Callable) -> void:  # gdlint: ignore=function-name
        ui_thread_runs += 1
        runnable.call()

    func getWindow() -> Object:  # gdlint: ignore=function-name
        return window

    func getGodot() -> Object:  # gdlint: ignore=function-name
        return next

    func getRenderView() -> Object:  # gdlint: ignore=function-name
        return next

    func getView() -> Object:  # gdlint: ignore=function-name
        return next

    func getParent() -> Object:  # gdlint: ignore=function-name
        return next

    func setGravity(to: int) -> void:  # gdlint: ignore=function-name
        gravity = to

    func setLayout(width: int, height: int) -> void:  # gdlint: ignore=function-name
        layout = Vector2i(width, height)

    func setPadding(left: int, top: int, right: int, bottom: int) -> void:  # gdlint: ignore=function-name
        padding = [left, top, right, bottom]

    func setBackgroundColor(color: int) -> void:  # gdlint: ignore=function-name
        background = color


## The chain from the runtime to the frame the render view sits in: runtime,
## activity, Godot, render view, view and frame, with the activity's window
## beside them.
class Device:
    var frame := AndroidStandIn.new()
    var view := AndroidStandIn.new(frame)
    var render_view := AndroidStandIn.new(view)
    var godot := AndroidStandIn.new(render_view)
    var window := AndroidStandIn.new()
    var activity := AndroidStandIn.new(godot, window)
    var runtime := AndroidStandIn.new(activity)

    ## The rows the render view fills: the window's, the whole display's when
    ## laid out to match its parent, less the frame's padding above and below.
    func view_rows() -> int:
        var window_rows := DISPLAY_ROWS if window.layout.y == SaAndroidWindow.MATCH_PARENT else window.layout.y
        return window_rows - frame.padding[1] - frame.padding[3]


var _saved_theme: String = ""


func before_each() -> void:
    _saved_theme = SaTheme.palette_id


func after_each() -> void:
    SaTheme.use_named(_saved_theme)


## The Java int the frame should hold for the status line's colour now, ARGB
## and signed.
func _bar_color() -> int:
    var argb: int = (SaTheme.palette.get("bg_primary") as Color).to_argb32()
    return argb - 0x100000000 if argb >= 0x80000000 else argb


## A shipped theme whose status line differs from the one in use.
func _other_theme() -> String:
    var now: Color = SaTheme.palette.get("bg_primary")
    for id: String in SaTheme.PALETTES:
        var other := load(SaTheme.PALETTES[id]) as SaPalette
        if other != null and other.get("bg_primary") != now:
            return id
    return ""


func test_full_screen_keeps_the_window_whole_and_the_render_view_eight_rows_short() -> void:
    var device := Device.new()
    var window := SaAndroidWindow.new(device.runtime)
    window.follow(DisplayServer.WINDOW_MODE_FULLSCREEN)
    assert_eq(device.window.layout, Vector2i(-1, -1), "The window is laid out at the display's full size")
    assert_eq(device.window.gravity, SaAndroidWindow.GRAVITY_TOP, "held to the top")
    assert_eq(device.frame.padding, [0, 0, 0, 8], "Godot's frame keeps eight rows free at its bottom only")
    assert_eq(device.view_rows(), 1832, "so the render view is 1832 rows of 1840, held to the top")
    assert_eq(device.activity.ui_thread_runs, 1, "laid out once, on the UI thread")


func test_the_strip_is_the_status_bar_s_colour_and_follows_a_theme_switch() -> void:
    var device := Device.new()
    var window := SaAndroidWindow.new(device.runtime)
    window.follow(DisplayServer.WINDOW_MODE_FULLSCREEN)
    assert_eq(device.frame.background, _bar_color(), "The strip is the status line's colour in the current theme")
    assert_eq(SaAndroidWindow.strip_color(), _bar_color(), "which is the colour the window reads")
    var before := device.frame.background
    var other := _other_theme()
    assert_true(other != "", "A shipped theme has another status line colour")
    SaTheme.use_named(other)
    assert_eq(device.frame.background, _bar_color(), "After a theme switch the strip is the new status line's colour")
    assert_true(device.frame.background != before, "which is not the colour it had")
    assert_eq(device.frame.padding, [0, 0, 0, 8], "and the render view is still eight rows short")


func test_leaving_full_screen_gives_the_render_view_the_whole_window_back() -> void:
    var device := Device.new()
    var window := SaAndroidWindow.new(device.runtime)
    window.follow(DisplayServer.WINDOW_MODE_FULLSCREEN)
    window.follow(DisplayServer.WINDOW_MODE_MAXIMIZED)
    assert_eq(device.window.layout, Vector2i(-1, -1), "Out of full screen the window is the whole display")
    assert_eq(device.frame.padding, [0, 0, 0, 0], "and the frame has no padding")
    assert_eq(device.view_rows(), DISPLAY_ROWS, "so the render view is the whole window")
    window.follow(DisplayServer.WINDOW_MODE_FULLSCREEN)
    assert_eq(device.view_rows(), 1832, "and full screen again is eight rows short once more")


func test_a_render_view_out_of_reach_leaves_the_window_whole() -> void:
    var device := Device.new()
    device.godot.next = null
    var window := SaAndroidWindow.new(device.runtime)
    window.follow(DisplayServer.WINDOW_MODE_FULLSCREEN)
    assert_eq(device.window.layout, Vector2i(-1, -1), "With no render view in reach the window is still the whole display")
    assert_eq(device.frame.padding, [0, 0, 0, 0], "and nothing is padded")
