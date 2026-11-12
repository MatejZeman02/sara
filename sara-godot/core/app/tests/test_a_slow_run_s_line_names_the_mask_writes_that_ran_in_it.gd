## A run of slow frames names the work noted inside it, the most frequent
## first, and the place before it only when nothing was noted in it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painting pass rewrote fourteen masks through the door, and
## every run of slow frames under the posts logged "at the eye of day, hidden,
## noted 1 min 37 s ago", an eye turned before the first post. Each run here is
## made on a watch out of the tree with frames on the suite's own clock, as the
## the sibling suite makes its own, and its line is read out of the run's own log.
extends "res://tests/test_framework.gd"

## What the suite notes before the run, which the run's line must not name.
const BEFORE := "the noted eye, hidden"
## What the door's mask step notes on the trail, written out here
## because `core` names nothing of the harness.
const MASK_WRITTEN := "a mask written through the door"

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


## The ask: an eye noted, time passing on frames that came on time, and then a
## run of mask writes, each a door request and a note, every one inside the slow
## frames. The line names the mask writes and the requests, and not the eye.
func test_a_run_of_mask_writes_is_named_and_not_the_eye_before_it() -> void:
    SaTrail.note(BEFORE)
    _frames(30, 16)
    OS.delay_msec(150)
    for post in 6:
        var ticket := SaTrail.enter("the door request layer")
        SaTrail.note(MASK_WRITTEN)
        SaTrail.give_back(ticket)
        _frames(2, 300)
    _frames(1, 16)
    _frames(10, 16)
    var lines := _lines()
    assert_eq(lines.size(), 1, "One line for the run, read %s" % "|".join(lines))
    var line := lines[0] if lines.size() == 1 else ""
    assert_true(
        line.ends_with("with 0 pen motions, at the door request layer (6 times), %s (6 times)" % MASK_WRITTEN),
        "It names the requests and the mask writes with how many of each, read '%s'" % line
    )
    assert_false(line.contains(BEFORE), "and not the eye noted before the run began")


## The most frequent is named first, and a piece of work noted once is named
## without a count.
func test_the_most_frequent_comes_first() -> void:
    _frames(5, 16)
    SaTrail.note("the noted export")
    _frames(1, 300)
    for post in 3:
        SaTrail.note(MASK_WRITTEN)
        _frames(1, 300)
    _frames(1, 300)
    _frames(10, 16)
    var lines := _lines()
    assert_eq(lines.size(), 1, "One line for the run, read %s" % "|".join(lines))
    assert_true(
        lines.size() == 1 and lines[0].ends_with(", at %s (3 times), the noted export" % MASK_WRITTEN),
        "The mask writes before the one export, read %s" % "|".join(lines)
    )


## Work noted in the frames on time after the run's last slow one is not its.
func test_work_after_the_last_slow_frame_is_not_named() -> void:
    _frames(5, 16)
    SaTrail.note("the noted thumbnails")
    _frames(5, 250)
    _frames(1, 16)
    SaTrail.note("the noted stroke")
    _frames(10, 16)
    var lines := _lines()
    assert_true(
        lines.size() == 1 and lines[0].ends_with(", at the noted thumbnails"), "The thumbnails alone, read %s" % "|".join(lines)
    )


## A run nothing was noted in names the place standing as before it, with its
## age, which is the one case the old reading is right for.
func test_a_run_with_nothing_noted_in_it_names_the_place_before_it_with_its_age() -> void:
    SaTrail.note(BEFORE)
    _frames(5, 16)
    _frames(5, 250)
    _frames(10, 16)
    var lines := _lines()
    assert_true(
        (
            lines.size() == 1
            and lines[0].contains("nothing noted in it, before it at %s, noted " % BEFORE)
            and lines[0].ends_with(" s ago")
        ),
        "The place before it with its age, read %s" % "|".join(lines)
    )


## *count* frames each *took* milliseconds on the suite's clock, with no pen.
func _frames(count: int, took: int) -> void:
    for frame in count:
        _clock += took * 1000
        _watch.frame_came(_clock, _watch._seen_motions)


## The stall lines printed since the last read, the prefix taken off.
func _lines() -> PackedStringArray:
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
