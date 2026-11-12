## A capture `move` aims at a named control, the way `click` always has.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `move_pointer` read `at` off the step and nothing else, so
## `{"move": {"control": "MinimizeBtn"}}` returned without a word and left the
## pointer where the step before it had put it. Nothing failed: the run went on
## to wait, shoot and dump, and what it shot was whatever had been under the
## pointer since the last step that did name a point. A reading taken that way
## costs an hour, which is why a step that does nothing has to say so.
##
## The pointer's own record is what these read, `last_pointer` on the runner,
## because that is what `_inject_motion` writes and what the next `relative` is
## measured from. What the running app does with the events is
## `scenarios/a-tooltip-shows-only-inside-a-dialog-under-the-capture-harness.json`.
extends "res://tests/test_framework.gd"

const InputDriver := preload("res://harness/drivers/sa_input_driver.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")

const BUTTON_AT := Vector2(300, 200)
const BUTTON_SIZE := Vector2(80, 40)

var _root: Node = null
var _host: Control = null
var _button: Button = null
## The run the driver is handed, which is where it leaves the pointer it aimed at.
var _run: CaptureRun = null
var _driver: SaInputDriver = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _root = Node.new()
    _root.name = "D22TestHost"
    EventBus.add_child(_root)

    _host = Control.new()
    _host.set_anchors_preset(Control.PRESET_FULL_RECT)
    _root.add_child(_host)

    _button = Button.new()
    _button.name = "D22ProbeButton"
    _button.position = BUTTON_AT
    _button.size = BUTTON_SIZE
    _button.custom_minimum_size = BUTTON_SIZE
    _host.add_child(_button)

    _run = CaptureRun.new()
    _driver = InputDriver.new(_run)


func after_each() -> void:
    _driver = null
    if _root != null:
        _root.free()
        _root = null


## The form that silently did nothing.
func test_a_move_at_a_named_control_reaches_its_centre() -> void:
    _driver.move_pointer({"control": "D22ProbeButton"})
    assert_eq(_run.last_pointer, _button.get_global_rect().get_center(), "the pointer is on the control the step named")


## And a step that names a control nothing answers to leaves the pointer alone
## rather than moving it somewhere arbitrary. `point_of` says so out loud, which
## is the half that was missing.
func test_a_move_at_a_control_that_is_not_there_moves_nothing() -> void:
    _run.last_pointer = Vector2(11, 13)
    _driver.move_pointer({"control": "NoSuchControlAnywhere"})
    assert_eq(_run.last_pointer, Vector2(11, 13), "the pointer stayed where it was")


## The two forms every scenario in the tree already uses, asserted so the change
## above cannot have cost them.
func test_a_bare_pair_still_moves_the_pointer() -> void:
    _driver.move_pointer([640.0, 480.0])
    assert_eq(_run.last_pointer, Vector2(640, 480), "a plain [x, y] is still a point")


func test_an_at_key_still_moves_the_pointer() -> void:
    _driver.move_pointer({"at": [12.0, 34.0], "pressure": 0.5})
    assert_eq(_run.last_pointer, Vector2(12, 34), "and so is an 'at' with pen telemetry beside it")


## A step with neither is the one case that has to refuse, and it refused before
## this change as well. Held here because the refusal is now `point_of`'s rather
## than `move_pointer`'s own, and a silent return is what this unit is about.
func test_a_move_with_neither_a_point_nor_a_control_moves_nothing() -> void:
    _run.last_pointer = Vector2(7, 9)
    _driver.move_pointer({"pressure": 0.5})
    assert_eq(_run.last_pointer, Vector2(7, 9), "the pointer stayed where it was")
