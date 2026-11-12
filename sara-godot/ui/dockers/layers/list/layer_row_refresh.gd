## Draws a layer list's rows again from the document, the rows in view at
## once and the rest as a scroll, a resize or the rows laid out again bring
## them into view.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A step that changes a few rows of a deep stack, a layer added, a filter
## attached, a layer made active, asks the list to draw every row again, because
## what else the step changed is not said. Each row then asks what it draws
## from and leaves itself as it stands when nothing moved, which is what
## [method SaLayerRowView.refresh] does, and still the asking was 5 ms of the
## large test document's 593 rows, and the drawing before it 15 ms. The painter sees
## the rows in view and no other, so those are drawn now, and every other row
## is owed until it comes into view, when the list's wake draws it before the
## frame is. A report of the rows pays every row owed first, so what it reads
## is what a whole refresh drew.
##
## Owing a row costs nothing: the rows drawn since the last whole refresh are
## the ones held, and every other row is owed, so a refresh of 790 rows touches
## the twenty in view and no other. The view is found by halving, because the
## rows stand in their order down the list.
##
## A list outside the tree, or one never laid out, has no view to tell rows
## by, and draws every row at once, as it always did, which is what a suite
## that drives a docker by hand reads.
class_name SaLayerRowRefresh
extends RefCounted

## Rows above and below the view drawn with it, so a short scroll finds them
## drawn already.
const MARGIN_ROWS := 8

## The rows drawn since the last whole refresh, by instance id. A row of the
## list not here is owed.
var _drawn: Dictionary[int, bool] = {}

## Whether a row may be owed at all, false once every row is drawn.
var _owing := false


## Draws the rows of *list* in view for *document* now and owes the rest.
func all(list: SaLayerList, document: SaDocument) -> void:
    var rows := list.rows
    var shown := _in_view(list)
    _drawn.clear()
    _owing = shown.x >= 0
    var first := 0 if shown.x < 0 else shown.x
    var last := rows.size() - 1 if shown.x < 0 else shown.y
    for index in range(first, last + 1):
        _pay(rows[index], document)


## Draws the owed rows of *list* that have come into view.
func pay_in_view(list: SaLayerList, document: SaDocument) -> void:
    if not _owing:
        return
    var shown := _in_view(list)
    if shown.x < 0:
        pay_all(list, document)
        return
    var rows := list.rows
    for index in range(shown.x, shown.y + 1):
        _pay(rows[index], document)


## Draws every owed row, for a reader that reads them all.
func pay_all(list: SaLayerList, document: SaDocument) -> void:
    if not _owing:
        return
    for row in list.rows:
        _pay(row, document)
    _owing = false
    _drawn.clear()


## Whether *row* waits for a refresh.
func owes(row: SaRowFrame) -> bool:
    return _owing and not _drawn.has(row.get_instance_id())


func _pay(row: SaRowFrame, document: SaDocument) -> void:
    var id := row.get_instance_id()
    if _drawn.has(id):
        return
    _drawn[id] = true
    row.refresh(document)


## The first and last index of the rows in view of *list*, a margin either
## side, or -1 for both when the list has no view to tell them by. Read off the
## rows' places as last laid out, so a row moved since is drawn by the wake that
## the layout brings.
static func _in_view(list: SaLayerList) -> Vector2i:
    var rows := list.rows
    if not list.is_inside_tree() or not list.is_visible_in_tree() or list.size.y <= 0.0 or rows.is_empty():
        return Vector2i(-1, -1)
    var top := float(list.scroll_vertical)
    var bottom := top + list.size.y
    var first := first_below(rows, top)
    var last := first
    while last + 1 < rows.size() and rows[last + 1].position.y <= bottom:
        last += 1
    return Vector2i(maxi(0, first - MARGIN_ROWS), mini(rows.size() - 1, last + MARGIN_ROWS))


## The index of the first of *rows* whose bottom reaches *top*, found by
## halving.
static func first_below(rows: Array[SaRowFrame], top: float) -> int:
    var low := 0
    var high := rows.size() - 1
    while low < high:
        @warning_ignore("integer_division")
        var middle := (low + high) / 2
        var row := rows[middle]
        if row.position.y + row.size.y < top:
            low = middle + 1
        else:
            high = middle
    return low
