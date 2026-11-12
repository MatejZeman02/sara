## The compute pipelines of one shader, at the variant this instance dispatches.
##
## A `.gmacs` compiles to one shader RID per `#kernel`, and a pipeline is created
## against each. Which set of them exists at any moment is a question with three
## inputs: the shader's name, the storage format the instance paints at, and the
## bindings that were given a format of their own. Change any of the three and
## every pipeline is freed and made again, because a pipeline belongs to the
## shader RID it was built from.
##
## That is the whole subject, and it is why this is a class rather than a group
## of fields on `SaCompute`. The RIDs are created here, so they are freed here,
## and nothing outside decides when. The owner asks for a reload and is told
## whether one happened, because two other things follow a reload: the descriptor
## set cache is invalid, and the declared bindings have to be read again.
##
## Reached by path rather than by a `class_name`, the way every half of the
## compiler is, because a class name resolves only after the editor rescans its
## class cache.
@tool
extends RefCounted

## One compute pipeline per kernel the shader declares, in `#kernel` order.
##
## A kernel that failed to compile still takes its slot, for the same reason the
## compiler keeps a failed kernel's: an index into this array is the kernel's
## name as far as every numbered dispatch is concerned.
var kernels: Array[RID] = []

## The shader RID the first kernel compiled to, which is what a descriptor set is
## built against and what a hot reload is noticed by.
var shader_id: RID

## Which compiled variant this instance dispatches.
##
## A kernel's `layout()` format has to match the bound image view's or every load
## and store is undefined across the whole image, so a dispatch at F16 chunks
## needs the F16 build of the same kernel. Callers set this from the texture they
## are about to bind.
var storage_format: int = GlobalShaderCompiler.DEFAULT_STORAGE_FORMAT

## Bindings that take a format of their own rather than `storage_format`, as
## binding index -> RenderingDevice.DATA_FORMAT_*. A mask beside a canvas is the
## case: `r32f` at one binding, the document's depth at the others. Part of which
## variant this instance dispatches, alongside storage_format.
var binding_formats: Dictionary[int, int] = {}

## The device the pipelines are created on and freed against, or null in a run
## that has none.
var _rd: RenderingDevice = null

## The shader whose kernels these are, for the compiler lookups and the errors.
var _shader_name: String = ""

## How many loads the process has made, and the microseconds they took, a
## compile of a variant the compiler did not hold yet included. Read through
## `SaCompute.counters()`, so a perf window says whether a stroke paid for its
## pipelines. Written only by [method _load] and by
## `SaCompute.reset_counters`, the ledger's owner.
static var loads: int = 0
static var load_usec: int = 0

## The compiler generation this last checked itself against. See
## GlobalShaderCompiler.compile_generation. Public because the hot-reload suite
## reads it to prove the check happened, written only here.
var seen_generation: int = -1


func _init(rd: RenderingDevice, shader_name: String) -> void:
    _rd = rd
    _shader_name = shader_name
    if _rd == null:
        return
    _load()


## Points this at the variant compiled for *format*. True when it reloaded.
##
## Cheap and idempotent: the common case is that nothing changed and this returns
## on the first line. A caller told that it reloaded has two things left to do,
## which is why the answer is a bool rather than nothing.
func use_storage_format(format: int) -> bool:
    if format == storage_format:
        return false
    storage_format = format
    if _rd == null:
        return false
    _load()
    return true


## Points one image binding at *format*, whatever `storage_format` says. True
## when it reloaded.
##
## The kernel's qualifier for that binding is what Vulkan validates the bound
## view against, so a mask stored as `r32f` needs the kernel built with `r32f` at
## the mask's binding and the document's depth at the canvas's. Whether the
## binding is allowed one at all is the declared bindings' question, asked before
## this is called.
func use_binding_format(binding: int, format: int) -> bool:
    binding_formats[binding] = format
    if _rd == null:
        return false
    _load()
    return true


## Reloads when the compiler has recompiled since this last looked. True when it
## did, so the owner can drop what a reload invalidates.
##
## Guarded by the generation, one integer compare, rather than fetching the
## shader's whole kernel array out of a Dictionary on every dispatch, hundreds
## of times a stroke, to notice something that happens when a file is saved.
func follow_recompiles() -> bool:
    if seen_generation == GlobalShaderCompiler.compile_generation:
        return false
    seen_generation = GlobalShaderCompiler.compile_generation
    var compiled := GlobalShaderCompiler.get_compute_kernel_compilations(_shader_name, storage_format, binding_formats)
    if compiled.is_empty() or shader_id == compiled[0]:
        return false
    _load()
    return true


## Index of a kernel of this shader by its `#kernel` name, or -1 when there is
## none.
func index_of(kernel_name: String) -> int:
    return GlobalShaderCompiler.get_kernel_index(_shader_name, kernel_name)


## Whether *index* names a kernel this shader has.
##
## A negative index counts from the *end* in GDScript, so an unresolved kernel
## name would bind the shader's last kernel and paint as something else without a
## word. Both ends are checked here so no caller has to remember that, and so is
## the slot itself, which is empty for a kernel that did not compile.
func holds(index: int) -> bool:
    return index >= 0 and index < kernels.size() and kernels[index].is_valid()


## The pipelines of *kernels* the device still holds.
##
## A pipeline is freed with the shader it was made from, and the compiler frees a
## shader whenever it compiles that name again: `_prepare_kernel_rids` in
## `global_shader_compiler.gd` drops the last variant's RIDs before it makes the
## new ones. A second `SaPixelFunction` over one source is enough. The RID in hand keeps its number
## after the device has let it go, so `RID.is_valid()` cannot tell a pipeline from
## its ghost, and freeing the ghost is the engine's "Attempted to free invalid
## ID".
static func still_held(rd: RenderingDevice, pipelines: Array[RID]) -> Array[RID]:
    var held: Array[RID] = []
    for pipeline: RID in pipelines:
        if pipeline.is_valid() and rd.compute_pipeline_is_valid(pipeline):
            held.append(pipeline)
    return held


## Frees every pipeline the device still holds and creates them again from what
## the compiler holds now.
func _load() -> void:
    if _rd == null:
        SaProblems.report("SaCompute", "'%s' has no RenderingDevice to load its kernels on." % _shader_name)
        return
    var started := Time.get_ticks_usec()
    _load_on_device()
    loads += 1
    load_usec += Time.get_ticks_usec() - started


func _load_on_device() -> void:
    for k: RID in still_held(_rd, kernels):
        _rd.free_rid(k)
    kernels.clear()

    var compiled := GlobalShaderCompiler.get_compute_kernel_compilations(_shader_name, storage_format, binding_formats)
    if compiled.is_empty():
        return

    shader_id = compiled[0]
    if not shader_id.is_valid():
        # The compiler has already said which kernel and why. This says what it
        # costs: the whole shader is unusable until that is fixed.
        SaProblems.report("SaCompute", "'%s' cannot run, its first kernel did not compile." % _shader_name)

    kernels = pipelines_of(_rd, compiled, _shader_name)


## A pipeline for each of *compiled*, in its slot.
##
## No asserts, because a release build strips them, and an invalid pipeline
## would be appended and dispatched into without a word. A failed pipeline still
## takes its slot, for the reason `kernels` gives above, and so does a kernel
## the compiler could not build. Skipping that one would move every kernel after
## it down a slot, so each would run its neighbour's pipeline.
static func pipelines_of(rd: RenderingDevice, compiled: Array, shader_name: String) -> Array[RID]:
    var made: Array[RID] = []
    for shader_rid: RID in compiled:
        if not shader_rid.is_valid():
            made.append(RID())
            continue
        var pipeline := rd.compute_pipeline_create(shader_rid)
        if not pipeline.is_valid():
            SaProblems.report("SaCompute", "'%s' could not create a compute pipeline." % shader_name)
        made.append(pipeline)
    return made


## RAII cleanup during runtime destruction: the pipelines this object created.
##
## Inlined rather than calling a method on self, the way the uniform set cache's
## own PREDELETE is: a method call on self from here fails with "in base 'null
## instance'", because the script instance is already partway through teardown.
## So the question [method still_held] asks is asked here in its own words: a
## pipeline whose shader was recompiled is already gone from the device.
func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        if _rd == null:
            return
        for k: RID in kernels:
            if k.is_valid() and _rd.compute_pipeline_is_valid(k):
                _rd.free_rid(k)
