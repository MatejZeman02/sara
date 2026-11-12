## Modules › Local Server is a tick, and its dialog copies the
## prompt for an agent.
##
## The row opens a server and says so, shows a dialog whose button copies the
## paragraph, and a second press closes the server.
##
## The row is pressed in a Modules menu built detached, the way
## `test_the_developers_rows_sit_together_at_the_end_of_modules.gd` builds its
## bar, so the press runs the command and the tick is the one the row draws.
## The bus's request is answered under a node of the suite's own with a known
## file of its own, as `test_sara_hands_an_agent_its_first_message.gd` answers
## it, and the door is polled by hand, since a suite runs no frames.
extends "res://tests/test_framework.gd"

const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const AgentInvite := preload("res://ui/boot/sa_agent_invite.gd")
const LocalServerDialog := preload("res://ui/dialogs/sa_local_server_dialog.gd")
const Fixtures := preload("res://tests/fixtures.gd")

## A sentence the clipboard holds before the press, so a press that wrote it
## is told from one that did not.
const UNTOUCHED := "d3: what the clipboard held before the press"

static var scratch_known: String = SaDataRoot.path("d3-door/door.json")

var _parent: Node = null
var _bar: TopMenuBar = null
var _copies: PackedStringArray = []
var _kept_embedding: bool = true


func before_each() -> void:
    if FileAccess.file_exists(scratch_known):
        DirAccess.remove_absolute(scratch_known)
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    # The dialog is a window, and one the root does not embed maps a real OS
    # window and stalls the run.
    tree.root.gui_embed_subwindows = true
    _parent = Node.new()
    _parent.name = "D3LocalServerHost"
    EventBus.add_child(_parent)
    EventBus.local_server_requested.connect(_answer)
    _copies = PackedStringArray()
    LocalServerDialog.clipboard = _copy
    _bar = TopMenuBar.new()
    _bar._ready()
    var note_mode := SaNoteMode.new()
    _bar.add_child(note_mode)
    _bar.bind_commands(SaTestFixtures.make_menu_registries(note_mode).commands)
    if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
        DisplayServer.clipboard_set(UNTOUCHED)


func after_each() -> void:
    LocalServerDialog.clipboard = DisplayServer.clipboard_set
    EventBus.local_server_requested.disconnect(_answer)
    if _bar != null:
        _bar.free()
        _bar = null
    if is_instance_valid(_parent):
        _parent.free()
    _parent = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding


## What `Main` does with the request, under the suite's node and known file.
func _answer() -> void:
    SaCapture.flip_the_local_server(_parent, scratch_known)


func _copy(text: String) -> void:
    _copies.append(text)
    DisplayServer.clipboard_set(text)


## Presses Local Server in Modules, built as the bar opens it, and answers
## whether the row then reads ticked.
func _press() -> bool:
    var menu := _bar.menu("Modules")
    menu.populate()
    assert_eq(menu.command_at(SaModulesMenu.ID_LOCAL_SERVER), &"help_connect_agent", "The row keeps the command a chord holds")
    menu.on_id_pressed(SaModulesMenu.ID_LOCAL_SERVER)
    return menu.is_item_checked(SaModulesMenu.ID_LOCAL_SERVER)


## The row's tick as the menu draws it on its next open.
func _ticked() -> bool:
    var menu := _bar.menu("Modules")
    menu.populate()
    return menu.is_item_checked(SaModulesMenu.ID_LOCAL_SERVER)


func _door() -> SaCapture:
    for child: Node in _parent.get_children():
        if child is SaCapture:
            return child as SaCapture
    return null


func _dialog() -> LocalServerDialog:
    for child: Node in _parent.get_children():
        if child is LocalServerDialog:
            return child as LocalServerDialog
    return null


## The clipboard as this process reads it back, or "" where the display
## server hands it nothing.
static func _held() -> String:
    return DisplayServer.clipboard_get() if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD) else ""


## The row's own words, the press, the button and the press again.
func test_the_row_opens_shows_copies_on_the_button_and_closes() -> void:
    assert_false(_ticked(), "Local Server starts unticked in a Sara with no door")
    var readable := _held() == UNTOUCHED

    assert_true(_press(), "The press ticks the row")
    var capture := _door()
    assert_true(capture != null and capture._door != null and capture._door.is_open(), "and the door listens")
    assert_true(FileAccess.file_exists(scratch_known), "with its known file written")
    var dialog := _dialog()
    assert_not_null(dialog, "The dialog is there")
    if capture == null or dialog == null:
        return
    assert_true(dialog.visible, "and shown")
    assert_eq(dialog.title, "Local Server", "under the row's name")
    assert_eq(_copies.size(), 0, "The press copies nothing")
    if readable:
        assert_eq(_held(), UNTOUCHED, "and the clipboard holds what it held")

    var where := ProjectSettings.globalize_path(scratch_known)
    var said := ""
    for label: Node in dialog.find_children("*", "Label", true, false):
        said += (label as Label).text + "\n"
    assert_true(said.contains("this computer only"), "The dialog says the server answers this computer alone")
    assert_true(said.contains(where), "and names the known file")
    assert_true(said.contains("sara.connect()"), "and how a notebook connects")
    assert_eq(dialog.copy_button.text, "Copy Prompt for Agent", "and its button copies the prompt for an agent")

    dialog.copy_button.pressed.emit()
    var paragraph := AgentInvite.paragraph(where, true)
    assert_eq(_copies, PackedStringArray([paragraph]), "The button copies the paragraph, once")
    if readable:
        assert_eq(_held(), paragraph, "and the clipboard holds it")

    assert_false(_press(), "The second press unticks the row")
    assert_false(is_instance_valid(capture) and capture.is_inside_tree(), "and the door's node has left")
    assert_true(capture._door == null, "with its door closed")
    assert_false(FileAccess.file_exists(scratch_known), "and the known file gone")
    assert_eq(_dialog(), null, "and the dialog with it")
    assert_false(_ticked(), "The row is still unticked when the menu opens again")
    assert_eq(_copies.size(), 1, "and nothing more was copied")


## An attached client is let go by the closing, so its next call finds no door
## and meets the guide rather than a hung connection.
func test_the_closing_lets_an_attached_client_go() -> void:
    _press()
    var capture := _door()
    if capture == null:
        assert_true(false, "The press opened a door")
        return
    var door: AgentDoor = capture._door
    var known := JSON.parse_string(FileAccess.get_file_as_string(scratch_known)) as Dictionary
    var port := int(known.get("port", 0))
    var client := StreamPeerTCP.new()
    client.connect_to_host(AgentDoor.LOOPBACK, port)
    var frame := func() -> void: door.poll(capture._steps_table, capture.run)
    for _i in 400:
        client.poll()
        frame.call()
        if client.get_status() == StreamPeerTCP.STATUS_CONNECTED:
            break
        OS.delay_msec(2)
    var answer := Fixtures.DoorHttp.ask(client, {"attach": true}, String(known.get("token", "")), frame)
    assert_true(bool(answer.get("attached", false)), "A client attaches: %s" % JSON.stringify(answer).left(200))
    assert_eq(door.connections, 1, "and the door holds it")

    _press()
    assert_false(door.is_open(), "Unticking closes the door")
    var gone := false
    for _i in 200:
        client.poll()
        if client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
            gone = true
            break
        OS.delay_msec(2)
    assert_true(gone, "and the client's connection is closed")
    # The port is free when a listener of the suite's own can take it. A call
    # to it read the same on Linux, where it is refused at once, but under
    # Windows Godot's connect to a closed port stays connecting for good, and
    # the call read as something still listening.
    var probe := TCPServer.new()
    assert_eq(probe.listen(port, AgentDoor.LOOPBACK), OK, "A call after the closing finds nothing listening on the port")
    probe.stop()
    client.disconnect_from_host()


## A door `--agent-door` opened at boot ticks the row too, shows no dialog,
## and is closed by the row like one the row opened.
func test_a_door_opened_at_boot_ticks_the_row_and_the_row_closes_it() -> void:
    var door := AgentDoor.open_known(scratch_known)
    assert_not_null(door, "A door opens the way the boot opens one")
    if door == null:
        return
    var capture := SaCapture.new(SaDataRoot.path("d3-door/captures"), [], door)
    _parent.add_child(capture)
    assert_true(_ticked(), "A door opened at boot ticks Local Server")
    assert_eq(_dialog(), null, "and shows no dialog")
    assert_false(_press(), "A press unticks it")
    assert_false(door.is_open(), "and closes the boot's door")
    assert_false(FileAccess.file_exists(scratch_known), "and removes its known file")
    assert_eq(_dialog(), null, "and shows no dialog on the way out")


## Another live Sara holding the known file: the notice stays and the row
## stays unticked.
func test_a_known_file_another_live_sara_holds_leaves_the_row_unticked() -> void:
    var ppid := int(FileAccess.get_file_as_string("/proc/self/stat").get_slice(" ", 3)) if OS.get_name() == "Linux" else 0
    if ppid <= 0:
        return
    DirAccess.make_dir_recursive_absolute(scratch_known.get_base_dir())
    var held := FileAccess.open(scratch_known, FileAccess.WRITE)
    held.store_string(JSON.stringify({"port": 1, "token": "x", "pid": ppid}))
    held.close()
    assert_false(_press(), "The press leaves the row unticked")
    assert_eq(_door(), null, "and opens no door")
    assert_eq(_dialog(), null, "and shows no dialog")
    var kept := JSON.parse_string(FileAccess.get_file_as_string(scratch_known)) as Dictionary
    assert_eq(int(kept.get("pid", 0)), ppid, "and the other Sara keeps its file")
    DirAccess.remove_absolute(scratch_known)
