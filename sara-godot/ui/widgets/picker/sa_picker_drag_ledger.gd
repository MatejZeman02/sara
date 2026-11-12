## What a drag in a picker shape costs and how far its handle trails the pen,
## kept for the state dump.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `scripts/colour_square_drag_on_the_seat.py` drags across the Colour
## Picker's square from a seat, and these are the two
## things it reads that only the shape knows: what sending a colour cost, every
## listener of the shape's `color_changed` and all they run in turn, and when
## the handle was drawn where. Off the dump, it costs a clock read a send and a
## small dictionary a draw.
class_name SaPickerDragLedger
extends RefCounted

## How many draws are kept, some ten seconds of a drag at 60 Hz.
const DRAWS_KEPT: int = 600

var _sends: int = 0
var _send_usec: int = 0
var _send_usec_max: int = 0
## The last draws of the handle, each its two axes and the wall clock of the
## draw in seconds, which a pointer's log is read against.
var _drawn: Array[Dictionary] = []


## One colour sent, which took *usec* microseconds.
func sent(usec: int) -> void:
    _sends += 1
    _send_usec += usec
    _send_usec_max = maxi(_send_usec_max, usec)


## The handle drawn at *across* and *up*, now.
func drew(across: float, up: float) -> void:
    _drawn.append({"across": across, "up": up, "unix": Time.get_unix_time_from_system()})
    if _drawn.size() > DRAWS_KEPT:
        _drawn = _drawn.slice(_drawn.size() - DRAWS_KEPT)


## The sends counted so far and the draws kept, for the dump.
func report() -> Dictionary:
    return {
        "sends": {"count": _sends, "usec": _send_usec, "usec_max": _send_usec_max},
        "drawn": _drawn.duplicate(),
    }
