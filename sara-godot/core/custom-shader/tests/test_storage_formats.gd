## Per-format kernel variants: the same kernel compiled for each storage depth.
##
## A kernel's `layout()` format is validated against the bound image view. When
## they disagree, Vulkan says every load and store is undefined across the whole
## image, and it still returns entirely correct numbers on the hardware this was
## first measured on, which is why the mismatch shipped unnoticed and why the
## fix needs a test that checks the *contract*, not just the output.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const F32 := RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
const F16 := RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
const R32 := RenderingDevice.DATA_FORMAT_R32_SFLOAT

const Bindings := preload("res://core/custom-shader/compiler/sa_bindings.gd")

## The dialect pass, so the walk below reads a converted kernel the way the
## compiler does. The conversion of every kernel rewrites `layout( ... ) uniform image2D` as
## `image`, and a walk that only knows the GLSL spelling checks nothing at all
## once the sweep is through.
const Dialect := preload("res://core/custom-shader/dialect/sa_dialect.gd")


func _read_half(texture: SaTexture, index: int = 0) -> Array:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var base := index * 8
    return [bytes.decode_half(base), bytes.decode_half(base + 2), bytes.decode_half(base + 4), bytes.decode_half(base + 6)]


func _read_float(texture: SaTexture, index: int = 0) -> Array:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var base := index * 16
    return [bytes.decode_float(base), bytes.decode_float(base + 4), bytes.decode_float(base + 8), bytes.decode_float(base + 12)]


# ---------------------------------------------------------------------------
# Per-binding formats, on the source alone
# ---------------------------------------------------------------------------

const TWO_IMAGES := """
layout( SA_STORAGE_FORMAT, set = 0, binding = 0 ) uniform image2D canvas;
layout( SA_STORAGE_FORMAT, set = 0, binding = 3 ) uniform image2D mask;
"""


## The blocker F6 recorded: the token used to be one global substitution, so
## every image a kernel bound inherited the canvas's format, and a single-channel
## mask bound as rgba32f is undefined across the whole image.
func test_two_image_bindings_can_compile_at_two_formats() -> void:
    var out: String = GlobalShaderCompiler.source.substitute_storage_formats(TWO_IMAGES, F32, {3: R32})

    assert_true("layout( rgba32f, set = 0, binding = 0 )" in out, "The canvas keeps the document's format")
    assert_true("layout( r32f, set = 0, binding = 3 )" in out, "and the mask gets its own")
    assert_false("SA_STORAGE_FORMAT" in out, "No token may survive into GLSL")


func test_a_binding_nobody_named_follows_the_document() -> void:
    var out: String = GlobalShaderCompiler.source.substitute_storage_formats(TWO_IMAGES, F16, {})

    assert_eq(out.count("rgba16f"), 2, "Both bindings take the default when no override names either")


## A token outside any layout() is not something a kernel should write, but one
## that did compiled before this existed, and it still has to.
func test_a_token_outside_a_layout_still_takes_the_default() -> void:
    var out: String = Bindings.substitute("#define FMT SA_STORAGE_FORMAT\n", "rgba16f", {3: "r32f"})

    assert_eq(out, "#define FMT rgba16f\n", "The bare token takes the default qualifier")


## Two callers asking for the same formats must land on the same compiled
## variant, so the key is the qualifiers in binding order, not the dictionary.
func test_the_variant_key_is_the_qualifiers_in_binding_order() -> void:
    assert_eq(GlobalShaderCompiler.source.variant_key(F32), "rgba32f", "No overrides is the bare default")
    assert_eq(GlobalShaderCompiler.source.variant_key(F32, {3: R32}), "rgba32f;3=r32f", "One override is named with its binding")
    assert_eq(
        GlobalShaderCompiler.source.variant_key(F16, {5: R32, 3: F32}),
        GlobalShaderCompiler.source.variant_key(F16, {3: F32, 5: R32}),
        "and the order the caller wrote them in does not make a second variant"
    )


# ---------------------------------------------------------------------------
# The binding layout a preamble declares
# ---------------------------------------------------------------------------

const PREAMBLE := """
layout( SA_STORAGE_FORMAT, set = 0, binding = 0 ) uniform image2D canvas;
layout( set = 0, binding = 1 ) uniform sampler2D tip;
layout( std430, set = 0, binding = 2 ) readonly buffer Curve { float values[]; } curve;
layout( SA_STORAGE_FORMAT, set = 0, binding = 3 ) uniform readonly image2D mask;
layout( push_constant, std430 ) uniform Params { vec2 offset; float pad[2]; } p;
"""


## The preamble is what a module author writes, so the three kinds it may declare
## have to be read back from exactly that text, memory qualifiers included.
func test_the_three_binding_kinds_are_read_out_of_the_preamble() -> void:
    var layout: Dictionary = Bindings.extract_layout(PREAMBLE)

    assert_eq(layout.size(), 4, "Four bindings, and the push constant block is not one of them")
    assert_eq(layout[0]["kind"], "image", "A storage image")
    assert_eq(layout[0]["name"], "canvas", "named as declared")
    assert_eq(layout[1]["kind"], "sampler", "A sampled texture")
    assert_eq(layout[2]["kind"], "buffer", "A storage buffer")
    assert_eq(layout[2]["name"], "Curve", "named by its block")
    assert_eq(layout[3]["kind"], "image", "An image with a memory qualifier after uniform is still an image")


## Which bindings may take a format of their own is what the token records.
func test_the_layout_says_which_images_follow_the_document() -> void:
    var layout: Dictionary = Bindings.extract_layout(PREAMBLE + "layout( r32f, set = 0, binding = 4 ) uniform image2D fixed;\n")

    assert_eq(layout[0]["format"], "SA_STORAGE_FORMAT", "A token binding follows the document")
    assert_eq(layout[4]["format"], "r32f", "A literal one is the kernel's own choice")
    assert_eq(layout[1]["format"], "", "A sampler carries no qualifier at all")


func test_a_kernel_sara_ships_reports_its_bindings() -> void:
    var layout := GlobalShaderCompiler.binding_layout("composite")

    assert_eq(layout.size(), 2, "The composite kernels bind the canvas and one chunk")
    assert_eq(GlobalShaderCompiler.binding_kind("composite", 1), "image", "both as storage images")
    assert_eq(GlobalShaderCompiler.binding_kind("composite", 7), "", "and an undeclared binding reads as none")


# ---------------------------------------------------------------------------
# What a kernel can be handed: a sampler, a buffer, and an image at its own format
# ---------------------------------------------------------------------------

## One shader with every binding kind F10 added, written to user:// by the test
## and compiled from there, so no probe kernel ships in the tree or in the
## startup report. Every kernel shares the preamble, and a uniform set has to
## cover every binding the compiled kernel kept, so _probe() binds all five.
##
## This suite prints "OpArrayLength is not supported yet" several times. That is
## the engine's SPIR-V reflection meeting a storage buffer, printed whenever a
## kernel that declares one is created, cached SPIR-V or not, and sizing the
## arrays does not silence it.
const PROBE_NAME := "sa_bindings_probe"
static var scratch_probe_path: String = SaDataRoot.path("sa_bindings_probe.gmacs")
const PROBE_SOURCE := """
#kernel sample_probe
#kernel buffer_probe
#kernel vec3_probe
#kernel mask_probe

layout( SA_STORAGE_FORMAT, set = 0, binding = 0 ) uniform image2D target;
layout( set = 0, binding = 1 ) uniform sampler2D source;
layout( std430, set = 0, binding = 2 ) buffer Table { float values[8]; } table;
layout( SA_STORAGE_FORMAT, set = 0, binding = 3 ) uniform image2D mask;
layout( std430, set = 0, binding = 4 ) buffer Vec3Table { vec3 entries[4]; } vec3_table;

[numthreads( 8, 8, 1 )] void sample_probe() {
    ivec2 px = ivec2( gl_GlobalInvocationID.xy );
    ivec2 size = imageSize( target );
    if ( px.x >= size.x || px.y >= size.y ) return;
    vec2 uv = ( vec2( px ) + 0.5 ) / vec2( size );
    imageStore( target, px, texture( source, uv ) );
}

[numthreads( 64, 1, 1 )] void buffer_probe() {
    uint i = gl_GlobalInvocationID.x;
    if ( i >= 8 ) return;
    table.values[i] = table.values[i] * 2.0 + 1.0;
}

[numthreads( 64, 1, 1 )] void vec3_probe() {
    uint i = gl_GlobalInvocationID.x;
    if ( i >= 4 ) return;
    vec3_table.entries[i] = vec3( float( i ), float( i ) + 0.5, float( i ) + 0.25 );
}

[numthreads( 8, 8, 1 )] void mask_probe() {
    ivec2 px = ivec2( gl_GlobalInvocationID.xy );
    ivec2 size = imageSize( target );
    if ( px.x >= size.x || px.y >= size.y ) return;
    imageStore( target, px, vec4( imageLoad( mask, px ).r ) );
}
"""


## Compiles the probe once per run and returns a compute bound to every binding.
func _probe(target: SaTexture, source: SaTexture, table: SaCompute.Buffer, mask: SaTexture, vec3s: SaCompute.Buffer) -> SaCompute:
    if GlobalShaderCompiler.get_kernel_names(PROBE_NAME).is_empty():
        var file := FileAccess.open(scratch_probe_path, FileAccess.WRITE)
        file.store_string(PROBE_SOURCE)
        file.close()
        GlobalShaderCompiler.compile_compute_shader(scratch_probe_path)
    var compute := SaCompute.new(PROBE_NAME)
    compute.use_storage_format(target.format)
    compute.use_binding_format(3, mask.format)
    compute.set_texture(0, target.rid)
    compute.set_sampled_texture(1, source.rid)
    compute.set_buffer(2, table.rid)
    compute.set_texture(3, mask.rid)
    compute.set_buffer(4, vec3s.rid)
    return compute


## A 2 by 2 source with one colour per texel, so a read between them is telling.
func _four_texels() -> SaTexture:
    var source := SaTexture.new(Vector2i(2, 2), F32)
    var texels := PackedFloat32Array([1, 0, 0, 1, 0, 1, 0, 1, 0, 0, 1, 1, 0, 0, 0, 0])
    GlobalShaderCompiler.get_rd().texture_update(source.rid, 0, texels.to_byte_array())
    return source


func _floats(count: int, value: float = 0.0) -> SaCompute.Buffer:
    var data := PackedFloat32Array()
    data.resize(count)
    data.fill(value)
    return SaCompute.Buffer.new(data.to_byte_array())


func test_the_probe_declares_every_binding_kind() -> void:
    var target := SaTexture.new(Vector2i(1, 1), F32)
    var mask := SaTexture.new(Vector2i(1, 1), R32)
    var source := _four_texels()
    var table := _floats(8)
    var vec3s := _floats(16)
    var compute := _probe(target, source, table, mask, vec3s)
    assert_false(compute.pipelines.kernels.is_empty(), "The probe compiles")

    var layout := GlobalShaderCompiler.binding_layout(PROBE_NAME)
    assert_eq(layout.size(), 5, "and declares five bindings")
    assert_eq(GlobalShaderCompiler.binding_kind(PROBE_NAME, 1), "sampler", "one of them a sampler")
    assert_eq(GlobalShaderCompiler.binding_kind(PROBE_NAME, 2), "buffer", "one a buffer")


## The same probe, bound by the names its preamble writes rather than by the
## five slot numbers `_probe()` counts off. The kernel already names
## every binding, so nothing on this side should be counting.
func test_the_probe_binds_by_the_names_it_declares() -> void:
    var target := SaTexture.new(Vector2i(1, 1), F32)
    target.clear(Color(0, 0, 0, 0))
    var mask := SaTexture.new(Vector2i(1, 1), R32)
    var source := _four_texels()
    var table := _floats(8)
    var vec3s := _floats(16)
    var compute := _probe(target, source, table, mask, vec3s)

    compute.set_image("target", target.rid)
    compute.set_sampler("source", source.rid)
    compute.set_storage("table", table.rid)
    compute.set_image("mask", mask.rid)
    compute.set_storage("vec3_table", vec3s.rid)
    compute.dispatch_kernel("sample_probe", 1, 1, 1)

    var texel := _read_float(target)
    assert_almost_eq(texel[0], 0.25, 1e-4, "The by-name binds reach the same slots the numbers did")
    assert_almost_eq(texel[3], 0.75, 1e-4, "and the sampled alpha comes back the same way")


## A second probe, one image and a block of the shape half of Sara's kernels
## declare, so that `set_params()` is proved against a GPU rather than against
## the packer's own idea of the offsets. The shared probe above takes no push
## constant and giving it one would change every case that dispatches it.
const PARAMS_NAME := "sa_params_probe"
static var scratch_params_path: String = SaDataRoot.path("sa_params_probe.gmacs")
const PARAMS_SOURCE := """
#kernel params_probe

layout( SA_STORAGE_FORMAT, set = 0, binding = 0 ) uniform image2D target;
layout( push_constant, std430 ) uniform Params {
    vec2 origin;
    float opacity;
    float pad;
} params;

[numthreads( 8, 8, 1 )] void params_probe() {
    ivec2 px = ivec2( gl_GlobalInvocationID.xy );
    if ( px.x > 0 || px.y > 0 ) return;
    imageStore( target, px, vec4( params.origin.x, params.origin.y, params.opacity, params.pad ) );
}
"""


## The block is the one declaration and the caller hands over a Dictionary. What
## the GPU reads back at each of the four offsets is the only thing that proves
## the packer agreed with std430 rather than with itself.
func test_the_params_block_is_filled_by_the_names_it_declares() -> void:
    if GlobalShaderCompiler.get_kernel_names(PARAMS_NAME).is_empty():
        var file := FileAccess.open(scratch_params_path, FileAccess.WRITE)
        file.store_string(PARAMS_SOURCE)
        file.close()
        GlobalShaderCompiler.compile_compute_shader(scratch_params_path)
    var target := SaTexture.new(Vector2i(1, 1), F32)
    target.clear(Color(0, 0, 0, 0))
    var compute := SaCompute.new(PARAMS_NAME)
    compute.use_storage_format(target.format)

    compute.set_image("target", target.rid)
    compute.set_params({"origin": Vector2(3.0, 4.0), "opacity": 0.5, "pad": 0.25})
    compute.dispatch_kernel("params_probe", 1, 1, 1)

    var texel := _read_float(target)
    assert_almost_eq(texel[0], 3.0, 1e-5, "origin.x arrives where the block declares it")
    assert_almost_eq(texel[1], 4.0, 1e-5, "origin.y beside it")
    assert_almost_eq(texel[2], 0.5, 1e-5, "opacity after the vec2")
    assert_almost_eq(texel[3], 0.25, 1e-5, "and the pad the caller filled in last")


## A storage image is read by integer coordinate. A transform, a warp and a scaled
## brush tip all need the value between four texels, which only a sampler gives.
func test_a_sampled_texture_reads_between_four_texels() -> void:
    var target := SaTexture.new(Vector2i(1, 1), F32)
    target.clear(Color(0, 0, 0, 0))
    var mask := SaTexture.new(Vector2i(1, 1), R32)
    var source := _four_texels()
    var table := _floats(8)
    var vec3s := _floats(16)
    var compute := _probe(target, source, table, mask, vec3s)

    # A 1 by 1 target samples at (0.5, 0.5), the exact corner shared by all four.
    compute.dispatch_kernel("sample_probe", 1, 1, 1)

    var texel := _read_float(target)
    assert_almost_eq(texel[0], 0.25, 1e-4, "Red is a quarter, from the one red texel")
    assert_almost_eq(texel[1], 0.25, 1e-4, "green likewise")
    assert_almost_eq(texel[2], 0.25, 1e-4, "blue likewise")
    assert_almost_eq(texel[3], 0.75, 1e-4, "and alpha is three quarters, because one texel was transparent")


## The filter is the caller's to name. A lookup table wants exactly its texels.
func test_a_nearest_sampler_returns_the_texel_itself() -> void:
    var target := SaTexture.new(Vector2i(2, 2), F32)
    target.clear(Color(0, 0, 0, 0))
    var mask := SaTexture.new(Vector2i(2, 2), R32)
    var source := _four_texels()
    var table := _floats(8)
    var vec3s := _floats(16)
    var compute := _probe(target, source, table, mask, vec3s)
    compute.set_sampled_texture(1, source.rid, RenderingDevice.SAMPLER_FILTER_NEAREST)

    compute.dispatch_kernel("sample_probe", 1, 1, 1)

    assert_eq(_read_float(target, 0), [1.0, 0.0, 0.0, 1.0], "Texel one comes back whole")
    assert_eq(_read_float(target, 3), [0.0, 0.0, 0.0, 0.0], "and so does the transparent fourth")


## The push constant is closed at 128 bytes and the composite block spends all
## of them, so side data has nowhere else to go. Written, read back, and checked
## by value, because a padding mistake in std430 produces plausible numbers.
func test_a_buffer_round_trips_through_a_kernel() -> void:
    var target := SaTexture.new(Vector2i(1, 1), F32)
    var mask := SaTexture.new(Vector2i(1, 1), R32)
    var table := SaCompute.Buffer.new(PackedFloat32Array([1, 2, 3, 4, 5, 6, 7, 8]).to_byte_array())
    var source := _four_texels()
    var vec3s := _floats(16)
    var compute := _probe(target, source, table, mask, vec3s)

    compute.dispatch_kernel("buffer_probe", 1, 1, 1)

    var back := table.read().to_float32_array()
    assert_eq(back.size(), 8, "Every entry comes back")
    assert_eq(back, PackedFloat32Array([3, 5, 7, 9, 11, 13, 15, 17]), "each one doubled and incremented by the kernel")


## The trap the phase page names. A `vec3[]` under std430 has a stride of 16, so
## the twelve-byte packing a PackedFloat32Array produces reads every entry after
## the first from the wrong place. Pinned by reading what the GPU wrote.
func test_a_vec3_array_in_a_buffer_has_a_stride_of_sixteen() -> void:
    var target := SaTexture.new(Vector2i(1, 1), F32)
    var mask := SaTexture.new(Vector2i(1, 1), R32)
    var vec3s := _floats(16)
    var source := _four_texels()
    var table := _floats(8)
    var compute := _probe(target, source, table, mask, vec3s)

    compute.dispatch_kernel("vec3_probe", 1, 1, 1)

    var bytes := vec3s.read()
    assert_almost_eq(bytes.decode_float(16), 1.0, 1e-6, "Entry one starts sixteen bytes in, not twelve")
    assert_almost_eq(bytes.decode_float(20), 1.5, 1e-6, "with its y beside it")
    assert_almost_eq(bytes.decode_float(12), 0.0, 1e-6, "and the fourth float of entry zero is padding the kernel never wrote")
    assert_almost_eq(bytes.decode_float(48), 3.0, 1e-6, "so four entries fill sixteen floats")


## An update writes in place, so a uniform set built against the buffer stays
## valid and the next dispatch sees the new values.
func test_a_buffer_updates_in_place() -> void:
    var target := SaTexture.new(Vector2i(1, 1), F32)
    var mask := SaTexture.new(Vector2i(1, 1), R32)
    var table := _floats(8, 1.0)
    var source := _four_texels()
    var vec3s := _floats(16)
    var compute := _probe(target, source, table, mask, vec3s)

    table.update(PackedFloat32Array([10.0]).to_byte_array(), 8)
    compute.dispatch_kernel("buffer_probe", 1, 1, 1)

    assert_eq(
        table.read().to_float32_array(),
        PackedFloat32Array([3, 3, 21, 3, 3, 3, 3, 3]),
        "The third entry was replaced before the dispatch"
    )


## Item 3 of F10, and the blocker F6 recorded. A mask is one channel, and a kernel
## that inherits the canvas qualifier for it loads and stores undefined values
## across the whole image while returning plausible numbers.
func test_a_mask_binding_dispatches_at_its_own_format_beside_the_canvas() -> void:
    var target := SaTexture.new(Vector2i(8, 8), F32)
    target.clear(Color(0, 0, 0, 0))
    var mask := SaTexture.new(Vector2i(8, 8), R32)
    mask.clear(Color(0.75, 0, 0, 0))
    var source := _four_texels()
    var table := _floats(8)
    var vec3s := _floats(16)
    var compute := _probe(target, source, table, mask, vec3s)

    compute.dispatch_kernel("mask_probe", 1, 1, 1)

    assert_eq(_read_float(target, 0), [0.75, 0.75, 0.75, 0.75], "The kernel read the r32f mask through an r32f binding")
    assert_eq(_read_float(target, 63), [0.75, 0.75, 0.75, 0.75], "across the whole image")


func test_the_same_mask_serves_an_f16_canvas() -> void:
    var target := SaTexture.new(Vector2i(8, 8), F16)
    target.clear(Color(0, 0, 0, 0))
    var mask := SaTexture.new(Vector2i(8, 8), R32)
    mask.clear(Color(0.5, 0, 0, 0))
    var source := _four_texels()
    var table := _floats(8)
    var vec3s := _floats(16)
    var compute := _probe(target, source, table, mask, vec3s)

    compute.dispatch_kernel("mask_probe", 1, 1, 1)

    assert_eq(_read_half(target, 0), [0.5, 0.5, 0.5, 0.5], "rgba16f at the canvas and r32f at the mask, in one kernel")


func test_a_per_binding_format_is_its_own_variant() -> void:
    var target := SaTexture.new(Vector2i(1, 1), F32)
    var mask := SaTexture.new(Vector2i(1, 1), R32)
    var source := _four_texels()
    var table := _floats(8)
    var vec3s := _floats(16)
    var compute := _probe(target, source, table, mask, vec3s)
    var plain: Array = GlobalShaderCompiler.get_compute_kernel_compilations(PROBE_NAME, F32)
    var masked: Array = GlobalShaderCompiler.get_compute_kernel_compilations(PROBE_NAME, F32, {3: R32})

    assert_eq(masked.size(), plain.size(), "Both variants carry the same kernels")
    assert_true(masked[0] != plain[0], "as different shaders")
    assert_eq(compute.pipelines.shader_id, masked[0], "and the instance that asked for the mask format dispatches the masked one")

    var f32_pipeline: RID = compute.pipelines.kernels[0]
    compute.use_binding_format(3, R32)
    assert_eq(compute.pipelines.kernels[0], f32_pipeline, "Asking again for the same format changes nothing")
