## The column a layer list's rows stand in, top of the stack first, which keeps
## the place of a row that sleeps.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A `VBoxContainer` lays out its shown children and closes up over a hidden
## one, so a row hidden to spare a show of the docker its controls would have
## moved every row under it and the scroll bar with them. This column stacks
## its children as that one does, the same separation between them, and a
## hidden child it is told a size for keeps that place, at the height it was
## laid out at, so every row, the scroll bar and a press read the places a
## whole column had. What a row's held size is, and which rows sleep, is
## [SaLayerRowSleep]'s. A hidden child with no held size takes no room, as in a
## `VBoxContainer`.
##
## **The column ends in a band of no row**, [constant TAIL] tall. A press on a
## row picks it and its drag reorders the stack, so a list longer than the
## docker would have nowhere a press and drag scrolls it, as [SaDragScroll]
## scrolls every docker's content. The band is that place once the list is
## scrolled to its end, and a drop below the last row lands on it as before.
class_name SaLayerRowColumn
extends Container

## The band under the last row, in logical pixels, a row's height.
const TAIL: int = 28

## What a hidden child holds, `held(row) -> Vector2`, the least width and the
## height a sleeping row keeps, or a negative size for a child that takes no
## room.
var _held: Callable


func _init(held: Callable) -> void:
    _held = held
    name = "VBox"
    set_meta(SaMake.KIND_META, SaMake.Kind.COLUMN)


func _notification(what: int) -> void:
    if what == NOTIFICATION_SORT_CHILDREN:
        _lay_out()


func _get_minimum_size() -> Vector2:
    var wide := 0.0
    var tall := 0.0
    var placed := 0
    for child in get_children():
        var room := _room(child)
        if room.y < 0.0:
            continue
        wide = maxf(wide, room.x)
        tall += room.y
        placed += 1
    return Vector2(wide, tall + float(_gap() * maxi(0, placed - 1)) + float(SaUI.px(TAIL)))


## Stands every child that takes room under the one before it, as wide as the
## column, a shown one at its least height and a sleeping one at its held one.
func _lay_out() -> void:
    var top := 0.0
    var gap := float(_gap())
    for child in get_children():
        var room := _room(child)
        if room.y < 0.0:
            continue
        fit_child_in_rect(child as Control, Rect2(0.0, top, size.x, room.y))
        top += room.y + gap


## The least width and the height *child* takes, negative when it takes none:
## a node that is no control, one standing apart from the column, and a hidden
## one with nothing held.
func _room(child: Node) -> Vector2:
    var control := child as Control
    if control == null or control.top_level:
        return Vector2(-1.0, -1.0)
    if control.visible:
        return control.get_combined_minimum_size()
    return _held.call(control)


func _gap() -> int:
    return get_theme_constant(&"separation", &"VBoxContainer")
