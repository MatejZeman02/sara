## The shape of the layer tree, each change a history step: a wrap into a
## group, an ungroup, a group taken out whole, isolation, and a layer's block
## moved or placed among its siblings.
##
## A group is a layer with `is_group` set, and a layer belongs to it through
## `group`. The document stays a flat list, a group's members below it and its
## subtree moving as a block, and membership is read from the reference, never
## from adjacency. A group taken out lives on inside the step with every member.
##
## `SaLayerOps` makes one for each call and forwards to it, so every caller
## still asks the stack's one door. It builds an ops of its own over the same
## document for what every structural step shares, the keeper, taking a layer
## out and putting it back, and the refresh, rather than being handed the one
## that made it. A step binds a method of this instance, so the step keeps both
## alive.
class_name SaLayerGroups
extends RefCounted

var _document: SaDocument
var _ops: SaLayerOps


func _init(document: SaDocument) -> void:
    _document = document
    _ops = SaLayerOps.new(document)


## Wraps the active layer in a new pass-through group, placed right below it
## in the order so the layer is the group's only member. Answers the group.
func group_active() -> SaLayer:
    var target := _document.active_layer
    return group_layers([target] if target != null else [])


## Wraps several layers in one new pass-through group. The group ends just
## above the topmost one in the order, and the whole wrap is one history step,
## so undo puts all of them back where they were.
##
## The members are gathered into one run and the group is lifted on top of it.
## Neither half is decoration. The docker draws one row per child from the
## highest index down and indents by depth, so the group's own row is above
## the rows of what it holds, which is where a painter expects it. And a layer
## that is not a member but sits between two that are would be drawn inside
## the group: picking the bottom and the top of three layers first showed the
## group's header between its own two members. Membership is by reference, so
## the composite was right and only the row list lied, which is the worst of
## both.
func group_layers(members: Array) -> SaLayer:
    var wanted: Array[SaLayer] = []
    for entry: Variant in members:
        var layer: SaLayer = entry if entry is SaLayer else null
        if layer != null and layer.get_parent() == _document and not wanted.has(layer):
            wanted.append(layer)
    if wanted.is_empty():
        return null
    # A layer already inside another of them would be wrapped twice, which is
    # what dragging a group and one of its children into a selection means.
    var outer: Array[SaLayer] = []
    for layer in wanted:
        var nested := false
        for other in wanted:
            if other != layer and SaLayerStack.is_inside(layer, other):
                nested = true
                break
        if not nested:
            outer.append(layer)

    outer.sort_custom(func(a: SaLayer, b: SaLayer) -> bool: return a.get_index() < b.get_index())
    var was: Array = _document.get_children().duplicate()
    var parents: Array = []
    for layer in outer:
        parents.append(layer.group)
    var home := _common_parent(outer)
    var anchor := _block_in(outer[-1], home)
    # A picked group moves with every node inside it, because its members sit
    # below it in the flat order, and its node moved alone would leave a layer
    # picked beside it standing between the group and its own members.
    var run: Array = []
    for layer in outer:
        run.append_array(_ordered_block(layer))
    # The run takes the place of the top pick when it sits in the new group's
    # own parent, and otherwise goes above the whole block that holds it, so
    # the new group never lands inside another group's run of rows.
    var top := anchor.get_index() + (0 if anchor == outer[-1] else 1)
    var group := SaLayer.new()
    group.is_group = true
    group.name = _ops.free_name("Group %d", 1)
    group.schema = SaFieldSpec.schema_for_space(_document.color_space)
    group.group = home
    _document.add_child(group)
    var below: Array = []
    var above: Array = []
    for child: Node in was:
        if run.has(child):
            continue
        if child.get_index() < top:
            below.append(child)
        else:
            above.append(child)
    var order := below
    order.append_array(run)
    order.append(group)
    order.append_array(above)
    _reorder(order)
    for layer in outer:
        layer.group = group
    var now: Array = _document.get_children().duplicate()
    _document.modified = true
    _ops.refresh()
    var keeper := SaLayerOps.LayerKeeper.new(group, group.get_index())
    _document.history.commit("Group Layer", _toggle_wrap.bind(keeper, outer, was, now, parents), {}, 0)
    return group


## The deepest group that holds every one of *members*, or null for the
## document's top level. A new group of them goes there, so grouping a group's
## child with a layer outside that group takes the child out to join the
## layer, and never pulls the layer into a group it was not in.
func _common_parent(members: Array[SaLayer]) -> SaLayer:
    var home := SaLayerStack.parent_of(members[0])
    while home != null:
        var holds_all := true
        for layer in members:
            if not SaLayerStack.is_inside(layer, home):
                holds_all = false
                break
        if holds_all:
            return home
        home = SaLayerStack.parent_of(home)
    return null


## The ancestor of *layer*, or *layer* itself, whose parent is *home*, which
## is the head of the block *layer* sits in among *home*'s children.
func _block_in(layer: SaLayer, home: SaLayer) -> SaLayer:
    var head := layer
    while head != null and SaLayerStack.parent_of(head) != home:
        head = SaLayerStack.parent_of(head)
    return head if head != null else layer


## Puts the document's children back in *order*, a whole order a wrap
## recorded, leaving out a node that has left the document. The whole
## order rather than the picks' own slots, because a picked group's members
## move with it and have to come back with it.
func _restore_order(order: Array) -> void:
    var wanted: Array = []
    for child: Variant in order:
        var node: Node = child if child is Node and is_instance_valid(child) else null
        if node != null and node.get_parent() == _document:
            wanted.append(node)
    _reorder(wanted)


## Undo and redo of a wrap: the group leaves and each member goes back to the
## parent it had, or it returns and takes them again. *was* and *now* are the
## document's whole order before and after the wrap, empty for an ungroup,
## which moves nobody.
## *parents* holds each member's group before the wrap, in the order of
## *members*. Undo once handed every member the new group's parent, which left
## a layer from outside a group inside it after Ctrl+Z.
func _toggle_wrap(keeper: SaLayerOps.LayerKeeper, members: Array, was: Array = [], now: Array = [], parents: Array = []) -> void:
    var group: SaLayer = keeper.layer
    if group.get_parent() == _document:
        var parent := SaLayerStack.parent_of(group)
        for i in members.size():
            var member: SaLayer = members[i]
            member.group = parents[i] if i < parents.size() else parent
        _ops.take_out(keeper)
        _restore_order(was)
    else:
        _ops.put_back(keeper)
        for member: SaLayer in members:
            member.group = group
        _restore_order(now)
    _document.modified = true
    _ops.refresh()


## Dissolves a group: its members join its parent and the group leaves.
##
## What the group did to its members goes into them first, inside the one
## step: its enabled filters and then its mask are written into the paint of
## every layer inside it, at any depth, through the flatten walk, and its
## opacity is multiplied into each direct member's. An isolated group's lowest
## member composites over nothing inside it, so its own mode is never read
## there, and it takes the group's mode, which is where the group's mode went.
## A group's records and mask leave with the group and come back with it on an
## undo, which also swaps the pixels, the opacities and the mode back. That
## keeps the picture exactly for a group of one, and where members overlap it
## is the nearest they can come on their own, because a composite blended once
## is not its members blended one by one against what lies below.
func ungroup(group: SaLayer) -> bool:
    if group == null or not group.is_group or group.get_parent() != _document:
        return false
    var members := SaLayerStack.members(_document, group)
    var render := SaTreeRender.new(_document)
    # Keyed by Variant, because a typed key refuses a layer that was freed.
    var states: Dictionary[Variant, Dictionary] = {}
    var paint_bytes := 0
    for layer in _ops.layers():
        if layer.is_group or layer.is_generated() or not SaLayerStack.is_inside(layer, group):
            continue
        var state: Dictionary[Vector2i, Variant] = {}
        render.bake(group, layer, state)
        if not state.is_empty():
            states[layer] = state
            for kept: Variant in state.values():
                var chunk: SaChunk = kept if kept is SaChunk else null
                paint_bytes += chunk.byte_size() if chunk != null else 0
    var swaps: Array = []
    for member: SaLayer in members:
        if not is_equal_approx(group.opacity, 1.0):
            swaps.append([member, &"opacity", member.opacity])
            member.opacity *= group.opacity
    if SaLayerStack.isolates(group) and not members.is_empty() and members[0].blend_mode != group.blend_mode:
        swaps.append([members[0], &"blend_mode", members[0].blend_mode])
        members[0].blend_mode = group.blend_mode
    if group.mask != null and _document.mask_target == group.mask:
        _document.mask_target = null
    var parent := SaLayerStack.parent_of(group)
    for member: SaLayer in members:
        member.group = parent
    var keeper := SaLayerOps.LayerKeeper.new(group, group.get_index())
    _ops.take_out(keeper)
    _document.modified = true
    _ops.refresh()
    var toggle := _toggle_ungroup.bind(keeper, members, states, swaps)
    _document.history.commit_pair("Ungroup", toggle, toggle, paint_bytes)
    return true


## Both sides of an ungroup: the members' pixels swap with what the step
## holds, and so does each `[member, key, value]` of *swaps*, and the group
## leaves or comes back.
func _toggle_ungroup(
    keeper: SaLayerOps.LayerKeeper, members: Array, states: Dictionary[Variant, Dictionary], swaps: Array
) -> void:
    # Untyped, because a typed loop variable refuses a key that was freed.
    for layer: Variant in states:
        if is_instance_valid(layer):
            var swapped: SaLayer = layer
            _document.swap_pixels(swapped, states[layer])
    for swap: Array in swaps:
        var member: SaLayer = swap[0]
        var property: StringName = swap[1]
        var was: Variant = member.get(property)
        member.set(property, swap[2])
        swap[2] = was
    _toggle_wrap(keeper, members)


## Takes a group out with everything inside it, as one step. The members keep
## pointing at the group, so undo brings the whole subtree back grouped.
func remove_group(group: SaLayer) -> bool:
    if not can_remove_group(group):
        return false
    var block := _ordered_block(group)
    var keepers: Array = []
    var layer_bytes := 0
    # Top of the block first. A keeper records the index it was taken from, so
    # taking the bottom one first would shift everything above it down and two
    # keepers would claim the same slot, which undo then fills in either order.
    for i in range(block.size() - 1, -1, -1):
        var keeper := SaLayerOps.LayerKeeper.new(block[i], block[i].get_index())
        _ops.take_out(keeper)
        layer_bytes += keeper.bytes()
        keepers.append(keeper)
    _document.modified = true
    _ops.refresh()
    _ops.commit_presence("Delete Group", keepers, layer_bytes)
    return true


## Whether `remove_group` would take *group* out: not when it and its members
## are the whole document, which would leave no layer.
func can_remove_group(group: SaLayer) -> bool:
    if group == null or not group.is_group or group.get_parent() != _document:
        return false
    return _ordered_block(group).size() < _ops.layers().size()


## Isolated or pass-through, as a step named Group Blending, in the words of
## the row that ticks it, Blend Group on Its Own.
func set_isolated(group: SaLayer, value: bool) -> void:
    if group == null or not group.is_group or group.isolated == value:
        return
    _apply_isolated(group, value)
    _document.history.commit_pair("Group Blending", _apply_isolated.bind(group, value), _apply_isolated.bind(group, not value))


func _apply_isolated(group: SaLayer, value: bool) -> void:
    group.isolated = value
    _document.modified = true
    _ops.refresh()


## Puts *layer* into *group* (null for the top level) so that its block starts
## at *index* in the order, its subtree moving with it, as one step. This is
## what a drag in the docker does, and what moving a group by a button does.
##
## The index counts the document with the block taken out of it, which is
## where a single layer lands the way `Node.move_child` counts, and for a
## group is where its lowest member lands with the group above them. The block
## rather than the layer, because a group's own node sits on top of its
## members and a caller that means "here" means the whole run.
func place(layer: SaLayer, group: SaLayer, index: int) -> bool:
    if not can_place(layer, group, index):
        return false
    var block := _ordered_block(layer)
    var order_before: Array = _document.get_children().duplicate()
    var old_group := SaLayerStack.parent_of(layer)
    _apply_place(layer, group, index, block)
    _document.history.commit_pair(
        "Move Layer", _apply_place.bind(layer, group, index, block), _restore_place.bind(layer, old_group, order_before)
    )
    return true


## Whether `place` would move anything, which is what dims the docker's Move
## Up and Move Down on a group. The index is clamped the way `_apply_place`
## clamps it, so a group already at the top asked to go higher stays put and
## says so, rather than committing a step that changed nothing.
func can_place(layer: SaLayer, group: SaLayer, index: int) -> bool:
    if layer == null or layer.get_parent() != _document:
        return false
    if group != null and (group == layer or SaLayerStack.is_inside(group, layer)):
        return false
    var block := _ordered_block(layer)
    var at := clampi(index, 0, _document.get_child_count() - block.size())
    return SaLayerStack.parent_of(layer) != group or block[0].get_index() != at


## The move is written as the whole order rather than as one `move_child` per
## member, because every move shifts the ones after it and a block of three
## computed against stale indices comes apart. The rest of the document keeps
## its order, and the block is spliced into it at *index*.
func _apply_place(layer: SaLayer, group: SaLayer, index: int, block: Array) -> void:
    layer.group = group
    var rest: Array = []
    for child in _document.get_children():
        if not block.has(child):
            rest.append(child)
    var at := clampi(index, 0, rest.size())
    var wanted: Array = rest.slice(0, at)
    wanted.append_array(block)
    wanted.append_array(rest.slice(at))
    _reorder(wanted)
    _document.modified = true
    _ops.refresh()


## The whole order as it was, put back one child at a time from the bottom:
## moving each to its recorded index in that sequence reproduces the sequence,
## where moving only the block would not, because every move shifts the rest.
func _restore_place(layer: SaLayer, group: SaLayer, order_before: Array) -> void:
    layer.group = group
    var wanted: Array = []
    for child: Variant in order_before:
        var node: Node = child if child is Node and is_instance_valid(child) else null
        if node != null and node.get_parent() == _document:
            wanted.append(node)
    _reorder(wanted)
    _document.modified = true
    _ops.refresh()


## Puts the document's children in the order *wanted* with the fewest
## `move_child` calls one sweep can make, which is what every listener of
## `child_order_changed` pays for: each call that moves a node emits it once.
## A sweep from the bottom moves the nodes that come first in a changed run and
## one from the top moves the ones that come last, so a block of thirty moved
## past a sibling of six is six moves one way and thirty the other. Both are
## counted on a copy of the order, which costs a few array moves, and the
## cheaper sweep is the one run. *wanted* may leave out a node, which then ends
## above the ones named, and only the sweep from the bottom puts it there.
func _reorder(wanted: Array) -> void:
    var whole := wanted.size() == _document.get_child_count()
    var from_bottom := _sweep(_document.get_children(), wanted, false) if whole else 0
    var from_top := _sweep(_document.get_children(), wanted, true) if whole else 1
    if from_top < from_bottom:
        for slot in range(wanted.size() - 1, -1, -1):
            var node: Node = wanted[slot]
            if node.get_index() != slot:
                _document.move_child(node, slot)
    else:
        for slot in wanted.size():
            var node: Node = wanted[slot]
            if node.get_index() != slot:
                _document.move_child(node, slot)


## How many moves a sweep puts *order* into *wanted* with, moving each node
## that is not yet in its slot to it, from the top when *from_top* and from the
## bottom otherwise. *order* is written to as the moves would write the
## document.
static func _sweep(order: Array, wanted: Array, from_top: bool) -> int:
    var moves := 0
    var slots := range(wanted.size() - 1, -1, -1) if from_top else range(wanted.size())
    for slot: int in slots:
        if order[slot] == wanted[slot]:
            continue
        order.remove_at(order.find(wanted[slot]))
        order.insert(slot, wanted[slot])
        moves += 1
    return moves


## *layer* and everything inside it, in the order the document holds them,
## so a group comes last, on top of its own members.
func _ordered_block(layer: SaLayer) -> Array[SaLayer]:
    var block := subtree(layer)
    block.sort_custom(func(a: SaLayer, b: SaLayer) -> bool: return a.get_index() < b.get_index())
    return block


## *layer* followed by everything inside it, in the document's order.
func subtree(layer: SaLayer) -> Array[SaLayer]:
    var found: Array[SaLayer] = [layer]
    if not layer.is_group:
        return found
    for child in _document.get_children():
        var other := child as SaLayer
        if other != null and other != layer and SaLayerStack.is_inside(other, layer):
            found.append(other)
    return found


## Whether `move` would shift *layer* by *delta*, which is what dims Move Up
## and Move Down: not at the end of the stack it would move past, and asked of
## the same sibling steps the move takes.
func can_move(layer: SaLayer, delta: int) -> bool:
    return not _move_target(layer, delta).is_empty()


## Moves a layer *delta* sibling steps up the stack, or down for a negative
## delta, as one Move Layer step. A step goes past the whole block of the
## sibling beside it, so a layer never lands between a group's header and its
## members, and a layer at the end of its group's members steps out of the
## group, above the header going up and below the lowest member going down.
## Counting slots instead put a layer inside a group's block with no group,
## which the docker drew as an outsider splitting the group from its child.
func move(layer: SaLayer, delta: int) -> bool:
    var target := _move_target(layer, delta)
    if target.is_empty():
        return false
    var group: SaLayer = target[0]
    var index: int = target[1]
    var block := _ordered_block(layer)
    var order_before: Array = _document.get_children().duplicate()
    var old_group := SaLayerStack.parent_of(layer)
    _apply_place(layer, group, index, block)
    _document.history.commit_pair(
        "Move Layer", _apply_place.bind(layer, group, index, block), _restore_place.bind(layer, old_group, order_before)
    )
    return true


## Where *delta* sibling steps take *layer*, as the group it ends in and the
## index `place` counts, or empty when the first step has nowhere to go. The
## steps are walked over a copy of the order, the document with the block
## taken out keeping its order throughout, so the index of the last step is
## the one `_apply_place` takes from the untouched document.
func _move_target(layer: SaLayer, delta: int) -> Array:
    if layer == null or layer.get_parent() != _document or delta == 0:
        return []
    var block := _ordered_block(layer)
    var rest: Array[SaLayer] = []
    for other in _ops.layers():
        if not block.has(other):
            rest.append(other)
    var group := SaLayerStack.parent_of(layer)
    var at := rest.size()
    for slot in rest.size():
        if rest[slot].get_index() > block[0].get_index():
            at = slot
            break
    var target: Array = []
    for _step in absi(delta):
        var next := _sibling_step(rest, group, at, delta > 0)
        if next.is_empty():
            break
        target = next
        group = next[0]
        at = next[1]
    return target


## One step of *move* for a block standing at *at* among *rest*, a child of
## *group*. Going up, the layer just above the block is either the group's
## header, which the block leaves to stand above, or a member of a sibling's
## block, whose topmost node is the sibling itself. Going down, the layer just
## below is either in a sibling's block, which the block goes under whole, or
## outside the group, which the block leaves where it stands.
func _sibling_step(rest: Array[SaLayer], group: SaLayer, at: int, up: bool) -> Array:
    var neighbour: SaLayer = null
    if up and at < rest.size():
        neighbour = rest[at]
    elif not up and at > 0:
        neighbour = rest[at - 1]
    if neighbour == null:
        return [] if group == null else [SaLayerStack.parent_of(group), at]
    if up and neighbour == group:
        return [SaLayerStack.parent_of(group), at + 1]
    var sibling := neighbour
    while sibling != null and SaLayerStack.parent_of(sibling) != group:
        sibling = SaLayerStack.parent_of(sibling)
    if sibling == null:
        return [SaLayerStack.parent_of(group), at]
    if up:
        return [group, rest.find(sibling) + 1]
    var lowest := rest.size()
    for member in subtree(sibling):
        lowest = mini(lowest, rest.find(member))
    return [group, lowest]


## What a bake writes into one of a layer's chunks: the chunk as a node shows
## it, the node's filters and then its mask, at the layer's own density, for
## `SaTreeRender.bake`, which an ungroup and a merge run. A merge refuses a
## lower layer at double resolution, so an ungroup is the one bake that meets
## one, and this lives beside it.
##
## The compositor's answer comes down to the document's resolution, which is
## what the output draws. A member made at Double Resolution took that answer
## into one corner of its 512 texel chunk and kept its own texels in the other
## three quarters, so an ungroup changed the picture under the painter. A layer
## finer than the document goes through a fine [SaLayerShown] of this one's own
## instead, the kind a display chunk's walk uses: the chain filters at the
## layer's density, and the mask kernel reads a coverage at the document's
## resolution at the texel under each of the chunk's, nearest, which is the
## texel `SaFilterDensity.Masks` would enlarge it to. A layer at the
## document's resolution goes through the compositor as any layer does.
class BakeShown:
    extends RefCounted

    var _compositor: SaCompositor
    ## The fine one, made when the first layer finer than the document comes
    ## through, since most bakes never meet one.
    var _fine: SaLayerShown = null

    func _init(compositor: SaCompositor) -> void:
        _compositor = compositor

    ## What *node* shows of *source*, *layer*'s chunk at *grid_pos* or null
    ## where it holds none, as a texture at *layer*'s density, or null where
    ## nothing shows. *layer* is where a neighbourhood filter reads the chunks
    ## around this one from.
    func of(node: SaLayer, layer: SaLayer, source: SaTexture, grid_pos: Vector2i) -> SaTexture:
        var region := Rect2i(0, 0, SaLayer.CHUNK_SIZE, SaLayer.CHUNK_SIZE)
        if SaFilterDensity.scale_of(layer) <= 1.0:
            return _compositor.shown(node, node, source, grid_pos, region, layer)
        if _fine == null:
            _fine = SaLayerShown.new(true, _compositor.filter_chain, _compositor.get_compute)
        return _fine.shown(node, node, source, grid_pos, region, layer)
