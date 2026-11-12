## A stall line names where Sara is, not the last dialog it opened.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Every stall line during Oil Smudge strokes once ended "at the
## dialog Preferences", which had been closed for minutes, because the trail
## kept the last place written and nothing wrote one as a dialog hid or a
## command returned. Here a real dialog shows and hides and a real registry runs
## a command, by its id and by its chord. Each stall is made on a watch out of
## the tree with a frame on the suite's own clock, as the sibling suite makes its
## own, and its line is read out of the run's own log.
##
## The dialog is embedded, the way the sibling suite embeds its own, because a
## dialog that maps an OS window hangs a headless run.
@tool
extends "res://tests/test_framework.gd"

## The probe command's id, its action, and what the trail names it by.
const PROBE := &"d16_probe"
## The one frame a stall takes, past `SaTrail.STALL_S`.
const STALL_MS := 1500
const AT_BRUSH := "a frame took 1.5 s, at the brush tool"
const AT_COMMAND := "a frame took 1.5 s, at the command d16_probe"


class StubDialog:
    extends SaDialogWindow

    func _init(dialog_title: String) -> void:
        _init_dialog("D16StubDialog", dialog_title, Vector2i(320, 200), Vector2i(200, 120))


var _kept_embedding: bool = true
var _host: Node = null
var _watch: SaTrail.Watch = null
## The suite's clock as the watch is handed it.
var _clock: int = 0
## Where in the run's log the lines not read yet begin.
var _from: int = 0


## Every test starts with the brush in hand, as an Oil Smudge stroke
## does, noted the way `tool_machine.gd` notes a tool switch.
func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "D16TestHost"
    EventBus.add_child(_host)
    _watch = SaTrail.Watch.new()
    _clock = _watch._beat_usec
    _from = _log_length()
    SaTrail.note("the brush tool")


func after_each() -> void:
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    if _watch != null:
        _watch.free()
        _watch = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _kept_embedding
    _forget()


## The ask: the brush in hand, a dialog opened and closed and a command run,
## and a stall after them names the brush, where Preferences was named before.
func test_a_stall_after_a_dialog_and_a_command_names_the_brush_tool() -> void:
    var dialog := _dialog("Preferences")
    dialog.show()
    dialog.hide()
    var registry := _registry(func() -> bool: return true)
    assert_true(registry.execute(PROBE), "The command runs")
    assert_eq(_stall(), AT_BRUSH, "The stall names the tool in hand, not the dialog or the command before it")


## A stall while a dialog shows names the dialog, and one after its hide names
## the tool again.
func test_a_stall_during_an_open_dialog_names_the_dialog() -> void:
    var dialog := _dialog("Preferences")
    dialog.show()
    assert_eq(_stall(), "a frame took 1.5 s, at the dialog Preferences", "The open dialog is where Sara is")
    dialog.hide()
    assert_eq(_stall(), AT_BRUSH, "and its hide gives back the tool")


## A stall inside a command's handler names the command, by its id and by its
## chord, and its return gives back the place before it.
func test_a_stall_while_a_command_runs_names_the_command() -> void:
    var during: Array[String] = []
    var registry := _registry(
        func() -> bool:
            during.append(_stall())
            return true
    )
    assert_true(registry.execute(PROBE), "The command runs by its id")
    assert_true(registry.try_handle_input(_chord()), "and by its chord")
    assert_eq(during, [AT_COMMAND, AT_COMMAND] as Array[String], "A stall inside the handler names the command both ways")
    assert_eq(_stall(), AT_BRUSH, "and the return gives back the tool")


## Brush Presets and Preferences open through a command, so the dialog shows
## while the command runs. Its return leaves the dialog named, and the dialog's
## hide the tool.
func test_a_dialog_a_command_opens_outlives_the_command() -> void:
    var dialog := _dialog("Preferences")
    var registry := _registry(
        func() -> bool:
            dialog.show()
            return true
    )
    assert_true(registry.execute(PROBE), "The command runs")
    assert_eq(_stall(), "a frame took 1.5 s, at the dialog Preferences", "The dialog it opened is named once it returns")
    dialog.hide()
    assert_eq(_stall(), AT_BRUSH, "and the tool once the dialog hides")


## Two dialogs closed in the order they opened: the first one's hide leaves the
## second named, and the second's leaves the tool, never the closed first.
func test_two_dialogs_closed_out_of_order_leave_the_one_still_open() -> void:
    var first := _dialog("Feather")
    var second := _dialog("Border")
    first.show()
    second.show()
    first.hide()
    assert_eq(_stall(), "a frame took 1.5 s, at the dialog Border", "The dialog still open is named")
    second.hide()
    assert_eq(_stall(), AT_BRUSH, "and the tool once both are closed")


## A tool picked while a dialog shows is where Sara went last, so it is named
## over the dialog, and the dialog's hide leaves it named.
func test_a_tool_picked_over_an_open_dialog_is_named_over_it() -> void:
    var dialog := _dialog("Preferences")
    dialog.show()
    SaTrail.note("the eraser tool")
    assert_eq(_stall(), "a frame took 1.5 s, at the eraser tool", "The tool picked last is named")
    dialog.hide()
    assert_eq(_stall(), "a frame took 1.5 s, at the eraser tool", "and the dialog's hide does not take it back")


## A window that leaves the tree showing says nothing of its visibility, so a
## dialog freed while it shows gives its place back on the way out.
func test_a_dialog_freed_while_it_shows_gives_its_place_back() -> void:
    var dialog := _dialog("Preferences")
    dialog.show()
    _host.remove_child(dialog)
    dialog.free()
    assert_eq(_stall(), AT_BRUSH, "The tool is named once the dialog is gone")


func _dialog(dialog_title: String) -> SaDialogWindow:
    var dialog := StubDialog.new(dialog_title)
    dialog.visible = false
    _host.add_child(dialog)
    return dialog


## A registry holding the probe command, run by *handler* and bound to
## Ctrl+Alt+K. The action is made before the command registers, so nothing is
## written to the shipped map and `_forget` takes it away whole.
func _registry(handler: Callable) -> SaCommandRegistry:
    _forget()
    InputMap.add_action(PROBE)
    InputMap.action_add_event(PROBE, _chord())
    var registry := SaCommandRegistry.new()
    registry.register(SaCommandDescriptor.create(PROBE, "Probe: run the handler", handler))
    return registry


func _forget() -> void:
    if InputMap.has_action(PROBE):
        InputMap.erase_action(PROBE)


func _chord() -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = KEY_K
    key.ctrl_pressed = true
    key.alt_pressed = true
    key.pressed = true
    return key


## Makes one stall on the suite's clock and answers the line it printed, the
## prefix taken off, or every line it printed when that was not one.
func _stall() -> String:
    _clock += STALL_MS * 1000
    _watch.frame_came(_clock, _watch._seen_motions)
    var lines := _lines()
    _from = _log_length()
    return lines[0] if lines.size() == 1 else "%d lines: %s" % [lines.size(), "|".join(lines)]


## The stall lines printed since `_from`, the prefix taken off.
func _lines() -> PackedStringArray:
    var out := PackedStringArray()
    for line in _log_text().substr(_from).split("\n"):
        var trimmed := line.strip_edges()
        if trimmed.begins_with(SaTrail.STALL):
            out.append(_without_age(trimmed.substr(SaTrail.STALL.length()).strip_edges()))
    return out


## *line* without the age a stall line puts on a place older than
## `SaTrail.SLOW_S`. These tests are about the words and the place, and
## a loaded machine can take that long between the note and the frame.
static func _without_age(line: String) -> String:
    if not line.ends_with(" ago"):
        return line
    for said: String in [", noted ", ", entered "]:
        var at := line.rfind(said)
        if at > 0:
            return line.substr(0, at)
    return line


func _log_length() -> int:
    return _log_text().length()


func _log_text() -> String:
    var path := SaTrail.log_path()
    if not FileAccess.file_exists(path):
        return ""
    var file := FileAccess.open(path, FileAccess.READ)
    return file.get_as_text() if file != null else ""
