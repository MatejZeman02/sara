## An attached filter's mask filled from a colour range, as one step: what the
## Colour Range dialog does when it was opened from a filter's row in the
## Layers docker.
##
## A class of its own because it owns the read of the picture with the filter
## switched off, which no other part of the docker's row of actions does. It was
## a part of `SaLayerActions` until that file reached its line limit.
##
## Sample merged reads the picture as seen, and otherwise the layer the filter
## hangs under, which is its colour before any of its filters. A filter on a
## group or on the document's root has no paint of its own to read, so it reads
## the picture.
##
## **The picture is read with this filter switched off.** The output already
## carries the filter, so a range picked off it would measure the sharpened reds
## or the inverted blues rather than the ones the painter pointed at, and the
## mask would chase its own effect. One composite without the record, the read,
## and one with it again, which is two composites for a click.
class_name SaFilterMaskRange
extends RefCounted

var _document: SaDocument
var _easel: SaEasel


## *easel* is the one the docker's canvas draws, null in a suite with none,
## which then reads the layer alone.
func _init(document: SaDocument, easel: SaEasel) -> void:
    _document = document
    _easel = easel


## Fills *record*'s mask with the range of *color* at *fuzziness*, reading the
## picture as seen when *sample_merged*. True when the mask was written.
func fill(record: SaAttachedFilter, color: Color, fuzziness: float, sample_merged: bool) -> bool:
    if _document == null or record == null:
        return false
    var node := node_holding(_document, record)
    var paint := node != null and not node.is_group and not node.is_generated()
    var engine := SaColorRange.new(_document)
    var coverage: Dictionary
    if (sample_merged or not paint) and _easel != null:
        var was_on := record.enabled
        _switch_for_read(record, false)
        coverage = engine.coverage(color, fuzziness, _easel.output)
        _switch_for_read(record, was_on)
    else:
        coverage = engine.coverage(color, fuzziness, null, node if paint else null)
    return SaMaskOps.new(_document).from_color_range(record, coverage)


## Switches *record* to *on* and composites the picture again, for the read
## above and for putting it back.
func _switch_for_read(record: SaAttachedFilter, on: bool) -> void:
    record.enabled = on
    record.touch()
    _document.invalidate_all_allocated_chunks()
    _document.update_caches()
    _easel.request_full_composite()
    # The whole picture is read, not the window's part of it.
    _easel.flush()


## The layer of *document* that *record* is attached under, or null for one on
## the document's root. Public, because the docker's Delete Filter and its two
## conversions ask the same of the picked filter.
static func node_holding(document: SaDocument, record: SaAttachedFilter) -> SaLayer:
    for child in document.get_children():
        var layer := child as SaLayer
        if layer != null and layer.filters.has(record):
            return layer
    return null
