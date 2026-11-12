## The Preferences window's frame: the size it opens at, and the maximize and
## minimize buttons in its title bar.
##
## **Maximize is the chord's.** The button is the dialog's own maximise,
## `SaDockerMaximise`'s, shown here, so a press fills Sara's window exactly as
## Ctrl+Space over Preferences does and a second press, or the chord, puts it
## back, so the same word on the strip and on the keyboard gives one window.
##
## Its own file because the window script is the page list and the page
## switching, and `ui/settings/tests/test_settings_pages.gd` holds that file under 300 lines
## on purpose.
##
## **Minimize is two different things, and which one depends on one preference.**
## It was first a roll-up for both, and the running app says why.
##
## With Embed subwindows on, Preferences is an embedded subwindow and its
## `get_window_id()` is the host's: the capture reads 0 for both, so
## `window_set_mode(WINDOW_MODE_MINIMIZED)` there is a request about the whole of
## Sara. The roll-up was right, and minimize rolls the window up to its title
## bar.
##
## With it off, Preferences is a real OS window with an id of its own, and the
## same call does minimize it and nothing else. A borderless transient
## window has no taskbar entry, and the chord is what gets it back:
## Ctrl+comma and Edit > Preferences both reach `toggle()`, and the capture reads
## the window windowed and visible again after one. So a real window really
## minimizes.
##
## Both states are `Mode.COLLAPSED`, because both mean "out of the way and one
## gesture from coming back", and the button's tooltip says which one it is
## about to do.
@tool
class_name SaSettingsFrame
extends RefCounted

## The two states the minimize button switches between. Maximized is not one of
## them: it is `SaDockerMaximise`'s, read with `is_maximised`, because the chord
## reaches it without this frame.
enum Mode { NORMAL, COLLAPSED }

## Logical margin kept clear around the window when it is fitted to its host, so
## a default that is larger than the screen still shows its own edges. Both sides
## together, and the same margin every other dialog keeps: it was 40 where the
## dialogs kept 24 a side, so Preferences fitted to one room and the dialog fit a
## frame later to another.
const HOST_MARGIN: int = 2 * SaDialogWindow.HOST_MARGIN

var mode: Mode = Mode.NORMAL

var maximize_button: Button = null
var minimize_button: Button = null

var _window: SaDialogWindow = null

## Where to come back to from a roll-up. Written every time normal is left, and a
## maximized window is put back before it is, so one maximized and then rolled
## up still restores to the size a person chose.
var _normal_rect := Rect2i()


## Builds the minimize button into the window's title bar and shows the
## maximize the dialog already has, both left of Close.
##
## The maximize keeps the name it had when this frame built it, because the
## scenarios that open Preferences wide click it by that name.
func attach(window: SaDialogWindow) -> void:
    _window = window
    var row := window.close_button.get_parent() as HBoxContainer
    if row == null:
        return

    minimize_button = _make_button("MinimizeButton", "window_minimize", "-", tr("Minimize"))
    minimize_button.pressed.connect(toggle_collapsed)
    row.add_child(minimize_button)

    maximize_button = window.maximise_button
    maximize_button.name = "MaximizeButton"
    maximize_button.visible = true
    window.maximise_toggling.connect(_leave_the_roll_up)

    # Close stays nearest the corner, the order GNOME and Windows both draw.
    row.move_child(minimize_button, maximize_button.get_index())


## One title bar button, chromed the way the close button beside it is.
func _make_button(button_name: String, icon: String, fallback: String, tip: String) -> Button:
    var button := SaMake.button(null, button_name, "", tip)
    button.flat = true
    button.focus_mode = Control.FOCUS_NONE
    button.custom_minimum_size = Vector2(float(SaUI.px(24)), 0.0)
    SaUI.set_button_icon(button, icon, fallback)
    return button


## What the maximize button does, for a caller that has no pointer.
func toggle_maximized() -> void:
    SaDockerMaximise.toggle_window(_window)
    sync_tooltips()


func toggle_collapsed() -> void:
    set_mode(Mode.NORMAL if mode == Mode.COLLAPSED else Mode.COLLAPSED)


## A maximize or a restore asked of a rolled-up window gives the window back
## first, or the chord would keep the title strip as the rectangle to restore
## and fill the window with a page it hides.
func _leave_the_roll_up() -> void:
    if mode == Mode.COLLAPSED:
        set_mode(Mode.NORMAL)


## Moves the window between its two states, and nothing else here writes
## geometry.
##
## A maximized window is put back first, whichever state is asked for, so a
## roll-up keeps the person's rectangle and not the filled one, a scale change
## ends the maximize as it ends the roll-up, and the chord's extra scale never
## outlives it.
func set_mode(target: Mode) -> void:
    if _window == null:
        return
    if SaDockerMaximise.is_maximised(_window):
        _window.toggle_maximised()
    if target == mode:
        sync_tooltips()
        return
    if mode == Mode.NORMAL:
        _normal_rect = Rect2i(_window.position, _window.size)
    mode = target

    match target:
        Mode.NORMAL:
            _window.min_size = SaUI.window_size_for(_window, _window.logical_min_size)
            _window.position = _normal_rect.position
            _window.size = _normal_rect.size
        Mode.COLLAPSED:
            if not _window.is_embedded():
                # `Window.mode` rather than `DisplayServer.window_set_mode`,
                # which is the seam first missed. The DisplayServer call takes a
                # window id, and an embedded Preferences shares the host's: the
                # capture reads 0 for both, so that call is a request about
                # Sara. This one is a property of this node, and Godot ignores
                # it while the window is embedded, so the wrong window cannot be
                # reached by it at all.
                _window.mode = Window.MODE_MINIMIZED
                sync_modal()
                sync_tooltips()
                return
            # The minimum has to come down first, or the window refuses to lose
            # the height and comes out a full-size window with no content in it.
            var bar := bar_height()
            _window.min_size = Vector2i(_window.min_size.x, bar)
            _window.size = Vector2i(_window.size.x, bar)

    var open := target != Mode.COLLAPSED
    if _window.content != null:
        _window.content.visible = open
    if _window.resizer != null:
        _window.resizer.visible = open
    sync_modal()
    sync_tooltips()


## Preferences is never modal, in any mode.
##
## One value rather than a rule written from the mode, because a painter paints
## beside Preferences whether it is open, rolled up or minimized, and this holds
## it against a mode change putting a modal flag back.
##
## **Kept rather than deleted, and the flag written rather than assumed.**
## `hide()` destroys the OS window and `popup_centered()` builds another, the
## frame's own modes each rebuild it, and a Godot default drifting under a
## rebuild is exactly the kind of thing a screenshot cannot show. One line that
## says "never" at each of those seams costs nothing and is the invariant
## `ui/settings/tests/test_prefs_modal.gd` reads back.
func sync_modal() -> void:
    if _window == null:
        return
    if _window.exclusive:
        _window.exclusive = false


## Whether the OS has this window minimized, which only a real window can be.
## An embedded subwindow shares the host's id, so asking about it would answer
## about Sara.
func is_os_minimized() -> bool:
    if _window == null or not _window.is_inside_tree() or _window.is_embedded():
        return false
    return _window.mode == Window.MODE_MINIMIZED


## Puts a minimized window back to a windowed one, and nothing else.
##
## Its own call because `hide()` destroys the OS window and `popup_centered()`
## builds another, and `Window.mode` is carried across: without this the window
## comes back minimized, which the capture caught and a reading of the code
## would not have.
func clear_os_minimize() -> void:
    if _window != null and not _window.is_embedded() and _window.mode == Window.MODE_MINIMIZED:
        _window.hide()
        _window.mode = Window.MODE_WINDOWED
        if mode == Mode.COLLAPSED:
            mode = Mode.NORMAL
        sync_modal()
        sync_tooltips()


## The title bar's own height, in whatever units this window measures itself in.
##
## The bar is a PanelContainer that grows with the title font, so the constant
## is a floor rather than the answer, and a Control's height is in the window's
## content space while `Window.size` is physical for a real OS window.
func bar_height() -> int:
    if _window == null or _window.drag_handle == null:
        return SaUI.px(SaUI.BASE_DRAG_H)
    var logical := maxf(_window.drag_handle.size.y, _window.drag_handle.get_combined_minimum_size().y)
    return maxi(1, roundi(logical * _window.content_scale_factor))


## What the window is fitted to: the host viewport for an embedded subwindow,
## the screen's usable rect for a real OS window, both below the main window's
## top bar. A maximize fills `SaDockerMaximise.host_rect`, the whole window.
##
## An embedded subwindow's position is measured inside its host viewport, so its
## own origin is that viewport's, and asking DisplayServer for a screen would
## answer about the host window instead. The embedded host is the dialog's own,
## the one every other dialog is kept in, and the bar comes off both through
## `SaDialogWindow.below_the_bar`: Preferences sat over the menu bar at y 20 at
## an interface scale of 2, and a maximized one covered the menus.
func host_rect() -> Rect2i:
    if _window == null:
        return Rect2i()
    if _window.is_embedded():
        return _window.host_rect()
    return _window.below_the_bar(DisplayServer.screen_get_usable_rect(host_screen()))


## The screen a real OS window opens on: its own once the display server knows
## it, before that the screen of the window that opens it, and the main
## window's when nothing does.
##
## A real window gets its display server id when it is first shown, and `_ready`
## fits Preferences to its host before that. Asking about the unknown id logs
## `INVALID_SCREEN` on every launch with subwindows off and measures whatever
## screen the error returns. The opener's screen is where the window then
## appears, because it is transient to that window and centred on it.
func host_screen() -> int:
    var id := _window.get_window_id()
    if id != DisplayServer.INVALID_WINDOW_ID:
        return DisplayServer.window_get_current_screen(id)
    var opener := _opener_of(_window)
    while opener != null:
        var opener_id := opener.get_window_id()
        if opener_id != DisplayServer.INVALID_WINDOW_ID:
            return DisplayServer.window_get_current_screen(opener_id)
        opener = _opener_of(opener)
    return DisplayServer.window_get_current_screen(DisplayServer.MAIN_WINDOW_ID)


## The nearest window above *window*, or null outside the tree.
static func _opener_of(window: Window) -> Window:
    var parent := window.get_parent()
    return parent.get_window() if parent != null and parent.is_inside_tree() else null


## Shrinks the window to fit the host it opens in, never grows it.
##
## The default size is chosen for a page rather than for a screen, so on a small
## display it would otherwise open with its own resize corner off the bottom.
## Growing here as well would undo a size the person had deliberately dragged
## smaller, which is what a window is expected to remember.
func fit_to_host() -> void:
    if _window == null or mode != Mode.NORMAL or SaDockerMaximise.is_maximised(_window):
        return
    var host := host_rect()
    if host.size.x <= 0 or host.size.y <= 0:
        return
    var margin := SaUI.window_size_for(_window, Vector2i(HOST_MARGIN, HOST_MARGIN))
    var room := host.size - margin
    var wanted := _window.size
    _window.size = Vector2i(maxi(mini(wanted.x, room.x), _window.min_size.x), maxi(mini(wanted.y, room.y), _window.min_size.y))

    # Shrinking leaves a window that popup_centered had just centred hanging off
    # the bottom right, so the corner it was pushed past comes back into range.
    var last := host.position + host.size - _window.size
    if last.x >= host.position.x and last.y >= host.position.y:
        _window.position = _window.position.clamp(host.position, last)

    # The minimize button's tooltip depends on whether this window is embedded,
    # and that answer changes under it when the preference is flipped. This runs
    # on every re-show, which is the moment after the window is rebuilt.
    sync_tooltips()


## Reads the settings title bar: its two buttons, and what the display server
## says about minimising this window, `{"prefs_frame": {...}}`.
##
## `{"probe": true}` reports the ids and the modes without touching anything.
## `{"os_minimize": true}` calls `DisplayServer.window_set_mode` the way it was
## once said it could not be called, reports what both windows became, and puts
## them back, which tests that reasoning against the running app rather than on
## paper.
static func capture_frame(tree: SceneTree, spec: Variant) -> String:
    var window := tree.root.find_child("SaSettingsWindow", true, false) as Window
    if window == null:
        return "SaCapture: no Preferences window"
    var wanted: Dictionary = spec if spec is Dictionary else {}
    var frame_state: SaSettingsFrame = window.get("frame")
    var lines := PackedStringArray(
        [
            (
                "SaCapture: prefs frame mode %s, embedded %s, os minimized %s, window id %d, root id %d"
                % [
                    (
                        "maximized"
                        if SaDockerMaximise.is_maximised(window)
                        else _mode_name(frame_state.mode if frame_state != null else Mode.NORMAL)
                    ),
                    "yes" if window.is_embedded() else "no",
                    "yes" if frame_state != null and frame_state.is_os_minimized() else "no",
                    window.get_window_id(),
                    tree.root.get_window_id()
                ]
            ),
            (
                "  borderless %s, transient %s, exclusive %s, minimize button says '%s'"
                % [
                    window.borderless,
                    window.transient,
                    window.exclusive,
                    (
                        frame_state.minimize_button.tooltip_text
                        if frame_state != null and frame_state.minimize_button != null
                        else ""
                    )
                ]
            )
        ]
    )

    if wanted.get("os_minimize", false):
        var id := window.get_window_id()
        var root_id := tree.root.get_window_id()
        var before := DisplayServer.window_get_mode(root_id)
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED, id)
        lines.append(
            (
                "  after window_set_mode(MINIMIZED, %d): that window is %d, the root is %d, it was %d"
                % [id, DisplayServer.window_get_mode(id), DisplayServer.window_get_mode(root_id), before]
            )
        )
        # Both, always, and in this order: a probe that leaves Sara minimized
        # takes the rest of the scenario with it.
        DisplayServer.window_set_mode(before, root_id)
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED, id)
        lines.append(
            (
                "  restored: that window is %d, the root is %d"
                % [DisplayServer.window_get_mode(id), DisplayServer.window_get_mode(root_id)]
            )
        )

    if wanted.get("reopen", false):
        # One press of Ctrl+comma, which is the only way back a borderless
        # transient window has and the whole of what there was to measure.
        window.call("toggle")
        lines.append(
            (
                "  after one toggle: visible %s, window mode %d, os minimized %s"
                % [window.visible, window.mode, "yes" if frame_state != null and frame_state.is_os_minimized() else "no"]
            )
        )

    if wanted.get("minimize", false) and frame_state != null:
        frame_state.toggle_collapsed()
        lines.append(
            (
                "  after the title bar's button: mode %s, size %s, os minimized %s, exclusive %s"
                % [_mode_name(frame_state.mode), window.size, "yes" if frame_state.is_os_minimized() else "no", window.exclusive]
            )
        )
    return "\n".join(lines)


static func _mode_name(value: int) -> String:
    return ["normal", "rolled up"][value] if value >= 0 and value < 2 else str(value)


## The button says what pressing it does now, and which of the two things
## minimize is here: a roll-up for an embedded window, a real minimize for a
## window of its own. A painter who has just made Preferences vanish needs to
## read where it went before they press it, so the tooltip names the way back.
func sync_tooltips() -> void:
    SaDockerMaximise.write_tooltip(maximize_button, _window)
    if minimize_button == null:
        return
    if mode == Mode.COLLAPSED:
        minimize_button.tooltip_text = tr("Restore the window.")
    elif _window != null and not _window.is_embedded():
        minimize_button.tooltip_text = tr("Minimize. Ctrl+comma brings Preferences back.")
    else:
        minimize_button.tooltip_text = tr("Roll up to the title bar.")
