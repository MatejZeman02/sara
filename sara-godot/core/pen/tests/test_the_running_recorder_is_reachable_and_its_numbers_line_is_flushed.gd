## The running stroke recorder is reachable from outside the canvas, and the
## line of numbers it is handed is a kind of its own, flushed as it is written.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The one recorder is the main canvas's and private, so the Stats docker
## reaches it through `SaStrokeRecorder.running`, which the recorder's own class
## sets when its file opens and clears when it closes. What has to hold is that
## the static follows the file and nothing else, that the line carries the log's
## clock and the numbers by name under a kind no reading uses, and that the file
## holds it before anything closes it, since one comes a stop and a session that
## dies should keep the last.
extends "res://tests/test_framework.gd"

static var scratch_folder: String = SaDataRoot.path("test_a4_running_recorder")


func test_the_static_follows_the_file_from_open_to_close() -> void:
    var before := SaStrokeRecorder.running
    var refused := SaStrokeRecorder.new("/proc/no-such-folder/strokes", {})
    assert_true(SaStrokeRecorder.running == before, "A recorder whose folder cannot be made is not the running one")
    var recorder := SaStrokeRecorder.new(scratch_folder.path_join("follows"), {})
    assert_true(recorder.is_recording(), "The file opened under the data root")
    assert_true(SaStrokeRecorder.running == recorder, "and the recorder with it open is the running one")
    refused.close()
    assert_true(SaStrokeRecorder.running == recorder, "Closing another recorder leaves it")
    recorder.close()
    assert_null(SaStrokeRecorder.running, "Closed, nothing is recorded")
    recorder.close()
    assert_null(SaStrokeRecorder.running, "and a second close changes nothing")
    _remove(recorder.path)


func test_a_numbers_line_is_its_own_kind_and_in_the_file_before_the_close() -> void:
    var recorder := SaStrokeRecorder.new(scratch_folder.path_join("numbers"), {"display_driver": "test"})
    var motion := InputEventMouseMotion.new()
    motion.position = Vector2(10, 20)
    recorder.record(motion, Vector2(1920, 1080), Rect2(0, 0, 1920, 1080), Transform2D.IDENTITY)
    recorder.note_numbers({"value_groups": 3, "value_group_1": "40 %"}, {"value_groups": "Groups", "value_group_1": "Value 0.42"})
    assert_eq(recorder.lines, 3, "The view, the reading and the numbers")

    var rows := _rows(recorder.path)
    assert_eq(rows.size(), 4, "The file holds the header and the three lines while it is still open")
    if rows.size() == 4:
        var line: Dictionary = rows[3]
        assert_eq(line["k"], SaStrokeRecorder.NUMBERS, "The numbers are a kind of their own")
        assert_false(["z", "m", "d", "u"].has(line["k"]), "which no reading uses")
        assert_true(int(line["t"]) >= int(rows[2]["t"]), "on the log's clock, after the reading before it")
        assert_eq(line["n"], {"value_groups": 3.0, "value_group_1": "40 %"}, "each number by its name")
        assert_eq(line["l"], {"value_groups": "Groups", "value_group_1": "Value 0.42"}, "and its title by the same name")
    recorder.close()
    recorder.note_numbers({"late": 1})
    assert_eq(recorder.lines, 3, "Closed, a line of numbers writes nothing")
    assert_eq(_rows(recorder.path).size(), 4, "and the file stays as it was")
    _remove(recorder.path)


## Every line of the file at *path*, each parsed.
static func _rows(path: String) -> Array:
    var rows: Array = []
    var file := FileAccess.open(path, FileAccess.READ)
    while file != null and not file.eof_reached():
        var line := file.get_line()
        if not line.is_empty():
            rows.append(JSON.parse_string(line))
    return rows


static func _remove(path: String) -> void:
    if not path.is_empty():
        DirAccess.remove_absolute(path)
