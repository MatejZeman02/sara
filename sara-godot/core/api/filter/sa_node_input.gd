## What a record attached to a node filters, one chunk position at a time: the
## door a module asks for a node's input by, so the walk that composites it
## stays the skeleton's and a module names none of the compositor, the layer
## stack or the tree walk to have it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A paint layer's input is its own paint, handed as each chunk's albedo. A
## group and the document's root store no paint, so their input is composited
## for the occasion: a group's members over transparent, before the group's own
## records and its mask, and for the root every layer, before the root's
## records. Each position is composited into one scratch by
## `SaTreeRender.render_members`, the compositor's own steps in the canvas's
## order, a clipping base and what is clipped to it as one group among them.
##
## An adjustment layer holds no paint either, and its input is its backdrop,
## which the canvas draws over before the frame ends. So each position is drawn
## again up to the layer by `SaTreeRender.render_below`, the members of its
## isolated group below it or every layer below it at the top level.
##
## It is made for a press and never runs in a frame. The caller walks
## `positions` and reads `at` for each before it asks for the next, because the
## scratch is the same texture every time, so the picture never holds more than
## one chunk. Nothing is read back here: the texture stays in VRAM for the
## caller's pass, so nothing leaves the device, and every dispatch covers one
## chunk. The scratches die with the instance.
##
## A record's input is taken as the node's, before any record of the node, so a
## second record on the same node is handed the same input as the first.
class_name SaNodeInput
extends RefCounted

var _document: SaDocument = null
## The node whose input this is, null for the document's root.
var _node: SaLayer = null
var _compositor: SaCompositor = null
## The walk the input is drawn by, made on its first read.
var _tree: SaTreeRender = null
## The transparent chunk the input is drawn into.
var _drawn: SaTexture = null
var _format: int = 0


## The input of *node* in *document*, *node* null for the root, composited by
## the compositor the document was set up with.
func _init(document: SaDocument, node: SaLayer) -> void:
    _document = document
    _node = node
    _compositor = document.compositor if document != null else null
    if document != null:
        _format = SaFieldSpec.schema_for_space(document.color_space)[0].format


## The node *record* hangs on and whether it hangs there at all, as
## `[found, node]`, the node null for the document's root.
static func node_of(document: SaDocument, record: SaAttachedFilter) -> Array:
    if document == null or record == null:
        return [false, null]
    if document.root_filters.has(record):
        return [true, null]
    for child in document.get_children():
        var layer := child as SaLayer
        if layer != null and layer.filters.has(record):
            return [true, layer]
    return [false, null]


## Every chunk position the input covers, empty when there is nothing to read.
func positions() -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    if _document == null or _compositor == null:
        return out
    if _node != null and _node.is_adjustment():
        return _scope_positions(SaTreeRender.scope_of(_node), _node)
    if _node != null and not _node.is_group:
        out.assign(_node.chunks.keys())
        return out
    return _scope_positions(_node)


## The input at *grid_pos*, one chunk: the paint layer's own albedo, or the
## scratch the composite was drawn into, which the next call draws over. Null
## where there is nothing to read.
func at(grid_pos: Vector2i) -> SaTexture:
    if _document == null or _compositor == null:
        return null
    if _node != null and not _node.is_group and not _node.is_adjustment():
        var chunk: SaChunk = _node.chunks.get(grid_pos)
        return chunk.albedo() if chunk != null else null
    if _tree == null:
        _tree = SaTreeRender.new(_document)
    var scratch := _scratch()
    if _node != null and _node.is_adjustment():
        _tree.render_below(scratch, grid_pos, _node)
    else:
        _tree.render_members(scratch, _node, grid_pos)
    return scratch


## Every chunk position the scope *group* composites to: the chunks of every
## layer inside it, and at the root the whole canvas when a layer that stores
## nothing, a background, fills it. Inside a group such a layer reaches only
## where the others hold paint, as the fold has it. With *below*, only the
## layers under it count, the backdrop an adjustment layer reads.
func _scope_positions(group: SaLayer, below: SaLayer = null) -> Array[Vector2i]:
    var found: Dictionary[Vector2i, bool] = {}
    var generated := false
    for child in _document.get_children():
        var layer := child as SaLayer
        if layer == null or layer == group:
            continue
        if below != null and layer.get_index() >= below.get_index():
            continue
        if group != null and not SaLayerStack.is_inside(layer, group):
            continue
        generated = generated or layer.is_generated()
        for grid_pos: Vector2i in layer.chunks:
            found[grid_pos] = true
    if group == null and generated:
        for grid_pos in SaLayer.grid_positions(_document.canvas_size):
            found[grid_pos] = true
    var out: Array[Vector2i] = []
    out.assign(found.keys())
    return out


## The scratch, cleared to transparent. Made on the first read and dropped with
## the instance.
func _scratch() -> SaTexture:
    if _drawn == null:
        _drawn = SaTexture.new(SaDocument.WHOLE_CHUNK.size, _format)
    _compositor.clear_scratch_batch([[_drawn, SaDocument.WHOLE_CHUNK]])
    return _drawn
