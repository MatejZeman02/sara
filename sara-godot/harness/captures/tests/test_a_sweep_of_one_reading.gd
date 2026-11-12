## A `sweep` step asking for one reading feeds numbers, not NaN.
##
## `SaTabletSweepCapture._scratch` spaced its readings by `readings - 1`, so a
## step with `"readings": 1` divided nought by nought for its first reading and
## one by nought for its second, and the sweep dialog was handed a NaN and an
## infinity as pressure and place. The dialog is stood in for by an object with
## the three methods the scratch calls, since the capture reaches it untyped.
extends "res://tests/test_framework.gd"

const SweepCapture := preload("res://harness/captures/tablet_sweep_capture.gd")

var _dialogs: Array[FakeDialog] = []


## What the scratch hands the dialog, kept rather than drawn.
class FakeDialog:
    extends Node

    var fed: Array = []
    var ended: bool = false

    func begin_sweep(_index: int) -> void:
        pass

    func feed(_index: int, along: float, pressure: float, _across: float = 0.0) -> void:
        fed.append(Vector2(along, pressure))

    func end_sweep(_index: int) -> void:
        ended = true


## A stand-in freed after each case, since a Node is not reference counted.
func _dialog() -> FakeDialog:
    var dialog := FakeDialog.new()
    _dialogs.append(dialog)
    return dialog


func after_each() -> void:
    for dialog: FakeDialog in _dialogs:
        dialog.free()
    _dialogs.clear()


func _all_finite(fed: Array) -> bool:
    for reading: Vector2 in fed:
        if not is_finite(reading.x) or not is_finite(reading.y):
            return false
    return true


func test_one_reading_feeds_finite_numbers() -> void:
    var dialog := _dialog()
    SweepCapture._scratch(dialog, {"readings": 1})
    assert_eq(dialog.fed.size(), 2, "two readings, the loop's floor")
    assert_true(_all_finite(dialog.fed), "no NaN or infinity reaches the dialog: %s" % [dialog.fed])
    assert_true(dialog.ended, "a whole sweep ends")


func test_no_reading_runs_from_nought_to_one() -> void:
    var dialog := _dialog()
    SweepCapture._scratch(dialog, {"readings": 0, "shape": 1.0})
    assert_true(_all_finite(dialog.fed), "finite: %s" % [dialog.fed])
    assert_almost_eq(dialog.fed[0].y, 0.0)
    assert_almost_eq(dialog.fed[1].y, 1.0)


func test_forty_readings_are_spaced_as_before() -> void:
    var dialog := _dialog()
    SweepCapture._scratch(dialog, {"readings": 40, "shape": 1.0})
    assert_eq(dialog.fed.size(), 40)
    assert_almost_eq(dialog.fed[39].x, 1.0, 1e-5, "the last reading at the far end")
    assert_almost_eq(dialog.fed[39].y, 1.0)
