## A `Sara hitch:` line says how long the main thread ran on a core over the
## frame, so a frame the main thread slept through reads well under its length
## and one it spent working reads close to it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The watch is made out of the tree, so no watcher thread runs, and the suite
## takes the watcher's reading itself before the frame begins. The frames are
## handed it on the real clock, because the schedule the line reads is the real
## one. The lines are read out of the run's own log, as the sibling suite reads its
## own.
extends "res://tests/test_framework.gd"

## A hitch long enough that a reading or two of `/proc` and the frames around
## it are a small part of it, and short enough to keep the run quick.
const FRAME_MS := 300

var _watch: SaTrail.Watch = null
var _from: int = 0


func before_each() -> void:
    _watch = SaTrail.Watch.new()
    _from = _log_length()


func after_each() -> void:
    if _watch != null:
        _watch.free()
        _watch = null


func test_a_frame_the_main_thread_slept_through_reads_little_time_on_a_core() -> void:
    if not _has_schedule():
        skip("no /proc schedule on this system, so the line carries no figures")
        return
    _begin_frame()
    OS.delay_msec(FRAME_MS)
    _end_frame()
    var figures := _figures()
    assert_eq(figures.size(), 3, "The hitch line ends with its span and the main thread's time on a core: %s" % _line())
    if figures.size() != 3:
        return
    assert_true(figures[0] >= FRAME_MS * 0.9, "The span covers the frame: %s" % _line())
    assert_true(figures[1] < FRAME_MS * 0.2, "A frame slept through reads well under its length on a core: %s" % _line())


func test_a_frame_the_main_thread_spent_working_reads_close_to_its_length_on_a_core() -> void:
    if not _has_schedule():
        skip("no /proc schedule on this system, so the line carries no figures")
        return
    _begin_frame()
    var until := Time.get_ticks_usec() + FRAME_MS * 1000
    var spun := 0
    while Time.get_ticks_usec() < until:
        spun += 1
    _end_frame()
    var figures := _figures()
    assert_eq(figures.size(), 3, "The hitch line ends with its span and the main thread's time on a core: %s" % _line())
    if figures.size() != 3 or spun == 0:
        return
    # A machine running other work may hold the thread off a core for part of
    # the frame, and that time is the line's waiting figure, so the two
    # together are the frame and the time on a core most of it.
    assert_true(figures[1] >= FRAME_MS * 0.6, "A frame spent working reads close to its length on a core: %s" % _line())
    assert_true(figures[1] + figures[2] >= FRAME_MS * 0.85, "On a core and waiting for one add up to the frame: %s" % _line())


func test_a_frame_with_no_reading_before_it_keeps_the_line_as_it_was() -> void:
    _frames(5)
    OS.delay_msec(150)
    _frames(1)
    var line := _line()
    assert_true(line.begins_with("a frame took "), "A hitch line is printed: %s" % line)
    assert_false(line.contains("on a core"), "With no reading of the schedule the line carries no figures: %s" % line)


## Frames on time, then the watcher's reading, then the last frame on time,
## so the reading is taken before the slow frame begins.
func _begin_frame() -> void:
    _frames(5)
    _watch.sample(Time.get_ticks_usec())
    _frames(1)


func _end_frame() -> void:
    _frames(1)


func _frames(count: int) -> void:
    for _i in count:
        _watch.frame_came(Time.get_ticks_usec(), SaStrokeLedger.motions)


func _has_schedule() -> bool:
    return not SaFrameTrace.schedule().is_empty()


## The span the line measured over, the main thread's time on a core and its
## time waiting for one, in milliseconds, or nothing when the line has none.
func _figures() -> PackedFloat64Array:
    var pattern := r"over the last ([\d.]+) ms, on a core ([\d.]+) ms, waiting for one ([\d.]+) ms"
    var found := RegEx.create_from_string(pattern).search(_line())
    if found == null:
        return PackedFloat64Array()
    var out := PackedFloat64Array()
    for group: int in [1, 2, 3]:
        out.append(found.get_string(group).to_float())
    return out


## The one hitch line printed since the test began, its prefix taken off.
func _line() -> String:
    for line in _log_text().substr(_from).split("\n"):
        var trimmed := line.strip_edges()
        if trimmed.begins_with(SaTrail.HITCH):
            return trimmed.substr(SaTrail.HITCH.length()).strip_edges()
    return ""


func _log_length() -> int:
    return _log_text().length()


func _log_text() -> String:
    var path := SaTrail.log_path()
    if not FileAccess.file_exists(path):
        return ""
    var file := FileAccess.open(path, FileAccess.READ)
    return file.get_as_text() if file != null else ""
