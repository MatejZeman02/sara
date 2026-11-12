## The bound of a suite that holds an act to a line in milliseconds, moved by
## how busy the machine is at the moment of the act.
##
## A suite that reads the wall clock against a 50 ms line fails it
## under the load of a crowded gate and passes alone, so every such suite takes
## its line from here, and `rg BusyBound` lists them. This times a spin of
## fixed work in the same thread just before and just after the act, and when
## the spin is slower than it runs on a quiet machine the line moves by as
## much. A busy machine slows the spin with the act, so the act is read
## as it would run quietly, and an act slow on its own is still caught.
extends RefCounted

## The microseconds the spin takes on a development machine with nothing else
## running, the least of fifty runs of it inside the suites' Godot. A machine
## slower than that moves the line too, which keeps it the felt 50 ms.
const QUIET_SPIN_USEC := 1420.0

## The most the line moves. A spin stalled by one long slice of the scheduler
## would otherwise excuse any act, and four times covers the load of a gate.
const MOST_SCALE := 4.0

## The rounds of the spin, enough work to take about a millisecond and a half.
const SPIN_ROUNDS := 40000

## The line on a quiet machine, in milliseconds.
var line_ms: float

## How much slower than quiet the spins around the last act ran, never under 1.
var scale := 1.0

## The milliseconds the last act took, as the wall clock read them.
var took_ms := 0.0

## Whether every act timed so far came in under its line.
var all_held := true

## The act that came closest to its line, or went furthest past it, in words.
var worst := ""

var _worst_share := -1.0

## Answers the microseconds now, `Time.get_ticks_usec` unless a suite injects one.
var _clock: Callable

## The fixed work timed around an act.
var _spin: Callable

## The spin's microseconds on a quiet machine.
var _quiet_usec: float


## A bound of *limit_ms* on a quiet machine. A suite of the bound itself injects
## *clock*, *spin* and *quiet_usec*, the timing suites leave them out.
func _init(limit_ms: float, clock := Callable(), spin := Callable(), quiet_usec := QUIET_SPIN_USEC) -> void:
    line_ms = limit_ms
    _clock = clock if clock.is_valid() else Time.get_ticks_usec
    _spin = spin if spin.is_valid() else _spin_once
    _quiet_usec = quiet_usec


## Times *act*, named *what*, between two spins and answers its milliseconds.
## *act* answers the milliseconds of its own when only part of what it does is
## read, as when the fold's share is taken off, and nothing when the whole is.
func time(what: String, act: Callable) -> float:
    var before := _spin_usec()
    var start: int = _clock.call()
    var own: Variant = act.call()
    var whole := (int(_clock.call()) - start) / 1000.0
    var after := _spin_usec()
    took_ms = float(own) if own is float else whole
    scale = clampf((before + after) / 2.0 / _quiet_usec, 1.0, MOST_SCALE)
    var share := took_ms / bound_ms()
    all_held = all_held and share < 1.0
    if share > _worst_share:
        _worst_share = share
        worst = reading(what)
    print("probe " + reading(what))
    return took_ms


## The line the last act is held to, moved by how busy the machine was.
func bound_ms() -> float:
    return line_ms * scale


## The last act and its line, for a suite's message and its log.
func reading(what: String) -> String:
    return (
        "%s took %.1f ms, under %.1f ms (%.0f ms quiet, the spin %.2f times as slow)"
        % [what, took_ms, bound_ms(), line_ms, scale]
    )


func _spin_usec() -> float:
    var start: int = _clock.call()
    _spin.call()
    return float(int(_clock.call()) - start)


## Fixed arithmetic the compiler cannot drop, the same every time it runs.
static func _spin_once() -> float:
    var sum := 0.0
    for i: int in SPIN_ROUNDS:
        sum += sqrt(float(i) + sum * 0.000001)
    return sum
