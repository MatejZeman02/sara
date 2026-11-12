## -------------------------------------------------------------------------
## Sara Brush Engine
## Copyright (c) 2026 [Matej Zeman]
##
## Portions of this compute shader infrastructure are based on the
## Acerola Compute Wrapper by Acerola (Garrett Gunnell).
## https://github.com/GarrettGunnell/Acerola-Compute/tree/main
##
## This software is released under the MIT License.
## The licence file is in this folder.
## https://opensource.org/licenses/MIT
## -------------------------------------------------------------------------
##
## Abstraction layer for dispatching Vulkan compute workloads.
##
## One call runs a kernel: [method run] takes a kernel name, the bindings and the
## params by the names the `.gmacs` declared, and the rectangle being painted, and
## derives everything else from them. Under that door sit the numbered calls the
## tree still uses, a bind by slot and a dispatch by group count.
##
## **What this class owns is the call**, and four objects own the pieces it is
## made of. `pipelines` owns the compiled variant and the RIDs it created. `slots`
## owns what the kernel declares at each binding and what is bound into it.
## `block` owns the push constant bytes and whether they are the size the shader
## asked for. `uniforms` owns the descriptor sets. `list` owns the open compute
## list. None of them takes this object back: they are handed RIDs, bytes and
## names, which is the whole point of the cut. Reading a field of one from outside
## is fine, `comp.pipelines.kernels` and `comp.block.bytes` are what the suites
## do, and each is written only by the class that holds it.
##
## Cut this way from one file of 694 lines and one sibling of 487 statics that
## took this object as their first argument.
@tool
extends RefCounted

## .gmacs: Godot Matej-Acerola Compute-Shader
class_name SaCompute

## The compiled pipelines of this shader at the variant this instance dispatches.
const Pipelines := preload("res://core/custom-shader/sa_pipelines.gd")

## What the kernel declares at each binding, and the binds into those slots.
const BindingSlots := preload("res://core/custom-shader/sa_binding_slots.gd")

## The push constant block: the bytes, and whether they are the declared size.
const PushConstants := preload("res://core/custom-shader/sa_push_constants.gd")

## The open compute list, from begin to end.
const DispatchList := preload("res://core/custom-shader/sa_dispatch_list.gd")

## The descriptor set cache, kept by the bindings that went into it.
const UniformSets := preload("res://core/custom-shader/sa_uniform_sets.gd")

var rd: RenderingDevice
var shader_name: String

## The compiled variant. Read from here as `pipelines.kernels` and
## `pipelines.shader_id`, and pointed at another format through the two `use_`
## doors below rather than written.
var pipelines: Pipelines = null

## What the kernel declares at each binding. Read from here as `slots.declared`.
var slots: BindingSlots = null

## The push constant block. Read from here as `block.bytes`, filled through the
## three `set_` doors below.
var block: PushConstants = null

## Every descriptor set this instance has built, and the one the next dispatch
## binds. Its own object because the cache is a whole concern and its fields are
## written by it alone. Read from here as `uniforms.gpu_id` and
## `uniforms.refresh`, told about a change with `uniforms.mark_dirty()`.
var uniforms: UniformSets = null

## The open compute list. Read from here as `list.id`, which is negative when
## there is none.
var list: DispatchList = null

## Cumulative GPU work counters, one for each way a stroke's dispatches can be
## made cheaper, so a change that claims a saving can show it:
##
## - `uniform_sets`, the uniform sets built. One per dispatch is caching that
##   has no effect at all rather than a small one.
## - `lists`. Every list end inserts a full barrier, so a batched list is many
##   dispatches under one list and this number stops tracking `dispatches`.
## - `workgroups`. A three-pixel dab still dispatches a whole chunk, and this is
##   where that shows up as a number rather than as a suspicion.
##
## Static because the interesting figure is across every SaCompute alive, not per
## instance, and cumulative because a reader that resets on sample cannot be read
## from two places at once. Four integer increments cost nothing beside a GPU
## dispatch, so they are always on: a counter behind a debug flag is a counter
## nobody reads.
##
## They stay here rather than moving to the list class with the begin and the end.
## They are this class's public ledger, read as `SaCompute.dispatches` by the
## capture harness and through `counters()` by the Info docker, and both of those
## live outside this folder. The list records the work, this counts it, one line
## either side of the call.
static var lists: int = 0
static var dispatches: int = 0
static var workgroups: int = 0
static var uniform_sets: int = 0

## The sRGB a composite with no space of its own packs, made once so its kept
## tail serves every such dispatch rather than being built for each.
static var _srgb: SaColorSpace = null

## The same three counted per kernel, keyed `shader_name/kernel_name`, each entry
## `{lists, dispatches, workgroups}`.
##
## The four counters above answer whether the session did more or less work.
## They cannot say which kernel did it, and a hot spot needs the second
## question answered. Kernel names repeat across shaders (`generate` is both
## `background.gmacs` and `paper.gmacs`), so the shader is part of the key.
static var by_kernel: Dictionary[String, Dictionary] = {}

## Moves on every [method reset_counters], so an instance knows the tallies it
## holds by kernel index were let go of with [member by_kernel].
static var _tally_generation: int = 0

## Bytes every live [Buffer] holds, the storage-buffer half of
## `SaTexture.allocated_bytes`. A `texture_copy` and a `storage_buffer_create`
## are both VRAM a session can leak, and a count of the textures alone misses half.
static var buffer_bytes: int = 0

## Index of the blend reference white within the packed composite block.
##
## It is the fourth float, filling out the 16-byte header the two matrices start
## after, rather than at the end, where the document's transfer curve takes the
## four trailing floats. So the block stays inside the 128 bytes Vulkan
## guarantees rather than growing past what every driver has to support.
##
## Written by index rather than appended, because SaColorSpace owns its own tail
## and W is a property of the document rather than of the colour space.
const COMPOSITE_BLEND_WHITE_INDEX: int = 3

## Where the composite block's density sits: the last float of the colour
## space's tail, which would otherwise only pad the block to a multiple of
## sixteen bytes. `pack_composite_params` writes it after the tail is appended.
const COMPOSITE_DENSITY_INDEX: int = 4 + SaColorSpacePushConstant.PUSH_CONSTANT_FLOATS - 1

## Compute kernels in Sara are 8x8, and both the compositor and the paint context
## align their regions to that. One number rather than three copies of it.
const WORKGROUP_SIZE: int = 8

## What [method set_image] and [method set_params] were handed, by the names the
## kernel declares, so that [method dispatch]'s named form can run the whole call.
##
## Held rather than passed, because the spec's box blur binds and sets in four
## separate lines and dispatches in a fifth, and those five lines are the
## contract. The numbered dispatch reads none of this.
var _named_images: Dictionary[String, Variant] = {}
var _named_params: Dictionary[String, Variant] = {}

## False only while [method dispatch] is running the call itself, so the region it
## folds into the params is not remembered as the caller's.
var _remembering: bool = true

## Where on the canvas the named dispatch's rectangle starts, in document pixels.
## Zero until somebody says otherwise.
##
## `dispatch(name, size)` has a size and nothing else, so without this a kernel
## declaring `origin` would be handed `(0, 0)` wherever it was really running.
## Silently: no error, and a plausible picture everywhere but over a selection.
var _named_origin: Vector2i = Vector2i.ZERO

## The storage buffers [method run] packs the params the dialect moved out of
## the push constant into, by the buffer's block name. Held for the instance's
## life, because a buffer freed when the call returns is a binding the dispatch
## finds invalid, and updated in place so the uniform set built on it stays.
var _moved_buffers: Dictionary[String, Buffer] = {}

## `shader_name/kernel_name` per kernel index of this instance, built lazily so
## `list_begin` allocates nothing after a kernel's first dispatch. Cleared on a
## reload, because a recompile can move a kernel's index.
var _kernel_keys: Array[String] = []

## The tally of [member by_kernel] per kernel index of this instance, held so a
## dispatch counts with one array read and no string hashed. Good while
## [member _tallies_of] is [member _tally_generation], and cleared on a reload
## with the keys it is filed under.
var _tallies: Array[Dictionary] = []
var _tallies_of: int = -1

## The tally of the list [method list_begin] opened, which its dispatches count in.
var _open_tally: Dictionary = {}

## Kernel indices by name as the compiler answered them, so a dispatch by name
## asks the compiler once. A name it does not know is asked again every
## time, because the kernel may compile later. Cleared on a reload.
var _indices: Dictionary[String, int] = {}


## Back to zero, so a caller can measure one stroke rather than a session.
static func reset_counters() -> void:
    lists = 0
    dispatches = 0
    workgroups = 0
    uniform_sets = 0
    _tally_generation += 1
    Pipelines.loads = 0
    Pipelines.load_usec = 0
    by_kernel.clear()


## The counters as one dictionary, for the info overlay and the capture dump.
static func counters() -> Dictionary[String, int]:
    return {
        "lists": lists,
        "dispatches": dispatches,
        "workgroups": workgroups,
        "uniform_sets": uniform_sets,
        "pipeline_loads": Pipelines.loads,
        "pipeline_load_usec": Pipelines.load_usec,
    }


## The per-kernel tally as a deep copy, so a reader cannot mutate the ledger.
static func kernel_counters() -> Dictionary[String, Dictionary]:
    var copy: Dictionary[String, Dictionary] = {}
    for key: String in by_kernel:
        copy[key] = by_kernel[key].duplicate()
    return copy


## Bumps `by_kernel[key].lists`, creating the entry on its first list.
static func _note_kernel_list(key: String) -> void:
    var entry := _tally(key)
    entry["lists"] += 1


## Bumps `by_kernel[key].dispatches` and `.workgroups`, creating the entry on
## its first dispatch.
static func _note_kernel_dispatch(key: String, workgroup_count: int) -> void:
    var entry := _tally(key)
    entry["dispatches"] += 1
    entry["workgroups"] += workgroup_count


## The tally *key* is counted in, filed at zero on its first use.
static func _tally(key: String) -> Dictionary[String, int]:
    if not by_kernel.has(key):
        var fresh: Dictionary[String, int] = {"lists": 0, "dispatches": 0, "workgroups": 0}
        by_kernel[key] = fresh
    return by_kernel[key]


func _init(_shader_name: String) -> void:
    assert(not _shader_name.is_empty(), "Shader name cannot be empty")
    shader_name = _shader_name
    rd = GlobalShaderCompiler.get_rd()
    # Before the null return, so a run with no device still has the five objects
    # rather than a null every call has to check.
    uniforms = UniformSets.new(rd)
    slots = BindingSlots.new(shader_name, uniforms)
    block = PushConstants.new(shader_name)
    list = DispatchList.new(rd, shader_name)
    pipelines = Pipelines.new(rd, shader_name)
    if rd == null:
        return
    slots.relearn()


## Points this instance at the variant compiled for *format*.
##
## Cheap and idempotent: the common case is that nothing changed and the pipelines
## answer no on the first line. A reload rebuilds the uniform set, because a set is
## created against a specific shader RID, and re-reads the declarations, because a
## recompile can move a binding.
func use_storage_format(format: int) -> void:
    if pipelines.use_storage_format(format):
        _after_reload()


## Points one image binding at *format*, whatever the storage format says.
##
## Refused, with an error, on a binding that did not write the storage-format
## token: a sampler has no qualifier and a literal one is the kernel's decision.
## Idempotent like [method use_storage_format], and a reload does the same two
## things afterwards.
func use_binding_format(binding: int, format: int) -> void:
    var current: int = pipelines.binding_formats.get(binding, -1)
    if current == format:
        return
    if rd != null and not slots.declares_storage_token(binding):
        push_error(
            (
                "SaCompute('%s'): binding %d does not declare %s, so it cannot take a format of its own."
                % [shader_name, binding, GlobalShaderCompiler.STORAGE_FORMAT_TOKEN]
            )
        )
        return
    if pipelines.use_binding_format(binding, format):
        _after_reload()


## Sets push constants from a float array, padded out to the 16-byte boundary.
func set_push_constant_float_array(data: PackedFloat32Array) -> void:
    block.fill_from_floats(data)


## Sets push constants from a raw byte array the caller laid out itself.
func set_push_constant(data: PackedByteArray) -> void:
    block.fill_from_bytes(data)


## The same three binds and the push constant, by the names the kernel wrote.
##
## A `.gmacs` names its fields and its bindings, and without the door both names
## are dropped: a positional float array matched to the block by eye, and a slot
## number the caller counted. The block holds the packing and the refusals,
## and this prefixes the shader's name onto whatever it complains about.
##
## *values* stays an untyped Dictionary because this is the door: a module hands
## in whatever it built, and a third party's must not break on a refactoring.
func set_params(values: Dictionary) -> void:
    if _remembering:
        # Copied into a typed Dictionary where it enters, since a module's
        # values arrive untyped. `str` keeps a key that names no field refusable.
        var remembered: Dictionary[String, Variant] = {}
        for key: Variant in values:
            remembered[str(key)] = values[key]
        _named_params = remembered
    var layout := GlobalShaderCompiler.push_constant_layout(shader_name)
    var problem := block.fill_from_values(layout, values)
    if not problem.is_empty():
        push_error("SaCompute('%s'): %s" % [shader_name, problem])


## Packs a composite kernel's push constant: the destination offset and opacity,
## the blend reference white, then the document's colour space.
##
## 128 bytes, exactly the Vulkan guarantee. The two matrices are `float[9]`
## rather than `mat3`, because std430 pads every column of a mat3 out to 16
## bytes, and the 24 bytes that saves hold the coordinate system. A null space
## means gamma sRGB in RGB coordinates with an identity matrix pair, which is
## what a caller with no document in hand should get.
##
## *density* is how many of the source's texels lie along one destination pixel,
## 2 for a chunk at twice the document's resolution, and zero is read as 1. It
## takes the colour space tail's last float, otherwise padding, and *offset* and
## *region* are in destination pixels.
static func pack_composite_params(
    offset: Vector2,
    opacity: float,
    space: SaColorSpace = null,
    density: float = 0.0,
    blend_white: float = 1.0,
    region: Rect2i = Rect2i()
) -> PackedFloat32Array:
    var params := PackedFloat32Array([offset.x, offset.y, opacity, 0.0])
    if space == null and _srgb == null:
        _srgb = SaColorSpace.srgb()
    params.append_array((space if space != null else _srgb).to_push_constant())
    params[COMPOSITE_DENSITY_INDEX] = density
    # A zero or negative window would divide the display-referred modes by
    # nothing. The shader guards too, so this is belt and braces rather than the
    # only line of defence.
    params[COMPOSITE_BLEND_WHITE_INDEX] = blend_white if blend_white > 0.0 else 1.0
    var covered := region if region.size.x > 0 and region.size.y > 0 else Rect2i(0, 0, SaChunk.SIZE, SaChunk.SIZE)
    params.append_array(PackedFloat32Array([covered.position.x, covered.position.y, covered.size.x, covered.size.y]))
    return params


## *values* packed by name into the bytes *layout* declares, std430, or empty
## when they do not fit it. For a caller that records a pass and binds its own
## bytes, as a pixel function does, through the face this package shows.
static func pack_block(layout: Array, values: Dictionary) -> PackedByteArray:
    return PushConstants.pack(layout, values)


## Workgroups along one axis for *pixels* of work, never zero.
##
## `int(3 / 8)` is 0, and RenderingDevice rejects a zero group count rather than
## treating it as no work, a crash the small rectangles of a fast stroke reach.
static func groups_for(pixels: int) -> int:
    return maxi(1, ceili(float(pixels) / float(WORKGROUP_SIZE)))


## Binds a storage image at a slot the caller counted.
func set_texture(binding: int, texture_rid: RID) -> void:
    slots.bind_image(binding, texture_rid)


## Binds a sampled texture at a slot the caller counted.
func set_sampled_texture(
    binding: int,
    texture_rid: RID,
    filter: int = RenderingDevice.SAMPLER_FILTER_LINEAR,
    repeat: int = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
) -> void:
    slots.bind_sampler(binding, texture_rid, filter, repeat)


## Binds a storage buffer at a slot the caller counted. See [Buffer] below for the
## RAII wrapper that owns one.
func set_buffer(binding: int, buffer_rid: RID) -> void:
    slots.bind_buffer(binding, buffer_rid)


## Binds *texture* to the image the kernel calls *image_name*, and remembers it.
##
## *texture* is an `SaTexture` or a bare `RID`. The spec's box blur writes
## `kernel.set_image("src", src)` with the texture `layer_pixels` answered, and the
## forty-two lines of that file are the contract this door is measured against, so
## the door takes what the student has rather than asking for the RID inside it.
##
## What is remembered is what [method dispatch]'s named form runs with. A dispatch
## by kernel index is unchanged and reads none of it.
func set_image(image_name: String, texture: Variant) -> void:
    _named_images[image_name] = texture
    var slot := slots.slot_for(image_name, "image")
    if slot >= 0:
        set_texture(slot, BindingSlots.rid_of(texture))


## Binds a sampled texture to the sampler the kernel calls *sampler_name*.
func set_sampler(
    sampler_name: String,
    texture_rid: RID,
    filter: int = RenderingDevice.SAMPLER_FILTER_LINEAR,
    repeat: int = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
) -> void:
    var slot := slots.slot_for(sampler_name, "sampler")
    if slot >= 0:
        set_sampled_texture(slot, texture_rid, filter, repeat)


## Binds a storage buffer to the block or instance the kernel calls *buffer_name*.
func set_storage(buffer_name: String, buffer_rid: RID) -> void:
    var slot := slots.slot_for(buffer_name, "buffer")
    if slot >= 0:
        set_buffer(slot, buffer_rid)


## Binds every storage buffer in *buffers*, { name -> RID }, by its name. A blend
## mode's side data arrives this way, see SaBlendModeDescriptor.extra_buffers.
func set_storages(buffers: Dictionary) -> void:
    for buffer_name: String in buffers:
        var rid: RID = buffers[buffer_name]
        set_storage(buffer_name, rid)


## Says where the next named dispatches run, for a caller that knows and a size
## that cannot say.
##
## Beside [method use_storage_format], and for the same kind of reason: what the
## instance dispatches against, told once and kept, rather than an argument on
## every call. A filter's context calls it, so the box blur the spec prints keeps
## the one-line dispatch its forty-two lines are pinned to.
func use_region(region: Rect2i) -> void:
    _named_origin = region.position


## One kernel run as one call: the bindings by name, the params by name, and the
## groups counted off the rectangle rather than by the caller.
##
## Positional and nothing optional. The order is the order the pieces depend on
## each other. The storage format comes first
## because changing it reloads the pipelines and rebuilds the uniform set, then the
## images that carry a format of their own, then the binds, then the block, then the
## dispatch. A complaint about a binding or a field stops the call before anything
## reaches the GPU, so a mistake costs an error naming it rather than a wrong picture.
##
## The declarations are read from the compiler rather than from `slots`, because a
## run on an instance whose kernels never loaded still has to say which name was
## wrong.
##
## A params field the dialect moved into a storage buffer, because the block
## would not fit the push constant with it, is passed in *params* like any other
## and packed into a buffer this instance holds, so a caller never learns which
## fields moved.
##
## *bindings* and *params* stay untyped Dictionaries, the door's rule: a module
## passes whatever it built, and a third party's must not break on a refactoring.
func run(kernel_name: String, bindings: Dictionary, params: Dictionary, region: Rect2i) -> void:
    var declared := GlobalShaderCompiler.binding_layout(shader_name)
    var moved := BindingSlots.moved_params(declared)
    if not moved.is_empty():
        bindings = bindings.duplicate()
        params = params.duplicate()
    var problem := _carry_moved(moved, bindings, params)
    if problem.is_empty():
        problem = BindingSlots.binding_complaint(declared, bindings)
    if not problem.is_empty():
        push_error("SaCompute('%s').run('%s'): %s" % [shader_name, kernel_name, problem])
        return
    if region.size.x <= 0 or region.size.y <= 0:
        push_error(
            "SaCompute('%s').run('%s'): the region is empty, so there is nothing to dispatch." % [shader_name, kernel_name]
        )
        return

    _follow_the_images(declared, bindings)
    var order: Array = declared.keys()
    order.sort()
    for binding: int in order:
        var entry: Dictionary[String, String] = declared[binding]
        var rid := BindingSlots.rid_of(BindingSlots.value_for(entry, bindings))
        match str(entry.get("kind", "")):
            "image":
                set_texture(binding, rid)
            "sampler":
                set_sampled_texture(binding, rid)
            "buffer":
                set_buffer(binding, rid)

    var layout := GlobalShaderCompiler.push_constant_layout(shader_name)
    if not layout.is_empty():
        set_params(PushConstants.with_region(layout, params, region))
    elif not params.is_empty():
        push_error(
            (
                "SaCompute('%s').run('%s'): %d value(s) were passed and the kernel declares no params block."
                % [shader_name, kernel_name, params.size()]
            )
        )
        return

    var group := GlobalShaderCompiler.workgroup_size(shader_name, kernel_name)
    var wide: int = group[0]
    var tall: int = group[1]
    dispatch_kernel(kernel_name, _groups_along(region.size.x, wide), _groups_along(region.size.y, tall), 1)


## Takes every field in *moved* out of *params* and into *bindings*, as a buffer
## holding its bytes, and answers what was wrong, empty when nothing was.
##
## Both Dictionaries are the copies [method run] made when anything moved, so
## the caller's own are not changed under it. The field is packed by the same packer and the same
## refusals as a field of the block, because the buffer is std430 too.
func _carry_moved(moved: Array[Dictionary], bindings: Dictionary, params: Dictionary) -> String:
    for field: Dictionary in moved:
        var name := str(field["name"])
        var layout: Array = field["layout"]
        var given := {name: params.get(name)} if params.has(name) else {}
        var problem := PushConstants.complaint(layout, given)
        if not problem.is_empty():
            return problem
        bindings[field["block"]] = _moved_buffer(str(field["block"]), PushConstants.pack(layout, given))
        params.erase(name)
    return ""


## The buffer *block_name* is bound to, holding *bytes*: the one this instance
## made for it last time and updated in place, or a new one when there is none.
func _moved_buffer(block_name: String, bytes: PackedByteArray) -> Buffer:
    var held: Buffer = _moved_buffers.get(block_name)
    if held != null and held.size == bytes.size():
        held.update(bytes)
        return held
    held = Buffer.new(bytes)
    _moved_buffers[block_name] = held
    return held


## Opens the communication queue with the GPU.
func list_begin(kernel_index: int = 0) -> void:
    # No device, no queue, and nothing to say about it that boot has not already
    # said once. Without this the canvas goes on asking for a dispatch it can
    # never get, and a machine with no driver writes the kernel-index errors
    # below, several a frame for as long as the app is open. Refusing here is
    # what "an empty canvas that refuses to paint" means
    # from the canvas's side.
    if rd == null:
        return

    # Check for hot-reloads, but only when one can have happened.
    if pipelines.follow_recompiles():
        _after_reload()

    if not pipelines.holds(kernel_index):
        push_error(
            (
                "SaCompute('%s'): kernel index %d is not a compiled one of its %d kernels."
                % [shader_name, kernel_index, pipelines.kernels.size()]
            )
        )
        return

    lists += 1
    var tally := _tally_at(kernel_index)
    tally["lists"] += 1
    _open_tally = tally
    list.begin(pipelines.kernels[kernel_index], _kernel_keys[kernel_index])


## Adds work to the open queue.
func list_dispatch(x_groups: int, y_groups: int, z_groups: int) -> void:
    # list_begin refused to open a list, so there is no queue to add work to.
    if list.id < 0:
        return
    if not list.has_work(x_groups, y_groups, z_groups):
        return

    # The bindings changed, so this dispatch needs a different set. It may well be
    # one already built: ask the cache rather than assuming a new one is needed.
    if uniforms.refresh or not uniforms.gpu_id.is_valid():
        uniform_sets += uniforms.rebuild(pipelines.shader_id)

    var count := x_groups * y_groups * z_groups
    dispatches += 1
    workgroups += count
    _open_tally["dispatches"] += 1
    _open_tally["workgroups"] += count
    list.dispatch(uniforms.gpu_id, block.bytes, x_groups, y_groups, z_groups)


## Closes the queue and submits the entire batch to the GPU.
func list_end() -> void:
    list.end()


## brush calls of dispatch (no batching)
##
## Prefer [method dispatch_kernel]. The index is a position in the shader's
## `#kernel` list, so writing it here is what made that order load-bearing. Two
## forms, and the second is why this one is untyped.
##
## `dispatch(index, x, y, z)` is the numbered form every caller in the tree uses,
## unchanged: three group counts, already divided by the workgroup size.
##
## `dispatch("blur", src.size)` is the form the spec's box blur writes, and it takes
## a **pixel size** rather than group counts. It runs the whole call the way
## [method run] does, over the images and params [method set_image] and
## [method set_params] remembered: the storage format follows the images, the region
## fills any `origin` and `extent` the block declares, and the size is divided by the
## kernel's own workgroup. A student who has to work out a group count is a student
## who has met the workgroup size, which is the thing the dialect exists to hide.
func dispatch(kernel: Variant, groups: Variant, y_groups: int = 1, z_groups: int = 1) -> void:
    if kernel is String or kernel is StringName:
        var size := Vector2i(0, y_groups)
        if groups is Vector2i:
            size = groups
        else:
            var along: int = groups
            size.x = along
        # `run` calls `set_params` with the region folded in, and remembering that
        # would carry this dispatch's rectangle into the next one.
        _remembering = false
        run(str(kernel), _named_images, _named_params, Rect2i(_named_origin, size))
        _remembering = true
        return
    var kernel_index: int = kernel
    var x_groups: int = groups
    _dispatch_at(kernel_index, x_groups, y_groups, z_groups)


## One list of one dispatch of the kernel at *kernel_index*, what both
## numbered forms of a dispatch come down to.
func _dispatch_at(kernel_index: int, x_groups: int, y_groups: int, z_groups: int) -> void:
    list_begin(kernel_index)
    list_dispatch(x_groups, y_groups, z_groups)
    list_end()


## Index of a kernel of *this* shader by its `#kernel` name, or -1 when there is no
## such kernel.
func index_of_kernel(kernel_name: String) -> int:
    var known: int = _indices.get(kernel_name, -1)
    if known >= 0:
        return known
    var asked := pipelines.index_of(kernel_name)
    if asked >= 0:
        _indices[kernel_name] = asked
    return asked


## Dispatches the kernel *kernel_name* names, one group deep unless *z_groups*
## says more, and says so when there is none.
##
## A shader with one kernel is where the numbered form hides best: `dispatch(0)`
## reads as "the only kernel" right up until someone adds a second one above it, at
## which point every such call is silently doing the wrong work. Naming the kernel
## costs the same and cannot go stale.
func dispatch_kernel(kernel_name: String, x_groups: int, y_groups: int, z_groups: int = 1) -> void:
    var index := index_of_kernel(kernel_name)
    if index < 0:
        push_error("SaCompute('%s'): no kernel named '%s'." % [shader_name, kernel_name])
        return
    _dispatch_at(index, x_groups, y_groups, z_groups)


## Dispatches the kernel *kernel_name* names at storage *format* into the list
## already open for it, and first closes whatever list is open, switches to
## *format* and opens one for the kernel when that list is not the one open.
## Bind before the call, as for [method list_dispatch].
##
## What a caller whose every dispatch writes a texture of its own reaches for:
## called once a dispatch, it keeps one list for all of them and one barrier
## at [method list_end], which the caller calls after the last. Followed by
## [method list_end] every time, it is [method dispatch_kernel] with the format
## said, which is how `SaChunkWalk` dispatches a walk that has to keep its
## barriers. The format is part of the question because switching it reloads
## the kernels, which cannot happen under an open list.
func list_dispatch_kernel(kernel_name: String, format: int, x_groups: int, y_groups: int, z_groups: int) -> void:
    var index := index_of_kernel(kernel_name)
    if index < 0:
        push_error("SaCompute('%s'): no kernel named '%s'." % [shader_name, kernel_name])
        return
    if list.id < 0 or format != pipelines.storage_format or list.label != _kernel_key_for(index):
        list_end()
        use_storage_format(format)
        list_begin(index)
    list_dispatch(x_groups, y_groups, z_groups)


## Settles the dispatch of *kernel_name* at storage *format* over the groups
## given, with what is bound and pushed now, and answers it for [method submit]
## to issue later. Null when there is no device, no such kernel or no work.
##
## Everything a dispatch asks of the device before the list opens happens here:
## the format, a reload after a recompile and the uniform set. So a caller can
## grow a texture or allocate a chunk between two records, which it cannot do
## under an open list, and still send the work as one list. *after_barrier* says
## this dispatch has to wait for every one recorded before it. Nothing is
## counted until the submit, because a record that is never sent is no work.
func record(kernel_name: String, format: int, x_groups: int, y_groups: int, z_groups: int, after_barrier: bool) -> Recorded:
    if rd == null:
        return null
    var index := index_of_kernel(kernel_name)
    if index < 0:
        push_error("SaCompute('%s'): no kernel named '%s'." % [shader_name, kernel_name])
        return null
    use_storage_format(format)
    if pipelines.follow_recompiles():
        _after_reload()
    if not pipelines.holds(index) or not list.has_work(x_groups, y_groups, z_groups):
        return null
    if uniforms.refresh or not uniforms.gpu_id.is_valid():
        uniform_sets += uniforms.rebuild(pipelines.shader_id)
    var groups := Vector3i(x_groups, y_groups, z_groups)
    return Recorded.new(
        pipelines.kernels[index], uniforms.gpu_id, block.bytes.duplicate(), groups, _kernel_key_for(index), after_barrier
    )


## Issues *recorded*, the answers of [method record] from any number of
## instances, in order under one compute list, counted and timed under *label*.
##
## One list rather than one a dispatch, with a barrier inside it wherever a
## record asked for one. The lists counter moves by one, and each
## dispatch is counted under its own kernel, so the per-kernel table still says
## which kernel did the work while the time goes to *label*.
##
## *dabs* holds the target count of each dab the list lays, told to the stroke
## ledger once the list is sent, which is when those dabs were dispatched. A
## module sees the door and not the ledger, so the door reports for it.
static func submit(recorded: Array[Recorded], label: String, dabs := PackedInt32Array()) -> void:
    var device := GlobalShaderCompiler.get_rd()
    if device == null or recorded.is_empty():
        return
    var open := DispatchList.new(device, label)
    lists += 1
    _note_kernel_list(label)
    var bound := recorded[0].pipeline
    open.begin(bound, label)
    for at: int in recorded.size():
        var one := recorded[at]
        if at > 0 and one.after_barrier:
            open.barrier()
        if one.pipeline != bound:
            bound = one.pipeline
            open.bind(bound)
        var count := one.groups.x * one.groups.y * one.groups.z
        dispatches += 1
        workgroups += count
        _note_kernel_dispatch(one.key, count)
        open.dispatch(one.uniform_set, one.bytes, one.groups.x, one.groups.y, one.groups.z)
    open.end()
    for target_count: int in dabs:
        SaStrokeLedger.dab_dispatched(target_count)


# --- Internal Methods ---


## What follows a pipeline reload, and the reason the reload answers a bool.
##
## A descriptor set is created against a specific shader RID, so every cached set
## is stale. And a recompile can move a binding, so the declarations have to be
## read again rather than trusted.
func _after_reload() -> void:
    slots.relearn()
    uniforms.mark_dirty()
    _kernel_keys.clear()
    _tallies.clear()
    _indices.clear()


## The tally key for *kernel_index* of this instance's shader, cached after the
## first call so a hot stroke pays one string build per kernel rather than one
## per dispatch.
func _kernel_key_for(kernel_index: int) -> String:
    if _kernel_keys.size() != pipelines.kernels.size():
        _kernel_keys.resize(pipelines.kernels.size())
    var cached: String = _kernel_keys[kernel_index]
    if not cached.is_empty():
        return cached
    var names := GlobalShaderCompiler.get_kernel_names(shader_name)
    var built := "%s/%s" % [shader_name, names[kernel_index]] if kernel_index < names.size() else shader_name
    _kernel_keys[kernel_index] = built
    return built


## The tally [member by_kernel] counts *kernel_index*'s lists and dispatches
## in, found once a kernel and a reset rather than once a dispatch.
func _tally_at(kernel_index: int) -> Dictionary:
    if _tallies_of != _tally_generation:
        _tallies.clear()
        _tallies_of = _tally_generation
    if _tallies.size() != pipelines.kernels.size():
        _tallies.resize(pipelines.kernels.size())
    var held: Dictionary = _tallies[kernel_index]
    if held.is_empty():
        held = _tally(_kernel_key_for(kernel_index))
        _tallies[kernel_index] = held
    return held


## Points the instance at the format its images are stored at.
##
## The lowest image binding decides the variant, which for every kernel in the tree
## is the canvas or the target, and an image at another depth takes a format of its
## own so that a `r32f` mask beside an `rgba32f` canvas compiles as itself. That
## mismatch is undefined across the whole image rather than at one texel, and it
## returns entirely plausible numbers on some hardware. Only a binding that
## wrote the storage-format
## token can take one, so a kernel that spelled its own qualifier is left alone.
func _follow_the_images(declared: Dictionary[int, Dictionary], bindings: Dictionary) -> void:
    var order: Array = declared.keys()
    order.sort()
    var document := -1
    for binding: int in order:
        var entry: Dictionary[String, String] = declared[binding]
        if str(entry.get("kind", "")) != "image":
            continue
        var format := BindingSlots.format_of(BindingSlots.value_for(entry, bindings))
        if format < 0:
            continue
        if document < 0:
            document = format
            use_storage_format(format)
        elif format != document and str(entry.get("format", "")) == GlobalShaderCompiler.STORAGE_FORMAT_TOKEN:
            use_binding_format(binding, format)


## Workgroups along one axis for *pixels* of work at a group *wide* pixels, never
## zero.
##
## [method groups_for] is the same arithmetic with the group width fixed at eight, and
## it stays as the helper a caller counting its own dispatch reaches for. This one
## asks the kernel instead: a `64, 1, 1` kernel over sixty-four pixels is one group,
## and dividing by eight made it eight groups of sixty-four, eight times the
## invocations for the same work and against hard rule 2.
##
## `maxi` on both sides for the same reason [method groups_for] has one: `int(3 / 8)`
## is 0 and RenderingDevice refuses a zero group count rather than reading it as no
## work, and a kernel that somehow declared a group of zero would divide by it.
static func _groups_along(pixels: int, wide: int) -> int:
    return maxi(1, ceili(float(pixels) / float(maxi(wide, 1))))


## A storage buffer a kernel indexes, owned the way SaTexture owns a texture.
##
## A curve, a palette, a lookup table, a per-dab array: side data that has no
## channel to travel in, because the push constant is bounded by the 128 bytes
## Vulkan guarantees and the composite block already spends all of them. The bytes
## are laid out by the caller and read back as bytes, so the std430 rules are the
## caller's to honour. `float`, `int`, `vec2` and `vec4` pack the way
## PackedFloat32Array does. `vec3` does not: std430 pads it to 16 bytes, so a
## `vec3[]` has a stride of 16 and the twelve-byte packing a GDScript array produces
## reads every entry after the first from the wrong place.
##
## One dispatch settled by [method record]: the pipeline, the uniform set, the
## push constant bytes and the groups, as they stood when it was recorded, and
## the tally key it is counted under once [method submit] issues it.
##
## Inner for the reason [Buffer] is. The set is one the recording instance's
## cache holds, and a set the cache lets go of is freed at the frame's end
## rather than at once, so a record submitted in the frame it was made in binds
## a live set.
class Recorded:
    extends RefCounted

    var pipeline: RID
    var uniform_set: RID
    var bytes: PackedByteArray
    var groups: Vector3i
    var key: String

    ## Whether the dispatch waits for every one recorded before it.
    var after_barrier: bool

    func _init(
        _pipeline: RID, _uniform_set: RID, _bytes: PackedByteArray, _groups: Vector3i, _key: String, _after_barrier: bool
    ) -> void:
        pipeline = _pipeline
        uniform_set = _uniform_set
        bytes = _bytes
        groups = _groups
        key = _key
        after_barrier = _after_barrier


## Inner rather than a `class_name` of its own so that no rescan of the class cache
## stands between a fresh checkout and a green gate, and inner rather than a file
## beside this one because `core/api/selection/sa_selection.gd` and `core/image/sa_adjustments.gd` name
## it `SaCompute.Buffer`.
class Buffer:
    extends RefCounted

    var rid: RID
    var rd: RenderingDevice

    ## Bytes the buffer holds, fixed at creation.
    var size: int = 0

    func _init(bytes: PackedByteArray) -> void:
        assert(not bytes.is_empty(), "A buffer needs its contents, so its size is known")
        rd = GlobalShaderCompiler.get_rd()
        if rd == null:
            return
        size = bytes.size()
        rid = rd.storage_buffer_create(size, bytes)
        assert(rid.is_valid(), "Failed to create a storage buffer")
        SaCompute.buffer_bytes += size

    ## Overwrites part or all of the buffer in place, without reallocating, so a
    ## uniform set built against it stays valid.
    func update(bytes: PackedByteArray, offset: int = 0) -> void:
        assert(offset + bytes.size() <= size, "An update cannot run past the end of the buffer")
        if rd != null and rid.is_valid():
            rd.buffer_update(rid, offset, bytes.size(), bytes)

    ## The buffer's bytes, back on the CPU. A readback stalls on the GPU like any
    ## other, so it is for a result a kernel computed, never for the hot path.
    ## The wait is handed to the GPU timing, which folds what the read's flush
    ## made readable.
    func read(offset: int = 0, length: int = -1) -> PackedByteArray:
        if rd == null or not rid.is_valid():
            return PackedByteArray()
        var wanted := length if length >= 0 else size - offset
        var asked := Time.get_ticks_usec()
        var bytes := rd.buffer_get_data(rid, offset, wanted)
        DispatchList.GpuTiming.read_done(rd, Time.get_ticks_usec() - asked)
        return bytes

    ## Asks for the buffer's bytes without waiting, *then* called with them as
    ## a later frame is drawn. Anything but OK means *then* is never called.
    func ask(then: Callable, offset: int = 0, length: int = -1) -> Error:
        if rd == null or not rid.is_valid():
            return FAILED
        return rd.buffer_get_data_async(rid, then, offset, length if length >= 0 else size - offset)

    func _notification(what: int) -> void:
        if what == NOTIFICATION_PREDELETE:
            if rid.is_valid() and rd != null:
                rd.free_rid(rid)
                rid = RID()
                SaCompute.buffer_bytes -= size
