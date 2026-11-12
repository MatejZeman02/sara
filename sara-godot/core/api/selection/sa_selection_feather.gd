## A selection's feather as a live amount over its hard mask, never baked in.
##
## The selection the tools and the Select menu shape is the hard mask. What
## every reader binds, the brush, the fills, the filters and the clipboard, is
## that mask feathered by [member amount], made from the hard mask once
## whenever either changes and never from the last feathered result, so a
## feather is never laid twice. An add with Shift reshapes the hard mask and
## the feather is made again from it, so an island the new shape does not
## touch reads the values it had before, however many shapes are added, and
## Select > Feather at 20, then 5, then 0 is the edge 5 gives and then the hard
## edge again.
##
## A record, one per state: a change that alters the amount or the hard mask
## makes a new one, so an undo step holds the record of its side by reference
## and puts the hard mask and the amount back together.
## [method SaSelection.change] lays [member hard] down before its work and
## [method settled] makes the feathered mask after it, which is how every
## shape command acts on the hard mask without knowing of the feather.
##
## Something that writes the selection outside a change, a carry, a crop, the
## quick mask's brush, leaves chunks this record never made. The next change
## finds that out and takes what stands as the hard mask with no feather, so
## nothing is ever feathered on top of a feathered mask.
##
## The chunks are held, never written into: a filter writes fresh chunks and
## [method SaSelection.own_chunk] copies one before a change writes into it, so
## holding the objects is enough and nothing leaves VRAM (hard rule 1).
##
## SPDX-License-Identifier: GPL-3.0-or-later
class_name SaSelectionFeather
extends RefCounted

## The feather's radius in document pixels, 0 for the hard edge.
var amount: float
## The canvas and its wrapping the feather reads its edges against.
var canvas_size: Vector2i
var wrapping: SaProjection.Wrap
## The hard mask the feathered one was made from, null while none was made.
var hard: SaSelectionHeld
## The feathered chunks as they were laid, by grid position, and their bounds,
## so a change can tell that the selection still stands as made.
var _made_chunks: Dictionary
var _made_bounds: Rect2i


func _init(
    radius: float = 0.0,
    canvas: Vector2i = Vector2i.ZERO,
    wraps: SaProjection.Wrap = SaProjection.Wrap.NONE,
    hard_mask: SaSelectionHeld = null,
    made_chunks: Dictionary = {},
    made_bounds: Rect2i = Rect2i()
) -> void:
    amount = maxf(radius, 0.0)
    canvas_size = canvas
    wrapping = wraps
    hard = hard_mask
    _made_chunks = made_chunks.duplicate()
    _made_bounds = made_bounds


## Sets *selection*'s live feather to *radius* pixels, inside a
## [method SaSelection.change], which makes the feathered mask when it ends. A
## radius of 0 gives the hard edge back. The Select menu's Feather, a shape
## that replaces the selection and the door's `feather` run this, as
## `selection.feather.apply`, so no caller outside the package names this file.
## It reads the selection's own record rather than this one, which a bound
## call may hold from before.
func apply(selection: SaSelection, radius: float, canvas: Vector2i, wraps := SaProjection.Wrap.NONE) -> void:
    selection.feather = selection.feather.at(radius, canvas, wraps)


## The record a replaced selection takes, hard until a tool's Feather sets it.
## Only inside a change, a *depth* above 0, since a fill that borrows the
## selection outside one puts the painter's back after.
func replaced(depth: int) -> SaSelectionFeather:
    return SaSelectionFeather.new() if depth > 0 else self


## The record once the quick mask's brush paints the chunks in place, which
## a comparison of chunk objects cannot see: the mask as shown becomes the
## hard mask, with no feather left to lay over it again.
func painted() -> SaSelectionFeather:
    return SaSelectionFeather.new() if hard != null else self


## This record with *radius* as its amount: itself when that is the amount it
## has, and otherwise a record with no feathered mask made yet, which
## [method settled] makes.
func at(radius: float, canvas: Vector2i, wraps: SaProjection.Wrap) -> SaSelectionFeather:
    radius = maxf(radius, 0.0)
    if is_equal_approx(radius, amount) and (radius <= 0.0 or (canvas == canvas_size and wraps == wrapping)):
        return self
    return SaSelectionFeather.new(radius, canvas, wraps)


## The record a change works under, asked of *selection* as it stands before
## the work: this one while the selection is the feathered mask it made, so
## [member hard] is laid down, and otherwise one with nothing made. A selection
## something else wrote since keeps no feather, because what it holds now is
## what the painter sees. One that has gone keeps the amount for a Reselect.
func opened(selection: SaSelection) -> SaSelectionFeather:
    if hard == null or _stands(selection):
        return self
    if not selection.active:
        return SaSelectionFeather.new(amount, canvas_size, wrapping)
    return SaSelectionFeather.new()


## What stands under the feathered mask *standing*, the state of *selection*
## now: the hard mask while the selection is what this record made, and
## *standing* itself otherwise. What a Deselect keeps for Reselect, so the
## Reselect feathers it once more rather than twice.
func hard_under(selection: SaSelection, standing: SaSelectionHeld) -> SaSelectionHeld:
    return hard if hard != null and _stands(selection) else standing


## Lays the feathered mask over *selection*, which holds its hard mask as the
## change's work left it, and answers the record that made it. Itself, with the
## mask it made laid back, when neither the hard mask nor the amount moved, so
## a change that did nothing records nothing.
func settled(selection: SaSelection) -> SaSelectionFeather:
    if amount <= 0.0 or not selection.active or selection.chunks.is_empty():
        return self if hard == null else SaSelectionFeather.new(amount, canvas_size, wrapping)
    if hard != null and hard.bounds == selection.bounds and _same(selection.chunks, hard.chunks):
        selection.chunks = _made_chunks.duplicate()
        # After the chunks, which the bounds' setter rebuilds the boxes from.
        selection.bounds = _made_bounds
        return self
    # Chunks, boxes and bounds alone, so a record never holds the one before it.
    var hard_now := SaSelectionHeld.new(selection.chunks, selection._boxes, selection.bounds, true)
    SaSelectionFilters.feather(selection, amount, canvas_size, wrapping)
    return SaSelectionFeather.new(amount, canvas_size, wrapping, hard_now, selection.chunks, selection.bounds)


## Whether *selection* is, chunk for chunk, the feathered mask this record made.
func _stands(selection: SaSelection) -> bool:
    return selection.active and selection.bounds == _made_bounds and _same(selection.chunks, _made_chunks)


static func _same(one: Dictionary, two: Dictionary) -> bool:
    if one.size() != two.size():
        return false
    for grid_pos: Vector2i in one:
        if two.get(grid_pos, null) != one[grid_pos]:
            return false
    return true
