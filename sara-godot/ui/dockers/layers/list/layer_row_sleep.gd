## Keeps the rows of a layer list that stand far from the view asleep: each
## one hidden, its controls taken out of the tree, and its place in the column
## held at the size it was laid out at, so a show, a hide or a scroll of the
## docker touches the rows in view and no other.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A window shown or hidden tells every control under it, and each control
## shown works out its size again and its container sorts. A large test document's
## 827 rows are 12124 nodes, and a Tab spent 20 to 30 ms telling them and 75
## to 86 ms in the layout that followed. A hidden row stops the telling at
## itself, and [SaLayerRowColumn] stands it where it stood, so
## the scroll bar and every row's place stay as they were and a press, a drop
## or a halving that reads a row's place reads it right whether the row is
## awake or not. That took the layout to 15 ms, and still the window's own
## show and hide took 10 to 20 ms, a cost that grows with every node under
## the window whether it is shown or not. Taken out of the tree, a sleeping
## row's controls cost nothing there, and a Tab's show came down to a frame of
## 38 ms with the layout 11 ms of it.
##
## A row is woken as soon as it comes within [constant NEAR] rows of the view,
## by the list's wake on a scroll, a resize or a layout, which runs before the
## frame is drawn, and a rename or a report wakes the rows it reads. A row is
## put to sleep once it stands [constant FAR] rows out, [constant BATCH] rows a
## frame while the list is shown and every one at once while it is hidden. A
## row never laid out is left awake, because its size is not known until the
## column has placed it, and a row freed while it sleeps frees its controls in
## its own predelete.
##
## A list outside the tree, or one never laid out, has no view to tell rows by,
## and keeps every row awake, which is what a suite that drives a list by hand
## reads.
class_name SaLayerRowSleep
extends Node

## Rows above and below the view woken with it, so a short scroll finds them
## awake.
const NEAR := 4

## Rows above and below the view left awake, so a scroll back and forth over a
## few rows neither wakes nor puts a row to sleep at every step.
const FAR := 8

## Rows put to sleep in one frame while the list is shown, a few milliseconds.
const BATCH := 96

var _list: SaLayerList

## The least width and the height each sleeping row was laid out at, by
## instance id.
var _asleep: Dictionary[int, Vector2] = {}


func _init(list: SaLayerList) -> void:
    _list = list
    name = "RowSleep"
    set_process(false)


## Whether *row* is asleep.
func sleeps(row: SaRowFrame) -> bool:
    return _asleep.has(row.get_instance_id())


## How many rows sleep, for a suite and a capture.
func asleep_count() -> int:
    var count := 0
    for row in _list.rows:
        count += 1 if sleeps(row) else 0
    return count


## Wakes the rows within [constant NEAR] of the view, and starts the frames
## that put the far ones to sleep when there are any. The list's wake calls it,
## on a scroll, a resize and a layout.
func follow() -> void:
    var shown := view(_list)
    if shown.x < 0:
        return
    var rows := _list.rows
    for index in range(maxi(0, shown.x - NEAR), mini(rows.size(), shown.y + NEAR + 1)):
        wake(rows[index])
    if _far_awake(shown):
        set_process(true)


func _process(_delta: float) -> void:
    if not step():
        set_process(false)


## Puts far rows to sleep, every one while the list is hidden and
## [constant BATCH] while it is shown, and answers whether any is left awake.
## A suite calls it straight, because a suite cannot wait for frames.
func step() -> bool:
    var shown := view(_list)
    if shown.x < 0:
        return false
    if not _asleep.is_empty():
        _forget_gone()
    var rows := _list.rows
    var budget := BATCH if _list.is_visible_in_tree() else rows.size()
    # From either end inwards, so the rows nearest the view sleep last.
    var top := 0
    var bottom := rows.size() - 1
    while budget > 0 and (top < shown.x - FAR or bottom > shown.y + FAR):
        if top < shown.x - FAR:
            budget -= _sleep(rows[top])
            top += 1
        if budget > 0 and bottom > shown.y + FAR:
            budget -= _sleep(rows[bottom])
            bottom -= 1
    return _far_awake(shown)


## Shows *row* again, at its own least size.
func wake(row: SaRowFrame) -> void:
    var id := row.get_instance_id()
    if not _asleep.has(id):
        return
    _asleep.erase(id)
    if row.hbox.get_parent() == null:
        row.add_child(row.hbox)
    row.visible = true


## The least width and the height *row* keeps while it sleeps, or a negative
## size for a row awake, which is what [SaLayerRowColumn] stands a hidden row by.
func held(row: Control) -> Vector2:
    return _asleep.get(row.get_instance_id(), Vector2(-1.0, -1.0))


## Wakes every row, for a reader that reads them all.
func wake_all() -> void:
    for row in _list.rows:
        wake(row)


## Hides *row* with its place held at the size it was laid out at, and answers
## 1 when it fell asleep and 0 when it was asleep already, never laid out or
## open for renaming.
func _sleep(row: SaRowFrame) -> int:
    var id := row.get_instance_id()
    if _asleep.has(id) or row.size.y <= 0.0 or row.is_queued_for_deletion() or row.edit.visible:
        return 0
    _asleep[id] = Vector2(row.get_combined_minimum_size().x, row.size.y)
    row.visible = false
    row.remove_child(row.hbox)
    return 1


## Whether a laid-out row more than [constant FAR] rows from the view is awake.
func _far_awake(shown: Vector2i) -> bool:
    var rows := _list.rows
    for index in range(0, mini(rows.size(), shown.x - FAR)):
        if not sleeps(rows[index]) and rows[index].size.y > 0.0:
            return true
    for index in range(maxi(0, shown.y + FAR + 1), rows.size()):
        if not sleeps(rows[index]) and rows[index].size.y > 0.0:
            return true
    return false


## Forgets the rows the list no longer holds, which a rebuild let go of.
func _forget_gone() -> void:
    var kept: Dictionary[int, bool] = {}
    for row in _list.rows:
        kept[row.get_instance_id()] = true
    for id: int in _asleep.keys():
        if not kept.has(id):
            _asleep.erase(id)


## The first and last index of the rows of *list* in its view, or -1 for both
## when the list stands outside the tree or was never laid out. Read whether the
## list is shown or not, off the rows' places as last laid out, which a sleeping
## row keeps.
static func view(list: SaLayerList) -> Vector2i:
    var rows := list.rows
    if not list.is_inside_tree() or list.size.y <= 0.0 or rows.is_empty() or rows[0].size.y <= 0.0:
        return Vector2i(-1, -1)
    var top := float(list.scroll_vertical)
    var bottom := top + list.size.y
    var first := SaLayerRowRefresh.first_below(rows, top)
    var last := first
    while last + 1 < rows.size() and rows[last + 1].position.y <= bottom:
        last += 1
    return Vector2i(first, last)
