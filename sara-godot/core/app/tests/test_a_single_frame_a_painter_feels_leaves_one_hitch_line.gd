## A single frame a painter feels, over a tenth of a second and under the second
## a stall needs, leaves one `Sara hitch:` line, and a burst of them one line.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter wrote: "The official freeze logger that exists doesn't take on
## these because they are sub-second, but it is still noticeable for humans."
## The watch is made out of the tree, so no thread runs, and its frames are
## handed it on a clock the suite keeps. The lines are read out of the run's
## own log, as the sibling suite reads its own.
extends "res://tests/test_framework.gd"

var _watch: SaTrail.Watch = null
var _clock: int = 0
var _motions: int = 0
var _from: int = 0


func before_each() -> void:
    _watch = SaTrail.Watch.new()
    _clock = _watch._beat_usec
    _motions = _watch._seen_motions
    _from = _log_length()


func after_each() -> void:
    if _watch != null:
        _watch.free()
        _watch = null


func test_a_frame_of_120_ms_is_one_line_with_its_length_and_its_place() -> void:
    _frames(30, 16)
    SaTrail.note("the sibling suite's dialog")
    _frames(1, 120)
    _frames(30, 16)
    assert_eq(
        _lines(),
        PackedStringArray(["a frame took 120 ms, at the sibling suite's dialog"]),
        "One line, saying how long the frame was and where Sara was"
    )


func test_a_frame_of_60_ms_is_no_line() -> void:
    _frames(30, 16)
    _frames(1, 60)
    _frames(30, 16)
    assert_eq(_lines(), PackedStringArray(), "A frame a twentieth of a second long is too common to log")


func test_ten_frames_of_120_ms_back_to_back_are_one_line() -> void:
    _frames(30, 16)
    SaTrail.note("the sibling suite's previews")
    _frames(10, 120)
    _frames(30, 16)
    assert_eq(
        _lines(),
        PackedStringArray(["a frame took 120 ms, at the sibling suite's previews"]),
        "A burst of hitches is one line, at its first"
    )


func test_a_hitch_more_than_a_second_after_the_last_is_a_line_again() -> void:
    _frames(30, 16)
    SaTrail.note("the sibling suite's menus")
    _frames(1, 150)
    _frames(70, 16)
    _frames(1, 200)
    assert_eq(
        _lines(),
        PackedStringArray(
            ["a frame took 150 ms, at the sibling suite's menus", "a frame took 200 ms, at the sibling suite's menus"]
        ),
        "Two hitches 1.1 s apart are two lines"
    )


func test_a_stall_is_no_hitch() -> void:
    _frames(30, 16)
    _frames(1, 1500)
    _frames(30, 16)
    assert_eq(_lines(), PackedStringArray(), "A frame over a second has its stall line and no hitch line")


func _frames(count: int, ms: int) -> void:
    for _i in count:
        _clock += ms * 1000
        _watch.frame_came(_clock, _motions)


## The hitch lines printed since the test began, the prefix and the place's age
## taken off.
func _lines() -> PackedStringArray:
    var out := PackedStringArray()
    for line in _log_text().substr(_from).split("\n"):
        var trimmed := line.strip_edges()
        if trimmed.begins_with(SaTrail.HITCH):
            out.append(_without_age(trimmed.substr(SaTrail.HITCH.length()).strip_edges()))
    return out


## *line* without the age a line for one frame puts on its place. The
## tests are about the words and the place.
static func _without_age(line: String) -> String:
    if not line.ends_with(" ago"):
        return line
    for said: String in [", noted ", ", entered "]:
        var at := line.rfind(said)
        if at > 0:
            return line.substr(0, at)
    return line


func _log_length() -> int:
    return _log_text().length()


func _log_text() -> String:
    var path := SaTrail.log_path()
    if not FileAccess.file_exists(path):
        return ""
    var file := FileAccess.open(path, FileAccess.READ)
    return file.get_as_text() if file != null else ""
