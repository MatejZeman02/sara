## The Stats docker's session numbers read the strokes the session log holds,
## how many a minute and their mean pressure, or name the flag that starts the
## log while none is recorded.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The part reads the running recorder's count at each refresh of the docker.
## The suite plays twelve strokes over two minutes of the log's clock, handed
## to the recorder so two minutes pass in a moment, at pressures it knows, and
## reads twelve strokes, six a minute and the mean of those pressures off the
## rows as the `pages` block of the dump does. With no recorder the one row
## shown is the sentence naming `--record-strokes` and `SARA_RECORD_STROKES`,
## and a closed recorder puts it back. In the docker the numbers join the line
## each stop writes into the log, and the sentence never does.
extends "res://tests/test_framework.gd"

const SessionNumbers := preload("../session_numbers.gd")

const WINDOW := Vector2(1920, 1080)
const VIEW := Rect2(0, 0, 1920, 1080)

static var scratch_folder: String = SaDataRoot.path("test_n5_session_numbers")

var _part: SaStatsPart = null
var _page: SaPage = null
var _box: VBoxContainer = null
var _recorder: SaStrokeRecorder = null
## What the clock the recorder is handed reads, in microseconds.
var now_usec: int = 0


func before_each() -> void:
    now_usec = 0
    assert_null(SaStrokeRecorder.running, "No recorder runs under the suites")
    _part = SessionNumbers.new()
    _page = SaPage.new(_part.declare)
    _page.declare_rows()
    _box = VBoxContainer.new()
    _page.realize(_box)


func after_each() -> void:
    if _recorder != null:
        _recorder.close()
        DirAccess.remove_absolute(_recorder.path)
    _recorder = null
    _box.free()
    _page = null
    _part = null


func test_without_a_recorder_the_rows_name_the_flag() -> void:
    var said := _told(&"session_log")
    assert_true(said["shown"], "With no log the sentence is shown")
    assert_true(String(said["value"]).contains("--record-strokes=<folder>"), "and names the flag, read %s" % said["value"])
    assert_true(String(said["value"]).contains("SARA_RECORD_STROKES=<folder>"), "and the variable")
    assert_eq((_page.row(&"session_log").control as Label).text, SessionNumbers.no_log(), "as the docker shows it")
    for key: StringName in [&"session_strokes", &"strokes_a_minute", &"mean_pressure"]:
        assert_false(_told(key)["shown"], "%s waits for a log" % key)


func test_twelve_strokes_over_two_minutes_read_twelve_six_a_minute_and_their_mean_pressure() -> void:
    _open("twelve")
    var mean := _play_twelve_strokes()
    _part.refresh(null)
    assert_false(_told(&"session_log")["shown"], "With a log the sentence goes")
    assert_true(_told(&"session_strokes")["shown"], "and the numbers come")
    assert_eq(_told(&"session_strokes")["value"], 12, "Twelve strokes")
    assert_almost_eq(float(_told(&"strokes_a_minute")["value"]), 6.0, 0.001, "six a minute")
    assert_almost_eq(float(_told(&"mean_pressure")["value"]), mean, 0.01, "and the mean pressure, %.3f" % mean)
    assert_eq((_page.row(&"session_strokes").control as Label).text, "12", "as the docker shows them")
    assert_eq((_page.row(&"strokes_a_minute").control as Label).text, "6.0")

    _recorder.close()
    _part.refresh(null)
    assert_true(_told(&"session_log")["shown"], "A closed log names the flag again")
    assert_false(_told(&"session_strokes")["shown"], "and hides the numbers")


func test_the_numbers_join_the_line_a_stop_writes_and_the_sentence_never_does() -> void:
    var service := SaReductionService.new()
    var clock := SaIdleClock.new()
    var docker := StatsDocker.new(service, clock)
    var numbers := docker.numbers()
    assert_true(numbers.has("session_log"), "With no log the docker holds the sentence")
    _open("line")
    _play_twelve_strokes()
    # What the docker does after each run, without a run.
    for part: SaStatsPart in docker.parts:
        part.refresh(null)
    numbers = docker.numbers()
    assert_eq(numbers.get("session_strokes"), 12, "With a log the stroke count is one of the line's numbers")
    assert_true(numbers.has("strokes_a_minute") and numbers.has("mean_pressure"), "with the rate and the pressure")
    assert_false(numbers.has("session_log"), "and the sentence is not")
    assert_eq(docker.titles().get("strokes_a_minute"), "Strokes a minute", "each under its title")
    docker.free()
    service.free()
    clock.free()


func _open(folder: String) -> void:
    _recorder = SaStrokeRecorder.new(scratch_folder.path_join(folder), {"display_driver": "test"}, _clock)
    assert_true(SaStrokeRecorder.running == _recorder, "The recorder runs")


## The log's clock the recorder is handed, reading the time the suite set.
func _clock() -> int:
    return now_usec


## Twelve strokes ten seconds apart, the clock at two minutes after them, each
## of fourteen motions at pressures known. Returns their mean.
func _play_twelve_strokes() -> float:
    var sum := 0.0
    var count := 0
    for stroke in 12:
        now_usec = stroke * 10_000_000
        _button(true)
        for reading in 14:
            var pressure := 0.2 + 0.04 * float(stroke) + 0.02 * float(reading % 3)
            now_usec += 10_000
            var motion := InputEventMouseMotion.new()
            motion.position = Vector2(300 + reading, 200)
            motion.pressure = pressure
            motion.button_mask = MOUSE_BUTTON_MASK_LEFT
            _recorder.record(motion, WINDOW, VIEW, Transform2D.IDENTITY)
            sum += pressure
            count += 1
        _button(false)
    now_usec = 120_000_000
    return sum / float(count)


func _button(down: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = down
    _recorder.record(event, WINDOW, VIEW, Transform2D.IDENTITY)


## The row of *key* as the `pages` block of the state dump describes it.
func _told(key: StringName) -> Dictionary:
    var row := _page.row(key)
    assert_not_null(row, "The page has a row %s" % key)
    return row.describe() if row != null else {"shown": false, "value": null}
