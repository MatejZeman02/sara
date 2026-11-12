## One pixel function file, loaded: the params its `uniform` lines declare, the
## kernel generated around it, and a dispatch over one rectangle.
##
## The spec's shortest door. A student writes `def pixel(ivec2 at) -> vec4` and a
## `uniform` line per slider, and this writes the declarations, the bindings,
## `src` and the dispatch around it, so the file needs no class beside it. The
## text is `sa_pixel_source.gd`'s, which is static and needs no GPU. What is here
## is everything that does: the generated file on disk, the compile, and the run.
##
## **The body is imported, not inlined.** The generated kernel registers the
## student's own text as a virtual include and writes `import <owner>_pixels/<file>`
## where the function belongs, so `sa_include_processor.gd` attributes every
## pasted line to the student's file and the line it was written on. That is what
## makes a glslang error read `[threshold.gmacs:4]`, and it is the existing line
## map rather than a second one.
##
## The include is qualified rather than bare, and it stays registered for as long
## as this object lives. A virtual include shadows a file of the same name for
## every compile while it is registered, so a pixel function called `paint.gmacs`
## under a bare name would quietly take the paint library's place. And it cannot
## be cleared after the compile either: a variant is compiled on demand, so the
## first dispatch at the document's own depth compiles the kernel a second time
## and would find the import gone. The qualified name is what makes keeping it
## safe.
##
## Preloaded by path rather than reached through a `class_name`, the way the
## compiler's own halves reach each other.
@tool
extends RefCounted

## The text half: the uniforms, the body and the wrapper.
const PixelSource := preload("res://core/custom-shader/dialect/sa_pixel_source.gd")

## The layout reader, for a params field the dialect moved into a buffer of its
## own, which [method carried] packs through `SaCompute` the way its `run` does.
const KernelSource := preload("res://core/custom-shader/dialect/sa_kernel_source.gd")

## Where a generated kernel is written.
##
## Under the data root because it is output rather than something anybody authored,
## and because the shader walk turns back at the app's own user directory, so a
## generated file is never indexed twice or hot-reloaded behind the wrapper's
## back. The `modules/<owner>` leg is what `SaShaderIndex.owner_of()` reads, so a
## module's generated kernel is owned by that module exactly as its hand-written
## ones are.
## A folder name, asked of `SaDataRoot` where it is used, so a `--settings-dir`
## run writes its kernels under its own root.
const GENERATED_FOLDER: String = "generated-kernels"

## The directory half of the name the body is registered under, after the module
## that owns it. See the note at the top of this file.
const INCLUDE_SUFFIX: String = "_pixels"

## Appended to the file's own name so the generated kernel and the pixel function
## it came from are two different shaders. A student's file under
## `modules/<name>/` is itself indexed, as a library with no kernels, and two
## files under one key is a collision the index can only report.
const GENERATED_SUFFIX: String = "_wrapped"

## The same for the pass form, `SaPixelSource.wrap_layered`'s kernel, so a file
## compiled both ways is two shaders and neither shadows the other.
const LAYERED_SUFFIX: String = "_layered"

## The same for the pass form run in place, [member in_place].
const POINT_SUFFIX: String = "_point"

## The same for the rule form, [member stepped].
const RULE_SUFFIX: String = "_rule"

## The pixel function file this was made for.
var path: String = ""

## Whether the kernel is the pass form a filter records, rather than the one
## [method run] dispatches. A constructor argument, written in `_init` alone.
var layered: bool = false

## Whether the pass form is the point form, the chunk read and rewritten in
## place with no halo, which a filter with no margin records. A constructor
## argument, written in `_init` alone.
var in_place: bool = false

## Whether the kernel is the rule form a simulation steps by, which
## [method register_rule] registers. A constructor argument, written in
## `_init` alone.
var stepped: bool = false

## Its name without the extension, which is the kernel's name.
var stem: String = ""

## What the body is registered as, `<owner>_pixels/<stem>`, which is what the
## generated kernel imports and what the line map names the pasted lines after.
var include_name: String = ""

## `<owner>/<stem>_wrapped`, or `_layered` or `_point` for the pass form, the
## shader the generated kernel compiles as.
var shader_name: String = ""

## Where the generated `.gmacs` was written.
var generated_path: String = ""

## The generated source, whether or not it ever compiled.
var generated_source: String = ""

## What the `uniform` lines declared, in order, as `sa_pixel_source.gd` reads
## them. This is what `SaPixelFilter` turns into sliders.
var uniforms: Array = []

## Whether the function reads `t`, the time, which is what makes a filter of it
## declare a time row. `sa_pixel_source.gd`'s answer, kept from the last read.
var reads_time: bool = false

## Everything wrong with the file, in the order a reader meets it. A file with a
## problem is never compiled, because the message about the file is more use than
## the compiler's message about the source generated from it.
var problems := PackedStringArray()

## The compute over the generated kernel, once it has compiled.
var compute: SaCompute = null

## What glslang said about the generated kernel, with the line map applied so
## every line of the body reads as the student's own file and line. Empty when
## the kernel compiled.
var compile_error: String = ""

## The student's text as the generated kernel imports it.
var _body: String = ""

## The file's text as it was last read, which is what [method reload_if_changed]
## compares against. The text rather than the modification time, because a
## modification time is whole seconds and a file fixed within a second of being
## read would look unchanged.
var _raw_text: String = ""


## Reads *file_path* and generates the kernel for it. Nothing is compiled here,
## because a caller may want to read the params or the source without a GPU.
##
## *raw_text* is the file's text for a caller that already has it, and the path
## is then only what the errors and the line map name it. *pass_form* generates
## the kernel a filter records as a pass, see [member layered], *point_form*
## its point form, see [member in_place], and *rule_form* the kernel a
## simulation steps by, see [member stepped], in place of either.
func _init(
    file_path: String, raw_text: String = "", pass_form: bool = false, point_form: bool = false, rule_form: bool = false
) -> void:
    path = file_path
    stepped = rule_form
    layered = pass_form and not rule_form
    in_place = layered and point_form
    stem = file_path.get_file().split(".")[0]
    var text := raw_text
    if text.is_empty():
        var file := FileAccess.open(file_path, FileAccess.READ)
        if file == null:
            problems.append("cannot open %s (%s)." % [file_path, error_string(FileAccess.get_open_error())])
            return
        text = file.get_as_text()
    _read(text)


## Parses *raw_text* and generates the kernel around it.
func _read(raw_text: String) -> void:
    _raw_text = raw_text
    problems.append_array(PixelSource.problems(raw_text, stem))
    uniforms = PixelSource.uniforms(raw_text)
    reads_time = PixelSource.reads_time(raw_text)
    _body = PixelSource.body(raw_text)
    include_name = _owner().replace("-", "_") + INCLUDE_SUFFIX + "/" + stem
    var suffix := GENERATED_SUFFIX
    var imported := PixelSource.imports(raw_text)
    generated_source = PixelSource.wrap(stem, include_name, uniforms, imported, PixelSource.PixelImages.declared(raw_text))
    if layered or stepped:
        problems.append_array(PixelSource.PixelImages.layered_problems(raw_text))
    if layered:
        problems.append_array(PixelSource.layered_problems(uniforms))
        suffix = POINT_SUFFIX if in_place else LAYERED_SUFFIX
        generated_source = PixelSource.wrap_layered(stem, include_name, uniforms, in_place, true, imported)
    elif stepped:
        problems.append_array(PixelSource.layered_problems(uniforms))
        suffix = RULE_SUFFIX
        generated_source = PixelSource.wrap_layered(stem, include_name, uniforms, false, false, imported)
    var owner_dir := _owner_directory()
    generated_path = SaDataRoot.path(GENERATED_FOLDER).path_join(owner_dir).path_join(stem + suffix + ".gmacs")
    shader_name = _owner() + "/" + stem + suffix


## The module the pixel function belongs to, or `sara` when it belongs to no
## module. The index's own rule, asked of the source file rather than of the
## generated one so the two answer the same.
func _owner() -> String:
    var parts := path.simplify_path().split("/")
    var at := parts.find("modules")
    return parts[at + 1] if at >= 0 and at + 1 < parts.size() else "sara"


## The leg under `GENERATED_FOLDER` that gives the generated file the same owner.
func _owner_directory() -> String:
    var module := _owner()
    return "" if module == "sara" else "modules".path_join(module)


## The value each param opens at, as the `uniform` lines declared them, with
## `step` and `t` at nought, which is what they read where nothing tells them
## otherwise. `origin` is not among them: `SaPushConstants.with_region()`
## writes it from the region the dispatch covers.
func defaults() -> Dictionary[String, Variant]:
    var out: Dictionary[String, Variant] = {PixelSource.STEP_FIELD: 0, PixelSource.TIME_FIELD: 0.0}
    for field: Dictionary[String, Variant] in uniforms:
        out[str(field["name"])] = field["default"]
    return out


## The params a pass of the pass form is recorded with: the defaults, *values*
## over them, and the colour space tail of *space* by the names the kernel
## declares, gamma sRGB when it is null. The places and the padding are the
## runner's to write per dispatch, so they are not here.
func pass_params(values: Dictionary, space: SaColorSpace) -> Dictionary[String, Variant]:
    var params := defaults()
    params.merge(values, true)
    var tail := SaColorSpacePushConstant.to_push_constant(space if space != null else SaColorSpace.srgb())
    params["doc_to_linear_srgb"] = tail.slice(0, 9)
    params["linear_srgb_to_doc"] = tail.slice(9, 18)
    var at := 18
    for scalar: String in PixelSource.LAYERED_FIELDS.slice(5):
        params[scalar] = tail[at]
        at += 1
    return params


## *params* as the point form's push constant, every field at its place in the
## block, ints by their bits, for a pass recorded as an `SaPointPass`. The
## places are zero here and the runner writes them per dispatch. Call it after
## [method carried], which takes out the fields a buffer holds.
func point_push(params: Dictionary[String, Variant]) -> PackedFloat32Array:
    var full := params.duplicate()
    full["origin"] = Vector2.ZERO
    full["chunk"] = Vector2.ZERO
    var bytes := SaCompute.pack_block(GlobalShaderCompiler.push_constant_layout(shader_name), full)
    if bytes.is_empty():
        SaProblems.report("SaPixelFunction", tr("%s: its params could not be packed into the push constant.") % path.get_file())
    return bytes.to_float32_array()


## Where the point form's `origin` sits in [method point_push], in floats.
func origin_slot() -> int:
    return floori(maxi(GlobalShaderCompiler.source.push_constant_offset(shader_name, "origin"), 0) / 4.0)


## The buffers *params* needs beside the push constant, by binding, with every
## field the dialect moved into one taken out of *params*.
##
## A pass is dispatched through `set_params`, which packs the push constant
## alone, so a block too wide for it, a matrix or a colour beside the tail,
## would be refused there. `SaCompute.run` carries such a field into its buffer
## and this does the same for a recorded pass, which binds buffers by number.
func carried(params: Dictionary[String, Variant]) -> Dictionary[int, SaCompute.Buffer]:
    var out: Dictionary[int, SaCompute.Buffer] = {}
    var declared := GlobalShaderCompiler.binding_layout(shader_name)
    for binding: int in declared:
        var entry: Dictionary = declared[binding]
        var moved := str(entry.get("param", ""))
        if moved.is_empty() or not params.has(moved):
            continue
        var bytes := SaCompute.pack_block(KernelSource.block_layout(str(entry.get("fields", ""))), {moved: params[moved]})
        if bytes.is_empty():
            SaProblems.report("SaPixelFunction", tr("%s: `%s` could not be packed into its buffer.") % [path.get_file(), moved])
            continue
        out[binding] = SaCompute.Buffer.new(bytes)
        params.erase(moved)
    return out


## Registers the pixel function at *file_path* on *ctx* as a simulation's rule
## under *key*, named *label* in the panel, whose cells read *reach* texels
## round themselves, and answers whether it was registered. *raw_text* is the
## file's text for a caller that already has it, as the constructor takes it.
##
## The file is compiled in the rule form, so the simulation's step runs it as it runs a
## written rule: `src` reads the previous state padded by the reach, the
## record tells `step` the number of the step it takes, and `t` reads nought.
## Its `uniform` lines are the rule's parameters, and [class Rule] keeps them
## for the panel to make a slider of each. Refused, with the problem reported,
## for a file that does not compile or one whose uniforms are too wide for the
## push constant, since the step binds no buffer to carry what the dialect
## moves out of it.
static func register_rule(
    ctx: SaContext, file_path: String, key: StringName, label: String, reach: int, raw_text: String = ""
) -> bool:
    var function := new(file_path, raw_text, false, false, true)
    if not function.compile():
        return false
    var declared := GlobalShaderCompiler.binding_layout(function.shader_name)
    for binding: int in declared:
        var moved := str(SaTyped.strings(declared[binding]).get("param", ""))
        if not moved.is_empty():
            SaProblems.report(
                "SaPixelFunction",
                (
                    "%s: `%s` is too wide for the push constant, and a simulation's step binds no buffer to carry it."
                    % [function.path.get_file(), moved]
                )
            )
            return false
    var made := Rule.new(key, label, function.shader_name, function.stem, reach, function.defaults(), function, function.uniforms)
    return ctx.simulation_rules.register(made, ctx.module_id)


## Writes the generated kernel and compiles it, and answers whether a kernel came
## out of it.
##
## Compiled every time it is asked rather than once, because `user://` outlives
## the process and a file whose source changed between runs would otherwise sit
## on disk as it was. The SPIR-V cache keys on the source, so an unchanged kernel
## is read back rather than built.
func compile() -> bool:
    if not problems.is_empty():
        for problem in problems:
            SaProblems.report("SaPixelFunction", "%s: %s" % [path.get_file(), problem])
        return false

    DirAccess.make_dir_recursive_absolute(generated_path.get_base_dir())
    var file := FileAccess.open(generated_path, FileAccess.WRITE)
    if file == null:
        SaProblems.report(
            "SaPixelFunction", "cannot write %s (%s)." % [generated_path, error_string(FileAccess.get_open_error())]
        )
        return false
    file.store_string(generated_source)
    file.close()

    GlobalShaderCompiler.set_virtual_include(include_name, _body)
    GlobalShaderCompiler.compile_compute_shader(generated_path)

    # A failed kernel still takes its slot in the name list, which is the whole
    # reason the list cannot answer this: `get_kernel_names` is as long for a
    # shader that did not compile as for one that did. The compiler's own message
    # is the answer, and keeping it is what lets a menu row say why it is dimmed
    # rather than only that it is.
    compile_error = GlobalShaderCompiler.compile_error(shader_name)
    if not compile_error.is_empty() or GlobalShaderCompiler.get_kernel_names(shader_name).is_empty():
        return false
    compute = SaCompute.new(shader_name)
    return true


## The first line of [member compile_error] that names an error, which is what a
## menu row carries as its tooltip. Empty when the kernel compiled.
##
## The first line of the message itself is glslang's own heading, `Failed
## parse:`, which says nothing a reader can act on. The first `ERROR:` line is
## the one that names the student's file, their line and what is wrong with it.
func first_error() -> String:
    if compile_error.is_empty():
        return ""
    for line in compile_error.split("\n"):
        var text := line.strip_edges()
        if text.begins_with("ERROR:"):
            return text
    return compile_error.split("\n")[0].strip_edges()


## Reads the file again and recompiles when its text has changed, and answers
## whether it did. False for a file that is as it was, which is the common case
## and costs one read.
##
## This is the "recompile on the next open" the spec asks for: a student fixes
## the file, opens the menu, and the row is live again without a restart. It is
## a reread rather than a signal from a watcher, because the file may be edited
## by anything and Sara's own hot-reload scan turns back at the user directory
## the generated kernel lives in.
func reload_if_changed() -> bool:
    if path.is_empty():
        return false
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return false
    var text := file.get_as_text()
    if text == _raw_text:
        return false
    problems = PackedStringArray()
    compile_error = ""
    compute = null
    _read(text)
    compile()
    return true


## The wrapped kernel over the rectangle a filter's context answers, with the
## result handed to the preview.
##
## This is the whole of what a pixel function does at run time, so
## `SaPixelFilter`'s run has a body of one line. The chunk walk is not here
## and is not duplicated: `layer_pixels` copies the layer's chunks into one
## texture GPU to GPU and the apply commits the result back the same way, so
## the dispatch between them is over the rectangle and nothing else, hard rule
## 2.
##
## *values* is an untyped Dictionary on purpose here and in [method run]: a
## module's filter hands in whatever it built, and a typed parameter would
## refuse it at the call.
func run_on(ctx: SaFilterContext, margin: int = 0, values: Dictionary = {}) -> void:
    var source := ctx.layer_pixels(margin)
    if source == null:
        SaProblems.report("SaPixelFunction", "%s was handed a context with no pixels." % path.get_file())
        return
    var target := ctx.blank_like(source)
    run(source, target, ctx.rect, values)
    ctx.show(target)


## One dispatch of the wrapped kernel: *source* read through `src`, *target*
## written at every pixel of *region*, and *values* over the defaults.
##
## *region* is the rectangle the run covers in canvas coordinates, and both
## textures cover exactly it, which is what `SaFilterContext.layer_pixels` and
## `blank_like` answer. The dispatch is that rectangle and nothing else, hard
## rule 2, and no texel is read back, hard rule 1.
func run(source: SaTexture, target: SaTexture, region: Rect2i, values: Dictionary = {}) -> void:
    if compute == null:
        SaProblems.report("SaPixelFunction", "%s has no compiled kernel to run." % path.get_file())
        return
    var params := defaults()
    params.merge(values, true)
    compute.run(stem, {PixelSource.SOURCE_IMAGE: source, PixelSource.TARGET_IMAGE: target}, params, region)


## Drops the body's registration when nothing holds this any more, the way
## `SaTexture` frees its RID. Not before: every variant of the generated kernel
## is compiled on demand and each one reads the import again.
##
## Not after the compiler either. The registration lives in the compiler's own
## table and goes with it, so a pixel function still held when the autoloads
## are freed at exit has nothing left to clear. Calling the freed autoload
## would log a SCRIPT ERROR per kernel in the whole run, or crash the engine
## while the tree is being deleted, so this asks first.
func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE and not include_name.is_empty() and is_instance_valid(GlobalShaderCompiler):
        GlobalShaderCompiler.clear_virtual_include(include_name)


## A pixel function as a simulation's rule: a written rule over the file's rule
## form, with the pixel function held for as long as the registry holds the
## rule. The generated kernel imports the body each time a variant of it
## compiles, the first step on a layer of another depth among them, so the
## body stays registered while the rule can be stepped, and goes with the rule
## when the module that registered it is unloaded. Written by its constructor
## alone.
class Rule:
    extends SaSimulation.Rule

    ## The pixel function the rule steps by, held and never read.
    var pixels: RefCounted = null

    ## Its `uniform` lines as `sa_pixel_source.gd` reads them, which the
    ## simulation's panel makes a slider of each.
    var uniforms: Array = []

    func _init(
        rule_key: StringName,
        rule_label: String,
        shader_key: String,
        kernel_name: String,
        rule_reach: int,
        rule_defaults: Dictionary[String, Variant],
        held: RefCounted,
        declared: Array
    ) -> void:
        super(rule_key, rule_label, shader_key, kernel_name, rule_reach, rule_defaults)
        pixels = held
        uniforms = declared.duplicate(true)
