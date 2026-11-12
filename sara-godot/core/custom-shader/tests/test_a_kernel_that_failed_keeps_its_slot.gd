## A kernel that failed to compile keeps its slot among the pipelines, so the
## kernels after it are still found at their own index.
##
## The compiler files a failed kernel as an empty RID in its place, and
## `SaPipelines` built one pipeline per valid shader and skipped the empty one.
## A shader whose second kernel broke then held two pipelines where it declared
## three, and index 1 ran the third kernel. This hands the pipelines a variant
## of three shaders with the middle one empty, borrowed from a shader that did
## compile, and asks each slot.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const PipelinesScript = preload("res://core/custom-shader/sa_pipelines.gd")


func test_the_kernel_after_a_failed_one_keeps_its_index() -> void:
    var rd: RenderingDevice = GlobalShaderCompiler.get_rd()
    var borrowed: Array = GlobalShaderCompiler.get_compute_kernel_compilations("clear")
    assert_false(borrowed.is_empty(), "The clear shader compiled, so its shader can be borrowed")
    if borrowed.is_empty():
        return
    var shader: RID = borrowed[0]
    var kernels := PipelinesScript.pipelines_of(rd, [shader, RID(), shader], "b2_test")
    assert_eq(kernels.size(), 3, "Three kernels declared, three slots, the failed one among them")
    assert_true(kernels[0].is_valid(), "The first kernel compiled and is held")
    assert_false(kernels[1].is_valid(), "The failed kernel's slot is an empty RID")
    assert_true(kernels[2].is_valid(), "The third kernel is still at index 2")
    for pipeline: RID in kernels:
        if pipeline.is_valid():
            rd.free_rid(pipeline)
