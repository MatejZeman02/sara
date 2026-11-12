## A reloaded kernel file rebuilds every storage variant it had,
## the half float one a document in that precision asks for as well as the
## default, and a broken edit keeps both.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A scratch kernel under `user://`, the way `test_reload_shaders.gd` builds
## one, compiled in the default format and then asked for at half float, so the
## compiler holds two variant keys for the one file before the edit.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

static var scratch_path: String = SaDataRoot.path("test_d2_reload_variants.gmacs")
const HALF := RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT

const SOURCE := """kernel d2_reload

image canvas

def d2_reload():
    ivec2 at = ivec2(global_id.xy)
    image_store(canvas, at, vec4(%s, 0.0, 0.0, 1.0))
"""


func after_each() -> void:
    if FileAccess.file_exists(scratch_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_path))


func _write(red: String) -> void:
    var file := FileAccess.open(scratch_path, FileAccess.WRITE)
    file.store_string(SOURCE % red)
    file.close()


func _shader_name() -> String:
    return GlobalShaderCompiler.index.shader_key(scratch_path)


## The first kernel RID of the variant *storage_format* asks for.
func _pipeline(storage_format: int) -> RID:
    var compiled: Array = GlobalShaderCompiler.get_compute_kernel_compilations(_shader_name(), storage_format)
    return compiled[0] if not compiled.is_empty() else RID()


## Both variants built from the first text, answered as `[default, half]`.
func _both_compiled() -> Array:
    _write("0.25")
    GlobalShaderCompiler.compile_compute_shader(scratch_path)
    return [_pipeline(GlobalShaderCompiler.DEFAULT_STORAGE_FORMAT), _pipeline(HALF)]


## The compile recorded the file's time in whole seconds, and this suite writes
## inside the same second, so the time is moved the way the other reload suites move it.
func _the_time_moved() -> void:
    GlobalShaderCompiler.source.shader_mtimes[scratch_path] = 1


func test_an_edit_rebuilds_the_default_and_the_half_float_variant() -> void:
    var before := _both_compiled()
    assert_true(before[0].is_valid() and before[1].is_valid(), "Both variants compiled to begin with")
    assert_true(before[0] != before[1], "as two pipelines")

    _write("0.75")
    _the_time_moved()
    var result := GlobalShaderCompiler.reload_changed([scratch_path])

    assert_eq(Array(result["rebuilt"]), [_shader_name()], "The file was rebuilt")
    var default_after := _pipeline(GlobalShaderCompiler.DEFAULT_STORAGE_FORMAT)
    var half_after := _pipeline(HALF)
    assert_true(default_after.is_valid() and default_after != before[0], "the default into a new pipeline")
    assert_true(half_after.is_valid() and half_after != before[1], "and the half float variant into a new one too")
    assert_eq(GlobalShaderCompiler.source.shader_code_cache.get(scratch_path, ""), SOURCE % "0.75", "both from the new text")


func test_a_broken_edit_keeps_both_variants() -> void:
    var before := _both_compiled()
    var generation := GlobalShaderCompiler.compile_generation

    _write("this_is_not_glsl")
    _the_time_moved()
    var result := GlobalShaderCompiler.reload_changed([scratch_path])

    assert_true(Dictionary(result["failed"]).has(_shader_name()), "The reload says the file failed")
    assert_false(GlobalShaderCompiler.compile_error(_shader_name()).is_empty(), "with the compiler's message")
    assert_eq(_pipeline(GlobalShaderCompiler.DEFAULT_STORAGE_FORMAT), before[0], "The default kept its pipeline")
    assert_eq(_pipeline(HALF), before[1], "and so did the half float variant")
    assert_eq(GlobalShaderCompiler.compile_generation, generation, "and nothing is told to reload")
