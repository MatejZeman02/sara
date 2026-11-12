## A note's freeze survives its control being freed.
##
## `SaNoteMode.freeze` waits one frame for the picture, and a menu row rebuilt
## or a docker closed in that frame would leave it reading a freed control: an engine
## error in the console and a note with no subject. The half after the frame is
## `develop`, which a synchronous suite can call with the control already gone,
## because a suite that awaits the frame drops every assertion after the await
## in a synchronous runner.
extends "res://tests/test_framework.gd"

## A real `Window` stands in the tree, the one the note was frozen in.
const REQUIRES_GPU := true

var _host: Control = null
var _mode: SaNoteMode = null
var _window: Window = null
var _control: Button = null
var _list: PopupMenu = null
var _embedding: bool = false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    # Embedding forced for the reason `test_windows_open.gd` gives, and put back
    # after, since it is a user setting.
    _embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    # Not `tree.root`, which is mid-`_ready` when a suite runs.
    _host = Control.new()
    _host.name = "D6FreezeHost"
    EventBus.add_child(_host)
    _mode = SaNoteMode.new()
    _mode.notes_dir = SaDataRoot.path("d6_notes")
    _host.add_child(_mode)
    _window = Window.new()
    _window.size = Vector2i(200, 120)
    _host.add_child(_window)
    _control = Button.new()
    _control.name = "Doomed"
    _window.add_child(_control)
    _list = PopupMenu.new()
    _list.hide_on_item_selection = true


func after_each() -> void:
    _list.free()
    _host.free()
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _embedding


## Stands where `freeze` leaves the mode at its await: the control frozen, the
## list it was taken on hushed, and the mark drawn on the window.
func _frozen_on(control: Control) -> SaNoteOverlay:
    _mode.active = true
    _mode.frozen = control
    _mode.hovered = control
    _mode.menu.hush(_list)
    var mark := SaNoteOverlay.attach_to(_window)
    mark.freeze(Rect2(0, 0, 40, 20), "Doomed")
    return mark


func test_a_control_freed_before_the_frame_drops_the_note_quietly() -> void:
    var mark := _frozen_on(_control)
    var gone: Variant = _control
    _control.free()
    _control = null

    var errors := SaErrorCatcher.new()
    OS.add_logger(errors)
    _mode.develop(gone, _window, Rect2(0, 0, 40, 20))
    OS.remove_logger(errors)

    assert_eq(errors.described([SaErrorCatcher.ERROR]), PackedStringArray(), "No engine error reads the freed control")
    assert_null(_mode.frozen, "The note is dropped, and the mode follows the pointer again")
    assert_null(_mode.hovered, "and holds no freed control for the hover to read")
    assert_eq(_mode.box_text(), "", "No box is open for a note")
    assert_null(mark.box, "and the window carries none")
    assert_false(mark._frozen, "The frozen mark is cleared")
    assert_false(_list.is_blocking_signals(), "The list hears again")
    assert_true(_list.hide_on_item_selection, "and closes on a pick again")


func test_a_window_freed_before_the_frame_drops_the_note_quietly() -> void:
    var control := Button.new()
    _host.add_child(control)
    _frozen_on(control)
    var gone: Variant = _window
    _window.free()
    _window = null

    var errors := SaErrorCatcher.new()
    OS.add_logger(errors)
    _mode.develop(control, gone, Rect2())
    OS.remove_logger(errors)

    assert_eq(errors.described([SaErrorCatcher.ERROR]), PackedStringArray(), "No engine error reads the freed window")
    assert_null(_mode.frozen, "The note is dropped")
    assert_false(_list.is_blocking_signals(), "and the list hears again")


func test_a_later_freeze_keeps_its_own_control() -> void:
    _frozen_on(_control)
    var later := Button.new()
    _window.add_child(later)
    _mode.frozen = later

    _mode.develop(_control, _window, Rect2())

    assert_eq(_mode.frozen, later, "The freeze that took over is left standing")
    assert_false(_list.is_blocking_signals(), "and the first freeze still unhushes the list")
