## Every frame of a perf window a scenario opens with
## `"trace": true` leaves one `Sara frame:` line, naming each part that spent
## more than 5 ms.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The frames are drawn with `RenderingServer.force_draw`, which emits the
## engine's pre and post draw signals the trace listens to without waiting on a
## compositor, so the count of frames is the suite's own and not a loading
## machine's. The window is opened and closed through `SaPerfWindow.capture`,
## which a scenario's `{"measure": {"perf": "begin", "trace": true}}` reaches
## through the harness's measure step.
extends "res://tests/test_framework.gd"

## The frames are the device's.
const REQUIRES_GPU := true

const FRAMES := 4

var _lines: Array[String] = []


func before_each() -> void:
    SaPerfWindow.forget()
    _lines = []


func after_each() -> void:
    SaPerfWindow.forget()


## The scenario's step turns the trace on, a frame drawn is a line, and the
## window's end turns it off before its own measuring draws, which leave none.
func test_a_traced_window_prints_one_line_a_frame() -> void:
    var opened := SaPerfWindow.capture(null, "begin", true)
    assert_true(opened.contains('"open":true'), "The window opens: %s" % opened)
    assert_true(SaFrameTrace.enabled, "and its trace is on")
    for _i: int in FRAMES:
        RenderingServer.force_draw(false)
    assert_eq(SaFrameTrace.lines, FRAMES, "One line a frame drawn")
    assert_true(SaFrameTrace.last_line.begins_with(SaFrameTrace.LINE), "Each a frame line: %s" % SaFrameTrace.last_line)
    if OS.get_name() == "Linux":
        assert_true(
            SaFrameTrace.last_line.contains(", on a core ") and SaFrameTrace.last_line.contains(" ms, waiting for one "),
            "and on Linux it says how long the main thread had a core and waited for one",
        )
    var closed := SaPerfWindow.capture(null, "end")
    assert_false(SaFrameTrace.enabled, "The end turns the trace off")
    var block: Dictionary = SaPerfWindow.last_block
    var window: Dictionary = block["window"]
    assert_eq(window["traced_frames"], FRAMES, "and the block says how many frames it traced: %s" % closed.left(200))
    RenderingServer.force_draw(false)
    assert_eq(SaFrameTrace.lines, FRAMES, "A frame after the end prints nothing")


## A window opened without the flag traces nothing.
func test_a_window_without_the_flag_traces_nothing() -> void:
    SaPerfWindow.capture(null, "begin")
    assert_false(SaFrameTrace.enabled, "No flag, no trace")
    RenderingServer.force_draw(false)
    SaPerfWindow.capture(null, "end")
    var window: Dictionary = SaPerfWindow.last_block["window"]
    assert_eq(window["traced_frames"], 0, "and no line")
    assert_eq(SaFrameTrace.now(), 0, "and a part's clock reads nought, so the hooks cost a compare")


## A part over 5 ms is named in its frame's line with its time, one under it is
## not, and each frame's parts are its own.
func test_a_part_over_five_milliseconds_is_named_in_its_frame_alone() -> void:
    SaFrameTrace.start(_keep)
    var began := SaFrameTrace.now()
    OS.delay_usec(8_000)
    SaFrameTrace.spent("a slow part", began)
    began = SaFrameTrace.now()
    OS.delay_usec(500)
    SaFrameTrace.spent("a quick part", began)
    RenderingServer.force_draw(false)
    RenderingServer.force_draw(false)
    SaFrameTrace.stop()
    assert_eq(_lines.size(), 2, "Two frames, two lines: %s" % [_lines])
    assert_true(_lines[0].contains("(a slow part "), "The slow part is named: %s" % _lines[0])
    assert_false(_lines[0].contains("a quick part"), "the quick one is not")
    assert_false(_lines[1].contains("a slow part"), "and the next frame does not carry it: %s" % _lines[1])


## The line's arithmetic: phases always, parts over the line longest first in
## their phase, a part inside another named in the other's brackets and not
## taken off the phase twice, the phase's unnamed rest beside them, and no
## semicolon.
func test_the_line_names_its_parts_by_phase_and_milliseconds() -> void:
    var phases: Dictionary[String, int] = {"before the tick": 450_000, "process": 40_000, "draw": 13_000}
    var spans: Array[SaFrameTrace.Span] = [
        SaFrameTrace.Span.new("eye", 1_000, 441_000, "before the tick"),
        SaFrameTrace.Span.new("layers docker follow", 452_000, 460_000, "process"),
        SaFrameTrace.Span.new("document_changed", 451_000, 471_000, "process"),
        SaFrameTrace.Span.new("easel composite", 472_000, 478_000, "process"),
        SaFrameTrace.Span.new("layer rows", 479_000, 480_000, "process"),
        SaFrameTrace.Span.new("layer rows", 481_000, 482_000, "process"),
    ]
    var line := SaFrameTrace.line_of(493_000, phases, spans, 3_200)
    assert_eq(
        line,
        (
            "Sara frame: 493.0 ms, before the tick 450.0 ms (eye 440.0 ms, other 10.0 ms), process 40.0 ms"
            + " (document_changed 20.0 ms (layers docker follow 8.0 ms), easel composite 6.0 ms, other 12.0 ms),"
            + " draw 13.0 ms, gpu 3.2 ms"
        ),
        "The line reads as the frame was spent",
    )
    assert_false(line.contains(";"), "No semicolon in a line a reader reads")


func _keep(line: String) -> void:
    _lines.append(line)
