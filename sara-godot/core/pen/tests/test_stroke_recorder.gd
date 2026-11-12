## The stroke recorder writes one JSON line per pointer reading and a header
## that says what the session ran on, and it is switched on by a flag or the
## environment and by nothing else.
##
## The learned cursor lead spec trains on recordings of a painter's own
## painting, so what has to hold is that every motion carries the position,
## the pressure, the tilt, the window and the view, that a press and a release
## are their own lines, that anything else is ignored, and that the file is
## whole after close. The flag parsing is held against a synthetic argument
## list because the process's own command line already carries real flags
## under the offscreen gate.
extends "res://tests/test_framework.gd"

static var scratch_folder: String = SaDataRoot.path("test_stroke_recorder")


func test_folder_from_flag_and_environment() -> void:
    assert_eq(SaStrokeRecorder.folder_from(PackedStringArray(["--record-strokes=/tmp/a"]), ""), "/tmp/a")
    assert_eq(SaStrokeRecorder.folder_from(PackedStringArray(["--record-strokes", "/tmp/b"]), ""), "/tmp/b")
    assert_eq(SaStrokeRecorder.folder_from(PackedStringArray(["--capture=x.json"]), "/tmp/c"), "/tmp/c")
    assert_eq(SaStrokeRecorder.folder_from(PackedStringArray([]), ""), "")
    var dangling := SaStrokeRecorder.folder_from(PackedStringArray(["--record-strokes"]), "/tmp/d")
    assert_eq(dangling, "/tmp/d", "a flag with nothing after it falls back to the environment")


func test_lines_carry_the_reading_and_the_frame() -> void:
    var recorder := SaStrokeRecorder.new(scratch_folder, {"display_driver": "test", "cursor_prediction_ms": 0.0})
    assert_true(recorder.is_recording(), "the file opened under user://")
    var motion := InputEventMouseMotion.new()
    motion.position = Vector2(120.5, 80.25)
    motion.pressure = 0.4
    motion.tilt = Vector2(0.1, -0.2)
    motion.pen_inverted = true
    motion.button_mask = MOUSE_BUTTON_MASK_LEFT
    var press := InputEventMouseButton.new()
    press.position = Vector2(1, 2)
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    var release := press.duplicate() as InputEventMouseButton
    release.pressed = false
    var key := InputEventKey.new()
    var window := Vector2(1920, 1080)
    var view := Rect2(300, 40, 1500, 1000)
    var at := Transform2D(0.0, Vector2(2.0, 2.0), 0.0, Vector2(300.0, 40.0))
    recorder.record(press, window, view, at)
    recorder.record(motion, window, view, at)
    recorder.record(key, window, view, at)
    recorder.record(release, window, view, at.translated(Vector2(-10.0, 0.0)))
    assert_eq(recorder.lines, 5, "a key event writes nothing, the view writes twice")
    recorder.close()
    recorder.close()
    assert_false(recorder.is_recording())

    var file := FileAccess.open(recorder.path, FileAccess.READ)
    assert_not_null(file, "the file is readable after close")
    var rows: Array = []
    while file != null and not file.eof_reached():
        var line := file.get_line()
        if not line.is_empty():
            rows.append(JSON.parse_string(line))
    assert_eq(rows.size(), 6, "a header, the view, three readings and the view again")
    var header: Dictionary = rows[0]
    assert_eq(header["display_driver"], "test")
    assert_eq(header["cursor_prediction_ms"], 0.0)
    assert_eq(int(header["format"]), 2)
    assert_true(header.has("started"))
    var placed: Dictionary = rows[1]
    assert_eq(placed["k"], "z", "the view comes before the first reading")
    assert_eq(placed["m"], [2.0, 0.0, 0.0, 2.0, 300.0, 40.0], "as the transform lays its six numbers out")
    var down: Dictionary = rows[2]
    assert_eq(down["k"], "d")
    assert_eq(int(down["btn"]), MOUSE_BUTTON_LEFT)
    var m: Dictionary = rows[3]
    assert_eq(m["k"], "m")
    assert_almost_eq(m["x"], 120.5)
    assert_almost_eq(m["y"], 80.25)
    assert_almost_eq(m["p"], 0.4)
    assert_almost_eq(m["tx"], 0.1)
    assert_almost_eq(m["ty"], -0.2)
    assert_eq(m["inv"], true)
    assert_eq(int(m["b"]), MOUSE_BUTTON_MASK_LEFT)
    assert_eq(m["w"], [1920.0, 1080.0])
    assert_eq(m["v"], [300.0, 40.0, 1500.0, 1000.0])
    assert_true(int(m["t"]) >= int(down["t"]), "time runs forward")
    var moved: Dictionary = rows[4]
    assert_eq(moved["k"], "z", "a pan writes the view again, before the reading that saw it")
    assert_eq(moved["m"], [2.0, 0.0, 0.0, 2.0, 290.0, 40.0])
    var up: Dictionary = rows[5]
    assert_eq(up["k"], "u")
    DirAccess.remove_absolute(recorder.path)


func test_a_folder_that_cannot_be_made_records_nothing() -> void:
    var recorder := SaStrokeRecorder.new("/proc/no-such-folder/strokes", {})
    assert_false(recorder.is_recording())
    recorder.record(InputEventMouseMotion.new(), Vector2.ZERO, Rect2(), Transform2D.IDENTITY)
    assert_eq(recorder.lines, 0)
    assert_eq(recorder.path, "")
