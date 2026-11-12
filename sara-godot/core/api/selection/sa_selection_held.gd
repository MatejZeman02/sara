## What a selection held at one moment, the two sides of the step a
## [method change] records and what a drop brings back. The dictionaries are
## copies, because a shape in replace mode starts from fresh ones and the
## history must not hold the live ones. The chunks are the same objects, as
## `Swap`'s are, which is safe because a change copies a chunk before it
## writes into one (see [method SaSelection.own_chunk]).
##
## What Reselect would bring back is held too, so an undone Deselect leaves
## Reselect as it found it rather than with the selection the undo put back.
## So is whether it was the one Select All made, which an undo or a redo of a
## later change puts back with it. So is the feather, the amount and the
## hard mask under it, so an undo restores the two together. So is the shape
## that made it, so a press beside an undone ellipse still starts a new one.
class_name SaSelectionHeld
extends RefCounted

var chunks: Dictionary
var boxes: Dictionary[Vector2i, Rect2i]
var bounds: Rect2i
var active: bool
var kept_chunks: Dictionary
var kept_boxes: Dictionary[Vector2i, Rect2i]
var kept_bounds: Rect2i
var whole: bool
var feather: SaSelectionFeather
var shape: SaSelectionShape


func _init(
    held_chunks: Dictionary,
    held_boxes: Dictionary[Vector2i, Rect2i],
    held_bounds: Rect2i,
    was_active: bool,
    held_kept_chunks: Dictionary = {},
    held_kept_boxes: Dictionary[Vector2i, Rect2i] = {},
    held_kept_bounds: Rect2i = Rect2i(),
    was_whole: bool = false,
    held_feather: SaSelectionFeather = null,
    held_shape: SaSelectionShape = null
) -> void:
    chunks = held_chunks.duplicate()
    boxes = held_boxes.duplicate()
    bounds = held_bounds
    active = was_active
    kept_chunks = held_kept_chunks.duplicate()
    kept_boxes = held_kept_boxes.duplicate()
    kept_bounds = held_kept_bounds
    whole = was_whole
    feather = held_feather
    shape = held_shape


## Whether there was anything to bring back.
func holds_something() -> bool:
    return active and not chunks.is_empty()


## Whether *other* is a different selection, by the chunk objects and not
## by their pixels: a change writes into a copy, so a chunk it touched is a
## new object, and one it left alone is the same one.
func differs_from(other: SaSelectionHeld) -> bool:
    if active != other.active or bounds != other.bounds or whole != other.whole or feather != other.feather:
        return true
    return not _same_chunks(chunks, other.chunks) or not _same_chunks(kept_chunks, other.kept_chunks)


## The bytes this side holds that *other* does not, which is what a step
## whose undo is this side keeps alive by itself while *other* is the live
## selection: the chunks an add copied, or the ones a replace let go of.
func bytes_not_in(other: SaSelectionHeld) -> int:
    var live := {}
    for chunk: SaChunk in other.chunks.values() + other.kept_chunks.values():
        live[chunk] = true
    var total := 0
    if other.feather != null and other.feather.hard != null:
        for chunk: SaChunk in other.feather.hard.chunks.values():
            live[chunk] = true
    var mine: Array = chunks.values() + kept_chunks.values()
    if feather != null and feather.hard != null:
        mine += feather.hard.chunks.values()
    for chunk: SaChunk in mine:
        if not live.has(chunk):
            live[chunk] = true
            total += chunk.byte_size()
    return total


static func _same_chunks(one: Dictionary, two: Dictionary) -> bool:
    if one.size() != two.size():
        return false
    for grid_pos: Vector2i in one:
        if two.get(grid_pos, null) != one[grid_pos]:
            return false
    return true
