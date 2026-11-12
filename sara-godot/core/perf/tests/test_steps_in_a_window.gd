## A perf window times the steps it holds around their own call,
## so the baseline's tool switch reads what a switch costs and not the frames
## the scenario waited between its steps.
extends "res://tests/test_framework.gd"

## `end` draws two frames.
const REQUIRES_GPU := true

## How long the stand-in step spins, in microseconds.
const SPIN_USEC := 300

var _easel: SaEasel
var _lines: Array[String] = []


func before_each() -> void:
    SaPerfWindow.forget()
    _easel = SaEasel.create_default(Vector2i(64, 64))
    _lines.clear()


func after_each() -> void:
    SaPerfWindow.forget()
    _easel.free()
    _easel = null


## The step table in miniature: a `measure` goes to the window, anything else
## spins for `SPIN_USEC`, the cost a real step would have.
func _run(step: Dictionary) -> void:
    if step.has("measure"):
        _lines.append(SaMeasure.capture(_easel.document, step["measure"] as Dictionary))
        return
    var until := Time.get_ticks_usec() + SPIN_USEC
    while Time.get_ticks_usec() < until:
        pass


func _window() -> Dictionary:
    var line: String = _lines.back()
    var parsed: Variant = JSON.parse_string(line.trim_prefix("SaCapture: measure perf "))
    return (parsed as Dictionary)["window"] if parsed is Dictionary else {}


func test_the_steps_inside_are_timed_and_the_measures_and_the_outside_are_not() -> void:
    SaPerfWindow.hold_step({"tool": "eraser"}, _run)
    SaPerfWindow.hold_step({"measure": {"perf": "begin"}}, _run)
    SaPerfWindow.hold_step({"tool": "brush"}, _run)
    SaPerfWindow.hold_step({"tool": "eraser"}, _run)
    SaPerfWindow.hold_step({"measure": {"perf": "end"}}, _run)
    SaPerfWindow.hold_step({"tool": "brush"}, _run)

    var window := _window()
    assert_eq(int(window["steps"]), 2, "the two switches inside, neither measure nor the switches outside")
    assert_true(int(window["steps_usec"]) >= 2 * SPIN_USEC, "each timed around its own call: %s" % window["steps_usec"])
    assert_true(int(window["steps_usec_max"]) >= SPIN_USEC, "the longest is one step's")
    assert_true(int(window["steps_usec"]) < int(window["usec"]), "and less than the window, which the forced draws pace")


func test_a_second_window_starts_from_nothing() -> void:
    SaPerfWindow.hold_step({"measure": {"perf": "begin"}}, _run)
    SaPerfWindow.hold_step({"tool": "brush"}, _run)
    SaPerfWindow.hold_step({"measure": {"perf": "end"}}, _run)
    SaPerfWindow.hold_step({"measure": {"perf": "begin"}}, _run)
    SaPerfWindow.hold_step({"measure": {"perf": "end"}}, _run)
    assert_eq(int(_window()["steps"]), 0, "begin cleared the first window's steps")
    assert_eq(int(_window()["steps_usec"]), 0, "and their time")
