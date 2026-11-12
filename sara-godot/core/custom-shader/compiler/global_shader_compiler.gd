## -------------------------------------------------------------------------
## Sara
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
## Runtime manager for custom .gmacs compute shaders.
##
## Responsible for reading, resolving #include directives, and compiling
## text-based shaders into SPIR-V RIDs using RenderingDevice. What a kernel may
## declare in its preamble, and how each binding is filled, is in
## `sa_bindings.gd` beside this file.

@tool
extends Node

## The per-binding half of the compiler: format substitution, the binding layout
## a kernel declares, and the shared samplers. By path rather than by class name,
## because a new class name resolves only after the editor rescans its class cache.
const Bindings := preload("res://core/custom-shader/compiler/sa_bindings.gd")

## The pure text half: comments, kernels, signatures, the push constant block.
## Reached the same way.
const KernelSource := preload("res://core/custom-shader/dialect/sa_kernel_source.gd")

## The file half: the directory walk, who owns a shader, what an `#include`
## resolves to, the hot-reload scan and the startup report.
const ShaderIndex := preload("res://core/custom-shader/compiler/sa_shader_index.gd")

## The source half: virtual includes, the paste, and the map that turns a
## glslang line back into a file and a line someone can open.
const IncludeProcessor := preload("res://core/custom-shader/compiler/sa_include_processor.gd")

## Lines the assembler puts in front of every kernel: the #version and the
## local_size layout. See KernelSource.assemble_glsl.
const PREAMBLE_LINES: int = IncludeProcessor.PREAMBLE_LINES

## The file half and the source half, built in `_init` before anything is scanned
## or read. Public and typed: each owns its state and neither holds this node, so
## a caller with a question about a file asks `index`, one with a question about
## a text asks `source`, and what stays on this node is what a caller outside the
## compiler's own three files asks for by name. Built in _init, before anything
## is scanned or read.
var index: ShaderIndex
var source: IncludeProcessor

var rd: RenderingDevice

## Dictionaries to store RIDs
var shader_compilations: Dictionary[String, RID] = {}
var compute_shader_kernel_compilations: Dictionary[String, Array] = {}
## shader_name -> { kernel_name: String -> index: int }.
##
## The compiler already parsed these names out of the #kernel directives and threw
## them away, which is what made "the order of #kernel directives is load-bearing"
## an undocumented invariant shared between composite.gmacs and SaCompositor.
var compute_shader_kernel_names: Dictionary[String, Dictionary] = {}

## shader_name -> { kernel_name: String -> [x, y, z] }.
##
## The same throwing away, one directive along: `[numthreads(x, y, z)]` was read
## in `_compile_kernel()`, written into the `local_size` line and forgotten, so
## nothing could answer how wide a group of this kernel is. `SaCompute.run()`
## counted groups by dividing the region by `SaCompute.WORKGROUP_SIZE`, the
## constant 8, which is exact for the fifty-six kernels that are 8 by 8 and eight
## times too many groups for a `64, 1, 1` one.
var compute_shader_workgroup_sizes: Dictionary[String, Dictionary] = {}

## Bumped whenever any shader is compiled, so a dispatch can ask "has anything
## been rebuilt since I last looked" with an integer comparison.
##
## Rather than fetching the shader's whole kernel array from a Dictionary on
## every `list_begin`, hundreds of lookups a stroke to catch a hot reload that
## happens approximately never.
var compile_generation: int = 0

## The placeholder every storage-image binding writes instead of a format.
##
## `layout(rgba32f)` is not documentation, it is the format Vulkan validates the
## bound image view against, so a kernel with a hardcoded one can only ever be
## dispatched at RGBA32F textures. Binding anything else is undefined across the
## whole image, so a half float document would paint plausible nonsense. Kernels
## declare the token, and the compiler
## substitutes the real format once per variant.
const STORAGE_FORMAT_TOKEN := "SA_STORAGE_FORMAT"

## The GLSL format qualifier each RenderingDevice format compiles to, and what a
## shader compiles for when nobody asks for anything else. Both are the source
## half's, which substitutes them, and are named on here for the dispatch side.
const STORAGE_FORMAT_NAMES := IncludeProcessor.STORAGE_FORMAT_NAMES
const DEFAULT_STORAGE_FORMAT := IncludeProcessor.DEFAULT_STORAGE_FORMAT

## shader_name -> { variant key -> [kernel RIDs] }.
##
## A variant is one assignment of a format qualifier to every image binding, and
## its key is that assignment written down, see source.variant_key(). Variants are
## compiled on demand rather than all at startup. A session that never opens an
## F16 document never pays for the second set, which is most sessions, and the
## startup report stays the list of what actually exists.
var _format_variants: Dictionary[String, Dictionary] = {}

## shader_name -> { variant key -> [storage_format, binding_formats] }, what
## built each variant in `_format_variants`, so a recompile of the file can
## build every one of them again from the new text. The key
## alone does not say it, because it is written in qualifiers and a recompile
## asks in formats.
var _variant_recipes: Dictionary[String, Dictionary] = {}

## What a lookup of a shader nobody compiled reads, typed, so that the typed
## local it lands in does not refuse the default. Read and never written.
const _NONE_BY_KEY: Dictionary[String, Array] = {}
const _NO_KERNEL_NAMES: Dictionary[String, int] = {}

## Check for changes every 30 frames
var frame_counter: int = 0

## Cached once. Hot reload is a development affordance and has no business
## running in a shipped build, where a failed reload would be silent anyway.
## It asks for the editor's binary and not for a debug build, because the
## alpha ships as a debug export so that a crash names its script frames, and
## a debug export is still a shipped build with its kernels packed.
var _runs_from_editor_binary: bool = OS.has_feature("editor")
const CHECK_EVERY_X_FPS: int = 30

var _shared_rd: RenderingDevice

## Set once `get_rd` has asked the driver and been refused, so it never asks
## again.
##
## Without it every caller retried `create_local_rendering_device()`. A boot on a
## machine with no device made 96 of those attempts and 96 identical reports, and
## the hot-reload pass below went on making more for as long as the app was open.
## On the desktop this was filed from, the driver was refusing because it had run
## out of memory, so each retry was another allocation into a driver already
## failing, and the process died inside the engine with no GDScript frame in the
## core. One attempt is all the answer there is: a device that could not be made
## at boot is not going to appear later in the same run, and an app that says so
## once and stops is the one a painter can read the message on.
var _rd_refused: bool = false

var _pending_uniform_free_queue: Array = []


func queue_free_uniform_set(uniform_rid: RID) -> void:
    if uniform_rid.is_valid() and rd and rd.uniform_set_is_valid(uniform_rid):
        if _pending_uniform_free_queue.is_empty():
            _pending_uniform_free_queue.append([])
        var newest: Array = _pending_uniform_free_queue[-1]
        newest.append(uniform_rid)


func get_rd() -> RenderingDevice:
    if _rd_refused:
        return null
    if _shared_rd == null:
        # The seam a scenario reaches this branch through. Beside the two calls
        # rather than in front of them, so the refusal takes the same latch, the
        # same report and the same path out as a driver's own.
        _shared_rd = null if DeviceRefused.asked else RenderingServer.get_rendering_device()
        if _shared_rd == null:
            _shared_rd = null if DeviceRefused.asked else RenderingServer.create_local_rendering_device()
            if _shared_rd == null:
                _rd_refused = true
                # Reported rather than warned, so a machine with no working
                # Vulkan says why its window draws nothing.
                SaProblems.report(
                    "GlobalShaderCompiler",
                    "No RenderingDevice could be created, so nothing can be painted. Is a Vulkan driver installed?"
                )
    return _shared_rd


func _init() -> void:
    # The first autoload after the run log, so the span from the engine's start
    # to here is the engine's own, the log's opening and the load of this
    # script and every class it names.
    SaBootMarks.mark(&"compiler_init_begin")
    index = ShaderIndex.new()
    source = IncludeProcessor.new(index)
    rd = get_rd()
    # Abort initialization silently during headless export/project scanning
    if rd == null:
        SaBootMarks.mark(&"compiler_init_end")
        return
    index.find_files("res://")

    for shader_file: String in index.shader_files:
        index.compile_shader(shader_file)
    SaBootMarks.mark(&"compiler_init_end")


## Compiles the kernel files the scan found, oldest first, and answers whether
## every one of them is compiled now.
##
## The boot's kernels stage, kept out of `_init` on purpose. In the first
## autoload's constructor it would hold the window shut for most of a second,
## although the welcome window dispatches nothing. `SaBoot` calls this
## once a frame with a *budget_usec* while the main script loads on a worker
## thread, so the welcome window keeps answering, and the test runner calls it
## once with no budget before the first suite. A negative budget is no budget.
##
## A file some caller already compiled on demand, through
## `get_compute_kernel_compilations`, is passed over rather than compiled a
## second time, which would free RIDs a live `SaCompute` holds and move
## `compile_generation`. The cache prune runs once, after the last file, and
## a machine with no device has nothing to compile and answers true.
func compile_kernels(budget_usec: int = -1) -> bool:
    if rd == null or _kernels_compiled >= index.compute_shader_file_paths.size():
        _finish_kernels()
        return true
    if _ahead == null:
        SaBootMarks.mark(&"kernels_begin")
        _ahead = SaTranslationsAhead.new(index.compute_shader_file_paths, SaGlslCache.shared())
    if not _ahead.finished(source, budget_usec < 0):
        return false
    var started := Time.get_ticks_usec()
    while _kernels_compiled < index.compute_shader_file_paths.size():
        var file_path: String = index.compute_shader_file_paths[_kernels_compiled]
        _kernels_compiled += 1
        if not _format_variants.has(index.shader_key(file_path)):
            compile_compute_shader(file_path)
        if budget_usec >= 0 and Time.get_ticks_usec() - started >= budget_usec:
            break
    if _kernels_compiled < index.compute_shader_file_paths.size():
        return false
    _finish_kernels()
    return true


## How many of the scan's kernel files `compile_kernels` has been through.
var _kernels_compiled: int = 0

## The translations the worker pool makes before the first file compiles,
## started by the first call of `compile_kernels`.
var _ahead: SaTranslationsAhead = null


## The end of the kernels stage: its mark, the SPIR-V cache tidied once and the
## dialect's new translations written, see `SaGlslCache`. Here
## rather than in the boot header's report, because a headless run has no boot
## header and the gate is what fills the cache. A session that compiles nothing
## still lands here, which is what clears a directory an older build left over
## the cap. The data folder's own copies are tidied here too, see
## `SaDataTidy`. The mark lands after the prune rather than before it, so the
## span from `kernels_end` to `spirv_cache_pruned` is the prune's own cost.
func _finish_kernels() -> void:
    if SaBootMarks.has_mark(&"spirv_cache_pruned"):
        return
    SaBootMarks.mark(&"kernels_end")
    if rd != null:
        SaBootMarks.spirv_cache_pruned_count = SaSpirvCache.prune()
        SaGlslCache.shared().write()
    SaDataTidy.run()
    SaBootMarks.mark(&"spirv_cache_pruned")


## The forwards below are the ones with a caller outside the compiler's own three
## files: the blend mode registry, the boot header, the pixel function and the
## dispatch side. Sixteen others stood here for suites alone and are gone, and a
## suite asks `index` or `source`.


func resolve_shader_name(written_name: String) -> String:
    return index.resolve_shader_name(written_name)


## Prints what was compiled, grouped by shader file. Called once after the
## initial compilation pass.
func report_compilation() -> void:
    index.report_compilation()


func set_virtual_include(include_name: String, glsl: String) -> bool:
    return source.set_virtual_include(include_name, glsl)


func clear_virtual_include(include_name: String) -> void:
    source.clear_virtual_include(include_name)


## Total size in bytes of a shader's push constant block, or 0 when it has none.
func push_constant_bytes(written_name: String) -> int:
    return source.push_constant_bytes(written_name)


## The whole parsed push constant block of a shader, for a caller packing it by
## the declared names rather than by position. See sa_push_constants.gd and sa_binding_slots.gd.
func push_constant_layout(written_name: String) -> Array:
    return source.push_constant_layout(written_name)


## Main compilation logic for .gmacs files.
##
## *storage_format* and *binding_formats* select which variant is built: the
## first is what every image binding gets, the second overrides it per binding
## index. The source is identical apart from the substituted qualifiers, so kernel
## names and their order are the same for every variant and `get_kernel_index()`
## needs no variant of its own.
func compile_compute_shader(
    compute_shader_file_path: String, storage_format: int = DEFAULT_STORAGE_FORMAT, binding_formats: Dictionary[int, int] = {}
) -> void:
    # Nothing here works without a device, and four callers reach this without
    # asking: the hot-reload pass above, `SaPipelines.follow_recompiles` through
    # `get_compute_kernel_compilations`, `SaPixelFunction.compile`, and the stamp
    # brush's pattern kernel. Each of them ended in `shader_create_from_spirv` on
    # a null `rd`. The guard is here rather than at the four, because this is the
    # one door they all come through and a fifth caller would otherwise arrive at
    # the same crash.
    if get_rd() == null:
        return

    var compute_shader_name := index.shader_key(compute_shader_file_path)
    # A shader compiled straight from a path nobody scanned for is still owned by
    # somebody, and a lookup by that owner has to find it.
    index.index_shader(compute_shader_file_path)

    var raw_text := source.load_shader_file(compute_shader_file_path)
    if raw_text.is_empty():
        # load_shader_file has already said why. Carrying on would register a
        # shader with no kernels, which reads downstream as "this file is a
        # library" rather than as a failure.
        return
    # The dialect pass is the first thing over the text, so everything below it
    # reads the GLSL it has always read. It leaves a GLSL file byte for byte
    # alone, and the raw text stays in the source cache the hot-reload scan
    # compares against. Through the source half, which translates a text once
    # however many formats it is built at.
    var clean_text := source.glsl_of(raw_text)
    clean_text = source.process_includes(clean_text, compute_shader_file_path)
    # Read before the token is replaced, so the layout still says which bindings
    # follow the document's format and which wrote a qualifier of their own.
    var previous_layout := _layout_under(compute_shader_name)
    binding_layouts[compute_shader_name] = Bindings.extract_layout(clean_text)
    clean_text = source.substitute_storage_formats(clean_text, storage_format, binding_formats)
    source.remember_origins(compute_shader_name)
    var kernels := KernelSource.extract_kernels(clean_text)
    source.remember_push_constants(compute_shader_name, clean_text)

    # No kernels? -> include file, then skip
    if kernels.is_empty():
        index.note_include(compute_shader_name)
        return

    _compiling_shader = compute_shader_name
    # Cleared before the kernels rather than after them, so a recompile of a file
    # that has been fixed leaves no message behind for a caller to read as still
    # broken.
    compile_errors.erase(compute_shader_name)
    var key := source.variant_key(storage_format, binding_formats)
    if not _variant_recipes.has(compute_shader_name):
        var recipes: Dictionary[String, Array] = {}
        _variant_recipes[compute_shader_name] = recipes
    _variant_recipes[compute_shader_name][key] = [storage_format, binding_formats.duplicate()]
    var previous := _prepare_kernel_rids(compute_shader_name, key)

    var name_to_index: Dictionary[String, int] = {}
    var declared_sizes: Dictionary[String, Array] = {}
    for k_name: String in kernels:
        name_to_index[k_name] = name_to_index.size()
        var declared := _compile_kernel(k_name, clean_text, compute_shader_name, key)
        if declared.size() == 3:
            # As numbers, because `extract_numthreads()` answers the three regex
            # captures and every caller of the size divides by it.
            declared_sizes[k_name] = [str(declared[0]).to_int(), str(declared[1]).to_int(), str(declared[2]).to_int()]

    # A recompile that breaks a kernel keeps the pipeline that worked, so a typo
    # saved while painting does not take the brush down. The new RIDs go, the old
    # ones come back under the same names, and the generation does not move, so no
    # live `SaCompute` reloads onto nothing. The message stays in `compile_errors`
    # for whoever asked for the recompile to report.
    if _kept_previous(compute_shader_name, key, previous):
        binding_layouts[compute_shader_name] = previous_layout
        return
    for rid: RID in previous:
        if rid.is_valid():
            rd.free_rid(rid)
    compile_generation += 1
    compute_shader_kernel_names[compute_shader_name] = name_to_index
    compute_shader_workgroup_sizes[compute_shader_name] = declared_sizes


## shader_name -> { binding index -> {kind, name, format} }, read out of every
## `layout(...)` declaration in the preamble, the way sa_bindings.gd reads it.
## SaCompute checks a bind against this so that a buffer bound where the kernel
## declared a sampler is refused by name instead of surfacing as a Vulkan error at
## the first dispatch, and so that a per-binding format lands only on a binding
## that wrote the token.
var binding_layouts: Dictionary[String, Dictionary] = {}


## The bindings a compiled shader declares, as `binding -> {kind, name, format}`.
## Empty for a shader that was never compiled.
func binding_layout(written_name: String) -> Dictionary[int, Dictionary]:
    return _layout_under(resolve_shader_name(written_name))


## The layout filed under *shader_name*, a name already resolved, or an empty
## one, built here so the default is as typed as what is filed.
func _layout_under(shader_name: String) -> Dictionary[int, Dictionary]:
    if not binding_layouts.has(shader_name):
        return {}
    return binding_layouts[shader_name]


## `image`, `sampler` or `buffer` for one binding of a shader, or empty when the
## shader declares no such binding.
func binding_kind(written_name: String, binding: int) -> String:
    var layout := binding_layout(written_name)
    if not layout.has(binding):
        return ""
    var entry: Dictionary[String, String] = layout[binding]
    return entry.get("kind", "")


## The sampler for *filter* and *repeat*, shared by every kernel and created on
## first use. Owned by this node, which frees it with the shaders.
func sampler_rid(
    filter: int = RenderingDevice.SAMPLER_FILTER_LINEAR, repeat: int = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
) -> RID:
    if rd == null:
        rd = get_rd()
    return Bindings.sampler_rid(rd, filter, repeat)


## Puts a fresh, empty RID array under *key* for the kernels about to compile,
## and answers the one it replaced, unfreed, so a failed recompile can put it
## back. Empty on a first compile.
func _prepare_kernel_rids(compute_shader_name: String, key: String) -> Array:
    if not _format_variants.has(compute_shader_name):
        var fresh: Dictionary[String, Array] = {}
        _format_variants[compute_shader_name] = fresh
    var variants: Dictionary[String, Array] = _format_variants[compute_shader_name]
    var previous: Array = variants.get(key, [])
    variants[key] = []
    _mirror_default_variant(compute_shader_name, key)
    return previous


## The default variant stays mirrored in `compute_shader_kernel_compilations`,
## so every existing reader keeps working without learning about formats.
func _mirror_default_variant(compute_shader_name: String, key: String) -> void:
    if key == source.variant_key(DEFAULT_STORAGE_FORMAT):
        compute_shader_kernel_compilations[compute_shader_name] = _format_variants[compute_shader_name][key]


## Whether the compile just finished broke a kernel that *previous* had working,
## and if so frees what it made and puts *previous* back under *key*. A first
## compile has nothing to keep, and a file that never compiled has nothing
## worth keeping either, so both take the new result, broken or not.
func _kept_previous(compute_shader_name: String, key: String, previous: Array) -> bool:
    var made: Array = _format_variants[compute_shader_name][key]
    var broke := made.any(func(rid: RID) -> bool: return not rid.is_valid())
    var worked := not previous.is_empty() and previous.all(func(rid: RID) -> bool: return rid.is_valid())
    if not (broke and worked):
        return false
    for rid: RID in made:
        if rid.is_valid():
            rd.free_rid(rid)
    _format_variants[compute_shader_name][key] = previous
    _mirror_default_variant(compute_shader_name, key)
    return true


## Reload Shaders: recompiles every kernel file among *paths* whose text
## differs from the text it was compiled from, and answers what happened,
## `rebuilt` the shader names that took their new pipelines, `failed` each name
## that kept its old one against the compiler's message, and `unchanged` how
## many were left alone.
##
## *paths* defaults to every kernel file the scan found, and a caller with a
## shader of its own, a suite writing one under `user://`, names it. A changed
## file with no kernels is an include, and every kernel file is recompiled for
## it, because which of them read it is not recorded.
##
## Which files changed is the source half's to say, by time first and text
## second, see `changed_files` there.
func reload_changed(paths: Array = []) -> Dictionary[String, Variant]:
    var scope: Array = paths if not paths.is_empty() else index.compute_shader_file_paths
    var changed := source.changed_files(scope)
    if changed.any(func(file_path: String) -> bool: return not compute_shader_kernel_names.has(index.shader_key(file_path))):
        for file_path: String in index.compute_shader_file_paths:
            if not changed.has(file_path):
                changed.append(file_path)
    var rebuilt: Array[String] = []
    var failed: Dictionary[String, String] = {}
    for file_path: String in changed:
        var shader_name := index.shader_key(file_path)
        _recompile_every_variant(file_path)
        if not compute_shader_kernel_names.has(shader_name):
            continue
        if compile_errors.has(shader_name):
            failed[shader_name] = compile_errors[shader_name]
        else:
            rebuilt.append(shader_name)
    return {"rebuilt": rebuilt, "failed": failed, "unchanged": scope.size() - changed.size()}


## Recompiles *file_path* in the default format and then in every other variant
## it holds, each with the formats that built it, so a document in half float
## paints with the edited kernel too. Rebuilding the default alone would leave
## the other keys filled, and `get_compute_kernel_compilations` would hand back
## the pipelines of the old text.
##
## Each variant goes through `compile_compute_shader`, so each keeps its previous
## pipelines when the new text breaks, the rule `_kept_previous` has for the
## default. Every call clears the shader's message before it compiles, so the
## first message any variant left is put back at the end, and a reload of a
## broken file reports it failed even when a later variant compiled.
func _recompile_every_variant(file_path: String) -> void:
    var shader_name := index.shader_key(file_path)
    compile_compute_shader(file_path)
    var message: String = compile_errors.get(shader_name, "")
    var recipes: Dictionary[String, Array] = _variant_recipes.get(shader_name, _NONE_BY_KEY)
    var default_key := source.variant_key(DEFAULT_STORAGE_FORMAT)
    for key: String in recipes.keys():
        if key == default_key:
            continue
        var recipe: Array = recipes[key]
        var storage_format: int = recipe[0]
        var binding_formats: Dictionary[int, int] = recipe[1]
        compile_compute_shader(file_path, storage_format, binding_formats)
        if message.is_empty():
            message = compile_errors.get(shader_name, "")
    if not message.is_empty():
        compile_errors[shader_name] = message


## Compile a single kernel from the shader code, and answer the workgroup size it
## declared so the caller can file it. An empty Array is a kernel that did not
## declare one, which is the same kernel that took an empty RID below.
func _compile_kernel(k_name: String, clean_text: String, compute_shader_name: String, key: String) -> Array:
    var code := clean_text
    var numthreads := KernelSource.extract_numthreads(k_name, code)

    # A failed kernel still takes its slot. get_kernel_index() is a position in
    # this array, so dropping one would renumber every kernel after it and a
    # blend mode would quietly start doing another mode's arithmetic - a worse
    # failure than the one being reported.
    if numthreads.size() != 3:
        _variant_rids(compute_shader_name, key).append(RID())
        return []

    code = KernelSource.replace_kernel_signature(k_name, code)

    var final_source := KernelSource.assemble_glsl(numthreads, code)
    var rid := _compile_spirv(final_source, k_name)
    if not rid.is_valid():
        SaProblems.report("GlobalShaderCompiler", "kernel '%s' of %s did not compile." % [k_name, compute_shader_name])

    _variant_rids(compute_shader_name, key).append(rid)
    # Only the default variant is reported. A lazily built F16 set is the same
    # kernels again, and listing them twice would read as twice the shaders.
    if key == source.variant_key(DEFAULT_STORAGE_FORMAT):
        index.print_kernel_compiled(k_name, compute_shader_name)
    return numthreads


## Which shader `_compile_spirv` is working on, so an error can be traced back to
## the file it came from. Set by compile_compute_shader, which is the only caller.
var _compiling_shader: String = ""

## shader_name -> glslang's message from the last compile that failed, with the
## line map already applied, and no entry at all for a shader that compiled.
##
## The message was reported and thrown away, so nothing could answer *why* a
## kernel is unavailable. The Filter menu has to: a filter whose kernel did not
## compile registers anyway and its menu row carries the first error as its
## tooltip, which means the text has to outlive the compile that produced it.
## The first failing kernel of a shader wins, because that is the error a reader
## fixes first and the ones after it are usually the same mistake again.
var compile_errors: Dictionary[String, String] = {}


## What the last compile of *written_name* said, empty when it compiled or was
## never tried. The line numbers are the file's own, not glslang's.
func compile_error(written_name: String) -> String:
    return compile_errors.get(resolve_shader_name(written_name), "")


## Compile GLSL to SPIR-V
func _compile_spirv(final_source: String, k_name: String) -> RID:
    # Before the cache key, or a kernel broken on purpose is served from the
    # cache of the day it compiled. KernelBreak hands the text back unchanged
    # unless the environment asked for this kernel to fail.
    final_source = KernelBreak.apply(final_source, k_name)
    # The bytes glslang produces depend only on the source text, so they are
    # worth keeping between runs. SaSpirvCache is where and how.
    var key := SaSpirvCache.key_for(final_source)
    var cached := SaSpirvCache.load_spirv(key)
    if cached != null:
        var reused := rd.shader_create_from_spirv(cached)
        if reused.is_valid():
            SaBootMarks.spirv_cache_hits += 1
            return reused
        # The bytes were readable and the driver still refused them, so they are
        # from an incompatible build and every other entry probably is too.
        push_warning("GlobalShaderCompiler: cached SPIR-V for '%s' was rejected, recompiling." % k_name)
        SaSpirvCache.discard(key)

    var shader_source := RDShaderSource.new()
    shader_source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
    shader_source.source_compute = final_source
    var shader_spirv := rd.shader_compile_spirv_from_source(shader_source)
    SaBootMarks.spirv_compiles += 1

    if shader_spirv.compile_error_compute != "":
        # glslang's own message, which is the only thing that names a line.
        # Stripped in release, this was the failure that produced an invalid RID
        # and no explanation anywhere.
        var located := source.locate_glsl_error(shader_spirv.compile_error_compute, _compiling_shader)
        if not compile_errors.has(_compiling_shader):
            compile_errors[_compiling_shader] = located
        SaProblems.report("GlobalShaderCompiler", "GLSL error in kernel '%s':\n%s" % [k_name, located])
        return RID()

    var rid := rd.shader_create_from_spirv(shader_spirv)
    if not rid.is_valid():
        SaProblems.report("GlobalShaderCompiler", "kernel '%s' compiled but produced no shader." % k_name)
        return rid
    SaSpirvCache.store(key, shader_spirv)
    return rid


## The kernels of one storage variant of *compute_shader_name*, by position, the
## array `_compile_kernel` files each kernel's pipeline into.
func _variant_rids(compute_shader_name: String, key: String) -> Array:
    var variants: Dictionary = _format_variants[compute_shader_name]
    var rids: Array = variants[key]
    return rids


## Hot-reload logic
func _process(_delta: float) -> void:
    if not _pending_uniform_free_queue.is_empty():
        if _pending_uniform_free_queue.size() > 2:
            var to_free: Array = _pending_uniform_free_queue.pop_front()
            for u_rid: Variant in to_free:
                if not u_rid is RID:
                    continue
                var uniform_set: RID = u_rid
                if uniform_set.is_valid() and rd and rd.uniform_set_is_valid(uniform_set):
                    rd.free_rid(uniform_set)
        _pending_uniform_free_queue.append([])

    # Nobody edits a .gmacs inside a shipped build, and in an exported one the
    # files are packed rather than on disk. Everything below this line was
    # running there anyway, opening every shader twice every 30 frames.
    if not _runs_from_editor_binary:
        return

    # And nothing below it can run without a device. `_init` returns early on a
    # null `rd` and this pass did not, so on a machine with no device the
    # hot-reload scan reached `_compile_spirv` and called
    # `shader_create_from_spirv` on null, every thirtieth frame for as long as
    # the app was open.
    if rd == null:
        return

    # Nor before the kernels stage has been through every file: a file it has
    # not read yet reads as changed, and the pass would compile every kernel in
    # one frame while the welcome window waits on it.
    if _kernels_compiled < index.compute_shader_file_paths.size():
        return

    frame_counter += 1
    if frame_counter % CHECK_EVERY_X_FPS != 0:
        return

    # If something changed, run everything through the compiler
    # (Files without kernels are silently skipped due to the change in step 1)
    if source.scan_for_changes():
        for file_path: String in index.compute_shader_file_paths:
            _recompile_every_variant(file_path)


## Resource cleanup during runtime destruction
func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        if rd == null:
            return

        # Flush ALL pending deferred uniform-set frees before the RD is torn down.
        for batch: Array in _pending_uniform_free_queue:
            for u_rid: RID in batch:
                if u_rid.is_valid() and rd.uniform_set_is_valid(u_rid):
                    rd.free_rid(u_rid)
        _pending_uniform_free_queue.clear()

        # Free compiled shader RIDs (legacy glsl path, currently unused but safe to clean)
        for s_name in shader_compilations:
            var shader: RID = shader_compilations[s_name]
            if shader.is_valid():
                rd.free_rid(shader)
        shader_compilations.clear()

        # Free compute pipeline RIDs (these are the pipelines, not the SPIR-V shaders).
        # Walked through _format_variants rather than
        # compute_shader_kernel_compilations, because that one mirrors the default
        # variant only and a lazily compiled F16 set would leak every RID in it.
        for cs_name: String in _format_variants:
            for key: String in _format_variants[cs_name]:
                for kernel: RID in _format_variants[cs_name][key]:
                    if kernel.is_valid():
                        rd.free_rid(kernel)
        _format_variants.clear()
        _variant_recipes.clear()
        compute_shader_kernel_compilations.clear()
        compute_shader_kernel_names.clear()
        compute_shader_workgroup_sizes.clear()

        for sampler: RID in Bindings.take_samplers():
            if sampler.is_valid():
                rd.free_rid(sampler)


## Getter to retrieve compiled kernel RIDs for other scripts.
##
## *storage_format* and *binding_formats* pick the variant, the way
## compile_compute_shader() reads them. A variant that has not been built yet is
## compiled here, which is what makes F16 cost nothing until a document actually
## uses it.
func get_compute_kernel_compilations(
    written_name: String, storage_format: int = DEFAULT_STORAGE_FORMAT, binding_formats: Dictionary[int, int] = {}
) -> Array:
    assert(written_name != "", "Shader name must not be empty")
    var shader_name := resolve_shader_name(written_name)
    var key := source.variant_key(storage_format, binding_formats)
    var variants: Dictionary[String, Array] = _format_variants.get(shader_name, _NONE_BY_KEY)
    if not variants.has(key) or variants[key].is_empty():
        if rd == null:
            rd = get_rd()
        if index.compute_shader_file_paths.is_empty():
            index.find_files("res://")
            # The scan may be what made the name resolvable in the first place.
            shader_name = resolve_shader_name(written_name)
        var file_path: String = index.shaders_by_key.get(shader_name, "")
        if not file_path.is_empty():
            compile_compute_shader(file_path, storage_format, binding_formats)
        variants = _format_variants.get(shader_name, _NONE_BY_KEY)
    return variants.get(key, [])


## Whether a storage format has a GLSL qualifier and so can be compiled for.
func supports_storage_format(storage_format: int) -> bool:
    return STORAGE_FORMAT_NAMES.has(storage_format)


## Index of a kernel by its `#kernel` name, or -1 when the shader or kernel is
## unknown.
##
## Registering a blend mode by name instead of by ordinal is what removes the
## requirement that SaCompositor's registration order mirror the textual order of
## the #kernel directives in composite.gmacs - an invariant nothing checked, so
## inserting a kernel silently remapped every mode after it.
func get_kernel_index(shader_name: String, kernel_name: String) -> int:
    var names: Dictionary[String, int] = compute_shader_kernel_names.get(resolve_shader_name(shader_name), _NO_KERNEL_NAMES)
    return names.get(kernel_name, -1)


## The workgroup size *kernel_name* declared, as `[x, y, z]`.
##
## `[8, 8, 1]` when the shader or the kernel is unknown, which is what nearly
## every kernel in the tree declares. A kernel nothing compiled cannot be dispatched
## anyway, so the fallback is the answer to a question about a kernel that is not
## there rather than a guess a dispatch acts on.
func workgroup_size(shader_name: String, kernel_name: String) -> Array:
    var sizes: Dictionary[String, Array] = compute_shader_workgroup_sizes.get(resolve_shader_name(shader_name), _NONE_BY_KEY)
    return sizes.get(kernel_name, [SaCompute.WORKGROUP_SIZE, SaCompute.WORKGROUP_SIZE, 1])


## Every kernel name of a shader, in declaration order.
func get_kernel_names(shader_name: String) -> Array:
    var names: Dictionary[String, int] = compute_shader_kernel_names.get(resolve_shader_name(shader_name), _NO_KERNEL_NAMES)
    var ordered: Array = []
    ordered.resize(names.size())
    for k_name: String in names:
        ordered[names[k_name]] = k_name
    return ordered


## Refuses the RenderingDevice on purpose, so an app with no working driver can
## be seen from the painter's side without unplugging a GPU.
##
## `SARA_NO_RENDERING_DEVICE=1` in the environment makes `get_rd` answer null the
## way it does on a machine whose driver could not allocate one, and the corner
## message, the empty canvas and the refusal to paint are then whatever the painter
## would really get.
## `scenarios/an-app-with-no-rendering-device-runs-to-ready-and-then-dies.json`
## runs under it. Debug builds only and read once. The alpha is a debug export, so
## the switch is live in the build a painter has: they reach it only by setting the
## variable, and a tester can show a friend's machine what a refused device looks
## like. An inner class because this node is its one user and a file of its own
## would be a second package naming it.
##
## The compatibility renderer, `--rendering-driver opengl3`, is the other way in
## and needs no switch at all, but it cannot be reached from a scenario: the shot
## harness puts a scenario's own arguments after the `--`, where the engine does
## not read them.
class DeviceRefused:
    ## Whether the environment asked for a machine with no device.
    static var asked: bool = OS.get_environment("SARA_NO_RENDERING_DEVICE") == "1" if OS.is_debug_build() else false


## Breaks one kernel on purpose, so a failed compile can be seen from the
## painter's side without editing a shader.
##
## `SARA_BREAK_KERNEL=<kernel>` in the environment makes that kernel fail with a
## directive glslang refuses, and the problem dialog then shows what a machine
## with a bad driver would show at boot. `scenarios/a-boot-problem-is-shown-as-a-message.json` runs under
## it. Debug builds only and read once, live in the alpha for the reason the
## switch above is, and an inner class for the same reason too.
class KernelBreak:
    ## The kernel the environment named, or empty.
    static var kernel: String = OS.get_environment("SARA_BREAK_KERNEL") if OS.is_debug_build() else ""

    ## *glsl*, or *glsl* made uncompilable when *k_name* is the kernel named.
    ## The SPIR-V cache keys by the text handed back, so a broken kernel is never
    ## served from the cache.
    static func apply(glsl: String, k_name: String) -> String:
        if kernel.is_empty() or k_name != kernel:
            return glsl
        return glsl + "\n#error broken on purpose by SARA_BREAK_KERNEL\n"
