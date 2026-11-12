## A kernel that leaves its edge check out gets one.
##
## The GPU runs threads in groups of 8 by 8, so a dispatch over an image whose
## side is no multiple of 8 has threads past its edge. The dialect writes the
## check onto the kernel's signature line, as an early return where nothing
## waits at a `barrier()` and as a guard on each store where something does,
## and leaves a kernel that writes its own alone. The barrier case goes through
## the include paste, because that is where `sa_edge_check.gd` swaps the return
## for the guards, the barrier being in a library as often as not.
extends "res://tests/test_framework.gd"

## The paste lives on the autoload and the compile proof needs glslang.
const REQUIRES_GPU := true

const Dialect := preload("res://core/custom-shader/dialect/sa_dialect.gd")
const KernelSource := preload("res://core/custom-shader/dialect/sa_kernel_source.gd")
const Bindings := preload("res://core/custom-shader/compiler/sa_bindings.gd")

## The library a case registers, the Gaussian's shape: a walk that waits at a
## barrier and a finish that stores.
const WALK_LIBRARY := "walk"

## A filter's kernel with no check, storing through nothing but its own body.
const PLAIN := """kernel tint

image src: readonly
image dst

params:
    float amount


def tint():
    image_store(dst, pixel, image_load(src, pixel) * amount)
"""

## The box blur's shape: an `origin` in its params and its store in a library.
const AT_ORIGIN := """kernel blur

image src: readonly
image mask: r32f, readonly
image dst

params:
    int radius
    vec2 origin

import neighbourhood


def blur():
    ivec2 at = pixel + ivec2(origin)
    sa_finish(at, sa_kept(at), image_load(src, at))
"""

## The box blur as it is written today, its check by hand.
const HAND_CHECKED := """kernel blur

image src: readonly
image dst

params:
    vec2 origin


def blur():
    ivec2 at = pixel + ivec2(origin)
    if at.x >= image_size(dst).x or at.y >= image_size(dst).y:
        return
    image_store(dst, at, image_load(src, at))
"""

## A kernel that waits at a barrier in its own body.
const WAITS := """kernel shared_sum

image src: readonly
image dst


def shared_sum():
    vec4 here = image_load(src, pixel)
    barrier()
    image_store(dst, pixel, here * 2.0)
"""

## A kernel whose barrier and store are both in a library it imports.
const WAITS_IN_LIBRARY := """kernel walked

image src: readonly
image dst

import walk


def walked():
    vec4 got = walk(pixel)
    finish(pixel, got)
"""

## The library *WAITS_IN_LIBRARY* imports, GLSL as a library is after its own
## pass.
const WALK_GLSL := """shared vec4 tile[64];
vec4 walk(ivec2 at) {
    tile[gl_LocalInvocationIndex] = imageLoad(src, min(at, imageSize(src) - 1));
    barrier();
    return tile[gl_LocalInvocationIndex];
}
void finish(ivec2 at, vec4 value) {
    imageStore(dst, at, value);
}
"""

## Two kernels in one file with a barrier: one checks for itself, one leaves
## the check out and stores through nothing the first calls.
const SIBLINGS := """kernel checked, waiting

image src: readonly
image dst

buffer sums: float values[]


def checked():
    if pixel.x >= image_size(dst).x or pixel.y >= image_size(dst).y:
        return
    image_store(dst, pixel, image_load(src, pixel))


def waiting():
    sums.values[gl_LocalInvocationIndex] = 1.0
    barrier()
"""


func after_each() -> void:
    GlobalShaderCompiler.clear_virtual_include(WALK_LIBRARY)


## *source* through the dialect and the paste, the way the compiler reads it.
func _pasted(source: String) -> String:
    var glsl := KernelSource.remove_comments(Dialect.to_glsl(source))
    return GlobalShaderCompiler.source.process_includes(glsl, "probe.gmacs")


## The line of *glsl* that opens the function *name*.
func _signature_line(glsl: String, name: String) -> String:
    for line in glsl.split("\n"):
        if line.contains("void %s(" % name):
            return line
    return ""


func test_a_kernel_with_no_check_returns_early_past_the_image_it_stores_to() -> void:
    var glsl := Dialect.transpile(PLAIN)

    var line := _signature_line(glsl, "tint")
    assert_true(
        line.contains("if (any(greaterThanEqual(sa_edge_at, imageSize(dst)))) return;"),
        "The kernel's signature line returns past the edge of dst: %s" % line
    )
    assert_true(line.contains("sa_edge_at = ivec2(gl_GlobalInvocationID.xy);"), "Its texel is the thread's own")
    assert_eq(glsl.split("\n").size(), PLAIN.split("\n").size(), "And the count of lines holds")


func test_a_kernel_with_an_origin_checks_the_texel_it_writes() -> void:
    var line := _signature_line(Dialect.transpile(AT_ORIGIN), "blur")

    assert_true(
        line.contains("sa_edge_at = ivec2(gl_GlobalInvocationID.xy) + ivec2(origin);"),
        "A kernel handed an origin is checked at pixel plus origin, where it reads and writes: %s" % line
    )
    assert_true(
        line.contains("imageSize(dst)"), "And against dst, the last image it declares writable, its store being in a library"
    )


func test_a_hand_written_check_is_left_alone_with_no_second_one() -> void:
    var glsl := Dialect.transpile(HAND_CHECKED)

    assert_false(glsl.contains("sa_edge_at"), "A kernel that writes its own check gets no second one")
    assert_eq(glsl.count("return;"), 1, "And its own return is the only one")


func test_a_kernel_that_waits_at_a_barrier_guards_its_store_instead() -> void:
    var glsl := _pasted(WAITS)

    assert_false(glsl.contains("return;"), "No thread returns before the barrier every thread has to reach")
    assert_true(
        glsl.contains("{ if (all(lessThan(pixel, imageSize(dst)))) imageStore(dst, pixel, here * 2.0); }"),
        "The store is guarded by its own texel: %s" % _signature_line(glsl, "shared_sum")
    )


func test_a_barrier_and_a_store_in_a_library_are_found_after_the_paste() -> void:
    GlobalShaderCompiler.set_virtual_include(WALK_LIBRARY, WALK_GLSL)

    var glsl := _pasted(WAITS_IN_LIBRARY)

    assert_false(glsl.contains("sa_edge_at"), "The early return is gone once the pasted walk waits at a barrier")
    assert_true(
        glsl.contains("{ if (all(lessThan(at, imageSize(dst)))) imageStore(dst, at, value); }"),
        "And the library's store the kernel calls is the one guarded"
    )


func test_a_sibling_that_checks_for_itself_keeps_its_store_bare() -> void:
    var glsl := _pasted(SIBLINGS)

    assert_true(
        glsl.contains("imageStore(dst, pixel, imageLoad(src, pixel));"),
        "The kernel with its own check keeps its store as written"
    )
    assert_false(glsl.contains("lessThan("), "And nothing the waiting kernel reaches stores to dst, so nothing is guarded")
    assert_false(glsl.contains("sa_edge_at"), "While the waiting kernel's early return is taken out")


## The two forms the check takes, handed to glslang: the early return and the
## guarded store, each in a kernel the front end turns into `main`.
func test_both_forms_compile() -> void:
    for pair: Array in [[PLAIN, "tint"], [WAITS, "shared_sum"]]:
        var clean := Bindings.substitute(_pasted(pair[0]), "rgba32f", {})
        var assembled := KernelSource.assemble_glsl(
            KernelSource.extract_numthreads(pair[1], clean), KernelSource.replace_kernel_signature(pair[1], clean)
        )
        var source := RDShaderSource.new()
        source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
        source.source_compute = assembled

        var spirv := RenderingServer.get_rendering_device().shader_compile_spirv_from_source(source, false)

        assert_eq(spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE), "", "glslang reads %s" % pair[1])
