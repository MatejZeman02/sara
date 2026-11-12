## The SPIR-V manifest: what proves a converted kernel is the same kernel.
##
## The conversion converts every kernel in the tree from GLSL to the `.gmacs` dialect,
## and the question that decides whether a conversion is honest is whether the
## program the driver ends up with is the same program. The spec asked for
## identical SPIR-V bytes and the maintainers ruled for stripped bytes, because the
## bytes glslang produces carry the source text, the line numbers and every
## name in the file. Rename a push constant block's instance and the bytes move
## while the program does not.
##
## So this suite compiles every kernel of the tree, at every storage format a
## document may declare, walks the SPIR-V words and drops the nine debug
## instructions, and hashes what is left. That hash is the baseline, and it is
## the only hash on the line.
##
## A second hash of the same module unstripped, unasserted,
## would be meant so that when a stripped hash moved the two together would say whether
## the program changed or only its names did. The pair cannot say that. A moved
## stripped hash is a moved program by construction, and on a red run the unstripped one always moves too.
## Committed and unasserted it would go stale, because every rewrite of a
## kernel's text moves it and nothing warns. The column is left out rather than
## asserted: asserting it would turn a rename red, and a rename staying green
## is the whole point of the stripped bytes.
##
## `tests/spirv_manifest.txt` is the baseline, written from the GLSL tree before
## the sweep begins. Rewrite it with
##
##     SARA_WRITE_SPIRV_MANIFEST=1 SARA_TEST_OFFSCREEN=1 ./run_tests.sh spirv_manifest
##
## which is the shape `core/custom-shader/tests/test_storage_formats.gd` established: a test that
## writes its own fixture when an environment variable asks and compares against
## it otherwise. Rewriting it is a deliberate act with a reason in the commit
## message, never a way past a red run.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

## The pure text half of the compiler, which turns one shader's source into the
## GLSL for one kernel. Reached by path, the way the compiler reaches it.
const KernelSource := preload("res://core/custom-shader/dialect/sa_kernel_source.gd")

## The dialect pass, which is the point of the whole manifest: a file the S
## units rewrite into the Python-shaped `.gmacs` has to reach glslang as the
## GLSL it used to be. Reached the same way, and applied at the same place
## `compile_compute_shader` applies it, before the comments come out.
const Dialect := preload("res://core/custom-shader/dialect/sa_dialect.gd")

## The baseline, beside this file.
const MANIFEST_PATH := "res://tests/spirv_manifest.txt"

## Asking for the baseline to be rewritten rather than compared.
const WRITE_ENV := "SARA_WRITE_SPIRV_MANIFEST"

## The fields of a manifest line: the shader key, the kernel index, the kernel,
## the storage format and the stripped hash.
##
## Asserted per line, because nothing asserting the second column is exactly how
## it went stale. A rewrite that put one back would be caught on the next run
## rather than on the next board.
const MANIFEST_FIELDS := 5

## The magic word every SPIR-V module opens with, and the length of the header
## that follows it: version, generator, id bound, schema.
const SPIRV_MAGIC := 0x07230203
const SPIRV_HEADER_WORDS := 5

## The debug instructions, which name things and locate them in a source file
## nobody ships. Dropping these is the whole difference between "the same
## program" and "the same bytes".
##
## OpString and OpSource carry the source text itself, OpName and OpMemberName
## every identifier, OpLine and OpNoLine the line each instruction came from,
## and OpModuleProcessed the compiler's own notes. None of them is reachable by
## an execution.
const DEBUG_OPCODES := {
    2: "OpSourceContinued",
    3: "OpSource",
    4: "OpSourceExtension",
    5: "OpName",
    6: "OpMemberName",
    7: "OpString",
    8: "OpLine",
    317: "OpNoLine",
    330: "OpModuleProcessed",
}

## The storage formats a document may declare, in the order the manifest lists
## them. Every one of them is a format some kernel is dispatched with, because
## a dispatch takes the format off the texture it was handed and a texture's
## format is its field's, `SaFieldSpec.BYTES_PER_TEXEL` being the four of them.
const FORMATS: Array[int] = [
    RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT,
    RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
    RenderingDevice.DATA_FORMAT_R32_SFLOAT,
    RenderingDevice.DATA_FORMAT_R16_SFLOAT,
]

## A compute shader small enough to read, used to prove the two properties the
## manifest rests on: a change to the body moves the stripped hash and a change
## to a name does not. Written here rather than to a file, because nothing about
## it needs the include pipeline.
const PROBE_SOURCE := """#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba32f, set = 0, binding = 0) uniform image2D canvas;
void main() {
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
    vec4 SCRATCH = imageLoad(canvas, pixel);
    imageStore(canvas, pixel, SCRATCH * 2.0);
}
"""

# ---------------------------------------------------------------------------
# The SPIR-V walk
# ---------------------------------------------------------------------------


## *bytecode* with every debug instruction removed, header kept.
##
## A SPIR-V module is a five-word header and then a stream of instructions, each
## opening with a word that packs its length into the high half and its opcode
## into the low one. Dropping a whole instruction is enough: no debug
## instruction is referenced by anything outside the debug set, and the id bound
## in the header is a count rather than a list, so nothing needs renumbering.
##
## Handed something that is not SPIR-V, this returns it unchanged, and the
## caller's assertion on the magic word is what reports that.
static func strip_debug(bytecode: PackedByteArray) -> PackedByteArray:
    # A SPIR-V module is a whole number of four-byte words by construction.
    @warning_ignore("integer_division")
    var words := bytecode.size() / 4
    if words < SPIRV_HEADER_WORDS or bytecode.decode_u32(0) != SPIRV_MAGIC:
        return bytecode

    var out := bytecode.slice(0, SPIRV_HEADER_WORDS * 4)
    var at := SPIRV_HEADER_WORDS
    while at < words:
        var head := bytecode.decode_u32(at * 4)
        var length := head >> 16
        var opcode := head & 0xFFFF
        if length == 0:
            # A zero-length instruction cannot be stepped over, so the stream is
            # not one this understands. Better to stop than to loop.
            break
        if not DEBUG_OPCODES.has(opcode):
            out.append_array(bytecode.slice(at * 4, (at + length) * 4))
        at += length
    return out


## Which debug instructions *bytecode* holds, as opcode name -> count.
static func debug_instructions(bytecode: PackedByteArray) -> Dictionary:
    var found: Dictionary = {}
    # A SPIR-V module is a whole number of four-byte words by construction.
    @warning_ignore("integer_division")
    var words := bytecode.size() / 4
    if words < SPIRV_HEADER_WORDS or bytecode.decode_u32(0) != SPIRV_MAGIC:
        return found
    var at := SPIRV_HEADER_WORDS
    while at < words:
        var head := bytecode.decode_u32(at * 4)
        var length := head >> 16
        var opcode := head & 0xFFFF
        if length == 0:
            break
        if DEBUG_OPCODES.has(opcode):
            var op_name: String = DEBUG_OPCODES[opcode]
            found[op_name] = int(found.get(op_name, 0)) + 1
        at += length
    return found


static func _sha256(bytes: PackedByteArray) -> String:
    var context := HashingContext.new()
    context.start(HashingContext.HASH_SHA256)
    context.update(bytes)
    # Sixteen hex characters is 64 bits, which is far past what 228 lines can
    # collide on and keeps a manifest line readable on one screen.
    return context.finish().hex_encode().substr(0, 16)


# ---------------------------------------------------------------------------
# Compiling
# ---------------------------------------------------------------------------


## The SPIR-V for *final_source*, or an empty array when glslang refused it.
##
## Compiled here rather than through the compiler, because the compiler hands
## back a shader RID and throws the bytes away, and it is the bytes this suite
## is about. `SaSpirvCache` is deliberately not consulted: its directory holds
## 256 entries and this suite alone asks for 228, so a hit would depend on what
## the last run happened to evict.
func _spirv_for(final_source: String) -> PackedByteArray:
    var rd := GlobalShaderCompiler.get_rd()
    var source := RDShaderSource.new()
    source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
    source.source_compute = final_source
    var spirv := rd.shader_compile_spirv_from_source(source)
    if spirv.compile_error_compute != "":
        return PackedByteArray()
    return spirv.bytecode_compute


## The GLSL handed to glslang for one kernel of *clean_text*, or "" when the
## kernel has no `[numthreads]` and so cannot be assembled.
func _kernel_glsl(kernel_name: String, clean_text: String) -> String:
    var numthreads := KernelSource.extract_numthreads(kernel_name, clean_text)
    if numthreads.size() != 3:
        return ""
    return KernelSource.assemble_glsl(numthreads, KernelSource.replace_kernel_signature(kernel_name, clean_text))


## Whether *file_path* is a shader in the user data directory rather than in the
## tree.
##
## A test fixture is not a kernel of Sara's. `test_storage_formats.gd` writes a
## probe shader to `user://` and hands the compiler its path, which puts it in
## the compiler's list from then on, so without this the manifest would gain
## four kernels or not depending on which suite ran first.
##
## The offscreen runner makes this sharper than it reads: it points
## `XDG_DATA_HOME` at `scratch/xdg-gate/data` inside the checkout, so `user://`
## resolves under `res://` and the compiler's own directory walk finds the probe
## on the next boot as well. This guard
## holds either way because it asks where a path really is rather than what it
## is spelled with.
static func _is_user_data(file_path: String) -> bool:
    return ProjectSettings.globalize_path(file_path).begins_with(ProjectSettings.globalize_path("user://"))


## Every manifest line the tree produces right now, sorted and ready to compare.
##
## The text stages are the compiler's own, in the compiler's order: read,
## comments out, includes pasted, format substituted. Only the last of those
## depends on the format, so the paste is done once per file and the four
## variants branch off it.
##
## Sources are deduplicated before glslang sees them. A kernel that declares no
## image binding, and there are several, assembles to the same text at all four
## formats, and compiling it four times would buy four identical hashes.
func _collect_lines() -> PackedStringArray:
    var by_key: Dictionary = {}
    for file_path: String in GlobalShaderCompiler.index.compute_shader_file_paths:
        if _is_user_data(file_path):
            continue
        by_key[GlobalShaderCompiler.index.shader_key(file_path)] = file_path
    var keys: Array = by_key.keys()
    keys.sort()

    var seen: Dictionary = {}
    var lines := PackedStringArray()
    for key: String in keys:
        var file_path: String = by_key[key]
        var raw := GlobalShaderCompiler.source.load_shader_file(file_path)
        if raw.is_empty():
            continue
        var pasted := GlobalShaderCompiler.source.process_includes(KernelSource.remove_comments(Dialect.to_glsl(raw)), file_path)
        var kernels := KernelSource.extract_kernels(pasted)
        if kernels.is_empty():
            # A file with no kernels is a library. It has no SPIR-V of its own,
            # and every kernel that imports it carries its lines already.
            continue
        for format: int in FORMATS:
            var text: String = GlobalShaderCompiler.source.substitute_storage_formats(pasted, format, {})
            var format_name: String = GlobalShaderCompiler.STORAGE_FORMAT_NAMES[format]
            for index in kernels.size():
                var kernel_name: String = kernels[index]
                var final_source := _kernel_glsl(kernel_name, text)
                var stripped_hash := ""
                if final_source.is_empty():
                    stripped_hash = "no-numthreads"
                elif seen.has(final_source):
                    stripped_hash = seen[final_source]
                else:
                    var bytecode := _spirv_for(final_source)
                    stripped_hash = "did-not-compile" if bytecode.is_empty() else _sha256(strip_debug(bytecode))
                    seen[final_source] = stripped_hash
                lines.append("%s %d %s %s %s" % [key, index, kernel_name, format_name, stripped_hash])
    return lines


# ---------------------------------------------------------------------------
# The manifest file
# ---------------------------------------------------------------------------

const MANIFEST_HEADER := """# The SPIR-V manifest of Sara's kernels, one line per kernel and storage format.
#
# <owner>/<shader> <kernel index> <kernel> <format> <stripped hash>
#
# The stripped hash is what core/custom-shader/dialect/tests/test_spirv_manifest.gd asserts on: the SPIR-V
# with its nine debug instructions dropped, so the names, the lines and the
# source text are out of it. A rewritten kernel that is the same program keeps
# its line here, which is what the dialect conversion was proved by.
#
# Written from the GLSL tree before the conversion. A second hash of the
# unstripped module is not kept, and the suite's docstring says why.
"""


func _write_manifest(lines: PackedStringArray) -> void:
    var file := FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
    if file == null:
        assert_true(false, "Could not write %s: %s" % [MANIFEST_PATH, error_string(FileAccess.get_open_error())])
        return
    file.store_string(MANIFEST_HEADER + "\n".join(lines) + "\n")
    print_rich("        wrote %d manifest lines to %s" % [lines.size(), MANIFEST_PATH])


## The baseline's lines, comments and blanks dropped.
func _read_manifest() -> PackedStringArray:
    var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
    if file == null:
        return PackedStringArray()
    var kept := PackedStringArray()
    for line in file.get_as_text().split("\n"):
        var trimmed := line.strip_edges()
        if trimmed.is_empty() or trimmed.begins_with("#"):
            continue
        kept.append(trimmed)
    return kept


## The first four fields of a manifest line, which name what it is about.
static func _line_id(line: String) -> String:
    var parts := line.split(" ")
    if parts.size() < 4:
        return line
    return " ".join([parts[0], parts[1], parts[2], parts[3]])


# ---------------------------------------------------------------------------
# The tests
# ---------------------------------------------------------------------------


func test_manifest_matches_baseline() -> void:
    var fresh := _collect_lines()
    assert_true(fresh.size() > 0, "The tree has kernels, so the manifest cannot be empty")

    if not OS.get_environment(WRITE_ENV).is_empty():
        _write_manifest(fresh)
        assert_true(true, "%s asked for the baseline to be rewritten" % WRITE_ENV)
        return

    var baseline := _read_manifest()
    assert_true(baseline.size() > 0, "%s holds no lines. Write it with %s=1." % [MANIFEST_PATH, WRITE_ENV])
    if baseline.is_empty():
        return

    var baseline_by_id: Dictionary = {}
    for line in baseline:
        baseline_by_id[_line_id(line)] = line
    var fresh_by_id: Dictionary = {}
    for line in fresh:
        fresh_by_id[_line_id(line)] = line

    for id: String in baseline_by_id:
        if not fresh_by_id.has(id):
            assert_true(false, "'%s' is in the baseline and the tree no longer compiles it" % id)
    for id: String in fresh_by_id:
        if not baseline_by_id.has(id):
            assert_true(false, "'%s' is compiled now and is not in the baseline" % id)

    # One assertion per shared line, so a red run names every kernel that moved
    # rather than the first one.
    for id: String in baseline_by_id:
        if not fresh_by_id.has(id):
            continue
        var was: PackedStringArray = String(baseline_by_id[id]).split(" ")
        var now: PackedStringArray = String(fresh_by_id[id]).split(" ")
        assert_eq(now[4], was[4], "'%s' is not the same program as the baseline's." % id)


func test_every_baseline_line_carries_one_hash() -> void:
    var baseline := _read_manifest()
    assert_true(baseline.size() > 0, "%s holds no lines. Write it with %s=1." % [MANIFEST_PATH, WRITE_ENV])
    for line in baseline:
        assert_eq(
            line.split(" ").size(),
            MANIFEST_FIELDS,
            "'%s' is not %d fields. A sixth would be the unstripped hash that is left out." % [line, MANIFEST_FIELDS]
        )


func test_a_body_change_moves_the_stripped_hash() -> void:
    var base := _spirv_for(PROBE_SOURCE)
    assert_true(not base.is_empty(), "The probe kernel compiles")
    var edited := _spirv_for(PROBE_SOURCE.replace("SCRATCH * 2.0", "SCRATCH * 3.0"))
    assert_true(not edited.is_empty(), "The probe kernel still compiles with one character changed")
    assert_true(
        _sha256(strip_debug(base)) != _sha256(strip_debug(edited)),
        "One character of the body changed the program, so the stripped hash has to move"
    )


func test_a_renamed_local_does_not_move_the_stripped_hash() -> void:
    var base := _spirv_for(PROBE_SOURCE)
    var renamed := _spirv_for(PROBE_SOURCE.replace("SCRATCH", "colour"))
    assert_true(not renamed.is_empty(), "The probe kernel compiles with its local renamed")
    assert_eq(
        _sha256(strip_debug(renamed)),
        _sha256(strip_debug(base)),
        "A renamed local is the same program, so the stripped hash stays"
    )
    assert_true(
        _sha256(renamed) != _sha256(base),
        "The unstripped hash does move, which is the reason the stripped one is what is asserted"
    )


func test_stripping_removes_the_debug_instructions() -> void:
    var base := _spirv_for(PROBE_SOURCE)
    assert_true(not base.is_empty(), "The probe kernel compiles")
    assert_true(base.decode_u32(0) == SPIRV_MAGIC, "What glslang returned opens with the SPIR-V magic word")

    var before := debug_instructions(base)
    assert_true(before.has("OpName"), "glslang names things, which is the whole reason for the strip: %s" % str(before))
    var after := debug_instructions(strip_debug(base))
    assert_eq(after.size(), 0, "Nothing in the debug set survives the strip, and %s did" % str(after.keys()))
    assert_true(strip_debug(base).size() < base.size(), "The stripped module is shorter than the one it came from")
    assert_eq(strip_debug(base).decode_u32(0), SPIRV_MAGIC, "The header is kept as it was")
    assert_eq(
        strip_debug(base).decode_u32(12),
        base.decode_u32(12),
        "The id bound is a count rather than a list, so dropping instructions leaves it alone"
    )


func test_stripping_leaves_what_is_not_spirv_alone() -> void:
    var not_spirv := PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8])
    assert_eq(strip_debug(not_spirv), not_spirv, "Something without the magic word is handed back unchanged")
    assert_eq(debug_instructions(not_spirv).size(), 0, "And has no debug instructions to report")
