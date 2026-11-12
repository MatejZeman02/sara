## The seven operations on a mask, each one a history step: add, add from
## the selection, delete, apply, invert, disable and mask to selection. And
## `transfer`, a mask moved or copied from one layer to another, and
## `mask_from_selection`, the second's body with no step, for an operation
## that makes a mask inside a step of its own. And `fill` and `clear`, what the
## fill and clear keys do while a mask is the paint target.
##
## Built the way `SaLayerOps` is, `SaMaskOps.new(document).invert(layer)`, and
## in a folder of its own below it rather than inside it, because that file is
## already long and a mask is a thing of its own. Each operation takes an owner, a layer, a group or an
## attached filter's record, and reaches the mask through the owner's `mask` and
## the one interface of `SaMask`, so a group's mask and an attached filter's
## take the same seven calls with no second implementation.
##
## The owner is an `Object` for the record's sake: an `SaAttachedFilter` is not a
## layer and has no paint, so it is told apart in the four places a layer's
## own members are read, `can`, `_give_mask`, `_reach` and `_refresh`, and
## everywhere else it is an owner with a `mask`.
##
## **One shape of step for five of them.** Add, add from the selection, delete,
## apply and invert change what the mask holds, or whether there is one, and
## each is recorded as a pair of `Shape`s, the owner's mask before and after, a
## VRAM copy of every chunk of it. Undo puts the first back and redo the second.
## A snapshot rather than the inverse operation, because invert is its own
## inverse only on paper: a mask chunk it allocated at one is a chunk that was
## not there before, and apply cannot be taken back by any arithmetic at all
## where the mask was zero. Disable is a flag and goes through
## `SaHistory.commit_pair` as two values, and mask to selection is a pair of
## selections.
class_name SaMaskOps
extends RefCounted

## The command ids, which the Layer menu, the docker's dropdown and the keyboard
## all run through `run`, so the three cannot disagree about what a row does.
const ADD := &"layer_mask_add"
const ADD_FROM_SELECTION := &"layer_mask_add_from_selection"
const DELETE := &"layer_mask_delete"
const APPLY := &"layer_mask_apply"
const INVERT := &"layer_mask_invert"
const DISABLE := &"layer_mask_disable"
const TO_SELECTION := &"layer_mask_to_selection"

## What a texel of coverage holds where the owner is hidden.
const HIDDEN := Color(0, 0, 0, 0)

## The seven, in the order a menu lists them.
const ALL: Array[StringName] = [ADD, ADD_FROM_SELECTION, DELETE, APPLY, INVERT, DISABLE, TO_SELECTION]


## An owner's mask at one moment: whether it had one, whether it was on, and a
## copy of every chunk of coverage it held. Apply also keeps the albedo it
## multiplied, because that is the half of the layer apply changes.
class Shape:
    extends RefCounted

    ## The mask the owner had, or null for an owner with none. Kept rather than
    ## rebuilt so a group's own mask comes back as the same object, which is
    ## what a paint target pointing at it still names.
    var mask: SaMask = null
    var enabled: bool = true
    ## What a position the mask held nothing at read, `SaMask.rest`.
    var rest: float = 1.0
    ## Grid position to a chunk holding the mask field alone.
    var chunks: Dictionary[Vector2i, SaChunk] = {}
    ## Grid position to a chunk holding the albedo alone. Empty but for apply.
    var albedo: Dictionary[Vector2i, SaChunk] = {}

    func _init(owner: Object, with_albedo: bool) -> void:
        mask = SaMaskOps.mask_of(owner)
        if mask != null:
            enabled = mask.enabled
            rest = mask.rest
            for grid_pos: Vector2i in mask.grid_positions():
                var copy := mask.duplicate_chunk(grid_pos)
                if copy != null:
                    chunks[grid_pos] = copy
        if with_albedo:
            var layer := owner as SaLayer
            for grid_pos: Vector2i in layer.chunks:
                albedo[grid_pos] = layer.chunks[grid_pos].duplicate_chunk(SaFieldSpec.ALBEDO)

    ## VRAM the copies hold, which is what the step is charged with.
    func bytes() -> int:
        var total := 0
        for grid_pos: Vector2i in chunks:
            total += chunks[grid_pos].byte_size()
        for grid_pos: Vector2i in albedo:
            total += albedo[grid_pos].byte_size()
        return total


var _document: SaDocument


func _init(document: SaDocument) -> void:
    _document = document


## *owner*'s mask, or null when it has none. The owner is a layer or a record,
## which share no type, so the mask is asked for by name.
static func mask_of(owner: Object) -> SaMask:
    var held: Variant = owner.get("mask")
    return held if held is SaMask else null


## Whether *command_id* can run on *owner* now: an add on an owner with no mask,
## the other six on one that has a mask. What the menus dim a row by, because a
## dimmed control is how this tree says disabled.
##
## A layer that stores nothing, a background, takes no mask, because it has no
## chunk for the coverage to live in. Apply is a layer's only, because neither a
## group nor a filter's record has paint of its own to apply a mask into, and
## an unlocked layer's only, because applying writes its paint.
static func can(command_id: StringName, owner: Object) -> bool:
    if owner == null:
        return false
    var record := owner is SaAttachedFilter
    if not record and (owner as SaLayer).is_generated():
        return false
    match command_id:
        ADD, ADD_FROM_SELECTION:
            return SaMaskOps.mask_of(owner) == null
        APPLY:
            var layer := owner as SaLayer
            return SaMaskOps.mask_of(owner) != null and not record and not layer.is_group and not layer.is_locked
        DELETE, INVERT, DISABLE, TO_SELECTION:
            return SaMaskOps.mask_of(owner) != null
    return false


## Says in the corner, for Apply Mask, that each layer of *owners* holding a
## mask is locked when it is, and answers whether one was. Applying writes the
## mask into the layer's paint, which a lock keeps as it is, so Apply refuses a
## locked layer as a stroke, Clear and Flatten Filter do. The other six change
## the mask alone and leave the paint, so a lock does not stop them.
static func refuses_locked(command_id: StringName, owners: Array) -> bool:
    if command_id != APPLY:
        return false
    var said := false
    for owner: Object in owners:
        var layer := owner as SaLayer if is_instance_valid(owner) else null
        if layer != null and not layer.is_group and layer.is_locked and SaMaskOps.mask_of(layer) != null:
            SaProblems.refuse("Apply Mask", TranslationServer.translate(SaLayerRefusals.LOCKED) % layer.name)
            said = true
    return said


## Runs *command_id* on *owner*, and answers whether anything happened. Disable
## is a toggle here, which is what a menu row and a chord mean by it.
func run(command_id: StringName, owner: Object) -> bool:
    if SaMaskOps.refuses_locked(command_id, [owner]):
        return false
    if not can(command_id, owner):
        return false
    match command_id:
        ADD:
            return add(owner)
        ADD_FROM_SELECTION:
            return add_from_selection(owner)
        DELETE:
            return remove(owner)
        APPLY:
            return apply(owner)
        INVERT:
            return invert(owner)
        DISABLE:
            return set_enabled(owner, not SaMaskOps.mask_of(owner).enabled)
        TO_SELECTION:
            return to_selection(owner)
    return false


## A mask that hides nothing yet. A layer's is the field of its own chunks, a
## group's holds chunks of its own, which is the one place the two forms are
## chosen between.
func add(owner: Object) -> bool:
    if not can(ADD, owner):
        return false
    var before := Shape.new(owner, false)
    _give_mask(owner, 1.0)
    _record("Add Mask", owner, before)
    return true


## A mask that shows what the selection selects and hides the rest. With no
## selection everything is selected, so the mask hides nothing.
##
## The selection's chunks are copied texel for texel, both being `R32_SFLOAT` on
## the same grid. Where it holds none the mask is zero, because unselected is
## hidden. A layer's mask is written at every chunk the layer holds and rests
## at zero, so a chunk the layer allocates later opens hidden. A group's
## and a record's rest at zero and hold a chunk only where the selection does,
## which was a chunk of zeros at every position of the canvas.
func add_from_selection(owner: Object) -> bool:
    if not can(ADD_FROM_SELECTION, owner):
        return false
    var before := Shape.new(owner, false)
    if mask_from_selection(owner) == null:
        _give_mask(owner, 1.0)
    _record("Add Mask from Selection", owner, before)
    return true


## The mask `add_from_selection` gives *owner* under an active selection, made
## with no history step of its own and answered, or null and no mask with
## nothing selected. For a caller whose own step keeps the owner and so the
## mask with it: `SaFilterOps.attach` and `SaFilterConversion.add_holding` give
## the record they make the selection as its mask this way, so an attached
## filter and the Layer way's adjustment layer keep to it as Bake does, and
## undo takes the record and its mask off together. The record's mask and not
## the adjustment layer's, because a layer with a mask of its own cannot become
## an attached filter again and a record keeps its mask through that way back.
func mask_from_selection(owner: Object) -> SaMask:
    var selection := _document.selection
    if selection == null or not selection.active:
        return null
    var mask := _give_mask(owner, 0.0)
    for grid_pos: Vector2i in _reach(owner, selection.chunks.keys()):
        var coverage := mask.get_or_create(grid_pos)
        var selected: SaChunk = selection.chunks.get(grid_pos, null)
        if coverage == null:
            continue
        if selected == null:
            coverage.clear(HIDDEN)
        else:
            _copy(selected.field(SaSelection.FIELD), coverage)
    return mask


## Fills *owner*'s mask with *coverage*, grid position to a mask chunk as
## `SaColorRange.coverage` answers it, as one step. An owner with no mask is
## given one first, and one that has a mask has it replaced whole, so the
## step is the mask before and after like the five above it.
##
## Not one of the seven and not in `ALL`, because it needs a colour and a
## fuzziness a menu row cannot carry: the colour range dialog is what calls it.
## A position the coverage does not name is hidden, as an unselected one is in
## `add_from_selection`, and an own mask says so by its rest rather than by a
## chunk of zeros, so it drops what it held outside the coverage first.
func from_color_range(owner: Object, coverage: Dictionary[Vector2i, SaChunk]) -> bool:
    if owner == null or coverage.is_empty():
        return false
    if not owner is SaAttachedFilter and (owner as SaLayer).is_generated():
        return false
    var before := Shape.new(owner, false)
    var mask: SaMask = SaMaskOps.mask_of(owner) if SaMaskOps.mask_of(owner) != null else _give_mask(owner, 0.0)
    if mask.is_own():
        for grid_pos: Vector2i in mask.grid_positions():
            if not coverage.has(grid_pos):
                mask.set_chunk(grid_pos, null)
    mask.rest = 0.0
    for grid_pos: Vector2i in _reach(owner, coverage.keys()):
        var target := mask.get_or_create(grid_pos)
        if target == null:
            continue
        var chosen: SaChunk = coverage.get(grid_pos, null)
        if chosen == null:
            target.clear(HIDDEN)
        else:
            _copy(chosen.field(SaSelection.FIELD), target)
    _record("Mask from Colour Range", owner, before)
    return true


## The owner of *mask* in *document*: the layer or group whose mask it is, or
## the attached filter's record that holds it. Null for a mask nothing of the
## document holds. What the fill keys ask of `SaDocument.mask_target`, which
## names the mask and not what holds it.
static func owner_of(document: SaDocument, mask: SaMask) -> Object:
    var holder := mask.holder_in(document) if mask != null and document != null else null
    if holder == null:
        return null
    if holder.mask == mask:
        return holder
    for record: SaAttachedFilter in holder.filters:
        if record.mask == mask:
            return record
    return null


## Fills *owner*'s mask with the coverage *color* paints into a mask, inside the
## selection or over the whole mask with nothing selected, as one step. The
## coverage is the one a brush on the mask takes from the same colour: its
## lightness in the document's own numbers, white showing and black hiding,
## which is also why the greyed pair shows what the fill will write.
func fill_with(owner: Object, color: Color) -> bool:
    var space := _document.color_space
    var value := clampf(space.lightness(space.from_display(color)) if space != null else color.v, 0.0, 1.0)
    return fill(owner, value, "Fill Mask")


## Hides what the selection selects, or the whole owner with nothing selected,
## as Krita's clear of a transparency mask does, as one step.
func clear(owner: Object) -> bool:
    return fill(owner, HIDDEN.r, "Clear Mask")


## Fills *owner*'s mask with *value*, a coverage from 0 to 1, as one step named
## *action_name*, the mask before and after like the steps above it. The
## owner's paint is never read or written.
##
## An adjustment or an effect layer with no mask is given one here, shown
## everywhere, inside the same step, because its mask is the one thing of it
## the keys can write: undo takes the added mask away with the fill. Any other
## owner with no mask answers false.
##
## With nothing selected the whole mask takes the value, which is a rest and no
## chunk: every chunk it held goes back to the rest, so a fill allocates
## nothing and a layer's chunk allocated later opens at the value too.
##
## Under a selection `fill_under` mixes each chunk toward the value by what the
## selection holds there, at the positions the selection holds a chunk. A paint
## layer's mask is reached at the chunks the layer holds, as `invert` reaches
## it: a position with no paint has nothing to hide and keeps reading the rest,
## the limit `add_from_selection` has as well. A mask of its own, a group's, a
## record's, an adjustment's or an effect's, is reached wherever the selection
## holds a chunk inside the canvas.
##
## False, with no step, when the fill would change nothing: a mask that already
## rests at the value and holds no chunk, or a selection that reaches no chunk
## of the mask. The fill keys read that false as a key that did nothing.
func fill(owner: Object, value: float, action_name: String) -> bool:
    var mask: SaMask = SaMaskOps.mask_of(owner)
    if mask == null and not SaMaskOps.stores_no_paint(owner):
        return false
    var selection := _document.selection
    var whole := selection == null or not selection.active
    var reached: Array[Vector2i] = []
    if not whole:
        for grid_pos: Vector2i in _reach(owner, selection.chunks.keys()):
            if selection.chunks.has(grid_pos):
                reached.append(grid_pos)
        if reached.is_empty():
            return false
    elif mask != null and is_equal_approx(mask.rest, value) and mask.grid_positions().is_empty():
        return false
    var before := Shape.new(owner, false)
    if mask == null:
        mask = _give_mask(owner, 1.0)
    if whole:
        mask.rest = value
        for grid_pos: Vector2i in mask.grid_positions():
            mask.set_chunk(grid_pos, null)
        _record(action_name, owner, before)
        return true
    for grid_pos: Vector2i in reached:
        var selected: SaChunk = selection.chunks[grid_pos]
        var coverage := mask.get_or_create(grid_pos)
        if coverage == null:
            continue
        var params := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, value, 0.0, 0.0, 0.0, 0.0, 0.0, coverage.size.x, coverage.size.y])
        var bindings: Dictionary[int, SaTexture] = {SaSelection.BINDING_SELF: selected.field(SaSelection.FIELD)}
        selection.dispatch("fill_under", coverage, Rect2i(Vector2i.ZERO, coverage.size), params, bindings)
    _record(action_name, owner, before)
    return true


## Whether *owner* holds no paint of its own, so its mask is the one thing of it
## the fill keys can write: a group, an adjustment layer, an effect layer, whose
## chunks are a cache, or an attached filter's record. Each of them holds a
## mask of its own form, `SaLayer.add_mask` says why, so its mask is reached
## over the canvas rather than at the chunks the owner holds.
static func stores_no_paint(owner: Object) -> bool:
    if owner is SaAttachedFilter:
        return true
    var layer := owner as SaLayer
    return layer != null and (layer.is_group or layer.is_adjustment() or layer.is_effect())


## Takes the mask away without applying it, so the owner shows whole again.
func remove(owner: Object) -> bool:
    if not can(DELETE, owner):
        return false
    var before := Shape.new(owner, false)
    _drop_mask(owner)
    _record("Delete Mask", owner, before)
    return true


## Multiplies the layer's alpha by its mask, in place, and drops the mask, as
## one step. A mask that is switched off reads as one, so applying it drops it
## and leaves the paint as the painter sees it.
##
## The kernel is `mask_chunk`, reading the albedo copy the step keeps for its
## undo and writing the live albedo. A second kernel that read and wrote the
## one texture was the page's plan, and it would have been the same line of
## maths with a second entry in the manifest, for a copy the step makes anyway.
func apply(owner: Object) -> bool:
    if SaMaskOps.refuses_locked(APPLY, [owner]):
        return false
    if not can(APPLY, owner):
        return false
    var before := Shape.new(owner, true)
    var mask: SaMask = SaMaskOps.mask_of(owner)
    if mask.enabled:
        var compute := _document.compositor.get_compute("mask") if _document.compositor != null else null
        for grid_pos: Vector2i in before.albedo:
            var coverage: SaTexture = mask.texture_for(grid_pos)
            var chunk: SaChunk = (owner as SaLayer).chunks.get(grid_pos, null)
            if compute == null or coverage == null or chunk == null:
                continue
            _multiply(compute, chunk.field(SaFieldSpec.ALBEDO), before.albedo[grid_pos].field(SaFieldSpec.ALBEDO), coverage)
            owner.call("mark_unresolved", grid_pos)
    _drop_mask(owner)
    _record("Apply Mask", owner, before, true)
    return true


## One minus the mask. A layer's allocates: a chunk of the layer that held no
## coverage read one and reads zero now, so the pass covers every chunk the
## layer holds, a quarter of an F32 albedo chunk each, 256 KB against 1 MB,
## and flips its rest, so a chunk allocated later opens at the flipped value. A
## group's and a record's flip their rest and the chunks they hold and allocate
## nothing, where they once filled the canvas.
func invert(owner: Object) -> bool:
    if not can(INVERT, owner):
        return false
    var before := Shape.new(owner, false)
    var selection := _document.selection
    var mask: SaMask = SaMaskOps.mask_of(owner)
    mask.rest = 1.0 - mask.rest
    for grid_pos: Vector2i in _reach(owner, mask.grid_positions()):
        var coverage: SaTexture = SaMaskOps.mask_of(owner).get_or_create(grid_pos)
        if coverage == null:
            continue
        var params := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, coverage.size.x, coverage.size.y])
        selection.dispatch("invert", coverage, Rect2i(Vector2i.ZERO, coverage.size), params)
    _record("Invert Mask", owner, before)
    return true


## Puts *source*'s mask on *target*, as one step: moved, so *source* is left
## with none, or with *keep* copied, so both carry the same coverage. The
## target must have no mask of its own and take one, and the two must store at
## one density, because a chunk of a layer at twice the resolution covers a
## quarter of the canvas a plain one does. The Layers docker's mask drag is
## what calls it. The copy is chunk for chunk through `duplicate_chunk`, which
## both forms of a mask answer and take, so a group's mask lands on a layer and
## a layer's on a group.
func transfer(source: SaLayer, target: SaLayer, keep: bool) -> bool:
    if source == null or target == null or source == target or SaMaskOps.mask_of(source) == null:
        return false
    if not can(ADD, target) or source.resolution_scale != target.resolution_scale:
        return false
    var source_before := Shape.new(source, false)
    var target_before := Shape.new(target, false)
    var mask := _give_mask(target, source_before.rest)
    for grid_pos: Vector2i in source_before.chunks:
        mask.set_chunk(grid_pos, source_before.chunks[grid_pos].duplicate_chunk())
    mask.enabled = source_before.enabled
    if not keep:
        _drop_mask(source)
    var source_after := Shape.new(source, false)
    var target_after := Shape.new(target, false)
    _document.modified = true
    _refresh(source, source_before)
    _refresh(target, target_before)
    if _document.history != null:
        var redo := _restore_both.bind(source, source_after, target, target_after)
        var undo := _restore_both.bind(target, target_before, source, source_before)
        var paid := source_before.bytes() + source_after.bytes() + target_before.bytes() + target_after.bytes()
        _document.history.commit_pair("Copy Mask" if keep else "Move Mask", redo, undo, paid)
    return true


## Puts *first_shape* back on *first* and then *second_shape* on *second*, the
## two halves of a transfer's step.
func _restore_both(first: Object, first_shape: Shape, second: Object, second_shape: Shape) -> void:
    _restore(first, first_shape)
    _restore(second, second_shape)


## Switches the mask off or back on. Off, the owner shows whole and the coverage
## is kept for when it comes back.
func set_enabled(owner: Object, value: bool) -> bool:
    if not can(DISABLE, owner) or SaMaskOps.mask_of(owner).enabled == value:
        return false
    _apply_enabled(owner, value)
    var title := "Enable Mask" if value else "Disable Mask"
    _document.history.commit_pair(title, _apply_enabled.bind(owner, value), _apply_enabled.bind(owner, not value))
    return true


## The mask becomes the selection, and undo gives back the selection the painter
## had. The mask reads one where it holds nothing, so the canvas outside its
## chunks is selected, which is what the owner shows there.
##
## Recorded as a pair of whole selections rather than through `SaSelection.Swap`,
## which the page named, because a swap exchanges chunks and bounds and not
## whether a selection is active: a painter with nothing selected would undo
## into a selection that holds nothing, which selects nothing rather than
## everything.
func to_selection(owner: Object) -> bool:
    if not can(TO_SELECTION, owner):
        return false
    var selection := _document.selection
    var old_chunks: Dictionary = selection.chunks
    var old_bounds: Rect2i = selection.bounds
    var old_active: bool = selection.active
    var new_chunks: Dictionary[Vector2i, SaChunk] = {}
    var paid := 0
    for grid_pos: Vector2i in SaLayer.grid_positions(_document.canvas_size):
        var coverage: SaTexture = SaMaskOps.mask_of(owner).texture_for(grid_pos)
        var chunk := selection.make_chunk(0.0 if coverage != null else SaMaskOps.mask_of(owner).rest)
        if coverage != null:
            _copy(coverage, chunk.field(SaSelection.FIELD))
        new_chunks[grid_pos] = chunk
        paid += chunk.byte_size()
    _put_selection(new_chunks, Rect2i(), true)
    var new_bounds := selection.measure_bounds()
    _put_selection(new_chunks, new_bounds, true)
    _document.history.commit_pair(
        "Mask to Selection",
        _put_selection.bind(new_chunks, new_bounds, true),
        _put_selection.bind(old_chunks, old_bounds, old_active),
        paid
    )
    return true


# ---------------------------------------------------------------------------


## Gives *owner* a mask holding *value* everywhere it keeps coverage. A layer
## takes the field form and a group the own form, which `SaLayer.add_mask`
## chooses, and a filter's record the own form, which it holds as a plain
## member. An own mask holds no chunk yet and reads its rest, which *value*
## sets, and a layer's opens every chunk it allocates later at that rest.
func _give_mask(owner: Object, value: float) -> SaMask:
    if owner is SaAttachedFilter:
        var record := owner as SaAttachedFilter
        if record.mask == null:
            record.mask = SaMask.own()
            record.mask.rest = value
        return record.mask
    var mask := (owner as SaLayer).add_mask(value)
    mask.rest = value
    return mask


## Takes the mask off *owner*, and off the brush when the brush was aimed at it,
## because a paint target that outlived its mask would paint into nothing.
func _drop_mask(owner: Object) -> void:
    if SaMaskOps.mask_of(owner) != null and _document.mask_target == SaMaskOps.mask_of(owner):
        _document.mask_target = null
    if owner is SaAttachedFilter:
        (owner as SaAttachedFilter).mask = null
    else:
        (owner as SaLayer).drop_mask()


## Where an operation that writes the whole mask writes it: the chunks a paint
## layer holds, or for an owner that stores no paint, *own*, the
## positions the operation's source names, cut to the canvas. The rest answers
## for every other position, so the canvas is never walked.
func _reach(owner: Object, own: Array) -> Array[Vector2i]:
    var positions: Array[Vector2i] = []
    if SaMaskOps.stores_no_paint(owner):
        var cells := Vector2i(
            ceili(_document.canvas_size.x / float(SaLayer.CHUNK_SIZE)), ceili(_document.canvas_size.y / float(SaLayer.CHUNK_SIZE))
        )
        var canvas := Rect2i(Vector2i.ZERO, cells)
        for grid_pos: Vector2i in own:
            if canvas.has_point(grid_pos):
                positions.append(grid_pos)
        return positions
    positions.assign((owner as SaLayer).chunks.keys())
    return positions


## Commits the change *owner* has just been through as one step, the mask as it
## stood before and as it stands now.
func _record(action_name: String, owner: Object, before: Shape, with_albedo: bool = false) -> void:
    var after := Shape.new(owner, with_albedo)
    _document.modified = true
    _refresh(owner, before)
    if _document.history == null:
        return
    _document.history.commit_pair(
        action_name, _restore.bind(owner, after), _restore.bind(owner, before), before.bytes() + after.bytes()
    )


## Puts *shape* back on *owner*: the mask or its absence, every chunk of
## coverage, the flag, and for apply the albedo. Copies of the copies go back,
## so the shape stays what it was for the next undo or redo.
func _restore(owner: Object, shape: Shape) -> void:
    if not is_instance_valid(owner):
        return
    if shape.mask == null:
        _drop_mask(owner)
    else:
        if SaMaskOps.mask_of(owner) == null:
            if shape.mask.is_own():
                owner.set("mask", shape.mask)
            else:
                owner.call("add_mask", 1.0)
        var live: SaMask = SaMaskOps.mask_of(owner)
        # Before the chunks, because a layer's position that goes back to
        # holding nothing is cleared to the rest.
        live.rest = shape.rest
        for grid_pos: Vector2i in live.grid_positions():
            if not shape.chunks.has(grid_pos):
                live.set_chunk(grid_pos, null)
        for grid_pos: Vector2i in shape.chunks:
            live.set_chunk(grid_pos, shape.chunks[grid_pos].duplicate_chunk())
        live.enabled = shape.enabled
    for grid_pos: Vector2i in shape.albedo:
        var chunk: SaChunk = (owner as SaLayer).chunks.get(grid_pos, null)
        if chunk == null:
            continue
        _copy(shape.albedo[grid_pos].field(SaFieldSpec.ALBEDO), chunk.field(SaFieldSpec.ALBEDO))
        owner.call("mark_unresolved", grid_pos)
    _document.modified = true
    _refresh(owner, shape)


func _apply_enabled(owner: Object, value: bool) -> void:
    if not is_instance_valid(owner) or SaMaskOps.mask_of(owner) == null:
        return
    SaMaskOps.mask_of(owner).enabled = value
    _document.modified = true
    _refresh(owner, null)


func _put_selection(chunks: Dictionary, bounds: Rect2i, active: bool) -> void:
    var selection := _document.selection
    # A step that leaves no chunks leaves no selection.
    selection.active = active and not chunks.is_empty()
    selection.chunks = chunks
    # After the chunks, because writing bounds rebuilds the per-chunk boxes from
    # whatever `chunks` holds at that moment.
    selection.bounds = bounds
    selection.changed.emit()


## Marks what the owner draws dirty, and for a mask of its own the chunks the
## mask held before as well, which is the only record of where a group's mask
## was once it is gone. A filter's record names no node, so what it draws is
## the chunks its mask held before and holds now, and nothing is isolated or
## released by it: a record isolates its group by being attached, mask or not.
func _refresh(owner: Object, shape: Shape) -> void:
    var record := owner is SaAttachedFilter
    if not record and (owner as SaLayer).is_group:
        # A mask isolates a pass-through group, so adding or dropping one
        # changes the walk and not only the chunks, which is `_apply_isolated`'s
        # refresh in `SaLayerOps` and for the same reason.
        _document.invalidate_all_allocated_chunks()
        _document.update_caches()
        _document.document_changed.emit()
        return
    if record:
        # The chain leaves the touch to whoever changes a record's mask, so
        # the chain tries a record it failed to build once more.
        (owner as SaAttachedFilter).touch()
    else:
        SaLayerStack.invalidate_layer_chunks(_document, owner as SaLayer)
    var moved: Array = []
    if SaMaskOps.mask_of(owner) != null and SaMaskOps.mask_of(owner).is_own():
        moved.append_array(SaMaskOps.mask_of(owner).grid_positions())
    if shape != null:
        moved.append_array(shape.chunks.keys())
    if not moved.is_empty():
        _document.invalidate_chunks(moved)
    _document.request_cache_update()
    _document.document_changed.emit()


## *source*'s alpha times *coverage* into *target*, over the whole chunk.
static func _multiply(compute: SaCompute, target: SaTexture, source: SaTexture, coverage: SaTexture) -> void:
    if target == null or source == null:
        return
    compute.use_storage_format(target.format)
    compute.set_texture(0, target.rid)
    compute.set_texture(1, source.rid)
    compute.set_texture(2, coverage.rid)
    compute.set_push_constant_float_array(PackedFloat32Array([0.0, 0.0, target.size.x, target.size.y]))
    compute.dispatch_kernel("mask_chunk", SaCompute.groups_for(target.size.x), SaCompute.groups_for(target.size.y), 1)


## A VRAM copy of *source* into *target*, over what the two share. Both the same
## format, which a mask and a selection chunk are by choice and two albedo
## textures of one layer are by construction.
static func _copy(source: SaTexture, target: SaTexture) -> void:
    var rd := GlobalShaderCompiler.get_rd()
    if rd == null or source == null or target == null:
        return
    var extent := Vector3(mini(source.size.x, target.size.x), mini(source.size.y, target.size.y), 1)
    rd.texture_copy(source.rid, target.rid, Vector3.ZERO, Vector3.ZERO, extent, 0, 0, 0, 0)
    SaTexture.note_copy(target.bytes)
