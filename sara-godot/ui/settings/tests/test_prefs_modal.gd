## Preferences is never modal, in any mode.
##
## A painter must be able to paint with Preferences collapsed to its title
## strip, minimized, or open. Dropping `Window.exclusive` for one state at a
## time is not enough, so Preferences alone stops being exclusive,
## because `Window.exclusive` blocks the parent for as long as the window is
## visible rather than only under what it covers, and `transient` is what keeps
## a page above the window it is about.
##
## The scenario proves the painting on the running app, in the undo history's
## step count. This pins the flag itself, which a screenshot cannot show at all,
## and it pins it in every mode rather than in only the collapsed and
## minimized states.
extends "res://tests/test_framework.gd"

## It opens a real window, and only a run with a RenderingDevice has one.
const REQUIRES_GPU := true


## A Preferences window in the tree, embedded, with a host to free it by.
##
## Embedding is forced the way `test_settings_window_frame.gd` forces it:
## without it `add_child` maps a real OS window and the run blocks until the
## watchdog, and the parent is an autoload because a node mid-`_ready` rejects
## `add_child`.
func _open_window() -> Array:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return []
    var was_embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true

    var host := Node.new()
    host.name = "PrefsModalTestHost"
    EventBus.add_child(host)

    var window := SaSettingsWindow.new()
    host.add_child(window)
    window.show()
    return [window, host, was_embedding]


## Freed here and now rather than queued: a queued free leaves the next test
## opening a second child of the same root while this one is still in the tree,
## which the engine refuses out loud for an exclusive window and which is no
## reason to start queueing them.
func _close_window(opened: Array) -> void:
    if opened.is_empty():
        return
    var window := opened[0] as Window
    if is_instance_valid(window):
        window.hide()
    var host := opened[1] as Node
    host.free()
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = bool(opened[2])


func test_an_open_preferences_is_not_modal() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow
    assert_false(window.exclusive, "An open Preferences lets the canvas beside it have the press")
    assert_true(window.transient, "and stays above the window it is about, which is what transient is for")

    _close_window(opened)


## Rolled up holds for the reason every other mode holds, not for one of its own.
func test_rolling_up_stays_not_modal() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow

    window.frame.toggle_collapsed()
    assert_eq(window.frame.mode, SaSettingsFrame.Mode.COLLAPSED, "The button rolls it up")
    assert_false(window.exclusive, "and a rolled up one lets the canvas underneath have the press")

    _close_window(opened)


## **The assertion to read.** Restoring puts no flag back, because there is
## no flag to put back: a painter who rolls Preferences down to look at the canvas and rolls it
## up again is not asking to be locked out.
func test_restoring_does_not_make_it_modal_again() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow

    window.frame.toggle_collapsed()
    window.frame.toggle_collapsed()
    assert_eq(window.frame.mode, SaSettingsFrame.Mode.NORMAL, "The same button brings it back")
    assert_false(window.exclusive, "and the canvas beside it is still paintable")

    _close_window(opened)


## Maximize is the other way out of normal, and it covers more rather than less.
## It is still not modal: what stops a press reaching the canvas is the pixels
## the window covers, which is what a painter can see and move.
func test_maximize_stays_not_modal() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow

    window.frame.toggle_maximized()
    assert_false(window.exclusive, "A maximized Preferences is not modal either")

    _close_window(opened)


## Three round trips, because each mode change rebuilds the OS window and a
## Godot default drifting back under a rebuild is what `sync_modal` is left for.
func test_the_flag_stays_down_through_every_mode() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow

    for i in 3:
        window.frame.set_mode(SaSettingsFrame.Mode.COLLAPSED)
        assert_false(window.exclusive, "Rolled up, round %d" % (i + 1))
        window.frame.toggle_maximized()
        assert_false(window.exclusive, "Maximized, round %d" % (i + 1))
        window.frame.set_mode(SaSettingsFrame.Mode.NORMAL)
        assert_false(window.exclusive, "Normal, round %d" % (i + 1))

    _close_window(opened)


## A reopen destroys the OS window and builds another, which is where a default
## has the best chance of coming back.
func test_a_reopen_is_still_not_modal() -> void:
    var opened := _open_window()
    if opened.is_empty():
        return
    var window := opened[0] as SaSettingsWindow

    window.hide()
    window.toggle()
    assert_true(window.is_open(), "The window is open again")
    assert_false(window.exclusive, "and it came back not modal")

    _close_window(opened)


## The change reaches Preferences and nothing else, and **the reason is not the
## one decision 8 gives.**
##
## The decision says New Document, Colour Space and the rest stay modal. Read
## against the code they never were: `sa_dialog_window.gd` sets `transient` and
## `borderless` and never touches `exclusive`, no dialog in `ui/` assigns it,
## and Godot's default is false. Preferences was the only exclusive window in
## Sara, so "Preferences alone" is what the change does whether or not the flag
## is written on the base. It is written on the window anyway, because that is
## where a reader looks for it and because the base staying silent is the fact
## this pins.
func test_the_shared_dialog_base_makes_nothing_modal() -> void:
    var dialog := SaDialogWindow.new()
    dialog.name = "PrefsModalProbeDialog"
    assert_false(dialog.exclusive, "A bare dialog off the shared base is not modal")
    dialog.free()

    var source := FileAccess.open("res://ui/dialogs/sa_dialog_window.gd", FileAccess.READ)
    assert_true(source != null, "the base is readable")
    assert_false(source.get_as_text().contains("exclusive"), "and never names the flag")
