## One stroke's own copies of the stored tip and masking block, which every dab
## writes its size, hardness and spacing onto.
##
## Copies because those writes are the stroke's state and the tip is a setting a
## preset saves. Written onto the stored tip, one stroke with Blender left the
## brush editor reading Unsaved changes over a brush nobody had changed. The
## brush makes a fresh one at every press and at the lift, so an edit to the tip
## between two strokes reaches the next one.
##
## The class holds no settings. The brush hands it what is stored when a dab
## asks, and it owns the two copies and nothing else, which is why it left
## `state_brush.gd` when a merge took that file past a thousand lines.
class_name SaStrokeTip
extends RefCounted

var _tip: Resource = null
var _masking: Resource = null


## The stroke's copy of *stored*, the one a dab may write on, made at the first
## dab that asks.
func tip(stored: Resource) -> Resource:
    if _tip == null:
        _tip = stored.duplicate()
    return _tip


## The stroke's copy of the masking block, deep so that the second tip the
## block shapes per dab is the copy's and not the preset's. Null while *stored*
## is.
func masking(stored: Resource) -> Resource:
    if _masking == null and stored != null:
        _masking = stored.duplicate(true)
    return _masking
