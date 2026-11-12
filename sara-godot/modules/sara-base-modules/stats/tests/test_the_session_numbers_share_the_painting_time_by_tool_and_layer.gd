## The Stats docker's session numbers show the painting time, each tool's share
## of it and each layer's time, read off the session log.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The recorder names the tool and the layer in its log and times each stroke
## from its press to its release, and the part reads that tally at each refresh
## of the docker. The suite plays strokes of known lengths with two tools on two
## layers into a running recorder, and reads the rows as the `pages` block of
## the dump does: each tool titled by its name with its share, each layer by
## its name with its time, within one per cent, the larger first, and no row
## for a tool or a layer there is not. Without a log none of them is shown, a
## session of more tools than rows folds the rest into the last, and the names
## join the line each stop writes.
extends "res://tests/test_framework.gd"

const SessionNumbers := preload("../session_numbers.gd")

const WINDOW := Vector2(1920, 1080)
const VIEW := Rect2(0, 0, 1920, 1080)

static var scratch_folder: String = SaDataRoot.path("test_n6_session_shares")

var _part: SaStatsPart = null
var _page: SaPage = null
var _box: VBoxContainer = null
var _recorder: SaStrokeRecorder = null
var _document: SaDocument = null
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
    # In the tree, as the canvas's document is, since a node out of it is
    # renamed without a word. Hung off `EventBus`, which readies nothing, because
    # the runner's root is still readying its own children.
    _document = SaDocument.new()
    EventBus.add_child(_document)


func after_each() -> void:
    if _recorder != null:
        _recorder.close()
        DirAccess.remove_absolute(_recorder.path)
    _recorder = null
    _box.free()
    _page = null
    _part = null
    _document.free()
    _document = null


func test_without_a_log_no_time_row_is_shown() -> void:
    for key: StringName in [&"painting_time", &"session_tools", &"session_tool_1", &"session_layers", &"session_layer_1"]:
        assert_false(_told(key)["shown"], "%s waits for a log" % key)


func test_two_tools_on_two_layers_read_their_shares_and_times() -> void:
    _open("two")
    var ground := _layer("Ground")
    var sky := _layer("Sky")
    _document.active_layer = ground
    _recorder.follow(_document)
    EventBus.tool_changed.emit("brush")
    for stroke in 3:
        _stroke(2.0)
    EventBus.tool_changed.emit("eraser")
    _stroke(1.5)
    _document.active_layer = sky
    _stroke(2.5)
    _stroke(2.5)
    EventBus.tool_changed.emit("brush")
    _stroke(3.0)
    _stroke(3.0)
    _part.refresh(null)

    var whole := 18.5
    assert_true(_told(&"painting_time")["shown"], "With a log the painting time is shown")
    assert_almost_eq(float(_told(&"painting_time")["value"]), whole, whole * 0.01, "the strokes' time, the pauses left out")
    assert_eq((_page.row(&"painting_time").control as Label).text, "18.5 s", "as the docker says it")
    assert_eq(_told(&"session_tools")["value"], 2, "Two tools")
    assert_eq(_told(&"session_tool_1")["label"], "brush", "the brush first, named")
    assert_almost_eq(float(_told(&"session_tool_1")["value"]), 100.0 * 12.0 / whole, 1.0, "with its share in per cent")
    assert_eq((_page.row(&"session_tool_1").control as Label).text, "65 %")
    assert_eq(_told(&"session_tool_2")["label"], "eraser", "then the eraser")
    assert_almost_eq(float(_told(&"session_tool_2")["value"]), 100.0 * 6.5 / whole, 1.0, "with its share")
    assert_true(_told(&"session_tool_2")["shown"], "Both tool rows are shown")
    assert_false(_told(&"session_tool_3")["shown"], "and none for a third")
    assert_eq(_told(&"session_layers")["value"], 2, "Two layers")
    assert_eq(_told(&"session_layer_1")["label"], "Sky", "Sky first, the longer")
    assert_almost_eq(float(_told(&"session_layer_1")["value"]), 11.0, 0.11, "with its seconds")
    assert_eq(_told(&"session_layer_2")["label"], "Ground", "then Ground")
    assert_almost_eq(float(_told(&"session_layer_2")["value"]), 7.5, 0.075, "with its seconds")
    assert_false(_told(&"session_layer_3")["shown"], "and no row for a third layer")

    _recorder.close()
    _part.refresh(null)
    assert_false(_told(&"session_tool_1")["shown"], "A closed log hides the tools")
    assert_false(_told(&"session_layer_1")["shown"], "and the layers")


func test_more_tools_than_rows_fold_into_the_last() -> void:
    _open("many")
    _document.active_layer = _layer("Paint")
    _recorder.follow(_document)
    var tools := SessionNumbers.MOST_TOOLS + 2
    for at in tools:
        EventBus.tool_changed.emit("tool_%02d" % at)
        _stroke(float(tools - at))
    _part.refresh(null)
    assert_eq(_told(&"session_tools")["value"], SessionNumbers.MOST_TOOLS, "Every tool row in use")
    assert_eq((_page.row(&"session_tools").control as Label).text, str(tools), "and the count says them all")
    var last := StringName("session_tool_%d" % SessionNumbers.MOST_TOOLS)
    assert_eq(_told(last)["label"], "3 other tools", "The last row adds up the three left over")
    var whole := 0.0
    for at in tools:
        whole += float(tools - at)
    assert_almost_eq(float(_told(last)["value"]), 100.0 * (3.0 + 2.0 + 1.0) / whole, 1.0, "with their share")


func test_the_names_join_the_line_a_stop_writes() -> void:
    var service := SaReductionService.new()
    var clock := SaIdleClock.new()
    var docker := StatsDocker.new(service, clock)
    _open("line")
    _document.active_layer = _layer("Sky")
    _recorder.follow(_document)
    EventBus.tool_changed.emit("brush")
    _stroke(2.0)
    for part: SaStatsPart in docker.parts:
        part.refresh(null)
    var numbers := docker.numbers()
    var titles := docker.titles()
    assert_almost_eq(float(numbers.get("painting_time", 0.0)), 2.0, 0.02, "The painting time is one of the line's numbers")
    assert_almost_eq(float(numbers.get("session_tool_1", 0.0)), 100.0, 0.1, "and the one tool's share")
    assert_eq(titles.get("session_tool_1"), "brush", "under its name")
    assert_eq(titles.get("session_layer_1"), "Sky", "and the layer's under its own")
    assert_false(numbers.has("session_tool_2"), "A row not in use is not on the line")
    docker.free()
    service.free()
    clock.free()


func test_a_duration_reads_as_the_rows_say_it() -> void:
    assert_eq(SessionNumbers.duration(42_500_000), "42.5 s")
    assert_eq(SessionNumbers.duration(192_000_000), "3 min 12 s")
    assert_eq(SessionNumbers.duration(3_840_000_000), "1 h 4 min")


func _open(folder: String) -> void:
    _recorder = SaStrokeRecorder.new(scratch_folder.path_join(folder), {"display_driver": "test"}, _clock)
    assert_true(SaStrokeRecorder.running == _recorder, "The recorder runs")


## The log's clock the recorder is handed, reading the time the suite set.
func _clock() -> int:
    return now_usec


func _layer(layer_name: String) -> SaLayer:
    var layer := SaLayer.new()
    layer.name = layer_name
    _document.add_child(layer)
    return layer


## A left press, twenty motions, the release *seconds* after the press, and
## twenty seconds of pause.
func _stroke(seconds: float) -> void:
    var start := now_usec
    _button(true)
    for reading in 20:
        now_usec = start + int(seconds * 1e6 * float(reading + 1) / 21.0)
        var motion := InputEventMouseMotion.new()
        motion.position = Vector2(300 + reading, 200)
        motion.pressure = 0.5
        motion.button_mask = MOUSE_BUTTON_MASK_LEFT
        _recorder.record(motion, WINDOW, VIEW, Transform2D.IDENTITY)
    now_usec = start + int(seconds * 1e6)
    _button(false)
    now_usec += 20_000_000


func _button(down: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = down
    _recorder.record(event, WINDOW, VIEW, Transform2D.IDENTITY)


## The row of *key* as the `pages` block of the state dump describes it.
func _told(key: StringName) -> Dictionary:
    var row := _page.row(key)
    assert_not_null(row, "The page has a row %s" % key)
    return row.describe() if row != null else {"shown": false, "value": null, "label": ""}
