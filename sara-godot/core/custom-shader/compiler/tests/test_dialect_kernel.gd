## One kernel written both ways: the spec's `blur_x` in the dialect and in the
## GLSL a hand would have written for it, compiled offscreen, and the SPIR-V
## bytes of the two compared.
##
## The sweep of Sara's own kernels, group S of this board, is to be proved "by
## identical SPIR-V bytes for every kernel before and after". This is that proof
## on one kernel, before twenty-five files depend on the transpiler: bytes rather
## than text, because the pass writes braces and a closing line where a hand
## would not, and nothing about brace placement reaches SPIR-V.
##
## Both kernels are written to `user://` by the test and compiled from there, the
## way `test_storage_formats.gd` writes its bindings probe, so no proof kernel
## ships in the tree or in the startup report.
##
## The comparison is the compile call rather than `sa_spirv_cache.gd`, which the
## unit was allowed either of. The cache is keyed on the exact final source, so
## two kernels that compile to the same text share one entry and comparing cache
## entries would compare a file with itself. Compiling each final source through
## the RenderingDevice gives two byte arrays that were made separately, and the
## cache is then used for the one thing it can prove: that the text this file
## assembled is the text the compiler handed glslang.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Dialect := preload("res://core/custom-shader/dialect/sa_dialect.gd")
const KernelSource := preload("res://core/custom-shader/dialect/sa_kernel_source.gd")
const Bindings := preload("res://core/custom-shader/compiler/sa_bindings.gd")

const F32 := RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT

## What the default storage format substitutes into an image's `layout()`. The
## qualifier rather than the format, because `SaBindings.substitute()` is static
## and takes the word, while the format-to-word map is the compiler's own.
## `test_the_compiler_compiled_the_source_the_bytes_came_from` is what proves
## this is the compiler's choice and not this file's guess.
const DEFAULT_QUALIFIER := "rgba32f"

const DIALECT_NAME := "sa_blur_x_dialect"
static var scratch_dialect_path: String = SaDataRoot.path("sa_blur_x_dialect.gmacs")
const GLSL_NAME := "sa_blur_x_glsl"
static var scratch_glsl_path: String = SaDataRoot.path("sa_blur_x_glsl.gmacs")

## The kernel both files declare, so the two shaders differ in their form and in
## nothing else.
const KERNEL := "blur_x"

## The spec's `blur_x`, with `gaussian` written into the file rather than
## imported.
##
## The import is a paste, and it happens after the dialect pass on both sides, so
## `import gaussian` and `#include "gaussian"` would splice the same GLSL into
## both final sources and prove nothing about the transpiler. It could not be
## read off disk here in any case: a library beside these two under `user://` is
## not in the index, because the shader walk turns back at the app's own user
## directory. The import's own proof is in
## `test_dialect.gd`, where the directive becomes the include the paste reads.
const DIALECT_SOURCE := """kernel blur_x

image src: readonly
image dst

params:
    float sigma
    int radius


def gaussian(float x, float sigma) -> float:
    return exp(-0.5 * x * x / (sigma * sigma))


@workgroup_size(8, 8)
def blur_x():
    vec4 sum = vec4(0.0)
    float weight = 0.0
    for i in range(-radius, radius + 1):
        float w = gaussian(float(i), sigma)
        sum += w * src[pixel + ivec2(i, 0)]
        weight += w
    dst[pixel] = sum / weight
"""

## The same kernel written in GLSL, the form the compiler still reads.
##
## Nothing under `shaders/compute/` is written this way, so the pair is
## a fixture: the point of it is that the dialect above and the GLSL here reach
## the same module, which is what the whole sweep was proved on.
##
## Three of its lines are written to match the dialect rather than to read best,
## and each one is a name the sweep has to carry across unchanged, because a
## SPIR-V module carries `OpName` for every local and every struct member:
## `pixel` is what the pass declares on the signature line, `_pad_0` and `_pad_1`
## are what it writes to close a block of eight bytes, and `i < radius + 1` is
## what `range(-radius, radius + 1)` means rather than the `i <= radius` a hand
## would reach for. `test_a_renamed_local_is_a_different_module` is the case that
## holds each of those to being a real constraint and not a preference. The
## fourth is the edge check the dialect writes for a kernel that leaves
## its own out, which the GLSL form writes by hand under the signature.
const GLSL_SOURCE := """#kernel blur_x

layout( SA_STORAGE_FORMAT, set = 0, binding = 0 ) uniform readonly image2D src;
layout( SA_STORAGE_FORMAT, set = 0, binding = 1 ) uniform image2D dst;

layout( push_constant, std430 ) uniform Params {
    float sigma;
    int radius;
    float _pad_0;
    float _pad_1;
};

float gaussian(float x, float sigma) {
    return exp(-0.5 * x * x / (sigma * sigma));
}

[numthreads( 8, 8, 1 )] void blur_x() {
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
    ivec2 sa_edge_at = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(sa_edge_at, imageSize(dst)))) return;
    vec4 sum = vec4(0.0);
    float weight = 0.0;
    for (int i = -radius; i < radius + 1; i++) {
        float w = gaussian(float(i), sigma);
        sum += w * imageLoad(src, pixel + ivec2(i, 0));
        weight += w;
    }
    imageStore(dst, pixel, sum / weight);
}
"""

## The image the dispatch runs over, one workgroup exactly, so no invocation
## reads or writes outside it and the case says nothing about what happens if
## one did.
const SIZE := Vector2i(8, 8)

## The column the source is lit in, far enough from either edge that the blur
## over it and its two neighbours never reaches a texel the kernel did not read.
const LIT_COLUMN: int = 4


## The text glslang is handed for *raw_text*, whichever form it is written in.
##
## The four steps `compile_compute_shader` takes over a file with no include in
## it, in its order: the dialect pass, the comments out, the storage token
## substituted, the kernel's signature rewritten into `main`, and the preamble
## put on top.
func _final_source(raw_text: String) -> String:
    var clean := KernelSource.remove_comments(Dialect.to_glsl(raw_text))
    clean = Bindings.substitute(clean, DEFAULT_QUALIFIER, {})
    var code := KernelSource.replace_kernel_signature(KERNEL, clean)
    return KernelSource.assemble_glsl(KernelSource.extract_numthreads(KERNEL, clean), code)


## The SPIR-V of *raw_text*, compiled on its own rather than read from the cache,
## so the two arrays a case compares were produced by two separate calls.
func _spirv(raw_text: String) -> PackedByteArray:
    var source := RDShaderSource.new()
    source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
    source.source_compute = _final_source(raw_text)
    var spirv := GlobalShaderCompiler.get_rd().shader_compile_spirv_from_source(source)
    assert_eq(spirv.compile_error_compute, "", "glslang read the source this file assembled")
    return spirv.bytecode_compute


## Writes *raw_text* to *path* and compiles it, once per run.
func _compiled(written_name: String, path: String, raw_text: String) -> void:
    if not GlobalShaderCompiler.get_kernel_names(written_name).is_empty():
        return
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(raw_text)
    file.close()
    GlobalShaderCompiler.compile_compute_shader(path)


## A source image that is black everywhere but one column, which a blur along x
## spreads into its two neighbours and nowhere else.
func _lit_column() -> SaTexture:
    var texels := PackedFloat32Array()
    texels.resize(SIZE.x * SIZE.y * 4)
    texels.fill(0.0)
    for y in SIZE.y:
        for channel in 4:
            texels[(y * SIZE.x + LIT_COLUMN) * 4 + channel] = 1.0
    var source := SaTexture.new(SIZE, F32)
    GlobalShaderCompiler.get_rd().texture_update(source.rid, 0, texels.to_byte_array())
    return source


## The red channel of one texel of *texture*.
func _red(texture: SaTexture, at: Vector2i) -> float:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return bytes.decode_float((at.y * SIZE.x + at.x) * 16)


# --- The bytes ------------------------------------------------------------------


## What the unit is for. The same kernel, written twice, compiled twice, and the
## modules compared byte for byte.
func test_one_kernel_written_both_ways_compiles_to_the_same_bytes() -> void:
    var from_dialect := _spirv(DIALECT_SOURCE)
    var from_glsl := _spirv(GLSL_SOURCE)

    assert_false(from_dialect.is_empty(), "The dialect form compiled to a module")
    assert_eq(from_dialect.size(), 2800, "One `blur_x` is 2800 bytes of SPIR-V, the record's 2536 and the edge check writes")
    assert_true(from_dialect == from_glsl, "and the GLSL a hand would have written compiles to the same bytes")


## Why the case above pins three names rather than reading well. A SPIR-V module
## carries `OpName` for every local and every struct member, so a conversion that
## renames one is a different module even when it is the same program. Each of
## the three is broken on its own here, because it says what "identical bytes"
## can and cannot be asked to mean: the sweep's own arbiter is the SPIR-V manifest,
## which hashes the module with the nine debug opcodes stripped out beside the
## hash of the whole thing, and this case is the measurement that entry earns its
## place with.
func test_a_renamed_local_is_a_different_module() -> void:
    var from_dialect := _spirv(DIALECT_SOURCE)

    var renamed_pixel := GLSL_SOURCE.replace("pixel", "at")
    var renamed_pads := GLSL_SOURCE.replace("_pad_0", "pad_a").replace("_pad_1", "pad_b")
    var widened_range := GLSL_SOURCE.replace("i < radius + 1", "i <= radius")

    assert_false(from_dialect == _spirv(renamed_pixel), "The declared pixel is a name in the module, not only in the file")
    assert_false(from_dialect == _spirv(renamed_pads), "So is every member of the params block, the pads the pass wrote included")
    assert_false(
        from_dialect == _spirv(widened_range), "And a loop that counts the same texels a different way is different code"
    )


## That the text this file assembles is the text the compiler compiles, which is
## what makes the comparison above a statement about the compiler rather than
## about this file's own idea of the pipeline.
##
## The SPIR-V cache is keyed on the exact source glslang was handed, so an entry
## under the key of this file's final source is the compiler saying it handed
## glslang the same string. It is the one thing the cache can prove that the
## compile call cannot.
func test_the_compiler_compiled_the_source_the_bytes_came_from() -> void:
    _compiled(DIALECT_NAME, scratch_dialect_path, DIALECT_SOURCE)
    _compiled(GLSL_NAME, scratch_glsl_path, GLSL_SOURCE)

    assert_eq(
        GlobalShaderCompiler.get_kernel_names(DIALECT_NAME), [KERNEL], "The dialect file compiled as a shader with one kernel"
    )
    assert_eq(GlobalShaderCompiler.get_kernel_names(GLSL_NAME), [KERNEL], "and so did the GLSL one")
    for raw_text: String in [DIALECT_SOURCE, GLSL_SOURCE]:
        var key := SaSpirvCache.key_for(_final_source(raw_text))
        assert_true(FileAccess.file_exists(SaSpirvCache.path_for(key)), "The compiler cached SPIR-V under this exact source")


# --- The run --------------------------------------------------------------------


## The other half of the unit: the dialect kernel dispatched through `SaCompute`,
## every binding and every field named rather than numbered, and the pixels it
## wrote read back once.
##
## Bytes equal to a hand-written kernel's say the program is right. They say
## nothing about whether the declarations the pass wrote are the ones GDScript
## can reach, because the names live in the `layout()` lines the pass produced
## and a wrong one is a bind that never lands.
func test_the_dialect_kernel_runs_bound_by_the_names_it_declares() -> void:
    _compiled(DIALECT_NAME, scratch_dialect_path, DIALECT_SOURCE)
    var source := _lit_column()
    var target := SaTexture.new(SIZE, F32)
    target.clear(Color(0, 0, 0, 0))

    var compute := SaCompute.new(DIALECT_NAME)
    compute.use_storage_format(F32)
    compute.set_image("src", source.rid)
    compute.set_image("dst", target.rid)
    compute.set_params({"sigma": 1.0, "radius": 1})
    compute.dispatch_kernel(KERNEL, 1, 1, 1)

    # exp(-0.5) either side of a 1.0 in the middle, over their own total.
    var side := exp(-0.5)
    var total := 1.0 + 2.0 * side
    assert_almost_eq(
        _red(target, Vector2i(LIT_COLUMN, 0)), 1.0 / total, 1e-5, "The lit column keeps its own weight over the total"
    )
    assert_almost_eq(_red(target, Vector2i(LIT_COLUMN - 1, 3)), side / total, 1e-5, "and each neighbour takes one Gaussian tail")
    assert_almost_eq(_red(target, Vector2i(LIT_COLUMN + 1, 7)), side / total, 1e-5, "on both sides and on every row")
    assert_almost_eq(_red(target, Vector2i(0, 0)), 0.0, 1e-5, "while a column the blur never reached stays black")
