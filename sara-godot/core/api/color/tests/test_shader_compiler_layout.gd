## The push constant block: the std430 layout parsed out of the GLSL, and the
## sizes and offsets the packers on the GDScript side write at.
##
## A sibling of `test_shader_compiler_source.gd` rather than more cases in it,
## because that file stood at gdlint's `max-public-methods` of thirty-two exactly
## and a test case is a public method, so it took no more. The split by subject the front end's own files already have.
##
## This half is worth standing on its own anyway: the front end's other
## transforms answer text, and this one answers numbers a caller then writes
## bytes at, so it is read beside `test_params_by_name.gd`, which packs against
## the layouts parsed here.
##
## The two parse cases are pure string transforms. The three below them ask the
## compiler about shaders it loaded at startup, so the suite declares the
## rendering device rather than reporting a missing one as a wrong answer.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const KernelSource := preload("res://core/custom-shader/dialect/sa_kernel_source.gd")
const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")


## std430 gives an array the stride its element aligns to, not the element's size.
##
## A block packed from this
## layout: a `vec3[4]` measured as four times twelve is forty-eight bytes, and
## every field declared after it is then placed sixteen bytes early, so the kernel
## reads plausible numbers out of the wrong offsets and nothing fails. No kernel
## in the tree declares one today, which is why the defect was latent, and the S
## sweep rewrites all twenty-five of them. The storage buffer side of the same
## rule is pinned by `test_a_vec3_array_in_a_buffer_has_a_stride_of_sixteen` in
## `test_storage_formats.gd`.
func test_a_vec3_array_in_a_block_strides_by_sixteen() -> void:
    var block := "layout( push_constant, std430 ) uniform Params { vec3 tint[4]; float opacity; } params;"

    var layout := KernelSource.extract_push_constant_layout(block)

    assert_eq(int(layout[0]["size"]), 64, "Four entries of sixteen, not four of twelve")
    assert_eq(int(layout[1]["offset"]), 64, "so opacity comes after the run and not sixteen bytes inside it")
    assert_eq(int(layout[2]["offset"]), 68, "and the block is what those two declare")


## The types whose stride is their own size must not move, which is most of them.
##
## `float[9]` is the composite matrices, declared that way rather than as `mat3`
## exactly because its stride is four, and rounding a stride up
## unconditionally would have made them nine entries of sixteen.
func test_the_other_array_types_keep_the_stride_they_had() -> void:
    var block := "layout( push_constant, std430 ) uniform Params" + " { float m[9]; vec2 pair[2]; vec4 quad[2]; } params;"

    var layout := KernelSource.extract_push_constant_layout(block)

    assert_eq(int(layout[0]["size"]), 36, "float[9] is nine tight floats")
    assert_eq(int(layout[1]["size"]), 16, "vec2[2] is two of eight")
    assert_eq(int(layout[2]["size"]), 32, "and vec4[2] two of sixteen")


# --- The block a caller fills ---------------------------------------------------


## The push constant block is parsed, and its size is what each packer sends.
##
## Nothing used to compare the GLSL block with the GDScript that fills it. The two
## were matched by eye, and the composite block has been hand-edited twice: once
## when the coordinate system arrived and once when the dispatch region did. A
## wrong count is at least refused by RenderingDevice, though it reports it as the
## push constant being *absent* rather than as the wrong size.
func test_every_push_constant_block_is_the_size_its_packer_sends() -> void:
    PaintKernel.compile()
    var expected := {
        "composite": 128,  # 32 floats: offset, opacity, W, two matrices, the curve, coordinates, region
        "convert_color_space": 80,  # 20 floats, SaColorSpace.CONVERSION_PUSH_CONSTANT_FLOATS
        "fill": 32,
        "clear": 32,
        PaintKernel.NAME: 64,  # 16 floats, PaintKernel.pack_params
    }
    for shader_name: String in expected:
        assert_eq(
            GlobalShaderCompiler.push_constant_bytes(shader_name),
            int(expected[shader_name]),
            "%s declares the block its packer fills" % shader_name
        )


## The offsets the composite packer relies on are the offsets the shader declares.
##
## These constants are the packer's structure written down. Checking them against
## the parsed GLSL is the closest thing to checking the *order*, which is the
## failure mode that stays silent: a misplaced field is a plausible wrong colour,
## not an error.
func test_the_composite_packer_writes_where_the_shader_reads() -> void:
    # Exact: every field of this block is four-byte aligned or better, which the
    # size test above already establishes.
    @warning_ignore("integer_division")
    var float_at := func(field: String) -> int:
        var byte_offset := GlobalShaderCompiler.source.push_constant_offset("composite", field)
        return -1 if byte_offset < 0 else byte_offset / 4

    assert_eq(float_at.call("offset"), 0, "The destination offset opens the block")
    assert_eq(
        float_at.call("blend_white"),
        SaCompute.COMPOSITE_BLEND_WHITE_INDEX,
        "and the packer overwrites the reference white exactly where the shader reads it"
    )
    assert_eq(float_at.call("doc_to_linear_srgb"), 4, "The colour space's floats start after those four")
    assert_eq(
        float_at.call("region_x"),
        4 + SaColorSpace.PUSH_CONSTANT_FLOATS,
        "and the dispatch region starts after the colour space's %d" % SaColorSpace.PUSH_CONSTANT_FLOATS
    )


## An include declares no block, which is not an error and must not read as one.
func test_a_shader_without_a_block_reports_no_size_rather_than_a_wrong_one() -> void:
    assert_eq(GlobalShaderCompiler.push_constant_bytes("transfer_curve"), 0, "A library takes no push constant")
    assert_eq(GlobalShaderCompiler.push_constant_bytes("not_a_shader"), 0, "Nor does a shader that does not exist")
    assert_eq(GlobalShaderCompiler.source.push_constant_offset("composite", "not_a_field"), -1, "An unknown field is -1")
