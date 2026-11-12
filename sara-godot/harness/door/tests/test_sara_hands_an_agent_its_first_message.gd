## Modules › Local Server opens the door in a Sara started
## without one, and its dialog's button hands over a paragraph whose path and
## first request answer when followed, and `--agent-help` prints the same
## paragraph.
##
## The row is pressed through its command, with the bus's request answered
## under a node of the suite's own and with a known file of the suite's own, so
## no case touches the real one. The door is polled by hand, the way
## `test_door_attach.gd` polls it, since a suite runs no frames.
## `scripts/test_door_connect_an_agent.py` presses the same row and button in
## a real Sara and runs the build with `--agent-help`. The tick and the closing
## are `test_local_server_is_a_toggle_and_its_dialog_copies_the_prompt.gd`'s.
extends "res://tests/test_framework.gd"

const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const AgentInvite := preload("res://ui/boot/sa_agent_invite.gd")
const LocalServerDialog := preload("res://ui/dialogs/sa_local_server_dialog.gd")
const Fixtures := preload("res://tests/fixtures.gd")

static var scratch_known: String = SaDataRoot.path("s2-door/door.json")

var _parent: Node = null
## What the dialog's button put on the clipboard, each copy in turn.
var _copies: PackedStringArray = []
var _kept_embedding: bool = true


func before_each() -> void:
    if FileAccess.file_exists(scratch_known):
        DirAccess.remove_absolute(scratch_known)
    # The dialog is a window, and one the root does not embed maps a real OS
    # window and stalls the run.
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _parent = Node.new()
    EventBus.add_child(_parent)
    EventBus.local_server_requested.connect(_answer)
    _copies = PackedStringArray()
    LocalServerDialog.clipboard = _copy


func after_each() -> void:
    LocalServerDialog.clipboard = DisplayServer.clipboard_set
    EventBus.local_server_requested.disconnect(_answer)
    if is_instance_valid(_parent):
        _parent.free()
    _parent = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding


## What `Main` does with the request, under the suite's node and known file.
func _answer() -> void:
    SaCapture.flip_the_local_server(_parent, scratch_known)


## The clipboard call, counted and then made.
func _copy(text: String) -> void:
    _copies.append(text)
    DisplayServer.clipboard_set(text)


## Presses Modules › Local Server the way the menu does, through the command
## the row names, whose id a stored chord holds.
func _press() -> void:
    assert_true(SaModulesMenu.DEVELOP_ROWS.has([SaModulesMenu.ID_LOCAL_SERVER, &"help_connect_agent"]), "Modules lists the row")
    var commands := SaMenuCommands.new(Callable(), Callable(), Callable(), Callable())
    for command: SaCommandDescriptor in commands.commands():
        if command.id == &"help_connect_agent":
            command.handler.call()
            return
    assert_true(false, "A command is called help_connect_agent")


## The capture nodes under the suite's node whose door listens.
func _doors() -> Array[SaCapture]:
    var doors: Array[SaCapture] = []
    for child: Node in _parent.get_children():
        if child is SaCapture and (child as SaCapture)._door != null and (child as SaCapture)._door.is_open():
            doors.append(child as SaCapture)
    return doors


## The dialogs under the suite's node, the one a press showed.
func _dialogs() -> Array[LocalServerDialog]:
    var dialogs: Array[LocalServerDialog] = []
    for child: Node in _parent.get_children():
        if child is LocalServerDialog:
            dialogs.append(child as LocalServerDialog)
    return dialogs


## The clipboard holds *text*, where the display server lets this process read
## back what it set. A nested weston answers an empty clipboard to a client
## with no keyboard focus, so there the call the button made is read instead.
## The real Sara's run in `scripts/test_door_connect_an_agent.py` reads the
## clipboard itself under an X server of its own.
func _assert_on_the_clipboard(text: String) -> void:
    assert_eq(_copies[_copies.size() - 1] if not _copies.is_empty() else "", text, "The button copies the paragraph")
    var held := DisplayServer.clipboard_get() if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD) else ""
    if not held.is_empty():
        assert_eq(held, text, "The clipboard holds the paragraph")


static func _read(file: String) -> Dictionary:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
    return parsed as Dictionary if parsed is Dictionary else {}


## The path the paragraph names, between the backticks after "is in".
static func _named_path(text: String) -> String:
    var from := text.find("is in `")
    if from < 0:
        return ""
    from += "is in `".length()
    return text.substr(from, text.find("`", from) - from)


func test_the_row_opens_the_door_and_the_paragraph_answers_when_followed() -> void:
    assert_eq(_doors().size(), 0, "The session starts without a door")
    _press()
    var doors := _doors()
    assert_eq(doors.size(), 1, "The row opens one door")
    var dialogs := _dialogs()
    assert_eq(dialogs.size(), 1, "and shows its dialog")
    if doors.is_empty() or dialogs.is_empty():
        return
    var door: AgentDoor = doors[0]._door
    assert_true(FileAccess.file_exists(scratch_known), "and writes the known file")
    assert_eq(_copies.size(), 0, "Nothing is copied at the press")
    dialogs[0].copy_button.pressed.emit()
    var text := AgentInvite.paragraph(ProjectSettings.globalize_path(scratch_known), true)
    _assert_on_the_clipboard(text)
    var where := _named_path(text)
    assert_eq(where, ProjectSettings.globalize_path(scratch_known), "The paragraph names the known file on this platform")
    assert_true(text.contains('{"steps": true}'), "and the request to send first")
    assert_true(text.contains("Authorization: Bearer <token>"), "with the token as a Bearer")
    var known := _read(where)
    assert_eq(int(known.get("port", 0)), door.port, "The file the paragraph names holds the door's port")

    var client := StreamPeerTCP.new()
    client.connect_to_host(AgentDoor.LOOPBACK, int(known.get("port", 0)))
    var frame := func() -> void: door.poll(doors[0]._steps_table, doors[0].run)
    for _i in 400:
        client.poll()
        frame.call()
        if client.get_status() == StreamPeerTCP.STATUS_CONNECTED:
            break
        OS.delay_msec(2)
    var answer := Fixtures.DoorHttp.ask(client, {"steps": true}, String(known.get("token", "")), frame)
    assert_true(bool(answer.get("ok", false)), "The first request answers: %s" % JSON.stringify(answer).left(300))
    var listed := (answer.get("start", []) as Array).size() + (answer.get("steps", {}) as Dictionary).size()
    assert_true(listed > 100, "with every step kind")
    client.disconnect_from_host()


## Opening again while the door listens, which the row never does since its
## second press closes, opens no second door and leaves one dialog, whose
## button copies the same paragraph.
func test_a_second_opening_opens_no_second_door() -> void:
    _press()
    var first := _doors()
    assert_eq(first.size(), 1, "The first press opens a door")
    if first.is_empty():
        return
    var port: int = first[0]._door.port
    var dialog := SaCapture.connect_an_agent(_parent, scratch_known)
    var second := _doors()
    assert_eq(second.size(), 1, "Opening again opens no second door")
    assert_eq(second[0], first[0], "and leaves the first one listening")
    assert_eq(int(_read(scratch_known).get("port", 0)), port, "on the port the known file names")
    var dialogs := _dialogs()
    assert_eq(dialogs.size(), 1, "with one dialog")
    assert_true(not dialogs.is_empty() and dialogs[0] == dialog, "the new one")
    dialog.copy_button.pressed.emit()
    var text := AgentInvite.paragraph(ProjectSettings.globalize_path(scratch_known), true)
    _assert_on_the_clipboard(text)


func test_the_door_closes_with_sara_and_takes_its_known_file() -> void:
    _press()
    assert_true(FileAccess.file_exists(scratch_known), "The press writes the known file")
    _parent.free()
    assert_false(FileAccess.file_exists(scratch_known), "and Sara leaving removes it, as the boot's door does")


func test_a_known_file_another_live_sara_holds_opens_nothing() -> void:
    # The parent of this process runs for as long as the suite does, so it
    # stands for a Sara that already listens.
    var other := OS.get_process_id()
    var ppid := int(FileAccess.get_file_as_string("/proc/self/stat").get_slice(" ", 3)) if OS.get_name() == "Linux" else 0
    if ppid <= 0:
        return
    DirAccess.make_dir_recursive_absolute(scratch_known.get_base_dir())
    var held := FileAccess.open(scratch_known, FileAccess.WRITE)
    held.store_string(JSON.stringify({"port": 1, "token": "x", "pid": ppid}))
    held.close()
    assert_true(ppid != other, "The holder is another process")
    assert_null(SaCapture.connect_an_agent(_parent, scratch_known), "No dialog is shown")
    assert_eq(_doors().size(), 0, "and no door opens")
    assert_eq(_copies.size(), 0, "and nothing is copied")
    assert_eq(int(_read(scratch_known).get("pid", 0)), ppid, "and the other Sara keeps its file")
    DirAccess.remove_absolute(scratch_known)


func test_the_help_flag_paragraph_is_the_same_request_and_names_no_step_kind() -> void:
    var listening := AgentInvite.paragraph("/x/door.json", true)
    var closed := AgentInvite.paragraph("/x/door.json", false)
    assert_true(closed.contains("--agent-door"), "The flag's paragraph says how to open the door")
    assert_true(closed.contains("Modules › Local Server"), "and names the row")
    # Everything after the opening sentences is the same text.
    var tail := listening.substr(listening.find("Where it listens"))
    assert_true(closed.ends_with(tail), "and goes on as the row's does")
    for kind: String in ["stroke", "shot", "zoom", "state", "quit", "dump", "attach"]:
        assert_false(listening.contains('"%s"' % kind), "It names no step kind such as %s" % kind)
    assert_eq(AgentDoor.KNOWN_FILE, AgentInvite.KNOWN_FILE, "The door and the paragraph name one file")
    assert_false(listening.contains("\u2014") or listening.contains(";"), "It is prose without a dash or a semicolon")
