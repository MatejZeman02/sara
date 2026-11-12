## The harness of a neighbourhood kernel is a library:
## `shaders/compute/libs/neighbourhood.gmacs` holds the read, the sample and the
## finish, the kaleidoscope's kernel keeps only its fold, and the base module's
## neighbourhood kernels import it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **A probe of this suite's own, under `user://`**, the shape
## `test_workgroup_size.gd` established, so no probe kernel ships in the tree.
## It imports the library as a module's kernel would and stores what each of
## its functions answers over a source two texels wide: opaque red, and a blue
## whose alpha is nought. A straight bilinear read or a straight blend would
## drag that blue in, and the library's premultiplied ones must not.
## `scenarios/the-kernels-harness-is-a-library.json` shoots the
## kaleidoscope and every moved base filter against the same scenario run on
## the integration branch before the row.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const PROBE_NAME := "sa_l12_probe"
static var scratch_probe_path: String = SaDataRoot.path("sa_l12_probe.gmacs")
const PROBE_SOURCE := """kernel l12_sample
kernel l12_read
kernel l12_finish
kernel l12_finish_premultiplied

image src: readonly
image mask: r32f, readonly
image dst

params:
    int halo
    vec2 origin

import neighbourhood


def l12_sample():
    ivec2 at = pixel + ivec2(origin)
    image_store(dst, at, sa_straight(sa_sample(vec2(at) + vec2(0.5, 0.0))))


def l12_read():
    ivec2 at = pixel + ivec2(origin)
    image_store(dst, at, sa_straight(sa_read(at + ivec2(1, 0))))


def l12_finish():
    ivec2 at = pixel + ivec2(origin)
    sa_finish(at, sa_kept(at), vec4(0.0, 1.0, 0.0, 1.0))


def l12_finish_premultiplied():
    ivec2 at = pixel + ivec2(origin)
    sa_finish_premultiplied(at, sa_read(at + ivec2(halo, halo)), vec4(0.0, 1.0, 0.0, 1.0))
"""

const RED := Color(1.0, 0.0, 0.0, 1.0)
const CLEAR_BLUE := Color(0.0, 0.0, 1.0, 0.0)
const TWO := Vector2i(2, 1)

## The kernels that moved onto the library, each with the one function it
## calls that says the move happened.
const MOVED := {
    "res://modules/sara-base-modules/kaleidoscope/kaleidoscope.gmacs": "sa_finish_premultiplied(",
    "res://modules/sara-base-modules/base/shaders/motion_blur.gmacs": "sa_sample(",
    "res://modules/sara-base-modules/base/shaders/gaussian_blur.gmacs": "sa_finish(",
    "res://modules/sara-base-modules/base/shaders/lens_blur.gmacs": "sa_finish(",
    "res://modules/sara-base-modules/base/shaders/sharpen.gmacs": "sa_finish(",
    "res://modules/sara-base-modules/base/shaders/denoise.gmacs": "sa_finish_premultiplied(",
    "res://modules/sara-base-modules/base/shaders/add_noise.gmacs": "sa_finish(",
    "res://modules/sara-base-modules/base/shaders/edge_detection.gmacs": "sa_finish(",
    "res://modules/sara-base-modules/base/shaders/bump_map.gmacs": "sa_finish(",
    "res://modules/sara-base-modules/base/shaders/normal_map.gmacs": "sa_finish(",
    "res://modules/sara-base-modules/base/shaders/wrap_offset.gmacs": "sa_finish(",
}


func after_each() -> void:
    if FileAccess.file_exists(scratch_probe_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_probe_path))


func _compiled() -> void:
    if GlobalShaderCompiler.get_kernel_names(PROBE_NAME).is_empty():
        var file := FileAccess.open(scratch_probe_path, FileAccess.WRITE)
        file.store_string(PROBE_SOURCE)
        file.close()
        GlobalShaderCompiler.compile_compute_shader(scratch_probe_path)


func _upload(texture: SaTexture, values: PackedFloat32Array) -> void:
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, values.to_byte_array())


## The source: opaque red at x 0, transparent blue at x 1.
func _source() -> SaTexture:
    var texture := SaTexture.new(TWO)
    _upload(texture, PackedFloat32Array([RED.r, RED.g, RED.b, RED.a, CLEAR_BLUE.r, CLEAR_BLUE.g, CLEAR_BLUE.b, CLEAR_BLUE.a]))
    return texture


## A mask of one texel at half, smaller than the target, so every read of it
## past its size lands on its last texel.
func _half_mask() -> SaTexture:
    var texture := SaTexture.new(Vector2i.ONE, RenderingDevice.DATA_FORMAT_R32_SFLOAT)
    _upload(texture, PackedFloat32Array([0.5]))
    return texture


## What *kernel_name* stores at the two texels.
func _run(kernel_name: String) -> Array[Color]:
    _compiled()
    var target := SaTexture.new(TWO)
    target.clear(Color(9.0, 9.0, 9.0, 9.0))
    var compute := SaCompute.new(PROBE_NAME)
    var bindings := {"src": _source(), "mask": _half_mask(), "dst": target}
    compute.run(kernel_name, bindings, {"halo": 0, "origin": Vector2.ZERO}, Rect2i(Vector2i.ZERO, TWO))
    var image := SaExport.get_texture_image_float(target)
    return [image.get_pixel(0, 0), image.get_pixel(1, 0)]


func _assert_colour(got: Color, wanted: Color, what: String) -> void:
    for channel: int in 4:
        assert_almost_eq(got[channel], wanted[channel], 1e-5, "%s, %s against %s" % [what, got, wanted])


func test_the_probe_compiles_against_the_library() -> void:
    _compiled()

    var names := GlobalShaderCompiler.get_kernel_names(PROBE_NAME)
    assert_eq(names.size(), 4, "A kernel that imports the library compiles, all four entries of it")


## Halfway between the red and the clear blue, premultiplied, is red at half
## alpha, and none of the blue a straight read would have mixed in. Past the
## source's edge the read is transparent.
func test_the_sample_is_bilinear_on_premultiplied_colour() -> void:
    var got := _run("l12_sample")

    _assert_colour(got[0], Color(1.0, 0.0, 0.0, 0.5), "Between red and clear blue the sample is red at half alpha")
    _assert_colour(got[1], Color(0.0, 0.0, 0.0, 0.0), "and between clear blue and past the edge it is transparent")


func test_the_read_is_transparent_past_the_source() -> void:
    var got := _run("l12_read")

    _assert_colour(got[0], Color(0.0, 0.0, 0.0, 0.0), "A texel of alpha nought reads as transparent black")
    _assert_colour(got[1], Color(0.0, 0.0, 0.0, 0.0), "and so does one past the source")


## The straight finish blends the colours as they are stored, the blend every
## base filter that works straight wrote for itself.
func test_the_finish_blends_straight_colour_by_the_mask() -> void:
    var got := _run("l12_finish")

    _assert_colour(got[0], Color(0.5, 0.5, 0.0, 1.0), "Half the mask over opaque red is half red, half green")
    _assert_colour(got[1], Color(0.0, 0.5, 0.5, 0.5), "and over clear blue it keeps half the blue")


## The premultiplied finish is the kaleidoscope's and the denoise's: a colour
## of alpha nought weighs nothing, so the clear blue does not tint the green.
func test_the_premultiplied_finish_does_not_tint_by_a_transparent_colour() -> void:
    var got := _run("l12_finish_premultiplied")

    _assert_colour(got[0], Color(0.5, 0.5, 0.0, 1.0), "Over opaque red the two finishes agree")
    _assert_colour(got[1], Color(0.0, 1.0, 0.0, 0.5), "and over clear blue this one is green at half alpha")


func test_every_moved_kernel_imports_the_library() -> void:
    for path: String in MOVED:
        # A checkout with `core.autocrlf`, the default of Git for Windows, ends
        # each line with a carriage return as well.
        var text := FileAccess.get_file_as_string(path).replace("\r\n", "\n")
        assert_true(text.contains("\nimport neighbourhood\n"), "%s imports the library" % path.get_file())
        assert_true(text.contains(String(MOVED[path])), "%s calls %s" % [path.get_file(), MOVED[path]])


## The kaleidoscope's kernel keeps its effect: the only `image_load` and
## `image_store` it had were the harness, so it names neither now.
func test_the_kaleidoscope_kernel_keeps_only_its_fold() -> void:
    var text := FileAccess.get_file_as_string("res://modules/sara-base-modules/kaleidoscope/kaleidoscope.gmacs")

    assert_true(text.contains("def folded("), "The fold stays in the kaleidoscope")
    assert_false(text.contains("image_load("), "and it reads the layer through the library only")
    assert_false(text.contains("image_store("), "and writes it through the library's finish")
