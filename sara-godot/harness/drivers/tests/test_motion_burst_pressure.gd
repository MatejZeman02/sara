## `motion_burst` carries a dictionary entry's own pressure through to the
## motion it injects, and a bare pair still injects pressure 0.
##
## Before this, `motion_burst` read only `[x, y]` pairs, so a burst could put
## several hardware samples inside one process frame but never carry what a
## tablet was pressing with while it did. The dictionary form reads the same
## fields `move_pointer` does: `at`, `pressure`, `tilt` and `inverted`.
##
## Asserted against `SaInputDriver.burst_entry_motion` rather than against a
## dispatched event: an injected motion is delivered on the next input flush,
## not inside the call that queues it, so nothing here can see one arrive
## without processing a frame, which this framework cannot do (a test that
## awaits drops every assertion after it).
extends "res://tests/test_framework.gd"

const InputDriver := preload("res://harness/drivers/sa_input_driver.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")

var _root: Node = null
## The run the driver is handed, which is where it leaves the pointer it aimed at.
var _run: CaptureRun = null
var _driver: SaInputDriver = null


func before_each() -> void:
    _root = Node.new()
    _root.name = "M7TestHost"
    EventBus.add_child(_root)

    _run = CaptureRun.new()
    _driver = InputDriver.new(_run)


func after_each() -> void:
    _driver = null
    if _root != null:
        _root.free()
        _root = null


## The loop itself, mixing both shapes in one burst: nothing here proves the
## event that reached `Input.parse_input_event` carried the right pressure
## (see the header), but the runner's own pointer, which `_inject_motion`
## writes synchronously, does prove the loop reached every entry in order.
func test_a_mixed_burst_reaches_every_entry_in_order() -> void:
    _driver.motion_burst([[1.0, 2.0], {"at": [3.0, 4.0], "pressure": 0.5}])
    assert_eq(_run.last_pointer, Vector2(3, 4), "the dictionary entry after the bare pair was the last one injected")


## A malformed entry, of either shape, is skipped rather than injected, so it
## leaves the pointer at whatever the entry before it set.
func test_a_malformed_entry_is_skipped_and_leaves_the_pointer_alone() -> void:
    _driver.motion_burst([{"at": [7.0, 8.0]}, {"pressure": 0.9}])
    assert_eq(_run.last_pointer, Vector2(7, 8), "the malformed second entry injected nothing")


func test_a_dictionary_entry_carries_its_own_pressure_and_tilt() -> void:
    var found: Dictionary = InputDriver.burst_entry_motion({"at": [10.0, 20.0], "pressure": 0.8, "tilt": [0.3, 0.4]})
    assert_eq(found["pos"], Vector2(10, 20), "the point is the entry's own")
    assert_eq(found["pressure"], 0.8, "and so is the pressure")
    assert_eq(found["tilt"], Vector2(0.3, 0.4), "and the tilt")
    assert_false(found["inverted"], "inverted defaults to false")


func test_a_dictionary_entry_with_no_pressure_answers_zero() -> void:
    var found: Dictionary = InputDriver.burst_entry_motion({"at": [5.0, 6.0]})
    assert_eq(found["pressure"], 0.0, "the same default a bare pair injects")


func test_an_inverted_entry_carries_the_flag() -> void:
    var found: Dictionary = InputDriver.burst_entry_motion({"at": [1.0, 2.0], "inverted": true})
    assert_true(found["inverted"], "the eraser end reaches the motion")


## Missing or short, the same way a malformed bare pair is skipped by the loop.
func test_a_dictionary_entry_with_no_usable_at_answers_null() -> void:
    assert_null(InputDriver.burst_entry_motion({"pressure": 0.9}), "no 'at' at all")
    assert_null(InputDriver.burst_entry_motion({"at": [1.0], "pressure": 0.9}), "one coordinate is not a point")
