## The generated document colour-space include, compiled and run on the GPU.
##
## The requirement: "a generated `.gmacs` include carries the RGB/XYZ
## matrices and transfer pair so kernels never hardcode sRGB". Generating GLSL
## text is easy to get subtly wrong and easy to test wrongly, a transposed mat3
## still compiles, still inverts and still looks like a colour matrix. So this
## suite compiles the real thing through the real include mechanism, runs it, and
## compares the device's answers against the CPU descriptor.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

## Four probes, one per texel of a 4x1 image.
const PROBE_WIDTH := 4

## The GPU is F32 and the CPU side is F64, so agreement is to float precision
## rather than exact. Wide enough for the cube roots, far too tight to pass if a
## matrix were transposed or a transfer curve wrong.
const EPSILON := 1e-5


func _probe_source() -> String:
    # Deliberately plain GLSL rather than .gmacs kernel syntax: the point under
    # test is the include, so depending on numthreads parsing as well would make
    # a failure ambiguous.
    return """#version 450
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
#include "document_color_space"
layout( rgba32f, set = 0, binding = 0 ) uniform image2D result;
void main() {
    imageStore( result, ivec2( 0, 0 ), vec4( document_to_linear( vec3( 0.5, 0.2, 0.8 ) ), 1.0 ) );
    imageStore( result, ivec2( 1, 0 ),
        vec4( linear_to_document( document_to_linear( vec3( 0.5, -0.25, 1.5 ) ) ), 1.0 ) );
    imageStore( result, ivec2( 2, 0 ), vec4( DOCUMENT_RGB_TO_XYZ * vec3( 1.0 ), 1.0 ) );
    imageStore( result, ivec2( 3, 0 ),
        vec4( DOCUMENT_XYZ_TO_RGB * ( DOCUMENT_RGB_TO_XYZ * vec3( 0.3, 0.6, 0.9 ) ), 1.0 ) );
}
"""


## Compiles the probe against *space*'s generated include and returns the four
## resulting texels. Returns an empty array if the GLSL did not compile, so a
## failure names the compile error instead of crashing the run.
func _run_probe(space: SaColorSpace) -> Array:
    GlobalShaderCompiler.set_virtual_include(SaColorSpace.GLSL_INCLUDE_NAME, space.to_glsl())
    var resolved := GlobalShaderCompiler.source.process_includes(_probe_source(), "test_color_space_shader")
    assert_false(resolved.contains("#include"), "The generated include must resolve, not survive into the compiled source")

    var rd := GlobalShaderCompiler.get_rd()
    var source := RDShaderSource.new()
    source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
    source.source_compute = resolved
    var spirv := rd.shader_compile_spirv_from_source(source)
    if spirv.compile_error_compute != "":
        assert_true(false, "Generated include must be valid GLSL: %s" % spirv.compile_error_compute)
        return []

    var shader := rd.shader_create_from_spirv(spirv)
    var pipeline := rd.compute_pipeline_create(shader)
    var output := SaTexture.new(Vector2i(PROBE_WIDTH, 1))
    output.clear(Color(0, 0, 0, 0))

    var uniform := RDUniform.new()
    uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
    uniform.binding = 0
    uniform.add_id(output.rid)
    var uniform_set := rd.uniform_set_create([uniform], shader, 0)

    var list := rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(list, pipeline)
    rd.compute_list_bind_uniform_set(list, uniform_set, 0)
    rd.compute_list_dispatch(list, 1, 1, 1)
    rd.compute_list_end()

    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(output)
    var texels: Array = []
    for x in PROBE_WIDTH:
        texels.append(image.get_pixel(x, 0))

    rd.free_rid(pipeline)
    rd.free_rid(shader)
    GlobalShaderCompiler.clear_virtual_include(SaColorSpace.GLSL_INCLUDE_NAME)
    return texels


func _assert_near(actual: float, expected: float, what: String) -> void:
    assert_true(
        absf(actual - expected) <= EPSILON, "%s: expected %s, got %s" % [what, String.num(expected, 9), String.num(actual, 9)]
    )


func _assert_rgb(actual: Color, expected: Vector3, what: String) -> void:
    _assert_near(actual.r, expected.x, "%s r" % what)
    _assert_near(actual.g, expected.y, "%s g" % what)
    _assert_near(actual.b, expected.z, "%s b" % what)


# ---------------------------------------------------------------------------
# The include mechanism
# ---------------------------------------------------------------------------


func test_a_generated_include_resolves_without_a_file_on_disk() -> void:
    # The document's matrices depend on what the user chose, so they cannot be a
    # file checked into the repository. That is the whole reason virtual includes
    # exist, and there is no such .gmacs anywhere in the tree.
    assert_false(
        GlobalShaderCompiler.source.has_virtual_include(SaColorSpace.GLSL_INCLUDE_NAME),
        "Nothing should be registered before the test registers it"
    )
    var changed := GlobalShaderCompiler.set_virtual_include(SaColorSpace.GLSL_INCLUDE_NAME, "// probe")
    assert_true(changed, "Registering new source reports that it changed")
    assert_false(
        GlobalShaderCompiler.set_virtual_include(SaColorSpace.GLSL_INCLUDE_NAME, "// probe"),
        "Registering identical source reports no change, so nothing recompiles needlessly"
    )

    var resolved := GlobalShaderCompiler.source.process_includes(
        '#include "%s"\nvoid main() {}' % SaColorSpace.GLSL_INCLUDE_NAME, "probe"
    )
    assert_false(resolved.contains("#include"), "The directive is replaced")

    GlobalShaderCompiler.clear_virtual_include(SaColorSpace.GLSL_INCLUDE_NAME)
    assert_false(GlobalShaderCompiler.source.has_virtual_include(SaColorSpace.GLSL_INCLUDE_NAME), "and it can be removed")


# ---------------------------------------------------------------------------
# The generated maths, on the device
# ---------------------------------------------------------------------------


func test_srgb_document_transfer_matches_the_cpu() -> void:
    var space := SaColorSpace.srgb()
    var texels := _run_probe(space)
    assert_eq(texels.size(), PROBE_WIDTH, "The probe must have run")

    # Godot's own sRGB-to-linear is an independent implementation of the same
    # curve, so agreeing with it is a real check rather than a restatement.
    var expected := Color(0.5, 0.2, 0.8).srgb_to_linear()
    _assert_rgb(texels[0], Vector3(expected.r, expected.g, expected.b), "sRGB document_to_linear")


func test_transfer_round_trip_survives_out_of_range_values() -> void:
    # -0.25 and 1.5 are exactly what the no-clamp invariant exists to protect,
    # and the mirrored curve is what lets them round-trip instead of turning into
    # NaN. See core/composite/tests/test_no_clamp.gd.
    for space: SaColorSpace in [SaColorSpace.srgb(), SaColorSpace.linear_srgb()]:
        var texels := _run_probe(space)
        assert_eq(texels.size(), PROBE_WIDTH, "The probe must have run for %s" % space.id)
        _assert_rgb(texels[1], Vector3(0.5, -0.25, 1.5), "%s transfer round trip" % space.id)


func test_linear_document_transfer_is_the_identity() -> void:
    var texels := _run_probe(SaColorSpace.linear_srgb())
    assert_eq(texels.size(), PROBE_WIDTH, "The probe must have run")
    # A linear document decodes to itself. This is the case a hardcoded sRGB
    # curve gets wrong, and the reason the include is generated per document.
    _assert_rgb(texels[0], Vector3(0.5, 0.2, 0.8), "linear document_to_linear")


func test_generated_matrix_maps_white_to_the_white_point() -> void:
    for space in SaColorSpace.presets():
        var texels := _run_probe(space)
        assert_eq(texels.size(), PROBE_WIDTH, "The probe must have run for %s" % space.id)
        var expected := SaColorSpace.xy_to_xyz(space.white)
        _assert_rgb(texels[2], expected, "%s RGB white on the GPU" % space.id)


func test_generated_matrices_are_inverses_on_the_device() -> void:
    for space in SaColorSpace.presets():
        var texels := _run_probe(space)
        assert_eq(texels.size(), PROBE_WIDTH, "The probe must have run for %s" % space.id)
        _assert_rgb(texels[3], Vector3(0.3, 0.6, 0.9), "%s XYZ round trip on the GPU" % space.id)
