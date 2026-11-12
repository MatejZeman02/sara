## Clear Layer, the mask's operations and Move Up and Move Down over every
## picked layer, each press one history step, which the Layers docker's rows
## and the Layer menu's chords both run.
##
## Acting on the active layer alone, Clear would empty one row of two and Move
## Up would pull the set apart. Each runs the operation a single row takes, a
## row at a time, inside `SaHistory.as_one`, so a set of one is the step a
## single row takes and a set of several is one step that one Ctrl+Z takes
## back whole. In `core` and not beside the docker, because the chords in
## `core/loader` reach it too and `core` never names `ui`.
class_name SaLayerSetStep
extends RefCounted

## The step a set of several writes, by mask command, a set of one keeping the
## name its single row's step has.
const MASK_STEPS: Dictionary[StringName, String] = {
    SaMaskOps.ADD: "Add Masks",
    SaMaskOps.ADD_FROM_SELECTION: "Add Masks from Selection",
    SaMaskOps.DELETE: "Delete Masks",
    SaMaskOps.APPLY: "Apply Masks",
    SaMaskOps.INVERT: "Invert Masks",
    SaMaskOps.DISABLE: "Disable Masks",
    SaMaskOps.TO_SELECTION: "Masks to Selection",
}

## The commands that give an owner a mask, after which the lead's mask is what
## the brush paints.
const ADDS: Array[StringName] = [SaMaskOps.ADD, SaMaskOps.ADD_FROM_SELECTION]

var _document: SaDocument


func _init(document: SaDocument) -> void:
    _document = document


## Empties every layer of *picked*, as one step. A locked layer is left as it
## is, which is what Clear does to one.
func clear(picked: Array[SaLayer]) -> bool:
    return _as_one("Clear Layers", _clear_each.bind(picked)) > 0


func _clear_each(picked: Array[SaLayer]) -> void:
    for layer in picked:
        if is_instance_valid(layer) and layer.get_parent() == _document:
            _document.clear_layer(layer)


## Runs the mask's *command_id* on every owner of *picked* it can run on, as
## one step. *lead* is the row whose state a toggle follows, the active layer,
## so Disable Mask over a mixed set lands every mask on one state, the one the
## lead's tick promised. Mask to Selection selects what every picked mask
## shows, the masks added together, since a selection is one thing and the
## last mask alone would make the rest a press that did nothing.
func run_mask(command_id: StringName, picked: Array, lead: Object = null) -> bool:
    SaMaskOps.refuses_locked(command_id, picked)
    var title: String = MASK_STEPS.get(command_id, "Mask")
    if command_id == SaMaskOps.DISABLE and _leader(command_id, picked, lead) != null:
        title = "Disable Masks" if SaMaskOps.mask_of(_leader(command_id, picked, lead)).enabled else "Enable Masks"
    # An add of one is two steps gathered, the mask and the brush's aim, so it
    # is named here as the single row's step would be.
    if command_id in ADDS and _takers(command_id, picked).size() == 1:
        title = "Add Mask" if command_id == SaMaskOps.ADD else "Add Mask from Selection"
    return _as_one(title, _mask_each.bind(command_id, picked, lead)) > 0


## Whether `run_mask` would act on any owner of *picked*, which keeps a row live
## while one picked row can take it.
static func can_mask(command_id: StringName, picked: Array) -> bool:
    for owner: Object in picked:
        if SaMaskOps.can(command_id, owner):
            return true
    return false


## The owners of *picked* *command_id* can run on.
static func _takers(command_id: StringName, picked: Array) -> Array[Object]:
    var takers: Array[Object] = []
    for owner: Object in picked:
        if is_instance_valid(owner) and SaMaskOps.can(command_id, owner):
            takers.append(owner)
    return takers


## The owner a toggle follows: *lead* when it takes the command, the first
## owner that does otherwise, and null when none does.
static func _leader(command_id: StringName, picked: Array, lead: Object) -> Object:
    var takers := _takers(command_id, picked)
    if takers.is_empty():
        return null
    return lead if takers.has(lead) else takers[0]


func _mask_each(command_id: StringName, picked: Array, lead: Object) -> void:
    var ops := SaMaskOps.new(_document)
    var takers := _takers(command_id, picked)
    var leader := _leader(command_id, picked, lead)
    if leader == null:
        return
    if command_id == SaMaskOps.DISABLE:
        var wanted := not SaMaskOps.mask_of(leader).enabled
        for owner in takers:
            ops.set_enabled(owner, wanted)
        return
    if command_id == SaMaskOps.TO_SELECTION:
        ops.to_selection(leader)
        for owner in takers:
            if owner == leader:
                continue
            var so_far: Dictionary = _document.selection.chunks
            ops.to_selection(owner)
            var selection := _document.selection
            selection.change("Mask to Selection", selection.merge_region.bind(so_far, SaSelection.Mode.ADD))
        return
    for owner in takers:
        ops.run(command_id, owner)
    if command_id in ADDS:
        _aim_brush(leader)


## Makes the mask just added to *leader* what the brush paints, as Photoshop
## does, inside the step the add is, so one Ctrl+Z takes the mask and the aim
## off together and a redo puts both back. Only a layer's or a group's mask
## takes the brush here: a filter's record is reached by its own row, and a
## mask a filter attaches for itself never comes this way.
func _aim_brush(leader: Object) -> void:
    if not leader is SaLayer or SaMaskOps.mask_of(leader) == null:
        return
    var before: SaMask = _document.mask_target
    SaLayerSetStep._aim_at(_document, leader)
    if _document.history != null:
        _document.history.commit_pair(
            "Add Mask", SaLayerSetStep._aim_at.bind(_document, leader), SaLayerSetStep._aim_back.bind(_document, before)
        )


## Aims *document*'s brush at *leader*'s mask, read when it runs, because a redo
## of the add gives a layer a new mask object rather than the one undo took off.
static func _aim_at(document: SaDocument, leader: Object) -> void:
    if is_instance_valid(leader) and SaMaskOps.mask_of(leader) != null:
        document.mask_target = SaMaskOps.mask_of(leader)


static func _aim_back(document: SaDocument, before: SaMask) -> void:
    document.mask_target = before


## Moves every root of *picked* *delta* sibling steps, as one block in its
## order and one step: the row in front goes first, the top one going up and
## the bottom one going down, and each after it steps past what it then has
## beside it, so a set that stood together stands together one place on. A
## set whose front row cannot move does not move at all, rather than closing
## up against it.
func move(picked: Array[SaLayer], delta: int) -> bool:
    var block := _front_first(picked, delta)
    if not can_move(picked, delta):
        return false
    var ops := SaLayerOps.new(_document)
    if block.size() == 1:
        return ops.move(block[0], delta)
    return _as_one("Move Layers", _move_each.bind(block, delta)) > 0


## Whether `move` would move *picked*, which dims Move Up and Move Down.
func can_move(picked: Array[SaLayer], delta: int) -> bool:
    var block := _front_first(picked, delta)
    return not block.is_empty() and SaLayerOps.new(_document).can_move(block[0], delta)


func _move_each(block: Array[SaLayer], delta: int) -> void:
    var ops := SaLayerOps.new(_document)
    for layer in block:
        ops.move(layer, delta)


## The roots of *picked*, the one a move of *delta* leads with first.
func _front_first(picked: Array[SaLayer], delta: int) -> Array[SaLayer]:
    var block := SaLayerStack.roots(_document, picked)
    block.sort_custom(func(a: SaLayer, b: SaLayer) -> bool: return (a.get_index() > b.get_index()) == (delta > 0))
    return block


## *work* as one step of the document's history, or simply run with no
## history, which a document being built has.
func _as_one(action_name: String, work: Callable) -> int:
    if _document.history == null:
        work.call()
        return 1
    return _document.history.as_one(action_name, work)
