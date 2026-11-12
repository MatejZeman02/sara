## The top bar's three window buttons, which edge they sit on and what they look
## like there. Two settings: the edge and the look are separate choices, both
## Auto by default, because one setting for both would make Left mean Apple's
## traffic lights.
##
## A container that owns its buttons, rather than statics handed the bar on
## every call restyling three buttons the bar holds. The bar places it on its first row and
## hears `close_pressed`, and this moves itself to the row's edge.
class_name SaTopBarWindowButtons
extends HBoxContainer

## The close button was pressed. The bar decides what that means.
signal close_pressed

## The three at the right edge, in the order Windows and GNOME draw them:
## close nearest the corner.
const WINDOWS_ORDER := ["MinimizeBtn", "MaximizeBtn", "CloseBtn"]
## The three at the left edge, macOS's own order and GNOME's with the buttons
## moved left: close nearest the corner again. The order follows the edge, not
## the look.
const MACOS_ORDER := ["CloseBtn", "MinimizeBtn", "MaximizeBtn"]

const MACOS_CLOSE_COLOR := Color(0xff / 255.0, 0x5f / 255.0, 0x57 / 255.0)
const MACOS_MINIMIZE_COLOR := Color(0xff / 255.0, 0xbd / 255.0, 0x2e / 255.0)
const MACOS_ZOOM_COLOR := Color(0x28 / 255.0, 0xc8 / 255.0, 0x40 / 255.0)

var minimize_btn: Button
var maximize_btn: Button
var close_btn: Button

## Set by a test that cannot launch on a real Mac to prove the Auto branch, read
## ahead of `OS.get_name()` when not empty.
##
## **Plain rather than private.** `ui/top_bar/tests/test_top_menu_bar.gd` and
## `ui/top_bar/tests/test_window_button_style.gd` set it, twice each and to a different
## value each time, and a private is written by its own class only. A
## constructor argument, the way to set something from outside, cannot express
## a value that changes halfway through a test, and the two suites are the only
## thing that writes it at all. So it says what it is instead of hiding behind an underscore.
var os_name_override: String = ""


func _init() -> void:
    name = "HBoxWindowControls"
    size_flags_horizontal = SIZE_SHRINK_END
    size_flags_vertical = SIZE_SHRINK_CENTER
    add_theme_constant_override("separation", DockerUtils.px(2))
    minimize_btn = _make("MinimizeBtn", "window_minimize", "-", _minimize, tr("Minimize the window"))
    maximize_btn = _make(
        "MaximizeBtn", "window_maximize", "[]", func() -> void: toggle_maximized(_os_name()), maximize_hint(_os_name())
    )
    close_btn = _make("CloseBtn", "window_close", "X", close_pressed.emit, tr("Close Sara, asking first about unsaved changes"))
    # Read again as the pointer arrives rather than on a signal of the window's,
    # because the hover is the one moment the sentence is read, and the mode can
    # change under the button from the window manager's own title bar.
    maximize_btn.mouse_entered.connect(func() -> void: maximize_btn.tooltip_text = maximize_hint(_os_name()))


## One button: the size, the font, the icon, the handler and the tooltip. The
## tooltip says what a press does, which three glyphs or three coloured dots do
## not, and it stays through either look since neither writes it.
func _make(node_name: String, icon_name: String, fallback: String, callback: Callable, hint: String) -> Button:
    var btn := SaMake.button(self, node_name, fallback, hint)
    btn.custom_minimum_size = Vector2(
        DockerUtils.px(DockerUtils.BASE_ICON_SIZE + 4), DockerUtils.px(DockerUtils.BASE_ICON_SIZE + 2)
    )
    btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    btn.set_meta(SaUI.FONT_SCALE_META, SaUI.SMALL_FONT_SCALE)
    btn.pressed.connect(callback)
    DockerUtils.set_button_icon(btn, icon_name, fallback)
    # The row's own rule, the same one the tool options bar keeps for its
    # buttons: a click here must not leave the keyboard behind it, or the next
    # Space minimises the window a second time instead of panning.
    btn.focus_mode = Control.FOCUS_NONE
    return btn


## "auto" resolves against *os_name*: Left on macOS, Right everywhere else,
## since that is the one thing Sara can tell about a Mac without one on hand to
## launch on.
static func side_for(setting: String, os_name: String) -> String:
    match setting:
        "left":
            return "left"
        "right":
            return "right"
        _:
            return "left" if os_name == "macOS" else "right"


## "auto" resolves against *os_name* the same way: the traffic lights on
## macOS, icon buttons everywhere else.
static func style_for(setting: String, os_name: String) -> String:
    match setting:
        "lights":
            return "lights"
        "icons":
            return "icons"
        _:
            return "lights" if os_name == "macOS" else "icons"


func _os_name() -> String:
    return os_name_override if not os_name_override.is_empty() else OS.get_name()


## Which edge the three sit on, with Auto resolved.
func effective_side() -> String:
    return side_for(SaSettings.window_button_position, _os_name())


## What the three look like, the second of the two settings.
func effective_style() -> String:
    return style_for(SaSettings.window_button_style, _os_name())


## Reads both settings and follows them. Left puts the three at the row's left
## edge ahead of the menu bar, close nearest the corner, and otherwise at the
## right edge past everything else, close nearest that corner. Lights draws them
## as macOS's coloured traffic lights, and otherwise as the icon buttons this
## bar has always drawn.
func apply_settings() -> void:
    var left := effective_side() == "left"
    var order := MACOS_ORDER if left else WINDOWS_ORDER
    for i in order.size():
        move_child(get_node(order[i]), i)
    size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if left else Control.SIZE_SHRINK_END
    var row := get_parent()
    if row != null:
        row.move_child(self, 0 if left else row.get_child_count() - 1)
    # On Android the system owns the window, so minimise is hidden. Full screen
    # stays one press away through the maximise square or View's full screen
    # command, and close stays because it asks about unsaved work.
    var system_owned := _os_name() == "Android"
    minimize_btn.visible = not system_owned
    maximize_btn.visible = true
    if effective_style() == "lights":
        _dot(close_btn, MACOS_CLOSE_COLOR)
        _dot(minimize_btn, MACOS_MINIMIZE_COLOR)
        _dot(maximize_btn, MACOS_ZOOM_COLOR)
    else:
        _restore(close_btn, "window_close", "X")
        _restore(minimize_btn, "window_minimize", "-")
        _restore(maximize_btn, "window_maximize", "[]")


## The icon-and-text button this bar has always drawn, restored after a macOS
## dot may have replaced it.
static func _restore(btn: Button, icon_name: String, fallback: String) -> void:
    btn.custom_minimum_size = Vector2(
        DockerUtils.px(DockerUtils.BASE_ICON_SIZE + 4), DockerUtils.px(DockerUtils.BASE_ICON_SIZE + 2)
    )
    for state: String in ["normal", "hover", "pressed"]:
        btn.remove_theme_stylebox_override(state)
    DockerUtils.set_button_icon(btn, icon_name, fallback)


## A macOS traffic light: a plain coloured dot, no glyph, since the real symbol
## only shows on a real Mac's own hover.
static func _dot(btn: Button, color: Color) -> void:
    btn.icon = null
    btn.text = ""
    var side := float(DockerUtils.px(DockerUtils.BASE_ICON_SIZE))
    btn.custom_minimum_size = Vector2(side, side)
    var dot := StyleBoxFlat.new()
    dot.bg_color = color
    dot.set_corner_radius_all(int(side / 2.0))
    for state: String in ["normal", "hover", "pressed"]:
        btn.add_theme_stylebox_override(state, dot)


static func _minimize() -> void:
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)


## What a press on the maximize button does now, which is the way back once the
## window is maximized, the way a docker's own maximize button reads.
static func maximize_hint(os_name: String = "") -> String:
    var is_android := (
        os_name == "Android" if not os_name.is_empty() else (OS.has_feature("android") or OS.get_name() == "Android")
    )
    if is_android:
        if SaAppCommands.is_fullscreen():
            return TranslationServer.translate("Restore the window under the system bars")
        return TranslationServer.translate("Fill the screen")
    if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED:
        return TranslationServer.translate("Restore the window to its size before it was maximized")
    return TranslationServer.translate("Maximize the window")


## Maximize is a toggle, because the button is the only way back from a
## maximised window when the bar is the whole title bar. A double click on the
## bar's empty part asks the same, through `SaTopBarWindowFrame`, which also
## puts a restored window on the rectangle it kept rather than leaving it the
## screen's size. On Android it toggles between fullscreen and maximised under the
## system bars.
static func toggle_maximized(os_name: String = "") -> void:
    var is_android := (
        os_name == "Android" if not os_name.is_empty() else (OS.has_feature("android") or OS.get_name() == "Android")
    )
    if is_android:
        SaAppCommands.toggle_fullscreen()
        return
    if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED:
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
    else:
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)


## The three buttons as numbers, for the state dump and the suite.
##
## A title bar is forty pixels of a 1920 wide screenshot and the three buttons
## are twelve of those, so which edge they sit on is readable in a PNG and
## their order is not, and whether one is a coloured dot or an icon is not
## either.
func report() -> Dictionary:
    var buttons: Array = []
    for child in get_children():
        var btn := child as Button
        if btn == null:
            continue
        # A macOS traffic light has a stylebox and no icon. The Windows and
        # GNOME button is the other way round, so one flag says which of the two
        # arrangements is drawn without anyone reading a picture.
        var entry := {
            "name": String(btn.name),
            "visible": btn.visible,
            "rect": _rect_of(btn),
            "dot": btn.icon == null and btn.has_theme_stylebox_override("normal"),
            "dot_color": _dot_color_of(btn),
        }
        buttons.append(entry)
    var row := get_parent()
    return {
        "setting": SaSettings.window_button_position,
        "side": effective_side(),
        "style_setting": SaSettings.window_button_style,
        "style": effective_style(),
        "order": buttons.map(func(b: Dictionary) -> String: return b["name"]),
        "buttons": buttons,
        # Whether the group is the first or the last thing on the row, which is
        # what "ahead of the menu bar" means as an index.
        "index_in_row": get_index() if row != null else -1,
        "row_children": row.get_child_count() if row != null else 0,
    }


static func _rect_of(control: Control) -> Dictionary:
    var r := control.get_global_rect()
    return {"x": r.position.x, "y": r.position.y, "w": r.size.x, "h": r.size.y}


## The traffic light's colour as a hex string, or "" for an icon button, so the
## dump says red, amber and green rather than only that three dots are drawn.
static func _dot_color_of(btn: Button) -> String:
    var box := btn.get_theme_stylebox("normal") as StyleBoxFlat
    if btn.icon != null or box == null or not btn.has_theme_stylebox_override("normal"):
        return ""
    return "#" + box.bg_color.to_html(false)
