## A brush field that brings its own kernel, in the noise brush's field pass:
## `noise_dab` built again with the field's function where the shipped fields
## are read.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **One seam, one line.** `noise_dab.gmacs` reads its field through
## `noise_field_read`, which `noise_field_seam.gmacs` beside this file defines
## over the three shipped fields, and imports it on a line of its own,
## [constant SEAM]. A field with its own kernel is painted by a copy of the
## kernel with that line swapped for an import of the field's function, under
## the name the door's registry keeps its text as, and a `noise_field_read`
## that calls it at the contract's numbers. The copy is written under the data
## root's generated kernels, as a pixel function's wrapper is, with this
## module's leg in its path, so the compiler owns it as this module's and its
## imports resolve as the shipped kernel's do. Its kernel keeps the name
## `noise_dab`, so the dab list records it and packs its block as it does the
## shipped one's.
##
## **Built once a field, when the engine first asks whether the field is its
## own.** `noise_fields.gd`'s `is_ours` asks, and the Texture row asks that
## when a module registers a field, so the build lands at registration rather
## than at a press. A field whose pass does not compile is passed over with a
## sentence through `SaProblems`, as a field naming a kernel the engine does
## not have is passed over.
##
## **Read on the GPU alone.** The texture sensor reads the field again on the
## CPU down the middle of the stroke, which a module's GLSL cannot be, so a
## field of its own takes the slot after the last of `noise_fields.gd`'s
## `KERNELS`, where the CPU reading finds no picture's mask and answers the
## middle grey the sensor reads for no texture.
extends RefCounted

## The shipped kernel, the text a field's pass is built from.
const DAB_PATH: String = "res://modules/sara-noise-brush-engine/noise_dab.gmacs"
## The kernel's name, which the copy keeps.
const KERNEL: String = "noise_dab"
## The line of the kernel a field's own function goes in at.
const SEAM: String = "import noise_field_seam"
## The module this is, the leg of the copy's path the compiler reads its owner
## from.
const OWNER: String = "sara-noise-brush-engine"

## Each field's pass by the field's instance id: the shader it compiled as, or
## empty when it did not. A field registered again is a new instance and is
## built again.
static var _shaders: Dictionary[int, String] = {}


## Whether *candidate* brings a kernel of its own that this engine's pass runs.
static func runs(candidate: SaBrushFieldRegistry.Field) -> bool:
    return candidate.has_own_kernel() and not shader_for(candidate).is_empty()


## The shader a stroke through *chosen* dispatches, built the first time the
## field is asked about, or empty when it brings no kernel of its own, its pass
## did not compile, or the door has not kept its function's text, which it does
## from its registration on, so a field is never built before the door took it.
static func shader_for(chosen: SaBrushFieldRegistry.Field) -> String:
    if chosen == null or not chosen.has_own_kernel() or not GlobalShaderCompiler.source.has_virtual_include(chosen.include_name):
        return ""
    var key := chosen.get_instance_id()
    if not _shaders.has(key):
        _shaders[key] = _build(chosen)
    return _shaders[key]


## The compute a stroke through *chosen* dispatches: *held* when it already
## runs that shader, otherwise a new one, the field's own pass or the shipped
## kernel, whose uniform sets the stroke's binds build afresh.
static func compute_for(chosen: SaBrushFieldRegistry.Field, held: SaCompute) -> SaCompute:
    var shader := shader_for(chosen)
    var wanted := GlobalShaderCompiler.resolve_shader_name(shader if not shader.is_empty() else KERNEL)
    if held != null and GlobalShaderCompiler.resolve_shader_name(held.shader_name) == wanted:
        return held
    return SaCompute.new(wanted)


## The text of *own*'s pass: the shipped kernel with [constant SEAM] swapped for
## [method read_for]. Empty when the shipped kernel cannot be read or has no
## seam, or more than one. A checkout made on Windows ends its lines in CR LF,
## and the seam is looked for with a bare LF, so the kernel is read as LF.
static func source_for(own: SaBrushFieldRegistry.Field) -> String:
    var shipped := FileAccess.get_file_as_string(DAB_PATH).replace("\r\n", "\n")
    if shipped.count(SEAM + "\n") != 1:
        return ""
    return shipped.replace(SEAM + "\n", read_for(own))


## What stands at the seam for *own*: the import of its function, and a read
## that hands it the field's three numbers and the stroke's offset out of the
## field's buffer and lays Relief over its lightness, as the shipped fields'
## second channel takes it, while the field has two and the Channels row says
## two.
static func read_for(own: SaBrushFieldRegistry.Field) -> String:
    var answer := "%s(along, across, half_width, numbers, offset)" % SaBrushFieldRegistry.FUNCTION
    var lines := PackedStringArray()
    lines.append("import %s" % own.include_name)
    lines.append("")
    lines.append("")
    lines.append("def noise_field_read(float along, float across, float half_width) -> vec2:")
    lines.append("    vec3 numbers = vec3(field.values[NOISE_FIELD_A], field.values[NOISE_FIELD_B], field.values[NOISE_FIELD_C])")
    lines.append("    vec2 offset = vec2(field.values[NOISE_FIELD_OFFSET_X], field.values[NOISE_FIELD_OFFSET_Y])")
    lines.append("    vec2 reading = clamp(%s, vec2(0.0), vec2(1.0))" % answer)
    lines.append("    if field.values[NOISE_FIELD_CHANNELS] > 1.5:")
    lines.append("        reading.y = clamp(0.5 + (reading.y - 0.5) * field.values[NOISE_FIELD_RELIEF], 0.0, 1.0)")
    lines.append("    return reading")
    lines.append("")
    return "\n".join(lines)


## Writes *own*'s pass and compiles it at the default depth, and answers the
## shader, or empty with a sentence through `SaProblems`. A machine with no
## device builds nothing and paints nothing.
static func _build(own: SaBrushFieldRegistry.Field) -> String:
    if GlobalShaderCompiler.get_rd() == null:
        return ""
    var text := source_for(own)
    if text.is_empty():
        _pass_over(own, TranslationServer.translate("%s has no line '%s' to build it in at.") % [DAB_PATH, SEAM])
        return ""
    var stem := KERNEL + "_" + own.include_name.replace("/", "_")
    var folder := SaDataRoot.path(SaBrushFieldRegistry.GENERATED_FOLDER).path_join("modules").path_join(OWNER)
    var path := folder.path_join(stem + ".gmacs")
    DirAccess.make_dir_recursive_absolute(folder)
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        _pass_over(
            own, TranslationServer.translate("%s cannot be written (%s).") % [path, error_string(FileAccess.get_open_error())]
        )
        return ""
    file.store_string(text)
    file.close()
    GlobalShaderCompiler.compile_compute_shader(path)
    var shader := GlobalShaderCompiler.index.shader_key(path)
    var said := GlobalShaderCompiler.compile_error(shader)
    if not said.is_empty() or GlobalShaderCompiler.get_kernel_names(shader).is_empty():
        _pass_over(own, TranslationServer.translate("its pass does not compile: %s") % SaBrushFieldRegistry.first_error(said))
        return ""
    return shader


## Says through `SaProblems` that *own* is passed over, and *why*.
static func _pass_over(own: SaBrushFieldRegistry.Field, why: String) -> void:
    SaProblems.report(
        "NoiseOwnField", TranslationServer.translate("The noise brush passes over the brush field '%s', since %s") % [own.id, why]
    )
