## The source of one shader on its way to glslang: read from disk, includes
## pasted in, the storage-format token substituted, and a record of which file
## every resulting line came from.
##
## A file of its own rather than part of `global_shader_compiler.gd`, so the
## compiler keeps the index and the cache and this keeps the text. Preloaded by
## path from the compiler rather than reached through a `class_name`, because a
## class name resolves only after the editor rescans its class cache.
##
## The virtual-include registry lives here because a generated include is
## resolved before the disk is asked, so it belongs to the paste rather than to
## the file index beside it. The format substitution lives here because it is a
## step of the same text pipeline, which is kept whole rather than in halves.

@tool
extends RefCounted

## The pure text half: comments, kernels, signatures, the push constant block.
const KernelSource := preload("res://core/custom-shader/dialect/sa_kernel_source.gd")

## The per-binding half, which does the format substitution itself.
const Bindings := preload("res://core/custom-shader/compiler/sa_bindings.gd")

## The Python-shaped dialect. An imported library written in it pastes as GLSL,
## which is why the pass runs here as well as in the compiler: the paste is the
## other point a file's text is read.
const Dialect := preload("res://core/custom-shader/dialect/sa_dialect.gd")

## The file half, which answers what an `#include` resolves to, which files the
## walk found and which key a written name means. By path for the reason above.
const ShaderIndex := preload("res://core/custom-shader/compiler/sa_shader_index.gd")

## The GLSL format qualifier each RenderingDevice format compiles to.
##
## Float formats only, at the two depths a document may declare, in four channels
## for colour and one for a field that is not colour: a mask, a height, a
## concentration. Integer formats clamp by construction and stay out, because
## nothing in a document clamps. Here because the substitution below is the
## one reader, and the compiler names both constants on for its callers.
const STORAGE_FORMAT_NAMES := {
    RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT: "rgba32f",
    RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT: "rgba16f",
    RenderingDevice.DATA_FORMAT_R32_SFLOAT: "r32f",
    RenderingDevice.DATA_FORMAT_R16_SFLOAT: "r16f",
}

## What a shader compiles for when nobody asks for anything else.
const DEFAULT_STORAGE_FORMAT := RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT

## The file index, handed in by the compiler that built both. This class holds
## no compiler: what it reached there, the source cache and the modification
## times, is its own below, and a name is resolved by the index.
var _index: ShaderIndex

## file path -> the text it held when it was last read, which is what a hot
## reload compares the disk against.
var shader_code_cache: Dictionary[String, String] = {}

## file path -> the modification time of that read, so the hot-reload scan can
## stat rather than read. Here with the cache and not on the index, because both
## record one event, a read, and this class is the only reader. Plain because
## `core/custom-shader/dialect/tests/test_shader_compiler_source.gd` reads the times.
var shader_mtimes: Dictionary[String, int] = {}

## Dialect text -> the GLSL it reads as, comments removed, for every text this
## compiler has read.
##
## The translation is a function of the text alone, and it is the dear part of a
## compile: 6 ms to 8 ms for a filter's own file on the laptop and 2 ms to 4 ms
## for each library it imports, where the SPIR-V and the pipelines after it take
## under 2 ms. A shader is read again for every format it is
## built at, and a library for every shader that imports it, so a filter's first
## use on an F16 document translated once more what boot had translated at F32,
## in the frame the painter opened its dialog.
##
## Keyed on the text rather than the path, so an edited file or a changed virtual
## include is a new key and nothing has to say that the old one went stale. A
## text the dialect refuses says so on its first read only, and the GLSL compile
## that fails after it on every later one says the rest.
var _glsl_by_text: Dictionary[String, String] = {}

## How many translations are kept before the table starts again. Boot reads
## about a hundred and fifty distinct texts. A virtual include rewritten at every
## change of a pixel function is a new key each time, so without a cap a long
## session at a lab would keep every version it ever typed.
const GLSL_KEPT: int = 1024


func _init(index: ShaderIndex) -> void:
    _index = index


## *text* as GLSL with its comments removed, translated once for each distinct
## text. The two points a file's text is read, the shader itself in the compiler
## and each library in the paste below, both come through here.
##
## A text no translation was kept for between starts is translated here and
## kept, see `SaGlslCache`, unless the dialect raised an error while it read it.
func glsl_of(text: String) -> String:
    var known: Variant = _glsl_by_text.get(text)
    if known != null:
        return known
    var kept := SaGlslCache.shared()
    var glsl := kept.read(text)
    if glsl.is_empty():
        var caught := SaErrorCatcher.listening()
        glsl = KernelSource.remove_comments(Dialect.to_glsl(text))
        caught.stop()
        if caught.reports(SaErrorCatcher.ERRORS).is_empty():
            kept.keep(text, glsl)
    if _glsl_by_text.size() >= GLSL_KEPT:
        _glsl_by_text.clear()
    _glsl_by_text[text] = glsl
    return glsl


## Takes *glsl* as what *text* reads as, translated elsewhere, see
## `SaTranslationsAhead`.
func learn(text: String, glsl: String) -> void:
    if _glsl_by_text.size() >= GLSL_KEPT:
        _glsl_by_text.clear()
    _glsl_by_text[text] = glsl


## Include name -> GLSL source, for includes that are generated rather than
## stored. Checked before the disk, so a generated include shadows a file of the
## same name.
##
## The document colour space is one: its matrices and transfer
## pair depend on what the user chose at creation, so they cannot live in a file
## checked into the repository. See SaColorSpace.to_glsl().
var _virtual_includes: Dictionary[String, String] = {}


## Registers *source* under *include_name*, so `#include "<include_name>"`
## resolves to it. Returns true when this replaces different source, which is the
## caller's signal that anything already compiled against it is now stale.
func set_virtual_include(include_name: String, source: String) -> bool:
    assert(not include_name.is_empty(), "Virtual include name cannot be empty")
    var changed: bool = _virtual_includes.get(include_name, "") != source
    _virtual_includes[include_name] = source
    return changed


func has_virtual_include(include_name: String) -> bool:
    return _virtual_includes.has(include_name)


func clear_virtual_include(include_name: String) -> void:
    _virtual_includes.erase(include_name)


## Load shader file and cache its content
func load_shader_file(file_path: String) -> String:
    var file := FileAccess.open(file_path, FileAccess.READ)
    if file == null:
        push_error(
            (
                "GlobalShaderCompiler: cannot open %s (%s). The shader will not be compiled."
                % [file_path, error_string(FileAccess.get_open_error())]
            )
        )
        shader_code_cache[file_path] = ""
        return ""
    var raw_text := file.get_as_text()
    shader_code_cache[file_path] = raw_text
    # Recorded here so the first hot-reload scan sees an unchanged file rather
    # than an unknown one, which would make it read everything once for nothing.
    shader_mtimes[file_path] = FileAccess.get_modified_time(file_path)
    return raw_text


## Reads every discovered shader whose file has changed since the last look, and
## answers whether any of their source differs from what is cached.
func scan_for_changes() -> bool:
    var needs_recompile := false

    # Check if any file (including includes) has changed.
    #
    # The timestamp is the cheap question and it answers for almost every file
    # almost every time, so ask it first and read only what it says changed.
    for file_path: String in _index.compute_shader_file_paths:
        var modified_time := FileAccess.get_modified_time(file_path)
        if modified_time != 0 and modified_time == shader_mtimes.get(file_path, 0):
            continue

        var file := FileAccess.open(file_path, FileAccess.READ)
        if file == null:
            continue
        shader_mtimes[file_path] = modified_time

        var current_code := file.get_as_text()
        if shader_code_cache.get(file_path, "") != current_code:
            shader_code_cache[file_path] = current_code
            needs_recompile = true
    return needs_recompile


## The files among *scope* whose text differs from the text they were compiled
## from, for Reload Shaders.
##
## The modified time is asked first, the way `scan_for_changes` asks it, because
## reading every kernel file in full to answer what a timestamp answers is the
## cost the note behind this command was filed about. A file whose time equals
## the one recorded when it was compiled is skipped without being opened, and
## every file whose time moved falls through to the text compare.
##
## The time is the filter and never the answer. A filesystem with a coarse or a
## frozen modified time, a checkout that rewrites every file with one timestamp,
## and an editor that writes through a rename are all cases where the time lies
## and the text does not, so a moved time costs one read and the read decides.
func changed_files(scope: Array) -> Array[String]:
    var changed: Array[String] = []
    for file_path: String in scope:
        var stored_time: int = shader_mtimes.get(file_path, 0)
        if stored_time != 0 and stored_time == FileAccess.get_modified_time(file_path):
            continue
        if FileAccess.get_file_as_string(file_path) != str(shader_code_cache.get(file_path, "")):
            changed.append(file_path)
    return changed


## Shader name -> one `[file, line]` per line of the source glslang was handed.
##
## glslang counts lines in the text it was given, which by then has its includes
## pasted in and two lines of preamble on top, so `ERROR: 0:137:` named a line that
## exists in no file anyone can open. This is what turns it back into
## `composite.gmacs:42`.
var line_origins: Dictionary[String, Array] = {}

## Built while includes are pasted, then handed to line_origins once per shader.
var _pending_origins: Array = []

## Lines the assembler puts in front of every kernel: the #version and the
## local_size layout. See KernelSource.assemble_glsl.
const PREAMBLE_LINES: int = KernelSource.PREAMBLE_LINES


## One `[file, line]` entry per line of *text*, all attributed to *file*.
func _origins_for(text: String, file: String) -> Array:
    var out: Array = []
    for i in text.count("\n") + 1:
        out.append([file, i + 1])
    return out


## Process '#include' directives and replace with file content recursively
func process_includes(clean_text: String, compute_shader_file_path: String) -> String:
    var include_regex := RegEx.new()
    include_regex.compile('#include\\s+"([^"]+)"')

    # What has already been pasted into this compilation chain, keyed by the file
    # that provided it rather than by the name it was asked for. Two files can ask
    # for the same library by different names, `transfer_curve` and
    # `sara/transfer_curve`, and pasting it twice is a redefinition error.
    var already_included: Array = []

    # Origin file -> the origin file whose directive pasted it, which is the
    # import chain a duplicate is read against. A library asked for again by a
    # file it did not lead to is a diamond and drops in silence, the way a
    # guarded header does in C. One asked for by a file it led to is a cycle.
    var pasted_by: Dictionary[String, String] = {}

    _pending_origins = _origins_for(clean_text, compute_shader_file_path)

    var include_match := include_regex.search(clean_text)
    while include_match != null:
        var include_name := include_match.get_string(1)

        # Whose directive this is. A library pasted into a shader keeps its own
        # origin in the map, so an include written inside that library resolves
        # from the library's point of view rather than from the file that pasted
        # it, which is what lets a module's library reach the module's own helpers.
        var directive_line := clean_text.substr(0, include_match.get_start(0)).count("\n")
        var asked_by := compute_shader_file_path
        if directive_line < _pending_origins.size():
            asked_by = str(_pending_origins[directive_line][0])

        # A generated include shadows a file of the same name. Checked first so a
        # document's colour maths, which cannot be a file in the repo, resolves
        # the same way every other include does.
        var is_virtual := _virtual_includes.has(include_name)
        var made := "" if is_virtual else KernelsOf.source(include_name, _index, asked_by)
        is_virtual = is_virtual or not made.is_empty()
        var include_path: String = "" if is_virtual else _index.find_include_file(include_name, asked_by)
        var identity: String = include_name if is_virtual else include_path

        var origin_file: String = include_name + "." + ShaderIndex.COMPUTE_SHADER_EXTENSION
        if not is_virtual and not include_path.is_empty():
            origin_file = include_path

        if not identity.is_empty() and identity in already_included:
            # Already in this compilation. Lessons 0 and 1 import both colour
            # libraries and the sRGB one imports Oklab itself, so a warning here
            # put a backtrace in the log for every run of code that is right.
            # Only a cycle is worth a word.
            if _leads_to(pasted_by, asked_by, origin_file):
                var cycle := [asked_by.get_file(), include_name, compute_shader_file_path]
                push_warning("Import cycle: %s imports %s, which leads back to it, in %s" % cycle)
            clean_text = _splice(clean_text, include_match, "")
            include_match = include_regex.search(clean_text)
            continue

        already_included.append(identity)
        if not pasted_by.has(origin_file):
            pasted_by[origin_file] = asked_by

        var include_content: String
        if is_virtual:
            include_content = glsl_of(made if not made.is_empty() else _virtual_includes[include_name])
        else:
            var include_file := FileAccess.open(include_path, FileAccess.READ) if not include_path.is_empty() else null
            if include_file == null:
                # The sentinel is an empty expansion, which is what release
                # builds already did - but silently. Whatever the include
                # declared is now undefined, so the GLSL compile fails next
                # and this error is what explains it.
                push_error(
                    "GlobalShaderCompiler: cannot read include '%s' required by %s." % [include_name, compute_shader_file_path]
                )
                include_content = ""
            else:
                include_content = glsl_of(include_file.get_as_text())

        # Replace the #include directive with the actual file content, and
        # replace the directive's line in the map with the file's own lines.
        # The line after a file's last newline is the rest of the directive's
        # line, where `import a, b` leaves its second include, so it keeps the
        # directive's origin and the second resolves from the importing file.
        var pasted := _origins_for(include_content, origin_file)
        if directive_line < _pending_origins.size():
            pasted[-1] = _pending_origins[directive_line] if include_content.ends_with("\n") else pasted[-1]
            _pending_origins = (_pending_origins.slice(0, directive_line) + pasted + _pending_origins.slice(directive_line + 1))
        clean_text = _splice(clean_text, include_match, include_content)

        # Search again in the updated text.
        # This automatically finds nested includes inside the newly pasted `include_content`!
        include_match = include_regex.search(clean_text)

    return Dialect.EdgeCheck.finished(clean_text)


## Whether *ancestor* is *file* or one of the files whose imports pasted it,
## walking *pasted_by* up to the shader the compilation started from.
func _leads_to(pasted_by: Dictionary[String, String], file: String, ancestor: String) -> bool:
    var at := file
    while at != ancestor:
        if not pasted_by.has(at):
            return false
        at = pasted_by[at]
    return true


## Replaces exactly the span *found* covers, and nothing else.
##
## Rather than `String.replace(directive, content)`, which rewrites *every*
## occurrence at once. A file including the same library twice would have both
## directives replaced on the first pass, so the source would be pasted twice
## and the already-included guard would never see the second one, the one case
## that guard exists for. The result is a GLSL redefinition error blamed on the
## library rather than on the file including it.
func _splice(text: String, found: RegExMatch, replacement: String) -> String:
    return text.substr(0, found.get_start(0)) + replacement + text.substr(found.get_end(0))


## Where every line of a compiled shader came from, as `[file, line]` in the order
## glslang sees them. Empty for a shader that was never compiled.
func line_map(written_name: String) -> Array:
    return line_origins.get(_index.resolve_shader_name(written_name), [])


## Rewrites glslang's line numbers into file and line as written.
##
## glslang counts lines in the text it was handed: includes already pasted, two
## lines of preamble in front. So `ERROR: 0:137:` names a line in a file that does
## not exist, and finding the real one meant reconstructing the paste by hand. Each
## such number is followed by the file and line it came from.
##
## The original is left in place rather than replaced. It is what glslang said, and
## a mapping that is ever wrong should not be able to hide that.
func locate_glsl_error(message: String, written_name: String) -> String:
    var origins := line_map(written_name)
    if origins.is_empty() or message.is_empty():
        return message

    var regex := RegEx.new()
    regex.compile("\\b0:(\\d+)")
    var out := ""
    var read_from := 0
    for found in regex.search_all(message):
        out += message.substr(read_from, found.get_end(0) - read_from)
        var source_line := int(found.get_string(1)) - PREAMBLE_LINES - 1
        if source_line >= 0 and source_line < origins.size():
            var origin: Array = origins[source_line]
            out += " [%s:%d]" % [str(origin[0]).get_file(), origin[1]]
        read_from = found.get_end(0)
    out += message.substr(read_from)
    return out


## Files the source just processed came from, filed under *shader_name* so a
## glslang error against it can be traced back. Called once per compile.
func remember_origins(shader_name: String) -> void:
    line_origins[shader_name] = _pending_origins


## The GLSL qualifier for *storage_format*.
##
## An unknown format falls back to the default rather than emitting the token,
## because the token is not valid GLSL and the compile error it would produce
## points at the shader instead of at the caller that asked for a format nothing
## supports.
func _qualifier_for(storage_format: int) -> String:
    var qualifier: String = STORAGE_FORMAT_NAMES.get(storage_format, "")
    if qualifier.is_empty():
        push_warning(
            (
                "GlobalShaderCompiler: no GLSL qualifier for storage format %d, compiling as %s."
                % [storage_format, STORAGE_FORMAT_NAMES[DEFAULT_STORAGE_FORMAT]]
            )
        )
        qualifier = STORAGE_FORMAT_NAMES[DEFAULT_STORAGE_FORMAT]
    return qualifier


## Replaces the storage-format placeholder binding by binding: *binding_formats*
## maps a binding index to the format it gets, and every other image binding
## gets *storage_format*. The mechanism and the reason are in sa_bindings.gd.
func substitute_storage_formats(clean_text: String, storage_format: int, binding_formats: Dictionary[int, int]) -> String:
    return Bindings.substitute(clean_text, _qualifier_for(storage_format), _qualifiers_for(binding_formats))


## The key one assignment of formats compiles under. See sa_bindings.gd.
func variant_key(storage_format: int, binding_formats: Dictionary[int, int] = {}) -> String:
    return Bindings.variant_key(_qualifier_for(storage_format), _qualifiers_for(binding_formats))


func _qualifiers_for(binding_formats: Dictionary[int, int]) -> Dictionary[int, String]:
    var out: Dictionary[int, String] = {}
    for binding: int in binding_formats:
        out[binding] = _qualifier_for(int(binding_formats[binding]))
    return out


## The `push_constant` block of a compiled shader, as an Array of
## `{name, type, offset, size, pad}` in declaration order, plus the total under the key
## -1. Empty when the shader declares no block.
##
## Parsed at compile time and kept, so the block is checked against the
## GDScript that fills it. `SaCompute.set_push_constant_float_array()` only pads
## the tail, so without this the two sides are matched by eye. A wrong *count*
## is caught by an assert. A wrong *order* is silent and looks like a colour
## bug, and filling the block by name is what catches it.
var push_constant_layouts: Dictionary[String, Array] = {}


## Total size in bytes of a shader's push constant block, or 0 when it has none.
##
## This is the number RenderingDevice demands *exactly*, and it reports a mismatch
## as the constant being absent rather than as the wrong size.
func push_constant_bytes(written_name: String) -> int:
    var layout: Array = push_constant_layout(written_name)
    if layout.is_empty():
        return 0
    var total: int = layout[-1]["offset"]
    return total


## The whole parsed block of *written_name*, as `{name, type, offset, size, pad}`
## in declaration order with a closing entry whose offset is the total. Empty for
## a shader that declares no block. This is what packs a Dictionary by name. The
## name is resolved here, the way `line_map` resolves it, so the compiler's
## forward of this is a forward and nothing else.
func push_constant_layout(written_name: String) -> Array:
    return push_constant_layouts.get(_index.resolve_shader_name(written_name), [])


## Byte offset of one named field, or -1 when the shader has no such field.
func push_constant_offset(written_name: String, field_name: String) -> int:
    for field: Dictionary[String, Variant] in push_constant_layout(written_name):
        if str(field["name"]) == field_name:
            var offset: int = field["offset"]
            return offset
    return -1


## Files what the source of *shader_name* declared as its push constant block.
func remember_push_constants(shader_name: String, clean_text: String) -> void:
    push_constant_layouts[shader_name] = KernelSource.extract_push_constant_layout(clean_text)


## `import kernels_of/<library>/<suffix>`, a kernel for each formula of a
## library. Every `def <name>_<suffix>(out ivec2 at, out vec4 value) -> bool`
## becomes `kernel <name>`, which stores what the formula answers through the
## importer's own `store_<suffix>(at, value)`, written above the import. So a
## formula is a kernel in each file that imports its library, a commit that
## rounds as well as a composite, and nobody writes the wrapper or lists it.
class KernelsOf:
    const PREFIX := "kernels_of/"
    const WRAPPER := (
        "kernel {0}\ndef {0}():\n    ivec2 canvas_coords\n    vec4 value\n"
        + "    if {0}_{1}(canvas_coords, value): store_{1}(canvas_coords, value)\n"
    )

    ## The include as dialect text, empty when the name is not one of these or
    ## the library is not found, which the paste then reports as it would.
    static func source(include_name: String, index: ShaderIndex, asked_by: String) -> String:
        var parts := include_name.trim_prefix(PREFIX).rsplit("/", true, 1)
        if not include_name.begins_with(PREFIX) or parts.size() != 2:
            return ""
        var path := index.find_include_file(parts[0], asked_by)
        if path.is_empty():
            return ""
        var formula := RegEx.create_from_string("(?m)^def (\\w+)_%s\\(out ivec2 \\w+, out vec4 \\w+\\) -> bool:" % parts[1])
        var text := "import %s\n" % index.shader_key(path)
        for found in formula.search_all(FileAccess.get_file_as_string(path)):
            var name := found.get_string(1)
            text += WRAPPER.format([name, parts[1]])
        return text
