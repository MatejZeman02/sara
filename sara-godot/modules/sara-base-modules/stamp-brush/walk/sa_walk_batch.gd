## What a frame's walks settle once for every dab they paint: the options the
## dynamics look up by name, the paper and what the settings answer, and what they
## gather and send once, the dirty rectangles into one commit and the plain dabs
## into one dispatch a chunk.
##
## A small tip is where this matters. The walk paints a dab every half pixel or
## so whatever the tip, so a Pencil at 8 px paints thirty dabs over the event a
## 128 px one paints two in, and paying these for each of the thirty leaves the pen
## behind. `scenarios/a-small-brush-keeps-up-with-the-pen.json` measures it.
##
## **The dispatches.** A plain dab is held as a record, its push constant and its
## box, and the walk's end sends each chunk's records as one dispatch of
## `dabs.gmacs`, which runs them at every texel in the order they were laid. That
## order is what the barrier `SaPaintContext.dispatch_batch` puts between two
## images symmetry lays on one chunk kept, so the held images need none.
##
## **What is not held is dispatched at once**: a dab whose bindings move from dab
## to dab (the smudge's carry, a pipe's cell, the masking brush's block) and a dab
## painting straight into a layer or a mask. The brush sends what the walk held
## before such a dab, so the card paints in the order the walk laid.
##
## **Once a frame, not once an event.** A pen reports several times a frame, and a
## smudge that sent each report would grow the stroke's snapshot into a new
## texture each time. So [method close] holds what its walk laid, and the frame's
## first walk asks for `process_frame`, which comes after the input and before the
## easel composites, to send it all as one list and commit it once. The options
## and paper are settled from a frame's first walk to its flush, so a change
## between two walks is read at the next frame. A dab outside a walk, the press's
## first and the airbrush's, commits on its own. The lift sends at once through
## [method flush], before the stroke is committed, and so does a reset.
class_name SaWalkBatch
extends RefCounted

const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")

## Floats a held dab's record takes, `SA_DAB_RECORD` in `dabs.gmacs`: the
## dab's push constant, then the width and height in texels of the box its own
## dispatch would have covered.
const RECORD_FLOATS: int = SaDabGeometry.PUSH_FLOATS + 2
## Where `dabs.gmacs` reads the records, after the ten bindings it shares with
## `dab.gmacs`.
const RECORDS_BINDING: int = 10
## Where `SaDabGeometry.pack` puts the dab's centre, the corner the kernel
## writes from and the dab's sequence in its block, which [method Reads.record]
## and [method Reads.placed] write onto a block packed for another dab.
const CENTER_INDEX: int = 0
const CORNER_INDEX: int = 2
const SEQUENCE_INDEX: int = 21
## The records a walk holds before it sends them and holds afresh. Every texel
## of a chunk's box runs through every record the chunk holds, so a long flick
## of a small tip is a few dispatches rather than one whose texels each test a
## thousand boxes they are not in.
const MOST_RECORDS: int = 256


## One chunk's held dabs, which go as one dispatch.
class Held:
    extends RefCounted

    var texture: SaTexture = null
    ## The selection over the chunk, `SaPaintContext.Target.mask`.
    var mask: SaTexture = null
    var records := PackedFloat32Array()
    ## The union of the held dabs' boxes, in the chunk's texels, which is the
    ## box the dispatch covers.
    var box := Rect2i()

    func _init(target: SaPaintContext.Target) -> void:
        texture = target.texture
        mask = target.mask


## What a frame's walks read off the brush's settings and no dab changes, read
## when the first dab asks rather than once a dab and kept to the frame's
## flush, and the answers a dab asks again of what the walks hold still, kept
## from the dab that asked first, so each dab reads the number it read before.
## Outside a walk [method SaWalkBatch.reads] makes one for each ask, so the
## press's dab and the airbrush's read the settings as they stand.
class Reads:
    extends RefCounted

    ## `background_color`, the colour Mix blends towards, or black.
    var background: Color = Color.BLACK
    ## Whether the brush is in wash rather than build-up, [method washing_of].
    var washing: bool = false
    ## The stroke opacity a build-up dab carries, read only when not washing.
    var opacity: float = 1.0
    ## The Hardness row, before the option reads the sensors.
    var hardness: float = 1.0
    ## The bar's spacing, which the tip is given.
    var spacing: float = 0.1
    ## The Flow row clamped to 0 to 1, as the push constant takes it.
    var flow: float = 1.0
    ## The sharpness's softness, clamped the same way.
    var sharpness_softness: float = 0.0
    ## Milliseconds between airbrush dabs, `SaDabCadence.interval_for`.
    var interval: float = -1.0
    ## Whether the step's travel gate is on, which Ignore Spacing turns off.
    var spaced: bool = true
    ## Texels to a document pixel on the layer painted, 2.0 at Double
    ## Resolution, which `SaSmallDab` reads to keep a finer layer out of the
    ## pixel mode.
    var density: float = 1.0

    var _settings: Resource = null
    var _pattern: SaDabPattern = null
    ## The last [method picked], by the colour and the space it was asked of.
    var _picked_known: bool = false
    var _picked_from := Color()
    var _picked_in: SaColorSpace = null
    var _picked := Color()
    ## The last [method strength_for], by the strength it was asked of.
    var _strength_from: float = -1.0
    var _strength: float = 0.0
    ## The last [method offset_for], by the chunk and the chunk size.
    var _offset_at := Vector2i.ZERO
    var _offset_size: int = 0
    var _offset := Vector2.ZERO
    ## The last [method goes_alone] of a dab that does not smudge, by the tip,
    ## the mask and the masking block it was asked of.
    var _alone_known: bool = false
    var _alone_tip: Resource = null
    var _alone_mask: SaBrushTipMask = null
    var _alone_masking: Resource = null
    var _alone: bool = false
    ## The last [method step_for], by the tip, the three of its numbers the
    ## brush writes from dab to dab that the step reads, and the scale.
    var _step: SaStrokeDistance.Spacing = null
    var _step_tip: Resource = null
    var _step_diameter: float = 0.0
    var _step_spacing: float = 0.0
    var _step_ratio: float = 0.0
    var _step_scale: float = 0.0
    ## The block of the last [method record], by every number it was packed
    ## from but the sequence, and what [member pack] places it with.
    var _record := PackedFloat32Array()
    var _record_tip: Resource = null
    var _record_diameter: float = NAN
    var _record_extent := Vector2(NAN, NAN)
    var _record_color := Color()
    var _record_radians: float = 0.0
    var _record_fade := Vector2.ZERO
    var _record_flow: float = 0.0
    var _record_mode: int = 0
    var _record_locked: bool = false
    var _record_sharpness: float = 0.0
    var _record_strength: float = 0.0
    var _record_mirror: int = 0
    ## The last [method packing], by the chunk size and the stroke it was bound to.
    var _pack := Callable()
    var _pack_size: int = 0
    var _pack_info: SaStrokeInfo = null

    func _init(settings: Resource, pattern: SaDabPattern, layer_density: float = 1.0) -> void:
        _settings = settings
        _pattern = pattern
        density = layer_density
        background = settings.background_color if "background_color" in settings else Color.BLACK
        washing = washing_of(settings)
        opacity = 1.0 if washing else settings.opacity
        hardness = settings.hardness.raw()
        spacing = settings.spacing
        flow = clampf(settings.flow.raw(), 0.0, 1.0)
        sharpness_softness = clampf(settings.sharpness_softness, 0.0, 1.0)
        interval = SaDabCadence.interval_for(settings)
        spaced = not SaDabCadence.ignores_spacing(settings)

    ## Whether *settings* is in wash rather than build-up, read through `in`
    ## because the eraser and the scratchpad hand the brush whatever settings
    ## resource they were built with, and a suite that constructs one by hand
    ## may hand it the resource that predates the field.
    static func washing_of(settings: Resource) -> bool:
        if not "painting_mode" in settings:
            return false
        return int(settings.painting_mode) == 1

    ## *shifted* in the document's numbers, `SaColorSpace.from_display` in
    ## *space*, or *shifted* itself with no space.
    func picked(shifted: Color, space: SaColorSpace) -> Color:
        if _picked_known and shifted == _picked_from and space == _picked_in:
            return _picked
        _picked = space.from_display(shifted) if space != null else shifted
        _picked_known = true
        _picked_from = shifted
        _picked_in = space
        return _picked

    ## `SaDabPattern.strength_for` of the paper the frame holds.
    func strength_for(dab_strength: float) -> float:
        if dab_strength == _strength_from:
            return _strength
        _strength = _pattern.strength_for(dab_strength, _settings)
        _strength_from = dab_strength
        return _strength

    ## `SaDabPattern.offset_for` *target*, whose phase is the stroke's and
    ## whose offset the settings name, so a chunk answers what it answered.
    func offset_for(target: SaPaintContext.Target, chunk_size: int, info: SaStrokeInfo) -> Vector2:
        if target.grid_pos == _offset_at and chunk_size == _offset_size:
            return _offset
        _offset = SaDabPattern.offset_for(target, chunk_size, _settings, info)
        _offset_at = target.grid_pos
        _offset_size = chunk_size
        return _offset

    ## [method SaWalkBatch.goes_alone] for *dab*. A smudge always goes now,
    ## and the rest is the tip's picture, the mask's and the masking block's,
    ## none of which a held dab moves.
    func goes_alone(dab: SaDabParams, tip: Resource, mask: SaBrushTipMask, masking: Resource) -> bool:
        if dab.smudge:
            return true
        if _alone_known and tip == _alone_tip and mask == _alone_mask and masking == _alone_masking:
            return _alone
        _alone = SaWalkBatch.goes_alone(dab, tip, mask, masking)
        _alone_known = true
        _alone_tip = tip
        _alone_mask = mask
        _alone_masking = masking
        return _alone

    ## The step a dab of *tip* asks for with the spacing option at
    ## *extra_scale*, `SaDabCadence.spacing_for`. The step reads the tip's
    ## diameter, ratio and spacing, its angle and its auto spacing, and the
    ## brush writes the first three a dab and none of the rest, so a dab
    ## asking with the same three and the same scale is answered the step
    ## before, which is kept here and nobody writes.
    func step_for(tip: Resource, extra_scale: float) -> SaStrokeDistance.Spacing:
        var brush_tip: SaBrushTipScript = tip
        if (
            _step != null
            and tip == _step_tip
            and brush_tip.diameter == _step_diameter
            and brush_tip.spacing == _step_spacing
            and brush_tip.ratio == _step_ratio
            and extra_scale == _step_scale
        ):
            return _step
        _step = SaDabCadence.spacing_for(tip, extra_scale, spaced, SaSmallDab.enters_mode(_settings, density))
        _step_tip = tip
        _step_diameter = brush_tip.diameter
        _step_spacing = brush_tip.spacing
        _step_ratio = brush_tip.ratio
        _step_scale = extra_scale
        return _step

    ## The block `SaDabPacking.pack_dab_params` packs for *dab* with these
    ## numbers, its flow, sharpness and paper read as the brush reads them, the
    ## mirror the dab answered written over the tip's, and the target's three
    ## left at nought for [method placed]. A dab whose numbers are the dab
    ## before's, all but its sequence, is given that dab's block with its own
    ## sequence written on. Of the tip the block reads its shape, generator,
    ## spikes, edges, density and randomness, which nobody writes on the
    ## stroke's own copy, and its diameter, which the brush writes a dab and is
    ## compared here. The block is this one's own, so a caller places a copy.
    func record(
        tip: Resource,
        dab: SaDabParams,
        color: Color,
        half_extent: Vector2,
        radians: float,
        fade: Vector2,
        mode: int,
        locked: bool,
        mirror: int,
        sequence: float
    ) -> PackedFloat32Array:
        var brush_tip: SaBrushTipScript = tip
        var dab_flow := flow * dab.flow
        var sharpness := clampf(dab.sharpness, 0.0, 1.0)
        var strength := strength_for(dab.pattern_strength)
        if (
            half_extent == _record_extent
            and brush_tip.diameter == _record_diameter
            and tip == _record_tip
            and color == _record_color
            and radians == _record_radians
            and fade == _record_fade
            and dab_flow == _record_flow
            and mode == _record_mode
            and locked == _record_locked
            and sharpness == _record_sharpness
            and strength == _record_strength
            and mirror == _record_mirror
        ):
            _record[SEQUENCE_INDEX] = sequence
            return _record
        _record = SaDabPacking.pack_dab_params(
            Vector2.ZERO,
            Vector2.ZERO,
            color,
            half_extent,
            radians,
            fade,
            dab_flow,
            mode,
            locked,
            tip,
            sharpness,
            sharpness_softness,
            sequence,
            strength,
            Vector2.ZERO,
            SaSmallDab.mode_diameter(_settings, brush_tip.diameter, density)
        )
        _record[SaDabGeometry.MIRROR_INDEX] = float(mirror)
        _record_tip = tip
        _record_diameter = brush_tip.diameter
        _record_extent = half_extent
        _record_color = color
        _record_radians = radians
        _record_fade = fade
        _record_flow = dab_flow
        _record_mode = mode
        _record_locked = locked
        _record_sharpness = sharpness
        _record_strength = strength
        _record_mirror = mirror
        return _record

    ## [method placed] of the last [method record] at *chunk_size* for *info*,
    ## the packing a held dab hands `hold`. Bound again only when the two
    ## change, so once a frame for a walk's dabs rather than a closure a dab.
    func packing(chunk_size: int, info: SaStrokeInfo) -> Callable:
        if not _pack.is_valid() or chunk_size != _pack_size or info != _pack_info:
            _pack = _placed_last.bind(chunk_size, info)
            _pack_size = chunk_size
            _pack_info = info
        return _pack

    ## A copy of *block*, a [method record], for *target*: the target's own
    ## centre rather than the dab's, because symmetry hands back one target per
    ## image of the dab, the corner its box starts at, and the paper's offset.
    func placed(
        block: PackedFloat32Array, target: SaPaintContext.Target, chunk_size: int, info: SaStrokeInfo
    ) -> PackedFloat32Array:
        var data := block.duplicate()
        var offset := offset_for(target, chunk_size, info)
        data[CENTER_INDEX] = target.local_center.x
        data[CENTER_INDEX + 1] = target.local_center.y
        data[CORNER_INDEX] = target.render_offset.x
        data[CORNER_INDEX + 1] = target.render_offset.y
        data[SaDabPacking.PATTERN_OFFSET_X_INDEX] = offset.x
        data[SaDabPacking.PATTERN_OFFSET_Y_INDEX] = offset.y
        return data

    func _placed_last(target: SaPaintContext.Target, chunk_size: int, info: SaStrokeInfo) -> PackedFloat32Array:
        return placed(_record, target, chunk_size, info)


var _dynamics: SaDynamics = null
var _pattern: SaDabPattern = null
## Whether a walk is painting, which is when a dab's dirty rectangles wait in
## [member _unsent] for its end and a plain dab waits in [member _held].
var _open: bool = false
var _unsent: SaPaintContext = null
## The settings the open walk paints under, whose paper a send binds.
var _settings: Resource = null
## `dabs.gmacs`, made at the first send.
var _compute: SaCompute = null
## Where a send puts the records, sized for [constant MOST_RECORDS] once and
## rewritten in place.
var _records: SaCompute.Buffer = null
## The held dabs by the RID of the chunk they paint, in the order the chunks
## were first reached.
var _held: Dictionary[RID, Held] = {}
## The chunk the last held dab reached, which the next one most often reaches
## too, and null once a send has sent what it held.
var _last_held: Held = null
## Records held across every chunk.
var _record_count: int = 0
## The chunks each held dab reached, which the ledger is told at the send, when
## the dab reaches the card.
var _targets := PackedInt32Array()
## The largest paper strength a held dab asked for, because the paper is bound
## once for all of them and a strength of nought binds none.
var _strength: float = 0.0
## What binds the tip for a send, [method close]'s *bind*, kept for the frame's.
var _bind := Callable()
## What [method flush] runs after the walks' dabs: the brush's smudge send.
var _then := Callable()
## Whether the frame's `process_frame` is already asked for.
var _armed: bool = false
## The context the open walk's dabs share, which [method paint_for] aims at
## each in turn, and null between two walks.
var _aimed: SaPaintContext = null
## What the frame's walks read once, made at the first [method reads], and
## null after the flush.
var _reads: Reads = null
## Whether the frame's walks hold the dynamics and the paper, from its first
## [method open] to its [method flush].
var _holding: bool = false


## *then* is run at every [method flush], after the frame's dabs are sent and
## committed, and is the brush's own smudge send.
func _init(dynamics: SaDynamics, pattern: SaDabPattern, then := Callable()) -> void:
    _dynamics = dynamics
    _pattern = pattern
    _then = then


## Builds `dabs.gmacs` at *format* ahead of the first stroke, the way
## `StateBrush.warm_at` builds `dab.gmacs`, so the first walk's send does not
## wait for a compile.
static func warm(format: int) -> void:
    SaCompute.new("dabs").use_storage_format(format)


## Whether *dab* has to be dispatched now rather than held for its walk's end,
## because something it binds moves from dab to dab: the smudge's carry, a
## pipe's cell or the masking brush's block. *mask* is the one the brush bound
## last, and a *tip* it is not for yet is loaded by a dab that goes now.
static func goes_alone(dab: SaDabParams, tip: Resource, mask: SaBrushTipMask, masking: Resource) -> bool:
    var wanted: String = tip.image_path if tip.uses_image() else ""
    var masked: bool = masking != null and masking.has_method("active") and masking.active()
    return dab.smudge or masked or mask == null or mask.path != wanted or mask.has_pipe()


## Opens the walk about to paint under *settings*, and settles the dynamics
## and the paper when it is the frame's first or its brush is another.
func open(settings: Resource) -> void:
    if not _holding or settings != _settings:
        _dynamics.hold()
        _pattern.hold(settings)
        _reads = null
        _holding = true
    _settings = settings
    _open = true


## Ends the walk [method open] opened and leaves what it held, its dabs, its
## dirty rectangles and what it settled, for the frame's [method flush]. *bind* is
## [method send]'s.
func close(bind: Callable = Callable()) -> void:
    _open = false
    _aimed = null
    _bind = bind
    later()


## Asks for this frame's [method flush] at `process_frame`, once however many
## events ask. With no tree to ask, as in a suite with no main loop, it
## flushes now.
func later() -> void:
    if _armed:
        return
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        flush()
        return
    _armed = true
    tree.process_frame.connect(_on_frame, CONNECT_ONE_SHOT)


## Sends what the frame's walks held, commits their dirty rectangles and runs
## the brush's smudge send, now. The lift calls it before the stroke is
## committed, and `process_frame` calls it once a frame.
func flush() -> void:
    send(_bind)
    if _unsent != null:
        _unsent.commit_invalidation()
    _unsent = null
    _reads = null
    if _holding:
        _pattern.release()
        _dynamics.release()
        _holding = false
    if _then.is_valid():
        _then.call()


## The frame's flush, whose ask is used up.
func _on_frame() -> void:
    _armed = false
    flush()


## The paint context for a dab over *region*, what `SaPaintContext.for_region`
## builds with *direct* as both its route and whether it keeps to paint. A walk's
## dabs share one, aimed at each in turn, because building it was a seventh of
## a 2 px Pencil dab. A dab whose context is *kept* past it, the smudge's
## queue, a dab that folds across a pole and a dab outside a walk are given
## one of their own. A *spreading* dab, a blur's, is direct and still reaches a
## chunk the layer has not made yet, because a blur carries paint past its edge.
func paint_for(
    doc: SaDocument, region: Rect2, direct: bool, kept: bool, folds: bool = false, spreading: bool = false
) -> SaPaintContext:
    if not _open or kept or folds:
        return SaPaintContext.for_region(doc, region, direct, 2.0, direct and not spreading, folds)
    if _aimed != null and _aimed.document == doc and _aimed.draw_direct == direct:
        _aimed.aim(region)
        return _aimed
    _aimed = SaPaintContext.for_region(doc, region, direct, 2.0, direct)
    return _aimed


## What a dab painted under *settings* on a layer of *density* reads once a
## frame, the frame's own while a walk paints under them, and one made now
## otherwise.
func reads(settings: Resource, density: float = 1.0) -> Reads:
    if not _open or settings != _settings:
        return Reads.new(settings, _pattern, density)
    if _reads == null or _reads.density != density:
        _reads = Reads.new(settings, _pattern, density)
    return _reads


## Commits *paint*'s dirty rectangles now, or folds them into the walk's while
## one is open. A context over another layer or mask cannot be folded, so the
## walk's are committed and *paint*'s are held in their place. The context
## the walk's dabs share holds every dab's already once it is the walk's.
func invalidate(paint: SaPaintContext) -> void:
    if not _open:
        paint.commit_invalidation()
        return
    if paint == _unsent:
        return
    if _unsent == null:
        _unsent = paint
    elif not _unsent.absorb(paint):
        _unsent.commit_invalidation()
        _unsent = paint


## Holds *paint*'s dab for the walk's end with its dirty rectangles and answers
## true, or holds nothing and answers false when the dab has to go now: outside
## a walk, when *alone* says its bindings move from dab to dab, and when it
## paints straight into a layer or a mask.
##
## *pack* answers a target's push constant, and is asked here rather than at the
## send because it reads the stroke as it stands at this dab. *strength* is the
## dab's paper strength before `SaDabPattern.strength_for`, which is what
## `SaDabPattern.bind` asks. *bind* is [method send]'s, for a walk that has
## held all the records it can.
func hold(paint: SaPaintContext, pack: Callable, strength: float, alone: bool, bind: Callable) -> bool:
    if not _open or alone or paint.draw_direct:
        return false
    var count := paint.targets.size()
    if _record_count + count > MOST_RECORDS:
        send(bind)
    for target in paint.targets:
        var held: Held = _last_held if _last_held != null and _last_held.texture == target.texture else null
        if held == null:
            held = _held.get(target.texture.rid)
        if held == null:
            held = Held.new(target)
            _held[target.texture.rid] = held
        _last_held = held
        var box := Rect2i(Vector2i(target.render_offset), Vector2i(target.groups_x, target.groups_y) * SaPaintContext.WORKGROUP)
        held.box = box if held.records.is_empty() else held.box.merge(box)
        held.records.append_array(paint.dab(pack.call(target), target))
        held.records.append(float(box.size.x))
        held.records.append(float(box.size.y))
    _record_count += count
    _targets.append(count)
    _strength = maxf(_strength, strength)
    invalidate(paint)
    return true


## Sends the held dabs, each chunk's as one dispatch in one compute list, and
## holds nothing afterwards. Nothing held sends nothing.
##
## *bind* binds what every held dab shares onto the kernel it is handed: the
## tip's table and picture, the masking block and the stand-ins, which
## `SaStampBindings.bind` covers. The paper goes on here, over its stand-in.
func send(bind: Callable) -> void:
    if _held.is_empty():
        return
    var records := PackedFloat32Array()
    for held: Held in _held.values():
        records.append_array(held.records)
    if _compute == null:
        _compute = SaCompute.new("dabs")
    if _records == null:
        var room := PackedFloat32Array()
        room.resize(MOST_RECORDS * RECORD_FLOATS)
        _records = SaCompute.Buffer.new(room.to_byte_array())
    _records.update(records.to_byte_array())
    # Settled before the bindings and the list, as `SaPaintContext.dispatch_batch`
    # settles it. One walk paints one layer, so its chunks share a depth.
    var format: int = (_held.values()[0] as Held).texture.format
    _compute.use_storage_format(format)
    if bind.is_valid():
        bind.call(_compute)
    _pattern.bind(_compute, _settings, _strength)
    _compute.set_buffer(RECORDS_BINDING, _records.rid)
    _compute.list_begin(_compute.index_of_kernel("dabs"))
    var first := 0
    for held: Held in _held.values():
        @warning_ignore("integer_division")
        var count := held.records.size() / RECORD_FLOATS
        if held.texture.format == format:
            _compute.set_texture(0, held.texture.rid)
            _compute.set_texture(SaSelection.BINDING, held.mask.rid)
            _compute.set_push_constant_float_array(PackedFloat32Array([held.box.position.x, held.box.position.y, first, count]))
            _compute.list_dispatch(SaCompute.groups_for(held.box.size.x), SaCompute.groups_for(held.box.size.y), 1)
        else:
            push_warning(
                "SaWalkBatch: a chunk is format %d in a walk at %d, so its dabs were skipped." % [held.texture.format, format]
            )
        first += count
    _compute.list_end()
    for reached: int in _targets:
        SaPaintContext.dab_dispatched(reached)
    _held.clear()
    _last_held = null
    _record_count = 0
    _targets.clear()
    _strength = 0.0
