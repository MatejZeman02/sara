## The perf block's shares: what each module's registration and each kind of
## start work took, so the costliest part of a start is read off a table rather
## than guessed.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"


func test_a_module_and_a_kind_of_work_are_in_milliseconds() -> void:
    var shares := SaBootMarks.shares_of({}, {&"midi": 1500}, {&"skeleton": 250000})
    assert_eq(shares["modules"], {&"midi": 1.5}, "A module's share is its microseconds in milliseconds")
    assert_eq(shares["work"], {&"skeleton": 250.0}, "and so is a kind of work")


func test_a_span_between_two_marks_is_a_share_of_its_own() -> void:
    var marks: Dictionary[StringName, int] = {&"kernels_begin": 1000000, &"kernels_end": 1300000, &"run_log_init": 900000}
    var work: Dictionary = SaBootMarks.shares_of(marks, {}, {})["work"]
    assert_eq(work.get(&"kernels"), 300.0, "The kernels are the span between their two marks")
    assert_eq(work.get(&"engine"), 900.0, "and the engine's runs from the start to the run log's mark")
    assert_false(work.has(&"interface"), "and a span whose marks this run never reached is left out")


func test_a_kind_of_work_timed_twice_adds_up() -> void:
    var before := SaBootMarks.work_total_usec()
    var began := Time.get_ticks_usec() - 2000
    SaBootMarks.add_work(&"suite probe", began)
    SaBootMarks.add_work(&"suite probe", Time.get_ticks_usec() - 1000)
    assert_true(SaBootMarks.work_usec[&"suite probe"] >= 3000, "Two timings of one kind are one share")
    assert_true(SaBootMarks.work_total_usec() - before >= 3000, "and the total grows by both")
    SaBootMarks.work_usec.erase(&"suite probe")


func test_the_table_carries_the_shares() -> void:
    assert_true(SaBootMarks.table().has("shares"), "The perf block's startup table has the shares")
