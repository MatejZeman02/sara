## The edge of a flat canvas as a feather's blur reads it: the selection
## carried on past it as it stands at the edge.
##
## A blur that read past the edge what the selection holds there, which is
## nothing unless its outline runs past the canvas, would fade a selection that
## meets the edge out against it over a feather's width, and a fill through it
## would leave soft columns at the edge. Here the texels past the edge are the
## edge's own, the way a clamped read gives them, so coverage at the edge is
## what it is a feather inside, and a selection that stops short of the edge,
## whose edge texels hold nothing, still fades.
##
## The kernel already clamps a read to the texture bound beside the chunk, so
## the neighbour past the edge is bound as a strip one texel thick holding the
## edge's own column or row, copied on the card (hard rule 1), and the chunk
## before that one is told where the canvas ends in it. An axis that
## wraps has no edge and is left to [SaSelectionFilters]' seam.
##
## SPDX-License-Identifier: GPL-3.0-or-later
class_name SaFeatherEdge
extends RefCounted

## What the pass reads, by grid position.
var _source: Dictionary[Vector2i, SaChunk]
var _canvas: Vector2i
## 0 for a pass along the rows, 1 for one along the columns.
var _axis: int
## Whether the canvas ends along this axis rather than wrapping.
var _flat: bool
## The strips copied so far, by grid position and the side, -1 or 1, as x, y, z.
var _strips: Dictionary[Vector3i, SaTexture] = {}


func _init(source: Dictionary[Vector2i, SaChunk], canvas_size: Vector2i, axis: int, flat: bool) -> void:
    _source = source
    _canvas = canvas_size
    _axis = axis
    _flat = flat


## Whether the neighbour *by*, -1 or 1, of the chunk at *grid_pos* along this
## axis lies past the canvas's edge.
func is_past(grid_pos: Vector2i, by: int) -> bool:
    if not _flat:
        return false
    return (grid_pos[_axis] == 0 and by < 0) or (grid_pos[_axis] == _last() and by > 0)


## How far the chunk at *grid_pos* runs along this axis before the neighbour
## after it takes over: the canvas's edge for the chunk the edge falls in, so a
## read past it reaches the strip rather than texels past the canvas, and
## *otherwise* for every other chunk.
func length(grid_pos: Vector2i, otherwise: int) -> int:
    if not _flat or grid_pos[_axis] != _last():
        return otherwise
    return _canvas[_axis] - grid_pos[_axis] * SaChunk.SIZE


## How far the neighbour after the chunk at *grid_pos* runs on the canvas
## when the canvas's edge falls in it, which the kernel takes in the slot the
## other axis leaves free. Without it a blur window across the seam before the
## last chunk would reach past the edge into the zeros a selection leaves
## there, when that chunk is narrower than the radius, and lay a soft band a
## few texels in from the edge. Nought, which reads the whole neighbour, for
## every other.
func after_length(grid_pos: Vector2i) -> int:
    if not _flat or grid_pos[_axis] + 1 != _last():
        return 0
    return _canvas[_axis] - _last() * SaChunk.SIZE


## The stand-in for the neighbour past the edge on side *by* of the chunk at
## *grid_pos*: the chunk's edge column or row, one texel thick. Null when the
## pass holds no chunk there, which the walk binds as nothing selected.
func strip(grid_pos: Vector2i, by: int) -> SaTexture:
    var key := Vector3i(grid_pos.x, grid_pos.y, by)
    if _strips.has(key):
        return _strips[key]
    var chunk: SaChunk = _source.get(grid_pos, null)
    var field: SaTexture = chunk.field(SaSelection.FIELD) if chunk != null else null
    var out: SaTexture = null
    if field != null and field.rid.is_valid():
        var at := 0 if by < 0 else length(grid_pos, field.size[_axis]) - 1
        var size := field.size
        size[_axis] = 1
        out = SaTexture.new(size, field.format)
        var from := Vector3(at, 0, 0) if _axis == 0 else Vector3(0, at, 0)
        field.rd.texture_copy(field.rid, out.rid, from, Vector3.ZERO, Vector3(size.x, size.y, 1), 0, 0, 0, 0)
    _strips[key] = out
    return out


## The grid position along this axis of the chunk the canvas's far edge falls in.
func _last() -> int:
    return ceili(float(_canvas[_axis]) / SaChunk.SIZE) - 1
