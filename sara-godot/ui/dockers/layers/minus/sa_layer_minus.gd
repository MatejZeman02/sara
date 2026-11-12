## The minus under the Layers docker's list: what a press takes off and what its
## hover says. A mask the document paints, its `mask_target`, goes alone and
## its layer or filter stays, a picked filter goes and its layer stays, and the
## picked layers go otherwise.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The facade of the
## folder. An instance follows one document's mask target for the button's
## hover, because a press on a mask's picture moves the target after the pick
## has already synced the buttons.
class_name SaLayerMinus
extends RefCounted

const DELETE_LAYER_HINT := "Delete the layer"
const DELETE_FILTER_HINT := "Delete the filter, and keep its layer"
const DELETE_MASK_HINT := "Delete the mask, and keep its layer"

## The minus button whose hover this keeps.
var _button: Button = null
## The document whose mask target the hover follows, and the filter its list
## had picked at the last sync.
var _document: SaDocument = null
var _record: SaAttachedFilter = null


func _init(button: Button) -> void:
    _button = button


## Follows *document* with *record* the picked filter, null while a layer's row
## holds the pick, and puts the hover right.
func follow(document: SaDocument, record: SaAttachedFilter) -> void:
    if document != _document:
        if is_instance_valid(_document) and _document.mask_target_changed.is_connected(_on_target_changed):
            _document.mask_target_changed.disconnect(_on_target_changed)
        _document = document
        if document != null:
            document.mask_target_changed.connect(_on_target_changed)
    _record = record
    _on_target_changed(null)


## The hover for a press now, before `tr()`, which is the caller's.
static func hint(document: SaDocument, record: SaAttachedFilter) -> String:
    if owner_of_target(document) != null:
        return DELETE_MASK_HINT
    return DELETE_FILTER_HINT if record != null else DELETE_LAYER_HINT


## Runs the mask's own delete, `SaMaskOps.DELETE`, on whatever holds the
## document's mask target, as one Delete Mask step that clears the target.
## Answers whether a mask came off, and false with no mask picked.
static func take_mask(document: SaDocument) -> bool:
    var owner := owner_of_target(document)
    return owner != null and SaMaskOps.new(document).run(SaMaskOps.DELETE, owner)


## The layer, group or attached filter whose mask is the document's
## `mask_target`, or null when the brush paints pixels. Asked of every node and
## record, because a group's mask and a filter's have no layer to name.
static func owner_of_target(document: SaDocument) -> Object:
    if document == null or document.mask_target == null:
        return null
    var records: Array[SaAttachedFilter] = []
    records.append_array(document.root_filters)
    var nodes: Array[Node] = [document]
    while not nodes.is_empty():
        var node: Node = nodes.pop_back()
        var layer := node as SaLayer
        if layer != null:
            if layer.mask == document.mask_target:
                return layer
            records.append_array(layer.filters)
        nodes.append_array(node.get_children())
    for record in records:
        if record.mask == document.mask_target:
            return record
    return null


func _on_target_changed(_mask: SaMask) -> void:
    if is_instance_valid(_button):
        _button.tooltip_text = _button.tr(hint(_document if is_instance_valid(_document) else null, _record))
