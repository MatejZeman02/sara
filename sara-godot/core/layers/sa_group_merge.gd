## A group merged down into the paint layer under it, which Krita's Merge with
## Layer Below does too: the group drawn into that
## layer's paint the way the canvas draws it, its members with their own
## modes and opacities and then the group's filters, mask, mode and opacity,
## through the walk `SaTreeRender` makes for Flatten, one chunk at a time.
##
## `SaLayerOps` owns the step around it, the snapshot, the take-out of the
## group with everything inside it and the undo, as it does for a layer's
## merge, whose pixels `SaMergeFold` writes. Whether a group may go down is
## `SaLayerRefusals`: onto a paint layer it may, and onto a group or a layer
## that stores nothing it may not.
##
## What lies under the lower layer is not part of the merge, as with any Merge
## Down: a member that multiplies or an adjustment layer inside a pass-through
## group acts on the lower layer's paint alone from then on.
class_name SaGroupMerge
extends RefCounted

var _document: SaDocument


func _init(document: SaDocument) -> void:
    _document = document


## The layer *layer* merges down into, or null when there is none. For a group
## it is the sibling under it, because the layer before a group in the
## document's order is the top member of a group beside it when there is one,
## and a merge into that would cross from one level of the tree to another.
## For any other layer it is the one before it in the document's order, which
## is what Merge Down has always read.
static func lower_of(document: SaDocument, layer: SaLayer) -> SaLayer:
    if document == null or layer == null or layer.get_parent() != document:
        return null
    if layer.is_group:
        var siblings := SaLayerStack.members(document, SaLayerStack.parent_of(layer))
        var at := siblings.find(layer)
        return siblings[at - 1] if at > 0 else null
    var below: SaLayer = null
    for child in document.get_children():
        if child == layer:
            return below
        if child is SaLayer:
            below = child as SaLayer
    return null


## Every layer a merge of *uppers* takes out of the document, each upper with
## everything inside it when it is a group, in the document's order.
static func taken(document: SaDocument, uppers: Array[SaLayer]) -> Array[SaLayer]:
    var groups := SaLayerGroups.new(document)
    var found: Array[SaLayer] = []
    for upper in uppers:
        for layer in groups.subtree(upper):
            if not found.has(layer):
                found.append(layer)
    found.sort_custom(func(a: SaLayer, b: SaLayer) -> bool: return a.get_index() < b.get_index())
    return found


## Draws *group* into *lower*'s paint at every chunk it shows on, a filter's
## halo included, snapshotting each of *lower*'s chunks into *state* the first
## time it is touched, so one snapshot serves the whole step. *height* adds the
## members' height to the lower layer's, each weighted by the opacity it shows
## at. A hidden group draws nothing and still goes, as a hidden layer does.
## Rendered before anything leaves the document, because the walk reads the
## tree as it stands.
func composite_into(lower: SaLayer, group: SaLayer, state: Dictionary[Vector2i, Variant], height: SaHeightOps) -> void:
    var compositor := _document.compositor
    if not group.visible or compositor == null:
        return
    var members := SaLayerGroups.new(_document).subtree(group)
    for member in members:
        member.resolve_pending()
    var render := SaTreeRender.new(_document)
    var spec := SaFieldSpec.find(lower.schema, SaFieldSpec.HEIGHT)
    var clipped := SaLayerStack.clip_base(_document, group) == lower
    # Clipped to *lower*, the group shows only where *lower* holds paint.
    var positions: Array = lower.chunks.keys() if clipped else _reach(render, members).keys()
    for grid_pos: Vector2i in positions:
        if clipped and lower.chunks[grid_pos] == null:
            continue
        if not state.has(grid_pos):
            state[grid_pos] = lower.duplicate_chunk(grid_pos)
        var destination := lower.get_or_create_chunk(grid_pos)
        for member in members:
            var shown := _shown_at(member, group)
            if shown > 0.0 and not member.is_group:
                height.add(destination, spec, member, grid_pos, shown)
        if clipped:
            _clip_into(compositor, render, destination.albedo(), group, grid_pos)
        else:
            render.render_node(destination.albedo(), group, grid_pos)
        lower.mark_unresolved(grid_pos)


## *group*, clipped to the layer whose paint *albedo* is, laid on that paint
## the way the two showed as one clipping group: the group by its mode and
## opacity on the paint's own colour, the result kept under the paint's alpha,
## which is `SaMergeFold`'s clipped merge with a group for the upper layer.
func _clip_into(compositor: SaCompositor, render: SaTreeRender, albedo: SaTexture, group: SaLayer, grid_pos: Vector2i) -> void:
    var whole := SaDocument.WHOLE_CHUNK
    var space := _document.color_space
    var blend_white := _document.blend_reference_white
    var lay_base := func(into: SaTexture) -> void:
        compositor.composite_chunk(into, albedo, SaLayer.BLEND_MODE.NORMAL, 1.0, Vector2.ZERO, space, blend_white, whole)
    var lay_clipped := func(plate: SaTexture) -> void: render.render_node(plate, group, grid_pos)
    var plated := compositor.clip_group.plate(compositor, albedo.format, whole, lay_base, lay_clipped)
    compositor.clear_scratch_batch([[albedo, whole]])
    compositor.composite_chunk(albedo, plated, SaLayer.BLEND_MODE.NORMAL, 1.0, Vector2.ZERO, space, blend_white, whole)


## Every grid position the group's members draw on, and the rings their
## filters and the groups' filters carry paint into, the way Flatten reaches:
## each layer's own ring first, then each group's over everything so far.
func _reach(render: SaTreeRender, members: Array[SaLayer]) -> Dictionary[Vector2i, bool]:
    var reach: Dictionary[Vector2i, bool] = {}
    for member in members:
        if member.is_group or not SaLayerStack.contributes(_document, member):
            continue
        var covered := SaLayerStack.drawn_by(_document, member)
        for grid_pos: Vector2i in SaLiveTransform.paint_of(member).chunks:
            covered[grid_pos] = true
        reach.merge(render.reach(member, covered))
    for member in members:
        if member.is_group and SaLayerStack.contributes(_document, member):
            reach.merge(render.reach(member, reach.duplicate()))
    return reach


## The opacity *member* shows at inside *group*: its own times every group's
## from its parent up to *group*, or nought when it or one of them is hidden.
static func _shown_at(member: SaLayer, group: SaLayer) -> float:
    var opacity := 1.0
    var at := member
    var guard := 0
    while at != null and guard < 64:
        if not at.visible:
            return 0.0
        opacity *= at.opacity
        if at == group:
            return opacity
        at = SaLayerStack.parent_of(at)
        guard += 1
    return 0.0
