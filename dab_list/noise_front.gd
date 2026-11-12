## The front of a noise stroke while it is drawn: the round end the stroke's
## last update paints, laid under the pen at every update and put back by the
## next, with the stroke buffer's texels it painted over, the box it reached and
## the buffer the kernel reads its points from.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Why a front at all**. Each update paints the body up to its newest point
## and leaves the texels in front of it to the next, which alone knows where
## the path goes from there, so the relief shows no joint and a bend keeps its
## holes (`noise_stretch.gd`). A round tip's body stops a half width short of
## its newest point and leaves that band to the next as well, so a turn is
## drawn round its pivot (`noise_held_path.gd`). Seen from the pen that is a
## stroke cut straight across behind the tip, a whole radius and up to a step
## short, or two radii for a round tip, which fills to the round end only at
## the lift. The round tip is to show under the pen as the stroke goes, at the
## pressure the pen has now. So after the body each update lays the end cap the
## closing update would paint, and the next update puts the texels back before
## its own body, which then paints them once. What the stroke leaves is the
## body's paint alone, with nothing of the front in it.
##
## **Put back on the card.** Hard rule 1 allows no read back, so before the
## front is laid its box is copied chunk by chunk into scratch textures this
## object keeps, and copied back at the start of the next update and at the
## lift, both by `copy_region` dispatches in the event's own list. Not
## `texture_copy`, which is a transfer and is not ordered against the compute
## around it inside a frame. A chunk of the stroke buffer the front itself made
## has nothing to copy: it is cleared by `clear_chunk` before the front is laid
## and again in place of the copy back, and dropped at the lift when the body
## never reached it, so the stroke lands no empty chunk on the layer.
##
## **The height too.** The front lays height where the body lays it, so the
## round end under the pen stands in relief rather than as a flat block until
## the lift. A stroke writes the layer's height in place, not through the
## buffer, so the front saves and puts back the height's texels beside the
## colour's, on chunks a body reached or that held a height already.
##
## **And the push the body lays.** Over old paint a front with no push showed
## the brush's own colour where the body then laid the pushed one, so it reads
## the stroke's loads as the next stretch will, folded first by [method push],
## and its own finds go to a buffer nothing reads, so the next stretch's loads
## are the body's alone. That stretch's length is not known yet, so the front
## is close to what the body lays there rather than the same.
##
## **Its size holds until the body begins.** A front laid while no body is
## laid yet is the press alone, and a pen pressed harder on the spot writes the
## harder press onto that point, its half extents with it, so a brush whose
## radius follows the pressure showed a dab that grew and shrank under a pen
## that had not moved, a dab the stroke had not committed. So while the press
## waits the front keeps the half extents it was first laid with, and only its
## cut reads the pressure now. Once a body is laid the front's points are the
## body's own and it takes their size.
extends RefCounted

const NoiseStretchScript = preload("res://modules/sara-noise-brush-engine/dab_list/noise_stretch.gd")
const NoiseHeightCarryScript = preload("res://modules/sara-noise-brush-engine/dab_list/noise_height_carry.gd")

## The fewest points the front's buffer is made for: the body's newest two and
## the point held back, which is all a tip that is not round sends. A
## round tip's front runs from the end the body laid through the half width it
## holds back, and the turns drawn round a pivot there, so a longer front makes
## a bigger buffer and keeps it.
const MIN_CAPACITY: int = 3

## The box the front reached in the stroke's own document pixels, and the point
## it ends on, which a suite measures the round end from. Empty while no front
## is laid.
var box: Rect2 = Rect2()
var end_at: Vector2 = Vector2.ZERO
## What the kernel reads of the front: how many points and what of its first
## segment the body painted already, `NoiseStretch.FIRST_SEGMENT` once a body
## was laid and `FIRST_NOTHING` while the press waits.
var count: int = 0
var first_laid: float = NoiseStretchScript.FIRST_NOTHING
## The half extents the front was first laid with while the press waits, the
## size it keeps until a body is laid, and its major radius, which a suite
## reads. Zero while no front of the stroke has been laid.
var press_extent: Vector2 = Vector2.ZERO
var drawn_radius: float = 0.0

## What the front laid over, one entry a chunk: its texture, the texels the
## front's dispatches cover there, and the scratch holding what they held, or
## null for a chunk the front made, which is cleared rather than copied back.
var _saved: Array[Saved] = []
## The contexts the front was laid through, whose dirty rectangles the put back
## commits again.
var _laid: Array[SaPaintContext] = []
## The stroke buffer's chunks the front made and the ones a body reached, by
## grid position, for the lift.
var _made: Dictionary[Vector2i, bool] = {}
var _reached: Dictionary[Vector2i, bool] = {}
## The scratch textures, reused update after update, by format and size.
var _scratch: Dictionary[String, Array] = {}
var _buffer: SaCompute.Buffer = null
var _capacity: int = 0
## The length of the front's line past the end the body laid, which the kernel
## reads ahead from as the next stretch reads from its start.
var _unlaid: float = 0.0
## One copier a storage format, since the colour and the layer's height are
## copied in one list and a kernel switched to another format drops the
## pipeline the records before it hold.
var _copiers: Dictionary[int, SaCompute] = {}
var _clearer: SaCompute = null
## Where the front's own finds go, the size of the carry's sums and never read.
var _found: SaCompute.Buffer = null
var _found_size: int = 0


## One chunk the front painted over.
class Saved:
    extends RefCounted

    var texture: SaTexture
    var region: Rect2i
    ## What the region held, at the same place in a texture of the chunk's
    ## size, or null for a chunk the front made.
    var scratch: SaTexture

    func _init(on: SaTexture, texels: Rect2i, held: SaTexture) -> void:
        texture = on
        region = texels
        scratch = held


## Forgets the stroke before, at a press and a lift. What was saved is dropped
## unput back, which is right for a stroke the document already ended.
func clear() -> void:
    box = Rect2()
    end_at = Vector2.ZERO
    count = 0
    first_laid = NoiseStretchScript.FIRST_NOTHING
    _saved = []
    _laid = []
    _made = {}
    _reached = {}
    forget_size()


## Forgets the size the press was first laid with, for a press laid again at
## the pressure of the sample that followed it.
func forget_size() -> void:
    press_extent = Vector2.ZERO
    drawn_radius = 0.0


## Notes the chunks the body's *contexts* reach, which the lift keeps.
func reached(contexts: Array[SaPaintContext]) -> void:
    for paint: SaPaintContext in contexts:
        for target: SaPaintContext.Target in paint.targets:
            _reached[target.grid_pos] = true


## The records that put back what the last front painted over, in order and
## the first after a barrier, empty while nothing is saved. The contexts it was
## laid through go to *laid*, so their rectangles are drawn again.
func put_back(laid: Array[SaPaintContext]) -> Array[SaCompute.Recorded]:
    var out: Array[SaCompute.Recorded] = []
    for saved: Saved in _saved:
        var one: SaCompute.Recorded = null
        if saved.scratch == null:
            one = _clear(saved.texture, saved.region, out.is_empty())
        else:
            one = _copy(saved.scratch, saved.texture, saved.region, out.is_empty())
        if one != null:
            out.append(one)
    laid.append_array(_laid)
    _saved = []
    _laid = []
    box = Rect2()
    return out


## The records that save what the front about to be laid through *contexts*
## paints over, the first after a barrier. *before* is the stroke buffer's
## chunks as they stood before the contexts were made, so a chunk missing there
## is one the front made, which is cleared whole rather than saved. *deposits*
## holds each context's deposits by grid position, and the layer's height a
## deposit binds is saved over the same texels, since the front lays height
## there and the layer is no buffer the lift lands.
func save(contexts: Array[SaPaintContext], before: Dictionary, deposits: Array[Dictionary] = []) -> Array[SaCompute.Recorded]:
    _laid = contexts
    var regions: Dictionary[Vector2i, Rect2i] = {}
    var textures: Dictionary[Vector2i, SaTexture] = {}
    var heights: Dictionary[SaTexture, Rect2i] = {}
    for index: int in contexts.size():
        var paint := contexts[index]
        for target: SaPaintContext.Target in paint.targets:
            var texture := target.texture
            var whole := Rect2i(Vector2i.ZERO, texture.size)
            var groups := Vector2i(target.groups_x, target.groups_y) * SaPaintContext.WORKGROUP
            var region := Rect2i(Vector2i(target.render_offset), groups).intersection(whole)
            var grid := target.grid_pos
            var deposit: Array = deposits[index].get(grid, []) if index < deposits.size() else []
            if not deposit.is_empty():
                var height: SaTexture = deposit[0]
                var texels := region.intersection(Rect2i(Vector2i.ZERO, height.size))
                heights[height] = heights[height].merge(texels) if heights.has(height) else texels
            if not before.has(grid):
                _made[grid] = true
                region = whole
            regions[grid] = regions[grid].merge(region) if regions.has(grid) else region
            textures[grid] = texture
    var out: Array[SaCompute.Recorded] = []
    var used: Dictionary[String, int] = {}
    for grid: Vector2i in regions:
        var texture := textures[grid]
        var region := regions[grid]
        if region.size.x <= 0 or region.size.y <= 0:
            continue
        var scratch: SaTexture = null
        var one: SaCompute.Recorded = null
        if not before.has(grid):
            one = _clear(texture, region, out.is_empty())
        else:
            scratch = _scratch_for(texture, used)
            one = _copy(texture, scratch, region, out.is_empty())
        if one != null:
            out.append(one)
        _saved.append(Saved.new(texture, region, scratch))
    for height: SaTexture in heights:
        var texels := heights[height]
        if texels.size.x <= 0 or texels.size.y <= 0:
            continue
        var scratch := _scratch_for(height, used)
        var one := _copy(height, scratch, texels, out.is_empty())
        if one != null:
            out.append(one)
        _saved.append(Saved.new(height, texels, scratch))
    return out


## Sends *line*, the front's points at the stretch's slots, to the buffer the
## kernel reads, and takes its box in the stroke's own pixels, *reach*. While
## no body is laid, *laid* nothing, every point takes the half extents of the
## stroke's first front.
func write(line: PackedFloat32Array, reach: Rect2, laid: float) -> void:
    @warning_ignore("integer_division")
    count = line.size() / NoiseStretchScript.FLOATS
    var size_at := (count - 1) * NoiseStretchScript.FLOATS + NoiseStretchScript.HALF_EXTENT
    if laid == NoiseStretchScript.FIRST_NOTHING:
        if press_extent == Vector2.ZERO:
            press_extent = Vector2(line[size_at], line[size_at + 1])
        for index: int in count:
            var at := index * NoiseStretchScript.FLOATS + NoiseStretchScript.HALF_EXTENT
            line[at] = press_extent.x
            line[at + 1] = press_extent.y
    drawn_radius = maxf(line[size_at], line[size_at + 1])
    first_laid = laid
    box = reach
    var last := (count - 1) * NoiseStretchScript.FLOATS + NoiseStretchScript.AT
    end_at = Vector2(line[last], line[last + 1])
    if _buffer == null or count > _capacity:
        _capacity = maxi(MIN_CAPACITY, nearest_po2(count))
        var room := PackedFloat32Array()
        room.resize(_capacity * NoiseStretchScript.FLOATS)
        _buffer = SaCompute.Buffer.new(room.to_byte_array())
    _buffer.update(line.to_byte_array())
    _unlaid = 0.0
    for index: int in range(2 if laid == NoiseStretchScript.FIRST_SEGMENT else 1, count):
        var at := index * NoiseStretchScript.FLOATS + NoiseStretchScript.AT
        var back := at - NoiseStretchScript.FLOATS
        _unlaid += Vector2(line[at], line[at + 1]).distance_to(Vector2(line[back], line[back + 1]))


## Binds on *compute* the loads of *pushed*, the stroke's carry or null while
## it lays no height, with a buffer of the front's own for its finds, and writes
## the push of a tip of *radius* into *values*. Answers the fold of the last
## stretch's finds, which goes first. Call after [method write].
func push(pushed: NoiseHeightCarryScript, compute: SaCompute, values: Dictionary, radius: float) -> Array[SaCompute.Recorded]:
    var out: Array[SaCompute.Recorded] = []
    values["push_reach"] = 0.0
    values["push_length"] = 0.0
    if pushed == null or pushed.carry == null or pushed.found == null:
        NoiseHeightCarryScript.bind_none(compute)
        return out
    var folded := pushed.fold()
    if folded != null:
        out.append(folded)
    var size := pushed.images * NoiseHeightCarryScript.LANES * NoiseHeightCarryScript.FOUND_INTS * 4
    if _found == null or _found_size != size:
        var zeros := PackedByteArray()
        zeros.resize(size)
        _found = SaCompute.Buffer.new(zeros)
        _found_size = size
    compute.set_storage("push_carry", pushed.carry.rid)
    compute.set_storage("push_found", _found.rid)
    values["push_reach"] = NoiseHeightCarryScript.reach_for(radius)
    values["push_length"] = _unlaid
    return out


## Binds the front's buffer to *compute*'s `stretch`.
func bind(compute: SaCompute) -> void:
    compute.set_storage("stretch", _buffer.rid)


## Drops from *buffer*, the stroke buffer, each chunk the front made that no
## body reached, all of it cleared by now. Called at the lift, after the closing
## update, so the stroke lands only the chunks the body painted.
func drop_unreached(buffer: SaLayer) -> void:
    for grid: Vector2i in _made:
        if not _reached.has(grid) and buffer.chunks.has(grid):
            buffer.set_chunk(grid, null)
    _made = {}


## A dispatch that copies *region* of *from* into *into* at the same place.
func _copy(from: SaTexture, into: SaTexture, region: Rect2i, waits: bool) -> SaCompute.Recorded:
    var copier: SaCompute = _copiers.get(into.format)
    if copier == null:
        copier = SaCompute.new("copy_region")
        _copiers[into.format] = copier
    copier.set_texture(0, into.rid)
    copier.set_texture(1, from.rid)
    var at := Vector2(region.position)
    copier.set_push_constant_float_array(PackedFloat32Array([at.x, at.y, at.x, at.y, region.size.x, region.size.y, 0.0, 0.0]))
    return copier.record(
        "copy_region", into.format, SaCompute.groups_for(region.size.x), SaCompute.groups_for(region.size.y), 1, waits
    )


## A dispatch that writes nought over *region* of *texture*.
func _clear(texture: SaTexture, region: Rect2i, waits: bool) -> SaCompute.Recorded:
    if _clearer == null:
        _clearer = SaCompute.new("clear")
    _clearer.set_texture(0, texture.rid)
    var at := Vector2(region.position)
    _clearer.set_push_constant_float_array(PackedFloat32Array([0.0, 0.0, at.x, at.y, region.size.x, region.size.y, 0.0, 0.0]))
    return _clearer.record(
        "clear_chunk", texture.format, SaCompute.groups_for(region.size.x), SaCompute.groups_for(region.size.y), 1, waits
    )


## A scratch texture of *texture*'s size and format that no other chunk of this
## front uses, *used* counting those taken by each kind.
func _scratch_for(texture: SaTexture, used: Dictionary[String, int]) -> SaTexture:
    var kind := "%d %dx%d" % [texture.format, texture.size.x, texture.size.y]
    var pool: Array = _scratch.get(kind, [])
    var index: int = used.get(kind, 0)
    used[kind] = index + 1
    if index >= pool.size():
        pool.append(SaTexture.new(texture.size, texture.format))
        _scratch[kind] = pool
    return pool[index]
