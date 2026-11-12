## One stroke of the filter brush: the layer as it was at the press, the
## coverage the stroke has laid, and the filter's result mixed into the layer
## by it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Private to the filter brush's folder, made by `state_filter_brush.gd` at a
## press and committed at the lift.
##
## **Filtered from the press, mixed by coverage.** A chunk the stroke reaches
## is saved whole at its first touch, the way the liquify session saves one,
## and every write into it is the filter run over that saved original, mixed
## into the original by the coverage the stroke has laid there so far. The
## coverage only rises (`filter_brush_coverage.gmacs`), so a dab over a dab
## writes the same texel again from the same original with at most the same
## weight, and nothing is ever filtered from paint the stroke already filtered.
## The saved originals are also the history step, so the stroke is one undo.
##
## **The filter's own kernel does the mixing.** Every filter keeps the
## selection contract, its kernel mixing its result into the texel by the mask
## bound at `SaSelection.BINDING`, so the coverage is bound there in place of
## the selection, the selection having been multiplied into it already. A point
## pass rewrites its texture in place, so the original is copied into the live
## chunk over the region first. A neighbourhood pass reads one texture and
## writes another, so it reads the original and its neighbours through the
## door's `SaNeighbourhoodPass.Runner`, padded by the pass's own reach, and a
## blur's halo is read whole from paint the stroke has not touched.
##
## **Refused before the press paints.** [method evaluate] runs the filter's
## `run` once over the record, as the compositor's chain does, and answers the
## pass it recorded or the sentence that says why the brush cannot paint it: a
## filter no module offers, one that does not compile, one that says it cannot
## be a brush, which a saved brush can still name, one that recorded no pass,
## and one that said yes and records a pass reading the whole layer for every
## texel, whose result under a brush would change everywhere the brush had not
## been.
##
## **Sparse like the layer.** A chunk is saved and written only where the
## brush passes and the layer held paint at the press, or, for a pass that
## reads its neighbours, beside a chunk that did, since a blur carries paint
## over the edge (hard rule 3). Every dispatch covers the stroke's rectangle in
## that chunk, rounded out to whole workgroups (hard rule 2), and nothing is
## read back (hard rule 1).
extends RefCounted

## The history step's name.
const ACTION_NAME: String = "Filter Brush"

## The coverage's storage, one float a texel and never clamped below one.
const COVERAGE_FORMAT: int = RenderingDevice.DATA_FORMAT_R32_SFLOAT

var document: SaDocument = null
## The layer the stroke writes, null once it is committed.
var layer: SaLayer = null
## The filter's pass and the compute it runs through.
var evaluation: Evaluation = null

## Grid position -> SaTexture, the coverage laid there so far, at the chunk's
## side. Only where the stroke has passed.
var coverage: Dictionary = {}

## Grid position -> SaChunkDelta, the whole chunk as it was at its first touch,
## or null where the stroke made the chunk, which the history round-trips as
## "remove it again".
var _before: Dictionary = {}

## Transparent at the chunk's side and format, the original of a chunk the
## stroke made.
var _blank: SaTexture = null
## What a neighbourhood pass writes before its region is copied on, at the
## chunk's side and format, kept for the stroke so a dispatch does not free
## one the card is still writing (`core/api/gpu/sa_texture.gd`).
var _scratch: SaTexture = null

var _runner := SaNeighbourhoodPass.Runner.new()
var _masks := SaFilterDensity.Masks.new()
var _kernels := Kernels.new()


func _init(on: SaDocument, into: SaLayer, evaluated: Evaluation) -> void:
    document = on
    layer = into
    evaluation = evaluated
    _runner.reads_canvas_of(on)


## The filter at *key* in *door*'s registry, or null when no module offers it.
static func filter_of(door: SaContext, key: String) -> SaFilter:
    var named := StringName(key)
    if door == null or door.filters == null or not door.filters.has(named):
        return null
    return door.filters.get_filter(named)


## The pass the filter at *key* in *door*'s registry records over *values*, or
## why the brush cannot paint it, for *node* in *on*. Either may be null, for a
## question asked before any document is open, which every filter's `run`
## answers.
##
## The filter's own values are put back after the run, because the registry
## holds one instance per key and an open dialog of that filter reads them.
static func evaluate(door: SaContext, key: String, values: Dictionary, on: SaDocument, node: SaLayer) -> Evaluation:
    var out := Evaluation.new()
    var filter := filter_of(door, key)
    if filter == null:
        out.refusal = (
            TranslationServer.translate("No installed module offers the filter %s, so the Filter Brush paints nothing.") % key
        )
        return out
    out.title = filter.title()
    var problem := filter.problem()
    if not problem.is_empty():
        out.refusal = TranslationServer.translate("%s cannot run, so the Filter Brush paints nothing. %s") % [out.title, problem]
        return out
    if not filter.can_be_a_brush():
        var says_no := "%s says a brush cannot paint it, so the Filter Brush paints nothing. Choose another filter."
        out.refusal = TranslationServer.translate(says_no) % out.title
        return out
    var shown := filter.parameters()
    filter.set_parameters(values)
    var ctx := SaFilterContext.new(on, node, door.filters.owner_of(StringName(key)), out.title, true)
    filter.run(ctx)
    filter.set_parameters(shown)
    var recorded := ctx.point
    if recorded == null:
        out.refusal = (
            TranslationServer.translate("%s records no pass the Filter Brush can run, so the brush cannot paint it.") % out.title
        )
    elif recorded is SaNeighbourhoodPass and (recorded as SaNeighbourhoodPass).whole():
        var whole := "%s reads the whole layer for every pixel, which a brush cannot paint. Choose another filter."
        out.refusal = TranslationServer.translate(whole) % out.title
    else:
        out.recorded = recorded
        out.compute = ctx.kernel(recorded.shader)
    return out


## Whether the stroke can paint: a layer, a pass and the device's kernels.
func is_open() -> bool:
    return layer != null and is_instance_valid(layer) and evaluation != null and evaluation.ok() and _kernels.ready()


## Lays the path through *points*, in document pixels, a capsule of *radius*
## document pixels between each two and a dab where there is one point, at
## *softness*, then filters every chunk it reached once. *strengths* holds one
## number a point, how much of the filter's result the stroke lays there, the
## opacity times what the pen's pressure gave it, and a capsule runs from its
## first end's to its last's. *soft_tip* is the fade of a brush of the format
## of now, false for the smoothstep alone a brush saved at format nought lays.
func lay(points: PackedVector2Array, strengths: PackedFloat32Array, radius: float, softness: float, soft_tip: bool) -> void:
    if not is_open() or points.is_empty() or radius <= 0.0 or strengths.size() != points.size():
        return
    var strongest := 0.0
    for strength: float in strengths:
        strongest = maxf(strongest, strength)
    if strongest <= 0.0:
        return
    var side := SaFilterDensity.side_of(layer)
    var texels := float(side) / SaChunk.SIZE
    var canvas := Rect2i(Vector2i.ZERO, document.canvas_size)
    # Grid position -> the region of the chunk the path covered, in its
    # texels, aligned, and in document pixels, for the redraw.
    var work: Dictionary = {}
    var regions: Dictionary = {}
    var segments := maxi(1, points.size() - 1)
    for index in segments:
        var from := points[index]
        var last := mini(index + 1, points.size() - 1)
        var to := points[last]
        var low := (from.min(to) - Vector2(radius, radius)).floor()
        var high := (from.max(to) + Vector2(radius, radius)).ceil()
        var reach := Rect2i(Vector2i(low), Vector2i(high - low)).intersection(canvas)
        if reach.size.x <= 0 or reach.size.y <= 0:
            continue
        for grid_pos: Vector2i in SaChunkWalk.positions_in(reach):
            var mask := _masks.at(document.selection.texture_for(grid_pos), side)
            if mask == null or _taken(grid_pos) == null:
                continue
            var local := _aligned(SaChunkWalk.local_rect(grid_pos, reach, side), side)
            if local.size.x <= 0 or local.size.y <= 0:
                continue
            var corner := Vector2(grid_pos * SaChunk.SIZE)
            _kernels.cover(
                _coverage_at(grid_pos, side),
                mask,
                local,
                (from - corner) * texels,
                (to - corner) * texels,
                radius * texels,
                softness,
                Vector2(strengths[index], strengths[last]),
                soft_tip
            )
            var placed := SaChunkWalk.local_rect(grid_pos, reach, SaChunk.SIZE)
            work[grid_pos] = (work[grid_pos] as Rect2i).merge(local) if work.has(grid_pos) else local
            regions[grid_pos] = (regions[grid_pos] as Rect2i).merge(placed) if regions.has(grid_pos) else placed
    for grid_pos: Vector2i in work:
        _filter(grid_pos, work[grid_pos])
        layer.mark_unresolved(grid_pos)
    if not regions.is_empty():
        document.invalidate_chunk_regions(regions, layer)


## Writes the stroke as one history step and lets it go. False when it touched
## nothing, which leaves no step behind.
func commit() -> bool:
    if layer == null or not is_instance_valid(layer) or _before.is_empty():
        _close()
        return false
    var state := _before.duplicate()
    var into := layer
    _close()
    if document.history != null:
        document.record_pixel_step(ACTION_NAME, into, state)
    document.modified = true
    document.document_changed.emit()
    return true


func _close() -> void:
    layer = null
    coverage = {}
    _before = {}


## Saves the chunk at *grid_pos* at its first touch and answers the live chunk,
## or null where the stroke writes nothing: no chunk at the press and no paint
## a neighbourhood pass could carry in.
func _taken(grid_pos: Vector2i) -> SaChunk:
    var live: SaChunk = layer.chunks.get(grid_pos, null)
    if _before.has(grid_pos):
        return live
    if live != null:
        _before[grid_pos] = SaChunkDelta.capture(live, Rect2i(0, 0, live.pixel_size(), live.pixel_size()))
        return live
    if not _carried_into(grid_pos):
        return null
    live = layer.get_or_create_chunk(grid_pos)
    # The chunk's own clear is a transfer, and a kernel writing part of it is
    # not ordered against one, so the whole of it is blanked on the compute
    # queue.
    for field_id: StringName in live.fields:
        if layer.is_color_field(field_id):
            _kernels.blank(live.fields[field_id], Rect2i(0, 0, live.pixel_size(), live.pixel_size()))
    _before[grid_pos] = null
    return live


## Whether a pass that reads its neighbours can carry paint into *grid_pos*,
## which is whether one of the eight around it held a chunk at the press.
func _carried_into(grid_pos: Vector2i) -> bool:
    var recorded := evaluation.recorded as SaNeighbourhoodPass
    if recorded == null or recorded.halo_at(SaFilterDensity.side_of(layer)) <= 0:
        return false
    for dy: int in [-1, 0, 1]:
        for dx: int in [-1, 0, 1]:
            if (dx != 0 or dy != 0) and _held_at_press(grid_pos + Vector2i(dx, dy)):
                return true
    return false


func _held_at_press(grid_pos: Vector2i) -> bool:
    if _before.has(grid_pos):
        return _before[grid_pos] != null
    return layer.chunks.has(grid_pos)


## The colour at *grid_pos* as it was at the press, the saved original, the
## live chunk where the stroke has not touched it, or null where there was
## none. What a neighbourhood pass reads its neighbours through.
func _original(grid_pos: Vector2i) -> SaTexture:
    if _before.has(grid_pos):
        var held: SaChunkDelta = _before[grid_pos]
        return held.fields.get(SaFieldSpec.ALBEDO, null) if held != null else null
    return layer.get_field(grid_pos)


## The coverage at *grid_pos*, made on the first touch there and blanked on
## the compute queue for the reason [method _taken] gives.
func _coverage_at(grid_pos: Vector2i, side: int) -> SaTexture:
    if coverage.has(grid_pos):
        return coverage[grid_pos]
    var made := SaTexture.new(Vector2i(side, side), COVERAGE_FORMAT)
    _kernels.blank(made, Rect2i(0, 0, side, side))
    coverage[grid_pos] = made
    return made


## *work* of the chunk at *grid_pos* filtered from the original and mixed into
## the live chunk by the coverage.
func _filter(grid_pos: Vector2i, work: Rect2i) -> void:
    var live: SaChunk = layer.chunks.get(grid_pos, null)
    var target := live.field(SaFieldSpec.ALBEDO) if live != null else null
    if target == null:
        return
    var original := _original(grid_pos)
    if original == null:
        original = _blank_like(target)
    var cover: SaTexture = coverage[grid_pos]
    var recorded := evaluation.recorded
    var compute := evaluation.compute
    if recorded is SaNeighbourhoodPass:
        # The runner reads the chunk's own texels over the region it writes
        # and nothing else of the chunk, so it runs over the region grown by
        # the reach, into a scratch, and only the region is copied on. The
        # grown ring's own reads stop short, and it is never copied.
        var gather := recorded as SaNeighbourhoodPass
        var side := target.size.x
        var wide := _aligned(work.grow(gather.halo_at(side)).intersection(Rect2i(0, 0, side, side)), side)
        var scratch := _scratch_like(target)
        _runner.run(gather, compute, scratch, original, _original, grid_pos, wide, cover)
        _kernels.copy(scratch, target, work)
        return
    _kernels.copy(original, target, work)
    compute.use_storage_format(target.format)
    compute.set_texture(0, target.rid)
    compute.set_texture(SaSelection.BINDING, cover.rid)
    recorded.bind(compute)
    compute.set_push_constant_float_array(recorded.push_for(work.position, grid_pos * SaChunk.SIZE))
    compute.dispatch_kernel(recorded.kernel, SaCompute.groups_for(work.size.x), SaCompute.groups_for(work.size.y), 1)


## A transparent texture like *like*, made once.
func _blank_like(like: SaTexture) -> SaTexture:
    if _blank == null or _blank.size != like.size or _blank.format != like.format:
        _blank = SaTexture.new(like.size, like.format)
        _kernels.blank(_blank, Rect2i(Vector2i.ZERO, like.size))
    return _blank


## A texture like *like* to write a neighbourhood pass into, made once.
func _scratch_like(like: SaTexture) -> SaTexture:
    if _scratch == null or _scratch.size != like.size or _scratch.format != like.format:
        _scratch = SaTexture.new(like.size, like.format)
    return _scratch


## *local* rounded out to the workgroup grid at both ends and kept inside a
## chunk *side* texels across, because a workgroup is dispatched whole and a
## point kernel's region starts where its origin says.
static func _aligned(local: Rect2i, side: int) -> Rect2i:
    if local.size.x <= 0 or local.size.y <= 0:
        return Rect2i()
    var group := SaCompute.WORKGROUP_SIZE
    var start := Vector2i(floori(float(local.position.x) / group) * group, floori(float(local.position.y) / group) * group)
    var end := Vector2i(ceili(float(local.end.x) / group) * group, ceili(float(local.end.y) / group) * group)
    end = end.min(Vector2i(side, side))
    return Rect2i(start, end - start)


## What [method evaluate] answers: the filter's title, and its pass and compute
## or the sentence that refuses it.
class Evaluation:
    extends RefCounted

    var title: String = ""
    var recorded: SaPointPass = null
    var compute: SaCompute = null
    var refusal: String = ""

    func ok() -> bool:
        return refusal.is_empty() and recorded != null and compute != null


## The three kernels a stroke runs besides the filter's. Inner, because nothing
## but the stroke dispatches them.
class Kernels:
    extends RefCounted

    var _cover: SaCompute = null
    var _clear: SaCompute = null
    var _copy: SaCompute = null

    ## Makes the three on first use. False with no device.
    func ready() -> bool:
        if GlobalShaderCompiler.get_rd() == null:
            return false
        if _cover == null:
            _cover = SaCompute.new("filter_brush_coverage")
            _clear = SaCompute.new("clear")
            _copy = SaCompute.new("copy_region")
        return true

    ## Raises *coverage* over *local* by the capsule from *from* to *to*, both
    ## in the chunk's texels, of *radius* texels, its strength running from
    ## *strength*'s x at *from* to its y at *to*.
    func cover(
        coverage: SaTexture,
        selection: SaTexture,
        local: Rect2i,
        from: Vector2,
        to: Vector2,
        radius: float,
        softness: float,
        strength: Vector2,
        soft_tip: bool
    ) -> void:
        _cover.set_texture(0, coverage.rid)
        _cover.set_texture(1, selection.rid)
        (
            _cover
            . set_push_constant_float_array(
                PackedFloat32Array(
                    [
                        local.position.x,
                        local.position.y,
                        local.size.x,
                        local.size.y,
                        from.x,
                        from.y,
                        to.x,
                        to.y,
                        radius,
                        clampf(softness, 0.0, 1.0),
                        strength.x,
                        strength.y,
                        1.0 if soft_tip else 0.0,
                        0.0,
                        0.0,
                        0.0,
                    ]
                )
            )
        )
        _cover.dispatch_kernel("filter_brush_coverage", SaCompute.groups_for(local.size.x), SaCompute.groups_for(local.size.y), 1)

    ## Writes transparency over *local* of *target*.
    func blank(target: SaTexture, local: Rect2i) -> void:
        _clear.use_storage_format(target.format)
        _clear.set_texture(0, target.rid)
        _clear.set_push_constant_float_array(
            PackedFloat32Array([0.0, 0.0, local.position.x, local.position.y, local.size.x, local.size.y, 0.0, 0.0])
        )
        _clear.dispatch_kernel("clear_chunk", SaCompute.groups_for(local.size.x), SaCompute.groups_for(local.size.y), 1)

    ## *local* of *source* into the same place in *target*.
    func copy(source: SaTexture, target: SaTexture, local: Rect2i) -> void:
        _copy.use_storage_format(target.format)
        _copy.set_texture(0, target.rid)
        _copy.set_texture(1, source.rid)
        _copy.set_push_constant_float_array(
            PackedFloat32Array(
                [local.position.x, local.position.y, local.position.x, local.position.y, local.size.x, local.size.y, 0.0, 0.0]
            )
        )
        _copy.dispatch_kernel("copy_region", SaCompute.groups_for(local.size.x), SaCompute.groups_for(local.size.y), 1)
