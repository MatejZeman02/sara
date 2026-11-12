## An input event's noise stroke on its way to the card: the stretch of path
## the event painted, each target's push constant packed by the names its
## kernel declares, its dispatches recorded as the stretch is laid, and the
## event's records sent as one compute list. The name says dab, and what an
## event lays is one stretch, once for the stroke and once for each image the
## document's symmetry paints.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **One list an event, and the block packed here.** A list opened and closed
## per laying, through `SaPaintContext.dispatch_batch`, pays its begin, its end
## and its ledger, commits its dirty rectangles, and packs its push constant
## through `SaCompute.set_params`, which checks the names against the block and
## packs them one field at a time on every call. Together those are most of
## what a laying costs the CPU, and a full press lays a stretch two dozen
## times over a stroke. So the list is one an event, its rectangles are
## committed once, and the block is packed here into floats at the offsets the
## compiler parsed out of `noise_dab.gmacs`, which are the bytes the door
## packs. The names are checked against the block at the first pack, the door's
## own check, and not again.
##
## **A barrier before every laying.** Two images of a mirrored stretch may
## overlap in the stroke buffer and each reads what the one before it wrote,
## so the list waits at each laying's first target, the wait the end of a list
## of its own would give it, and only one laying's own targets, which are
## different chunks, share a stretch of it. So a laying reads the texels the
## laying before it finished writing, which
## `tests/test_an_event_sends_its_dabs_as_one_compute_list.gd` holds.
##
## **Recorded, not dispatched**, through `SaCompute.record`, which settles the
## format and the uniform set when the stretch is laid. A laying may allocate a
## chunk or sum the surface beneath its layer there, which no open list can hold,
## and the one after it binds other images, so each record carries its own.
##
## **Symmetry maps the stretch, not its box.** The door's symmetry moves a
## round dab's box to each image of its centre, which is the whole of a
## mirrored dab. A mirrored stretch is the path reflected or turned, so
## [method images] answers the map to each image, and the kernel reads every
## texel of an image back through it into the stroke's own pixels.
extends RefCounted

const NoiseStretchScript = preload("res://modules/sara-noise-brush-engine/dab_list/noise_stretch.gd")
const NoiseHeightCarryScript = preload("res://modules/sara-noise-brush-engine/dab_list/noise_height_carry.gd")
const NoiseFrontScript = preload("res://modules/sara-noise-brush-engine/dab_list/noise_front.gd")

## What the event's list is counted and timed under. Its dispatches still
## count under the kernel's own name.
const LIST_LABEL := "noise_dab/event"
## The images the kernel names that [method bind_target] binds by their slots,
## and the samplers it reads the layer's paint and the paint below it through.
const IMAGES: Array[String] = ["height", "beneath", "smudge", "height_below"]
const PAINT := "layer_paint"
const BELOW := "paint_below"
## Where [method images] reads the symmetry's maps, a point off every axis it
## can draw, and a second for when the first lands on one.
const PROBES: Array[Vector2] = [Vector2(97.31, 41.17), Vector2(-53.9, 88.7)]

## The points the update under way paints and the buffer the kernel reads
## them from, which the brush fills point by point and this list lays.
var stretch: NoiseStretchScript = NoiseStretchScript.new()
## The round end shown under the pen between two updates, which
## [method lay_front] lays and [method put_back_front] takes up again.
var front: NoiseFrontScript = NoiseFrontScript.new()
## The old paint the stroke under way carries ahead of itself, made by its
## first stretch that lays height and dropped with the stroke.
var _pushed: NoiseHeightCarryScript = null

var _kernel: String = ""
## Each field of the kernel's block as its name, the float it starts at and how
## many floats it is, read off the compiler's layout at the first pack.
var _fields: Array[Array] = []
## The block the next record sends, sized to what the kernel declares, with
## std430's gaps left at nought.
var _floats := PackedFloat32Array()
var _checked: bool = false
## The slots of the four images [method bind_target] binds, the height, the
## surface beneath it, the smudge carry and the height of the paint below, and
## of the layer's paint and the paint below it, which it samples, looked up by
## name once for the compute of the instance id beside them rather than six
## times a target.
var _image_slots := PackedInt32Array()
var _paint_slot: int = 0
var _below_slot: int = 0
var _slots_of: int = 0
## What the event laid since the last [method send]: the dispatches, each dab's
## count of targets for the stroke ledger, and the contexts whose dirty
## rectangles commit once the list is sent, each taking in the next that
## paints the same layer.
var _recorded: Array[SaCompute.Recorded] = []
var _dabs := PackedInt32Array()
var _laid: Array[SaPaintContext] = []
## The stretch [method reach] found, the map from the stroke's own document
## pixels to each image of it and the chunks each image reaches, in that order.
var _maps: Array[Transform2D] = []
var _images: Array[SaPaintContext] = []


func _init(kernel: String) -> void:
    _kernel = kernel


## Forgets the stroke before, at a press and a lift: its stretch and the
## height it carried.
func clear() -> void:
    stretch.clear()
    front.clear()
    _pushed = null


## The kernel's block with *values* written in by the names it declares,
## exactly the bytes `SaCompute.set_params` would have packed for them.
func pack(values: Dictionary) -> PackedByteArray:
    if not _checked:
        _checked = true
        _learn(values)
    for field: Array in _fields:
        var value: Variant = values[field[0]]
        var at: int = field[1]
        match field[2]:
            1:
                _floats[at] = value
            2:
                var pair: Vector2 = value
                _floats[at] = pair.x
                _floats[at + 1] = pair.y
            4:
                var colour: Color = value
                _floats[at] = colour.r
                _floats[at + 1] = colour.g
                _floats[at + 2] = colour.b
                _floats[at + 3] = colour.a
    return _floats.to_byte_array()


## Reads the block's fields off the layout and checks *values* against it,
## once, saying what is wrong as the door would.
func _learn(values: Dictionary) -> void:
    var layout := GlobalShaderCompiler.push_constant_layout(_kernel)
    var problem := SaCompute.PushConstants.complaint(layout, values)
    if not problem.is_empty():
        push_error("NoiseDabList('%s'): %s" % [_kernel, problem])
    @warning_ignore("integer_division")
    _floats.resize(GlobalShaderCompiler.push_constant_bytes(_kernel) / 4)
    for field: Dictionary in layout:
        var name := str(field["name"])
        if name.is_empty() or field.get("pad", false):
            continue
        var count: int = SaCompute.PushConstants.COMPONENTS.get(str(field["type"]), 1)
        @warning_ignore("integer_division")
        _fields.append([name, int(field["offset"]) / 4, count])


## Binds *target* on *compute* for the stretch *values* describe and hands the
## compute its block: the chunk, read through *into_stroke*, the map from the
## image's document pixels to the stroke's own, on a grid of chunks *side*
## pixels wide, the height there, the surface beneath it, the layer's paint and
## the paint below it from *deposits* by grid position, or the stand-ins for
## them, and the smudge stage's *carry*. What [method lay] and the smudge queue call for each
## target.
func bind_target(
    target: SaPaintContext.Target,
    compute: SaCompute,
    values: Dictionary,
    into_stroke: Transform2D,
    side: float,
    deposits: Dictionary,
    carry: SaTexture
) -> void:
    values["render_offset"] = target.render_offset
    values["frame_x"] = into_stroke.x
    values["frame_y"] = into_stroke.y
    values["frame_origin"] = into_stroke * (Vector2(target.grid_pos) * side - target.wrap_offset)
    compute.set_texture(0, target.texture.rid)
    if compute.get_instance_id() != _slots_of:
        _slots_of = compute.get_instance_id()
        _image_slots = PackedInt32Array([0, 0, 0, 0])
        for at: int in IMAGES.size():
            _image_slots[at] = compute.slots.slot_for(IMAGES[at], "image")
        _paint_slot = compute.slots.slot_for(PAINT, "sampler")
        _below_slot = compute.slots.slot_for(BELOW, "sampler")
    var deposit: Array = deposits.get(target.grid_pos, [])
    var none := SaStrokeHeights.held(null)
    compute.set_texture(_image_slots[0], (deposit[0] if not deposit.is_empty() else none).rid)
    compute.set_texture(_image_slots[1], (deposit[1] if not deposit.is_empty() else none).rid)
    compute.set_texture(_image_slots[2], carry.rid)
    var paint: SaTexture = deposit[2] if not deposit.is_empty() else SaSmudgeReservoir.stand_in()
    compute.set_sampled_texture(_paint_slot, paint.rid, RenderingDevice.SAMPLER_FILTER_NEAREST)
    # The paint below, where the setting is on and paint with a body lies
    # there, and otherwise the stand-ins, whose one texel the kernel knows.
    var below: SaTexture = deposit[3] if deposit.size() > 4 else SaSmudgeReservoir.stand_in()
    compute.set_sampled_texture(_below_slot, below.rid, RenderingDevice.SAMPLER_FILTER_NEAREST)
    compute.set_texture(_image_slots[3], (deposit[4] if deposit.size() > 4 else none).rid)
    values["lays_height"] = 0.0 if deposit.is_empty() else 1.0
    compute.set_push_constant(pack(values))


## The chunks *region* of *doc* reaches, in document pixels, once for the
## stroke and once for each image the document's symmetry paints, the stroke's
## own first. Kept for [method lay_images], which lays the stretch on them.
func reach(doc: SaDocument, region: Rect2) -> Array[SaPaintContext]:
    _maps = images(doc.symmetry)
    _images = []
    for map: Transform2D in _maps:
        _images.append(SaPaintContext.for_regions(doc, [_mapped(region, map)] as Array[Rect2], false))
    return _images


## Lays the stretch on every image [method reach] found, each target bound by
## [method bind_target] with *values*, the height *heights* holds for its chunk
## and the smudge stage's *carry*. Each laying joins a list that is sent once
## the update is laid: *smudge*'s queue, after the pickup it reads, while the
## stretch smudges, and this one otherwise.
##
## While the stretch lays height, the fold of what the last stretch found into
## the loads the stroke carries goes first in this list, which is sent before
## the smudge stage's, so every laying reads the carry folded. Each image reads
## and adds to lanes of its own, and the carry is told how far the stretch
## went, which its next fold weighs.
func lay_images(
    compute: SaCompute, values: Dictionary, heights: SaStrokeHeights, carry: SaTexture, smudge: SaSmudgeReservoir
) -> void:
    values["push_reach"] = NoiseHeightCarryScript.reach_for(stretch.newest_radius)
    values["push_length"] = stretch.walked
    if heights != null:
        if _pushed == null:
            _pushed = NoiseHeightCarryScript.new()
        _pushed.room_for(_maps.size())
        var folded := _pushed.fold()
        if folded != null:
            _recorded.append(folded)
        _pushed.bind(compute)
    else:
        NoiseHeightCarryScript.bind_none(compute)
    for index: int in _maps.size():
        var paint := _images[index]
        values["carry_lane"] = float(index * NoiseHeightCarryScript.LANES)
        if paint.is_empty():
            continue
        var deposits := _deposits(paint, heights, values["push_below"] > 0.5)
        var bind := bind_target.bind(compute, values, _maps[index].affine_inverse(), float(paint.chunk_size), deposits, carry)
        if smudge != null:
            smudge.lay(paint, compute, _kernel, bind)
        else:
            lay(paint, compute, bind)
    _images = []
    if _pushed != null:
        _pushed.laid(stretch.walked, values["push_reach"])


## Each target's height, the surface beneath it and the layer's paint there, by
## grid position, from *heights* and the layer it thickens, or none while the
## stretch lays no height or paints coverage into a mask. Asked before the list
## opens, because the first touch of a chunk snapshots it for undo and sums the
## layers below it, which a compute list cannot hold. The paint is the layer's
## own chunk, which a stroke into the stroke buffer leaves as it stood, so the
## push reads the paint before the stroke without a copy of it.
##
## With *below*, the brush's Push Colour Below, a target over paint below the
## layer that has a height there carries that paint's colour and height after
## them, `SaStrokeHeights.paint_beneath`, which leaves out the Background and
## the grounds. Without it nothing below is asked for, and the kernel pushes
## the layer's own paint alone.
##
## With *reached*, the front's, a target is left out unless a body of the
## stroke reached its chunk or the layer has a height there already: a front
## ahead of every body would otherwise make the layer a height there that the
## put back leaves standing empty.
static func _deposits(paint: SaPaintContext, heights: SaStrokeHeights, below: bool, reached: Variant = null) -> Dictionary:
    var deposits := {}
    if heights == null or paint.paints_coverage:
        return deposits
    for target: SaPaintContext.Target in paint.targets:
        if reached != null and not _stands(heights, target.grid_pos, reached):
            continue
        var height := heights.reach(target.grid_pos)
        var beneath := heights.beneath(target.grid_pos)
        var colour: SaTexture = heights._layer.get_field(target.grid_pos) if heights._layer != null else null
        if height == null or beneath == null:
            continue
        var deposit: Array = [height, beneath, colour if colour != null else SaSmudgeReservoir.stand_in()]
        if below:
            deposit.append_array(heights.paint_beneath(target.grid_pos))
        deposits[target.grid_pos] = deposit
    return deposits


## Whether a body of the stroke *reached* the chunk at *grid* or the layer
## *heights* thickens has a height there already.
static func _stands(heights: SaStrokeHeights, grid: Vector2i, reached: Dictionary) -> bool:
    if reached.has(grid):
        return true
    var layer := heights._layer
    var chunk: SaChunk = layer.chunks.get(grid) if layer != null else null
    return chunk != null and chunk.has_field(SaFieldSpec.HEIGHT)


## The box *region* covers once *map* has moved it, in document pixels.
static func _mapped(region: Rect2, map: Transform2D) -> Rect2:
    var corners := PackedVector2Array(
        [region.position, Vector2(region.end.x, region.position.y), region.end, Vector2(region.position.x, region.end.y)]
    )
    var out := Rect2(map * corners[0], Vector2.ZERO)
    for corner: Vector2 in corners:
        out = out.expand(map * corner)
    return out


## The map from the stroke's own document pixels to each image the document's
## *symmetry* paints it at, the stroke itself first. One, the identity, while
## no symmetry is on.
##
## Read off the symmetry's own images of three points rather than built from
## its switches, so a mirror or a spoke it gains is mapped here unasked. The
## three are off every axis, where no two images of a point fall together and
## so every point has the same count of them, in the same order.
static func images(symmetry: SaSymmetry) -> Array[Transform2D]:
    var maps: Array[Transform2D] = [Transform2D.IDENTITY]
    if symmetry == null or not symmetry.is_active():
        return maps
    for probe: Vector2 in PROBES:
        var at := symmetry.center + probe
        var origin := symmetry.images(at)
        var right := symmetry.images(at + Vector2.RIGHT)
        var down := symmetry.images(at + Vector2.DOWN)
        if origin.size() != right.size() or origin.size() != down.size():
            continue
        maps.clear()
        for index: int in origin.size():
            var x_axis := right[index] - origin[index]
            var y_axis := down[index] - origin[index]
            var linear := Transform2D(x_axis, y_axis, Vector2.ZERO)
            maps.append(Transform2D(x_axis, y_axis, origin[index] - linear * at))
        return maps
    return maps


## Puts back the stroke buffer's texels the last front painted over, first in
## the event's list, and draws their rectangles again with the rest.
func put_back_front() -> void:
    _recorded.append_array(front.put_back(_laid))


## Lays the stretch's front, the end cap its closing update would paint now, on
## every image of *doc*'s symmetry, each through its own map as the body is,
## after saving what it paints over. *values* are the body's but for the
## stretch's own three numbers and the push, which the front lays from the
## loads the stroke carries so far, folded first, over the length its path has
## that the body has not painted, and whose finds go to a buffer of its own
## that nothing reads, so the next stretch's loads are the ones it would have
## had with no front. The layer's height under the round end is saved and put
## back with the colour. With no *heights* the front lays colour only. *carry* is the smudge
## stage's, so the front's colour is the body's. *pressure* is the pen's now,
## which the point the front ends on takes.
func lay_front(
    doc: SaDocument, compute: SaCompute, values: Dictionary, carry: SaTexture, pressure: float, heights: SaStrokeHeights = null
) -> void:
    var line := stretch.front_line(pressure)
    var buffer := doc.stroke_layer
    if line.is_empty() or buffer == null:
        return
    var box := stretch.front_box()
    var before := buffer.chunks.duplicate()
    var maps := images(doc.symmetry)
    var contexts: Array[SaPaintContext] = []
    var deposits: Array[Dictionary] = []
    for map: Transform2D in maps:
        var paint := SaPaintContext.for_regions(doc, [_mapped(box, map)] as Array[Rect2], false)
        contexts.append(paint)
        deposits.append(_deposits(paint, heights, false, front._reached))
    _recorded.append_array(front.save(contexts, before, deposits))
    front.write(line, box, stretch.front_first_laid())
    front.bind(compute)
    stretch.returns.bind(compute)
    _recorded.append_array(front.push(_pushed if heights != null else null, compute, values, stretch.newest_radius))
    values["point_count"] = float(front.count)
    values["first_laid"] = front.first_laid
    values["open_end"] = 0.0
    values["push_below"] = 0.0
    for index: int in maps.size():
        var paint := contexts[index]
        values["carry_lane"] = float(index * NoiseHeightCarryScript.LANES)
        if paint.is_empty():
            continue
        lay(
            paint,
            compute,
            bind_target.bind(compute, values, maps[index].affine_inverse(), float(paint.chunk_size), deposits[index], carry)
        )


## Records *paint*'s dispatches of the kernel on *compute*, *dispatcher*
## binding each target, [method bind_target] bound to the dab, the way
## `SaPaintContext.dispatch_batch` dispatches them, and holds its dirty
## rectangles for [method send].
func lay(paint: SaPaintContext, compute: SaCompute, dispatcher: Callable) -> void:
    if paint.targets.is_empty():
        return
    var format: int = paint.targets[0].texture.format
    var current_pass := -1
    for target: SaPaintContext.Target in paint.targets:
        if target.texture.format != format:
            push_warning(
                "NoiseDabList: a target chunk is format %d in a dab at %d, so it was skipped." % [target.texture.format, format]
            )
            continue
        compute.set_texture(SaSelection.BINDING, target.mask.rid)
        dispatcher.call(target)
        var waits := target.pass_index != current_pass
        current_pass = target.pass_index
        var one := compute.record(_kernel, format, target.groups_x, target.groups_y, 1, waits)
        if one != null:
            _recorded.append(one)
    _dabs.append(paint.targets.size())
    if _laid.is_empty() or not _laid[-1].absorb(paint):
        _laid.append(paint)


## Sends what the update laid so far at the head of *smudge*'s queue, as one
## list with it, and commits its dirty rectangles, or as a list of its own
## before the stage's when the stage holds nothing to send. What is laid here
## first is the front put back and the carry folded, which the stage's pickups
## and the body after them read, so they go before.
func send_before(smudge: SaSmudgeReservoir) -> void:
    if smudge._queue.is_empty():
        send()
        smudge.submit()
        return
    smudge.submit(true, _recorded)
    for paint: SaPaintContext in _laid:
        paint.commit_invalidation()
    _recorded = []
    _dabs = PackedInt32Array()
    _laid = []


## Sends what the update laid as one list and commits its dirty rectangles.
## Nothing laid sends nothing.
func send() -> void:
    if not _recorded.is_empty():
        SaCompute.submit(_recorded, LIST_LABEL, _dabs)
    for paint: SaPaintContext in _laid:
        paint.commit_invalidation()
    _recorded = []
    _dabs = PackedInt32Array()
    _laid = []
