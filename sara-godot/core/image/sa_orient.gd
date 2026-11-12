## Image > Flip and Rotate, and Layer > Flip: the picture mirrored or turned by
## a quarter, exactly, as one undoable step.
##
## **A flip is a resample by a map that lands on texel centres.** `SaResample`
## walks the destination grid and reads every texel back through the inverse of
## a map, and a flip or a quarter turn is such a map whose inverse sends the
## centre of a destination texel to the centre of a source one. Read with the
## filter on nearest, every texel is one `image_load` of the texel it came from,
## so the copy is exact and two flips are the picture byte for byte. Nothing
## here is a kernel, and nothing walks a grid of its own: this file is the maps
## and the history step of the one flip `SaResample` cannot record, a single
## layer's.
##
## **The image commands are `SaResample.resample_by`.** Every paint layer, the
## mask of every group and of every attached filter go through the same map,
## the generated layers need nothing because they evaluate over the canvas that
## is, and the selection is dropped as a resize drops it. A quarter turn swaps
## the canvas's sides, and undo puts the size and the chunks back together.
##
## **The layer flip mirrors about the middle of the canvas**, the same map the
## image flip uses, so flipping every layer one at a time and flipping the image
## agree. A group flips the layers inside it, which is what a painter who
## grouped a figure's layers means. The selection stays, since a layer flip
## changed no size and no other layer.
class_name SaOrient
extends RefCounted

## What the undo list calls each, which is the menu row with what it acted on,
## because the Image menu and the Layer menu both say "Flip Horizontally" and
## the history has to tell the two apart.
const FLIP_IMAGE_HORIZONTALLY := "Flip Image Horizontally"
const FLIP_IMAGE_VERTICALLY := "Flip Image Vertically"
const FLIP_LAYER_HORIZONTALLY := "Flip Layer Horizontally"
const FLIP_LAYER_VERTICALLY := "Flip Layer Vertically"
## By clockwise quarters, one to three.
const ROTATE_NAMES: Array[String] = ["", "Rotate Image 90° Clockwise", "Rotate Image 180°", "Rotate Image 90° Anticlockwise"]

var _document: SaDocument
## The walk, on nearest and never anything else, which is what makes it exact.
var _walk: SaResample


func _init(document: SaDocument) -> void:
    _document = document
    _walk = SaResample.new(document)
    _walk.filter = SaResampleKernel.Filter.NEAREST


## The map a flip of a canvas of *size* is, in document pixels: across the
## vertical middle for *horizontal*, across the horizontal one otherwise.
static func flip_map(size: Vector2i, horizontal: bool) -> Transform2D:
    if horizontal:
        return Transform2D(Vector2(-1.0, 0.0), Vector2(0.0, 1.0), Vector2(size.x, 0.0))
    return Transform2D(Vector2(1.0, 0.0), Vector2(0.0, -1.0), Vector2(0.0, size.y))


## The map *quarters* clockwise quarter turns of a canvas of *size* are, landing
## in the turned canvas with its top left at the origin. Clockwise on screen,
## where y runs down: the top edge becomes the right one, so the old top left
## lands at the new top right.
static func turn_map(size: Vector2i, quarters: int) -> Transform2D:
    match posmod(quarters, 4):
        1:
            return Transform2D(Vector2(0.0, 1.0), Vector2(-1.0, 0.0), Vector2(size.y, 0.0))
        2:
            return Transform2D(Vector2(-1.0, 0.0), Vector2(0.0, -1.0), Vector2(size))
        3:
            return Transform2D(Vector2(0.0, -1.0), Vector2(1.0, 0.0), Vector2(0.0, size.x))
    return Transform2D.IDENTITY


## Mirrors the whole picture. True when it happened.
##
## The view is handed the whole canvas as the part the new document is made of,
## so it keeps its zoom and its place: the canvas did not move, only what is on
## it.
func flip_image(horizontal: bool) -> bool:
    if _document == null:
        return false
    var size := _document.canvas_size
    var action := FLIP_IMAGE_HORIZONTALLY if horizontal else FLIP_IMAGE_VERTICALLY
    return _walk.resample_by(size, flip_map(size, horizontal), action, Rect2i(Vector2i.ZERO, size))


## Turns the whole picture by *quarters* clockwise quarter turns, a negative
## number anticlockwise. True when it happened, and false for a whole turn,
## which would be a step that changes nothing.
##
## A half turn keeps the view where it was, as a flip does. A quarter turn
## swaps the sides, so the view fits the document afresh the way Image Size's
## does, since no point of the old canvas stands where it stood.
func rotate_image(quarters: int) -> bool:
    if _document == null:
        return false
    var turns := posmod(quarters, 4)
    if turns == 0:
        return false
    var size := _document.canvas_size
    var turned := Vector2i(size.y, size.x) if turns != 2 else size
    var source := Rect2i(Vector2i.ZERO, size) if turns == 2 else Rect2i()
    return _walk.resample_by(turned, turn_map(size, turns), ROTATE_NAMES[turns], source)


## Mirrors *layer* about the middle of the canvas, or every layer inside it for
## a group. True when it happened.
##
## A layer that will not take paint says why in the corner the way a refused
## stroke does, and so does one that holds nothing, because a menu row that
## answers with silence reads as a broken row.
func flip_layer(layer: SaLayer, horizontal: bool) -> bool:
    if _document == null or layer == null:
        return false
    if not _flippable(layer):
        return false
    var owners := _owners(layer)
    var stores := owners.filter(func(owner: SaLayer) -> bool: return not owner.is_group)
    var map := flip_map(_document.canvas_size, horizontal)
    var size := _document.canvas_size

    # Keyed by Variant, for the reason `SaResample` gives.
    var before: Dictionary[Variant, Dictionary] = {}
    var held := 0
    for store: SaLayer in stores:
        before[store] = store.chunks.duplicate()
        held += store.chunks.size()
    var masks_before: Dictionary[Variant, Dictionary] = {}
    for mask: SaMask in _masks_in(owners):
        masks_before[mask] = mask.chunks.duplicate()
        held += mask.chunks.size()
    if held == 0:
        EventBus.paint_refused.emit(tr("This layer holds no paint yet, so there was nothing to flip."))
        return false

    var after: Dictionary[Variant, Dictionary] = {}
    for store: SaLayer in before:
        after[store] = _walk.mapped_chunks(store.chunks, store.schema, store.resolution_scale, map, size)
    var masks_after: Dictionary[Variant, Dictionary] = {}
    for mask: SaMask in masks_before:
        masks_after[mask] = _walk.mapped_chunks(mask.chunks, SaMask.schema(), 1.0, map, size, SaCrop.at_rest(mask))

    var exchange := SaCanvasExchange.new(_document, size, before, masks_before, _put_back)
    _put(after, masks_after)
    exchange.commit(FLIP_LAYER_HORIZONTALLY if horizontal else FLIP_LAYER_VERTICALLY)
    return true


## Whether *layer* can be flipped, saying why in the corner when it cannot. A
## group asks it of every layer inside it, because flipping all but the locked
## one would tear the figure the group holds. Not of itself or a group inside
## it, which reports locked whatever was set since there is nothing in one to
## paint on.
func _flippable(layer: SaLayer) -> bool:
    if not layer.is_group:
        return not SaContext.refuse_paint(layer, tr("flip"))
    for owner: SaLayer in _owners(layer):
        if owner.is_locked and not owner.is_group:
            EventBus.paint_refused.emit(
                tr("'%s' is locked, so nothing in the group was flipped. Unlock it in the Layers docker.") % owner.name
            )
            return false
    return true


## *layer*, and for a group every layer inside it at any depth that stores
## texels and every group inside it. Membership is the `group` reference that
## `SaLayerStack.is_inside` walks, since the layers are one flat list. A
## generated layer evaluates over the canvas and has nothing to mirror.
func _owners(layer: SaLayer) -> Array[SaLayer]:
    var found: Array[SaLayer] = [layer]
    if not layer.is_group:
        return found
    for child: Node in _document.get_children():
        var inside := child as SaLayer
        if inside == null or inside == layer or inside == _document.stroke_layer or inside.is_generated():
            continue
        if SaLayerStack.is_inside(inside, layer):
            found.append(inside)
    return found


## The masks holding chunks of their own that go with *owners*: the one of
## every filter record attached to one of them, and a group's own. A layer's
## own mask is a field of its chunks and goes with them, as `SaCrop.own_masks`
## says.
static func _masks_in(owners: Array[SaLayer]) -> Array[SaMask]:
    var found: Array[SaMask] = []
    for owner: SaLayer in owners:
        for record: SaAttachedFilter in owner.filters:
            if record.mask != null:
                found.append(record.mask)
        if owner.mask != null and owner.mask.is_own():
            found.append(owner.mask)
    return found


## Puts *chunks* on their layers and *masks* in their stores, and redraws what
## moved: every grid position a layer held before or holds now, because the
## half of the canvas the paint left would otherwise keep showing it.
func _put(chunks: Dictionary[Variant, Dictionary], masks: Dictionary[Variant, Dictionary]) -> void:
    var moved: Dictionary[Vector2i, bool] = {}
    for layer: SaLayer in chunks:
        for grid_pos: Vector2i in layer.chunks:
            moved[grid_pos] = true
        # Emptied and refilled by key, for the reason `SaResample._apply` gives.
        var wanted := SaTyped.chunks(chunks[layer])
        layer.chunks.clear()
        for grid_pos: Vector2i in wanted:
            layer.chunks[grid_pos] = wanted[grid_pos]
            moved[grid_pos] = true
        layer.mark_all_unresolved()
    for mask: SaMask in masks:
        for grid_pos: Vector2i in mask.chunks:
            moved[grid_pos] = true
        for grid_pos: Vector2i in masks[mask]:
            moved[grid_pos] = true
    SaCrop.put_masks(_document, masks, false)
    _document.modified = true
    # The caches first, because a layer under or over the active one is folded
    # into one and the fold reads it only when it is rebuilt.
    _document.update_caches()
    _document.invalidate_chunks(moved.keys())
    _document.document_changed.emit()


## What `SaCanvasExchange` puts back at an undo or a redo, which is only the
## chunks, because a layer flip keeps the size.
func _put_back(
    _size: Vector2i,
    chunks: Dictionary[Variant, Dictionary],
    masks: Dictionary[Variant, Dictionary],
    _source: Rect2i,
    _projection: SaProjection
) -> void:
    _put(chunks, masks)
