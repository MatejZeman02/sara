## A shader compiled a second time takes the first compile's pipelines with it,
## and the object holding them frees only what the device still holds.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The gate's log read three "Attempted to free invalid ID" in the middle of the
## run, under the pattern suite's `test_the_shipped_kernels_declare_the_tile_uniform`,
## which made a `SaPatternKernel` of its own beside the pattern's for each shipped
## kernel. Both compile a `SaPixelFunction` over one source, the second compile
## frees the shader the first's pipelines were made from, and the device drops
## those pipelines with it. The first kernel's `SaPipelines` then freed them again
## when the loop let it go.
##
## The engine's error goes to its own log and never reaches a script, so no case
## here can see it come back. What these read is the state the error needs, and
## the one call that decides what is freed.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Pipelines := preload("res://core/custom-shader/sa_pipelines.gd")


func test_a_second_compile_of_one_source_drops_the_first_pipelines() -> void:
    var rd := GlobalShaderCompiler.get_rd()
    var source := _shipped_source()
    assert_false(source.is_empty(), "a shipped pattern to compile")

    var first := SaPatternKernel.new(source)
    assert_true(first.uniforms().size() > 0, "the first kernel compiles")
    var first_pipelines: Array[RID] = first._function.compute.pipelines.kernels.duplicate()
    assert_true(first_pipelines.size() > 0, "and holds pipelines")
    assert_eq(Pipelines.still_held(rd, first_pipelines).size(), first_pipelines.size(), "which the device holds")

    var second := SaPatternKernel.new(source)
    assert_true(second.uniforms().size() > 0, "The second kernel over the same source compiles")
    var second_pipelines: Array[RID] = second._function.compute.pipelines.kernels
    assert_eq(Pipelines.still_held(rd, second_pipelines).size(), second_pipelines.size(), "and its pipelines are held")
    assert_true(
        Pipelines.still_held(rd, first_pipelines).is_empty(),
        "while the first kernel's are gone from the device, freed with the shader the second compile replaced"
    )
    assert_true(first_pipelines[0].is_valid(), "though the RID in hand still reads as valid, which is why it was freed twice")


func test_a_pipeline_the_device_dropped_is_not_freed_again() -> void:
    var rd := GlobalShaderCompiler.get_rd()
    var source := _shipped_source()
    var first := SaPatternKernel.new(source)
    first.uniforms()
    var dropped: Array[RID] = first._function.compute.pipelines.kernels.duplicate()
    var second := SaPatternKernel.new(source)
    second.uniforms()

    assert_eq(Pipelines.still_held(rd, dropped), [] as Array[RID], "nothing of the first kernel's is left to free")
    var mixed: Array[RID] = dropped.duplicate()
    mixed.append_array(second._function.compute.pipelines.kernels)
    assert_eq(
        Pipelines.still_held(rd, mixed),
        second._function.compute.pipelines.kernels,
        "and from a mixed list only what the device holds is kept, in order"
    )
    assert_eq(Pipelines.still_held(rd, [RID()] as Array[RID]), [] as Array[RID], "and an empty RID is nobody's")


## The source of the first shipped pattern, the kind of file the pattern suite
## compiled twice.
func _shipped_source() -> String:
    var store := SaPatternStore.new([SaPatternStore.SHIPPED_DIR])
    var pattern := store.pattern("Canvas Weave")
    return pattern.source if pattern != null else ""
