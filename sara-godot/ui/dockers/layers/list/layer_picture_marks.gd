## Which rows' pictures a change of the document marks as out of date, for the
## layers list, and which layer the stroke under way paints.
##
## A stroke, an undo or anything else that moves pixels may leave a row's
## picture old. Each thumbnail decides for itself when to redraw, so a mark
## costs a flag. A layer's own property moves no picture, a group's row being a
## folder, so the plain change after it marks nothing.
##
## A stroke's dabs move the layer it paints and no other picture of the list,
## so a frame of a stroke marks that row alone: 300 rows each marked after a
## dab cost a deep stack's docker 9 to 13 ms a frame. The commit's
## change, heard in the frame of its last dabs, marks that row again with the
## adjustment and effect rows, whose pictures are what they make of others.
## Anything else marks every row, as a mask's stroke does, since a dab into a
## mask notes no region.
class_name SaLayerPictureMarks
extends RefCounted

## The frame a layer's property changed in, whose plain change marks no picture.
var _quiet_frame: int = -1

## The layer a stroke under way paints, and the frame its dabs last moved in,
## which [method stroked] answers.
var _stroked: SaLayer = null
var _stroked_frame: int = -1


## What the document's `chunks_invalidated`, `document_changed` and
## `layer_changed` each ask of the pictures of *rows*, the list's, which show
## *doc*: *arg* is the first's positions, nothing for the second, and the
## third's layer.
func heard(arg: Variant, doc: SaDocument, rows: Array[SaRowFrame]) -> void:
    var frame := Engine.get_process_frames()
    if arg is SaLayer:
        _quiet_frame = frame
    elif arg is Array and doc != null and _in_stroke(doc):
        _stroked = doc.active_layer
        _stroked_frame = frame
        _mark(rows, doc, func(layer: SaLayer) -> bool: return layer == _stroked)
    elif arg == null and stroked() != null:
        _mark(rows, doc, _shows_the_stroke)
    elif arg != null or _quiet_frame != frame:
        _stroked = null
        _mark(rows, doc, func(_layer: SaLayer) -> bool: return true)


## The layer the stroke whose dabs moved in this frame paints, or null. The
## keeper reads it to draw that row alone at the stroke's commit.
func stroked() -> SaLayer:
    if _stroked_frame != Engine.get_process_frames() or not is_instance_valid(_stroked):
        return null
    return _stroked


## Wakes the pictures of *rows* that wait out of sight, so one scrolled or
## laid into view asks again whether it is shown.
static func wake_all(rows: Array[SaRowFrame]) -> void:
    for row in rows:
        if is_instance_valid(row):
            row.wake()


## Whether a stroke on a layer's colour is under way, its dabs noted.
static func _in_stroke(doc: SaDocument) -> bool:
    var held := doc.stroke_transaction
    return held != null and held.mask == null and not held.painted_regions.is_empty() and doc.active_layer != null


## Whether *layer*'s picture moves with the stroke's commit, null being a row
## that holds no layer.
func _shows_the_stroke(layer: SaLayer) -> bool:
    return layer != null and (layer == _stroked or layer.is_adjustment() or layer.is_effect())


## Marks the pictures of *rows* that *wanted* answers true for, handed each
## row's layer, or null for a row that holds none, an attached filter's.
static func _mark(rows: Array[SaRowFrame], doc: SaDocument, wanted: Callable) -> void:
    for row in rows:
        if is_instance_valid(row) and wanted.call(row.layer if row.has_layer() else null):
            row.mark_dirty(doc)
