## An image reads and writes with brackets beside `image_load` and
## `image_store`.
##
## `src[at]` reads a declared image and `dst[at] = c` writes one, and both ways
## of a kernel come out of the dialect as the same GLSL, a compound assignment
## included. A bracket on anything else is GLSL's array and stays one.
extends "res://tests/test_framework.gd"

## The compile proof hands the bracket kernel to glslang, which needs one.
const REQUIRES_GPU := true

const Dialect := preload("res://core/custom-shader/dialect/sa_dialect.gd")
const KernelSource := preload("res://core/custom-shader/dialect/sa_kernel_source.gd")
const Bindings := preload("res://core/custom-shader/compiler/sa_bindings.gd")

## A kernel written the old way, each image call spelt out. The compound
## assignment's own spelling is the store of the load with the value in
## parentheses, which is what the bracket form means.
const OLD_WAY := """kernel tint

image src: readonly
image dst
image sum: r32f

params:
    float amount
    vec2 origin


def tint():
    ivec2 at = pixel + ivec2(origin)
    float weights[3] = float[](0.25, 0.5, 0.25)
    vec4 total = image_load(src, at) * weights[1]
    if image_load(src, at).a > 0.0:
        total += image_load(src, image_load(sum, at).r > 0.5 ? at : at + ivec2(1, 0))
    if amount > 1.0: image_store(sum, at, image_load(sum, at) + (vec4(weights[0])))
    image_store(dst, at, total * amount)
    image_store(sum, at, image_load(sum, at) * (amount + 1.0))
    image_store(sum, at, image_load(sum, at) + (image_load(src, at)))
"""

## The same kernel with brackets.
const NEW_WAY := """kernel tint

image src: readonly
image dst
image sum: r32f

params:
    float amount
    vec2 origin


def tint():
    ivec2 at = pixel + ivec2(origin)
    float weights[3] = float[](0.25, 0.5, 0.25)
    vec4 total = src[at] * weights[1]
    if src[at].a > 0.0:
        total += src[sum[at].r > 0.5 ? at : at + ivec2(1, 0)]
    if amount > 1.0: sum[at] += vec4(weights[0])
    dst[at] = total * amount
    sum[ at ] *= amount + 1.0
    sum[at] += src[at]
"""

## A kernel that writes only with brackets and leaves its edge check out.
const UNCHECKED := """kernel copy

image src: readonly
image spare
image dst


def copy():
    spare[pixel] = src[pixel]
"""

## A store to one channel of a texel, which GLSL has no call for.
const ONE_CHANNEL := """kernel red

image dst


def red():
    dst[pixel].r = 1.0
"""


func test_both_ways_give_the_same_glsl() -> void:
    var old_glsl := Dialect.transpile(OLD_WAY)
    var new_glsl := Dialect.transpile(NEW_WAY)

    var old_lines := old_glsl.split("\n")
    var new_lines := new_glsl.split("\n")
    assert_eq(new_lines.size(), NEW_WAY.split("\n").size(), "The count of lines holds")
    for i in old_lines.size():
        assert_eq(new_lines[i], old_lines[i], "Line %d is the same GLSL both ways" % (i + 1))


func test_a_read_and_a_store_become_the_calls() -> void:
    var glsl := Dialect.transpile(NEW_WAY)

    assert_true(glsl.contains("vec4 total = imageLoad(src, at) * weights[1];"), "A bracket on src reads it")
    assert_true(glsl.contains("imageStore(dst, at, total * amount);"), "An assignment to dst stores to it")
    assert_true(glsl.contains("if (imageLoad(src, at).a > 0.0) {"), "A header reads with brackets too")
    assert_true(
        glsl.contains("imageLoad(src, imageLoad(sum, at).r > 0.5 ? at : at + ivec2(1, 0))"),
        "An index holding a bracket of its own is read inside out"
    )


func test_a_compound_assignment_reads_and_writes_the_same_texel() -> void:
    var glsl := Dialect.transpile(NEW_WAY)

    assert_true(
        glsl.contains("imageStore(sum, at, imageLoad(sum, at) * (amount + 1.0));"), "`*=` multiplies the texel by the whole value"
    )
    assert_true(
        glsl.contains("if (amount > 1.0) { imageStore(sum, at, imageLoad(sum, at) + (vec4(weights[0]))); }"),
        "And a one-line body after a colon stores the same way"
    )


func test_an_arrays_bracket_is_left_to_glsl() -> void:
    var glsl := Dialect.transpile(NEW_WAY)

    assert_true(glsl.contains("float weights[3] = float[](0.25, 0.5, 0.25);"), "An array's declaration is untouched")
    assert_true(glsl.contains("* weights[1];"), "And so is a read of it")
    assert_false(glsl.contains("imageLoad(weights"), "A name that is no declared image is never read as one")


func test_a_bracket_store_names_the_image_the_edge_check_guards() -> void:
    var glsl := Dialect.transpile(UNCHECKED)

    assert_true(
        glsl.contains("if (any(greaterThanEqual(sa_edge_at, imageSize(spare)))) return;"),
        "The check is against spare, the image the bracket stores to, not dst, the last writable one"
    )


func test_a_store_to_one_channel_is_refused_in_words() -> void:
    var glsl := Dialect.transpile(ONE_CHANNEL)

    assert_true(glsl.contains("#error SaDialect: a store to one channel of dst"), "The part store is refused: %s" % glsl)


func test_the_bracket_kernel_compiles() -> void:
    var glsl := KernelSource.remove_comments(Dialect.to_glsl(NEW_WAY))
    var pasted := GlobalShaderCompiler.source.process_includes(glsl, "probe.gmacs")
    var clean := Bindings.substitute(pasted, "rgba32f", {})
    var assembled := KernelSource.assemble_glsl(
        KernelSource.extract_numthreads("tint", clean), KernelSource.replace_kernel_signature("tint", clean)
    )
    var source := RDShaderSource.new()
    source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
    source.source_compute = assembled

    var spirv := RenderingServer.get_rendering_device().shader_compile_spirv_from_source(source, false)

    assert_eq(spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE), "", "glslang reads the bracket kernel")
