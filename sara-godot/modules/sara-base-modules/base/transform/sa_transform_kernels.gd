## The eight kernels a transform runs, and the dispatches that drive
## them.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## In the base module, beside the tool whose gestures it dispatches for.
##
## `SaTransform` decides what a lift, a preview and a commit are, and this is
## every place one of them touches a compute queue: the clear over a
## rectangle, the whole-pixel shift, the masked copy and cut the lift takes
## with and their height half, the resample the preview draws through, and
## the height's landing at the commit, and the reduce the box round the
## paint is measured by. It is a class of its own by
## responsibility: this owns the `SaCompute` objects and knows their push
## constants, and the pass owns the gesture and knows none of them.
##
## Every dispatch is over a rectangle a caller worked out, hard rule 2, and
## every compute is made on first use so a pass that only slides never
## compiles a resample.
class_name SaTransformKernels
extends RefCounted

## The `copy_masked` and `cut_masked` kernels' third texture: where a copy
## lands, and unused by a cut.
const DESTINATION_BINDING: int = 2

## Where `painted_bounds.gmacs` reads its four ints. Binding 0 is the chunk's
## own colour, which the walk binds.
const BOUNDS_BINDING: int = 1

## Past any document pixel, which is where the reduce's minimum starts and,
## negated, its maximum.
const BOX_WIDE: int = 1 << 30

var _clear_compute: SaCompute = null
var _resample_compute: SaCompute = null
var _warp_compute: SaCompute = null
var _copy_compute: SaCompute = null
var _cut_compute: SaCompute = null
var _shift_compute: SaCompute = null
var _height_compute: SaCompute = null
var _land_compute: SaCompute = null
var _no_height: SaTexture = null
var _bounds_compute: SaCompute = null
## The four ints `painted_bounds.gmacs` reduces into. One buffer for every
## measure, so a uniform set built against it stays valid.
var _bounds_box: SaCompute.Buffer = null


## Writes transparency over *local* of one texture, on the compute queue.
func blank_texture(target: SaTexture, local: Rect2i) -> void:
    var compute := clear()
    if compute == null or target == null or not target.rid.is_valid():
        return
    if local.size.x <= 0 or local.size.y <= 0:
        return
    compute.use_storage_format(target.format)
    compute.set_texture(0, target.rid)
    compute.set_push_constant_float_array(
        PackedFloat32Array([0.0, 0.0, local.position.x, local.position.y, local.size.x, local.size.y, 0.0, 0.0])
    )
    compute.dispatch_kernel("clear_chunk", SaCompute.groups_for(local.size.x), SaCompute.groups_for(local.size.y), 1)


## One overlap between two textures, whatever they belong to.
func shift_texture(source: SaTexture, into: SaTexture, from: Vector2i, to: Vector2i, size: Vector2i) -> void:
    var compute := shift()
    if compute == null or not source.rid.is_valid() or not into.rid.is_valid():
        return
    compute.use_storage_format(into.format)
    compute.set_texture(0, source.rid)
    compute.set_texture(1, into.rid)
    compute.set_push_constant_float_array(PackedFloat32Array([to.x, to.y, from.x, from.y, size.x, size.y, 0.0, 0.0]))
    compute.dispatch_kernel("shift", SaCompute.groups_for(size.x), SaCompute.groups_for(size.y), 1)


## One overlap, one dispatch per field the two chunks share.
func shift_part(source: SaChunk, into: SaChunk, from: Vector2i, to: Vector2i, size: Vector2i) -> void:
    var compute := shift()
    if compute == null:
        return
    var push := PackedFloat32Array([to.x, to.y, from.x, from.y, size.x, size.y, 0.0, 0.0])
    for field_id: StringName in into.fields:
        var target: SaTexture = into.fields[field_id]
        var origin_texture: SaTexture = source.fields.get(field_id, null)
        if target == null or origin_texture == null or not target.rid.is_valid() or not origin_texture.rid.is_valid():
            continue
        compute.use_storage_format(target.format)
        compute.set_texture(0, origin_texture.rid)
        compute.set_texture(1, target.rid)
        compute.set_push_constant_float_array(push)
        compute.dispatch_kernel("shift", SaCompute.groups_for(size.x), SaCompute.groups_for(size.y), 1)


## One masked kernel over *local* of *source*, the way the clipboard runs them:
## the dispatch starts on a workgroup boundary and the push constant carries the
## rectangle's end, so the kernel stops where the rectangle does.
func masked(
    compute: SaCompute, kernel: String, source: SaTexture, mask: SaTexture, local: Rect2i, destination: SaTexture
) -> void:
    var workgroup := SaCompute.WORKGROUP_SIZE
    var start := Vector2i(
        floori(float(local.position.x) / workgroup) * workgroup, floori(float(local.position.y) / workgroup) * workgroup
    )
    var covered := Vector2i(local.end.x - start.x, local.end.y - start.y)
    compute.use_storage_format(source.format)
    compute.set_texture(0, source.rid)
    compute.set_texture(SaSelection.BINDING, mask.rid)
    if destination != null:
        compute.set_texture(DESTINATION_BINDING, destination.rid)
    compute.set_push_constant_float_array(PackedFloat32Array([start.x, start.y, covered.x, covered.y]))
    compute.dispatch_kernel(kernel, SaCompute.groups_for(covered.x), SaCompute.groups_for(covered.y), 1)


func resample() -> SaCompute:
    if _resample_compute == null and GlobalShaderCompiler.get_rd() != null:
        _resample_compute = SaCompute.new("transform")
    return _resample_compute


## The freehand warp's kernel, a file of its own because a file's kernels
## share one push constant block and the mesh does not fit beside the
## resample's rows.
func warp() -> SaCompute:
    if _warp_compute == null and GlobalShaderCompiler.get_rd() != null:
        _warp_compute = SaCompute.new("warp")
    return _warp_compute


func clear() -> SaCompute:
    if _clear_compute == null and GlobalShaderCompiler.get_rd() != null:
        _clear_compute = SaCompute.new("clear")
    return _clear_compute


func copy() -> SaCompute:
    if _copy_compute == null and GlobalShaderCompiler.get_rd() != null:
        _copy_compute = SaCompute.new("copy_masked")
    return _copy_compute


func cut() -> SaCompute:
    if _cut_compute == null and GlobalShaderCompiler.get_rd() != null:
        _cut_compute = SaCompute.new("cut_masked")
    return _cut_compute


## The height half of the masked pair, `height_masked.gmacs`, whose bindings
## are the colour pair's, so `masked` drives it.
func height() -> SaCompute:
    if _height_compute == null and GlobalShaderCompiler.get_rd() != null:
        _height_compute = SaCompute.new("height_masked")
    return _height_compute


## Covers *below*, a landing chunk's height, by the moved paint: *above* is
## its height, null where it holds none, and *paint* its colour, whose alpha is
## how far it covers. `height_over` of `height.gmacs`, a mix where Merge Down
## adds, over the whole chunk the way the colour's `composite_chunk` is.
func land_height(below: SaTexture, above: SaTexture, paint: SaTexture) -> void:
    if _land_compute == null and GlobalShaderCompiler.get_rd() != null:
        _land_compute = SaCompute.new("height")
    if _land_compute == null or below == null or paint == null:
        return
    if above != null and above.format != below.format:
        above = null
    if above == null and (_no_height == null or _no_height.format != below.format):
        # What the kernel binds as the moved height where there is none, which
        # it never reads.
        _no_height = SaTexture.new(Vector2i.ONE, below.format)
    _land_compute.use_storage_format(below.format)
    _land_compute.use_binding_format(2, paint.format)
    _land_compute.set_texture(0, below.rid)
    _land_compute.set_texture(1, above.rid if above != null else _no_height.rid)
    _land_compute.set_texture(2, paint.rid)
    _land_compute.set_push_constant_float_array(PackedFloat32Array([1.0, 1.0 if above != null else 0.0]))
    _land_compute.dispatch_kernel("height_over", SaCompute.groups_for(below.size.x), SaCompute.groups_for(below.size.y), 1)


func shift() -> SaCompute:
    if _shift_compute == null and GlobalShaderCompiler.get_rd() != null:
        _shift_compute = SaCompute.new("crop")
    return _shift_compute


## The union of the chunks *layer* holds, in document pixels, which is the box
## when there is no device to measure the paint on. It lives beside the
## kernels rather than in the tool because a group's box needs it too, and it
## is the reduce's fallback.
static func chunk_union(layer: SaLayer) -> Rect2i:
    var out := Rect2i()
    if layer == null:
        return out
    var side := SaChunk.SIZE
    for grid_pos: Vector2i in layer.chunks:
        var chunk := Rect2i(grid_pos * side, Vector2i(side, side))
        out = chunk if not out.has_area() else out.merge(chunk)
    return out


## The box round *layer*'s paint in document pixels, the empty box when no
## texel holds any, and *fallback* when there is nothing on a device to reduce.
##
## `painted_bounds.gmacs` over every chunk the layer holds and nowhere else,
## which is hard rules 2 and 3, and four ints read back, which is the read
## `SaSelection.measure_bounds` makes and never a texel (hard rule 1). The
## colour is read for its alpha and the height, where a chunk has one, for its
## own value, into the same four. A chunk with no colour field cannot say
## where its paint is, so a layer with such a chunk answers *fallback* rather
## than a box that leaves it out.
func painted_box(layer: SaLayer, fallback: Rect2i) -> Rect2i:
    if layer == null or layer.chunks.is_empty() or GlobalShaderCompiler.get_rd() == null:
        return fallback
    for chunk: SaChunk in layer.chunks.values():
        var albedo: SaTexture = chunk.fields.get(SaFieldSpec.ALBEDO, null)
        if albedo == null or not albedo.rid.is_valid():
            return fallback
    if _bounds_compute == null:
        _bounds_compute = SaCompute.new("painted_bounds")
    var wide := PackedInt32Array([BOX_WIDE, BOX_WIDE, -BOX_WIDE, -BOX_WIDE]).to_byte_array()
    if _bounds_box == null:
        _bounds_box = SaCompute.Buffer.new(wide)
    else:
        _bounds_box.update(wide)
    var reach := SaChunkWalk.reach_of(layer.chunks.keys())
    var chunk_at := func(grid_pos: Vector2i) -> SaChunk: return layer.chunks.get(grid_pos, null)
    for field_id: StringName in [SaFieldSpec.ALBEDO, SaFieldSpec.HEIGHT]:
        var channel := 1.0 if field_id == SaFieldSpec.HEIGHT else 0.0
        var push := func(grid_pos: Vector2i, local: Rect2i, start: Vector2i) -> PackedFloat32Array:
            var chunk: SaChunk = layer.chunks[grid_pos]
            var scale := float(chunk.pixel_size()) / SaChunk.SIZE
            var origin := grid_pos * SaChunk.SIZE
            return PackedFloat32Array([start.x, start.y, local.end.x, local.end.y, origin.x, origin.y, scale, channel])
        var walk := SaChunkWalk.new(_bounds_compute, null, null, field_id)
        walk.run("painted_bounds", reach, chunk_at, push, {BOUNDS_BINDING: _bounds_box})
    var read := _bounds_box.read().to_int32_array()
    if read.size() < 4 or read[2] < read[0] or read[3] < read[1]:
        return Rect2i()
    return Rect2i(read[0], read[1], read[2] - read[0] + 1, read[3] - read[1] + 1)
