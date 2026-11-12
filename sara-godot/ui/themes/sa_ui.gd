## Global UI Scaling and Icon loading utilities.
@tool
class_name SaUI
extends Object

## Reference DPI for a 1:1 scale (typical 1080p monitor).
const REFERENCE_DPI: float = 96.0

## Ceiling for the X11 DPI guess. Panel DPI is a poor proxy for desktop scale,
## so the inference is capped where over-scaling stops being recoverable.
const MAX_INFERRED_SCALE: float = 2.0

## Android's density for a scale of 1, the dots per inch its dp is measured at.
const ANDROID_REFERENCE_DPI: float = 160.0

## `TypedValue.COMPLEX_UNIT_IN`, the unit `applyDimension` reads as inches.
const ANDROID_COMPLEX_UNIT_IN: int = 4

## The physical dots per inch `_android_dpi()` read, kept so the Java bridge is
## crossed once a run. Written by that function alone, 0 until it has.
static var _android_physical_dpi: float = 0.0

## Base sizes in logical pixels (at 96 DPI / 1× scale).
const BASE_FONT_SIZE: int = 20
const BASE_DRAG_H: int = 20
const BASE_MARGIN: int = 4
const BASE_SEPARATOR: int = 10
const BASE_BTN_H: int = 22
const BASE_TOOL_BTN: int = 40
const BASE_ICON_SIZE: int = 20
const BASE_FACTOR_SLIDER_W: int = 170
const BASE_FACTOR_SLIDER_H: int = 20

## What the Font size slider may ask for. The ceiling is where a top bar row
## stops fitting 1920 logical pixels, which ui/top_bar/tests/test_top_bar_rows.gd measures.
##
## The floor is 0.55 of BASE_FONT_SIZE, 11 points, which is the size the hint
## line under every Preferences row draws at at the default Font size, so the
## floor is the smallest theme text Sara draws rather than a number chosen for a
## docker. A control that asks for a fraction of the theme's size through
## FONT_SCALE_META draws that fraction of it, so a hint at the floor is 8.
##
## The default, `SaSettingsValues.DEFAULT_FONT_SCALE`, is 0.75, 15 points, the
## largest size whose line, 18 pixels of Inter, leaves a pixel or more above and
## below inside a BASE_BTN_H field.
##
## `SaSettingsValues` owns the real numbers, because its own clamp on
## `ui_font_scale` needed them and `core` may not name a class under `ui`. Read
## back here as an alias, because a slider built in `ui/` still types
## `SaUI.MIN_FONT_SCALE` for its bounds.
const MIN_FONT_SCALE: float = SaSettingsValues.MIN_FONT_SCALE
const MAX_FONT_SCALE: float = SaSettingsValues.MAX_FONT_SCALE

## Name of the meta a container sets to ask for spacing tighter than BASE_SEPARATOR.
## The value is a multiplier, so the result still follows the UI scale.
const SEPARATION_SCALE_META: StringName = &"ui_separation_scale"
## What the theme pass last wrote into a container's separation, so the next
## pass can tell its own value from one a caller set.
const APPLIED_SEPARATION_META: StringName = &"ui_separation_applied"

## The fraction of the theme's size the bar's small controls ask for through
## FONT_SCALE_META, the preset group, Edit Brush, a choice among the tool's
## options and the window buttons. Each was built with a fixed 11 pixels the
## theme pass wrote over with its own size, so it drew 20 and never followed the
## slider. Now it draws the 11 pixels it asked for at the default and
## follows the slider from there.
const SMALL_FONT_SCALE: float = 11.0 / (BASE_FONT_SIZE * SaSettingsValues.DEFAULT_FONT_SCALE)

## Name of the meta a control sets to ask for text smaller than BASE_FONT_SIZE,
## as a multiplier, so the result still follows the UI scale.
##
## The pass below writes `font_size` onto every Control it walks, so a plain
## `add_theme_font_size_override` in a builder is put back the next time the
## pass runs, which `ui/main/main.gd` does more than once at startup. That is the
## same trap SEPARATION_SCALE_META exists for, and the same answer: the control
## states the fraction it wants and the pass applies it. Inherited by children,
## so a section sets it once rather than every label in it.
const FONT_SCALE_META: StringName = &"ui_font_scale"

## The user's UI Scale preference, as a multiplier on top of the system scale.
##
## Mirrors SaSettings.ui_scale, which is the persisted value and the only writer,
## and which keeps it at 0.1 or more before it writes here. Cached here so
## this @tool script never has to reach for an autoload.
static var user_scale: float = 1.0

## The user's Font size preference, a multiplier on BASE_FONT_SIZE alone.
##
## Mirrors SaSettings.ui_font_scale, and it is deliberately not part of scale():
## text is the only thing it moves, so a window's geometry, its margins and
## every icon stay the size the UI scale slider left them. That is what keeps
## hard rule 7 intact, since nothing here ever reaches content_scale_factor.
## Its range is MIN_FONT_SCALE to MAX_FONT_SCALE, held by the SaSettings setter
## that writes it.
static var user_font_scale: float = SaSettingsValues.DEFAULT_FONT_SCALE

## Test seam. A positive value replaces the system scale, so scaling can be
## asserted deterministically without a 4K display attached.
##
## **Plain rather than private**. `test_ui_scale.gd` and `test_ui_font.gd`
## are what set it, thirteen lines between them, and each puts it back. The
## privates rule wants a member set from outside to arrive as a constructor
## argument, and this class is never constructed, so the name is the seam and
## this paragraph is what says who may write it.
static var os_scale_override: float = -1.0

## The screen half of the seam above, plain for the same reason and set by the
## same suites. `screen_override` is the screen every window is treated as
## sitting on, and `screen_scales_override` maps a screen to the scale it
## reports, so a window can be walked from a 2x monitor to a 1x one with one
## monitor attached. An empty table and a negative screen are the real display
## server, which is what every run but a suite gets.
static var screen_override: int = -1
static var screen_scales_override: Dictionary = {}

## Meta key recording the factor last applied to a Window, so apply_to_window()
## can rescale geometry by the delta instead of compounding.
const APPLIED_SCALE_META: StringName = &"sa_applied_scale"


## The single scale authority: system scale times the user's preference.
##
## Exactly one thing consumes it, Window.content_scale_factor, set through
## apply_to_window(). UI code sizes everything in logical units and lets the
## window do the scaling. Previously px() scaled every font and margin *and*
## content_scale_factor scaled the viewport, so a 4K display at 2x got both and
## the UI came out twice the intended size.
##
## This is the app-wide answer, for the screen the app calls the current one,
## and it is what a caller with no window in hand should use. A window that is
## being scaled reads its own screen's answer through `scale_for()` instead, so
## a window dragged to a monitor of another scale follows it.
static func scale() -> float:
    return _os_scale() * user_scale


## The scale that applies to `window`, read from the screen it is on.
##
## The main window on a 4K monitor at 2x and the secondary workspace dragged
## to a 1x monitor beside it ask two different questions of the display server,
## and each gets its own answer. A window in no tree has no screen to read, and
## answers for the current one.
static func scale_for(window: Window) -> float:
    return _os_scale(screen_of(window)) * user_scale


## The screen a window is on, which is the screen its scale is read from.
##
## The engine's own answer, `Window.current_screen`, which is the call the rest
## of the tree already asks "which monitor is this on" with: `docker_utils`,
## `sa_popup_rect`, the layout store and the secondary workspace's host all read
## it, rather than the screen holding the window's centre, which needs
## `Window.position` to find that centre, and a native Wayland toplevel is
## given no position by the protocol at all, so every window would answer
## screen 0 on the platform Sara ships on.
##
## -1 for a window that is not in a tree, which is a suite's window and a
## docker's before it is parented, and -1 is what the display server's own
## queries take to mean "the current screen".
static func screen_of(window: Window) -> int:
    if screen_override >= 0:
        return screen_override
    if window == null or not window.is_inside_tree():
        return -1
    return window.current_screen


## What one screen's display server reports, before the user's preference.
##
## The screen is a parameter rather than the current screen alone, which is
## all a single-monitor machine has. On two it is the difference between the window
## under the pointer and the one being scaled.
static func _os_scale(screen: int = -1) -> float:
    if screen_override >= 0:
        screen = screen_override
    if screen_scales_override.has(screen):
        return float(screen_scales_override[screen])
    if os_scale_override > 0.0:
        return os_scale_override

    var reported := DisplayServer.screen_get_scale(screen)
    var os_name := OS.get_name()
    var dpi := _android_dpi(screen) if os_name == "Android" else float(DisplayServer.screen_get_dpi(screen))
    return starting_scale(os_name, DisplayServer.get_name(), reported, dpi)


## The system scale one screen's figures ask for, before the user's preference.
##
## Pure, so a suite can feed it a tablet, a phone and a monitor without one of
## them attached. `os_name` is `OS.get_name()`, `ds_name` the display server's,
## `reported` what the display server calls the screen's scale, and `dpi` the
## screen's dots per inch, the physical figure on Android.
static func starting_scale(os_name: String, ds_name: String, reported: float, dpi: float) -> float:
    # Android reports its density bucket as the scale, and a maker files a 12.7
    # inch tablet of 273 dots per inch under 320, which is 2x and too large
    # for a painter. The density Android's own dp is measured against is 160, so the
    # screen's real dots per inch over 160 is the size Android means a button
    # to be, and on a phone of 429 it is well over 2, big enough for a finger.
    if os_name == "Android":
        return infer_android_scale(dpi)

    if reported > 0.0 and not is_equal_approx(reported, 1.0):
        return reported

    # Wayland and macOS report a real scale, so a reported 1.0 from them is the
    # truth rather than a missing value.
    if ds_name == "Wayland" or ds_name == "macOS":
        return maxf(reported, 1.0)

    # X11 reports no scale, so all that is left is physical DPI, which measures
    # the panel, not how the desktop is scaled. A 4K laptop panel can report
    # 287 DPI while the desktop runs at 2x, and 287/96 rounds to 3, so the
    # raw ratio overshoots badly. Round to whole steps and cap at 2x: guessing too
    # small is a minor annoyance, guessing 3x makes the app unusable.
    #
    # This is a heuristic and X11 is not the supported path, run native Wayland,
    # which reports the real scale.
    return infer_scale_from_dpi(int(dpi))


## Android's guess: dots per inch over 160, in steps of a twentieth, never
## below 1. An unknown figure is 1, the size Android itself assumes.
static func infer_android_scale(dpi: float) -> float:
    if dpi <= 0.0:
        return 1.0
    return maxf(snappedf(dpi / ANDROID_REFERENCE_DPI, 0.05), 1.0)


## The screen's physical dots per inch on Android, read once and kept.
##
## `DisplayServer.screen_get_dpi()` answers Android's `densityDpi`, the bucket,
## which is the very figure that made the tablet 2x. The physical one is the
## `xdpi` field of the display's metrics, and fields cannot be read across the
## Java bridge, so it is asked for as the pixels in one inch,
## `TypedValue.applyDimension(COMPLEX_UNIT_IN, 1, metrics)`, which is `xdpi`.
## Any step of that failing leaves the bucket, which is what Sara read before.
static func _android_dpi(screen: int) -> float:
    if _android_physical_dpi > 0.0:
        return _android_physical_dpi
    var dpi := float(DisplayServer.screen_get_dpi(screen))
    if Engine.has_singleton("AndroidRuntime"):
        var activity: Variant = Engine.get_singleton("AndroidRuntime").call("getActivity")
        var typed_value: Variant = JavaClassWrapper.wrap("android.util.TypedValue")
        if activity != null and typed_value != null:
            var metrics: Variant = activity.call("getResources").call("getDisplayMetrics")
            var inch: Variant = typed_value.call("applyDimension", ANDROID_COMPLEX_UNIT_IN, 1.0, metrics)
            if typeof(inch) == TYPE_FLOAT and float(inch) > 0.0:
                dpi = float(inch)
    _android_physical_dpi = dpi
    return dpi


## The X11 guess, split out so it can be tested without an X11 session.
static func infer_scale_from_dpi(dpi: int) -> float:
    if dpi <= 0:
        return 1.0
    return clampf(roundf(dpi / REFERENCE_DPI), 1.0, MAX_INFERRED_SCALE)


## Logical pixels to OS physical pixels.
##
## Needed only for Window.size, min_size and position: those are in physical
## pixels and are NOT affected by content_scale_factor. Everything inside a
## window stays in logical units.
static func to_physical(logical: int) -> int:
    return int(ceil(logical * scale()))


static func to_physical_v(logical: Vector2i) -> Vector2i:
    var factor := scale()
    return Vector2i(int(ceil(logical.x * factor)), int(ceil(logical.y * factor)))


static func to_logical(physical: int) -> int:
    return int(round(physical / scale()))


## A factor one window asks for on top of the one its kind earns, as metadata on
## the window itself.
##
## The maximise is the only thing that sets it today: a docker filling its host
## draws its interface larger while it is filling it, and takes the factor off
## again when it goes back. Metadata rather than an argument, because
## `apply_to_window` is called from five places that have never heard of
## maximising, and because hard rule 7 keeps one writer for
## `content_scale_factor`. This is how a caller asks that writer for more instead
## of writing the number itself.
const EXTRA_SCALE_META: StringName = &"sa_extra_scale"


## The scale that applies to `window` specifically.
##
## An embedded subwindow is rendered inside the host viewport, which has already
## been scaled, and its size and position are in the host's logical space. Giving
## it its own content_scale_factor scales its contents a second time, and treating
## its size as physical pixels makes it enormous, a docker came out 3070 wide
## inside a 1920-logical viewport. So an embedded window scales by 1 and inherits
## everything from its host. Only a real OS window scales itself.
##
## Times whatever the window asks for on top, which is 1.0 for every window that
## asks for nothing. The base for an OS window is its own screen's scale rather
## than the app-wide one, so the secondary workspace dragged to a 1x monitor is
## at 1x while the window it was opened from stays at 2x.
static func window_scale(window: Window) -> float:
    if window == null:
        return scale()
    var base := 1.0 if window.is_embedded() else scale_for(window)
    return base * extra_scale(window)


## The extra factor `window` is asking for, and 1.0 when it asks for none or asks
## for something that is not a positive number.
static func extra_scale(window: Window) -> float:
    if window == null or not window.has_meta(EXTRA_SCALE_META):
        return 1.0
    var asked := float(window.get_meta(EXTRA_SCALE_META))
    return asked if asked > 0.0 else 1.0


## How many device pixels one logical unit of `window` covers on the screen.
##
## A real OS window's own scale, and for an embedded one its host's times its
## own, because its contents are drawn inside the host's scaled viewport.
static func screen_scale(window: Window) -> float:
    if window == null:
        return scale()
    if not window.is_embedded():
        return window_scale(window)
    var parent := window.get_parent()
    var host := parent.get_window() if parent != null else null
    return (screen_scale(host) if host != null else scale()) * window_scale(window)


## Whether a window at `factor` draws its 2D vertices on whole device pixels.
##
## The engine rasterises each glyph at the window's scale but places it on a
## whole logical pixel, so at a scale of 1.05 or 0.85 every glyph lands between
## device pixels and is filtered soft, and so is the texture an embedded docker
## is drawn from. Snapping the vertices puts both back on the pixel grid. At a
## whole scale logical pixels already are device pixels, and the snap stays off
## there, because it also rounds the feather of an antialiased line.
static func snaps_to_pixels(factor: float) -> bool:
    return not is_equal_approx(factor, roundf(factor))


## Logical size to whatever `window` measures its geometry in.
static func window_size_for(window: Window, logical: Vector2i) -> Vector2i:
    var factor := window_scale(window)
    return Vector2i(int(ceil(logical.x * factor)), int(ceil(logical.y * factor)))


## Apply the current scale to `window`, and rescale its geometry by the change.
##
## Idempotent: calling it twice does not resize the window twice. It runs both at
## window creation and on every scale change, and dockers are re-entered as they
## are shown and hidden, so that matters. A window that has never been scaled
## keeps the geometry its constructor set, which is already physical.
static func apply_to_window(window: Window) -> void:
    if window == null:
        return

    var wanted := window_scale(window)
    # Before the early return, because an embedded docker's own factor stays 1.0
    # while the root's changes, and its snap follows the root's.
    window.snap_2d_vertices_to_pixel = snaps_to_pixels(screen_scale(window))
    var applied: float = window.get_meta(APPLIED_SCALE_META, 0.0)
    if applied > 0.0 and is_equal_approx(applied, wanted):
        return

    window.content_scale_factor = wanted

    # The root window is sized by the OS, so only its content scales. Dockers call
    # this from _init, before they are in the tree, where get_tree() is an error.
    var is_root := window.is_inside_tree() and window == window.get_tree().root
    if applied > 0.0 and not is_root:
        var ratio := wanted / applied
        window.size = Vector2i(roundi(window.size.x * ratio), roundi(window.size.y * ratio))
        window.min_size = Vector2i(roundi(window.min_size.x * ratio), roundi(window.min_size.y * ratio))

    window.set_meta(APPLIED_SCALE_META, wanted)


## Hand every window in `windows` to the one writer above, and report how many
## of them it moved.
##
## This is the follower's tick, and it is a static rather than a method for the
## reason the seams above are: a suite can hand it a window it built to test
## the screen change without a tree, a second monitor or a real OS window.
##
## An embedded window is skipped rather than written, because a subwindow's
## contents are already inside its host's scaled viewport and its geometry is
## the host's logical space, so the write would draw at the wrong size. A
## window that has not moved screen is a no-op inside `apply_to_window`, which
## is what makes a once-a-second sweep of every window cheap.
static func apply_to_windows(windows: Array) -> int:
    var moved := 0
    for window: Window in windows:
        if window == null or not is_instance_valid(window) or window.is_embedded():
            continue
        var before := window.content_scale_factor
        apply_to_window(window)
        if not is_equal_approx(before, window.content_scale_factor):
            moved += 1
    return moved


## Every Window the app has open, the root included and listed once.
##
## The follower walks this rather than each window registering itself, so a
## window that arrives later, the secondary workspace, the brush editor, a
## docker dragged out of the main window, is followed without a line anywhere
## having to remember this class exists.
##
## The walk already yields the root, because a root is a Window, so appending
## it here as well listed it twice and the tick scaled it twice (d3).
static func windows_in(tree: SceneTree) -> Array[Window]:
    var found: Array[Window] = []
    if tree != null and tree.root != null:
        found = all_windows(tree.root)
    return found


## Every Window under `node`, the node itself included. The same walk
## `SaCapture.all_windows` does for the state dump, kept here so the follower
## needs nothing from the capture half.
static func all_windows(node: Node) -> Array[Window]:
    var found: Array[Window] = []
    if node is Window:
        found.append(node as Window)
    for child in node.get_children():
        found.append_array(all_windows(child))
    return found


## The once-a-second tick that keeps every window's scale on the screen it is
## on.
##
## Godot reports no notification when a window is dragged to another monitor,
## and on Wayland the position such a notification would have to be derived
## from is not reported to a client at all, so a poll is what is left. Once a
## second is well under the rate a person notices an interface resizing, and
## each tick costs one display server query per window and then an early return
## from the writer.
##
## Built by `ui/main/main.gd`, the one thing that knows the app is up. Kept beside
## the writer rather than in `ui/`'s controllers, because the whole of it is
## "call the writer", and a file for that is a file with one call in it.
class ScreenFollower:
    extends Node
    ## How long between sweeps. The number is a compromise with the cost of a
    ## sweep, not with an event: a window is dragged at human speed.
    const CHECK_SECONDS: float = 1.0

    var _elapsed: float = 0.0

    func _process(delta: float) -> void:
        _elapsed += delta
        if _elapsed < CHECK_SECONDS:
            return
        _elapsed = 0.0
        var tree := get_tree()
        if tree != null:
            SaUI.apply_to_windows(SaUI.windows_in(tree))


## Logical-pixel helpers.
##
## These are identity functions. Scaling happens once, in
## Window.content_scale_factor, so UI code sizes everything in logical units.
## They are kept because roughly 150 call sites use them and reading `px(20)`
## still says "20 logical pixels" at the call site.
##
## For Window.size, min_size and position, which are physical pixels and are
## not affected by content_scale_factor, use to_physical() instead.
static func px(logical: int) -> int:
    return logical


static func pxf(logical: float) -> float:
    return logical


## The theme built by init_global_theme, so sub-windows can share it.
##
## Plain for the reason `os_scale_override` above is: `test_sa_theme.gd`
## and `test_theme_groups.gd` swap it for a scratch theme and put it back, and
## there is no constructor to hand it to. Everything else reads it directly,
## with no getter in front of it.
static var shared_theme: Theme = null

## Every class the shared theme carries a font size for, so a font size change
## can rewrite the same list rather than build a second theme.
const THEME_FONT_CLASSES := [
    "Label",
    "Button",
    "OptionButton",
    "PopupMenu",
    "TooltipLabel",
    "LineEdit",
    "TextEdit",
    "Tree",
    "ItemList",
    "CheckBox",
    "CheckButton",
    "MenuBar",
    "MenuButton",
    "RichTextLabel",
    "TabBar",
    "TabContainer",
    "Window",
    "Dialog",
    "AcceptDialog",
    "ConfirmationDialog",
    "FileDialog"
]


## Build the project theme and assign it to the root window.
static func init_global_theme(tree: SceneTree) -> void:
    var font_size := get_font_size()
    var theme := Theme.new()
    theme.default_font_size = font_size
    theme.default_font = SaFonts.regular()

    for cls: String in THEME_FONT_CLASSES:
        theme.set_font_size("font_size", cls, font_size)

    theme.set_constant("h_separation", "PopupMenu", px(8))
    theme.set_constant("v_separation", "PopupMenu", px(8))
    theme.set_constant("item_start_padding", "PopupMenu", px(10))
    theme.set_constant("item_end_padding", "PopupMenu", px(10))

    theme.set_constant("separation", "VBoxContainer", px(BASE_SEPARATOR))
    theme.set_constant("separation", "HBoxContainer", px(BASE_SEPARATOR))
    theme.set_constant("separation", "GridContainer", px(BASE_SEPARATOR))

    var icon_max_w := px(BASE_ICON_SIZE)
    for cls: String in ["Button", "CheckBox", "CheckButton", "MenuButton", "OptionButton"]:
        theme.set_constant("icon_max_width", cls, icon_max_w)

    # The palette's own colours on the theme, so a control nobody styled is
    # drawn in it rather than in Godot's white. Here rather than in the list
    # above because the colours are SaTheme's to say, and this file's job is the
    # object they are written onto.
    SaThemeDefaults.paint(theme)

    if tree and tree.root:
        tree.root.theme = theme
        seed_theme(tree.root, theme)

    # Wrapping a tooltip is not a theme item, so the one thing the theme cannot
    # say about `TooltipLabel` is said beside it instead.
    SaTooltip.install(tree)

    # Deliberately does NOT touch ThemeDB.get_default_theme(). That is a
    # process-global engine singleton shared with the editor, the mutation cannot
    # be undone, and it made the default theme a second de-facto scale authority.
    # A Window is a Viewport, so theme does not cross the boundary into sub-windows,
    # DockerWindow assigns this same theme to itself instead.
    shared_theme = theme


## The size every piece of interface text is drawn at, in logical units.
##
## BASE_FONT_SIZE times the Font size preference. The multiplier lives here and
## nowhere else, so a text size is never a second scale authority: the pass below
## and the shared theme are the only two consumers, and neither touches geometry.
static func get_font_size() -> int:
    return maxi(1, int(roundf(float(BASE_FONT_SIZE) * user_font_scale)))


## The fraction of the theme's text that draws *points* at the default Font size.
## A size written as a number of points was fixed and never followed the slider,
## so a site that wants a size of its own states it this way and keeps exactly
## the size it drew before at the default.
static func fraction_of(points: float) -> float:
    return points / (float(BASE_FONT_SIZE) * SaSettingsValues.DEFAULT_FONT_SCALE)


## The size *fraction* of the theme's text is at the current Font size, for text
## a control draws itself and no theme reaches.
static func font_size_for(fraction: float) -> int:
    return maxi(1, roundi(float(get_font_size()) * fraction))


## Gives *control* text at *fraction* of the theme's size, now and after every
## change of the Font size. The meta is what the theme pass in a docker or a bar
## reads, and `refit_text` is what a dialog runs, so the size follows wherever the
## control lives.
static func size_text(control: Control, fraction: float) -> void:
    control.set_meta(FONT_SCALE_META, fraction)
    control.add_theme_font_size_override("font_size", font_size_for(fraction))


## Sizes again every control under *root* that asked for a fraction through
## FONT_SCALE_META, and touches nothing else. A dialog runs this rather than the
## theme pass, which would flatten every hint it has to the theme's size, as
## `SaDialogWindow._on_ui_font_scale_changed` says.
static func refit_text(root: Node) -> void:
    if root is Control and root.has_meta(FONT_SCALE_META):
        var fraction := float(root.get_meta(FONT_SCALE_META))
        (root as Control).add_theme_font_size_override("font_size", font_size_for(fraction))
    for child in root.get_children():
        refit_text(child)


## Rewrites the shared theme for the current Font size preference.
##
## Every window shares one Theme object, so writing the sizes back into it is
## what moves the text a control has no override of its own for. The controls
## that do carry an override are reached by apply_ui_theme, which the title bar,
## the tool options bar and every docker run on themselves when SaSettings
## announces the change.
static func refresh_font_sizes() -> void:
    if shared_theme == null:
        return
    var font_size := get_font_size()
    shared_theme.set_block_signals(true)
    shared_theme.default_font_size = font_size
    for cls: String in THEME_FONT_CLASSES:
        shared_theme.set_font_size("font_size", cls, font_size)
    shared_theme.set_block_signals(false)
    shared_theme.emit_changed()


## Hands *theme* to every Control whose inheritance chain the engine has cut.
##
## Godot propagates a theme down through `Control` and `Window` and stops dead
## at anything else: "theme inheritance chains are broken by nodes that aren't
## Control or Window" is the engine's own comment on it. `scenes/main.tscn`'s
## root is a plain `Node`, so the theme written onto `tree.root` above reached
## the dockers and the dialogs, which each hold their own `Window`, and nothing
## at all in the main window: the menu bar and the tool options bar resolved
## Godot's defaults however the palette read.
##
## The theme is seeded again at each cut rather than that scene root being made
## a Control, because it carries `ui/main/main.gd`, and a Control there would take a
## size, an anchor set and the mouse for a change that is about colours.
##
## Stops at the first Control it reaches down any branch, because the chain
## below one is whole, and steps over a `Window`, which adopts the shared theme
## for itself.
static func seed_theme(node: Node, theme: Theme) -> void:
    if theme == null or node == null:
        return
    if node is Control:
        var parent := node.get_parent()
        if parent != null and not (parent is Control) and not (parent is Window):
            (node as Control).theme = theme
        return
    if node is Window and node.get_parent() != null:
        return
    for child: Node in node.get_children():
        seed_theme(child, theme)


## Apply consistent font sizes and spacing to all text-bearing nodes in `root`.
##
## Seeds the theme first, because a bar rebuilt after the theme pass sits under
## the same plain `Node` that cuts the inheritance chain.
static func apply_ui_theme(root: Node) -> void:
    seed_theme(root, shared_theme)
    var font_size := get_font_size()
    var sep := px(BASE_SEPARATOR)
    _apply_recursive(root, font_size, sep)


## The separation a container should get: the global one, times whatever it asked
## for through SEPARATION_SCALE_META.
##
## This exists because a container could not previously keep its own spacing.
## `ToolOptionsBar._init` overrode the separation to `px(4)` and then called this
## theme pass on the next line, which put it straight back to `px(10)`, and
## `ui/main/main.gd` re-applies the theme twice more. So the line had never had any
## effect, and the bar carried 90 pixels of gap it had not asked for. A plain
## "leave an existing override alone" rule cannot work here, because this pass is
## also what re-applies spacing when the UI scale changes: its own override from
## the previous pass would look exactly like the caller's.
static func _separation_for(node: Node, sep: int) -> int:
    var factor: float = float(node.get_meta(SEPARATION_SCALE_META, 1.0))
    return maxi(1, int(roundf(float(sep) * factor)))


static func _apply_recursive(node: Node, font_size: int, sep: int, font_scale: float = 1.0) -> void:
    var scale_here: float = float(node.get_meta(FONT_SCALE_META, font_scale))
    var size_here: int = maxi(1, int(roundf(float(font_size) * scale_here)))
    if node is Control:
        _override_font_size(node, &"font_size", size_here)

    if node is MenuButton:
        var popup: PopupMenu = (node as MenuButton).get_popup()
        # No `OptionButton` half: a dropdown is an `SaChoiceButton`, whose rows
        # are Sara's own and reached by the recursion like any other child.
        if popup:
            # Through the recursion rather than in here, so a submenu of the
            # popup is styled too: BlendModeButton has one per blend section,
            # and a submenu the pass never reached drew at the engine's default
            # size beside a parent at the theme's. The scale is 1.0 whatever the
            # button's own is, because a popup is a window of its own and the
            # fraction the bar asks for is about the control on the row.
            _apply_recursive(popup, font_size, sep, 1.0)

    if node is PopupMenu or node is MenuBar:
        _override_constant(node, &"h_separation", px(8))
        _override_constant(node, &"v_separation", px(8))
        if node is PopupMenu:
            _override_font_size(node, &"font_size", font_size)
            _override_constant(node, &"item_start_padding", px(10))
            _override_constant(node, &"item_end_padding", px(10))

    if node is VBoxContainer or node is HBoxContainer:
        # Rewritten only when the container still holds what this pass last
        # wrote, or holds nothing. A separation a caller set is left alone
        # through every pass, which is what lets the top bar keep the spacing
        # it asked for rather than a gap of 90 pixels.
        var applied: int = int(node.get_meta(APPLIED_SEPARATION_META, -1))
        var container := node as Control
        var has_own: bool = (
            container.has_theme_constant_override("separation") and int(container.get_theme_constant("separation")) != applied
        )
        if not has_own:
            var wanted := _separation_for(node, sep)
            _override_constant(node, &"separation", wanted)
            node.set_meta(APPLIED_SEPARATION_META, wanted)
    elif node is FlowContainer and node.name != "ToolFlowBox":
        _override_constant(node, &"h_separation", sep)
        _override_constant(node, &"v_separation", sep)

    for child in node.get_children():
        _apply_recursive(child, font_size, sep, scale_here)


## Writes a font size override only when it would change one. Godot re-themes
## the control and queues its layout on every write, the same value included,
## and the pass reaches every control of every docker on a scale change, where
## no size moves, so the writes that change nothing were most of the wait after
## the scale slider was let go. The node is untyped, because a popup is a Window
## and not a Control, and both carry the same override calls.
static func _override_font_size(node: Variant, item: StringName, value: int) -> void:
    if node.has_theme_font_size_override(item) and node.get_theme_font_size(item) == value:
        return
    node.add_theme_font_size_override(item, value)


## The constant half of `_override_font_size`, for the separations and paddings.
static func _override_constant(node: Variant, item: StringName, value: int) -> void:
    if node.has_theme_constant_override(item) and node.get_theme_constant(item) == value:
        return
    node.add_theme_constant_override(item, value)


## Retrieve an icon Texture2D by name from res://assets/icons/.
##
## Deliberately does not fall back to the editor's "EditorIcons" theme: that
## theme is stripped from exported builds, so any icon reached that way works
## while developing and silently disappears in a release. Every icon the UI
## needs must ship in res://assets/icons/, which ui/themes/tests/test_icons.gd enforces.
## A module's icon ships in the module, so a whole `res://` path is taken too.
static func get_icon(icon_name: String) -> Texture2D:
    for path: String in [
        icon_name if icon_name.begins_with("res://") else "",
        "res://assets/icons/" + icon_name.to_lower() + ".svg",
        "res://assets/icons/" + icon_name + ".svg",
    ]:
        if path != "" and ResourceLoader.exists(path):
            var tex := load(path) as Texture2D
            if tex != null:
                return tex
    return null


## Set an icon on `btn` from res://assets/icons/, or fall back to `fallback_text`.
static func set_button_icon(btn: Button, icon_name: String, fallback_text: String = "") -> void:
    var icon := get_icon(icon_name)
    if icon != null:
        btn.icon = icon
        btn.text = ""
        btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
        btn.expand_icon = true
        btn.add_theme_constant_override("icon_max_width", px(BASE_ICON_SIZE))
    else:
        if fallback_text != "":
            btn.text = fallback_text
