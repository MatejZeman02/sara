## One point filter's pass, recorded rather than run: a kernel, its push
## constant and its buffers by binding. The compositor previews it on the
## active layer at composite time and Apply walks it once over the chunks, so
## the preview and the result cannot disagree about what a slider meant.
##
## **The contract a point kernel keeps** is the one the base module's
## `adjust.gmacs` keeps. The
## chunk's colour field is image binding 0 and is rewritten in place, or a scratch copy of it is,
## when the pass previews. The selection mask is binding 1, `SaSelection.BINDING`, `r32f`, and the
## kernel reads it per pixel and mixes by it, because a 1 by 1 mask reads as 1.0 everywhere through
## a clamped read. Buffers sit from binding 2 upwards. The push constant is the filter's own, with
## two floats at [member origin_slot] that the runner writes: where the dispatched region starts in
## the chunk, zero for Apply, which covers whole chunks, and the dirty region's corner for the
## preview. A kernel adds that origin to `global_id` and stops at the chunk's edge.
##
## A kernel whose push constant block names a `vec2 chunk` is handed the chunk's document corner
## there as well, `grid_pos * SaChunk.SIZE` in document pixels, as [SaNeighbourhoodPass] hands its
## own. A pattern computed in document pixels, a dither above all, then runs on across a chunk
## border rather than starting again at every one.
##
## It names no layer. Whoever runs it hands over the texture it reads and the
## rectangle it covers, which is what lets a group or the document run the same
## record.
class_name SaPointPass
extends RefCounted

## The shader file the kernel is in, as the shader index knows it: the bare
## name for Sara's own, `<owner>/<name>` for a module's.
var shader: String = ""
## The kernel's entry point inside [member shader].
var kernel: String = ""
## The push constant as the filter wrote it. The two floats at
## [member origin_slot] are overwritten per dispatch by [method push_for].
var push: PackedFloat32Array = PackedFloat32Array()
## Binding -> `SaCompute.Buffer`, bound on every dispatch.
var buffers: Dictionary[int, SaCompute.Buffer] = {}
## Where the region's origin goes in [member push], x then y.
var origin_slot: int = 0
## Where the chunk's document corner goes in [member push], x then y, or -1
## when the kernel declares no `chunk` field and is handed none.
var corner_slot: int = -1


func _init(
    shader_key: String,
    kernel_name: String,
    push_constant: PackedFloat32Array,
    bound: Dictionary[int, SaCompute.Buffer] = {},
    origin_at: int = 0,
    corner_at: int = -1
) -> void:
    shader = shader_key
    kernel = kernel_name
    push = push_constant
    buffers = bound
    origin_slot = origin_at
    corner_slot = corner_at


## The push constant for a dispatch whose region starts at *origin* in the
## chunk, on the chunk whose document corner is *corner*.
func push_for(origin: Vector2i, corner: Vector2i = Vector2i.ZERO) -> PackedFloat32Array:
    var out := push.duplicate()
    out.resize(maxi(out.size(), maxi(origin_slot, corner_slot) + 2))
    out[origin_slot] = float(origin.x)
    out[origin_slot + 1] = float(origin.y)
    if corner_slot >= 0:
        out[corner_slot] = float(corner.x)
        out[corner_slot + 1] = float(corner.y)
    return out


## Binds every buffer of the pass on *compute*.
func bind(compute: SaCompute) -> void:
    for binding: int in buffers:
        var buffer := buffers[binding] as SaCompute.Buffer
        if buffer != null:
            compute.set_buffer(binding, buffer.rid)
