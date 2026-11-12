## The lattice hash of `shaders/compute/libs/lattice_hash.gmacs`,
## read for the two things a noise and a simulation need of it: its numbers
## spread evenly over 0 to 1, and a step of one along any axis changes about
## half its bits, so two neighbouring corners are unrelated.
##
## The hash replaced the `pcg3d` listing, whose licence GPLv3 cannot carry, and
## this suite is what says the new one is not weaker. The same checks run over
## a deliberately weak hash in the same probe and have to refuse it, so a
## check loose enough to pass anything is caught here rather than trusted.
##
## The probe is written to `user://` and compiled from there, the shape
## `test_run_call.gd` uses, so no probe kernel ships in the tree. It imports
## the library by name, which resolves to Sara's own copy the way any kernel's
## import does.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const F32 := RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT

const PROBE_NAME := "sa_lattice_hash_probe"
static var scratch_probe_path: String = SaDataRoot.path("sa_lattice_hash_probe.gmacs")

## The cube of lattice points read, 32 to a side from -16 to 15, so the corners
## either side of nought and the wrap of a negative int into a uint are in it.
## It is laid out as eight slices to a row of the image and four rows.
const SIDE := 32
const IMAGE := Vector2i(SIDE * 8, SIDE * 4)

## Each texel writes the bits that flipped when its corner stepped one along
## *axis*, as two halves of 16 bits that a float holds exactly, then the hash
## of the corner in 0 to 1, then how many bits flipped. `weak_step` writes the
## same of a hash that is one multiply of the corner's index, the kind of hash
## the checks below are there to refuse.
const PROBE_SOURCE := """kernel lattice_step, weak_step

image dst

params:
    int axis

import lattice_hash


def corner_of(ivec2 at) -> ivec3:
    return ivec3(at.x % 32, at.y % 32, at.x / 32 + 8 * (at.y / 32)) - ivec3(16)


def along() -> ivec3:
    return ivec3(axis == 0 ? 1 : 0, axis == 1 ? 1 : 0, axis == 2 ? 1 : 0)


def written(ivec2 at, uint bits, uint stepped):
    uint flipped = bits ^ stepped
    float value = ldexp(float(bits >> 8u), -24)
    image_store(dst, at, vec4(float(flipped >> 16u), float(flipped & 0xFFFFu), value, float(bit_count(flipped))))


def weak_bits(ivec3 corner) -> uint:
    uvec3 c = uvec3(corner + ivec3(16))
    return (c.x + c.y * 32u + c.z * 1024u) * 0x01234567u


def lattice_step():
    ivec3 corner = corner_of(pixel)
    written(pixel, sa_lattice_bits(corner), sa_lattice_bits(corner + along()))


def weak_step():
    ivec3 corner = corner_of(pixel)
    written(pixel, weak_bits(corner), weak_bits(corner + along()))
"""

## What the checks allow. A good 32-bit hash flips 16 bits a step on average,
## and each bit half the time. Over 32,768 corners a bit's share has a standard
## deviation of 0.003, so 0.45 to 0.55 is more than fifteen of them either
## side, wide enough never to fail a good hash and narrow enough to refuse one
## whose bits stick. Over this cube on the CPU the new hash's shares read 0.494
## to 0.505, `pcg3d`'s 0.473 to 0.509, and the weak hash's nought to one, with
## 30 of its 32 bits outside, while its mean along x is 15.87 and inside. So
## the bits are read one by one and the mean is not enough.
const MEAN_FLIPS_LOW := 15.0
const MEAN_FLIPS_HIGH := 17.0
const SHARE_LOW := 0.45
const SHARE_HIGH := 0.55

## The numbers in 0 to 1 are counted into 64 equal bins. A chi-square of 63
## degrees of freedom passes 120 about once in a hundred thousand runs. Over
## this cube on the CPU the new hash read 64.7, `pcg3d` 60.9 and the weak
## hash 661.
const BINS := 64
const CHI_SQUARE_HIGH := 120.0

## The 24 bits a value is made of are each set in about half the corners.
const SET_LOW := 0.48
const SET_HIGH := 0.52

const AXES := ["x", "y", "z"]

## The `pcg3d` listing's two constants and its first addition, as a search
## found them. A kernel holding any of the three is the listing back.
const PCG3D_MARKS := ["1664525u", "1013904223u", "v.x += v.y * v.z"]


func _compiled() -> SaCompute:
    if GlobalShaderCompiler.get_kernel_names(PROBE_NAME).is_empty():
        var file := FileAccess.open(scratch_probe_path, FileAccess.WRITE)
        file.store_string(PROBE_SOURCE)
        file.close()
    GlobalShaderCompiler.compile_compute_shader(scratch_probe_path)
    return SaCompute.new(PROBE_NAME)


## The texels *kernel* writes for a step along *axis*, four floats each.
func _texels(compute: SaCompute, kernel: String, axis: int) -> PackedFloat32Array:
    var dst := SaTexture.new(IMAGE, F32)
    dst.clear(Color(0, 0, 0, 0))
    compute.run(kernel, {"dst": dst}, {"axis": axis}, Rect2i(Vector2i.ZERO, IMAGE))
    return GlobalShaderCompiler.get_rd().texture_get_data(dst.rid, 0).to_float32_array()


## What is wrong with *kernel*'s hash, one line a failed check, and nothing
## when it passes them all. A function rather than assertions of its own so
## the weak hash can be held to it and expected to fail.
func _faults(compute: SaCompute, kernel: String) -> PackedStringArray:
    var faults := PackedStringArray()
    var corners := IMAGE.x * IMAGE.y
    for axis in AXES.size():
        var texels := _texels(compute, kernel, axis)
        var flips := 0.0
        var per_bit := PackedInt32Array()
        per_bit.resize(32)
        for i in corners:
            flips += texels[i * 4 + 3]
            var high := int(texels[i * 4])
            var low := int(texels[i * 4 + 1])
            for bit in 16:
                per_bit[bit + 16] += (high >> bit) & 1
                per_bit[bit] += (low >> bit) & 1
        var mean := flips / corners
        if mean < MEAN_FLIPS_LOW or mean > MEAN_FLIPS_HIGH:
            faults.append("a step along %s flips %.2f bits on average" % [AXES[axis], mean])
        for bit in 32:
            var share := float(per_bit[bit]) / corners
            if share < SHARE_LOW or share > SHARE_HIGH:
                faults.append("a step along %s flips bit %d in %.3f of the corners" % [AXES[axis], bit, share])
        if axis == 0:
            faults.append_array(_spread_faults(texels, corners))
    return faults


## Whether the numbers in 0 to 1 of *texels* fill the range evenly.
func _spread_faults(texels: PackedFloat32Array, corners: int) -> PackedStringArray:
    var faults := PackedStringArray()
    var bins := PackedInt32Array()
    bins.resize(BINS)
    var set_counts := PackedInt32Array()
    set_counts.resize(24)
    for i in corners:
        var value := texels[i * 4 + 2]
        if value < 0.0 or value >= 1.0:
            faults.append("a value of %f is outside 0 to 1" % value)
            return faults
        bins[int(value * BINS)] += 1
        var top := int(value * 16777216.0)
        for bit in 24:
            set_counts[bit] += (top >> bit) & 1
    var expected := float(corners) / BINS
    var chi_square := 0.0
    for count in bins:
        chi_square += (count - expected) * (count - expected) / expected
    if chi_square > CHI_SQUARE_HIGH:
        faults.append("the values over %d bins read a chi-square of %.1f" % [BINS, chi_square])
    for bit in 24:
        var share := float(set_counts[bit]) / corners
        if share < SET_LOW or share > SET_HIGH:
            faults.append("bit %d of the value is set in %.3f of the corners" % [bit, share])
    return faults


func test_the_lattice_hash_spreads_evenly_and_a_step_along_any_axis_flips_about_half_its_bits() -> void:
    var faults := _faults(_compiled(), "lattice_step")
    assert_eq(faults, PackedStringArray(), "The lattice hash passes every check over %d corners" % (IMAGE.x * IMAGE.y))


## The checks are only worth their pass if they can fail. One multiply of the
## corner's index flips nearly 16 bits a step along x, so a check of the mean
## alone would pass it, while its lowest bit flips at every step and others
## almost never, the fixed pattern a value noise shows as a grid.
func test_a_weak_hash_fails_the_same_checks() -> void:
    var faults := _faults(_compiled(), "weak_step")
    assert_false(faults.is_empty(), "One multiply of the index is refused")
    var named_flips := false
    for fault in faults:
        named_flips = named_flips or fault.contains("flips bit")
    assert_true(named_flips, "and what it is refused for is a bit that flips on a pattern: %s" % ", ".join(faults.slice(0, 3)))


## The two callers read the one function, the way the unit asked: neither
## library holds a hash of its own, and both import the shared one.
func test_the_noise_and_the_simulation_libraries_import_the_one_hash() -> void:
    for path: String in ["res://shaders/compute/libs/noise.gmacs", "res://core/layers/simulation/simulation.gmacs"]:
        var text := FileAccess.get_file_as_string(path)
        assert_true(text.contains("\nimport lattice_hash\n"), "%s imports lattice_hash" % path.get_file())
        assert_false(text.contains("def sa_lattice_hash"), "and defines no lattice hash of its own")
        assert_false(text.contains("* v.z"), "nor mixes a vector of its own")
    var simulation := FileAccess.get_file_as_string("res://core/layers/simulation/simulation.gmacs")
    assert_true(
        simulation.contains("return sa_lattice_hash(ivec3(ivec2(chunk) + at, step))"),
        "The step's number is the lattice hash",
    )


## The Done line of the unit as a check that stays: no kernel in the tree or in
## a module checkout holds the listing, by its constants and its additions.
func test_no_kernel_holds_the_pcg3d_listing() -> void:
    var kernels := _kernels_under("res://")
    assert_true(kernels.size() > 80, "The walk found the tree's kernels, %d of them" % kernels.size())
    for path in kernels:
        var text := FileAccess.get_file_as_string(path)
        for mark: String in PCG3D_MARKS:
            assert_false(text.contains(mark), "%s holds %s, a mark of the pcg3d listing" % [path, mark])


func _kernels_under(folder: String) -> PackedStringArray:
    var found := PackedStringArray()
    var dir := DirAccess.open(folder)
    if dir == null:
        return found
    dir.include_hidden = false
    for sub in dir.get_directories():
        if sub == ".godot" or sub == "scratch" or sub == "build" or sub.begins_with("."):
            continue
        found.append_array(_kernels_under(folder.path_join(sub)))
    for file in dir.get_files():
        if file.get_extension() == "gmacs":
            found.append(folder.path_join(file))
    return found
