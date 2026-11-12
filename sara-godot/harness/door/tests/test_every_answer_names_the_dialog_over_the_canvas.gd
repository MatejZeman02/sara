## Every door answer names the dialog standing over the canvas.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The "Recovered work" question can stand over the canvas from a client's
## first request, and without this no answer said so until a click on Later did nothing. These
## open the door in this process over TCP, as `test_the_door_answers_in_verdict_lines.gd`
## does, put that question up with its own title and labels, and read what the
## door answers over it, embedded and as a window of its own.
##
## Each case reads the dialogs already standing before it opens its own, so a
## window an earlier suite of a whole run left up is counted as that suite's and
## not as this one's, and an answer over a clear canvas still holds no key.
extends "res://tests/test_framework.gd"

const AgentDoor := preload("res://harness/door/sa_agent_door.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const Fixtures := preload("res://tests/fixtures.gd")
const DoorRunner := preload("res://tests/fixtures/door_runner.gd")

static var scratch_known: String = SaDataRoot.path("d22-door/door.json")
static var scratch_port_file: String = SaDataRoot.path("d22-door/door.port")
static var scratch_run_folder: String = SaDataRoot.path("d22-door-run")

## Rounds of polling before a case gives up on an answer.
const ROUNDS: int = 600

## The recovery question as `MainDialogs.offer_recoveries` asks it: Later is the
## cancel answer and Open the default.
const TITLE := "Recovered work"
const LABELS: Array[String] = ["Open", "Delete", "Later"]
const LATER: int = 2

const ZOOM := {"zoom": 1.0}

var _host: Node = null
var _canvas: SaCanvas = null
var _door: AgentDoor = null
var _run: CaptureRun = null
var _runner: DoorRunner = null
var _table: StepTable = null
var _was_embedding: bool = true
var _answers: Array = []


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    var root := _root()
    _was_embedding = root.gui_embed_subwindows
    root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "DoorTestHost"
    EventBus.add_child(_host)
    _canvas = SaCanvas.new()
    _canvas.canvas_size = Vector2i(1920, 1080)
    _host.add_child(_canvas)
    _canvas.size = Vector2(1920, 1080)
    _door = AgentDoor.new(scratch_known)
    _run = CaptureRun.new(scratch_run_folder)
    _table = StepTable.new(_run)
    _runner = DoorRunner.new(_door, _table, _run, ROUNDS, scratch_known)
    _answers = []


func after_each() -> void:
    _door.close()
    _door = null
    _table = null
    _runner = null
    _run = null
    if _host != null:
        _host.free()
        _host = null
        _canvas = null
    _root().gui_embed_subwindows = _was_embedding


static func _root() -> Window:
    return (Engine.get_main_loop() as SceneTree).root


func _ask(client: StreamPeerTCP, request: Dictionary) -> Dictionary:
    return _runner.ask(client, request)


## The recovery question, put up by `SaMessage.confirm` the way Sara does at
## boot. Its answer lands in `_answers`.
func _confirm() -> SaMessage:
    return SaMessage.confirm(_host, TITLE, "Sara kept a recovery copy.", PackedStringArray(LABELS), _heard, LATER, 0)


## The same question as a window of its own, which is what Embed subwindows off
## makes of every dialog.
##
## `force_native` set while the window is hidden stands in for the preference,
## the way `test_preferences_screen_before_shown.gd` has it: the root refuses to
## stop embedding while any embedded window is shown, and in a whole run another
## suite's window can be. `confirm` builds and shows in one call, so this builds
## the window it would and asks the same question on it.
func _confirm_native() -> SaMessage:
    var dialog := SaMessage.new()
    dialog.name = "Question"
    dialog.visible = false
    dialog.force_native = true
    _host.add_child(dialog)
    dialog.ask(TITLE, "Sara kept a recovery copy.", PackedStringArray(LABELS), _heard, LATER, 0)
    return dialog


func _heard(index: int) -> void:
    _answers.append(index)


## The entries of *answer*'s `dialogs` titled *title*.
static func _named(answer: Dictionary, title: String) -> Array:
    var found: Array = []
    for entry: Variant in answer.get("dialogs", []):
        if entry is Dictionary and String((entry as Dictionary).get("title", "")) == title:
            found.append(entry)
    return found


## The question names itself in the answer to a `zoom`, with its labels and the
## step that answers it, and once answered by that step it is gone again.
func _holds_the_question_until_it_is_answered(dialog: SaMessage, standing: Array, how: String) -> void:
    var client := _runner.connect_client()
    var answer := _ask(client, {"id": 1, "zoom": ZOOM["zoom"]})
    assert_true(bool(answer.get("ok", false)), "%s: the zoom is answered: %s" % [how, answer])
    var named := _named(answer, TITLE)
    assert_eq(named.size(), 1, "%s: the answer names the question once: %s" % [how, answer.get("dialogs")])
    var entry: Dictionary = named[0] if not named.is_empty() else {}
    assert_eq(entry.get("buttons"), LABELS, "%s: with its three labels in the order it was asked" % how)
    assert_eq(entry.get("step"), {"message": {"close": "escape"}}, "%s: the step that answers it" % how)
    assert_eq(entry.get("presses"), "Later", "%s: and the button that step presses" % how)
    assert_eq((answer.get("dialogs", []) as Array).size(), standing.size() + 1, "%s: and nothing else new" % how)

    var closed := _ask(client, {"id": 2, "message": {"close": "escape"}})
    assert_eq(_answers, [LATER], "%s: the step it named answers Later: %s" % [how, closed.get("verdicts")])
    assert_false(dialog.visible, "%s: and the question is down" % how)
    var after := _ask(client, {"id": 3, "zoom": ZOOM["zoom"]})
    assert_true(_named(after, TITLE).is_empty(), "%s: the next answer does not name it" % how)
    assert_eq(after.has("dialogs"), not standing.is_empty(), "%s: and has no dialogs key over a clear canvas" % how)
    client.disconnect_from_host()


func test_an_embedded_question_is_named_until_it_is_answered() -> void:
    var standing := SaDoorDialogs.on_screen(_root())
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var dialog := _confirm()
    assert_true(dialog.is_embedded(), "The question is embedded")
    _holds_the_question_until_it_is_answered(dialog, standing, "embedded")


func test_a_question_that_is_a_window_of_its_own_is_named_as_well() -> void:
    var standing := SaDoorDialogs.on_screen(_root())
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var dialog := _confirm_native()
    assert_false(dialog.is_embedded(), "The question is a window of its own")
    assert_false(_root().get_embedded_subwindows().has(dialog), "in no list the state dump's walk reads")
    _holds_the_question_until_it_is_answered(dialog, standing, "a window of its own")


## The first answer an agent gets is the catalogue's, which the invite tells it
## to ask for first, and a ping is the cheapest request there is. Neither runs a
## step, and both name the question all the same.
func test_the_catalogue_and_a_ping_name_it_too() -> void:
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    _confirm()
    var client := _runner.connect_client()
    var listed := _ask(client, {"id": 1, "steps": true})
    assert_eq(_named(listed, TITLE).size(), 1, "The catalogue's answer names the question: %s" % listed.get("dialogs"))
    var pinged := _ask(client, {"id": 2, "ping": true})
    assert_eq(_named(pinged, TITLE).size(), 1, "and so does a ping's")
    client.disconnect_from_host()


## A dialog that is not a message is named by its title alone, and a window that
## asks nothing, a docker's kind, is not named at all.
func test_a_dialog_is_named_by_its_title_and_a_docker_is_not_named() -> void:
    var standing := SaDoorDialogs.on_screen(_root())
    var dialog := SaRadiusDialog.new()
    _host.add_child(dialog)
    dialog.popup_centered()
    var docker := Window.new()
    docker.name = "NotADialog"
    docker.title = "not a dialog"
    _host.add_child(docker)
    var named := SaDoorDialogs.on_screen(_root())
    var radius := named.filter(func(entry: Dictionary) -> bool: return entry["title"] == dialog.title)
    assert_eq(radius.size(), 1, "The dialog is named: %s" % [named])
    assert_eq((radius[0] as Dictionary).keys() if not radius.is_empty() else [], ["title"], "by its title alone")
    assert_eq(named.size(), standing.size() + 1, "and the plain window beside it is not named")


func test_an_answer_over_a_clear_canvas_has_no_dialogs_key() -> void:
    var standing := SaDoorDialogs.on_screen(_root())
    assert_true(_door.open_port(scratch_port_file), "The TCP way in opens")
    var client := _runner.connect_client()
    var answer := _ask(client, {"id": 1, "zoom": ZOOM["zoom"]})
    assert_true(bool(answer.get("ok", false)), "The zoom is answered")
    assert_eq(answer.has("dialogs"), not standing.is_empty(), "with no dialogs key: %s" % answer.get("dialogs"))
    client.disconnect_from_host()
