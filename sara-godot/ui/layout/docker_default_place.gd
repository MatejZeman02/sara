## Where a docker opens that the layout being restored has no section for: at
## the side its registration names, `SaUIRegistry.register_docker`'s *side* and
## *order*, beside the dockers the layout opens there.
##
## A side's column is every open docker of the layout under the bar at that edge
## of the host or beside one that is, and a placed docker stands just inside it,
## toward the painting, under the bar. Two dockers placed on one side stack top down, the lower order
## higher, and one that would run past the foot starts a column further in.
##
## Its own class rather than a part of `DockerLayoutStore`, because the store
## reads a layout and applies it, and this answers one question of a layout the
## store has already read: where a docker it does not name goes. One is made for
## each restore, since it holds the stacks of that restore and no other.
class_name SaDockerDefaultPlace
extends RefCounted

## How near an edge of the host a docker's rectangle has to end to count as
## standing at that side, in the units its window measures in.
const EDGE_SLACK: int = 12

## The gap a placed docker keeps from the column beside it and from the docker
## above it.
const GAP: int = 4

## The rectangles of the dockers the layout opens, by section.
var _opened: Dictionary = {}

## `func() -> int`, the first logical row below the bar, the store's own.
var _top_inset: Callable

## Side -> the column of placed dockers it is filling: "edge", the inner edge
## it stands beside, "reach", the furthest in a docker of it reaches, and
## "foot", the row its lowest docker ends at.
var _columns: Dictionary = {}


func _init(opened: Dictionary, top_inset: Callable) -> void:
    _opened = opened
    _top_inset = top_inset


## *configs*, the store's docker configs of the dockers to place, in the order
## they are placed: by *order*, and by registration where two orders tie, which
## is the order the store lists them in.
static func in_order(configs: Array) -> Array:
    var indexed: Array = []
    for i in configs.size():
        indexed.append([int(configs[i].get("order", 0)), i, configs[i]])
    indexed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
    return indexed.map(func(row: Array) -> Dictionary: return row[2])


## The entry *win* opens with on *side* of *host*, open, at its own size cut to
## the host's height under the bar.
func entry_for(win: Window, side: StringName, host: Vector2i) -> Dictionary:
    var top := _top(win)
    var size := Vector2i(win.size.x, mini(win.size.y, maxi(host.y - top, 1)))
    var column: Dictionary = _columns.get(side, {})
    if column.is_empty():
        column = _column(_inner_edge(side, host, top), top)
    elif int(column["foot"]) + GAP + size.y > host.y:
        column = _column(int(column["reach"]), top)
    var left := side == &"left"
    var pos := Vector2i(int(column["edge"]) + GAP if left else int(column["edge"]) - GAP - size.x, int(column["foot"]) + GAP)
    pos.x = clampi(pos.x, 0, maxi(host.x - size.x, 0))
    column["foot"] = pos.y + size.y
    column["reach"] = maxi(int(column["reach"]), pos.x + size.x) if left else mini(int(column["reach"]), pos.x)
    _columns[side] = column
    return {"position": pos, "size": size, "visible": true}


## A column of placed dockers standing beside *edge*, empty, whose first docker
## opens at *top*.
static func _column(edge: int, top: int) -> Dictionary:
    return {"edge": edge, "reach": edge, "foot": top - GAP}


## The inner edge of *side*'s column on *host*, or the edge of the host when
## the layout opens nothing there. The column is every open docker under the
## bar that stands at that edge or beside one that does, so a toolbox and the
## options beside it are one column, and the inner edge is the furthest in any
## of them reaches. A docker past the middle of the host belongs to the other
## side, which keeps a layout full from edge to edge, as Full is, from carrying
## a column across the whole window.
func _inner_edge(side: StringName, host: Vector2i, top: int) -> int:
    var left := side == &"left"
    var edge := 0 if left else host.x
    var middle := host.x >> 1
    var grew := true
    while grew:
        grew = false
        for section: String in _opened:
            var rect: Rect2i = _opened[section]
            if rect.position.y > top + EDGE_SLACK:
                continue
            if left and rect.position.x <= edge + EDGE_SLACK and rect.end.x > edge and rect.end.x <= middle:
                edge = rect.end.x
                grew = true
            elif not left and rect.end.x >= edge - EDGE_SLACK and rect.position.x < edge and rect.position.x >= middle:
                edge = rect.position.x
                grew = true
    return edge


## The row below the bar in the units *win* measures in.
func _top(win: Window) -> int:
    if not _top_inset.is_valid():
        return 0
    return int(ceil(int(_top_inset.call()) * SaUI.window_scale(win)))
