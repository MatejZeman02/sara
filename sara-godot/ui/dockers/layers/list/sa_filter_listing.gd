## The order a node's attached filters are listed in under its row, and what a
## drop in that order means for the array they run in.
##
## The records run the first attached first, each reading what the one before
## it wrote, and the list shows them the way up of every list around it, the
## top of the stack first, so the record that runs last stands nearest the
## layer. Photoshop's smart filters and Krita's filter masks list the filter
## applied last at the top, and so does this.
##
## The array is in the order the records run, because the
## compositor, the document format and every script read it that way. Only the
## list turns it over, and this class is the one place that does, so a row and
## an index in the array are never mapped by two pieces of arithmetic.
class_name SaFilterListing
extends RefCounted


## *records* as the list shows them under the row of *node*, null for the
## document's root: the record that runs last first, which is the one nearest
## the row. A copy, so the array a step edits is never the one a loop over the
## rows walks.
##
## An adjustment layer's first record is the layer itself, its row and its
## settings, so it is left out and the rest are listed under the row the way a
## plain layer's are.
static func listed(records: Array[SaAttachedFilter], node: SaLayer = null) -> Array[SaAttachedFilter]:
    var shown: Array[SaAttachedFilter] = records.duplicate()
    shown.erase(SaBackdropLayer.own_filter(node))
    shown.reverse()
    return shown


## The index `SaFilterOps.reorder` takes to put *dragged* above *over* in the
## list when *above* is true and below it when false, both being records of
## *records*.
##
## Above in the list is later in the array, so a drop above a record means
## after it. `reorder` counts with the dragged record taken out, the way
## `Node.move_child` does, so a target further along the array is one nearer
## once the record has left.
static func index_for(records: Array[SaAttachedFilter], dragged: SaAttachedFilter, over: SaAttachedFilter, above: bool) -> int:
    var at := records.find(over)
    if records.find(dragged) < at:
        at -= 1
    return at + (1 if above else 0)
