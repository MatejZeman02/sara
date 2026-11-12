## An agent can lock the cursor from the door, so Sara stops listening to the
## system's mouse.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A cursor lock is a command from a client via the door that stops Sara
## listening to the system mouse. It is useful for tutorials, where both user
## and client want to edit at the same time. These lock through the door's `lock_cursor` step,
## press a button with the system's mouse and with the door's `click`, and read
## which press the button heard, then unlock, close the door and let the idle
## timeout pass with the lock held.
##
## **Where the system's press comes from.** A suite cannot move the hand on
## the desk, and the display server hands its events over between two
## iterations of the main loop, which is how `SaPointerLock` tells them from
## the door's. So the press goes through `Input.parse_input_event` after
## [method SaPointerLock.frame_ended], the call the lock's own end of a frame
## makes, and the frame begins again after it.
extends "res://tests/test_framework.gd"

const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const DoorRunner := preload("res://tests/fixtures/door_runner.gd")

static var scratch_known: String = SaDataRoot.path("door/door.json")
static var scratch_port_file: String = SaDataRoot.path("door/door.port")
static var scratch_run_folder: String = SaDataRoot.path("door-run")

## Rounds of polling before a case gives up on an answer, a few milliseconds
## each.
const ROUNDS: int = 600

## Where the button stands, in root units, over everything else in the window.
const BUTTON_AT := Vector2(80.0, 80.0)
const BUTTON_SIZE := Vector2(160.0, 48.0)

## The idle timeout of the case that lets it pass, in seconds.
const SHORT_IDLE: float = 0.6

var _host: Node = null
var _button: Button = null
var _door: AgentDoor = null
var _run: CaptureRun = null
var _table: StepTable = null
var _runner: DoorRunner = null
var _client: StreamPeerTCP = null
## How many presses the button heard.
var _presses: int = 0


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    SaCursorPolicy.unlock_system_pointer()
    _host = Node.new()
    _host.name = "U871LockTestHost"
    EventBus.add_child(_host)
    var layer := CanvasLayer.new()
    layer.layer = 128
    _host.add_child(layer)
    _button = Button.new()
    _button.name = "U871Target"
    _button.text = "Target"
    _button.position = BUTTON_AT
    _button.size = BUTTON_SIZE
    layer.add_child(_button)
    _presses = 0
    _button.button_down.connect(_heard_a_press)
    _door = AgentDoor.new(scratch_known)
    _run = CaptureRun.new(scratch_run_folder)
    _table = StepTable.new(_run)
    _runner = DoorRunner.new(_door, _table, _run, ROUNDS, scratch_known)
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    _client = _runner.connect_client()


func after_each() -> void:
    if _client != null:
        _client.disconnect_from_host()
        _client = null
    _door.close()
    _door = null
    _table = null
    _runner = null
    _run = null
    SaCursorPolicy.unlock_system_pointer()
    if _host != null:
        _host.free()
        _host = null
    _button = null


func _heard_a_press() -> void:
    _presses += 1


## The button's middle, in root units.
func _middle() -> Vector2:
    return _button.get_global_rect().get_center()


## Sends *request* through the door and answers its answer.
func _ask(request: Dictionary) -> Dictionary:
    return _runner.ask(_client, request)


## A motion, a press and a release of the system's left button at *at*, in root
## units, handed over between two frames as the display server hands its own.
func _system_click(at: Vector2) -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    var physical: Vector2 = root.get_final_transform() * at
    SaPointerLock.frame_ended()
    var motion := InputEventMouseMotion.new()
    motion.position = physical
    motion.global_position = physical
    Input.parse_input_event(motion)
    for pressed: bool in [true, false]:
        var button := InputEventMouseButton.new()
        button.button_index = MOUSE_BUTTON_LEFT
        button.pressed = pressed
        button.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
        button.position = physical
        button.global_position = physical
        Input.parse_input_event(button)
    Input.flush_buffered_events()
    SaPointerLock.frame_began()


## The door's own click on the button's middle, answered.
func _door_click() -> Dictionary:
    var at := _middle()
    return _ask({"id": 9, "click": {"at": [at.x, at.y]}})


## Whether a gate of the lock stands in the main window.
static func _gated() -> bool:
    var root := (Engine.get_main_loop() as SceneTree).root
    return root.find_child(SaPointerLock.GATE_NAME, true, false) != null


func test_a_locked_sara_hears_the_door_s_click_and_drops_the_system_s_press() -> void:
    _system_click(_middle())
    assert_eq(_presses, 1, "Before the lock the system's press reaches the button")

    var locked := _ask({"id": 1, "lock_cursor": "probe suite"})
    assert_true(bool(locked.get("ok", false)), "The door takes lock_cursor: %s" % locked)
    assert_true(SaCursorPolicy.system_pointer_locked, "and the lock is held")
    assert_true(_gated(), "with a gate in the main window")

    _system_click(_middle())
    assert_eq(_presses, 1, "A press of the system's mouse while locked never reaches the button")
    assert_true(SaPointerLock.dropped > 0, "and is counted as dropped")

    var clicked := _door_click()
    assert_true(bool(clicked.get("ok", false)), "The door's click is answered: %s" % clicked)
    assert_eq(_presses, 2, "and the door's click reaches the button while the lock is held")


func test_an_unlocked_sara_hears_the_system_s_press_again() -> void:
    _ask({"id": 1, "lock_cursor": true})
    _system_click(_middle())
    assert_eq(_presses, 0, "The locked button hears nothing from the system")

    var unlocked := _ask({"id": 2, "unlock_cursor": true})
    assert_true(bool(unlocked.get("ok", false)), "The door takes unlock_cursor: %s" % unlocked)
    assert_false(SaCursorPolicy.system_pointer_locked, "and the lock is let go")
    assert_false(_gated(), "with its gate taken out")
    var said := str(unlocked.get("verdicts", []))
    assert_true(said.contains("unlock_cursor let go"), "and the answer says so: %s" % said)

    _system_click(_middle())
    assert_eq(_presses, 1, "Once unlocked the system's press reaches the button again")


func test_closing_the_door_while_locked_lets_the_lock_go() -> void:
    _ask({"id": 1, "lock_cursor": true})
    assert_true(SaCursorPolicy.system_pointer_locked, "The lock is held")
    _client.disconnect_from_host()
    _client = null
    _door.close()
    assert_false(SaCursorPolicy.system_pointer_locked, "A closed door leaves the lock free")
    assert_false(_gated(), "and no gate behind")
    _system_click(_middle())
    assert_eq(_presses, 1, "so the system's press reaches the button")


func test_the_idle_timeout_lets_the_lock_go_as_it_does_a_notebook_that_went_away() -> void:
    var attached := _ask({"id": 1, "attach": true})
    assert_true(bool(attached.get("attached", false)), "The client attaches as a notebook does: %s" % attached)
    _door.idle_timeout = SHORT_IDLE
    _ask({"id": 2, "lock_cursor": "a notebook"})
    var answered := Time.get_ticks_msec()
    _client.disconnect_from_host()
    _client = null
    _runner.frame()
    # A loaded machine can take the whole timeout between the answer and this
    # frame, and then the lock is let go by right and there is no hang-up to
    # read apart from the quiet.
    if Time.get_ticks_msec() - answered < int(SHORT_IDLE * 500.0):
        assert_true(SaCursorPolicy.system_pointer_locked, "A notebook's hang-up between calls keeps the lock")
    var until := Time.get_ticks_msec() + int(SHORT_IDLE * 2000.0)
    while Time.get_ticks_msec() < until and SaCursorPolicy.system_pointer_locked:
        _runner.frame()
        OS.delay_msec(5)
    assert_false(SaCursorPolicy.system_pointer_locked, "and no request for the idle timeout lets it go")
    assert_true(_door.is_open(), "while the attached door listens on")


func test_the_status_line_says_the_mouse_is_locked() -> void:
    var line := SaStatusLine.new(Callable())
    _host.add_child(line)
    assert_false(line.lock_label.visible, "A free lock shows nothing on the status line")
    _ask({"id": 1, "lock_cursor": "probe suite"})
    assert_true(line.lock_label.visible, "A held lock shows on the status line")
    assert_false(line.lock_label.text.is_empty(), "in words")
    assert_true(line.lock_label.tooltip_text.contains("probe suite"), "and its tooltip names who holds it")
    _ask({"id": 2, "unlock_cursor": true})
    assert_false(line.lock_label.visible, "Letting it go takes the word away")
