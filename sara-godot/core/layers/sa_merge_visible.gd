## Merge Visible, Krita's Ctrl+Shift+E: every layer the canvas shows drawn into
## one new paint layer, which stands where the topmost of them stood, and every
## one of them taken out, while the hidden layers stay as they are. One step,
## which one undo takes back whole.
##
## The pixels are the compositor's own, through `SaTreeRender.flattened`, the
## walk Flatten draws with, so a blend mode, an opacity, a mask, a clip and a
## group read in the merged layer as they read on the canvas. That walk passes
## over a hidden layer already, so the whole tree drawn is the visible layers
## drawn. A group goes with the merge only when everything in it does: one
## holding a hidden layer stays, with the hidden layer in it, and the merged
## layer stands above it at the top level, where the group's mode and opacity
## cannot fall on paint that already carries them.
##
## **The Ground stays.** A ground, the paper or the canvas or a module's that
## answers a height, is never taken: the layers above it merge drawn over
## nothing, and the ground keeps its row and its colour, which stay settings the
## painter can change. A merged layer whose look leaned on the ground, a
## mode other than Normal, an adjustment, an effect or a clip to it, looks
## different as part of a Normal layer, so the corner names the first such
## layer and says the merge is one undo away. Flatten, `SaLayerOps`, still takes
## the ground, because one layer is what it is for. Every other generated layer,
## the flat Background colour and a module's that answers no height, contributes
## and goes as any visible layer does.
##
## Its own file beside `SaLayerOps`, which stood at 841 lines and whose
## mechanics it borrows through that class's public door: the keeper, `take_out`,
## `put_back`, `refresh` and `commit_presence`.
class_name SaMergeVisible
extends RefCounted

## The step's name in the history, and the title a refusal goes under.
const ACTION := "Merge Visible"
## What the corner says over a visible locked layer, which refuses the whole
## merge rather than taking out a layer the painter locked.
const LOCKED := "'%s' is locked, so the visible layers were not merged."
## What the corner says when a merged layer's look read the ground under it.
const OVER_GROUND := "'%s' looked different over the ground, so the merged layer differs from it there. Undo brings it back."
## The skeleton's grounds by type, for a ground saved before the tooth that
## tells one apart today.
const GROUND_TYPES: Array[StringName] = [&"paper", &"canvas"]

var _document: SaDocument
var _ops: SaLayerOps


func _init(document: SaDocument) -> void:
    _document = document
    _ops = SaLayerOps.new(document)


## Whether *layer* is a ground: a generated layer that answers a height, read
## from its tooth as `SaGroundRows` reads it without a registry, or one of the
## skeleton's ground types.
static func is_ground(layer: SaLayer) -> bool:
    if layer == null or not layer.is_generated():
        return false
    return layer.generator_params.has(SaGeneratedLayer.PARAM_TOOTH) or GROUND_TYPES.has(layer.layer_type)


## The layers the merge takes out, bottom first: every layer that contributes
## but a ground, and every visible group all of whose members go too.
func merged() -> Array[SaLayer]:
    var stack := _ops.layers()
    var going: Dictionary[SaLayer, bool] = {}
    for layer in stack:
        if not layer.is_group and not is_ground(layer) and SaLayerStack.contributes(_document, layer):
            going[layer] = true
    # A group sits above its members, so walking the stack upwards meets every
    # member, an inner group included, before the group that holds it.
    for layer in stack:
        if not layer.is_group or not SaLayerStack.contributes(_document, layer):
            continue
        var whole := true
        for member in SaLayerStack.members(_document, layer):
            whole = whole and going.has(member)
        if whole:
            going[layer] = true
    var found: Array[SaLayer] = []
    for layer in stack:
        if going.has(layer):
            found.append(layer)
    return found


## Merges the visible layers, or says in the corner why not, and answers
## whether it did. Fewer than two visible layers is nothing to merge and says
## nothing, the way Flatten over one layer does, so the row stays lit as
## Flatten's does rather than walking the stack on every open of the menu.
func merge() -> bool:
    var going := merged()
    if going.size() < 2:
        return false
    for layer in going:
        if layer._locked:
            SaProblems.refuse(ACTION, tr(LOCKED) % layer.name)
            return false
    var fresh := SaLayer.new()
    fresh.schema = SaFieldSpec.schema_for_space(_document.color_space)
    if SaLayerRefusals.new(_document).refuses_merge(ACTION, null, fresh):
        fresh.free()
        return false
    SaLocalView.end_contents(_document)
    var top := going[going.size() - 1]
    var at := _place(going, top)
    var grounds := _grounds()
    var changed := _changed_over(going, grounds)
    # The walk draws every visible layer, so a ground is hidden for the length
    # of the draw and shown again before anything else reads it.
    for ground in grounds:
        ground.visible = false
    _draw_into(fresh, going)
    for ground in grounds:
        ground.visible = true
    SaHeightOps.new(_document).give_schema(fresh, going, {})
    var keepers: Array = []
    var layer_bytes := 0
    for i in range(going.size() - 1, -1, -1):
        var keeper := SaLayerOps.LayerKeeper.new(going[i], going[i].get_index())
        _ops.take_out(keeper)
        layer_bytes += keeper.bytes()
        keepers.append(keeper)
    # Named once the layer it is named for is out, so the name is free.
    fresh.take_name(top.shown_name())
    var kept := SaLayerOps.LayerKeeper.new(fresh, at)
    _ops.put_back(kept)
    keepers.append(kept)
    _document.modified = true
    _ops.refresh()
    _ops.commit_presence(ACTION, keepers, layer_bytes)
    if changed != null:
        EventBus.corner_notice.emit(tr(OVER_GROUND) % changed.name)
    return true


## The visible grounds, which the merged layer is drawn without.
func _grounds() -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for layer in _ops.layers():
        if is_ground(layer) and SaLayerStack.contributes(_document, layer):
            found.append(layer)
    return found


## The first layer of *going* whose look read a ground under it, or null: one
## with no isolated group around it that blends in a mode other than Normal,
## is an adjustment or an effect, or is clipped to a ground. A pass-through
## group is no composite of its own, so its members answer for it.
func _changed_over(going: Array[SaLayer], grounds: Array[SaLayer]) -> SaLayer:
    if grounds.is_empty():
        return null
    var lowest := grounds[0].get_index()
    for layer in going:
        if layer.get_index() < lowest or _isolated_around(layer):
            continue
        if layer.is_group and not SaLayerStack.isolates(layer):
            continue
        var clipped := grounds.has(SaLayerStack.clip_base(_document, layer))
        var mode := layer.get_blend_mode_name() != SaLayer.BLEND_MODE.NORMAL
        if mode or layer.is_adjustment() or layer.is_effect() or clipped:
            return layer
    return null


## Whether an isolated group holds *layer*, which then reads nothing under it.
func _isolated_around(layer: SaLayer) -> bool:
    var group := SaLayerStack.parent_of(layer)
    while group != null:
        if SaLayerStack.isolates(group):
            return true
        group = SaLayerStack.parent_of(group)
    return false


## The index the merged layer takes once *going* is out: above *top*, or above
## the outermost group holding *top* that stays, counted among the layers that
## stay.
func _place(going: Array[SaLayer], top: SaLayer) -> int:
    var anchor := top
    var group := SaLayerStack.parent_of(top)
    while group != null:
        if not going.has(group):
            anchor = group
        group = SaLayerStack.parent_of(group)
    var count := 0
    for layer in _ops.layers():
        if layer.get_index() <= anchor.get_index() and not going.has(layer):
            count += 1
    return count


## The whole tree drawn into *fresh* at every grid position a visible layer
## reaches, its halo included, rendered before anything moves. Flatten's walk,
## `SaLayerOps._flatten_into`, over the layers that go.
func _draw_into(fresh: SaLayer, going: Array[SaLayer]) -> void:
    var render := SaTreeRender.new(_document)
    var reach: Dictionary[Vector2i, bool] = {}
    for layer in going:
        layer.resolve_pending()
        if layer.is_group:
            continue
        var covered: Dictionary[Vector2i, bool] = {}
        for grid_pos: Vector2i in _covered_by(layer):
            covered[grid_pos] = true
        reach.merge(render.reach(layer, covered))
    for layer in going:
        if layer.is_group:
            reach.merge(render.reach(layer, reach.duplicate()))
    var schema: Array[SaFieldSpec] = []
    for spec in fresh.schema:
        if spec != null and spec.id != SaFieldSpec.MASK:
            schema.append(spec)
    var flat: Dictionary[Vector2i, SaChunk] = {}
    for grid_pos: Vector2i in reach:
        flat[grid_pos] = render.flattened(schema, grid_pos)
    SaHeightOps.new(_document).flatten(SaHeightOps.spec_among(going), going, flat)
    for grid_pos: Vector2i in flat:
        fresh.set_chunk(grid_pos, flat[grid_pos])


## Every grid position *layer* draws on, as `SaLayerOps` reads it.
func _covered_by(layer: SaLayer) -> Array:
    if layer.is_generated():
        return SaGeneratedLayer.covered_positions(_document)
    return SaLiveTransform.paint_of(layer).chunks.keys()
