## A kernel run as one call: the bindings, the params, the groups and the
## dispatch derived from what the kernel declares and the rectangle it covers.
##
## The eight lines a caller writes today are a storage format, a handful of
## binds by slot, a positional float array, two group counts and a dispatch,
## and every one of them is already written down in the kernel's own preamble.
## `SaCompute.run()` reads them from there instead, so a call site says what it
## is painting rather than how the descriptor set is shaped.
##
## Both probes are written to `user://` by this suite and compiled from there,
## the shape `test_storage_formats.gd` uses, so no probe kernel ships in the
## tree or in the startup report.
##
## The helpers this suite reaches into live in
## `sa_push_constants.gd` and `sa_binding_slots.gd`.
##
## This suite prints one error on purpose, "the region is empty, so there is
## nothing to dispatch". It is the refusal `test_a_refused_call_dispatches_nothing`
## asks for, and a `push_error` is not something a suite can catch, so the
## dispatch counter is what the case reads instead.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const PushConstants := preload("res://core/custom-shader/sa_push_constants.gd")
const BindingSlots := preload("res://core/custom-shader/sa_binding_slots.gd")
const KernelSource := preload("res://core/custom-shader/dialect/sa_kernel_source.gd")

const F32 := RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT

## The scripting example, in the GLSL the compiler reads. The same
## kernel through the same call is proved in the dialect too. `gaussian` is
## inlined rather than imported, because `import` is the dialect's word and a
## `#include` would need a second file beside a probe that is meant to be one.
const BLUR_NAME := "sa_run_blur_probe"
static var scratch_blur_path: String = SaDataRoot.path("sa_run_blur_probe.gmacs")
const BLUR_SOURCE := """
#kernel blur_x

layout( SA_STORAGE_FORMAT, set = 0, binding = 0 ) uniform readonly image2D src;
layout( SA_STORAGE_FORMAT, set = 0, binding = 1 ) uniform image2D dst;
layout( push_constant, std430 ) uniform Params {
    float sigma;
    int radius;
} params;

float gaussian( float x, float sigma ) {
    return exp( -( x * x ) / ( 2.0 * sigma * sigma ) );
}

[numthreads( 8, 8, 1 )] void blur_x() {
    ivec2 at = ivec2( gl_GlobalInvocationID.xy );
    ivec2 size = imageSize( dst );
    if ( at.x >= size.x || at.y >= size.y ) return;
    vec4 sum = vec4( 0.0 );
    float weight = 0.0;
    for ( int i = -params.radius; i <= params.radius; i++ ) {
        ivec2 from = clamp( at + ivec2( i, 0 ), ivec2( 0 ), size - ivec2( 1 ) );
        float w = gaussian( float( i ), params.sigma );
        sum += w * imageLoad( src, from );
        weight += w;
    }
    imageStore( dst, at, sum / weight );
}
"""

## One image and the two fields the maintainers' rule of 2026-09-08 names, written
## straight out to the first texel so the region the call derived can be read
## back rather than argued about.
const WHERE_NAME := "sa_run_region_probe"
static var scratch_where_path: String = SaDataRoot.path("sa_run_region_probe.gmacs")
const WHERE_SOURCE := """
#kernel where

layout( SA_STORAGE_FORMAT, set = 0, binding = 0 ) uniform image2D dst;
layout( push_constant, std430 ) uniform Params {
    vec2 origin;
    vec2 extent;
} params;

[numthreads( 8, 8, 1 )] void where() {
    ivec2 at = ivec2( gl_GlobalInvocationID.xy );
    if ( at.x > 0 || at.y > 0 ) return;
    imageStore( dst, ivec2( 0 ), vec4( params.origin, params.extent ) );
}
"""


## The probe on disk and a compute over it.
##
## Compiled every time rather than once. `user://` outlives the process, so a
## probe whose source changed between runs sits on disk as it was, and the
## suite went on reporting a field the block below no longer declared. Cheap:
## the SPIR-V cache keys on the source, so an unchanged probe is read back
## rather than built.
func _compiled(shader_name: String, path: String, source: String) -> SaCompute:
    if GlobalShaderCompiler.get_kernel_names(shader_name).is_empty():
        var file := FileAccess.open(path, FileAccess.WRITE)
        file.store_string(source)
        file.close()
    GlobalShaderCompiler.compile_compute_shader(path)
    return SaCompute.new(shader_name)


func _read_float(texture: SaTexture, index: int = 0) -> Array:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var base := index * 16
    return [bytes.decode_float(base), bytes.decode_float(base + 4), bytes.decode_float(base + 8), bytes.decode_float(base + 12)]


## A one-texel line with the middle lit, so a blur along x has something to
## spread and the result says whether the weights reached the neighbours.
func _lit_row() -> SaTexture:
    var source := SaTexture.new(Vector2i(3, 1), F32)
    var texels := PackedFloat32Array([0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0])
    GlobalShaderCompiler.get_rd().texture_update(source.rid, 0, texels.to_byte_array())
    return source


# ---------------------------------------------------------------------------
# The spec's kernel through the one call
# ---------------------------------------------------------------------------


## What the unit is for. Two images, two fields and a rectangle, and nothing in
## the call names a slot, a byte or a group.
func test_the_specs_blur_runs_through_one_call() -> void:
    var src := _lit_row()
    var dst := SaTexture.new(Vector2i(3, 1), F32)
    dst.clear(Color(0, 0, 0, 0))
    var compute := _compiled(BLUR_NAME, scratch_blur_path, BLUR_SOURCE)

    compute.run("blur_x", {"src": src, "dst": dst}, {"sigma": 1.0, "radius": 1}, Rect2i(0, 0, 3, 1))

    var middle := _read_float(dst, 1)
    var edge := _read_float(dst, 0)
    assert_true(middle[0] > edge[0], "The lit texel is still the brightest")
    assert_true(edge[0] > 0.0, "and its neighbour took some of it, which is the blur having run at all")
    assert_almost_eq(middle[3], middle[0], 1e-5, "Every channel is weighted the same way")


## The groups come off the region, so a rectangle wider than one workgroup is
## covered to its last texel rather than to the first eight.
func test_the_region_counts_the_groups() -> void:
    var src := SaTexture.new(Vector2i(20, 1), F32)
    src.clear(Color(1, 1, 1, 1))
    var dst := SaTexture.new(Vector2i(20, 1), F32)
    dst.clear(Color(0, 0, 0, 0))
    var compute := _compiled(BLUR_NAME, scratch_blur_path, BLUR_SOURCE)

    compute.run("blur_x", {"src": src, "dst": dst}, {"sigma": 1.0, "radius": 1}, Rect2i(0, 0, 20, 1))

    assert_almost_eq(_read_float(dst, 19)[0], 1.0, 1e-5, "The twentieth texel was covered, which needs three groups of eight")


# ---------------------------------------------------------------------------
# The region written into the block
# ---------------------------------------------------------------------------


## The maintainers' rule of 2026-09-08. A kernel that dispatches over one rectangle
## and reads another has to be told which it is on, and every caller was passing
## it by hand.
func test_a_block_that_declares_the_region_is_given_it() -> void:
    var dst := SaTexture.new(Vector2i(1, 1), F32)
    dst.clear(Color(0, 0, 0, 0))
    var compute := _compiled(WHERE_NAME, scratch_where_path, WHERE_SOURCE)

    compute.run("where", {"dst": dst}, {}, Rect2i(3, 4, 5, 6))

    assert_eq(_read_float(dst), [3.0, 4.0, 5.0, 6.0], "The position and the size of the region, in the fields that named them")


## The other half of the rule. The caller wins, because passing one by hand is
## exactly the case the rule exists for.
func test_a_passed_origin_wins_and_the_extent_still_arrives() -> void:
    var dst := SaTexture.new(Vector2i(1, 1), F32)
    dst.clear(Color(0, 0, 0, 0))
    var compute := _compiled(WHERE_NAME, scratch_where_path, WHERE_SOURCE)

    compute.run("where", {"dst": dst}, {"origin": Vector2(9.0, 9.0)}, Rect2i(3, 4, 5, 6))

    assert_eq(_read_float(dst), [9.0, 9.0, 5.0, 6.0], "The caller's origin stands and the extent is still the region's")


## Without a GPU as well, because the rule is about a Dictionary and a layout
## and the two probes above cannot say which field was filled by whom.
func test_the_region_fills_only_what_the_block_declares_and_the_caller_left_out() -> void:
    var layout := KernelSource.extract_push_constant_layout(
        "layout( push_constant, std430 ) uniform Params { vec2 origin; float opacity; float pad; } p;"
    )
    var filled := PushConstants.with_region(layout, {"opacity": 1.0, "pad": 0.0}, Rect2i(7, 8, 9, 10))

    assert_eq(filled["origin"], Vector2(7, 8), "origin is declared, so the region's position lands in it")
    assert_false(filled.has("extent"), "extent is not declared, so nothing is invented for it")
    assert_eq(filled["opacity"], 1.0, "and the caller's own values are untouched")


func test_the_callers_dictionary_is_not_written_through() -> void:
    var layout := KernelSource.extract_push_constant_layout(
        "layout( push_constant, std430 ) uniform Params { vec2 origin; vec2 extent; } p;"
    )
    var mine := {}
    PushConstants.with_region(layout, mine, Rect2i(1, 2, 3, 4))

    assert_true(mine.is_empty(), "A caller who keeps its params between runs does not find the last region in them")


# ---------------------------------------------------------------------------
# The refusals
# ---------------------------------------------------------------------------


## A binding the kernel does not declare is a typo or a rename, and the one word
## that is wrong is the only thing worth printing.
func test_a_wrong_name_in_the_bindings_is_refused_with_the_name() -> void:
    var layout := GlobalShaderCompiler.binding_layout(BLUR_NAME)
    if layout.is_empty():
        _compiled(BLUR_NAME, scratch_blur_path, BLUR_SOURCE)
        layout = GlobalShaderCompiler.binding_layout(BLUR_NAME)

    var complaint := BindingSlots.binding_complaint(layout, {"soruce": RID(), "dst": RID()})

    assert_true("'soruce'" in complaint, "The name the caller wrote is in the message")
    assert_true("'src'" in complaint, "and so are the names it could have meant")


## A declaration the caller left out is a hole in the uniform set, which
## surfaces as a Vulkan complaint about a descriptor rather than as the word.
func test_a_binding_left_out_is_reported_by_name() -> void:
    var layout := GlobalShaderCompiler.binding_layout(BLUR_NAME)
    if layout.is_empty():
        _compiled(BLUR_NAME, scratch_blur_path, BLUR_SOURCE)
        layout = GlobalShaderCompiler.binding_layout(BLUR_NAME)

    var complaint := BindingSlots.binding_complaint(layout, {"src": RID()})

    assert_true("'dst'" in complaint, "The binding nothing was passed for is named")
    assert_false("'src'" in complaint, "and the one that was is not")


func test_a_complete_set_of_bindings_has_no_complaint() -> void:
    var layout := GlobalShaderCompiler.binding_layout(BLUR_NAME)
    if layout.is_empty():
        _compiled(BLUR_NAME, scratch_blur_path, BLUR_SOURCE)
        layout = GlobalShaderCompiler.binding_layout(BLUR_NAME)

    assert_eq(BindingSlots.binding_complaint(layout, {"src": RID(), "dst": RID()}), "", "Both declarations answered for")


## A refusal stops the call before anything reaches the GPU. Counted rather than
## watched for the error, because a `push_error` is not something a suite can
## catch and a dispatch that did happen is.
func test_a_refused_call_dispatches_nothing() -> void:
    var dst := SaTexture.new(Vector2i(1, 1), F32)
    var compute := _compiled(WHERE_NAME, scratch_where_path, WHERE_SOURCE)
    var before := SaCompute.dispatches

    compute.run("where", {"dst": dst}, {}, Rect2i(0, 0, 0, 0))

    assert_eq(SaCompute.dispatches, before, "An empty region is nothing to paint, and nothing was painted")
