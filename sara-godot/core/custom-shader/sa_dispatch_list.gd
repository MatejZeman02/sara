## The one compute list an `SaCompute` has open, from begin to end.
##
## A compute list is Vulkan's recording of work: open one, bind a pipeline, bind
## a descriptor set and a push constant, dispatch, close it. Closing inserts a
## full barrier, which is why the count of lists matters as much as the count of
## dispatches and why a batched stroke is many dispatches under one list.
##
## The subject is the open list and nothing else. It holds the list's own id, the
## device it was opened on, and the one warning it has to say only once. What is
## bound into it, the descriptor set and the push constant bytes, arrives as
## arguments, so this knows nothing about the cache that built the set or the
## block that packed the bytes, and nothing takes its owner back.
##
## Reached by path rather than by a `class_name`, the way every half of the
## compiler is, because a class name resolves only after the editor rescans its
## class cache.
@tool
extends RefCounted

## By path like the rest of the compiler's halves, for the reason above. The
## statics are the ones `SaGpuTiming` names, because it is the same script.
const GpuTiming := preload("res://core/perf/sa_gpu_timing.gd")

## The open list, or -1 when there is none. Read by the owner to know whether the
## two calls after `begin()` have anything to act on.
var id: int = -1

var _rd: RenderingDevice = null

## The shader whose work this records, for the one warning.
var _shader_name: String = ""

## Set once an empty dispatch is skipped, so the warning does not repeat per
## frame.
var _warned_empty: bool = false

## The `shader_name/kernel_name` key SaCompute's per-kernel tally keys this
## list's dispatches by. Written by [method begin], read back by the owner so
## no second copy of the key travels alongside the list.
var label: String = ""


func _init(rd: RenderingDevice, shader_name: String) -> void:
    _rd = rd
    _shader_name = shader_name


## Opens a list and binds *pipeline* into it, under *new_label* for the tally.
##
## The timing pair opens before the list does, and closes in [method end] after
## the list has, because the engine refuses a timestamp while a list is open.
func begin(pipeline: RID, new_label: String = "") -> void:
    if _rd == null:
        return
    label = new_label
    # Asked here rather than inside, so an untimed run builds no key.
    if GpuTiming.enabled:
        GpuTiming.list_pair_begin(_rd, _timing_key())
    id = _rd.compute_list_begin()
    _rd.compute_list_bind_compute_pipeline(id, pipeline)


## Whether *x*, *y* and *z* groups are work worth submitting, said once when they
## are not.
##
## A zero group count means there is no work, but RenderingDevice treats it as an
## error rather than a no-op. Callers are expected to skip empty regions
## themselves, this is defence in depth, and it warns once so a real caller bug
## still surfaces.
func has_work(x_groups: int, y_groups: int, z_groups: int) -> bool:
    if x_groups > 0 and y_groups > 0 and z_groups > 0:
        return true
    if not _warned_empty:
        _warned_empty = true
        var groups := "(%d, %d, %d)" % [x_groups, y_groups, z_groups]
        push_warning("SaCompute('%s'): skipped an empty dispatch of %s groups." % [_shader_name, groups])
    return false


## Records one dispatch of *x* by *y* by *z* groups against *uniform_set* and
## *push_bytes*.
##
## An invalid set binds nothing, which is what a shader that did not compile
## leaves behind. Empty bytes
## bind nothing either, so a kernel with no `push_constant` block is dispatched
## rather than refused.
func dispatch(uniform_set: RID, push_bytes: PackedByteArray, x_groups: int, y_groups: int, z_groups: int) -> void:
    if id < 0:
        return
    if uniform_set.is_valid():
        _rd.compute_list_bind_uniform_set(id, uniform_set, 0)
    if not push_bytes.is_empty():
        _rd.compute_list_set_push_constant(id, push_bytes, push_bytes.size())
    _rd.compute_list_dispatch(id, x_groups, y_groups, z_groups)


## Binds *pipeline* into the open list, for a list that carries the dispatches
## of more than one kernel.
func bind(pipeline: RID) -> void:
    if id < 0:
        return
    _rd.compute_list_bind_compute_pipeline(id, pipeline)


## Orders every dispatch after this point behind every one before it, without
## closing the list.
##
## The engine splits the list in two at the barrier and binds back what was
## bound, so the cost is the device's and not a list end's three calls out of
## GDScript, the tally's and the timing pair's. It is the order
## `SaSmudgeReservoir` needs between a pickup and the dab reading its carry.
func barrier() -> void:
    if id < 0:
        return
    _rd.compute_list_add_barrier(id)


## Closes the list and submits the batch to the GPU.
func end() -> void:
    if id < 0:
        return
    _rd.compute_list_end()
    id = -1
    if GpuTiming.enabled:
        GpuTiming.list_pair_end(_timing_key())


## What the list's GPU time is filed under: the tally's key, or the shader alone
## for a caller that began the list with no label.
func _timing_key() -> String:
    return label if label != "" else _shader_name
