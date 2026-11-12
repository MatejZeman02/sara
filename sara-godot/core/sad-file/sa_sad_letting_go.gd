## What an open lets go of in the document it opens into, before the new
## file's blobs are read: the layers and every chunk they hold, the undo
## history and the steps it keeps alive, the root's filters and their masks,
## and the caches made at the old document's size and depth.
##
## Read beside all of this, the whole new file and the old painting with its
## history were held at once, two paintings where one fits. Let go of first,
## an open over a painting peaks as one into a fresh Sara.
##
## The document stands empty from here until the file lands, so a load that
## fails leaves it empty with its error rather than holding the old painting,
## and the window draws an empty canvas while an open over frames reads.
##
## Its own file beside `sa_sad_file.gd`, which shares the step that empties the
## stack before a load rebuilds it and which is near its thousand lines.
class_name SaSadLettingGo
extends RefCounted


## Lets go of everything of *document* a load replaces. The history first,
## because a step holds layers and chunks the stack no longer does, then the
## stack, then the caches. The stack goes with the document's signals held,
## and its listeners hear once that the active layer and the stack changed.
static func before_reading(document: SaDocument) -> void:
    for layer in taken_out(document):
        layer.free()


## Lets go of what [method before_reading] does, but takes the layers out of
## *document* rather than freeing them, and answers them for the caller to
## free. An open over frames frees them a share a frame, where freeing the
## seasons file's 625 layers in one held a frame for about 50 ms.
static func taken_out(document: SaDocument) -> Array[SaLayer]:
    var out: Array[SaLayer] = []
    if document == null:
        return out
    if document.stroke_transaction != null:
        document.stroke_transaction.reset()
    if document.undo_redo != null:
        document.undo_redo.clear_history()
    if document.history != null:
        document.history.reset()
    # In one notice and not one per layer, for the reason `add_in_one_notice` gives.
    document.set_block_signals(true)
    document.active_layer = null
    document.mask_target = null
    # The last first, since a child taken from the end moves no sibling.
    var children := document.get_children()
    children.reverse()
    for child in children:
        if child is SaLayer:
            document.remove_child(child)
            out.append(child)
    document.set_block_signals(false)
    document.active_layer_changed.emit(null)
    document.mask_target_changed.emit(null)
    document.child_order_changed.emit()
    document.root_filters.clear()
    if document.fold != null:
        document.fold.release()
    if document.stroke_layer != null:
        document.stroke_layer.release_chunks()
    return out


## Answers *error*, and when it is a load's failure leaves *document* a new
## empty one at its size and space rather than the painting it held or the
## half it let go of, as a new document is made. ERR_SKIP is an open a later
## one dropped, whose document that later one fills, and a document that was
## never handed a compositor was never touched.
static func failed(document: SaDocument, error: Error) -> Error:
    if error == OK or error == ERR_SKIP or error == ERR_INVALID_PARAMETER:
        return error
    if not is_instance_valid(document) or document.compositor == null:
        return error
    document.reset_to_default(document.canvas_size, document.color_space)
    return error


## Adds *layers* to *document* in their order, with one notice to the
## document's listeners rather than one per layer.
##
## Every `add_child` and every `free` of a layer fires the document's
## `child_order_changed`, and the bucket fill's reference layer choice answers
## each by listing every layer again, twice. Over a painting of 308 layers
## that was 1.1 million objects made in one call and let go of only at the end
## of the frame, 3.4 GiB of memory on the open of a painting that holds 2.4
## GiB on the card, and as much again when the layers were freed. Held, the
## stack is listed once, and the layers docker hears `child_entered_tree` once,
## which is all it reads it for.
static func add_in_one_notice(document: SaDocument, layers: Array[SaLayer]) -> void:
    document.set_block_signals(true)
    for layer in layers:
        document.add_child(layer)
    document.set_block_signals(false)
    document.child_order_changed.emit()
    if not layers.is_empty():
        document.child_entered_tree.emit(layers[-1])
