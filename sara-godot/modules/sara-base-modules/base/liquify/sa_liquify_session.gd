## One liquify session: the displacement field the strokes edit, the originals
## the layer is drawn from through it, and the one history step it ends in.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Private to the liquify folder, reached through the `liquify` role
## `sa_liquify.gd` registers, the way the transform tool reaches its pass.
##
## **A field, resampled from the original.** A texel the session has touched
## holds where it reads from, and every dab edits that and draws the texels
## under it again from the untouched original, once. So a texel pushed ten
## times is read once, and an edge stays as sharp as one push leaves it,
## where a picture resampled from its own last resample softens with each.
##
## **Sparse like the layer.** A field chunk and a saved original exist only
## where a dab has landed (hard rule 3), each at the layer's own density, and
## every dispatch is over the dab's rectangle in that chunk (hard rule 2). The
## original is the whole chunk as a `SaChunkDelta`, taken at the first dab over
## it, which is what the commit hands the history and what Escape puts back.
## Nothing is read back.
##
## **The reach.** A texel's offset is held to `MAX_REACH` document pixels, and
## the session keeps for each field chunk how far its offsets can have grown,
## so the original a dab's draw reads from is stitched over the dab's rectangle
## grown by that much and no wider.
##
## **Six modes of the field, one kernel.** Push drags the field along a
## motion, reconstruct takes it back towards no offset, twirl turns it around
## the brush's centre, shrink and grow scale it about that centre, one dab
## with its sign turned, and smooth straightens the strokes under the brush.
## Twirl reads the field where its turn comes from, so its dab stitches the
## field chunks around its rectangle into a texture first, grown by how far
## the turn carries a texel, and so do shrink and grow, by how far the scale
## carries one. Push and reconstruct read only the texel they write.
##
## **Smooth is a warp too**, and never mixes a colour: it straightens the
## strokes under the brush as a stabiliser would rather than blurring them
## together, which darkens them and washes them into one another. Each dab
## reads where the strokes under the brush run, out of the layer as last drawn,
## by `liquify_smooth.gmacs`, and moves the field a small step along their
## normal by how sharply they bend, which `liquify.gmacs` gives the reasons
## for. A line keeps the sharpness one resampling leaves, as a push's does, and
## a reconstruct takes a smooth back as it takes a push.
extends RefCounted

## The kernel's modes, as `motion.w` carries them.
enum Mode { PUSH, RECONSTRUCT, TWIRL, SHRINK, GROW, SMOOTH }

## What the undo menu calls a committed session.
const ACTION_NAME := "Liquify"

## The longest offset a texel may hold, in document pixels: one chunk's edge,
## so the stitched original around a dab is never more than the dab and one
## chunk on each side.
const MAX_REACH: float = 256.0

## How far apart the dabs of one motion sit, as a fraction of the radius. A
## motion is one per frame at best and a fast hand crosses more than a radius
## in one, and a single dab of that length would tear rather than drag.
const STEP: float = 0.25

## The field's texels, `xy` the offset in the layer's texels.
const FIELD_FORMAT := RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT

## The rounding of the stitched original's size, so a stroke reuses one
## texture rather than making one a dab.
const SCRATCH_ROUNDING: int = 256

## The sigma smooth softens the strokes' direction at, as a fraction of the
## brush's width, so its bell reaches a quarter of the brush each way. The
## grain of a stroke's pixels is lost at that and both edges of a thin stroke
## move as one, while a wobble the brush covers is still seen.
const SMOOTH_SOFTEN: float = 0.125

## The wide softening, as a multiple of the brush's, whose bend is taken away
## from the brush's. A wobble the brush covers bends at the brush's softening
## and barely at twice it, while a curve as wide as the brush bends at both, so
## the difference straightens the one and keeps the other.
const SMOOTH_WIDE: float = 2.0

## The fine softening, in cells, that tells the stroke's own normal and where
## its edges are. The brush's softening spreads a thin stroke over a band wider
## than the stroke, and a texel moved along that band's normal shears the
## stroke wider where it bends.
const SMOOTH_FINE: float = 1.0

## How far across the stroke a texel looks for its middle, in the brush's
## sigma each way. Both edges of a stroke take the bend at the middle, so they
## move as one and the stroke keeps its width.
const SMOOTH_MIDDLE: float = 2.0

## The softening read at a coarser grid, of a texel to every this much of the
## sigma, so a wide brush costs what a narrow one does. Below four texels of
## sigma the grid is the layer's own.
const SMOOTH_CELLS: float = 4.0

## The longest time one smooth dab runs, in the sigma squared, the unit
## curvature flow keeps its pace in at any size. A longer one is dabbed in
## steps of this, each reading the strokes where the last left them.
const SMOOTH_STEP: float = 0.25

## How strong the softened tensor has to be for smooth to trust its edge by
## half, times the sigma in cells: an edge of a fifth of full contrast. Below
## it smooth fades out, so a flat colour or paint's faint noise stays put.
const SMOOTH_EDGE: float = 0.01

## The largest turn one twirl dab makes, in radians. A longer one is dabbed in
## steps of this, so the field a dab stitches around itself stays near the
## brush.
const TWIRL_STEP: float = PI / 12.0

## The largest scale one shrink or grow dab makes, as the logarithm of its
## factor, a tenth, for the reason `TWIRL_STEP` gives.
const SCALE_STEP: float = 0.1

## The key of the stitched field in `_scratch`, which no layer field id takes.
const RING := &"liquify ring"

## The keys of smooth's stitched picture and its steps in `_scratch`.
const PICTURE := &"liquify picture"
const CELLS := &"liquify cells"
const ACROSS := &"liquify across"
const TENSOR := &"liquify tensor"
const BEND := &"liquify bend"

## The document the session lives in, which a tool compares with its own to
## tell a rebuilt document from the one it started in.
var document: SaDocument = null

## The layer the session is on, null while none is open.
var layer: SaLayer = null

## Grid position -> SaTexture, the field chunk there, only where a dab landed.
var fields: Dictionary = {}

## Grid position -> SaChunkDelta, the whole chunk as it was before the first
## dab over it, or null where the session made the chunk, which the history
## round-trips as "remove it again".
var _before: Dictionary = {}

## Grid position -> how long an offset in that field chunk can have grown, in
## the layer's texels. Never less than the truth, so the stitch is always wide
## enough.
var _reach: Dictionary = {}

## Field id -> SaTexture, the stitched original the draw reads, kept for the
## session so a stroke does not free one a dab (`core/api/gpu/sa_texture.gd`).
var _scratch: Dictionary = {}

var _kernels: Kernels = Kernels.new()


func _init(on: SaDocument) -> void:
    document = on


## Whether a session is open, so the tool knows Enter and Escape mean
## something.
func is_open() -> bool:
    return layer != null


## Opens a session on *on*. False when the layer refuses paint or the device
## has no kernels.
func begin(on: SaLayer) -> bool:
    if is_open():
        return on == layer
    if document == null or on == null:
        return false
    if SaContext.refuse_paint(on, TranslationServer.translate("liquify")):
        return false
    if not _kernels.ready():
        return false
    layer = on
    return true


## Pushes the paint under a brush of *size* document pixels from *from* to
## *to*, at *strength*, one dab every `STEP` of the radius.
func push(from: Vector2, to: Vector2, size: float, strength: float) -> void:
    if not is_open() or not is_instance_valid(layer) or size <= 0.0 or strength <= 0.0:
        return
    var motion := to - from
    if motion.length() < 0.001:
        return
    var radius := size * 0.5
    var steps := maxi(1, ceili(motion.length() / maxf(radius * STEP, 0.5)))
    var each := motion / float(steps)
    for index in steps:
        _dab(from + each * float(index), radius, strength, Mode.PUSH, each)


## Takes the field under a brush of *size* document pixels at *at* towards no
## offset, by *strength* of the way at the brush's core, which returns a pushed
## area to the original as it is held.
func reconstruct(at: Vector2, size: float, strength: float) -> void:
    if not is_open() or not is_instance_valid(layer) or size <= 0.0 or strength <= 0.0:
        return
    _dab(at, size * 0.5, minf(strength, 1.0), Mode.RECONSTRUCT, Vector2.ZERO)


## Straightens the strokes under a brush of *size* document pixels at *at*
## for *time*, in the softening's sigma squared, by *strength* of that at the
## brush's core, dabbed in steps of `SMOOTH_STEP`.
func smooth(at: Vector2, size: float, strength: float, time: float) -> void:
    if not is_open() or not is_instance_valid(layer) or size <= 0.0 or strength <= 0.0 or time <= 0.0:
        return
    var steps := ceili(time * minf(strength, 1.0) / SMOOTH_STEP)
    for index in steps:
        _dab(at, size * 0.5, minf(strength, 1.0), Mode.SMOOTH, Vector2(time / float(steps), 0.0))


## Turns the paint under a brush of *size* document pixels at *at* by *angle*
## radians at the brush's core, clockwise on screen when positive, and by
## *strength* of that.
func twirl(at: Vector2, size: float, strength: float, angle: float) -> void:
    if not is_open() or not is_instance_valid(layer) or size <= 0.0 or strength <= 0.0 or is_zero_approx(angle):
        return
    var steps := ceili(absf(angle) / TWIRL_STEP)
    for index in steps:
        _dab(at, size * 0.5, strength, Mode.TWIRL, Vector2(angle / float(steps), 0.0))


## Shrinks the paint under a brush of *size* document pixels at *at* towards
## its centre, to `exp(-amount)` of its size at the brush's core at full
## *strength*, and by *strength* of that amount elsewhere.
func shrink(at: Vector2, size: float, strength: float, amount: float) -> void:
    _scale_by(at, size, strength, amount, Mode.SHRINK)


## Grows the paint under the brush out from its centre, to `exp(amount)` of
## its size at the core: shrink with its sign turned.
func grow(at: Vector2, size: float, strength: float, amount: float) -> void:
    _scale_by(at, size, strength, amount, Mode.GROW)


## Shrink or grow by *amount*, dabbed in steps of `SCALE_STEP`. The kernel's
## `motion.x` is positive for a shrink, the point a texel reads from moved out.
func _scale_by(at: Vector2, size: float, strength: float, amount: float, mode: Mode) -> void:
    if not is_open() or not is_instance_valid(layer) or size <= 0.0 or strength <= 0.0 or amount <= 0.0:
        return
    var steps := ceili(amount / SCALE_STEP)
    var each := amount / float(steps) * (-1.0 if mode == Mode.GROW else 1.0)
    for index in steps:
        _dab(at, size * 0.5, strength, mode, Vector2(each, 0.0))


## Writes the session into the history as one step and closes it. True when
## there was a step to write.
func commit() -> bool:
    if not is_open():
        return false
    if not is_instance_valid(layer) or _before.is_empty():
        close()
        return false
    var state := _before.duplicate()
    var into := layer
    close()
    if document.history != null:
        document.record_pixel_step(ACTION_NAME, into, state)
    document.modified = true
    document.document_changed.emit()
    return true


## Puts every chunk the session touched back as it was and closes it.
func cancel() -> void:
    if not is_open():
        return
    if not is_instance_valid(layer):
        close()
        return
    var touched: Array = []
    for grid_pos: Vector2i in _before:
        var held: Variant = _before[grid_pos]
        if held is SaChunkDelta:
            (held as SaChunkDelta).apply_to(layer.get_or_create_chunk(grid_pos))
            layer.mark_unresolved(grid_pos)
        else:
            layer.set_chunk(grid_pos, null)
        touched.append(grid_pos)
    close()
    document.invalidate_chunks(touched)
    document.document_changed.emit()


## Forgets the session without touching the layer, which is what a commit does
## once it holds the step, and what a tool does when its document was rebuilt
## under it.
func close() -> void:
    layer = null
    fields = {}
    _before = {}
    _reach = {}
    _scratch = {}


## The layer's texels a document pixel.
func _scale() -> float:
    return layer.resolution_scale if layer != null else 1.0


## One dab at *centre* in document pixels in *mode*. *step* is push's motion
## in document pixels, or in its `x` twirl's angle, the scale's amount or
## smooth's time.
func _dab(centre: Vector2, radius: float, strength: float, mode: Mode, step: Vector2) -> void:
    var t := _scale()
    var edge := roundi(SaChunk.SIZE * t)
    var low := (centre - Vector2(radius, radius)).floor()
    var high := (centre + Vector2(radius, radius)).ceil()
    var rect := Rect2i(Vector2i(low), Vector2i(high - low))
    var cap := MAX_REACH * t
    var motion := step * t
    var grown := step.length() * t * strength
    if mode == Mode.TWIRL:
        motion = step
        # A turn of a radians moves a texel r out by at most a times r, and
        # never more than across the brush.
        grown = minf(2.0, absf(step.x) * strength) * radius * t
    elif mode == Mode.SHRINK or mode == Mode.GROW:
        motion = step
        # A texel r out reads from r times the factor, and the brush's texels
        # are never more than a radius out.
        grown = (exp(absf(step.x) * strength) - 1.0) * radius * t
    var ring := Ring.new()
    if mode == Mode.SMOOTH:
        _bend_ring(ring, rect, radius, edge)
        if ring.texture == null:
            # No paint in reach, so no stroke to straighten.
            return
        # The time in the layer's texels squared, and the longest step a dab
        # takes, a bend of one sigma's radius at that time.
        var sigma := ring.sigma * ring.scale
        motion = Vector2(step.x * sigma * sigma, step.x * sigma)
        grown = motion.y * strength
    elif mode != Mode.PUSH and mode != Mode.RECONSTRUCT:
        # Two texels past the reach, for the bilinear read's second texel.
        _ring_for(ring, rect, ceili(grown) + 2, edge)
    var regions: Dictionary = {}
    for grid_pos: Vector2i in SaChunkWalk.positions_in(rect):
        var local := SaChunkWalk.local_rect(grid_pos, rect, edge)
        if local.size.x <= 0 or local.size.y <= 0:
            continue
        if mode == Mode.RECONSTRUCT and not fields.has(grid_pos):
            # No offset here, so nothing to take back.
            continue
        if (
            mode == Mode.SMOOTH
            and not _painted_within(Rect2i(grid_pos * edge + local.position, local.size).grow(ring.margin), edge)
        ):
            # No paint near enough to bend, so no chunk is made here.
            continue
        var mask := document.selection.texture_for(grid_pos) if document.selection != null else null
        if mask == null:
            # Nothing selected in this chunk, so nothing here moves.
            continue
        var field := _field_at(grid_pos, edge)
        var at := centre * t - Vector2(grid_pos * edge)
        var dab := Vector4(at.x, at.y, radius * t, strength)
        var place := Vector4(0.0, 0.0, 0.0, 0.0)
        if mode == Mode.SMOOTH:
            var from := grid_pos * edge - ring.rect.position
            place = Vector4(from.x, from.y, ring.scale, ring.window)
        elif ring.texture != null:
            var origin := grid_pos * edge - ring.rect.position
            place = Vector4(origin.x, origin.y, 0.0, 0.0)
        if mode == Mode.PUSH or mode == Mode.SMOOTH:
            _reach[grid_pos] = minf(cap, float(_reach.get(grid_pos, 0.0)) + grown)
        elif mode != Mode.RECONSTRUCT:
            # A texel takes an offset from within `grown` of it, plus that.
            _reach[grid_pos] = minf(cap, maxf(float(_reach.get(grid_pos, 0.0)), ring.reach) + grown)
        # A reconstruct only shortens an offset, so the chunk's reach stands.
        var constants := Vector4(motion.x, motion.y, cap, float(mode))
        _kernels.dab(field, mask, ring.texture if ring.texture != null else _kernels.nothing(), local, dab, constants, place)
        regions[grid_pos] = local
    if not regions.is_empty():
        _draw(regions, edge)


## Fills *ring* with the field around *rect*, in document pixels: the dab's
## texels grown by *margin*, read out of the field chunks there. A ring with no
## field chunk in it keeps no texture.
func _ring_for(ring: Ring, rect: Rect2i, margin: int, edge: int) -> void:
    var t := _scale()
    var texels := Rect2i(Vector2i((Vector2(rect.position) * t).floor()), Vector2i((Vector2(rect.size) * t).ceil()))
    ring.rect = texels.grow(margin)
    var found: Dictionary = {}
    for grid_pos: Vector2i in fields:
        var overlap := ring.rect.intersection(Rect2i(grid_pos * edge, Vector2i(edge, edge)))
        if overlap.size.x > 0 and overlap.size.y > 0:
            found[grid_pos] = overlap
            ring.reach = maxf(ring.reach, float(_reach.get(grid_pos, 0.0)))
    if found.is_empty():
        return
    var held := _scratch_for(RING, FIELD_FORMAT, ring.rect.size)
    _kernels.blank(held, Rect2i(Vector2i.ZERO, ring.rect.size))
    for grid_pos: Vector2i in found:
        var overlap: Rect2i = found[grid_pos]
        var from := overlap.position - grid_pos * edge
        _kernels.shift(fields[grid_pos], held, from, overlap.position - ring.rect.position, overlap.size)
    ring.texture = held


## Fills *ring* with what smooth reads of the layer as last drawn around
## *rect*, in document pixels, for a brush of *radius*: the picture stitched
## over the dab and the reach of the widest bell around it, read into cells,
## and the bend and the direction `liquify_smooth.gmacs` finds there. A ring
## with no paint in reach keeps no texture.
func _bend_ring(ring: Ring, rect: Rect2i, radius: float, edge: int) -> void:
    var t := _scale()
    var sigma := maxf(radius * 2.0 * t * SMOOTH_SOFTEN, 1.0)
    ring.scale = maxi(1, floori(sigma / SMOOTH_CELLS))
    ring.sigma = sigma / ring.scale
    ring.window = ceili(SMOOTH_MIDDLE * ring.sigma)
    var texels := Rect2i(Vector2i((Vector2(rect.position) * t).floor()), Vector2i((Vector2(rect.size) * t).ceil()))
    # The widest bell's reach, a cell each for the tensor's difference and the
    # bend's, the window the middle is looked for in, and a cell for the
    # bilinear read, so every cell the dab reads is whole.
    var margin := ceili(3.0 * ring.sigma * SMOOTH_WIDE) + ring.window + 4
    var first := Vector2i(floori(float(texels.position.x) / ring.scale), floori(float(texels.position.y) / ring.scale))
    var last := Vector2i(ceili(float(texels.end.x) / ring.scale), ceili(float(texels.end.y) / ring.scale))
    var cells := Rect2i(first, last - first).grow(margin)
    ring.rect = Rect2i(cells.position * ring.scale, cells.size * ring.scale)
    ring.margin = margin * ring.scale
    var live := _live_in(ring.rect, edge)
    if live.is_empty():
        return
    var picture := _stitch(SaFieldSpec.ALBEDO, ring.rect, live, edge, PICTURE)
    if picture == null:
        return
    var space := document.color_space
    var oklab := 1.0 if space != null and space.coordinates == SaColorSpace.Coordinates.OKLAB else 0.0
    var whole := Rect2i(Vector2i.ZERO, cells.size)
    var reduced := _scratch_for(CELLS, FIELD_FORMAT, cells.size)
    var across := _scratch_for(ACROSS, FIELD_FORMAT, cells.size)
    var tensor := _scratch_for(TENSOR, FIELD_FORMAT, cells.size)
    var read := _scratch_for(BEND, FIELD_FORMAT, cells.size)
    _kernels.soften(picture, reduced, whole, Vector4(0.0, ring.scale, 0.0, oklab), Vector4.ZERO)
    # The bend at the brush's softening, less the bend at the wide one, then
    # the stroke's own direction at the fine one.
    var passes: Array[Vector4] = [
        Vector4(ring.sigma, 3.0, 1.0, 0.0), Vector4(ring.sigma * SMOOTH_WIDE, 3.0, -1.0, 1.0), Vector4(SMOOTH_FINE, 4.0, 0.0, 0.0)
    ]
    for each: Vector4 in passes:
        _kernels.soften(reduced, across, whole, Vector4(1.0, ring.scale, each.x, 0.0), Vector4.ZERO)
        _kernels.soften(across, tensor, whole, Vector4(2.0, ring.scale, each.x, 0.0), Vector4.ZERO)
        _kernels.soften(
            tensor, read, whole, Vector4(each.y, ring.scale, each.x, 0.0), Vector4(SMOOTH_EDGE / each.x, each.z, each.w, 0.0)
        )
    ring.texture = read


## Grid position -> the fields of the layer as last drawn, for every chunk it
## holds that meets *texels*, in global texels.
func _live_in(texels: Rect2i, edge: int) -> Dictionary:
    var found: Dictionary = {}
    for grid_pos: Vector2i in layer.chunks:
        var live: SaChunk = layer.chunks[grid_pos]
        if live != null and texels.intersects(Rect2i(grid_pos * edge, Vector2i(edge, edge))):
            found[grid_pos] = live.fields
    return found


## Whether the layer holds a chunk that meets *texels*, in global texels.
func _painted_within(texels: Rect2i, edge: int) -> bool:
    return not _live_in(texels, edge).is_empty()


## The fields of *sources* the draw carries: colour and height.
func _picture_ids(sources: Dictionary) -> Array[StringName]:
    var ids: Array[StringName] = []
    for grid_pos: Vector2i in sources:
        var chunk_fields: Dictionary = sources[grid_pos]
        for field_id: StringName in chunk_fields:
            if not ids.has(field_id) and (layer.is_color_field(field_id) or field_id == SaFieldSpec.HEIGHT):
                ids.append(field_id)
    return ids


## The session's scratch texture under *key*, at least *size* and in *format*,
## made again only when the one held is too small or of another format.
func _scratch_for(key: StringName, format: int, size: Vector2i) -> SaTexture:
    var held: SaTexture = _scratch.get(key, null)
    if held == null or held.format != format or held.size.x < size.x or held.size.y < size.y:
        var wide := Vector2i(
            ceili(float(size.x) / SCRATCH_ROUNDING) * SCRATCH_ROUNDING, ceili(float(size.y) / SCRATCH_ROUNDING) * SCRATCH_ROUNDING
        )
        if held != null:
            wide = wide.max(held.size)
        held = SaTexture.new(wide, format)
        _scratch[key] = held
    return held


## The field chunk at *grid_pos*, made at no offset on the first dab there.
func _field_at(grid_pos: Vector2i, edge: int) -> SaTexture:
    var held: SaTexture = fields.get(grid_pos, null)
    if held != null:
        return held
    var made := SaTexture.new(Vector2i(edge, edge), FIELD_FORMAT)
    # Through the kernel rather than a transfer clear, which is not ordered
    # against the dab that follows.
    _kernels.blank(made, Rect2i(0, 0, edge, edge))
    fields[grid_pos] = made
    return made


## Draws *regions*, grid position -> chunk-local texels, again from the
## originals through the field.
func _draw(regions: Dictionary, edge: int) -> void:
    var reach := 0.0
    var wanted := Rect2i()
    for grid_pos: Vector2i in regions:
        reach = maxf(reach, float(_reach.get(grid_pos, 0.0)))
        var local: Rect2i = regions[grid_pos]
        var placed := Rect2i(grid_pos * edge + local.position, local.size)
        wanted = placed if wanted.size == Vector2i.ZERO else wanted.merge(placed)
    # Two texels past the reach, for the bilinear read's second texel.
    var source := wanted.grow(ceili(reach) + 2)
    var sources := _sources_in(source, edge)
    if sources.is_empty():
        return

    var ids := _picture_ids(sources)

    var drawn: Dictionary = {}
    for grid_pos: Vector2i in regions:
        var live := _original_taken(grid_pos)
        if live == null:
            continue
        drawn[grid_pos] = regions[grid_pos]

    for field_id: StringName in ids:
        var curve := SaResampleKernel.curve_for(document.color_space, field_id)
        var stitched := _stitch(field_id, source, sources, edge)
        if stitched == null:
            continue
        for grid_pos: Vector2i in drawn:
            var live: SaChunk = layer.chunks[grid_pos]
            var target := live.field(field_id)
            if target == null and field_id == SaFieldSpec.HEIGHT:
                target = live.add_sparse_field(SaFieldSpec.find(layer.schema, field_id))
            if target == null or target.format != stitched.format:
                continue
            var origin := Vector2(grid_pos * edge - source.position)
            _kernels.draw(stitched, fields[grid_pos], target, drawn[grid_pos], origin, source.size, curve)
    for grid_pos: Vector2i in drawn:
        layer.mark_unresolved(grid_pos)
    document.invalidate_chunk_regions(drawn)


## Grid position -> the fields of the original there, for every position
## *source* touches that holds paint: the saved original where the session has
## one, and the live chunk where it has none, which is the original because
## nothing has touched it.
func _sources_in(source: Rect2i, edge: int) -> Dictionary:
    var found: Dictionary = {}
    var first := Vector2i(floori(float(source.position.x) / edge), floori(float(source.position.y) / edge))
    var last := Vector2i(floori(float(source.end.x - 1) / edge), floori(float(source.end.y - 1) / edge))
    for y in range(first.y, last.y + 1):
        for x in range(first.x, last.x + 1):
            var grid_pos := Vector2i(x, y)
            if _before.has(grid_pos):
                var held: Variant = _before[grid_pos]
                if held is SaChunkDelta:
                    found[grid_pos] = (held as SaChunkDelta).fields
                continue
            var live: SaChunk = layer.chunks.get(grid_pos, null)
            if live != null:
                found[grid_pos] = live.fields
    return found


## Saves the original at *grid_pos* on the first dab there and answers the
## live chunk to draw into. A position with no chunk gets one, blank, whose
## undo removes it again. Null only when the device refuses.
func _original_taken(grid_pos: Vector2i) -> SaChunk:
    var live: SaChunk = layer.chunks.get(grid_pos, null)
    if _before.has(grid_pos):
        return live
    if live != null:
        _before[grid_pos] = SaChunkDelta.capture(live, Rect2i(0, 0, live.pixel_size(), live.pixel_size()))
        return live
    live = layer.get_or_create_chunk(grid_pos)
    # The chunk's own clear is a transfer, and the draw into part of it is not
    # ordered against one, so the whole of it is blanked on the compute queue.
    for field_id: StringName in live.fields:
        if layer.is_color_field(field_id):
            _kernels.blank(live.fields[field_id], Rect2i(0, 0, live.pixel_size(), live.pixel_size()))
    _before[grid_pos] = null
    return live


## The *field_id* of *sources* over *source*, in global texels, as one texture
## at its (0, 0), because a bilinear read at a chunk's edge needs the texels of
## the chunk beside it. Held in `_scratch` under *key*, the field id unless
## the caller keeps its own.
func _stitch(field_id: StringName, source: Rect2i, sources: Dictionary, edge: int, key: StringName = &"") -> SaTexture:
    var format := -1
    for grid_pos: Vector2i in sources:
        var from: SaTexture = (sources[grid_pos] as Dictionary).get(field_id, null)
        if from != null:
            format = from.format
            break
    if format < 0:
        return null
    var held := _scratch_for(key if key != &"" else field_id, format, source.size)
    _kernels.blank(held, Rect2i(Vector2i.ZERO, source.size))
    for grid_pos: Vector2i in sources:
        var from: SaTexture = (sources[grid_pos] as Dictionary).get(field_id, null)
        if from == null or from.format != format:
            continue
        var overlap := source.intersection(Rect2i(grid_pos * edge, from.size))
        if overlap.size.x <= 0 or overlap.size.y <= 0:
            continue
        _kernels.shift(from, held, overlap.position - grid_pos * edge, overlap.position - source.position, overlap.size)
    return held


## The field twirl, shrink and grow read around a dab, or the softened tensor
## smooth reads, where it sits in the layer's texels, and the longest offset in
## it. Inner, because it is one dab's working and nothing else holds one.
class Ring:
    extends RefCounted

    var texture: SaTexture = null
    var rect: Rect2i = Rect2i()
    var reach: float = 0.0
    ## Smooth's: the layer's texels to a cell, the brush's softening in cells,
    ## the cells either side of a texel its stroke's middle is looked for in,
    ## and how far past the dab the paint it reads lies, in texels.
    var scale: int = 1
    var sigma: float = 1.0
    var window: int = 0
    var margin: int = 0


## The five kernels a session runs, and the push constants each wants. Inner,
## because nothing but the session dispatches them.
class Kernels:
    extends RefCounted

    var _liquify: SaCompute = null
    var _draw: SaCompute = null
    var _smooth: SaCompute = null
    var _clear: SaCompute = null
    var _shift: SaCompute = null
    ## The 1 by 1 blank a push binds where the other modes bind a ring, and
    ## any mode binds where no field chunk is in reach.
    var _nothing: SaTexture = null

    ## Makes the five on first use. False with no device.
    func ready() -> bool:
        if GlobalShaderCompiler.get_rd() == null:
            return false
        if _liquify == null:
            _liquify = SaCompute.new("liquify")
            _draw = SaCompute.new("liquify_draw")
            _smooth = SaCompute.new("liquify_smooth")
            _clear = SaCompute.new("clear")
            _shift = SaCompute.new("crop")
        return true

    ## The blank a dab with no ring binds, made once.
    func nothing() -> SaTexture:
        if _nothing == null:
            _nothing = SaTexture.new(Vector2i.ONE, FIELD_FORMAT)
            blank(_nothing, Rect2i(0, 0, 1, 1))
        return _nothing

    ## One dab into *field* over *local*: *brush* the centre, radius and
    ## strength, *motion* the kernel's `motion` and *place* its `ring_at`.
    func dab(
        field: SaTexture, mask: SaTexture, ring: SaTexture, local: Rect2i, brush: Vector4, motion: Vector4, place: Vector4
    ) -> void:
        _liquify.set_texture(0, field.rid)
        _liquify.set_texture(1, mask.rid)
        _liquify.set_texture(2, ring.rid)
        var constants := PackedFloat32Array([local.position.x, local.position.y, local.size.x, local.size.y])
        for vector: Vector4 in [brush, motion, place]:
            constants.append_array(PackedFloat32Array([vector.x, vector.y, vector.z, vector.w]))
        _liquify.set_push_constant_float_array(constants)
        _liquify.dispatch_kernel("liquify", SaCompute.groups_for(local.size.x), SaCompute.groups_for(local.size.y), 1)

    ## *local* of *target* read out of *source* through *field*, in linear light
    ## by *curve*, `SaResampleKernel.curve_for`'s.
    func draw(
        source: SaTexture, field: SaTexture, target: SaTexture, local: Rect2i, origin: Vector2, size: Vector2i, curve: Vector4
    ) -> void:
        _draw.use_storage_format(target.format)
        _draw.set_texture(0, source.rid)
        _draw.set_texture(1, field.rid)
        _draw.set_texture(2, target.rid)
        _draw.set_push_constant_float_array(
            PackedFloat32Array(
                (
                    [local.position.x, local.position.y, local.size.x, local.size.y, origin.x, origin.y, size.x, size.y]
                    + [curve.x, curve.y, curve.z, curve.w]
                )
            )
        )
        _draw.dispatch_kernel("liquify_draw", SaCompute.groups_for(local.size.x), SaCompute.groups_for(local.size.y), 1)

    ## One step of smooth's reading, *local* of *target* out of *source*:
    ## *step* and *bend* the kernel's own, the first saying which.
    func soften(source: SaTexture, target: SaTexture, local: Rect2i, step: Vector4, bend: Vector4) -> void:
        _smooth.use_storage_format(source.format)
        _smooth.set_texture(0, source.rid)
        _smooth.set_texture(1, target.rid)
        var constants := PackedFloat32Array([local.position.x, local.position.y, local.size.x, local.size.y])
        for vector: Vector4 in [step, bend]:
            constants.append_array(PackedFloat32Array([vector.x, vector.y, vector.z, vector.w]))
        _smooth.set_push_constant_float_array(constants)
        _smooth.dispatch_kernel("liquify_smooth", SaCompute.groups_for(local.size.x), SaCompute.groups_for(local.size.y), 1)

    ## Writes transparency, or no offset, over *local* of *target*.
    func blank(target: SaTexture, local: Rect2i) -> void:
        if local.size.x <= 0 or local.size.y <= 0:
            return
        _clear.use_storage_format(target.format)
        _clear.set_texture(0, target.rid)
        _clear.set_push_constant_float_array(
            PackedFloat32Array([0.0, 0.0, local.position.x, local.position.y, local.size.x, local.size.y, 0.0, 0.0])
        )
        _clear.dispatch_kernel("clear_chunk", SaCompute.groups_for(local.size.x), SaCompute.groups_for(local.size.y), 1)

    ## *size* texels of *source* from *from* into *into* at *to*.
    func shift(source: SaTexture, into: SaTexture, from: Vector2i, to: Vector2i, size: Vector2i) -> void:
        _shift.use_storage_format(into.format)
        _shift.set_texture(0, source.rid)
        _shift.set_texture(1, into.rid)
        _shift.set_push_constant_float_array(PackedFloat32Array([to.x, to.y, from.x, from.y, size.x, size.y, 0.0, 0.0]))
        _shift.dispatch_kernel("shift", SaCompute.groups_for(size.x), SaCompute.groups_for(size.y), 1)
