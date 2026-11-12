## Shift and Alt held over a selection tool add and subtract, and say so.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Holding Alt over a selection tool (lasso, marquee, ...) switches it to
## subtract mode temporarily, and Shift adds to the selection. The press reads
## both keys. Alt was lost before it: it is `tool_eyedropper_quick`, so holding it
## put the Eyedropper in the hand and the press never reached the marquee. And
## nothing said a key was down, the mode row kept the chosen mode and the
## pointer its plain cross.
##
## With the marquee active, Shift, then Alt, then both are held as the keyboard
## holds them, through `Input` and the machine. Each reads the tool still in the
## hand, the Tool Options docker's mode row on Add, Subtract or Intersect, and
## the pointer's mark, and each release reads the row back on the chosen mode
## and the mark gone. `selection_mode` reads Replace throughout.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A surface builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _host: Node = null
var _docker: ToolOptionsDocker = null


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(1024, 1024))
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"marquee")
    _host = Node.new()
    _docker = ToolOptionsDocker.new()
    _host.add_child(_docker)
    _docker.target_tool_machine = _machine
    _docker.sync_from_tool()


func after_each() -> void:
    for key: int in [KEY_SHIFT, KEY_ALT]:
        _key(key, false)
    _host.free()
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _host = null
    _docker = null


## Presses or lets go of *key* as a keyboard does: into `Input`, which the tool
## and the row read, and into the machine, which decides the tool in the hand.
func _key(key: int, down: bool) -> void:
    var event := InputEventKey.new()
    event.keycode = key as Key
    event.physical_keycode = key as Key
    event.pressed = down
    event.shift_pressed = Input.is_key_pressed(KEY_SHIFT) if key != KEY_SHIFT else down
    event.alt_pressed = Input.is_key_pressed(KEY_ALT) if key != KEY_ALT else down
    Input.parse_input_event(event)
    Input.flush_buffered_events()
    if _machine != null:
        _machine.handle_input(event)
        _machine._process(0.0)
    if _docker != null:
        _docker.held.follow(_machine, _docker.shown_tool_id())


## The mode the docker's Selection row shows.
func _row() -> Variant:
    var choice := _docker.options.control(&"selection_mode") as SaChoiceButton
    return choice.selected_value() if choice != null else null


func _mark() -> StringName:
    var picture := _machine.active_tool.cursor_picture()
    return picture.name if picture != null else &""


func _reads(keys: Array[int], mode: int, mark: StringName, what: String) -> void:
    for key: int in keys:
        _key(key, true)
    assert_eq(_machine.active_tool_name, &"marquee", "%s leaves the marquee in the hand" % what)
    assert_eq(_row(), mode, "%s shows its mode on the row" % what)
    assert_eq(_mark(), mark, "%s puts its mark on the pointer" % what)
    var asked := _machine._wanted_cursor_picture()
    assert_eq(asked.name if asked != null else &"", mark, "and the machine asks for it")
    assert_eq(_machine.active_tool.mode, SaSelection.Mode.REPLACE, "%s writes nothing into selection_mode" % what)
    for key: int in keys:
        _key(key, false)
    assert_eq(_machine.active_tool_name, &"marquee", "Letting %s go leaves the marquee in the hand" % what)
    assert_eq(_row(), SaSelection.Mode.REPLACE, "Letting %s go puts the chosen mode back on the row" % what)
    assert_eq(_mark(), &"", "and takes the mark away")
    assert_eq(_machine.active_tool.mode, SaSelection.Mode.REPLACE, "and selection_mode is still Replace")


func test_shift_alt_and_both_show_their_mode_and_mark_and_let_go_cleanly() -> void:
    assert_eq(_row(), SaSelection.Mode.REPLACE, "The row starts on Replace")
    assert_eq(_mark(), &"", "and the pointer with no mark")
    _reads([KEY_SHIFT], SaSelection.Mode.ADD, &"select_add", "Shift")
    _reads([KEY_ALT], SaSelection.Mode.SUBTRACT, &"select_subtract", "Alt")
    _reads([KEY_SHIFT, KEY_ALT], SaSelection.Mode.INTERSECT, &"select_intersect", "Shift and Alt")


func test_alt_still_holds_the_eyedropper_over_a_tool_that_does_not_read_it() -> void:
    _machine.set_active_tool(&"bucket_fill")
    _key(KEY_ALT, true)
    assert_eq(_machine.active_tool_name, &"eyedropper", "Alt over the Fill is the quick Eyedropper as before")
    _key(KEY_ALT, false)
    assert_eq(_machine.active_tool_name, &"bucket_fill", "and letting it go hands the Fill back")


func test_a_key_let_go_mid_drag_leaves_the_shapes_mode_alone() -> void:
    var tool := _machine.active_tool
    _key(KEY_ALT, true)
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.alt_pressed = true
    tool.handle_input(press)
    _key(KEY_ALT, false)
    assert_eq(_row(), SaSelection.Mode.SUBTRACT, "Alt let go mid-drag leaves the row on Subtract")
    assert_eq(_mark(), &"select_subtract", "and the pointer's minus")
    _key(KEY_SHIFT, true)
    assert_eq(_row(), SaSelection.Mode.SUBTRACT, "Shift pressed mid-drag changes nothing either")
    _key(KEY_SHIFT, false)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    tool.handle_input(release)
    _docker.held.follow(_machine, _docker.shown_tool_id())
    assert_eq(_row(), SaSelection.Mode.REPLACE, "The release puts Replace back on the row")
    assert_eq(_mark(), &"", "and takes the mark away")
