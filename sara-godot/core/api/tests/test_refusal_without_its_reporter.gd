## The corner notice no longer wears the class that reported it.
##
## Every refusal in the tree reached the canvas corner as
## `SaHistory: Undo history is full...` or `SaRecorder: There is no canvas to
## record.`, because `SaProblems._deliver` built one line for both kinds and the
## reporter's name is the first half of it. The words for that surface are
## that the gesture cannot happen and nothing is broken, and a painter who has
## just been told nothing is broken should not then be reading a GDScript class
## name. A fault keeps its reporter, because a fault is copied into a bug report
## and that is what makes the report useful, and the log keeps it for both.
extends "res://tests/test_framework.gd"

var _lines: Array[String] = []
var _kinds: Array[int] = []


func before_each() -> void:
    SaProblems.announce = false
    SaProblems.detach_sink()
    SaProblems.pending = PackedStringArray()
    SaProblems.pending_refusals = PackedStringArray()
    _lines = []
    _kinds = []


func after_each() -> void:
    SaProblems.detach_sink()
    SaProblems.pending = PackedStringArray()
    SaProblems.pending_refusals = PackedStringArray()
    SaProblems.announce = true


## One sink for both kinds, the way `SaMessage.install` attaches one, so what
## each kind is handed is read off the same call rather than off two.
func _attach() -> void:
    SaProblems.attach_sink(
        func(line: String, kind: SaProblems.Kind) -> void:
            _lines.append(line)
            _kinds.append(int(kind))
    )


## The two kinds through one sink, which is the whole of the fix: the fault
## carries its reporter to the screen and the refusal does not.
func test_a_refusal_reaches_the_sink_without_its_source() -> void:
    _attach()

    SaProblems.report("SaFileMenu", "Could not open 'sky.sad' (File not found).")
    SaProblems.refuse("SaRecorder", "There is no canvas to record.")

    assert_eq(_lines.size(), 2, "Both doors reach the one sink")
    assert_eq(_kinds[0], int(SaProblems.Kind.FAULT), "the first as a fault")
    assert_eq(_kinds[1], int(SaProblems.Kind.REFUSAL), "and the second as a refusal")
    assert_eq(
        _lines[0],
        "SaFileMenu: Could not open 'sky.sad' (File not found).",
        "The fault keeps the class that reported it, because a bug report wants it"
    )
    assert_eq(_lines[1], "There is no canvas to record.", "and the refusal is the sentence the painter reads and nothing else")


## A refusal that arrives before there is a window is kept the way it will be
## shown, so the drain has nothing left to strip.
func test_a_refusal_kept_before_the_sink_is_kept_bare() -> void:
    SaProblems.report("SaTexture", "could not allocate a 256x256 texture.")
    SaProblems.refuse("SaHistory", "Undo history is full, so 2 steps were dropped.")

    assert_eq(SaProblems.pending.size(), 1, "The fault is kept")
    assert_eq(SaProblems.pending_refusals.size(), 1, "and the refusal in its own record")
    assert_eq(SaProblems.pending[0], "SaTexture: could not allocate a 256x256 texture.", "The kept fault carries its reporter")
    assert_eq(SaProblems.pending_refusals[0], "Undo history is full, so 2 steps were dropped.", "and the kept refusal does not")

    _attach()
    assert_eq(_lines.size(), 2, "Both drain onto the sink")
    assert_eq(_lines[1], "Undo history is full, so 2 steps were dropped.", "unchanged by the drain")


## The prefix is decided by the kind and not by the words, so a refusal whose
## sentence reads like a fault still loses its source and a fault whose sentence
## reads like a refusal still keeps one.
func test_the_kind_decides_the_prefix_and_not_the_sentence() -> void:
    _attach()

    SaProblems.refuse("Patch", "Could not patch: there is no selection. Draw one first.")
    SaProblems.report("SaKernel", "There is no compiler for this dialect.")

    assert_eq(_lines[0], "Could not patch: there is no selection. Draw one first.", "'Could not' in a refusal is still a refusal")
    assert_eq(_lines[1], "SaKernel: There is no compiler for this dialect.", "and 'There is no' in a fault is still a fault")


## The log is the surface that has no other way to say where a line came from,
## so `push_error` is handed `"%s: %s"` for both kinds. `sara_shot.py` counts a
## run's problems off that line and `test_shot_problems` reads them back, and
## neither moves because of this unit.
##
## `push_error` cannot be read back from GDScript, so what is held here is the
## string itself: `_deliver` builds one `logged` and the fault path shows it
## unchanged, so a fault reaching the sink is that line to the character. A
## refusal's log line is the same expression over the same two arguments.
func test_the_log_line_is_the_fault_line_and_still_names_its_source() -> void:
    _attach()

    SaProblems.report("SaHistory", "Undo history is full.")

    assert_eq(_lines[0], "SaHistory: Undo history is full.", "The line the log is handed is source, colon, space, text")


## Nine call sites pass a source and none of them changed, so a refusal whose
## source is a tool's name rather than a class's loses it just the same.
func test_a_tool_named_source_is_dropped_too() -> void:
    _attach()

    SaProblems.refuse("Filter", "There is no active layer to run 'Levels' on.")

    assert_eq(
        _lines[0],
        "There is no active layer to run 'Levels' on.",
        "A friendlier prefix is still a prefix the painter did not ask for"
    )
