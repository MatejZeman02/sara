## Layer > Duplicate Layer's copy: a layer of the same kind as the one it
## copies, put into the document above it, with nothing recorded yet, and the
## copy of a picked set recorded as one step.
##
## **Every property the file keeps.** The copy carries each member
## `SaSadFile` writes for a layer, so a duplicate saved and opened again is the
## layer it copied under another name. A group's copy holds a copy of each of
## its members, in their order and nested as they were, and a generated
## layer's copy carries its generator, its resolve hook and parameters of its
## own. A copy made as a paint layer whatever it copied would bring a group
## out empty and a generated layer that draws nothing.
##
## **Right before any save.** The copy carries what a load would otherwise
## mend through `SaLayerTypeRegistry.rebind`, an adjustment or effect layer's
## `input` above all, without which an adjustment copied inside a group would
## composite as an empty paint layer until the file was opened again. A scene
## layer's copy has its scene, its parameters and a viewport of its own, a
## simulated layer's copy a record of its own, and an effect layer whose input
## is inside the copied block reads the input's copy.
##
## **Placed, not committed.** `place` returns the copies bottom first, which
## is the block `SaLayerOps.commit_added` records as one step, so the whole
## duplicate leaves and comes back together. `write` is the one path here
## that records, because a set's copies are one `Duplicate Layers` step and
## `SaLayerOps` stands at gdlint's limit of public methods.
class_name SaLayerDuplicate
extends RefCounted

var _document: SaDocument


func _init(document: SaDocument) -> void:
    _document = document


## Copies *source*, and everything inside it when it is a group, directly
## above the block it heads. Empty when there is nothing to copy.
func place(source: SaLayer) -> Array[SaLayer]:
    var copies: Array[SaLayer] = []
    if source == null or source.get_parent() != _document:
        return copies
    var block := _block(source)
    var at := source.get_index() + 1
    var copy_of: Dictionary[SaLayer, SaLayer] = {}
    for original in block:
        var twin := _copy(original)
        copy_of[original] = twin
        _document.add_child(twin)
        _document.move_child(twin, at)
        at += 1
        copies.append(twin)
    # A second pass, because a group sits above its members and so is copied
    # after them. The top of the block keeps its source's parent, and every
    # member inside it follows its own parent's copy.
    for original in block:
        var parent := SaLayerStack.parent_of(original)
        var twin: SaLayer = copy_of[original]
        twin.group = parent if original == source else copy_of.get(parent, parent)
        # An effect layer that reads a member of the block reads that member's
        # copy, so the copied group is a working copy of the whole recipe and
        # not a second view of the original's input.
        if original.source != null:
            twin.source = copy_of.get(original.source, original.source)
    return copies


## Copies each of *picked* above itself as `SaLayerOps.duplicate` does and
## records every copy as one `Duplicate Layers` step, so one Ctrl+Z takes the
## whole set's copies away, where each row once wrote a step of its own. A set
## of one is `SaLayerOps.duplicate`, its step named as it always was. The copy
## of the active layer is active afterwards, or the top copy when the active
## layer was not picked. Answers that copy, or null when nothing was copied.
func write(picked: Array[SaLayer]) -> SaLayer:
    if picked.size() == 1:
        return SaLayerOps.new(_document).duplicate(picked[0])
    var copies: Array[SaLayer] = []
    var chosen: SaLayer = null
    for source in picked:
        var block := place(source)
        copies.append_array(block)
        if source == _document.active_layer and not block.is_empty():
            chosen = block[-1]
    if copies.is_empty():
        return null
    # Bottom first, the order `commit_added` reads, whatever order the rows
    # were picked in.
    copies.sort_custom(func(a: SaLayer, b: SaLayer) -> bool: return a.get_index() < b.get_index())
    if chosen == null:
        chosen = copies[-1]
    _document.set_active_layer(chosen)
    SaLayerOps.new(_document).commit_added("Duplicate Layers", copies)
    return chosen


## *source* and every layer inside it, bottom first, which is the order the
## copies go in so the group's copy lands on top of its own members.
func _block(source: SaLayer) -> Array[SaLayer]:
    var block: Array[SaLayer] = []
    for child in _document.get_children():
        var layer := child as SaLayer
        if layer != null and (layer == source or (source.is_group and SaLayerStack.is_inside(layer, source))):
            block.append(layer)
    return block


func _copy(source: SaLayer) -> SaLayer:
    var shown := source.shown_name()
    return copy(source, _free_name(shown + " Copy" if not shown.is_empty() else "Layer Copy"))


## A copy of *source* alone, named *layer_name* and in no document yet, its
## group and its effect input still its source's for the caller to point.
## Duplicate To, `SaLayerDuplicateTo`, makes its copies here, so a layer carried
## into another document carries every property a duplicate in its own does.
func copy(source: SaLayer, layer_name: String) -> SaLayer:
    var dup := SaLayer.new()
    dup.take_name(layer_name)
    dup.layer_type = source.layer_type
    dup.input = source.input
    dup.scene = source.scene
    dup.scene_params = source.scene_params.duplicate(true)
    dup.folded = source.folded
    dup.resolve_hook = source.resolve_hook
    dup.generator = source.generator
    dup.generator_params = source.generator_params.duplicate(true)
    dup.module_data = source.module_data.duplicate(true)
    dup.is_group = source.is_group
    dup.isolated = source.isolated
    dup.affects_all = source.affects_all
    dup.clip_to_below = source.clip_to_below
    dup.comment = source.comment
    dup.color_tag = source.color_tag
    dup.blend_mode = source.blend_mode
    dup.opacity = source.opacity
    dup.is_locked = source.is_locked
    dup.alpha_locked = source.alpha_locked
    dup.visible = source.visible
    dup.schema = source.schema.duplicate()
    dup.resolution_scale = source.resolution_scale
    for grid_pos: Vector2i in source.chunks.keys():
        dup.set_chunk(grid_pos, source.duplicate_chunk(grid_pos))
    var live := SaLiveTransform.of(source)
    if live != null:
        dup.live_transform = SaLiveTransform.new(live.matrix, live.crop, live.smart)
    _copy_mask(source, dup)
    for record in source.filters:
        if record != null:
            dup.filters.append(record.duplicate_record())
    _copy_simulation(source, dup)
    SaSceneLayer.attach(dup)
    SaDrawnLayer.copy_recipe(source, dup)
    return dup


## The simulation on *source* put on *dup* as a file puts it back, through
## `SaSimulation.reopen`, its writer: the same rule, module and values, a seed
## of its own copied from the source's, the ring, the count, the speed and the
## domain. The copy is paused whatever the source was doing, as an opened
## file is.
func _copy_simulation(source: SaLayer, dup: SaLayer) -> void:
    var record := SaSimulation.record_of(source)
    if record == null:
        return
    var rd := GlobalShaderCompiler.get_rd()
    var kept: Dictionary[Vector2i, SaTexture] = {}
    for grid_pos: Vector2i in record.seed_chunks:
        var held: SaTexture = record.seed_chunks[grid_pos]
        if rd == null or held == null or not held.rid.is_valid():
            continue
        var chunk := SaTexture.new(held.size, held.format)
        rd.texture_copy(held.rid, chunk.rid, Vector3.ZERO, Vector3.ZERO, Vector3(held.size.x, held.size.y, 1), 0, 0, 0, 0)
        SaTexture.note_copy(chunk.bytes)
        kept[grid_pos] = chunk
    var ringed: Array[Vector2i] = []
    ringed.assign(record._ringed.keys())
    var made := SaSimulation.reopen(dup, record.rule, record.module, record.params, kept, ringed)
    if made == null:
        return
    made.steps = record.steps
    made.speed = record.speed
    made.domain = record.domain


## The schema's setter builds a field mask at a rest of one, so a copy of a
## mask made from a selection or inverted would open a new chunk shown where
## the original hides it. A group's mask holds chunks of its
## own, which the chunks copied above never reach.
func _copy_mask(source: SaLayer, dup: SaLayer) -> void:
    if source.mask == null:
        return
    if source.mask.is_own():
        dup.mask = SaMask.own()
        for grid_pos: Vector2i in source.mask.grid_positions():
            dup.mask.set_chunk(grid_pos, source.mask.duplicate_chunk(grid_pos))
    if dup.mask == null:
        return
    dup.mask.rest = source.mask.rest
    dup.mask.enabled = source.mask.enabled


## *base* when no layer has it, else the first of `base 2`, `base 3` and on
## that none has.
func _free_name(base: String) -> String:
    var candidate := base
    var number := 2
    while _name_taken(candidate):
        candidate = "%s %d" % [base, number]
        number += 1
    return candidate


func _name_taken(candidate: String) -> bool:
    for child in _document.get_children():
        if str(child.name) == candidate.validate_node_name():
            return true
    return false
