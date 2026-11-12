## The layers-list timing suites hold a bound that a busy machine does not
## break.
##
## The layers-list timing suites time their acts through `BusyBound`, which spins fixed work
## just before and just after an act and moves the 50 ms line by how much slower
## than quiet the spin ran. Here the clock is a counter the spin and the act
## advance by hand, so the bound's arithmetic is read with no machine under it.
extends "res://tests/test_framework.gd"

const BusyBound = preload("res://tests/fixtures/busy_bound.gd")

## The spin's microseconds on the counter's quiet machine.
const QUIET_USEC := 1000.0

## An act of the layers list on a quiet machine, under the line.
const ACT_MSEC := 40.0


## A clock that moves only when the spin or the act moves it.
class Counter:
    extends RefCounted

    var now_usec := 0
    var spin_usec := 0

    func _init(usec: int) -> void:
        spin_usec = usec

    func read() -> int:
        return now_usec

    func spin() -> void:
        now_usec += spin_usec

    func take(msec: float) -> void:
        now_usec += int(msec * 1000.0)


func _bound(counter: Counter) -> BusyBound:
    return BusyBound.new(50.0, counter.read, counter.spin, QUIET_USEC)


func test_a_quiet_act_under_the_line_holds_at_the_line() -> void:
    var counter := Counter.new(int(QUIET_USEC))
    var bound := _bound(counter)
    assert_eq(bound.time("an act", func() -> void: counter.take(ACT_MSEC)), ACT_MSEC, "the act reads 40 ms")
    assert_eq(bound.scale, 1.0, "a spin at its quiet time leaves the line where it is")
    assert_eq(bound.bound_ms(), 50.0, "at 50 ms")
    assert_true(bound.all_held, bound.worst)


func test_a_spin_three_times_as_long_moves_the_line_with_the_act() -> void:
    var counter := Counter.new(int(QUIET_USEC * 3.0))
    var bound := _bound(counter)
    bound.time("an act on a busy machine", func() -> void: counter.take(ACT_MSEC * 3.0))
    assert_eq(bound.took_ms, 120.0, "the act reads three times its quiet 40 ms")
    assert_eq(bound.scale, 3.0, "the spin three times as long moves the line three times")
    assert_eq(bound.bound_ms(), 150.0, "to 150 ms")
    assert_true(bound.all_held, "and the act holds: " + bound.worst)


func test_an_act_three_times_as_long_on_a_quiet_spin_breaks_the_line() -> void:
    var counter := Counter.new(int(QUIET_USEC))
    var bound := _bound(counter)
    bound.time("an act slow on its own", func() -> void: counter.take(ACT_MSEC * 3.0))
    assert_eq(bound.scale, 1.0, "a quiet spin leaves the line at 50 ms")
    assert_false(bound.all_held, "and 120 ms breaks it")
    assert_true(bound.worst.begins_with("an act slow on its own took 120.0 ms"), "the message names the act: " + bound.worst)


func test_one_broken_act_among_held_ones_breaks_the_bound() -> void:
    var counter := Counter.new(int(QUIET_USEC))
    var bound := _bound(counter)
    bound.time("the first", func() -> void: counter.take(ACT_MSEC))
    bound.time("the second", func() -> void: counter.take(ACT_MSEC * 1.5))
    bound.time("the third", func() -> void: counter.take(ACT_MSEC))
    assert_false(bound.all_held, "60 ms among two of 40 breaks the bound")
    assert_true(bound.worst.begins_with("the second took 60.0 ms"), "and the worst named is the one past it: " + bound.worst)


## A faster spin than the quiet one never tightens the line, and a stalled one
## loosens it no further than four times.
func test_the_line_moves_between_once_and_four_times() -> void:
    var fast := Counter.new(int(QUIET_USEC / 2.0))
    var bound := _bound(fast)
    bound.time("an act", func() -> void: fast.take(ACT_MSEC))
    assert_eq(bound.bound_ms(), 50.0, "a spin faster than quiet keeps the line at 50 ms")
    var stalled := Counter.new(int(QUIET_USEC * 10.0))
    bound = _bound(stalled)
    bound.time("an act", func() -> void: stalled.take(ACT_MSEC * 5.0))
    assert_eq(bound.bound_ms(), 200.0, "a spin ten times as long moves it to four times, 200 ms")
    assert_false(bound.all_held, "so 200 ms is no excuse")


## An act that answers its own share, as the click suite takes the fold's off, is held by
## that share and not by the wall clock around it.
func test_an_act_answering_its_own_share_is_read_by_it() -> void:
    var counter := Counter.new(int(QUIET_USEC))
    var bound := _bound(counter)
    var took := bound.time(
        "a share",
        func() -> float:
            counter.take(80.0)
            return 30.0
    )
    assert_eq(took, 30.0, "the act's own 30 ms is what is read")
    assert_true(bound.all_held, bound.worst)
