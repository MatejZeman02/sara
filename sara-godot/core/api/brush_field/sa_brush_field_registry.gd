## The ninth registry: the fields a brush engine paints through, grain,
## bristle, a picture, or one a module adds.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## It is on the door because a list inside one module is one no other module can
## reach (hard rule 6). The noise module registers its three fields through
## [method SaContext.register_brush_field] as any module would, and its engine
## reads the list back from here, a field from another module among them.
##
## A field names the engine it is for ([member Field.engine]) and the kernel it
## runs. An engine reads only its own fields and passes over a field naming a
## kernel it has none of rather than painting it as something else. [constant
## PICTURE] is the one kernel this registry names, because a picture is any
## pattern the door's `SaPatternStore` holds, so it needs no GLSL.
##
## A field answers at stroke coordinates, which is the contract. A kernel is read
## at three numbers: along, the distance in document pixels travelled on the path
## at the texel's nearest point less what the drift has carried the field,
## across, the texel's signed distance from the path over the tip's half-width
## there (minus one at one edge to one at the other), and the half-width itself
## in pixels. It answers two readings in 0 to 1, the pressure the texel needs
## before it takes paint and the lightness the stroke writes into the height. So
## a field tiles or streaks along the path and bends with it.
##
## A field may bring its own kernel. It names [constant OWN] as its kernel and a
## `.gmacs` file as its [member Field.source], which holds one function by the
## name [constant FUNCTION], with helpers beside it if it wants them:
##
##     def brush_field(float along, float across, float half_width, vec3 numbers, vec2 offset) -> vec2:
##
## *numbers* is the field's first three [member Field.numbers], settings keys the
## engine reads off its settings and hands the kernel in order, each with a
## fallback, since a module cannot add a property to another engine's settings
## and a key the settings do not have reads as the fallback at the same index.
## A switch reads as one when on and nought when off. *offset* is the stroke's
## own, two numbers in document pixels drawn from its seed, which a field adds
## wherever two strokes should not lay one pattern. It answers the pressure in x
## and the lightness in y. The file's text is imported under [member
## Field.include_name], qualified by its module so two modules' fields never
## collide, and kept for as long as a field registered here names it. At
## registration the function is compiled into a kernel of its own, and a field
## whose kernel does not compile is refused through `SaProblems` with a sentence
## naming the file and the line.
##
## A painter's field is a `.gmacs` file in the folder [method folder_for] names,
## and the engine registers what it finds there like any module's field. The
## door's `brush_field` step writes a file there from a notebook's text and asks
## the engine to read the folder again through [signal reread_asked], then reads
## [member refusals] for why a file did not take. Registered at load and read
## once a stroke, never per dab.
class_name SaBrushFieldRegistry
extends RefCounted

## Registration and removal, which a Texture row may rebuild from.
signal changed
## A file was written into *engine*'s folder of fields, which its engine reads
## again before the emit returns.
@warning_ignore("unused_signal")
signal reread_asked(engine: StringName)

## The kernel every engine takes as a picture from the pattern store.
const PICTURE: StringName = &"picture"
## The kernel a field names when it brings its own, in [member Field.source].
const OWN: StringName = &"own"
## The function a field's own kernel defines, which an engine calls.
const FUNCTION: String = "brush_field"
## What the check kernel's name ends in, after its import's name.
const CHECK_SUFFIX: String = "_check"
## Where the check kernels are written, the folder a pixel function's wrapper
## goes to, asked of `SaDataRoot` so a `--settings-dir` run writes under its own
## root.
const GENERATED_FOLDER: String = "generated-kernels"
## The half-width the check reads the field at, any width, since the check
## only has to compile.
const CHECK_HALF_WIDTH: float = 16.0
## The folder under the data root an engine's fields of the painter's own are
## read from, one folder an engine below it.
const FOLDER: String = "brush-fields"


## One field. Written by the constructor alone.
##
## *numbers* are the settings keys the kernel reads, in order, *fallbacks* what
## each reads as when the settings have no such key, and *rows* the field's
## own sliders, which name the same keys. *channels* is the most the field
## has, one or two. *kernel_file* is the `.gmacs` file of a field that brings
## its own kernel, and a field given one runs it, [constant OWN], whatever
## kernel it names.
class Field:
    extends RefCounted

    var id: String = ""
    var label: String = ""
    var engine: StringName = &""
    var kernel: StringName = &""
    var channels: int = 1
    var numbers: Array[StringName] = []
    var fallbacks: PackedFloat32Array = PackedFloat32Array()
    var rows: Array[SaOptionSpec] = []
    ## The file holding the field's own kernel, empty for a field over one the
    ## engine has.
    var source: String = ""
    ## What the file's text is imported as, [method SaBrushFieldRegistry.include_for]
    ## of it, or empty.
    var include_name: String = ""

    func _init(
        field_id: String,
        field_label: String,
        for_engine: StringName,
        kernel_name: StringName,
        most_channels: int,
        keys: Array[StringName],
        specs: Array[SaOptionSpec] = [],
        defaults: PackedFloat32Array = PackedFloat32Array(),
        kernel_file: String = ""
    ) -> void:
        id = field_id
        label = field_label
        engine = for_engine
        kernel = OWN if not kernel_file.is_empty() else kernel_name
        channels = clampi(most_channels, 1, 2)
        numbers = keys.duplicate()
        rows = specs.duplicate()
        fallbacks = defaults.duplicate()
        fallbacks.resize(numbers.size())
        source = kernel_file
        include_name = SaBrushFieldRegistry.include_for(kernel_file) if not kernel_file.is_empty() else ""

    ## Whether this field is a pattern the store holds rather than a kernel.
    func is_picture() -> bool:
        return kernel == PICTURE

    ## Whether this field brings its own kernel.
    func has_own_kernel() -> bool:
        return not source.is_empty()

    ## The number at *index* as *settings* hold it, or its fallback when they
    ## have no such key.
    func number(settings: Object, index: int) -> float:
        var held: Variant = settings.get(numbers[index]) if settings != null else null
        if held is bool:
            return 1.0 if held else 0.0
        return SaTyped.real(held, fallbacks[index]) if held is float or held is int else fallbacks[index]


## A field's own kernel: the file's text kept as an import for as long as a
## field registered here names it, and the check that compiled it there.
##
## Kept by the import's name rather than by the field, because two fields can
## run one file at numbers of their own, and the import is one.
class Kernel:
    extends RefCounted

    var include_name: String = ""
    ## Why the kernel did not compile, glslang's first error with the file and
    ## the line, or empty when it did.
    var error: String = ""

    ## Reads *own*'s file, keeps its text as the import and compiles the check.
    func _init(own: Field) -> void:
        var text := FileAccess.get_file_as_string(own.source)
        if text.is_empty():
            error = "%s cannot be read (%s)." % [own.source, error_string(FileAccess.get_open_error())]
            return
        include_name = own.include_name
        GlobalShaderCompiler.set_virtual_include(include_name, text)
        error = _compile()

    ## Writes and compiles the check, a kernel that calls the function at the
    ## contract's numbers and stores both readings, and answers what went
    ## wrong. A machine with no device compiles and paints nothing, so there
    ## is nothing there to refuse.
    func _compile() -> String:
        if GlobalShaderCompiler.get_rd() == null:
            return ""
        var kernel_name := SaBrushFieldRegistry.check_kernel_name(include_name)
        var path := SaDataRoot.path(GENERATED_FOLDER).path_join(kernel_name + ".gmacs")
        DirAccess.make_dir_recursive_absolute(path.get_base_dir())
        var file := FileAccess.open(path, FileAccess.WRITE)
        if file == null:
            return "%s cannot be written (%s)." % [path, error_string(FileAccess.get_open_error())]
        file.store_string(_check_source(kernel_name))
        file.close()
        GlobalShaderCompiler.compile_compute_shader(path)
        var shader_name := GlobalShaderCompiler.index.shader_key(path)
        var said := GlobalShaderCompiler.compile_error(shader_name)
        if said.is_empty() and GlobalShaderCompiler.get_kernel_names(shader_name).is_empty():
            return "no kernel came of it."
        return SaBrushFieldRegistry.first_error(said)

    ## The check's text, the function's import and one call of it a texel.
    func _check_source(kernel_name: String) -> String:
        var lines := PackedStringArray()
        lines.append("# Generated by core/api/brush_field/sa_brush_field_registry.gd, the check")
        lines.append("# that %s compiles at the brush field contract's numbers." % include_name)
        lines.append("")
        lines.append("kernel %s" % kernel_name)
        lines.append("")
        lines.append("image readings: rgba32f")
        lines.append("")
        lines.append("params:")
        lines.append("    vec2 origin")
        lines.append("")
        lines.append("import %s" % include_name)
        lines.append("")
        lines.append("")
        lines.append("def %s():" % kernel_name)
        lines.append("    ivec2 size = image_size(readings)")
        lines.append("    if pixel.x >= size.x or pixel.y >= size.y:")
        lines.append("        return")
        lines.append("    vec2 at = vec2(pixel) + origin")
        lines.append("    float half_width = %.1f" % CHECK_HALF_WIDTH)
        lines.append("    vec2 reading = %s(at.x, at.y / half_width - 1.0, half_width, vec3(1.0), vec2(0.0))" % FUNCTION)
        lines.append("    image_store(readings, pixel, vec4(reading, 0.0, 1.0))")
        lines.append("")
        return "\n".join(lines)

    ## Drops the import when no field names it any more, the way `SaTexture`
    ## frees its RID. At the engine's exit the compiler, an autoload, can be
    ## freed first and takes every import with it.
    func _notification(what: int) -> void:
        if what == NOTIFICATION_PREDELETE and not include_name.is_empty() and is_instance_valid(GlobalShaderCompiler):
            GlobalShaderCompiler.clear_virtual_include(include_name)


## Every field, in the order they were registered.
var _fields: Array[Field] = []
## The module each field's id was registered by, since a field is written by
## its constructor alone and the module is only known here.
var _owners: Dictionary[Field, StringName] = {}
## The own kernels the fields registered here run, by their import's name.
var _kernels: Dictionary[String, Kernel] = {}
## Why the last registration of each own kernel's file was refused, by the
## file, and no entry once a field of that file is taken.
var refusals: Dictionary[String, String] = {}


## The folder *engine*'s fields of the painter's own are read from, under the
## data root so a `--settings-dir` run reads its own.
static func folder_for(engine: StringName) -> String:
    return SaDataRoot.path(FOLDER).path_join(String(engine))


## The name the text of a field's own kernel in *path* is imported under:
## `<module>_fields/` and the path below the module's folder, or below the
## project for a file in no module, with every character an import cannot hold
## read as an underscore. Qualified by the module, so two modules' fields never
## share one, and by the path, so neither do two files of one module.
static func include_for(path: String) -> String:
    var parts := path.get_basename().get_slice("://", path.get_slice_count("://") - 1).split("/", false)
    var at := parts.find("modules")
    var module := "sara"
    if at >= 0 and at + 1 < parts.size():
        module = parts[at + 1]
        parts = parts.slice(at + 2)
    var unspeakable := RegEx.create_from_string("[^A-Za-z0-9_]")
    var below := PackedStringArray()
    for part in parts:
        below.append(unspeakable.sub(part, "_", true))
    return unspeakable.sub(module, "_", true) + "_fields/" + "/".join(below)


## The name of the check kernel for the field imported as *include_name*, which
## is also its file's name. A short hash of the import rather than the import
## itself, because the import spells the path below the module and the file sits
## under the data root, so a deep settings folder pushed the file name past what
## a file system holds (255 bytes) and the check could not be written.
static func check_kernel_name(include_name: String) -> String:
    return "sara_fields_" + include_name.sha256_text().left(16) + CHECK_SUFFIX


## The first line of *said*, a compiler's message, that names an error, which
## is the one naming the file and the line. glslang heads its message with a
## line that names neither.
static func first_error(said: String) -> String:
    for line in said.split("\n"):
        if line.strip_edges().begins_with("ERROR:"):
            return line.strip_edges()
    return said.strip_edges().get_slice("\n", 0)


## Adds *added* for *module_id*, refused when it has no id or no engine, its
## engine already has a field of that id, or its own kernel does not compile.
func register(added: Field, module_id: StringName = &"") -> bool:
    if added == null or added.id.is_empty() or added.engine == &"":
        return false
    if field(added.engine, added.id) != null:
        return false
    if added.has_own_kernel() and not _keep_kernel(added):
        return false
    _fields.append(added)
    _owners[added] = module_id
    changed.emit()
    return true


## The field of *engine* called *field_id*, or null.
func field(engine: StringName, field_id: String) -> Field:
    for each: Field in _fields:
        if each.engine == engine and each.id == field_id:
            return each
    return null


## Every field of *engine*, in the order they were registered.
func fields_for(engine: StringName) -> Array[Field]:
    var out: Array[Field] = []
    for each: Field in _fields:
        if each.engine == engine:
            out.append(each)
    return out


## The module that registered *registered*, empty for a field registered with
## none or not here.
func owner_of(registered: Field) -> StringName:
    return _owners.get(registered, &"")


## Drops every field *module_id* registered, which is its unload.
func unregister_module(module_id: StringName) -> void:
    var kept: Array[Field] = []
    for each: Field in _fields:
        if _owners.get(each, &"") == module_id:
            _owners.erase(each)
        else:
            kept.append(each)
    if kept.size() == _fields.size():
        return
    _fields = kept
    var named: Dictionary[String, Kernel] = {}
    for each: Field in _fields:
        if _kernels.has(each.include_name):
            named[each.include_name] = _kernels[each.include_name]
    _kernels = named
    changed.emit()


## Compiles *own*'s kernel, or finds the one another field of its file
## compiled, and keeps it. Says why through `SaProblems` and answers false when
## it does not compile.
func _keep_kernel(own: Field) -> bool:
    var kept: Kernel = _kernels.get(own.include_name)
    if kept == null:
        kept = Kernel.new(own)
    if not kept.error.is_empty():
        refusals[own.source] = kept.error
        SaProblems.report(
            "SaBrushFieldRegistry",
            (
                tr("The brush field '%s' is not registered, because its kernel in %s does not compile: %s")
                % [own.id, own.source, kept.error]
            )
        )
        return false
    _kernels[own.include_name] = kept
    refusals.erase(own.source)
    return true
