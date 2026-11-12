## The stroke recorder counts the strokes it writes, how many a minute and the
## mean pressure inside them.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The Stats docker's session numbers come from the log, and a stroke is what
## the training script reads as one: the left button's press to its release,
## holding ten motions or more. The suite plays twelve strokes over two minutes
## of the log's own clock, handed in so two minutes pass in a moment, at
## pressures it knows, and reads twelve strokes, six a minute and the mean of
## those pressures. A stroke too short to count, the right button and a motion
## outside a stroke add nothing, a second press starts the stroke again, and
## the file read back by the training script's rule holds what was counted.
extends "res://tests/test_framework.gd"

static var scratch_folder: String = SaDataRoot.path("test_n5_recorder_tally")

const WINDOW := Vector2(1920, 1080)
const VIEW := Rect2(0, 0, 1920, 1080)

## What the clock the recorder is handed reads, in microseconds.
var now_usec: int = 0
var _recorder: SaStrokeRecorder = null


func before_each() -> void:
    now_usec = 0


func after_each() -> void:
    if _recorder != null:
        _recorder.close()
        DirAccess.remove_absolute(_recorder.path)
    _recorder = null


func test_twelve_strokes_over_two_minutes_read_six_a_minute_and_their_mean_pressure() -> void:
    _open("twelve")
    var pressures: Array[float] = []
    for stroke in 12:
        now_usec = stroke * 10_000_000
        var said: Array[float] = []
        for reading in 14:
            said.append(0.15 + 0.05 * float(stroke) + 0.01 * float(reading % 4))
        _stroke(MOUSE_BUTTON_LEFT, said)
        pressures.append_array(said)
    now_usec = 120_000_000
    var mean := 0.0
    for pressure: float in pressures:
        mean += pressure
    mean /= float(pressures.size())
    assert_eq(_recorder.tally.strokes, 12, "Twelve strokes")
    assert_almost_eq(_recorder.strokes_a_minute(), 6.0, 0.001, "over two minutes of the log's clock, six a minute")
    assert_almost_eq(_recorder.tally.mean_pressure(), mean, 0.01, "and the mean of the pressures played, %.3f" % mean)
    assert_eq(_recorder.tally.readings, 12 * 14, "every motion inside a stroke counted once")

    _recorder.close()
    var read := _strokes_by_the_training_rule(_recorder.path)
    assert_eq(read.size(), 12, "The file holds the twelve strokes the training script would read")
    var sum := 0.0
    var count := 0
    for stroke: Array in read:
        for pressure: float in stroke:
            sum += pressure
            count += 1
    assert_almost_eq(sum / float(maxi(count, 1)), _recorder.tally.mean_pressure(), 0.0001, "and the count is the file's")


func test_what_the_training_script_does_not_read_as_a_stroke_counts_nothing() -> void:
    _open("short")
    _stroke(MOUSE_BUTTON_LEFT, _even(0.9, SaStrokeRecorder.Tally.LEAST_READINGS - 1))
    assert_eq(_recorder.tally.strokes, 0, "A stroke one motion short of the least is not one")
    assert_eq(_recorder.tally.readings, 0, "and its motions are not in the mean")
    _stroke(MOUSE_BUTTON_RIGHT, _even(0.9, 20))
    assert_eq(_recorder.tally.strokes, 0, "The right button draws no stroke")
    _motion(0.7)
    assert_eq(_recorder.tally.readings, 0, "A motion with no stroke open is in no mean")

    _press(MOUSE_BUTTON_LEFT, true)
    for reading in 6:
        _motion(0.9)
    _press(MOUSE_BUTTON_LEFT, true)
    for reading in SaStrokeRecorder.Tally.LEAST_READINGS:
        _motion(0.3)
    _press(MOUSE_BUTTON_LEFT, false)
    assert_eq(_recorder.tally.strokes, 1, "A second press starts the stroke again")
    assert_almost_eq(_recorder.tally.mean_pressure(), 0.3, 0.0001, "and the motions before it are left out")
    _recorder.close()
    assert_eq(_strokes_by_the_training_rule(_recorder.path).size(), 1, "as the training script reads the file")


func test_the_least_stroke_is_the_training_script_s() -> void:
    var source := FileAccess.get_file_as_string("res://scripts/train_cursor_lead.py")
    assert_true(
        source.contains("MIN_EVENTS = %d\n" % SaStrokeRecorder.Tally.LEAST_READINGS),
        "The tally's least stroke is the training script's MIN_EVENTS"
    )


func test_a_closed_recorder_counts_nothing_and_no_time_reads_no_rate() -> void:
    _open("closed")
    assert_eq(_recorder.strokes_a_minute(), 0.0, "No time passed, no rate")
    assert_eq(_recorder.tally.mean_pressure(), 0.0, "and no mean before a stroke")
    _recorder.close()
    _stroke(MOUSE_BUTTON_LEFT, _even(0.5, 20))
    assert_eq(_recorder.tally.strokes, 0, "Closed, a stroke is neither written nor counted")


func _open(folder: String) -> void:
    _recorder = SaStrokeRecorder.new(scratch_folder.path_join(folder), {"display_driver": "test"}, _clock)
    assert_true(_recorder.is_recording(), "The file opened under the data root")


## The log's clock the recorder is handed, reading the time the suite set.
func _clock() -> int:
    return now_usec


## A press of *button*, one motion at each of *pressures* a hundredth of a
## second apart, and the release.
func _stroke(button: MouseButton, pressures: Array[float]) -> void:
    _press(button, true)
    for pressure: float in pressures:
        now_usec += 10_000
        _motion(pressure)
    _press(button, false)


func _press(button: MouseButton, down: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = button
    event.pressed = down
    _recorder.record(event, WINDOW, VIEW, Transform2D.IDENTITY)


func _motion(pressure: float) -> void:
    var event := InputEventMouseMotion.new()
    event.position = Vector2(400, 300)
    event.pressure = pressure
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    _recorder.record(event, WINDOW, VIEW, Transform2D.IDENTITY)


static func _even(pressure: float, count: int) -> Array[float]:
    var out: Array[float] = []
    for at in count:
        out.append(pressure)
    return out


## The pressures of each stroke in the file at *path*, read as
## `read_recording` in the training script reads its strokes.
static func _strokes_by_the_training_rule(path: String) -> Array:
    var strokes: Array = []
    var current: Variant = null
    var file := FileAccess.open(path, FileAccess.READ)
    var first := true
    while file != null and not file.eof_reached():
        var text := file.get_line()
        if text.is_empty():
            continue
        var row: Dictionary = JSON.parse_string(text)
        if first:
            first = false
            if not row.has("k"):
                continue
        var kind: String = row.get("k", "")
        if kind == "d" and int(row.get("btn", 0)) == 1:
            current = []
        elif kind == "u" and int(row.get("btn", 0)) == 1:
            if current != null and (current as Array).size() >= 10:
                strokes.append(current)
            current = null
        elif kind == "m" and current != null:
            (current as Array).append(float(row.get("p", 0.0)))
    return strokes
