## One attached filter's row in the layers docker, under the row of the node it
## hangs on.
##
## Reorderable rows below the layer's, inside the Layers docker. A row of its
## own class, made of the same frame a layer
## row is made of and not a kind of layer row: it carries no layer, so
## `SaLayerList.layer_at` answers null for it and every gesture written for a
## layer passes it by. What it carries is the record and the node the record
## hangs on, null being the document's root.
##
## The eye is the record's enabled flag, the way Krita draws a filter mask. The
## picture, the note mark and the three locks are a layer's and are hidden, and
## the picture's slot draws the record's mask once it has one.
class_name SaFilterRowView
extends SaRowFrame

## How far past its node's own depth the row is indented, in steps.
const EXTRA_DEPTH: int = 1

## The mark before the title, so a filter reads as one at a glance and not as
## a layer with no picture.
const FILTER_MARK: String = "ƒ "

## The node the record hangs on, set by the constructor and never again: a
## rebuild makes new rows.
var node: SaLayer = null

## What the filter calls itself, or its key when no installed module answers
## to it.
var filter_title: String = ""


func _init(
    attached: SaAttachedFilter, on_node: SaLayer, title_text: String, node_depth: int, idx: int, pick: SaLayerPick = null
) -> void:
    super(FILTER_MARK + title_text, node_depth + EXTRA_DEPTH, false, idx, null, attached, pick)
    node = on_node
    filter_title = title_text
    name = "FilterRow_%d" % idx
    thumb.visible = false
    comment_btn.visible = false
    for which: StringName in toggles:
        (toggles[which] as Button).visible = false
    if on_node == null:
        tooltip_text = TranslationServer.translate("Applies to the whole document.")


## Whether the node the row was built under is still there. The root always is.
func node_alive() -> bool:
    return node == null or is_instance_valid(node)


## Puts the record's state back on the row, which is the eye, the dimming and
## the mask's picture.
func refresh(document: SaDocument) -> void:
    if record == null:
        return
    show_eye(record.enabled)
    lbl.modulate.a = 1.0 if record.enabled else HIDDEN_BY_GROUP_ALPHA
    _sync_mask_thumb()
    if mask_thumb != null:
        mask_thumb.show_mask(_mask(), document, picked_picture(document) == &"mask")
        # The layer's wording names a picture beside it that a filter has not.
        mask_thumb.tooltip_text = TranslationServer.translate(
            (
                "Filter mask. Click to paint where the filter works, black hides it."
                if _mask().enabled
                else "Filter mask, switched off: the filter works everywhere until it is switched on again."
            )
        )


## What a plain press on a filter row aims the brush at, the filter's half of
## `SaLayerRowView.aim_brush`. The mask's picture makes the record's mask the
## document's `mask_target`, which is all painting it takes: the paint context
## paints whatever mask that names. A press anywhere else on the row keeps the
## record's own mask and gives the brush back to the paint from any other.
## Static for the parent's reason, and named apart from it because the two take
## a different owner.
static func aim_brush_at_filter(document: SaDocument, of: SaAttachedFilter, picture: StringName) -> void:
    if document == null or of == null:
        return
    var mask := of.mask
    var wanted: SaMask = document.mask_target
    if picture == &"mask" and mask != null:
        wanted = mask
    elif wanted != null and wanted != mask:
        wanted = null
    if wanted != document.mask_target:
        document.mask_target = wanted


## A filter row takes another filter above or below itself and nothing inside.
func drop_mode_at(global_point: Vector2) -> SaLayerList.Drop:
    var rect := get_global_rect()
    if rect.size.y <= 0.0:
        return SaLayerList.Drop.NONE
    var down := (global_point.y - rect.position.y) / rect.size.y
    return SaLayerList.Drop.ABOVE if down < 0.5 else SaLayerList.Drop.BELOW


## The frame's report with the filter's own half on top, so a capture that walks
## the rows by number finds every key it reads on every row.
func report() -> Dictionary:
    var out := super()
    out["kind"] = "filter"
    out["filter"] = String(record.key) if record != null else ""
    out["title"] = filter_title
    out["enabled"] = record.enabled if record != null else false
    # The record's own answer goes over the frame's, which read the picture off
    # the node this row hangs on and not off a layer it carries.
    out["picked"] = String(picked_picture(_document_of(node) if node_alive() and node != null else null))
    out["node"] = str(node.name) if node != null and is_instance_valid(node) else ""
    return out
