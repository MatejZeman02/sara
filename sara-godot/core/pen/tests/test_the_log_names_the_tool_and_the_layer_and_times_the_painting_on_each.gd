## The session log names the tool in hand and the active layer, and the tally
## gives each stroke's press-to-release time to the two it was painted with.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The Stats docker's time per layer and share per tool come from the log, so
## the log has to say which tool and which layer a stroke was on. The suite
## hands the recorder a clock of its own, so seconds pass in a moment, follows a
## document of two layers, switches between two tools on `EventBus.tool_changed`
## as a tool machine does, and plays strokes of known lengths with long pauses
## between them. Each tool's share and each layer's time read within one per
## cent of what was played, the pauses counting for nothing, and the file read
## back line by line gives the same. A layer is named as the painter sees it,
## so a rename is a line and the time stays with the one layer under its new
## name, and a tool or a layer named again unchanged writes nothing.
extends "res://tests/test_framework.gd"

static var scratch_folder: String = SaDataRoot.path("test_n6_tool_and_layer")

const WINDOW := Vector2(1920, 1080)
const VIEW := Rect2(0, 0, 1920, 1080)

## What the clock the recorder is handed reads, in microseconds.
var now_usec: int = 0
var _recorder: SaStrokeRecorder = null
var _document: SaDocument = null
var _ground: SaLayer = null
var _sky: SaLayer = null


func before_each() -> void:
    now_usec = 0
    # In the tree, as the canvas's document is, since a node out of it is
    # renamed without a word. Hung off `EventBus`, which readies nothing, because
    # the runner's root is still readying its own children.
    _document = SaDocument.new()
    EventBus.add_child(_document)
    _ground = _layer("Ground")
    _sky = _layer("Sky")
    _document.active_layer = _ground


func after_each() -> void:
    if _recorder != null:
        _recorder.close()
        DirAccess.remove_absolute(_recorder.path)
    _recorder = null
    _document.free()
    _document = null


func test_strokes_on_two_layers_with_two_tools_share_their_painting_time() -> void:
    _open("shares")
    _recorder.follow(_document)
    EventBus.tool_changed.emit("brush")
    # Brush on Ground, three strokes of two seconds, ten seconds apart.
    for stroke in 3:
        _stroke(2.0, 10.0)
    EventBus.tool_changed.emit("eraser")
    _stroke(1.5, 30.0)
    _document.active_layer = _sky
    for stroke in 2:
        _stroke(2.5, 10.0)
    EventBus.tool_changed.emit("brush")
    for stroke in 2:
        _stroke(3.0, 45.0)

    var tally := _recorder.tally
    var brush := 3 * 2.0 + 2 * 3.0
    var eraser := 1.5 + 2 * 2.5
    var whole := brush + eraser
    assert_almost_eq(
        tally.painting_usec / 1e6, whole, whole * 0.01, "The painting time is the strokes' alone, the pauses left out"
    )
    var tools := _by_name(tally.by_tool())
    assert_eq(tools.keys().size(), 2, "Two tools")
    assert_almost_eq(float(tools["brush"]["share"]), brush / whole, 0.01, "The brush's share, %.3f" % (brush / whole))
    assert_almost_eq(float(tools["eraser"]["share"]), eraser / whole, 0.01, "the eraser's, %.3f" % (eraser / whole))
    assert_eq(String(tally.by_tool()[0]["name"]), "brush", "the larger share first")
    var layers := _by_name(tally.by_layer())
    assert_eq(layers.keys().size(), 2, "Two layers")
    var ground := 3 * 2.0 + 1.5
    var sky := 2 * 2.5 + 2 * 3.0
    assert_almost_eq(int(layers["Ground"]["usec"]) / 1e6, ground, ground * 0.01, "Ground's time, %.1f s" % ground)
    assert_almost_eq(int(layers["Sky"]["usec"]) / 1e6, sky, sky * 0.01, "Sky's time, %.1f s" % sky)
    assert_eq(String(tally.by_layer()[0]["name"]), "Sky", "the longer first")

    _recorder.close()
    var rows := _rows(_recorder.path)
    var again := SaStrokeRecorder.Tally.new()
    for row: Dictionary in rows:
        again.take(row)
    assert_eq(again.strokes, 8, "The file read back holds the eight strokes")
    assert_almost_eq(float(_by_name(again.by_tool())["brush"]["share"]), brush / whole, 0.01, "and the same shares")
    assert_almost_eq(int(_by_name(again.by_layer())["Sky"]["usec"]) / 1e6, sky, sky * 0.01, "and the same times")
    var first_reading := -1
    var first_tool := -1
    var first_layer := -1
    for at in rows.size():
        var kind := String(rows[at].get("k", ""))
        if kind in ["d", "u", "m"] and first_reading < 0:
            first_reading = at
        elif kind == SaStrokeRecorder.TOOL and first_tool < 0:
            first_tool = at
        elif kind == SaStrokeRecorder.LAYER and first_layer < 0:
            first_layer = at
    assert_true(first_layer >= 0 and first_layer < first_reading, "A layer is named before the first reading")
    assert_true(first_tool >= 0 and first_tool < first_reading, "and a tool")


func test_a_renamed_layer_is_named_again_and_keeps_its_time() -> void:
    _document.active_layer = null
    var fresh := _layer("Layer 3")
    _document.active_layer = fresh
    _open("renamed")
    _recorder.follow(_document)
    EventBus.tool_changed.emit("brush")
    _stroke(1.0, 5.0)
    fresh.name = "Clouds"
    _stroke(2.0, 5.0)
    var layers := _recorder.tally.by_layer()
    assert_eq(layers.size(), 1, "One layer, renamed")
    assert_eq(String(layers[0]["name"]), "Clouds", "under the name it has now")
    assert_almost_eq(int(layers[0]["usec"]) / 1e6, 3.0, 0.03, "with the time before the rename and after")
    _recorder.close()
    var named: Array[String] = []
    for row: Dictionary in _rows(_recorder.path):
        if row.get("k") == SaStrokeRecorder.LAYER:
            named.append("%d %s" % [int(row["id"]), row["name"]])
    assert_eq(named, ["1 Layer 3", "1 Clouds"] as Array[String], "The log names it twice, by one number")


func test_a_tool_or_a_layer_named_again_unchanged_writes_nothing() -> void:
    _open("unchanged")
    _recorder.follow(_document)
    EventBus.tool_changed.emit("brush")
    var written := _recorder.lines
    EventBus.tool_changed.emit("brush")
    _document.active_layer = _ground
    _recorder.follow(_document)
    assert_eq(_recorder.lines, written, "The same tool and the same layer again add no line")
    _document.active_layer = _sky
    _document.active_layer = _ground
    assert_eq(_recorder.lines, written + 2, "A layer and back are two, Ground keeping its number")
    assert_eq(_recorder.tally.layer_names.keys().size(), 2, "two layers named")


func test_a_closed_recorder_hears_neither() -> void:
    _open("closed")
    _recorder.follow(_document)
    EventBus.tool_changed.emit("brush")
    _recorder.close()
    var written := _recorder.lines
    EventBus.tool_changed.emit("eraser")
    _document.active_layer = _sky
    _sky.name = "Sky at dusk"
    assert_eq(_recorder.lines, written, "Closed, a switch, a layer and a rename write nothing")
    for connection: Dictionary in EventBus.tool_changed.get_connections():
        assert_false((connection["callable"] as Callable).get_object() == _recorder, "and it no longer listens")


func test_a_stroke_too_short_to_count_adds_no_time() -> void:
    _open("short")
    _recorder.follow(_document)
    EventBus.tool_changed.emit("brush")
    _stroke(4.0, 1.0, SaStrokeRecorder.Tally.LEAST_READINGS - 1)
    assert_eq(_recorder.tally.painting_usec, 0, "A stroke the training script would not read has no time")
    assert_true(_recorder.tally.by_tool().is_empty(), "and puts no tool on the list")


func _open(folder: String) -> void:
    _recorder = SaStrokeRecorder.new(scratch_folder.path_join(folder), {"display_driver": "test"}, _clock)
    assert_true(_recorder.is_recording(), "The file opened under the data root")


## The log's clock the recorder is handed, reading the time the suite set.
func _clock() -> int:
    return now_usec


func _layer(layer_name: String) -> SaLayer:
    var layer := SaLayer.new()
    layer.name = layer_name
    _document.add_child(layer)
    return layer


## A left press, *readings* motions spread evenly over *seconds*, the release
## *seconds* after the press, and a pause of *pause* seconds after it.
func _stroke(seconds: float, pause: float, readings: int = 20) -> void:
    var start := now_usec
    _button(true)
    for reading in readings:
        now_usec = start + int(seconds * 1e6 * float(reading + 1) / float(readings + 1))
        var motion := InputEventMouseMotion.new()
        motion.position = Vector2(300 + reading, 200)
        motion.pressure = 0.5
        motion.button_mask = MOUSE_BUTTON_MASK_LEFT
        _recorder.record(motion, WINDOW, VIEW, Transform2D.IDENTITY)
    now_usec = start + int(seconds * 1e6)
    _button(false)
    now_usec += int(pause * 1e6)


func _button(down: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = down
    _recorder.record(event, WINDOW, VIEW, Transform2D.IDENTITY)


## The lines of the closed file at *path* after its header, parsed.
func _rows(path: String) -> Array[Dictionary]:
    var rows: Array[Dictionary] = []
    var file := FileAccess.open(path, FileAccess.READ)
    assert_not_null(file, "The log is readable after close")
    if file == null:
        return rows
    file.get_line()
    while not file.eof_reached():
        var line := file.get_line()
        if not line.is_empty():
            rows.append(JSON.parse_string(line) as Dictionary)
    return rows


## *spent*, as the tally lists it, by name.
static func _by_name(spent: Array[Dictionary]) -> Dictionary:
    var out := {}
    for entry: Dictionary in spent:
        out[String(entry["name"])] = entry
    return out
