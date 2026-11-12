## Opening the Local Server leaves the pointer where it is.
##
## Enabling the server must not jump the mouse to a different location. Modules › Local Server adds a capture
## node with no scenario, and that node ran the warp probe on its first frame
## past the settle, which moves the pointer to test whether the platform lets
## it. A door in a painter's session now never moves the pointer by itself: the
## probe runs at the first motion a step injects, and the dump says what it
## found from then on.
##
## The warp is a stand-in that counts its calls and moves nothing, so the suite
## reads the probe without touching the painter's pointer either. The door is
## polled through the capture's own `_process`, since a suite runs no frames,
## which is the path that ran the probe at the settle.
extends "res://tests/test_framework.gd"

const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const InputDriver := preload("res://harness/drivers/sa_input_driver.gd")
const Fixtures := preload("res://tests/fixtures.gd")

static var scratch_known: String = SaDataRoot.path("d17-door/door.json")

var _parent: Node = null
var _warps: Array[Vector2] = []
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
    _parent.name = "D17LocalServerHost"
    EventBus.add_child(_parent)
    _warps = []
    InputDriver.warp = _warp


func after_each() -> void:
    InputDriver.warp = Input.warp_mouse
    if is_instance_valid(_parent):
        _parent.free()
    _parent = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding


func _warp(at: Vector2) -> void:
    _warps.append(at)


func _door() -> SaCapture:
    for child: Node in _parent.get_children():
        if child is SaCapture:
            return child as SaCapture
    return null


func test_the_door_probes_at_its_first_move_and_not_before() -> void:
    SaCapture.connect_an_agent(_parent, scratch_known)
    var capture := _door()
    assert_not_null(capture, "Local Server opens a door")
    if capture == null:
        return
    for _i in SaCapture.SETTLE_FRAMES + 30:
        capture._process(0.0)
    assert_eq(_warps.size(), 0, "Frames past the settle move no pointer")
    assert_false(capture.run.pointer_warp_probed, "and the probe has not run")

    var known: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(scratch_known))
    var client := StreamPeerTCP.new()
    client.connect_to_host(AgentDoor.LOOPBACK, int(known.get("port", 0)))
    var frame := func() -> void: capture._process(0.0)
    for _i in 400:
        client.poll()
        frame.call()
        if client.get_status() == StreamPeerTCP.STATUS_CONNECTED:
            break
        OS.delay_msec(2)
    var token := String(known.get("token", ""))
    var resting := Fixtures.DoorHttp.ask(client, {"id": 1, "dump": true}, token, frame)
    assert_true(bool(resting.get("ok", false)), "A dump with no step answers: %s" % JSON.stringify(resting).left(300))
    assert_eq(_warps.size(), 0, "and moves no pointer")

    var answer := Fixtures.DoorHttp.ask(client, {"id": 2, "move": [40, 30], "dump": true}, token, frame)
    assert_true(bool(answer.get("ok", false)), "The move answers: %s" % JSON.stringify(answer).left(300))
    assert_eq(_warps.size(), 1, "The move runs the probe, once")
    assert_true(capture.run.pointer_warp_probed, "and the run knows it has")
    var state := answer.get("state", {}) as Dictionary
    assert_true(state.has("pointer_warp_works"), "The dump reports what the probe found")
    assert_eq(state.get("pointer_warp_works"), capture.run.pointer_warp_works, "as the run holds it")

    var again := Fixtures.DoorHttp.ask(client, {"id": 3, "move": [60, 50]}, token, frame)
    assert_true(bool(again.get("ok", false)), "A second move answers")
    assert_eq(_warps.size(), 1, "and runs no second probe")
    client.disconnect_from_host()
