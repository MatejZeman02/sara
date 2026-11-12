## A stall line names what held the frame, or says how long ago its place was
## noted.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A long run read `Sara stall: a frame took 1.2 s, at
## SaSadFile: opened ...structure-start.sad in 2530 ms` for an hour
## after that load, because the work that held those frames, a door request of
## thirty eyes and an export, wrote no place of its own and the trail says
## nothing about when a place was written. Every place is timed now, and a line
## for a measured frame says how long before it the place was written, which
## read against the frame says whether that place could have held it.
##
## A frame is measured when the next one begins, by which time work that
## entered and gave back inside it has left nothing standing, so a line for one
## frame names a place given back that stood over half of the gap it measures.
## Those three tests run on the engine's clock rather than the suite's, since
## that is the rule they are about.
##
## Each stall is made on a watch out of the tree with a frame on the suite's own
## clock, as the sibling suite makes its own, and its line is read out of the run's
## own log. The age is real time, so the suite waits rather than moving a clock:
## `last_aged` reads the engine's, not the watch's.
@tool
extends "res://tests/test_framework.gd"

## The one frame a stall takes, past `SaTrail.STALL_S`.
const STALL_MS := 1500
## The wait that makes a place stale, past `SaTrail.SLOW_S`.
const STALE_MS := 150
## The wait a frame on the engine's own clock takes, past `SaTrail.STALL_S`.
const HELD_MS := 1100
## What this suite notes and enters.
const PLACE := "the noted place"
const STOOD := "the noted dialog"

var _watch: SaTrail.Watch = null
## The suite's clock as the watch is handed it.
var _clock: int = 0
## Where in the run's log the lines not read yet begin.
var _from: int = 0


func before_each() -> void:
    _watch = SaTrail.Watch.new()
    _clock = _watch._beat_usec
    _from = _log_length()


func after_each() -> void:
    if _watch != null:
        _watch.free()
        _watch = null


## The ask: a note left behind is named with its age, so a reader knows the
## place is older than the frame rather than the work that held it.
func test_a_stall_names_a_note_left_behind_with_its_age() -> void:
    SaTrail.note(PLACE)
    OS.delay_msec(STALE_MS)
    var line := _stall()
    assert_true(
        line.begins_with("a frame took 1.5 s, at %s, noted 0." % PLACE) and line.ends_with(" s ago"),
        "The stall says how long ago the note was written, read '%s'" % line
    )


## A place written as the frame ended held none of it, which only its age
## says: the door's request of thirty eyes notes an eye in the last tenth of
## the frame that came before it, and read without an age that eye is the
## work that held the frame.
func test_a_place_written_as_the_frame_ended_says_so_by_its_age() -> void:
    SaTrail.note(PLACE)
    assert_eq(
        _stall(), "a frame took 1.5 s, at %s, noted 0.0 s ago" % PLACE, "A place of no age against a long frame held none of it"
    )


## A place that stands by its own will, a dialog or a door request, says it was
## entered rather than noted, so a reader knows it is still open.
func test_an_entered_place_says_it_was_entered() -> void:
    SaTrail.note(PLACE)
    var ticket := SaTrail.enter(STOOD)
    OS.delay_msec(STALE_MS)
    var during := _stall()
    assert_true(
        during.begins_with("a frame took 1.5 s, at %s, entered 0." % STOOD),
        "The place entered is named as entered, read '%s'" % during
    )
    SaTrail.give_back(ticket)
    SaTrail.note(PLACE)
    var after := _stall()
    assert_eq(after, "a frame took 1.5 s, at %s, noted 0.0 s ago" % PLACE, "and a note after the give back stands over it")


## The ask's other half: an export enters a place and gives it back inside one
## frame, and the watch measures that frame when the next one begins. The line
## names the work that held it all the same, and says it has ended.
func test_a_place_given_back_inside_the_frame_is_what_held_it() -> void:
    SaTrail.note(PLACE)
    var ticket := SaTrail.enter(STOOD)
    OS.delay_msec(HELD_MS)
    SaTrail.give_back(ticket)
    var line := _stall_on_the_engines_clock()
    assert_true(
        line.contains("at %s, entered 1." % STOOD) and line.ends_with(" s ago and given back"),
        "The work that ended in the frame names it, read '%s'" % line
    )


## The door's own shape: a request gives its place back as the frame ends and
## the next step notes a place in what is left of it. The newer place held
## none of the frame, so the request that ended in it is named.
func test_a_place_noted_after_the_give_back_does_not_take_the_frame() -> void:
    var ticket := SaTrail.enter(STOOD)
    OS.delay_msec(HELD_MS)
    SaTrail.give_back(ticket)
    SaTrail.note(PLACE)
    var line := _stall_on_the_engines_clock()
    assert_true(
        line.contains("at %s, entered 1." % STOOD) and line.ends_with(" s ago and given back"),
        "The work that ended in the frame names it over the place noted after it, read '%s'" % line
    )


## And a place given back as the frame began held none of it, a dialog hidden
## by the press that started the work. The note it left standing is named, with
## its age, rather than the dialog.
func test_a_place_given_back_before_the_frame_does_not_take_it() -> void:
    SaTrail.note(PLACE)
    SaTrail.give_back(SaTrail.enter(STOOD))
    OS.delay_msec(HELD_MS)
    var line := _stall_on_the_engines_clock()
    assert_true(
        line.contains("at %s, noted 1." % PLACE) and line.ends_with(" s ago"),
        "The note stands over work that ended before the frame, read '%s'" % line
    )


## The line a run of slow frames prints carries the age as well, since the
## painter's freezes come as runs as often as they come as one long frame. A
## run names the place before it only when nothing was noted inside it,
## so the note is followed by a frame on time before the run begins.
func test_a_run_of_slow_frames_carries_the_age_too() -> void:
    SaTrail.note(PLACE)
    _frame(16)
    OS.delay_msec(STALE_MS)
    for frame in 5:
        _frame(300)
    for frame in 3:
        _frame(50)
    var lines := _read()
    assert_eq(lines.size(), 1, "One line for the run, read %s" % "|".join(lines))
    assert_true(
        lines[0].contains("before it at %s, noted " % PLACE) and lines[0].ends_with(" s ago"),
        "The run's line names the note before it with its age, read '%s'" % lines[0]
    )


## How an age reads: tenths of a second inside a minute, and minutes and
## seconds beyond one, which is the stale label a painter's log holds.
func test_an_age_reads_in_tenths_and_then_in_minutes() -> void:
    assert_eq(SaTrail.how_long(1_500_000), "1.5 s", "Under a minute, in tenths")
    assert_eq(SaTrail.how_long(59_900_000), "59.9 s", "Up to the minute")
    assert_eq(SaTrail.how_long(61_000_000), "1 min 1 s", "Past it, in minutes and seconds")
    assert_eq(SaTrail.how_long(3_765_000_000), "62 min 45 s", "An hour is minutes, which is how a log is read")


## Makes one stall on the suite's clock and answers the line it printed, the
## prefix taken off, or every line it printed when that was not one.
func _stall() -> String:
    _frame(STALL_MS)
    var lines := _read()
    return lines[0] if lines.size() == 1 else "%d lines: %s" % [lines.size(), "|".join(lines)]


## Makes one stall whose frame is as long as the wait this suite really took,
## so what a place covered of it is read against the engine's clock.
func _stall_on_the_engines_clock() -> String:
    _clock = Time.get_ticks_usec()
    _watch.frame_came(_clock, _watch._seen_motions)
    var lines := _read()
    return lines[0] if lines.size() == 1 else "%d lines: %s" % [lines.size(), "|".join(lines)]


## One frame *took* milliseconds long on the suite's clock.
func _frame(took: int) -> void:
    _clock += took * 1000
    _watch.frame_came(_clock, _watch._seen_motions)


## The stall lines printed since the last read, the prefix taken off.
func _read() -> PackedStringArray:
    var out := PackedStringArray()
    for line in _log_text().substr(_from).split("\n"):
        var trimmed := line.strip_edges()
        if trimmed.begins_with(SaTrail.STALL):
            out.append(trimmed.substr(SaTrail.STALL.length()).strip_edges())
    _from = _log_length()
    return out


func _log_length() -> int:
    return _log_text().length()


func _log_text() -> String:
    var path := SaTrail.log_path()
    if not FileAccess.file_exists(path):
        return ""
    var file := FileAccess.open(path, FileAccess.READ)
    return file.get_as_text() if file != null else ""
