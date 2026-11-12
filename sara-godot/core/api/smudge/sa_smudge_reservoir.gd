## The smudge stage's carry: the paint a stroke has picked up, held on the GPU,
## and the pickup that moves it towards the paint under each dab.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **One colour and one strength per stroke, never read back.** The carry is a
## row of `rgba32f` [SaTexture]: texel 0 is what `dab.gmacs` reads at
## [constant BINDING], the carried colour and in alpha how much of it the dab
## lays, texel 1 is the pickup's own strength, and texel [constant LOAD] how
## much paint the carry holds, which thins a dab over an empty texel.
## `smudge_pickup.gmacs` writes both once per dab, reading the stroke's
## [SaMergedSnapshot], so a colour read to the CPU per dab never happens (hard
## rule 1). The dispatch is one group, because the answer is one colour rather
## than a picture, and the snapshot only ever grows to take in the boxes of the
## dabs that read it (hard rule 2).
##
## **A queue, sent as one list.** The brush queues each smudge dab's pickup
## with [method pick_up] and records the dab itself with [method lay], and
## [method submit] sends what an input event laid under one compute list, with
## a barrier between a pickup and its dab, because two lists a dab and a snapshot
## grown a dab are what a smudge dab's CPU time would go on.
##
## **Three rates.** [member mode] is the brush's own choice. A smearing dab mixes
## the carry towards what it crossed at the pickup rate, so the paint travels
## along the stroke. A dulling dab sets the carry to the mean of the paint under
## it, so nothing is dragged, and the carry's spread about that mean is what the
## pickup kernel leaves in the buffer [member variance] wraps. A blurring dab
## dulls the same way and [member blur] softens the paint under it on a lattice
## the dab reads texel by texel, so a stroke along an edge leaves a ramp across
## it. The carry is then the taller [constant SaSmudgeBlur.CARRY], its first row
## as at the other rates and the lattice below.
##
## **The source** is [member snapshot], the merged composite by default (Krita's
## overlay mode, so a smudge across two layers reads as one surface) or the layer
## being painted when Sample Merged is off.
##
## **The height moves with the colour** when the brush's Move Height is on and
## the layer carries height. Texel 1 then holds, past the strength, the height
## the dab moves the paint towards and the rate it moves it at, and the dab
## reports what it found under itself in the buffer [member exchange] wraps. The
## carry takes from the canvas exactly what it gives back, so a smudge drags a
## ridge along the stroke and the sum of the heights stays what it was.
## [member heights] is the stroke's own [SaStrokeHeights].
##
## Both brush engines hold one of these per stroke, made on the first dab that
## asks for the stage and dropped with the stroke, so its VRAM goes with it (hard
## rule 4). The stamp binds the carry on its `dab` kernel through [method bind],
## and the noise brush binds [method carry_of] on `noise_dab` by the image's name.
class_name SaSmudgeReservoir
extends RefCounted

## Where `dab.gmacs` reads the carry. After the masking buffer at 5, in
## declaration order.
const BINDING: int = 6

## The carry's two texels, two the blur alone writes, the load at
## [constant LOAD], and past it what a mix in the brush's own blend mode
## reads, up to the mark at [constant MET].
const SIZE := Vector2i(MET + 1, 1)

## The texel of row 0 that holds the carry's load, how much paint it has for
## the dab to lay where the layer is empty, `SA_CARRY_LOAD` in
## `smudge_pickup.gmacs`. Past the blur's two, so both carries hold it in one
## place.
const LOAD: int = 4

## The texel of row 0 that marks a meeting with the brush's colour taken in the
## brush's own blend mode, `SA_CARRY_MET` in `smudge_met.gmacs`. The carry's
## own colour, what the pickup found and where it started stand at 5, 6 and 7
## before it, `smudge_pickup.gmacs`'s.
const MET: int = 8

## What the one list a [method submit] sends is counted and timed under. Its
## dispatches still count under `smudge_pickup` and `dab`.
const LIST_LABEL := "smudge/queue"

## Where the pickup's own result goes: after the two images, in declaration
## order.
const BUFFER_BINDING: int = 2

## Where the pickup reads what the last dab found under itself, after the
## variance.
const EXCHANGE_BINDING: int = 3

## Where the dab adds what it finds under itself, after its height at 7.
const DAB_EXCHANGE_BINDING: int = 8

## The one texel of nothing the dab reads while the stage is off, made once and
## shared, so a stroke without the stage costs one bind and no texture.
static var _stand_in: SaTexture = null

## The exchange every dab that moves no height binds, made once and shared for
## the reason [member _stand_in] is. No dab adds to it, because a dab only adds
## where it binds a carry of two texels and a height of its layer's.
static var _exchange_stand_in: SaCompute.Buffer = null

## The carry, two texels. Null only when the device is missing.
var texture: SaTexture = null

## The stroke's copy of what the pickup reads, grown by each dab's box: an
## [SaMergedSnapshot] over the composite, or an [SaLayerSnapshot] over the layer
## being painted.
##
## Typed as the base both share rather than as either one, because the reservoir
## holds whichever it built and the two answer the same four members. A base
## class of their own would make the layer source a mode of the composite's
## copy rather than a second reader beside it.
var snapshot: RefCounted = null

## How many pickups this stroke has dispatched, for a dump and a test that holds
## the count to the dab count rather than trusting one dispatch per dab.
var pickups: int = 0

## How many times the dabs sent so far committed their dirty rectangles, for a
## test that holds a stroke sent a dab at a time to a commit a frame rather
## than one a dab.
var commits: int = 0

## The reach the last pickup sampled, in document texels: the dab's own radius
## times the brush's multiple. Nought until the first pickup.
var reach: float = 0.0

## Which of the stage's rates the stroke is painting at: nought smears,
## one dulls and two blurs, the values the brush's `smudge_mode` carries.
var mode: int = 0

## The pickup's own result, one float: the carry's spread about the paint under
## the last dab, nought when the dab sets the carry and positive while it drags.
var variance: SaCompute.Buffer = null

## What the last dab found under itself, two `uint` sums the dab adds to and
## the pickup reads and clears, so the carry's height never leaves the GPU.
var exchange: SaCompute.Buffer = null

## The stroke's heights when it moves them, or null: Move Height off, a layer
## with no height, or no document. The dab binds the layer's height through it.
var heights: SaStrokeHeights = null

## The lattice a blurring stroke lays through, or null at the other two rates.
## Made on the first pickup at [constant SaSmudgePage.BLURRING], which also
## swaps the carry for the taller one the lattice lives in.
var blur: SaSmudgeBlur = null

## The picture a smearing stroke drags, or null when the brush did not ask for
## one or the stroke is not smearing. Made on the first pickup, which also swaps
## the carry for the taller one the lattice lives in.
var field: SaSmudgeField = null

## The mixes taken in the brush's own blend mode, or null for a brush in Normal
## or Erase, which mixes in the straight line and records nothing more.
var mixed: SaSmudgeMix = null

var _compute: SaCompute = null
var _first: bool = true
## Grid position -> the layer's height [method reach_heights] found for the dab about
## to dispatch.
var _reached: Dictionary = {}

## The dabs queued since the last [method submit], each a [Queued], in the
## order they were laid.
var _queue: Array = []

## The pickup [method pick_up] queued for the dab [method lay] records next,
## empty when the dab picks nothing up.
var _pickup := PackedFloat32Array()

## The lattice [method pick_up] laid out for the same dab, null unless the
## stroke blurs.
var _plan: SaSmudgeBlur.Plan = null

## The lattice [method pick_up] laid out for the same dab, null unless the
## stroke carries a picture.
var _carried_plan: SaSmudgeField.Plan = null

## The brush's colour [method pick_up] was handed for the same dab.
var _own := Color(0.0, 0.0, 0.0, 0.0)

## The gradient map [method pick_up] was handed for the same dab, or null.
var _ramp: SaSmudgeMix.Ramp = null

## Whether the brush reads a picture under its tip rather than the carry's one
## colour. The stamp's dab kernel does and the noise brush's reads texel 0
## alone, so only the first pays for the lattice.
var _carries_picture: bool = false

## The box every queued pickup reaches, in document texels, which the snapshot
## grows to at the submit.
var _wanted: Rect2i = Rect2i()

## The context of the dabs sent since the last commit, the later ones'
## rectangles absorbed into the first's, or null when none waits.
var _held: SaPaintContext = null


## A carry for a stroke on *easel*, starting from nothing, with the snapshot
## taken under *region*, the first dab's box in document texels.
##
## *sample_merged* picks the source: the easel's composite when it is on, and
## *layer*, the layer the stroke is painting, when it is off. A stroke with no
## easel and no layer gets no snapshot and picks nothing up.
##
## *carried* is the stroke's heights when it moves them, which the brush makes
## only when Move Height is on and *layer* carries height, so a smudge never
## gives a layer a height it did not have.
##
## *picture* is the brush saying its dab reads a lattice rather than the carry's
## one colour, which the stamp's does. A smearing stroke then carries the
## picture under its tip, [SaSmudgeField], and a dab lays what stood under each
## of its texels. Off by default, so a caller that never asked pays nothing.
##
## *blend* is the brush's own blend mode, and every mix the stage takes is taken
## in it, through [SaSmudgeMix], unless it is Normal or Erase.
func _init(
    easel: SaEasel,
    layer: SaLayer,
    sample_merged: bool,
    region: Rect2i,
    carried: SaStrokeHeights = null,
    picture: bool = false,
    blend: StringName = SaLayer.BLEND_MODE.NORMAL
) -> void:
    if GlobalShaderCompiler.get_rd() == null:
        return
    heights = carried
    _carries_picture = picture
    texture = SaTexture.new(SIZE)
    texture.clear(Color(0.0, 0.0, 0.0, 0.0))
    variance = SaCompute.Buffer.new(PackedFloat32Array([0.0]).to_byte_array())
    exchange = SaCompute.Buffer.new(PackedInt32Array([0, 0]).to_byte_array())
    if sample_merged:
        if easel != null:
            snapshot = easel.snapshot_merged(region)
    else:
        snapshot = SaLayerSnapshot.new(layer, region)
    _compute = SaCompute.new("smudge_pickup")
    if SaSmudgeMix.wanted(easel, blend):
        mixed = SaSmudgeMix.new(easel, blend)


## Compiles the pickup's kernel at *format*, the depth of a document that has
## just opened, so the first smudge stroke on it finds the build waiting.
##
## The pickup dispatches at its snapshot's depth, which is the document's, and
## the first build of a kernel at a depth costs the compile, about 7 ms here,
## where every later one costs a pipeline at a tenth of a millisecond. The
## compiler keeps the build once made, so the pickup made here is let go at once
## and the stroke's own finds the build in place.
static func warm(format: int) -> void:
    if GlobalShaderCompiler.get_rd() == null:
        return
    SaCompute.new("smudge_pickup").use_storage_format(format)
    SaSmudgeBlur.warm(format)
    SaSmudgeField.warm(format)
    SaSmudgeMix.warm()


## The one texel of nothing the dab reads while the stage is off.
static func stand_in() -> SaTexture:
    if _stand_in == null and GlobalShaderCompiler.get_rd() != null:
        _stand_in = SaTexture.new(Vector2i.ONE)
        _stand_in.clear(Color(0.0, 0.0, 0.0, 0.0))
    return _stand_in


## The carry a dab reads for *reservoir*: its own two texels, or the stand-in
## when the stage is off or the device is missing.
static func carry_of(reservoir: SaSmudgeReservoir) -> SaTexture:
    return reservoir.texture if reservoir != null and reservoir.texture != null else stand_in()


## Binds *reservoir*'s carry at [constant BINDING] on the dab's *compute*, and
## its exchange at [constant DAB_EXCHANGE_BINDING], or the stand-ins when
## *reservoir* is null, because a uniform set has to cover every binding the
## kernel declares whether or not the stage is on.
static func bind(compute: SaCompute, reservoir: SaSmudgeReservoir) -> void:
    var carry := carry_of(reservoir)
    if compute != null and carry != null:
        compute.set_texture(BINDING, carry.rid)
    if _exchange_stand_in == null and GlobalShaderCompiler.get_rd() != null:
        _exchange_stand_in = SaCompute.Buffer.new(PackedInt32Array([0, 0]).to_byte_array())
    var sums := reservoir.exchange if reservoir != null and reservoir.exchange != null else _exchange_stand_in
    if compute != null and sums != null:
        compute.set_buffer(DAB_EXCHANGE_BINDING, sums.rid)


## The heights a smudge stroke on *document* moves, or null. *wanted* is the
## brush's Move Height, already false for a stroke that erases or paints a
## mask, and the active layer has to carry height already: the switch is on by
## default and moves height only where there is some to move.
static func moving(document: SaDocument, wanted: bool) -> SaStrokeHeights:
    if not wanted or document == null or document.active_layer == null:
        return null
    if not document.active_layer.carries_height():
        return null
    return SaStrokeHeights.new(document, document.active_layer)


## Reaches the layer's height under every one of *targets*, the paint
## context's, before the dab's list opens, since `SaStrokeHeights.reach` may
## allocate the height, blank it and snapshot it for undo, and none of that
## may run inside a compute list. Nothing when this carry moves no height.
func reach_heights(targets: Array) -> void:
    _reached.clear()
    if heights == null:
        return
    for target: SaPaintContext.Target in targets:
        var own := heights.reach(target.grid_pos)
        if own != null:
            _reached[target.grid_pos] = own


## The height the dab binds for the chunk at *grid_pos*: the layer's own that
## [method reach_heights] found for this dab, and *otherwise* where it found none.
func height_for(grid_pos: Vector2i, otherwise: SaTexture) -> SaTexture:
    return _reached.get(grid_pos, otherwise)


## Queues the pickup of the dab whose box is *region* and whose centre is
## *centre*, both in document texels, to move the carry towards the paint under
## it when [method submit] sends the queue.
##
## *radius* is how far out the pickup samples, *pickup* how much of the paint it
## finds enters the carry, *keep* the smear length, and *color_rate* how much
## of the brush's own colour the dab then lays beside the carry. *smudge_mode* is which of the stage's rates this
## dab paints at, the brush's own setting and not a per-dab answer. The snapshot
## is asked to take *region* in at the submit, so a stroke that wanders off its
## first chunk still reads what stood there.
##
## **And it takes the reach too.** A pickup wider than the dab samples past the
## dab's own box, and the kernel clamps a sample outside the snapshot to its
## edge, so without the margin the wide pickup would read the stroke's own
## leading edge for most of its disc. The margin is nothing at the dab's own
## radius, because the box already covers that, so a preset at one costs the copy
## it always did.
##
## **A blurring dab lays out its lattice here too**, and the snapshot is asked
## for the Gaussian's reach past it, which is half the pickup's reach past the
## dab's rim. The pickup itself still runs and dulls, so the carry's strength and
## the colour rate mean at this rate what they mean at dulling, and the colour a
## texel lays is the lattice's rather than the carry's mean.
##
## **A smearing dab of a brush that carries a picture lays out its own**, the
## tip's own grid rather than the document's, and the pickup still runs: the
## carry's strength and the colour rate go on meaning what they meant, and the
## colour a texel lays is the cell's under it rather than the mean over the tip.
##
## *own* is the brush's colour on this dab in the document's values, which the
## carry meets in the brush's blend mode ahead of the dab. Its alpha is nought
## where the dab's colour is not one colour across the tip, a gradient map's,
## and the dab then meets the carry in the straight line, unless *ramp* says
## which gradient map it is, met cell by cell where the stroke has a lattice.
func pick_up(
    region: Rect2i,
    centre: Vector2,
    radius: float,
    pickup: float,
    keep: float,
    color_rate: float,
    smudge_mode: int,
    own: Color = Color(0.0, 0.0, 0.0, 0.0),
    ramp: SaSmudgeMix.Ramp = null
) -> void:
    if _compute == null or texture == null or snapshot == null:
        return
    reach = radius
    mode = smudge_mode
    var half := minf(region.size.x, region.size.y) * 0.5
    var wanted := region.grow(ceili(maxf(radius - half, 0.0)))
    if smudge_mode == SaSmudgePage.BLURRING:
        if blur == null:
            blur = SaSmudgeBlur.new()
            texture = SaTexture.new(SaSmudgeBlur.CARRY)
            texture.clear(Color(0.0, 0.0, 0.0, 0.0))
        _plan = SaSmudgeBlur.plan(region, centre, radius)
        wanted = wanted.merge(_plan.wanted())
    elif _carries_picture and smudge_mode == SaSmudgePage.SMEARING:
        if field == null:
            field = SaSmudgeField.new()
            texture = SaTexture.new(SaSmudgeField.CARRY)
            texture.clear(Color(0.0, 0.0, 0.0, 0.0))
        _carried_plan = SaSmudgeField.plan(region, centre, pickup, keep)
        wanted = wanted.merge(_carried_plan.wanted())
    _wanted = wanted if _wanted.size == Vector2i.ZERO else _wanted.merge(wanted)
    _pickup = PackedFloat32Array([centre.x, centre.y, maxf(radius, 0.5), pickup, keep, color_rate, 0.0, float(smudge_mode)])
    _own = own
    _ramp = ramp


## Grows the snapshot to take *region* in now, in document texels, rather than
## at the next [method submit]. A brush calls it before it lays paint the next
## pickup must not find, a preview the brush puts back, so the snapshot holds
## what stood there before the composite shows that paint.
func take_in(region: Rect2i) -> void:
    if snapshot != null:
        _grow_source(region)


## Records the dab of *paint*'s targets on *compute*'s kernel *kernel_name*,
## after the pickup [method pick_up] queued for it if it queued one.
## *dispatcher* binds one target and pushes its block, as it does for
## `SaPaintContext.dispatch_batch`, whose loop this is with a record where that
## one dispatches.
##
## The first target waits for the pickup before it, and a target of a later
## image of a mirrored dab waits for the images before it. Nothing is sent and
## nothing is invalidated until [method submit].
func lay(paint: SaPaintContext, compute: SaCompute, kernel_name: String, dispatcher: Callable) -> void:
    var recorded: Array[SaCompute.Recorded] = []
    if not paint.targets.is_empty():
        var format: int = paint.targets[0].texture.format
        var current_pass := -1
        for target: SaPaintContext.Target in paint.targets:
            if target.texture.format != format:
                continue
            compute.set_texture(SaSelection.BINDING, target.mask.rid)
            dispatcher.call(target)
            var waits := target.pass_index != current_pass
            current_pass = target.pass_index
            var one := compute.record(kernel_name, format, target.groups_x, target.groups_y, 1, waits)
            if one != null:
                recorded.append(one)
    _queue.append(Queued.new(_pickup, recorded, paint, _plan, _carried_plan, _own, _ramp))
    _pickup = PackedFloat32Array()
    _own = Color(0.0, 0.0, 0.0, 0.0)
    _ramp = null
    _plan = null
    _carried_plan = null


## Sends every pickup and dab queued since the last submit as one compute list,
## after the records *first* holds, a barrier between each pickup and the dab that reads its carry and between
## that dab and the next pickup, which writes the carry the dab read.
##
## **One growth for the queue rather than one a dab.** The composite only
## changes when the frame composites, so every cell the queue's dabs reach
## reads the same before the first of them is sent as it did between them,
## and the snapshot grows once to their bounding box. A growth is a new
## texture, and a freed texture drops every uniform set of every kernel, so a
## growth a dab would be the largest part of a smudge dab's cost.
##
## A stroke that paints straight into the layer its snapshot reads does change
## the source between two dabs, and the brush sends that stroke's queue a dab at
## a time.
##
## **The dirty rectangles wait for the frame when *commit* is off.** A dab sent
## alone committed its rectangles alone, and a commit walks the filters'
## spread and the halo of every chunk it names, a millisecond on a deep
## painting with effect layers. That was most of a Blender dab's time there,
## so the walk's share of a frame laid five dabs where the pen asked
## for twenty, the stroke fell seconds behind the pen and the next press laid
## the thousands it owed in one frame. The rectangles only tell the easel what
## to composite, which it reads once a frame, so a dab sent alone keeps them
## with the ones before it and a submit with *commit* on, the brush's own once
## a frame and at the lift, commits them all once.
func submit(commit: bool = true, first: Array[SaCompute.Recorded] = []) -> void:
    if _queue.is_empty():
        if commit:
            _commit_held()
        return
    var queue := _queue
    _queue = []
    var ready := _bind_snapshot()
    var recorded: Array[SaCompute.Recorded] = first.duplicate()
    var dabs := PackedInt32Array()
    for queued: Queued in queue:
        if ready and not queued.pickup.is_empty():
            # Read before the pickup, which is what spends the stroke's first dab.
            var fresh := _first
            var one := _record_pickup(queued.pickup)
            if one != null:
                recorded.append(one)
            var smears := mixed != null and not fresh and mode == SaSmudgePage.SMEARING
            if smears:
                recorded.append_array(mixed.record_carry())
            var lattice := Vector2i.ZERO
            if blur != null and queued.plan != null:
                recorded.append_array(blur.record(queued.plan, _source_rect().position, _source_scale()))
                lattice = queued.plan.count
            if field != null and queued.carried != null:
                var cells := field.record(queued.carried, _source_rect().position, _source_scale(), fresh, smears)
                if cells != null:
                    recorded.append(cells)
                    if smears:
                        recorded.append_array(mixed.record_cells(queued.carried.count))
                lattice = queued.carried.count
            if mixed != null and queued.own.a > 0.0:
                recorded.append_array(mixed.record_meet(queued.own, lattice))
            elif mixed != null and queued.ramp != null and lattice != Vector2i.ZERO:
                recorded.append_array(mixed.record_meet(queued.ramp.colour, lattice, queued.ramp))
        recorded.append_array(queued.dabs)
        if not queued.paint.targets.is_empty():
            dabs.append(queued.paint.targets.size())
    SaCompute.submit(recorded, LIST_LABEL, dabs)
    for queued: Queued in queue:
        _hold(queued.paint)
    if commit:
        _commit_held()


## Keeps *paint*'s dirty rectangles with the ones held before it, or commits
## those first when the two cannot share a commit.
func _hold(paint: SaPaintContext) -> void:
    if _held != null and _held.absorb(paint):
        return
    _commit_held()
    _held = paint


## Commits the dirty rectangles the dabs sent since the last commit left.
func _commit_held() -> void:
    if _held != null:
        _held.commit_invalidation()
        commits += 1
    _held = null


## Grows the snapshot to every pickup queued and binds it, the carry and the
## spread on the pickup's kernel. False when there is nothing to read from.
func _bind_snapshot() -> bool:
    if _compute == null or texture == null or snapshot == null or _wanted.size == Vector2i.ZERO:
        return false
    _grow_source(_wanted)
    _wanted = Rect2i()
    var source := _source_texture()
    if source == null:
        return false
    _compute.use_storage_format(source.format)
    _compute.set_texture(0, source.rid)
    _compute.set_texture(1, texture.rid)
    _compute.set_buffer(BUFFER_BINDING, variance.rid)
    _compute.set_buffer(EXCHANGE_BINDING, exchange.rid)
    if blur != null:
        blur.bind(source, texture)
    if field != null:
        field.bind(source, texture, mixed)
    if mixed != null:
        mixed.bind(texture, field.held if field != null else null)
    return true


## Records one queued pickup, its centre moved into the snapshot's own texels,
## which is only known once the queue's growth has happened.
func _record_pickup(queued: PackedFloat32Array) -> SaCompute.Recorded:
    var params := queued.duplicate()
    # A layer snapshot of a double resolution layer holds its texels, so the
    # centre and the reach are taken into them.
    var scale := _source_scale()
    var origin := _source_rect().position
    params[0] = (params[0] - float(origin.x)) * scale
    params[1] = (params[1] - float(origin.y)) * scale
    params[2] *= scale
    params[6] = 1.0 if _first else 0.0
    _compute.set_push_constant_float_array(params)
    var one := _compute.record("smudge_pickup", _source_texture().format, 1, 1, 1, true)
    if one != null:
        _first = false
        pickups += 1
    return one


## What the carry says about itself, for a state dump.
##
## *variance* is read off the buffer the pickup kernel wrote, which is a result
## the kernel computed and not the canvas, and it is asked for when a dump is
## taken rather than during a stroke. The pixel path never calls this.
func report() -> Dictionary:
    var rect := _source_rect()
    return {
        "pickups": pickups,
        "radius": reach,
        "mode": mode,
        "variance": _last_variance(),
        "picture": _picture_report(),
        "moves_height": heights != null,
        "snapshot": [rect.position.x, rect.position.y, rect.size.x, rect.size.y] if snapshot != null else [],
        "snapshot_copies": _source_copies(),
    }


## The lattice the stroke carries under its tip, its cells along x and y and a
## cell's side in document pixels, or an empty array for a stroke that carries
## one colour. What a dump reads it for is the size of the dispatch a dab pays
## for, which is the tip's grid and never the canvas.
func _picture_report() -> Array:
    if field == null or field.lattice == null:
        return []
    return [field.lattice.count.x, field.lattice.count.y, field.lattice.cell]


## The source's copy, read through whichever of the two classes it is, since
## the member is typed as their common base.
func _source_texture() -> SaTexture:
    if snapshot is SaMergedSnapshot:
        return (snapshot as SaMergedSnapshot).texture
    if snapshot is SaLayerSnapshot:
        return (snapshot as SaLayerSnapshot).texture
    return null


## The document rectangle the source covers, empty without one.
func _source_rect() -> Rect2i:
    if snapshot is SaMergedSnapshot:
        return (snapshot as SaMergedSnapshot).rect
    if snapshot is SaLayerSnapshot:
        return (snapshot as SaLayerSnapshot).rect
    return Rect2i()


## Texels to a document pixel in the source: a layer snapshot's own scale, and
## one for the composite's copy.
func _source_scale() -> float:
    return (snapshot as SaLayerSnapshot).scale if snapshot is SaLayerSnapshot else 1.0


## How many chunk copies the source has made, nought without one.
func _source_copies() -> int:
    if snapshot is SaMergedSnapshot:
        return (snapshot as SaMergedSnapshot).chunk_copies
    if snapshot is SaLayerSnapshot:
        return (snapshot as SaLayerSnapshot).chunk_copies
    return 0


## Grows the source to take *wanted* in.
func _grow_source(wanted: Rect2i) -> void:
    if snapshot is SaMergedSnapshot:
        (snapshot as SaMergedSnapshot).grow(wanted)
    elif snapshot is SaLayerSnapshot:
        (snapshot as SaLayerSnapshot).grow(wanted)


## The one float the pickup kernel last left, or nought before any dab ran or
## on a device that never dispatched one.
func _last_variance() -> float:
    if variance == null:
        return 0.0
    var bytes := variance.read()
    return bytes.decode_float(0) if bytes.size() >= 4 else 0.0


## One dab waiting for the submit: its pickup's push constant, with the centre
## still in document texels and empty when it picks nothing up, the dispatches
## recorded for its targets, its paint context, whose invalidation waits for the
## submit too, the lattice a blurring dab reads, null at the other rates,
## the one a smearing dab that carries a picture drags, null without one, and
## the brush's colour the carry meets in the brush's mode, nought in alpha for
## the straight line, and the gradient map met cell by cell in its place, null
## for none.
class Queued:
    extends RefCounted

    var pickup: PackedFloat32Array
    var dabs: Array[SaCompute.Recorded]
    var paint: SaPaintContext
    var plan: SaSmudgeBlur.Plan
    var carried: SaSmudgeField.Plan
    var own: Color
    var ramp: SaSmudgeMix.Ramp

    func _init(
        queued_pickup: PackedFloat32Array,
        recorded: Array[SaCompute.Recorded],
        context: SaPaintContext,
        lattice: SaSmudgeBlur.Plan = null,
        picture: SaSmudgeField.Plan = null,
        colour: Color = Color(0.0, 0.0, 0.0, 0.0),
        map: SaSmudgeMix.Ramp = null
    ) -> void:
        pickup = queued_pickup
        dabs = recorded
        paint = context
        plan = lattice
        carried = picture
        own = colour
        ramp = map
