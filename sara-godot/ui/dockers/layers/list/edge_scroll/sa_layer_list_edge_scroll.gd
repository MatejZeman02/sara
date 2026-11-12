## Scrolls the layer list while a row is held near its top or bottom edge.
##
## So a row can be carried to a place the list has scrolled out of view. The
## list's drag hands every motion to
## `follow`, and while the pointer stands in a band at either edge of the list
## each frame moves the list that way and puts the drop mark on whatever row is
## under the pointer now. A layer's row and a filter's row share the drag, so
## both scroll. Its own file because the list is at its limit, and a node of
## its own because a held pointer sends no motion, so only a frame can move it.
class_name SaLayerListEdgeScroll
extends Node

## The height of the band at each edge, in the list's own logical pixels, which
## is a little over one row.
const BAND: float = 40.0

## The speed with the pointer on the edge itself, in pixels a second. It falls
## in a straight line to nothing at the band's inner side, so the closer the
## pointer, the faster the list goes.
const TOP_SPEED: float = 900.0

var _list: SaLayerList
## What puts the drop mark under a point, the list's own `_aim_at`.
var _aim: Callable
## Where the pointer last was, in the docker window's space, the same as the
## rows' rectangles.
var _pointer: Vector2 = Vector2.ZERO
## The part of a pixel the last frames moved and `scroll_vertical`, an integer,
## could not take yet, so a slow scroll still moves.
var _carry: float = 0.0


func _init(list: SaLayerList, aim: Callable) -> void:
    _list = list
    _aim = aim
    name = "EdgeScroll"
    set_process(false)


## A motion of the drag at *global_point*: the mark goes under it, and the frames
## start asking whether it stands in a band.
func follow(global_point: Vector2) -> void:
    _pointer = global_point
    _aim.call(global_point)
    set_process(true)


func _process(delta: float) -> void:
    step(delta)


## One frame of *delta* seconds. Moves the list as far as the pointer's place in
## a band asks and aims the mark again, and answers whether the list moved. A
## suite calls it straight, because a suite cannot wait for frames.
func step(delta: float) -> bool:
    if not _list.dragging or not _list.is_inside_tree():
        _carry = 0.0
        set_process(false)
        return false
    var speed := speed_at(_list.get_global_rect(), _pointer)
    if speed == 0.0:
        _carry = 0.0
        return false
    _carry += speed * delta
    var whole := int(_carry)
    if whole == 0:
        return false
    _carry -= whole
    var before := _list.scroll_vertical
    _list.scroll_vertical = before + whole
    if _list.scroll_vertical == before:
        _carry = 0.0
        return false
    # The container moves its rows when it next sorts, which is deferred, and
    # the mark has to be measured against where they are now.
    _list.notification(Container.NOTIFICATION_SORT_CHILDREN)
    _aim.call(_pointer)
    return true


## Pixels a second the list scrolls with the pointer at *point*, negative upward,
## given *rect*, the list's rectangle in the same space. Inside a band the speed
## grows from nothing at its inner side to `TOP_SPEED` at the edge, and past the
## edge, over the docker's title or its buttons, it stays at `TOP_SPEED`, as a
## hand carrying a row down overshoots the list's last pixel. Nothing between the
## bands or beside the list. Static, so a suite asks it with no window.
static func speed_at(rect: Rect2, point: Vector2) -> float:
    if point.x < rect.position.x or point.x >= rect.end.x:
        return 0.0
    var band := minf(BAND, rect.size.y / 4.0)
    if band <= 0.0:
        return 0.0
    var from_top := point.y - rect.position.y
    if from_top < band:
        return -TOP_SPEED * minf(1.0 - from_top / band, 1.0)
    var from_bottom := rect.end.y - point.y
    if from_bottom < band:
        return TOP_SPEED * minf(1.0 - from_bottom / band, 1.0)
    return 0.0
