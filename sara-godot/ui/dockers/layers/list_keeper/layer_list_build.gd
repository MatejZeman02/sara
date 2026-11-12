## Which rows of a deep stack a sync builds in this frame, so the rows of a
## stack the list does not hold yet are built a part a frame and no frame holds
## more than a part of them.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A row costs about a millisecond and a half to build, and a large test document's
## 756 rows held the frame its open ended in for over a second while the list
## built them all. Here a sync that would build more than [constant WHOLE_ROWS]
## new rows builds as many as [constant BUDGET_USEC] holds beside what the last
## part spent placing and styling the rows already built, in the stack's own
## order from the top, keeps every row that stands, and owes the rest to the
## next frame. Each part is a whole sync of the stack as it then stands, so a
## change of the stack while the rows are built starts the build again from
## it, and a press, a drop or a scroll acts on the rows the list shows, which
## are the stack's own rows in its own order with the unbuilt ones left out.
## The keeper puts the pick, the active row and the folds back after each part
## as it does after a whole sync, so the last part leaves exactly what one
## sync in one frame drew.
##
## A list outside the tree is built whole, as before: it has no frames to
## spread the build over, and a suite that drives a docker by hand reads its
## rows at once.
class_name SaLayerListBuild
extends RefCounted

## The most new rows a sync builds in one frame without parts. A fold, an add
## and a group's rows stay one sync, which the layers suites time.
const WHOLE_ROWS := 64

## What one frame's part may spend, in microseconds, building its new rows and
## placing and styling every row the list holds. A quarter of the tenth of a
## second a frame may hold, because a part's rows cost what the last part's did
## only roughly, and on a busy machine one part ran 40 per cent over its share.
## At half, the parts after an open of a large test document ran 60 to 70 ms beside
## the frame's other 35 ms, and frames of 0.1 to 0.14 s followed. At a quarter
## every other part still ran 38 ms, the rows built 30 of it, and the new rows
## drew for up to 30 ms after. At 15 ms and then at 8, beside the frame's
## composite of 12 to 19 ms, frames of a large test document's open still reached
## 0.12 s until the rows' pictures were counted against their
## own share, see [method SaLayerRowReuse.rebuild].
const BUDGET_USEC := 8_000

## The fewest new rows a frame builds, so the build ends however slow a row.
## Eight new rows of a large test document cost 20 to 25 ms on their own, more than
## the whole share, so the floor is three.
const FEWEST := 3

## What a row was taken to cost before any was timed, in microseconds. The
## dearest a row was timed at, the first rows of an open, so the first part,
## which lands in the frame the open ends in, never takes more than its share.
const FIRST_GUESS_USEC := 3000.0

## What one new row cost in the last part timed, in microseconds.
var _usec_per_row: float = FIRST_GUESS_USEC

## What the last part spent beside its new rows, placing and styling every row
## the list holds, which grows as the rows do and comes out of the next part's
## share first.
var _rest_usec: float = 0.0

## The frame the last part was built in and what it spent, so a second sync in
## one frame builds only what the frame has left.
var _part_frame: int = -1
var _part_usec: int = 0

## The new rows the part under way builds, which [method took] divides by.
var _fresh: int = 0

## Whether rows of the stack were left out of the last part for a frame after,
## which the keeper reads to owe the next frame a part.
var owing: bool = false

## The rows the list held when [method part] last read it, by the layer or the
## record each draws, as [method SaLayerRowReuse.standing_rows] answers. The
## rebuild that follows reads a copy rather than walk the rows again, which on
## a large test document's 593 rows was half a millisecond a sync.
var _standing: Dictionary = {}

## The row of [member _standing] that draws each entry [method part] last
## answered, or null for an entry built anew, in the entries' order, so the
## rebuild matches each entry to its row once rather than twice.
var _matched: Array = []


## What *list* draws in this sync, out of *drawn*, the entries a whole sync
## draws in [method SaLayerRowReuse.rebuild]'s shape. Every entry whose row
## stands is kept, and new ones are taken in order while the frame's share
## lasts. A filter's row is left out with its layer's. All of *drawn* when the
## list is outside the tree or the new rows are few.
func part(list: SaLayerList, drawn: Array) -> Array:
    _fresh = 0
    _standing = SaLayerRowReuse.standing_rows(list)
    var rows: Array = []
    rows.resize(drawn.size())
    var fresh := 0
    for index in drawn.size():
        var row := SaLayerRowReuse.standing_row(_standing, drawn[index])
        rows[index] = row
        if row == null:
            fresh += 1
    if (not owing and fresh <= WHOLE_ROWS) or not list.is_inside_tree():
        owing = false
        _fresh = fresh
        _matched = rows
        return drawn
    var room := _room()
    var out: Array = []
    _matched = []
    var shown_layers := {}
    owing = false
    for index in drawn.size():
        var entry: Array = drawn[index]
        var stands: bool = rows[index] != null
        var node: Object = entry[0] if entry.size() == 2 else entry[1]
        if entry.size() != 2 and node != null and not shown_layers.has(node):
            if not stands:
                owing = true
            continue
        if stands or _fresh < room:
            out.append(entry)
            _matched.append(rows[index])
            shown_layers[node] = true
            if not stands:
                _fresh += 1
        else:
            owing = true
    return out


## Builds the rows of *wanted*, what [method part] last answered, keeping the
## rows it found standing, by [method SaLayerRowReuse.rebuild], which adds to
## *fresh* the rows it built and to *worn* the kept rows that wore the pick.
## False, and nothing built, for a list with no rows and no build under way,
## which the keeper builds whole, or a list with a rename open.
func rebuild(list: SaLayerList, wanted: Array, fresh: Array, worn: Array) -> bool:
    if list.row_count() == 0 and not owing:
        return false
    return SaLayerRowReuse.rebuild(list, wanted, fresh, worn, _standing, _matched)


## Says the part asked of [method part] took *rows_usec* to build its rows and
## the whole sync *whole_usec*, the reading of the stack, the pick and the
## styling with them, which sets
## what the next part takes a row and the rest to cost.
func took(rows_usec: int, whole_usec: int) -> void:
    var frame := Engine.get_process_frames()
    if frame != _part_frame:
        _part_frame = frame
        _part_usec = 0
    _part_usec += whole_usec
    if _fresh > 0:
        _usec_per_row = maxf(float(rows_usec) / _fresh, 1.0)
    _rest_usec = maxf(float(whole_usec - rows_usec), 0.0)


## Starts a frame's share afresh, at the start of the part a frame owes, so a
## suite that calls the parts in one frame of its own builds each whole.
func new_frame() -> void:
    _part_frame = -1
    _part_usec = 0


## Lets go of the rows owed, after a sync that built the whole stack.
func stop() -> void:
    owing = false


## How many new rows this frame has room for: what is left of its share at the
## cost the last part measured, and never fewer than [constant FEWEST] in a
## frame no part has spent in.
func _room() -> int:
    var left := BUDGET_USEC - _rest_usec
    if _part_frame == Engine.get_process_frames():
        left -= _part_usec
        return maxi(int(left / _usec_per_row), 0)
    return maxi(int(left / _usec_per_row), FEWEST)
