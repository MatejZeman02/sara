## The pictures of a reference board that are selected, and the box a left drag
## on the empty board draws to select them, as PureRef and a file manager have
## it.
##
## A folder of its own beside `ReferencePictureView` because the set and its
## box are one thing the view asks rather than draws. The view still owns which
## press starts a box and draws what this class answers: who is selected, the
## one picture the handles and the bar are for, what a drag moves and what Fit
## and Normalize act on, and the pictures a finished box takes.
##
## The set is kept in the order the pictures were added to it, and every read
## goes through `held`, which drops a picture the board no longer holds, so a
## picture removed by another way never lingers here. Nothing of it is saved.
class_name ReferenceSelection
extends RefCounted

## The selected pictures, possibly stale, which `held` filters.
var _pictures: Array[SaReferenceBoard.Picture] = []

## Whether a box is being drawn, and whether it adds to the selection rather
## than replacing it, the Ctrl drag. Read by the view, written here only.
var drawing: bool = false
var adding: bool = false

## Where the box was pressed and where the pointer is now, in the view's own
## coordinates.
var _box_from: Vector2 = Vector2.ZERO
var _box_to: Vector2 = Vector2.ZERO


## The selected pictures *board* still holds, in the order they were picked.
func held(board: SaReferenceBoard) -> Array[SaReferenceBoard.Picture]:
    var out: Array[SaReferenceBoard.Picture] = []
    if board == null:
        return out
    for picture in _pictures:
        if board.pictures.has(picture):
            out.append(picture)
    return out


## Whether *picture* is selected, on whichever board holds it.
func has(picture: SaReferenceBoard.Picture) -> bool:
    return picture != null and _pictures.has(picture)


## The one selected picture, or null when none is selected or several are,
## since the handles, the crop and the hover bar are each for one picture.
func one(board: SaReferenceBoard) -> SaReferenceBoard.Picture:
    var chosen := held(board)
    return chosen[0] if chosen.size() == 1 else null


## What Fit and Normalize act on: the selected pictures when there are two or
## more, and none otherwise, which is the whole board. One picture is not a
## selection to act on, because Sara selects every picture as it lands, so
## Normalize straight after an open would bring one picture to a size alone,
## and a fit to one picture is the double click's.
func several(board: SaReferenceBoard) -> Array[SaReferenceBoard.Picture]:
    var chosen := held(board)
    if chosen.size() < 2:
        chosen.clear()
    return chosen


## What a drag on *dragged* moves: the whole selection when it is one of them,
## and *dragged* alone otherwise.
func moving(board: SaReferenceBoard, dragged: SaReferenceBoard.Picture) -> Array[SaReferenceBoard.Picture]:
    var chosen := held(board)
    if chosen.has(dragged):
        return chosen
    var out: Array[SaReferenceBoard.Picture] = [dragged]
    return out


## The rectangle *pictures* fit in, in board units, for a fit to them.
static func bounds(pictures: Array[SaReferenceBoard.Picture]) -> Rect2:
    var out := pictures[0].rect
    for picture in pictures:
        out = out.merge(picture.rect)
    return out


## *picture* alone, or nothing for a null.
func only(picture: SaReferenceBoard.Picture) -> void:
    _pictures.clear()
    if picture != null:
        _pictures.append(picture)


## *picture* added when it was out and taken out when it was in, the Ctrl and
## Shift click.
func toggle(picture: SaReferenceBoard.Picture) -> void:
    if picture == null:
        return
    if _pictures.has(picture):
        _pictures.erase(picture)
    else:
        _pictures.append(picture)


## *picture* taken out, for a removal.
func forget(picture: SaReferenceBoard.Picture) -> void:
    _pictures.erase(picture)


func clear() -> void:
    _pictures.clear()


## A box starts at *at*. With *add* the pictures it touches join the
## selection, which is the Ctrl drag, and otherwise they replace it.
func begin_box(at: Vector2, add: bool) -> void:
    drawing = true
    _box_from = at
    _box_to = at
    adding = add


func drag_box(at: Vector2) -> void:
    if drawing:
        _box_to = at


## The box in the view's own coordinates, or an empty one when none is drawn.
func box() -> Rect2:
    return Rect2(_box_from, _box_to - _box_from).abs() if drawing else Rect2()


## The box as the dump writes it, x, y, width and height, all zero with none.
func box_report() -> Array:
    var shown := box()
    return [shown.position.x, shown.position.y, shown.size.x, shown.size.y]


## The box lifted: every picture of *board* it touches is selected, those the
## board shows at all, which in solo is the soloed one alone. A box that
## touched none replaces the selection with nothing, or leaves it under Ctrl.
## Answers whether the selection changed.
func end_box(board: SaReferenceBoard) -> bool:
    if not drawing:
        return false
    drawing = false
    var before := _pictures.duplicate()
    if not adding:
        _pictures.clear()
    if board != null:
        var area := Rect2(board.to_board(_box_from), (_box_to - _box_from) / board.zoom).abs()
        for picture in board.ordered():
            if not _pictures.has(picture) and touches(area, picture.rect):
                _pictures.append(picture)
    return before != _pictures


## The box drawn, without a selection change: a press that never opened out.
func drop_box() -> void:
    drawing = false


## Whether a box over *area* touches a picture at *rect*, both in board units.
## Touching an edge counts, so a box laid along a thin picture takes it.
static func touches(area: Rect2, rect: Rect2) -> bool:
    var across := area.end.x >= rect.position.x and rect.end.x >= area.position.x
    return across and area.end.y >= rect.position.y and rect.end.y >= area.position.y
