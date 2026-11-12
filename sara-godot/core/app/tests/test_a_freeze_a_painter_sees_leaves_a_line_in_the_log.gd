## A freeze a painter sees that no single frame and no stuck thread shows leaves
## a line in the log all the same.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter saw Sara freeze on Windows with a small brush, and the log had no
## `Sara stall:` line. Two shapes of freeze get one now: a run of slow frames,
## each under the second a stall needs, and a pen whose motions were held back
## while the frames kept coming. Each is made here on a watch out of the tree,
## so no thread runs, and its frames are handed it on a clock the suite keeps,
## which is what a loaded gate cannot disturb. The lines are read out of the
## run's own log, as the sibling suite reads its own.
extends "res://tests/test_framework.gd"

var _watch: SaTrail.Watch = null
## The suite's clock and the ledger's motion count as the watch is handed them.
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


## A pen's backlog on a slow machine: seven frames of 200 ms, each handling the
## sixty motions that came while the one before it ran, and one frame on time
## between two of them. None is a stall, and together they are 1.4 s of the
## picture at five frames a second.
func test_a_run_of_slow_frames_is_one_line_once_it_ends() -> void:
    _frames(30, 16, 3)
    SaTrail.note("the sibling suite's backlog")
    _frames(4, 200, 60)
    _frames(1, 10, 0)
    _frames(3, 200, 60)
    assert_eq(_lines(), PackedStringArray(), "Nothing while the run is under way")
    _frames(6, 16, 3)
    assert_eq(_lines(), PackedStringArray(), "nor while the frames on time come to under a tenth of a second")
    _frames(1, 16, 3)
    assert_eq(
        _lines(),
        PackedStringArray(
            [
                (
                    "the frames came slow for 1.4 s, 7 of them over 0.1 s and the longest 0.20 s,"
                    + " with 420 pen motions, at the sibling suite's backlog"
                ),
            ]
        ),
        "One line once they pass it, saying how long, how slow, whether the pen was in it and where"
    )
    _frames(100, 16, 3)
    assert_eq(_lines().size(), 1, "and the frames on time after it say nothing")


## Work of Sara's own with no hand in it reads as such, which is what the first
## start's preset thumbnails, one a frame, look like.
func test_a_run_with_no_pen_in_it_says_so() -> void:
    SaTrail.note("the sibling suite's thumbnails")
    _frames(6, 180, 0)
    _frames(12, 10, 0)
    assert_eq(
        _lines(),
        PackedStringArray(
            [
                (
                    "the frames came slow for 1.1 s, 6 of them over 0.1 s and the longest 0.18 s,"
                    + " with 0 pen motions, at the sibling suite's thumbnails"
                ),
            ]
        ),
        "No motion came in it"
    )


## The pen went quiet for 0.4 s with the frames on time, then forty motions
## came in one frame: the driver or the system sat on them while Sara drew.
func test_a_pen_held_back_is_one_line() -> void:
    _frames(20, 16, 3)
    SaTrail.note("the sibling suite's held pen")
    _frames(40, 10, 0)
    assert_eq(_lines(), PackedStringArray(), "A silence alone says nothing")
    _frames(1, 60, 40)
    assert_eq(
        _lines(),
        PackedStringArray(
            [
                (
                    "the pen went quiet for 0.40 s while the frames came on time,"
                    + " then 40 motions came in one frame, at the sibling suite's held pen"
                ),
            ]
        ),
        "The heap after it is one line, the silence measured without the frame it landed in"
    )
    _frames(20, 16, 3)
    assert_eq(_lines().size(), 1, "and the pen going on says nothing")


## What a painter does without anything freezing leaves no line: painting on
## time, holding the pen still and going on, a mouse at a thousand reports a
## second resuming after a rest, a frame rate capped at thirty, one hitch of
## 0.4 s, and two hitches together under a second.
func test_a_plain_run_leaves_no_line() -> void:
    _frames(200, 16, 3)
    _frames(100, 10, 0)
    _frames(50, 16, 3)
    _frames(100, 10, 10)
    _frames(50, 10, 0)
    _frames(1, 17, 17)
    _frames(20, 10, 10)
    _frames(100, 33, 5)
    _frames(1, 400, 3)
    _frames(20, 16, 3)
    _frames(1, 300, 3)
    _frames(1, 16, 3)
    _frames(1, 300, 3)
    _frames(20, 16, 3)
    assert_eq(_lines(), PackedStringArray(), "Not one line")


## A frame over a second has its stall line already, so a run it is the only slow
## frame of adds none, and neither does a silence that was one long frame.
func test_a_stall_is_told_once() -> void:
    _frames(20, 16, 3)
    SaTrail.note("the sibling suite's stall")
    _frames(1, 1500, 0)
    _frames(1, 200, 0)
    _frames(20, 16, 0)
    _frames(1, 60, 40)
    _frames(20, 16, 3)
    assert_eq(
        _lines(), PackedStringArray(["a frame took 1.5 s, at the sibling suite's stall"]), "The stall's own line and nothing more"
    )


## A run the quit cuts short is told as the watch finishes.
func test_the_quit_tells_a_run_still_under_way() -> void:
    SaTrail.note("the sibling suite's quit")
    _frames(6, 200, 0)
    assert_eq(_lines(), PackedStringArray(), "Under way")
    _watch.finish()
    assert_eq(_lines().size(), 1, "and told at the finish: %s" % "|".join(_lines()))


## In the app the watch reads the pen from the stroke ledger, whose count moves
## at the canvas window's input signal.
func test_the_watch_reads_the_pen_from_the_stroke_ledger() -> void:
    var before_it := "It starts from the ledger's count, so the motions before it are not a heap"
    assert_eq(_watch._seen_motions, SaStrokeLedger.motions, before_it)
    for _i in 3:
        SaStrokeLedger.event_arrived(true)
    _watch._process(0.0)
    assert_eq(_watch._seen_motions, SaStrokeLedger.motions, "and each frame takes up what came")


## *count* frames of *ms* each, *motions* of the pen in each.
func _frames(count: int, ms: int, motions: int) -> void:
    for _i in count:
        _clock += ms * 1000
        _motions += motions
        _watch.frame_came(_clock, _motions)


## The stall lines printed since the test began, the prefix taken off.
func _lines() -> PackedStringArray:
    var out := PackedStringArray()
    for line in _log_text().substr(_from).split("\n"):
        var trimmed := line.strip_edges()
        if trimmed.begins_with(SaTrail.STALL):
            out.append(_without_age(trimmed.substr(SaTrail.STALL.length()).strip_edges()))
    return out


## *line* without the age a stall line puts on a place older than
## `SaTrail.SLOW_S`. These tests are about the words and the place, and
## a loaded machine can take that long between the note and the frame.
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
