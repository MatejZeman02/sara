## The activity's window on Android, and Godot's render view inside it a few
## rows shorter than the display while Sara is full screen.
##
## On the Adreno 750 tablet a Vulkan surface of the display's exact full height
## draws bands of rows taken from far to the right, and a surface eight rows
## shorter, held to the top of the display, draws none, as a test app read on
## the tablet showed. The bands follow the surface Godot renders into, so the
## window stays the whole display and the render view's parent, Godot's own
## frame, takes eight rows of padding at its bottom. The render view fills the
## frame less its padding, and the strip below it is the frame's background,
## which is set to the colour of Sara's status line and set again on a theme
## change. A strip outside the window would stay black, since nothing the
## activity paints reaches it.
##
## Godot has no setting for the size of its render view, so the view is laid
## out through the `AndroidRuntime` singleton, on Android's UI thread, where a
## view has to be touched from. The render view is reached as the activity's
## `getGodot().getRenderView().getView()`, all public in Godot's template.
##
## The full screen toggle keeps the painter's choice, and the settings apply
## the choice through here, so one place lays the window out for both.
##
## Off Android there is no runtime, and every layout is a no-op. A suite hands
## the constructor a stand-in for the runtime that records what it was asked.
class_name SaAndroidWindow
extends RefCounted

## How many rows shorter than the display the render view is in full screen.
## Eight is the strip the tablet was read clean with.
const ROWS: int = 8

## `Gravity.TOP` and `LayoutParams.MATCH_PARENT`, the two Android constants the
## window's layout is written in.
const GRAVITY_TOP: int = 48
const MATCH_PARENT: int = -1

## The palette key of the status line's background, the bar the strip lies
## under.
const STRIP_COLOR_KEY: String = "bg_primary"

## The one the toggle and the settings share, made on first use.
static var _shared: SaAndroidWindow = null

## The `AndroidRuntime` singleton, or a stand-in, or null off Android.
var _runtime: Object

## Whether the render view was last laid out short, so a mode set twice lays
## it out once.
var _shortened: bool = false


func _init(runtime: Object) -> void:
    _runtime = runtime
    if _runtime != null:
        EventBus.theme_changed.connect(_on_theme_changed)


## The one Sara's window uses, holding the real runtime on Android and none
## anywhere else.
static func shared() -> SaAndroidWindow:
    if _shared == null:
        var runtime: Object = null
        if Engine.has_singleton("AndroidRuntime"):
            runtime = Engine.get_singleton("AndroidRuntime")
        _shared = SaAndroidWindow.new(runtime)
    return _shared


## Puts the main window in the screen mode the painter chose, "fullscreen" or
## "maximised", and lays it out for it. The layout is asked for even when the
## mode is already right, because the project opens full screen at the
## display's full height.
func apply_choice(choice: String, get_mode: Callable, set_mode: Callable) -> void:
    var target := DisplayServer.WINDOW_MODE_FULLSCREEN if choice == "fullscreen" else DisplayServer.WINDOW_MODE_MAXIMIZED
    if get_mode.call() != target:
        set_mode.call(target)
    follow(target)


## Lays the window out for the mode the main window was just set to: the
## render view short while it is full screen, the whole window otherwise, and
## the window the whole display either way.
func follow(mode: DisplayServer.WindowMode) -> void:
    var full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
    if _runtime == null or full == _shortened:
        return
    _shortened = full
    var rows := ROWS if full else 0
    var color := strip_color()
    var lay_out := func(activity: Object) -> void:
        var window: Object = activity.getWindow()
        if window != null:
            window.setGravity(GRAVITY_TOP)
            window.setLayout(MATCH_PARENT, MATCH_PARENT)
        var frame := _render_frame(activity)
        if frame == null:
            print("SaAndroidWindow: Godot's render view was not reached, so it stays the whole window")
            return
        frame.setPadding(0, 0, 0, rows)
        frame.setBackgroundColor(color)
    var said := "the render view %d rows short of the display" % ROWS if full else "the render view the whole display"
    print("SaAndroidWindow: %s" % said)
    _on_ui_thread(lay_out)


## The status line's colour as the Java int `setBackgroundColor` takes, ARGB
## and signed.
static func strip_color() -> int:
    var argb: int = (SaTheme.palette.get(STRIP_COLOR_KEY) as Color).to_argb32()
    return argb - 0x100000000 if argb >= 0x80000000 else argb


func _on_theme_changed(_theme_id: String) -> void:
    var color := strip_color()
    _on_ui_thread(
        func(activity: Object) -> void:
            var frame := _render_frame(activity)
            if frame != null:
                frame.setBackgroundColor(color)
    )


func _on_ui_thread(work: Callable) -> void:
    var activity: Object = _runtime.getActivity()
    if activity == null:
        return
    var run := func() -> void: work.call(activity)
    activity.runOnUiThread(_runtime.createRunnableFromGodotCallable(run))


## The frame Godot's render view sits in, or null when any step to it is
## missing.
static func _render_frame(activity: Object) -> Object:
    var godot: Object = activity.getGodot()
    if godot == null:
        return null
    var render_view: Object = godot.getRenderView()
    if render_view == null:
        return null
    var view: Object = render_view.getView()
    if view == null:
        return null
    return view.getParent()
