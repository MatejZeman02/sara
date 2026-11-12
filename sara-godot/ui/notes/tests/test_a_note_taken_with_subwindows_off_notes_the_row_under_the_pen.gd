## A note taken with subwindows off notes the row under the pen.
##
## Under WinTab: the Help list open, Ctrl+Shift+C, the pen on Manual and a tap.
## Three faults are guarded. The first try must not freeze "Note on Control", the
## canvas under the list, nor log `under_pointer`'s argument 2 as previously
## freed every frame until the pen moved, which happened when the window the last
## motion went to was the note box of the try before, freed with its note. The
## next try must not log `Rect2 size is negative` as the note begins and as it is
## cancelled, the view being mirrored. And no start may log `Unexpected NUL
## character`, which is the list's type-ahead making a letter of Ctrl and of
## Shift.
##
## The lists are embedded here, because a window of its own maps a real OS
## window and blocks the run (`test_a_dropdown_is_drawn_inside_the_window.gd`).
## What subwindows off does to the tap is that the main window can hear it, so
## the tap is handed to a window standing in for the main one, at the point
## the list covers. The let-out half is
## `scenarios/a-note-taken-with-subwindows-off-notes-the-row-under-the-pen.json`.
extends "res://tests/test_framework.gd"

## Real windows, a live canvas and the note's picture, which is a readback.
const REQUIRES_GPU := true

## Where the Help list stands on the 1280 by 1024 screen, under its title.
const LIST_AT := Rect2i(741, 30, 265, 298)

## The eight rows of the Help list, in its order, Manual the third.
const HELP_ROWS: Array[StringName] = [&"welcome", &"shortcuts", &"manual", &"documents", &"report", &"agent", &"note", &"about"]
const HELP_LABELS: Array[String] = [
    "Welcome",
    "Keyboard Shortcuts",
    "Manual",
    "Documents",
    "Report a Problem",
    "Connect an Agent",
    "Take a Note",
    "About Sara",
]

## What each of the three faults logged, a line apiece.
const FREED := "previously freed"
const NEGATIVE := "Rect2 size is negative"
const NUL := "Unexpected NUL character"
## What a case reads off its catcher. The script error of a freed argument
## arrives as an error, and the Unicode parser's complaint as an error message,
## so both halves are read.
const ERRORS_AND_PRINTERR: Array[String] = [
    SaErrorCatcher.ERROR, SaErrorCatcher.SCRIPT, SaErrorCatcher.SHADER, SaErrorCatcher.PRINTED_AS_ERROR
]


## The mode, with the windows it marks named rather than walked from the root.
## The runner's root is in the middle of its `_ready` while a suite runs and
## refuses a child, and the mode puts a mark on every window it walks.
class HostedMode:
    extends SaNoteMode

    var marked: Array[Window] = []

    func _windows() -> Array:
        var found: Array = []
        for window in marked:
            if is_instance_valid(window) and window.visible:
                found.append(window)
                found.append_array(_all_windows(window))
        return found


var _host: Node = null
var _main: Window = null
var _canvas_window: Window = null
var _canvas: SaCanvas = null
var _mode: HostedMode = null
var _notes_dir := ""
var _embedding: bool = true
var _holder: StringName = &""


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    # Embedding forced for the reason the header gives, and put back after,
    # since it is a user setting.
    _embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _holder = ToolMachine.pointer_holder
    # Not `tree.root`, which is mid-`_ready` when a suite runs.
    _host = Node.new()
    _host.name = "D8NoteHost"
    EventBus.add_child(_host)
    _main = Window.new()
    _main.name = "D8MainWindow"
    _main.borderless = true
    _main.size = Vector2i(1280, 1024)
    _host.add_child(_main)
    _main.show()
    # What the main window has under the list: the lost note was "Note on
    # Control", the canvas's own Control, which reaches under the whole window.
    var under := Control.new()
    under.name = "Control"
    under.set_anchors_preset(Control.PRESET_FULL_RECT)
    _main.add_child(under)
    under.size = Vector2(_main.size)
    _notes_dir = ProjectSettings.globalize_path(SaDataRoot.folder()).path_join("d8-notes-%d" % Time.get_ticks_usec())
    _mode = HostedMode.new()
    _mode.notes_dir = _notes_dir
    _mode.marked = [_main]
    _host.add_child(_mode)


func after_each() -> void:
    if _mode != null and _mode.active:
        _mode.stop()
    ToolMachine.pointer_holder = _holder
    if _host != null:
        _host.free()
        _host = null
    _main = null
    _canvas = null
    _canvas_window = null
    _mode = null
    _remove_notes()
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _embedding


## The Help list as the top bar builds it, open at its place and laid out.
func _open_help() -> SaChoicePopup:
    var help := SaChoicePopup.new(true, false)
    help.name = "HelpMenu"
    for at in HELP_ROWS.size():
        if HELP_ROWS[at] == &"about":
            help.add_gap()
        help.add_row(HELP_ROWS[at], HELP_LABELS[at])
    _host.add_child(help)
    help.popup(LIST_AT)
    _lay_out(help)
    return help


## The layout a frame would give the rows, given now, because the runner is
## synchronous and an awaited assertion is a dropped one. Top down, so
## each container sorts inside the rectangle its parent has just handed it.
func _lay_out(node: Node) -> void:
    if node is Container:
        node.notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child in node.get_children(true):
        _lay_out(child)


## Where *row* of *help* is on the main window: its middle, in `_main`'s space.
func _on_main(help: SaChoicePopup, row: StringName) -> Vector2:
    var middle := help.row_of(row).get_global_rect().get_center()
    var rect := SaCursorPolicy.rect_in(_main, help)
    return rect.position + middle * rect.size / help.get_visible_rect().size


## A canvas the view mirrors left to right, in a window of its own.
##
## With no tool machine, because a machine publishes its cursor into the
## policy's statics, which outlive the suite. Clearing them after a machine
## can let go of a brush an earlier suite's `Main` had left there, and the
## brush's pattern kernels then outlived the shader compiler at exit, a script
## error that failed the run.
func _mirrored_canvas() -> void:
    _canvas_window = Window.new()
    _canvas_window.borderless = true
    _canvas_window.size = Vector2i(1280, 1024)
    _host.add_child(_canvas_window)
    _canvas_window.show()
    _canvas = SaCanvas.new()
    _canvas.canvas_size = Vector2i(256, 256)
    _canvas_window.add_child(_canvas)
    _canvas.size = Vector2(1280, 1024)
    # The view's own mirror, the one H flips, about the middle it keeps still.
    SaCanvasView.for_canvas(_canvas).flip_view(true)


## Ctrl+Shift+C as the keyboard delivers it, a press at a time, to *list*.
func _chord_over(list: SaChoicePopup) -> void:
    var chord: Array[Key] = [KEY_CTRL, KEY_SHIFT, KEY_C]
    for at in chord.size():
        var key := InputEventKey.new()
        key.keycode = chord[at]
        key.physical_keycode = chord[at]
        key.pressed = true
        key.ctrl_pressed = at >= 1 or chord[at] == KEY_CTRL
        key.shift_pressed = at >= 2 or chord[at] == KEY_SHIFT
        list._input(key)


func _motion(at: Vector2) -> InputEventMouseMotion:
    var motion := InputEventMouseMotion.new()
    motion.position = at
    motion.global_position = at
    return motion


func _press(at: Vector2) -> InputEventMouseButton:
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = at
    press.global_position = at
    return press


func _remove_notes() -> void:
    if _notes_dir.is_empty() or not DirAccess.dir_exists_absolute(_notes_dir):
        return
    for folder in DirAccess.get_directories_at(_notes_dir):
        var inside := _notes_dir.path_join(folder)
        for file in DirAccess.get_files_at(inside):
            DirAccess.remove_absolute(inside.path_join(file))
        DirAccess.remove_absolute(inside)
    DirAccess.remove_absolute(_notes_dir)


## The whole path from the chord to the written note, the Help list closed and freed
## between the hover and the tap and opened again, and the tap heard by the
## main window at a point the new list covers. The third line, the negative
## rectangle, needs a mirrored view under a tool machine, and is the last test's.
func test_w6_notes_manual_and_writes_it_and_logs_nothing() -> void:
    var errors := SaErrorCatcher.new()
    OS.add_logger(errors)

    var first := _open_help()
    _mode.marked = [_main, first]
    _chord_over(first)
    _mode.start()
    # The pen over Manual: the motion goes to the list, and the mark with it.
    _mode.handle_window_input(_motion(first.row_of(&"manual").get_global_rect().get_center()), first)
    _mode.menu.take(SaNoteMenu.item_of(first, first.row_of(&"manual")))
    assert_eq(_mode.menu.tag(), "Manual, item 3 of 8", "The mark is on Manual")

    first.hide()
    first.free()
    _mode._process(0.0)
    assert_null(_mode._pointer_window, "The freed list is let go of rather than handed on")

    var help := _open_help()
    _mode.marked = [_main, help]
    var tapped := _on_main(help, &"manual")
    assert_true(_mode.handle_window_input(_press(tapped), _main), "The tap the main window heard is the note's")
    assert_eq(_mode.frozen, help.row_of(&"manual"), "and it froze on Manual, not on the canvas under the list")
    assert_eq(_mode.menu.window, help, "in the list that was open")
    # The half of the freeze after the frame, which a synchronous suite calls
    # itself (`test_a_notes_freeze_survives_its_control_being_freed.gd`).
    _mode.develop(_mode.frozen, _main, help.row_of(&"manual").get_global_rect())
    assert_false(help.visible, "The list is closed once the picture is taken")
    var path := _mode.save("Manual should open the manual")
    OS.remove_logger(errors)

    assert_false(path.is_empty(), "The note is written")
    var written := FileAccess.get_file_as_string(path)
    assert_true(written.contains("**Item.** Manual, item 3 of 8"), "and names Manual as its item:\n%s" % written)
    assert_true(written.contains("Manual should open the manual"), "with the words typed into the box")
    assert_eq(_carrying(errors, FREED), PackedStringArray(), "No freed window is handed on")
    assert_eq(_carrying(errors, NUL), PackedStringArray(), "no NUL from the chord pressed over the list")
    assert_eq(errors.described(ERRORS_AND_PRINTERR), PackedStringArray(), "and nothing else is logged either")


## The mode forgets the window at both ends, so the next note never starts
## holding the box of the one before, which is how a first tap goes wrong.
func test_the_window_the_last_motion_went_to_is_forgotten_at_both_ends() -> void:
    var box := Window.new()
    _host.add_child(box)
    _mode.start()
    _mode.handle_window_input(_motion(Vector2(10.0, 10.0)), box)
    assert_eq(_mode._pointer_window, box, "A motion in the box names it")
    _mode.stop()
    assert_null(_mode._pointer_window, "and leaving the mode forgets it")
    _mode.handle_window_input(_motion(Vector2(10.0, 10.0)), box)
    assert_null(_mode._pointer_window, "and a motion after the mode is off is not the mode's")
    _mode.start()
    assert_null(_mode._pointer_window, "A mode that starts holds none")


## The geometry the tap and the hover share: the list over a point of the main
## window answers with the point in its own space, and a point it does not
## cover with nothing.
func test_a_list_over_the_main_window_answers_for_the_point_it_covers() -> void:
    var help := _open_help()
    var over := SaNoteMenu.menu_over(_main, _on_main(help, &"manual"))
    assert_eq(over.get("menu"), help, "The list stands over Manual's point on the main window")
    var item := SaNoteMenu.item_in(over["menu"], over["at"])
    assert_eq(item.get("text"), "Manual", "and the point in its own space is on Manual")
    assert_eq(item.get("index"), 2, "the third row")
    assert_true(SaNoteMenu.menu_over(_main, Vector2(200.0, 600.0)).is_empty(), "A point beside the list is no list's")
    assert_true(SaNoteMenu.menu_over(help, Vector2(20.0, 20.0)).is_empty(), "and the list is never over itself")
    help.hide()
    assert_true(SaNoteMenu.menu_over(_main, _on_main(help, &"manual")).is_empty(), "A closed list stands over nothing")


## The NUL was `char()` of a key that is no letter: Ctrl and Shift reach an open
## list's type-ahead with no character. A letter still types ahead.
func test_a_modifier_over_an_open_list_makes_no_nul_and_a_letter_still_types_ahead() -> void:
    var help := _open_help()
    var errors := SaErrorCatcher.new()
    OS.add_logger(errors)
    _chord_over(help)
    var letter := InputEventKey.new()
    letter.keycode = KEY_M
    letter.unicode = "m".unicode_at(0)
    letter.pressed = true
    help._input(letter)
    OS.remove_logger(errors)
    assert_eq(_carrying(errors, NUL), PackedStringArray(), "Ctrl, Shift and C over the list make no NUL")
    assert_eq(help.highlighted(), &"manual", "and M still lands on Manual")


## The note's question mark over a mirrored view, in and out, with the mirror
## left as it was drawn. Written the way `_show_tool_cursor` writes it, which is
## the step a machine's cursor reaches as the note starts and stops.
func test_a_mirrored_canvas_takes_a_new_shape_with_no_negative_rect() -> void:
    _mirrored_canvas()
    var drawn := _canvas.scale
    assert_true(_canvas.get_global_rect().size.y < 0.0, "The mirrored canvas's rect does come back negative")
    var errors := SaErrorCatcher.new()
    OS.add_logger(errors)
    SaCursorPolicy._write_cursor_shape(_canvas, Control.CURSOR_HELP)
    var during := _canvas.mouse_default_cursor_shape
    SaCursorPolicy._write_cursor_shape(_canvas, Control.CURSOR_CROSS)
    OS.remove_logger(errors)
    assert_eq(during, Control.CURSOR_HELP, "The question mark is written onto the canvas")
    assert_eq(_canvas.mouse_default_cursor_shape, Control.CURSOR_CROSS, "and the brush's shape put back")
    assert_eq(_canvas.scale, drawn, "The mirror is the one the painter set")
    assert_eq(_carrying(errors, NEGATIVE), PackedStringArray(), "and neither write logs a negative rectangle")


## The lines *errors* caught that carry *fragment*.
func _carrying(errors: SaErrorCatcher, fragment: String) -> PackedStringArray:
    var found := PackedStringArray()
    for line in errors.described(ERRORS_AND_PRINTERR):
        if line.contains(fragment):
            found.append(line)
    return found
