## What Copy holds when several layers are picked, and what Paste puts down
## from it: every picked layer as a layer of its own, a group with its members,
## in the order and nesting they stood in.
##
## **A held copy is a layer in no document.** Each one is made by
## `SaLayerDuplicate.copy`, so it carries what Duplicate Layer carries: its
## name, opacity, blend mode, visibility, locks, mask, attached filters and a
## generated or effect layer's settings, its texels copied on the GPU and never
## read back (rule 1). A paste copies the held layers again, so the clipboard
## keeps its own and a second paste is the same set. The held nodes are freed
## by `clear` and when the clipboard goes, since a node outside the tree is
## nobody's to free otherwise.
##
## **A selection narrows the paint.** With one standing, each paint layer holds
## only what the selection reaches, the masked copy `SaClipboard.copy` makes
## for a single layer, its mask kept where that paint is. A group, a generated,
## adjustment, effect or scene layer is held whole, since it is more than its
## chunks.
##
## **Where Paste lands.** Above the active layer and inside its group, as a new
## layer lands, bottom first in the order they were copied, and the pasted set
## is picked with its top layer active. In place on a canvas of the size the
## copy came from, and centred on any other, `SaClipboard.offset_in`'s rule.
## Across documents the paint is converted into the target's colour space and
## a paste across depths is refused, as a single paste does. A layer that
## cannot travel to another document, `_refused`, is refused by its name and the
## rest still paste. One history step, `ACTION_NAME`, takes them all away.
class_name SaClipboardLayers
extends RefCounted

## The history step a paste of several layers records.
const ACTION_NAME := "Paste Layers"

## The history step a cut of several layers through a selection records.
const CUT_NAME := "Cut Layers"

## What the copied colours mean, so a paste elsewhere can convert them.
var space: SaColorSpace = null

## The rectangle the copy covers, in document pixels of the source: the
## selection's bounds when one stood, and otherwise the canvas.
var bounds: Rect2i = Rect2i()

## The held copies, bottom of the stack first, each a layer in no document.
var _held: Array[SaLayer] = []

## For each held copy, the index in `_held` of the group it stood in, or -1
## when its group was not copied with it.
var _parent: Array[int] = []

## For each held copy, the index in `_held` of the layer an effect layer
## reads, or -1 when it reads a layer that was not copied.
var _input: Array[int] = []

## For each held copy, the layer an effect layer reads when that layer was not
## copied, kept weakly, since a paste into the same document reads it again.
var _outside: Array[WeakRef] = []

## The document the copy was taken from, weakly, so a paste can tell its own
## document from another one. A copy outlives its document being closed.
var _from: WeakRef = null

## The canvas size of the document the copy was taken from.
var _from_size: Vector2i = Vector2i.ZERO


func is_empty() -> bool:
    return _held.is_empty()


## How many layers are held, groups and their members counted.
func size() -> int:
    return _held.size()


func clear() -> void:
    _free_held()
    _held.clear()
    _parent.clear()
    _input.clear()
    _outside.clear()
    space = null
    bounds = Rect2i()
    _from = null
    _from_size = Vector2i.ZERO


func _notification(what: int) -> void:
    # The loop is written here rather than called, because a method of this
    # instance can no longer be called while it is being deleted.
    if what != NOTIFICATION_PREDELETE:
        return
    for layer in _held:
        if is_instance_valid(layer):
            layer.free()


## Frees the held copies, which are in no document and so nobody else's.
func _free_held() -> void:
    for layer in _held:
        if is_instance_valid(layer):
            layer.free()


## Holds every layer of *picked* in *document*, a picked group with all of its
## members, and answers how many layers are held.
func copy(document: SaDocument, picked: Array[SaLayer]) -> int:
    clear()
    if document == null:
        return 0
    var block := _block(document, picked)
    if block.is_empty():
        return 0
    space = document.color_space
    _from = weakref(document)
    _from_size = document.canvas_size
    var selection := document.selection
    var narrowed := selection.active and not selection.selects_everything()
    bounds = selection.bounds if narrowed else Rect2i(Vector2i.ZERO, document.canvas_size)
    var duplicate := SaLayerDuplicate.new(document)
    for original in block:
        var held := duplicate.copy(original, String(original.name))
        if narrowed and holds_paint(original):
            _narrow(document, original, held)
        _held.append(held)
    for original in block:
        _parent.append(block.find(SaLayerStack.parent_of(original)))
        var input := block.find(original.source) if original.source != null else -1
        _input.append(input)
        _outside.append(weakref(original.source) if original.source != null and input < 0 else null)
    return _held.size()


## Copies every layer of *picked* as `copy` does, then clears what the
## selection reaches on each paint layer as one `CUT_NAME` step, or with no
## selection takes the picked layers out as one step. Answers whether anything
## was cut.
func cut(document: SaDocument, picked: Array[SaLayer]) -> bool:
    if copy(document, picked) == 0:
        return false
    var selection := document.selection
    var roots := SaLayerStack.roots(document, picked)
    if not selection.active or selection.selects_everything():
        return SaLayerOps.new(document).remove_many(roots)
    var cut_any := [false]
    var work := func() -> void:
        for layer in _block(document, roots):
            if holds_paint(layer) and SaClipboard.new().cut(document, layer):
                cut_any[0] = true
    if document.history != null:
        document.history.as_one(CUT_NAME, work)
    else:
        work.call()
    return cut_any[0]


## Puts every held layer down above *document*'s active layer as one step,
## picked afterwards, and answers the pasted layers bottom first. Empty when
## nothing could be pasted.
func paste(document: SaDocument) -> Array[SaLayer]:
    var pasted: Array[SaLayer] = []
    if is_empty() or document == null:
        return pasted
    if space != null and space.depth != document.color_space.depth:
        SaProblems.refuse(
            "Clipboard",
            (
                TranslationServer.translate("The clipboard has %s pixels and this document is %s, so they cannot be pasted here.")
                % [SaColorSpace.depth_name(space.depth), SaColorSpace.depth_name(document.color_space.depth)]
            )
        )
        return pasted
    var same: bool = _from != null and _from.get_ref() == document
    var active := document.active_layer
    var at := active.get_index() + 1 if active != null else document.get_child_count()
    var outer := SaLayerStack.parent_of(active)
    var offset := offset_in(document)
    var ops := SaLayerOps.new(document)
    var duplicate := SaLayerDuplicate.new(document)
    var copies: Dictionary[int, SaLayer] = {}
    var made: Array = []
    for index in _held.size():
        if not same and _refused(index):
            continue
        var held := _held[index]
        var layer := duplicate.copy(held, _free_name(document, String(held.name)))
        _shift(document, layer, offset)
        var keeper := SaLayerOps.LayerKeeper.new(layer, at, active)
        copies[index] = layer
        pasted.append(layer)
        # Picked before it goes in, because going in makes it active and the
        # Layers docker lights the document's pick when it holds the active
        # layer, so every layer pasted so far stays lit.
        document.picked.pick(pasted)
        ops.put_back(keeper)
        made.push_front(keeper)
        at += 1
    if pasted.is_empty():
        return pasted
    for index: int in copies:
        _connect(document, index, copies, outer, same)
    if space != null and not space.matches(document.color_space):
        for layer in pasted:
            if holds_paint(layer):
                SaColorConversion.new(document).convert_layer(layer, space)
    document.set_active_layer(pasted[-1])
    document.picked.pick(pasted)
    document.invalidate_chunks(_reach(pasted))
    document.update_caches()
    ops.refresh()
    ops.commit_presence(ACTION_NAME, made)
    document.active_layer_changed.emit(pasted[-1])
    return pasted


## How far the held paint moves to land in *document*: not at all in a canvas
## the size of the one it was copied from, and otherwise its bounds' middle
## onto the canvas's middle, as `SaClipboard.offset_in` places one layer.
func offset_in(document: SaDocument) -> Vector2i:
    var canvas := Rect2i(Vector2i.ZERO, document.canvas_size)
    if canvas.size == _from_size and canvas.encloses(bounds):
        return Vector2i.ZERO
    return SaCrop.offset_for(bounds.size, canvas.size, Vector2i(1, 1)) - bounds.position


## Whether *layer* is a paint layer, whose chunks are its own paint, which a
## selection narrows and a conversion converts.
static func holds_paint(layer: SaLayer) -> bool:
    return not (layer.is_group or layer.is_generated() or layer.is_adjustment() or layer.is_effect() or layer.is_scene())


## Whether the held layer at *index* cannot go into another document, said in
## the corner by its name when it cannot. A scene layer's viewport and a
## simulation's record belong to the document that runs them, and an effect
## layer whose input was not copied has nothing to read there.
func _refused(index: int) -> bool:
    var held := _held[index]
    var named := String(held.name)
    if held.is_scene():
        SaProblems.refuse(
            "Clipboard",
            TranslationServer.translate("'%s' is a scene layer, which cannot be pasted into another document.") % named
        )
        return true
    if held.simulation != null:
        SaProblems.refuse(
            "Clipboard",
            TranslationServer.translate("'%s' is a simulated layer, which cannot be pasted into another document.") % named
        )
        return true
    if held.is_effect() and _outside[index] != null:
        SaProblems.refuse(
            "Clipboard",
            (
                TranslationServer.translate(
                    "'%s' is an effect layer whose input was not copied, so it cannot be pasted into another document."
                )
                % named
            )
        )
        return true
    return false


## Points the pasted copy at *index* at its group and an effect layer at its
## input: the copies of the ones it was copied with, *outer* for a layer whose
## group stayed behind, and the layer it read outside the copy when *same*.
func _connect(document: SaDocument, index: int, copies: Dictionary[int, SaLayer], outer: SaLayer, same: bool) -> void:
    var layer := copies[index]
    layer.group = copies.get(_parent[index], outer) if _parent[index] >= 0 else outer
    layer.source = null
    if _input[index] >= 0:
        layer.source = copies.get(_input[index], null)
    elif same and _outside[index] != null:
        var read: SaLayer = _outside[index].get_ref()
        layer.source = read if read != null and read.get_parent() == document else null


## Keeps on *held*, the copy of *original*, only what *document*'s selection
## reaches of its paint: the masked copy a single Copy makes, with the mask
## the layer had kept on the chunks that paint is on.
func _narrow(document: SaDocument, original: SaLayer, held: SaLayer) -> void:
    var one := SaClipboard.new()
    one.copy(document, original)
    for grid_pos: Vector2i in held.chunks.keys():
        var taken: SaChunk = one.chunks.get(grid_pos, null)
        if taken == null:
            held.set_chunk(grid_pos, null)
            continue
        var chunk: SaChunk = held.chunks[grid_pos]
        for field_id: StringName in chunk.fields.keys():
            if field_id != SaFieldSpec.MASK and not taken.fields.has(field_id):
                chunk.drop_field(field_id)
        for field_id: StringName in taken.fields:
            chunk.fields[field_id] = taken.fields[field_id]


## Moves *layer*'s chunks by *offset* document pixels, a whole number of
## chunks by moving the grid and any other re-tiled on the GPU by
## `SaCrop.shifted`. A group's own mask chunks stay where they were.
func _shift(document: SaDocument, layer: SaLayer, offset: Vector2i) -> void:
    if offset == Vector2i.ZERO or layer.chunks.is_empty():
        return
    var edge := SaLayer.CHUNK_SIZE
    var moved: Dictionary[Vector2i, SaChunk] = {}
    if offset.x % edge == 0 and offset.y % edge == 0:
        @warning_ignore("integer_division")
        var cells := offset / edge
        for grid_pos: Vector2i in layer.chunks:
            moved[grid_pos + cells] = layer.chunks[grid_pos]
    else:
        moved = SaCrop.new(document).shifted(layer.chunks, layer.schema, layer.resolution_scale, offset)
    layer.chunks.clear()
    for grid_pos: Vector2i in moved:
        layer.set_chunk(grid_pos, moved[grid_pos])


## Every grid position the pasted *layers* hold paint on.
static func _reach(layers: Array[SaLayer]) -> Array[Vector2i]:
    var found: Dictionary[Vector2i, bool] = {}
    for layer in layers:
        for grid_pos: Vector2i in layer.chunks:
            found[grid_pos] = true
    var out: Array[Vector2i] = []
    out.assign(found.keys())
    return out


## Every layer of *picked* in *document* and, for a picked group, everything
## inside it, bottom first, which is the order the copies go back in.
static func _block(document: SaDocument, picked: Array[SaLayer]) -> Array[SaLayer]:
    var roots := SaLayerStack.roots(document, picked)
    var block: Array[SaLayer] = []
    for child in document.get_children():
        var layer := child as SaLayer
        if layer == null:
            continue
        for root in roots:
            if layer == root or (root.is_group and SaLayerStack.is_inside(layer, root)):
                block.append(layer)
                break
    return block


## *base* when no layer of *document* has it, else the first of `base 2`,
## `base 3` and on that none has, since two children of one node never share a
## name.
static func _free_name(document: SaDocument, base: String) -> String:
    var taken: Dictionary[String, bool] = {}
    for child in document.get_children():
        taken[str(child.name)] = true
    var candidate := base
    var number := 2
    while taken.has(candidate):
        candidate = "%s %d" % [base, number]
        number += 1
    return candidate
