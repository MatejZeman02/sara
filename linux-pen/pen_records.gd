## The kernel's `input_event` records a tablet's pen node sends, read into the
## pen's state: in range or out, touching or not, each barrel button held, and
## an airbrush's finger wheel.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Bytes in any pieces.** The node is read through a pipe, which hands over
## what it holds, so a record split between two reads is kept until the rest of
## it comes. A record is 24 bytes on a 64-bit kernel: the time as two 64-bit
## numbers, then the type, the code and the value, little-endian. Sara ships
## for 64-bit Linux alone, where that holds.
##
## **A frame at a time.** The kernel sends the changes of one moment and closes
## them with `SYN_REPORT`, so the state the tools read is the last closed
## frame's, never half of one. `SYN_DROPPED` says the kernel's buffer overran
## and changes were lost, which a reader holding the node through a pipe cannot
## ask again, so the state is unknown until the pen next enters or leaves the
## tablet's range, where the kernel reports every button afresh.
##
## **Unknown until the pen moves in or out of range.** The node reports
## changes, never the state it starts in, so a reader opened with the pen held
## over the tablet and the upper down hears nothing of the upper until it
## changes. [method now] answers null until a frame brings the pen into the
## range or takes it out, and the tools fall back on what Godot says.
##
## **Out of range every button is let go**, whether or not the frame says so,
## because nothing is held by a pen the tablet cannot see.
##
## **The airbrush's wheel is a place, kept.** An airbrush comes into range as
## `BTN_TOOL_AIRBRUSH` and reports its finger wheel as `ABS_WHEEL`, between the
## lowest and highest values the node declares, which the reader is built with
## and reads as 0 to 1. The kernel sends an axis only when it moves, so the
## wheel is where the last frame that moved it left it, out of range as well,
## and nought before any frame moved it. Built with no range, as for a node
## that declares no wheel, the wheel is never read and stays at nought.
extends RefCounted

## Bytes in one record on a 64-bit kernel.
const RECORD_BYTES := 24

## From `linux/input-event-codes.h`.
const EV_SYN := 0x00
const EV_KEY := 0x01
const EV_ABS := 0x03
const SYN_REPORT := 0
const SYN_DROPPED := 3
const ABS_WHEEL := 0x08
const BTN_TOOL_PEN := 0x140
const BTN_TOOL_RUBBER := 0x141
const BTN_TOOL_AIRBRUSH := 0x144
const BTN_STYLUS3 := 0x149
const BTN_TOUCH := 0x14A
const BTN_STYLUS := 0x14B
const BTN_STYLUS2 := 0x14C

## A key's value when the kernel repeats a held key, which changes nothing.
const REPEAT := 2

## The tools that come into range, as bits of [member _ends]: a pen's two ends
## and an airbrush.
const PEN_END := 1
const RUBBER_END := 2
const AIRBRUSH_END := 4

## The wheel's lowest value as the node declares it.
var _wheel_low: int = 0

## The wheel's highest value as the node declares it, at or below
## [member _wheel_low] for a node that declares no wheel.
var _wheel_high: int = 0

## The first bytes of a record the last read cut short.
var _rest := PackedByteArray()

## The state as the open frame leaves it.
var _frame := SaPenSource.State.new()

## The state as the last closed frame left it.
var _closed := SaPenSource.State.new()

## The ends in range as the open frame leaves them, [constant PEN_END] and
## [constant RUBBER_END].
var _ends: int = 0

## Whether the open frame brought an end into range or took one out.
var _range_moved: bool = false

## Whether the closed state is the pen's, which it is from the first frame that
## moved the pen in or out of range until a frame is dropped.
var _known: bool = false

## Whether records are being skipped after `SYN_DROPPED`, to the next report.
var _dropping: bool = false


## *wheel_range* is the lowest and highest value the node declares for
## `ABS_WHEEL`, as `x` and `y`. Left at nought, or with no room between the
## two, the wheel is not read.
func _init(wheel_range: Vector2i = Vector2i.ZERO) -> void:
    _wheel_low = wheel_range.x
    _wheel_high = wheel_range.y


## Whether the wheel is read, which a range with room in it decides.
func reads_wheel() -> bool:
    return _wheel_high > _wheel_low


## Reads *bytes* off the node, any number of whole or cut records.
func feed(bytes: PackedByteArray) -> void:
    var data := _rest + bytes
    var whole := data.size() - data.size() % RECORD_BYTES
    for at: int in range(0, whole, RECORD_BYTES):
        _take(data.decode_u16(at + 16), data.decode_u16(at + 18), data.decode_s32(at + 20))
    _rest = data.slice(whole)


## The pen as the last closed frame left it, a copy, or null while it is not
## known. See the class's note.
func now() -> SaPenSource.State:
    return _closed.copy() if _known else null


## The wheel as the last closed frame left it, 0 to 1, and nought while the
## state is not known or the wheel is not read. Allocates nothing, so a brush
## may ask it at every dab through [method SaPenSource.wheel].
func wheel() -> float:
    return _closed.wheel if _known else 0.0


func _take(type: int, code: int, value: int) -> void:
    if type == EV_SYN:
        if code == SYN_DROPPED:
            _dropping = true
        elif code == SYN_REPORT:
            _close()
        return
    if _dropping:
        return
    if type == EV_ABS:
        if code == ABS_WHEEL and reads_wheel():
            _frame.wheel = clampf(float(value - _wheel_low) / float(_wheel_high - _wheel_low), 0.0, 1.0)
        return
    if type != EV_KEY or value == REPEAT:
        return
    var down := value != 0
    match code:
        BTN_TOOL_PEN:
            _end(PEN_END, down)
        BTN_TOOL_RUBBER:
            _end(RUBBER_END, down)
        BTN_TOOL_AIRBRUSH:
            _end(AIRBRUSH_END, down)
        BTN_TOUCH:
            _frame.touching = down
        BTN_STYLUS:
            _barrel(SaPenSource.Barrel.FIRST, down)
        BTN_STYLUS2:
            _barrel(SaPenSource.Barrel.SECOND, down)
        BTN_STYLUS3:
            _barrel(SaPenSource.Barrel.THIRD, down)


func _end(end: int, down: bool) -> void:
    _ends = _ends | end if down else _ends & ~end
    _range_moved = true


func _barrel(barrel: SaPenSource.Barrel, down: bool) -> void:
    if down:
        _frame.barrels |= 1 << barrel
        _frame.last_pressed = barrel
    else:
        _frame.barrels &= ~(1 << barrel)


## Ends the open frame. After a drop the frame is thrown away and the state is
## not known until the pen moves in or out of range again.
func _close() -> void:
    if _dropping:
        _dropping = false
        _known = false
        _range_moved = false
        _frame = _closed.copy()
        return
    _frame.in_range = _ends != 0
    _frame.rubber = (_ends & RUBBER_END) != 0
    _frame.airbrush = (_ends & AIRBRUSH_END) != 0
    if not _frame.in_range:
        _frame.touching = false
        _frame.barrels = 0
    if _range_moved:
        _known = true
        _range_moved = false
    _closed = _frame.copy()
