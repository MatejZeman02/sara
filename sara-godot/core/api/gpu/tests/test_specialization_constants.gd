## Does Godot 4.7 honour specialization constants for *compute* pipelines?
##
## The specialisation-constant work is built entirely on the answer, and it called for
## prototyping it before committing to a rewrite of composite.gmacs. The answer is
## yes, and this is kept rather than thrown away so the answer stays checked: it is
## a property of the engine and the driver, not of Sara, so it can stop being true
## on an upgrade without anything else noticing.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const SOURCE := """#version 450
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
layout(constant_id = 0) const int MODE = 0;
layout(rgba32f, set = 0, binding = 0) uniform image2D target;
void main() {
    vec4 v = vec4(0.25, 0.0, 0.0, 1.0);
    if (MODE == 1) { v = vec4(0.5, 0.0, 0.0, 1.0); }
    else if (MODE == 2) { v = vec4(0.75, 0.0, 0.0, 1.0); }
    imageStore(target, ivec2(gl_GlobalInvocationID.xy), v);
}
"""


func test_one_module_makes_pipelines_that_behave_differently() -> void:
    var rd := GlobalShaderCompiler.get_rd()
    var source := RDShaderSource.new()
    source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
    source.source_compute = SOURCE
    var spirv := rd.shader_compile_spirv_from_source(source)
    assert_eq(spirv.compile_error_compute, "", "The probe shader has to compile before it can prove anything")
    if spirv.compile_error_compute != "":
        return

    # One compile, one shader module. That is the half the specialisation-constant work wants: today the
    # composite file is compiled twenty times, once per kernel.
    var shader := rd.shader_create_from_spirv(spirv)
    assert_true(shader.is_valid(), "One SPIR-V module")

    var seen: Array = []
    var pipelines: Array = []
    for mode in 3:
        var constant := RDPipelineSpecializationConstant.new()
        constant.constant_id = 0
        constant.value = mode
        var pipeline := rd.compute_pipeline_create(shader, [constant])
        assert_true(pipeline.is_valid(), "Pipeline %d specialized from the same module" % mode)
        pipelines.append(pipeline)

        var texture := SaTexture.new(Vector2i(1, 1))
        texture.clear(Color(0, 0, 0, 0))
        var uniform := RDUniform.new()
        uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
        uniform.binding = 0
        uniform.add_id(texture.rid)
        var uniform_set := rd.uniform_set_create([uniform], shader, 0)

        var list := rd.compute_list_begin()
        rd.compute_list_bind_compute_pipeline(list, pipeline)
        rd.compute_list_bind_uniform_set(list, uniform_set, 0)
        rd.compute_list_dispatch(list, 1, 1, 1)
        rd.compute_list_end()

        var data := rd.texture_get_data(texture.rid, 0)
        seen.append(snappedf(data.decode_float(0), 0.001))
        rd.free_rid(uniform_set)

    for rid: RID in pipelines:
        rd.free_rid(rid)
    rd.free_rid(shader)

    assert_eq(seen, [0.25, 0.5, 0.75], "Each pipeline ran its own branch, so the constant reached the GPU")
