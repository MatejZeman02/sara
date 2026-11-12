## One column of an `HSplitContainer` that can be dragged to nothing the way a
## web resizer can: under a floor it snaps shut, dragged back past the floor it
## snaps to the width it had, and the width it had is what the owner stores.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The column never expands and its minimum is nought**, which is what makes
## its width the split's offset itself: Godot puts a child that does not expand
## at its minimum and moves the divider by `split_offset` from there, so a first
## child is `offset` wide and a second child `-offset` wide. That is the one
## number this class keeps and snaps, and the owner turns it into an inset, a
## hidden box and a profile key through [signal moved].
##
## Its own class rather than a block of the scratchpad, because the editor has
## two such edges, the pad on the right and the presets on the left, and the
## two behave alike.
class_name SaSplitSnap
extends RefCounted

## The column moved: to *open_width* wide, or shut. Emitted for a drag and for
## [method fold], never for [method restore], so a state put back from the
## profile is not a change the profile is told about again.
signal moved(open_width: int, shut: bool)

var split: HSplitContainer = null

## True when the column is the split's first child, so its width is the offset
## rather than its negation.
var leading: bool = false

## The floor under a drag, in the split's units. A column dragged under it
## snaps shut rather than showing a sliver, and a shut column dragged back
## past it snaps to `open_width`.
var floor_width: int = 0

## The width the column snaps back to, and whether it is shut. Written here
## only.
var open_width: int = 0
var shut: bool = false

## True from the moment a shut column snaps back open until the grabber is
## let go, while the width the hand asks for is still under the one it
## snapped to. Without it the frame after the snap would follow the pointer
## back down to the floor and the snap would last one motion event.
var _holding: bool = false


func _init(on_split: HSplitContainer, is_leading: bool, at_floor: int, width: int) -> void:
    split = on_split
    leading = is_leading
    floor_width = at_floor
    open_width = maxi(floor_width, width)
    if split != null:
        split.dragged.connect(_on_dragged)
        split.drag_ended.connect(_on_drag_ended)


## Puts the column at *width*, or shut, without announcing: the profile's
## state on an open of the editor.
func restore(width: int, is_shut: bool) -> void:
    if width > 0:
        open_width = maxi(floor_width, width)
    shut = is_shut
    apply()


## Shuts the column or opens it to the width it had, and announces, for a
## fold header pressed by hand.
func fold(open: bool) -> void:
    shut = not open
    _holding = false
    apply()
    moved.emit(open_width, shut)


## The grabber dragged to *width*, through the same handler a hand's drag
## reaches, then let go. Nought is the column's edge.
func drag_to(width: int) -> void:
    if split == null:
        return
    split.split_offset = offset_for(maxi(0, width))
    _on_dragged(split.split_offset)
    _on_drag_ended()


## Writes the offset the state says.
func apply() -> void:
    if split != null:
        split.split_offset = 0 if shut else offset_for(open_width)


func width_of(offset: int) -> int:
    return offset if leading else -offset


func offset_for(width: int) -> int:
    return width if leading else -width


## Where the grabber is. An open column dragged under the floor shuts. A shut
## column stays shut while the hand is under the floor, by putting the offset
## back before the split sorts its children, and snaps to `open_width` the
## moment the hand crosses it. Above the floor the column follows the hand.
func _on_dragged(offset: int) -> void:
    var width := width_of(offset)
    if shut:
        if width >= floor_width:
            shut = false
            _holding = true
            apply()
            moved.emit(open_width, shut)
        else:
            split.split_offset = 0
        return
    if width < floor_width:
        shut = true
        _holding = false
        apply()
        moved.emit(open_width, shut)
        return
    if _holding and width < open_width:
        split.split_offset = offset_for(open_width)
        return
    _holding = false
    open_width = width
    moved.emit(open_width, shut)


func _on_drag_ended() -> void:
    _holding = false


## For a dump: the three numbers a shot of a column that is gone cannot show.
func report() -> Dictionary:
    return {
        "open_width": open_width,
        "shut": shut,
        "split_offset": split.split_offset if split != null else 0,
    }
