## Coming back to Sara prints a stall only when a frame was really slow.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter saw "a frame took 3.2 s, at the brush tool" on coming back to Sara
## with Alt+Tab. A gap the focus left or came back in is time Sara was away and
## prints nothing, and the same gap with the focus held is a stall as ever. The
## watch is out of the tree, so no thread runs, its frames come on the suite's
## own clock and its focus by `notification`, which is how the scene tree hands
## it to every node. The lines are read out of the run's own log, as the freeze-line
## suite reads its own.
extends "res://tests/test_framework.gd"

## A gap past `SaTrail.STALL_S`, a 3.2 s gap.
const GAP_MS := 3200
const LINE := "a frame took 3.2 s, at the sibling suite"

var _watch: SaTrail.Watch = null
var _clock: int = 0
var _from: int = 0


func before_each() -> void:
    _watch = SaTrail.Watch.new()
    _clock = _watch._beat_usec
    _from = _log_length()
    SaTrail.note("the sibling suite")


func after_each() -> void:
    if _watch != null:
        _watch.free()
        _watch = null


## The ask: the focus leaves, nothing draws for 3.2 s, the focus comes back and
## a frame comes. No line.
func test_a_gap_that_spans_a_focus_loss_prints_no_stall() -> void:
    _frames(10, 16)
    _watch.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
    _watch.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
    _frames(1, GAP_MS)
    _frames(10, 16)
    assert_eq(_lines(), PackedStringArray(), "The time away is no stall")


## The same gap with the window focused throughout is a stall.
func test_the_same_gap_with_the_window_focused_prints_the_line() -> void:
    _frames(10, 16)
    _frames(1, GAP_MS)
    assert_eq(_lines(), PackedStringArray([LINE]), "A real slow frame still prints")


## The focus left while frames went on, and only came back with the gap: the
## gap the return closes is no stall, which is the shape a window the desktop
## stopped drawing leaves.
func test_frames_that_stopped_while_away_print_nothing_on_the_return() -> void:
    _watch.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
    _frames(30, 16)
    _watch.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
    _frames(1, GAP_MS)
    assert_eq(_lines(), PackedStringArray(), "The return's gap is the time away")


## Away, with frames still coming, a gap with no focus change in it is a real
## stall, so a long load a script asks for while the painter is elsewhere is
## still told.
func test_a_slow_frame_while_away_with_no_focus_change_still_prints() -> void:
    _watch.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
    _frames(30, 16)
    _frames(1, GAP_MS)
    assert_eq(_lines(), PackedStringArray([LINE]), "A slow frame while away is still a stall")


## The return's gap counts in no run of slow frames either: slow frames before
## it that alone add to nothing stay nothing.
func test_the_time_away_counts_in_no_run_of_slow_frames() -> void:
    _frames(5, 150)
    _watch.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
    _watch.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
    _frames(1, GAP_MS)
    _frames(20, 16)
    assert_eq(_lines(), PackedStringArray(), "Five slow frames of 150 ms and the time away are no freeze")


## The watcher's thread owes no line while Sara is away or once the focus moved
## since the beat, and owes one while focused.
func test_the_watcher_says_nothing_while_sara_is_away() -> void:
    var past := int(SaTrail.STUCK_S * 1e6) + 100000
    _watch.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
    assert_eq(_watch.stuck_for(_clock + past), 0, "Away, a beat long gone is no stuck thread")
    _watch.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
    assert_eq(_watch.stuck_for(_clock + past), 0, "nor just after the return, before a frame came")
    _frames(1, 16)
    assert_eq(_watch.stuck_for(_clock + past), past, "Focused, the stuck thread is told")
    assert_eq(_watch.stuck_for(_clock + past + 1000), 0, "once")


func _frames(count: int, ms: int) -> void:
    for _i in count:
        _clock += ms * 1000
        _watch.frame_came(_clock, _watch._seen_motions)


func _lines() -> PackedStringArray:
    var out := PackedStringArray()
    for line in _log_text().substr(_from).split("\n"):
        var trimmed := line.strip_edges()
        if trimmed.begins_with(SaTrail.STALL):
            out.append(_without_age(trimmed.substr(SaTrail.STALL.length()).strip_edges()))
    return out


## *line* without the age a stall line puts on a place older than
## `SaTrail.SLOW_S`. This suite is about which gap prints at all, and a
## loaded machine can take that long between the note and the frame.
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
