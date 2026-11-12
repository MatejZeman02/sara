## Reload Shaders: a kernel edited on disk is rebuilt under its
## own name, one left alone is not, and one broken keeps the pipeline that
## worked with the compiler's message reported.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **A kernel of this suite's own, under `user://`**, compiled once through the
## compiler's own door and then edited and reloaded by path, because the shipped
## kernels are read-only in the tree and a module kernel is edited
## in place. `scenarios/a-command-recompiles-the-shaders-that-changed.json`
## presses the chord on the running app and shoots the corner.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

static var scratch_path: String = SaDataRoot.path("test_g12_reload.gmacs")

const SOURCE := """kernel g12_reload

image canvas

def g12_reload():
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


## The default variant's first kernel RID under this suite's shader.
func _pipeline() -> RID:
    var compiled: Array = GlobalShaderCompiler.get_compute_kernel_compilations(
        GlobalShaderCompiler.index.shader_key(scratch_path)
    )
    return compiled[0] if not compiled.is_empty() else RID()


func _compiled_once() -> RID:
    _write("0.25")
    GlobalShaderCompiler.compile_compute_shader(scratch_path)
    return _pipeline()


## Moves the time the compile of this file recorded out of the way, so the next
## reload reads the file rather than trusting the timestamp.
##
## `FileAccess.get_modified_time` is whole seconds (also recorded beside the
## pattern store), and this suite writes and reloads inside one second, so a
## rewrite here leaves the file's time *exactly* what the compile recorded. A
## person saving in an editor and pressing Ctrl+Shift+R does not have that
## problem, and the second boundary moves the time on its own when the edit is
## not in the same second as the compile. A test cannot wait out a boundary, so
## it does what the boundary would.
func _the_time_moved() -> void:
    GlobalShaderCompiler.source.shader_mtimes[scratch_path] = 1


func test_an_edited_kernel_is_rebuilt_under_its_own_name() -> void:
    var before := _compiled_once()
    assert_true(before.is_valid(), "The kernel compiled to begin with")
    var generation := GlobalShaderCompiler.compile_generation

    _write("0.75")
    _the_time_moved()
    var result := GlobalShaderCompiler.reload_changed([scratch_path])

    assert_eq(Array(result["rebuilt"]), [GlobalShaderCompiler.index.shader_key(scratch_path)], "It was rebuilt")
    assert_true(_pipeline().is_valid(), "into a pipeline that works")
    assert_true(_pipeline() != before, "which is a new one")
    assert_true(GlobalShaderCompiler.compile_generation > generation, "and live computes are told to follow it")


func test_a_kernel_nobody_edited_is_left_alone() -> void:
    var before := _compiled_once()
    var generation := GlobalShaderCompiler.compile_generation

    var result := GlobalShaderCompiler.reload_changed([scratch_path])

    assert_true(Array(result["rebuilt"]).is_empty(), "Nothing is rebuilt")
    assert_eq(int(result["unchanged"]), 1, "and the one file is counted as unchanged")
    assert_eq(_pipeline(), before, "so its pipeline is the same one")
    assert_eq(GlobalShaderCompiler.compile_generation, generation, "and nothing is told to reload")


## The modified time is asked before the text, so an untouched
## file is never opened. The witness is the text cache itself: it is emptied
## here with the file's time still the one the compile recorded, and it stays
## empty, which is what says the reload did not read the file. A reload that had
## read it would have put the text back.
func test_an_untouched_file_is_never_read() -> void:
    var before := _compiled_once()
    GlobalShaderCompiler.source.shader_code_cache.erase(scratch_path)

    var result := GlobalShaderCompiler.reload_changed([scratch_path])

    assert_true(Array(result["rebuilt"]).is_empty(), "Nothing is rebuilt")
    assert_eq(int(result["unchanged"]), 1, "and the untouched file is counted as unchanged")
    assert_false(GlobalShaderCompiler.source.shader_code_cache.has(scratch_path), "because it was never read")
    assert_eq(_pipeline(), before, "so its pipeline is the same one")


## The filter is the time, so a file whose time moved is read, and what it says
## is what decides. Here the text moved with the time, and it rebuilds.
func test_a_moved_time_reads_the_file_and_an_edit_is_rebuilt() -> void:
    var before := _compiled_once()
    var generation := GlobalShaderCompiler.compile_generation

    _write("0.75")
    _the_time_moved()
    var result := GlobalShaderCompiler.reload_changed([scratch_path])

    assert_eq(Array(result["rebuilt"]), [GlobalShaderCompiler.index.shader_key(scratch_path)], "The edit is rebuilt")
    assert_true(_pipeline() != before, "into a pipeline that is a new one")
    assert_true(GlobalShaderCompiler.compile_generation > generation, "and live computes are told to follow it")


## And the text is still behind the time rather than replaced by it: the same
## text under a newer time is read and reported unchanged, which is the case a
## coarse or a frozen filesystem produces.
func test_a_moved_time_over_the_same_text_is_still_unchanged() -> void:
    var before := _compiled_once()
    var generation := GlobalShaderCompiler.compile_generation

    _write("0.25")
    _the_time_moved()
    var result := GlobalShaderCompiler.reload_changed([scratch_path])

    assert_true(Array(result["rebuilt"]).is_empty(), "Nothing is rebuilt")
    assert_eq(int(result["unchanged"]), 1, "the file is unchanged")
    assert_eq(_pipeline(), before, "so its pipeline is the same one")
    assert_eq(GlobalShaderCompiler.compile_generation, generation, "and nothing is told to reload")


func test_a_broken_kernel_keeps_the_pipeline_that_worked() -> void:
    var before := _compiled_once()
    var generation := GlobalShaderCompiler.compile_generation

    _write("this_is_not_glsl")
    _the_time_moved()
    var result := GlobalShaderCompiler.reload_changed([scratch_path])
    var shader_name := GlobalShaderCompiler.index.shader_key(scratch_path)

    assert_true((result["failed"] as Dictionary).has(shader_name), "The broken kernel is reported as failed")
    assert_false(String(result["failed"][shader_name]).is_empty(), "with the compiler's message")
    assert_eq(_pipeline(), before, "and the pipeline under its name is still the one that worked")
    assert_true(_pipeline().is_valid(), "which is still valid")
    assert_eq(GlobalShaderCompiler.compile_generation, generation, "and no live compute is told to reload onto nothing")


func test_the_corner_line_names_what_was_rebuilt_and_what_kept_its_build() -> void:
    assert_eq(
        SaAppCommands.reload_notice({"rebuilt": [], "failed": {}, "unchanged": 40}), "No shader changed.", "Nothing to do says so"
    )
    assert_eq(
        SaAppCommands.reload_notice({"rebuilt": ["dab"], "failed": {}, "unchanged": 39}),
        "Reloaded 1 shader.",
        "one rebuilt in the singular"
    )
    var line := SaAppCommands.reload_notice(
        {"rebuilt": ["dab", "composite"], "failed": {"blur": "3: 'x' : undeclared identifier\nmore"}, "unchanged": 37}
    )
    assert_true(line.begins_with("Reloaded 2 shaders."), "several in the plural")
    assert_true(line.contains("blur kept its last build: 3: 'x' : undeclared identifier"), "and a failure by name")
    assert_false(line.contains("more"), "with the first line of its message only")
