## The revised CAM16 of `shaders/compute/libs/cam16_hellwig.gmacs`, read on
## the GPU for a handful of colours and held to what the papers' equations
## give in double precision: J, C, h and the Helmholtz-Kohlrausch J_HK within
## 1e-4, and the inverse giving each colour back within 1e-5.
##
## The fixtures are printed by `scripts/cam16_hellwig_fixtures.py`, which
## writes the papers' equations out on its own and agrees with colour-science's
## `hellwig2022` to 2e-9 under `--compare`. The probe is written to `user://`
## and compiled from there, as the lattice hash's suite does, and imports the
## library by name.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const F32 := RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT

const PROBE_NAME := "sa_cam16_hellwig_probe"
static var scratch_probe_path: String = SaDataRoot.path("sa_cam16_hellwig_probe.gmacs")

const PROBE_SOURCE := """kernel cam16_read, cam16_round_trip

image src: rgba32f, readonly
image dst

import cam16_hellwig


def cam16_read():
    vec3 jch = sa_cam16_from_linear_srgb(image_load(src, pixel).rgb)
    image_store(dst, pixel, vec4(jch, sa_cam16_lightness_hk(jch)))


def cam16_round_trip():
    vec3 jch = sa_cam16_from_linear_srgb(image_load(src, pixel).rgb)
    vec3 back = sa_cam16_with_lightness_hk(sa_cam16_lightness_hk(jch), jch.y, jch.z)
    image_store(dst, pixel, vec4(sa_cam16_to_linear_srgb(back), 1.0))
"""

## Name, linear sRGB, then J, C, h in radians and J_HK, as the script prints them.
const FIXTURES := {
    "grey": [Vector3(0.18, 0.18, 0.18), 39.06855349, 0.00000000, 3.14159265, 39.06855350],
    "red": [Vector3(0.6, 0.06, 0.05), 40.56588672, 39.38088977, 0.41276024, 46.01918719],
    "yellow": [Vector3(0.5, 0.42, 0.03), 60.90144790, 28.78039495, 1.79413749, 62.90556604],
    "cyan": [Vector3(0.03, 0.32, 0.38), 46.92421811, 21.84376445, 3.62411741, 54.64115873],
    "blue": [Vector3(0.05, 0.08, 0.6), 30.61434306, 51.49306387, 4.90344536, 40.79553679],
    "above_white": [Vector3(1.8, 1.4, 1.1), 123.45124440, 12.65118626, 1.07387374, 125.02479429],
    "dark": [Vector3(0.01, 0.004, 0.02), 6.39501235, 10.66535541, 5.42349356, 9.98929287],
}

const READ_TOLERANCE := 1e-4
const ROUND_TRIP_TOLERANCE := 1e-5


func _compiled() -> SaCompute:
    var file := FileAccess.open(scratch_probe_path, FileAccess.WRITE)
    file.store_string(PROBE_SOURCE)
    file.close()
    GlobalShaderCompiler.compile_compute_shader(scratch_probe_path)
    return SaCompute.new(PROBE_NAME)


## What *kernel* writes for each fixture's colour, one texel a colour.
func _run(kernel: String) -> Dictionary:
    var names := FIXTURES.keys()
    var size := Vector2i(names.size(), 1)
    var src := SaTexture.new(size, F32)
    var colours := PackedFloat32Array()
    for name: String in names:
        var rgb: Vector3 = FIXTURES[name][0]
        colours.append_array([rgb.x, rgb.y, rgb.z, 1.0])
    GlobalShaderCompiler.get_rd().texture_update(src.rid, 0, colours.to_byte_array())
    var dst := SaTexture.new(size, F32)
    dst.clear(Color(0, 0, 0, 0))
    _compiled().run(kernel, {"src": src, "dst": dst}, {}, Rect2i(Vector2i.ZERO, size))
    var texels := GlobalShaderCompiler.get_rd().texture_get_data(dst.rid, 0).to_float32_array()
    var out := {}
    for i in names.size():
        out[names[i]] = Vector4(texels[i * 4], texels[i * 4 + 1], texels[i * 4 + 2], texels[i * 4 + 3])
    return out


func test_the_library_reads_j_c_h_and_j_hk_as_the_papers_equations_give() -> void:
    var read := _run("cam16_read")
    for name: String in FIXTURES:
        var want: Array = FIXTURES[name]
        var got: Vector4 = read[name]
        assert_almost_eq(got.x, float(want[1]), READ_TOLERANCE, "%s: J %.6f against %.6f" % [name, got.x, want[1]])
        assert_almost_eq(got.y, float(want[2]), READ_TOLERANCE, "%s: C %.6f against %.6f" % [name, got.y, want[2]])
        # A grey has no hue, and the papers' atan of two noughts is a convention.
        if float(want[2]) > 0.0:
            assert_almost_eq(got.z, float(want[3]), READ_TOLERANCE, "%s: h %.6f against %.6f" % [name, got.z, want[3]])
        assert_almost_eq(got.w, float(want[4]), READ_TOLERANCE, "%s: J_HK %.6f against %.6f" % [name, got.w, want[4]])


func test_the_inverse_through_j_hk_gives_each_colour_back() -> void:
    var back := _run("cam16_round_trip")
    for name: String in FIXTURES:
        var want: Vector3 = FIXTURES[name][0]
        var got: Vector4 = back[name]
        var off := maxf(absf(got.x - want.x), maxf(absf(got.y - want.y), absf(got.z - want.z)))
        assert_true(off <= ROUND_TRIP_TOLERANCE, "%s comes back as %s from %s, %.8f off" % [name, got, want, off])
