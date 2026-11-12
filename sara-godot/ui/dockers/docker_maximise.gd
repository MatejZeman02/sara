## The maximise chord's whole mechanism: what a window goes back to, the button
## that does the same thing with the pointer, and the switch that decides
## whether the button is drawn.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Ctrl+Space toggles the maximise of the docker or dialog in hand, as in
## Blender, and the optional button beside the close button does the same.
##
## **Its own file rather than more of `docker_window.gd`**, by responsibility
## rather than by count: the state a
## maximise keeps belongs to *any* window, and a dialog is not a `DockerWindow`.
## The kept rectangle lives in the window's own metadata for that reason, so the
## same three functions answer for the Layers docker and for the Brush Editor
## without either of them carrying a member the other has never heard of.
class_name SaDockerMaximise

## Where the window was before it filled its host, on the window itself.
##
## Metadata rather than a member of this class, because the state is one per
## window and this file has no instance to hang it on. Metadata is dropped when
## the window is, so nothing here outlives what it describes.
const KEPT_META := &"sa_maximise_kept_rect"

## The switch's place in the profile: the skeleton's own section, beside the
## summon's keys `SaDockerBorrow` keeps there, and for its reason. A property
## of `SaSettingsValues` is where the hide button's switch lives, and that file
## is at the thousand lines `tests/test_file_length.gd` fails a run over.
const MODULE_ID := &"sara-skeleton"
const SWITCH_KEY := &"docker_maximise_button"

## How much larger a maximised window draws its interface.
##
## A quarter again: enough that the Info docker's readings and a layer row's
## text are readable across a room, and small enough that the docker still
## shows what it showed unmaximised, which is the whole point of filling the
## window with it. At twice the size the Info docker's rows start wrapping, so
## a maximise that magnifies more is a maximise that shows less.
##
## Nothing stores it. A maximised docker is not a geometry the painter chose,
## and the factor goes off with the maximise.
const MAXIMISED_SCALE: float = 1.25

## The drag bar button's node name, which `toggle` finds it by in the window it
## was built into.
const BUTTON_NAME := "MaximiseButton"

## The switch, as a property a Preferences row binds to, which is why this
## class is ever made. It holds nothing: it reads and writes the profile, so
## the row and every docker always agree.
var button_on: bool:
    get:
        return button_wanted()
    set(val):
        SaSettings.set_module_preference(MODULE_ID, SWITCH_KEY, val)


## Whether the button is wanted, which is one switch for every docker, on
## Layouts and dockers under Every docker. Off for a new profile.
##
## One switch rather than one on each docker's own page, because a painter who
## wants the button everywhere would otherwise turn it on once per docker.
static func button_wanted() -> bool:
    var stored: Variant = SaSettings.module_preference(MODULE_ID, SWITCH_KEY, false)
    return stored if stored is bool else false


## Whether a name `SaSettings.changed` announced is this switch's, which a
## module's preference is announced under as its id, a slash and its key.
static func names_the_switch(property: StringName) -> bool:
    return property == StringName("%s/%s" % [MODULE_ID, SWITCH_KEY])


## Whether *window* is filling its host right now.
static func is_maximised(window: Window) -> bool:
    return window != null and window.has_meta(KEPT_META)


## The toggle every caller uses: the chord, the button, and the door.
##
## A `DockerWindow` or a `SaDialogWindow` is asked to do it itself, because each
## has to hold `_deriving_geometry` over the resize or its own size tracker
## reads the maximised size back as the size a painter gave it. Any other
## window goes straight to [method toggle], which has nothing to protect.
static func toggle_window(window: Window) -> String:
    if window != null and window.has_method("toggle_maximised"):
        return String(window.call("toggle_maximised"))
    return toggle(window)


## Fills *window*'s host with it, or puts it back where it was, and says which in
## the sentence a capture step prints.
##
## **The host is the same answer the corner grip clamps against**,
## `DockerDragHandle.host_size_of`, so an embedded docker fills the main window
## and a docker a painter has taken out onto a second monitor fills that screen.
## The Reference docker asks for exactly the second of those and names
## this chord as the toggle.
##
## Nothing here saves anything. A maximised docker is not a geometry the painter
## chose, so `DockerLayoutStore.save` steps over one and the stored layout keeps
## the rectangle this remembers.
## **The scale goes on before the rectangle and comes off before it**.
## `SaUI.apply_to_window` rescales `size` and `min_size` by the change in
## factor, which is right for every other caller and would fight the two lines
## below, so it is called first and the rectangle is written over what it left.
## The factor itself is asked for through `SaUI.EXTRA_SCALE_META` rather than
## written here, because `SaUI.apply_to_window()` is the one writer of `content_scale_factor`.
##
## **The button's words follow here rather than in its press**, because the
## chord and the door come through this function too and never touch the
## button, and the words have to say what the next press does whoever pressed
## last.
static func toggle(window: Window) -> String:
    if window == null:
        return "SaCapture: nothing is focused, so there is nothing to maximise"
    if is_maximised(window):
        var kept: Rect2i = window.get_meta(KEPT_META)
        window.remove_meta(KEPT_META)
        window.remove_meta(SaUI.EXTRA_SCALE_META)
        SaUI.apply_to_window(window)
        window.position = kept.position
        window.size = kept.size
        write_tooltip(window.find_child(BUTTON_NAME, true, false) as Button, window)
        return (
            "SaCapture: '%s' back at (%d, %d) %d by %d at %.2f"
            % [window.title, kept.position.x, kept.position.y, kept.size.x, kept.size.y, window.content_scale_factor]
        )
    var host := host_rect(window)
    if host.size == Vector2i():
        return "SaCapture: '%s' has no host to fill" % window.title
    window.set_meta(KEPT_META, Rect2i(window.position, window.size))
    window.set_meta(SaUI.EXTRA_SCALE_META, MAXIMISED_SCALE)
    SaUI.apply_to_window(window)
    window.position = host.position
    window.size = host.size
    write_tooltip(window.find_child(BUTTON_NAME, true, false) as Button, window)
    return (
        "SaCapture: '%s' fills (%d, %d) %d by %d at %.2f"
        % [window.title, host.position.x, host.position.y, host.size.x, host.size.y, window.content_scale_factor]
    )


## The rectangle a maximised *window* fills, in whatever space its `position` is
## measured in: the host viewport from its own corner when embedded, the screen's
## usable rectangle when it is a real OS window.
static func host_rect(window: Window) -> Rect2i:
    var size := DockerDragHandle.host_size_of(window)
    if not window.is_embedded():
        return Rect2i(
            DisplayServer.screen_get_usable_rect(window.current_screen if window.is_inside_tree() else -1).position, size
        )
    return Rect2i(Vector2i.ZERO, size)


## The window the chord answers for: the docker or dialog that holds the
## keyboard, and null when the main window does.
##
## Null rather than a fallback to whichever docker was last in front, and that is
## the whole of what keeps this chord off the quick zoom tool. The zoom tool
## keeps Ctrl+Space, and it is a held gesture over the canvas: a
## painter leaning on it has the main window focused, this answers null, the
## command declines the event and the zoom is untouched.
##
## The walk is untyped and casts to `Window` alone, because a cast to a script's
## own `class_name` inside a static leaks the script and every object it holds.
##
## **An open list answers null as well**. A `Popup` is a `Window` and takes the
## focus when it opens, so otherwise a toolbox flyout would be the answer, and
## the chord would fill the toolbox with the list. Null rather than the docker the list came out
## of, because the list would stay where the docker's button was, at the docker's
## old factor, over a docker that had just moved under it. A press from a focused
## popup reaches the router through `handle_popup_input`, which never hands it to
## the quick tools, so nothing else takes the chord either.
static func focused_window(tree: SceneTree) -> Window:
    if tree == null or tree.root == null:
        return null
    for node in tree.root.find_children("*", "Window", true, false):
        var window := node as Window
        if window != null and window.visible and window.has_focus():
            return null if window is Popup else window
    return null


## The button, built into the drag bar row the hide button already sits in.
##
## Ahead of the hide button rather than after it, so it stands next to the
## close button, which is at the end of the bar in every window Sara draws.
static func build_button(row: Container, window: Window) -> Button:
    var button := SaMake.button(row, BUTTON_NAME)
    write_tooltip(button, window)
    button.flat = true
    button.focus_mode = Control.FOCUS_NONE
    button.custom_minimum_size = Vector2(float(SaUI.px(24)), 0.0)
    SaUI.set_button_icon(button, "window_maximize", "[]")
    button.pressed.connect(func() -> void: toggle_window(window))
    return button


## Writes what *button* does on its next press, from whether *window* is
## maximised now.
##
## Written at every toggle rather than once at build, or the words would be
## wrong half the time a painter reads them. The spelling is the Oxford -ize
## of the English Sara's strings are written in. A dialog's button says window
## rather than docker, in the words Preferences' button always used, and a
## dialog is told from a docker by a method only `SaDialogWindow` has, for the
## leak a cast to a script's class inside a static brings.
static func write_tooltip(button: Button, window: Window) -> void:
    if button == null:
        return
    if window != null and window.has_method("fit_opening_size"):
        if is_maximised(window):
            button.tooltip_text = TranslationServer.translate("Restore the window.")
        else:
            button.tooltip_text = TranslationServer.translate("Maximize the window.")
        return
    if is_maximised(window):
        button.tooltip_text = TranslationServer.translate("Restore this docker.")
    else:
        button.tooltip_text = TranslationServer.translate("Maximize this docker.")


## Shows or hides the button from the one switch.
static func apply_button(button: Button) -> void:
    if button != null:
        button.visible = button_wanted()
