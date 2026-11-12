## A pixel function freed after the compiler leaves quietly.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The whole run failed at exit on five SCRIPT ERRORs with every suite passed,
## `clear_virtual_include` called on a freed `GlobalShaderCompiler` from
## `SaPixelFunction._notification`. The five were the stamp brush's pattern
## kernels, compiled when the detached `Main` of
## `test_no_boot_frame_holds_the_window_on_windows` built its Texture page,
## and still held once the scene tree had been deleted. The include table is
## the compiler's own and goes with it, so a pixel function freed after the
## compiler has nothing left to clear, and it asks first.
##
## A suite cannot free the autoload, and exit is the case. So the second test
## hands a pixel function to the one node the tree deletes after the compiler:
## the root deletes its children last first, and `SaRunLog` stands before
## `GlobalShaderCompiler` in `project.godot`. Without the guard that exit
## crashes the engine with signal 11 inside `_notification` rather than
## logging, and `run_tests.sh` reads a crash after its pass line as the
## Vulkan teardown it forgives, so the crash shows in the log and not in the
## exit code. The whole run's SCRIPT ERROR check is the one that fails.
extends "res://tests/test_framework.gd"

const PixelFunction := preload("res://core/custom-shader/compiler/sa_pixel_function.gd")

## The meta key the kept pixel function hangs on `SaRunLog` under.
const KEPT_META: StringName = &"d1_pixel_function_kept_past_the_compiler"

## A pixel function with no module of its own, so its include is `sara`'s and
## no fixture module's include is cleared by it.
const SOURCE := """uniform float level: hint_range(0, 1) = 0.5

def pixel(ivec2 at) -> vec4:
    vec4 c = src(at)
    return vec4(vec3(step(level, luminance(c.rgb))), c.a)
"""


## The ordinary case, which the guard must leave as it was: a pixel function
## dropped while the compiler stands takes its include with it.
func test_a_pixel_function_freed_while_the_compiler_stands_clears_its_include() -> void:
    var include_name := _registered_and_dropped("res://d1_freed_in_the_run.gmacs")
    assert_false(include_name.is_empty(), "the pixel function named an include")
    assert_false(
        GlobalShaderCompiler.source.has_virtual_include(include_name),
        "and dropping it while the compiler stands cleared that include"
    )


## The exit case. `SaRunLog` stands before the compiler among the root's
## children, so the tree deletes it after, and the pixel function it holds is
## freed with the compiler already gone. The assertions hold the premise, and
## the exit holds the rest.
func test_a_pixel_function_freed_after_the_compiler_is_one_the_tree_frees_last() -> void:
    assert_true(
        SaRunLog.get_index() < GlobalShaderCompiler.get_index(),
        "the run log stands before the compiler, so the root deletes it after"
    )
    var kept := PixelFunction.new("res://d1_kept_past_the_compiler.gmacs", SOURCE)
    assert_false(kept.include_name.is_empty(), "the kept pixel function names an include to clear")
    GlobalShaderCompiler.set_virtual_include(kept.include_name, SOURCE)
    SaRunLog.set_meta(KEPT_META, kept)
    assert_eq(SaRunLog.get_meta(KEPT_META), kept, "and the run log holds it until the tree is deleted")


## Registers a pixel function's include and drops the function by returning,
## since a local set to null can leave the free for later.
func _registered_and_dropped(path: String) -> String:
    var pixels := PixelFunction.new(path, SOURCE)
    GlobalShaderCompiler.set_virtual_include(pixels.include_name, SOURCE)
    assert_true(GlobalShaderCompiler.source.has_virtual_include(pixels.include_name), "the include was registered")
    return pixels.include_name
