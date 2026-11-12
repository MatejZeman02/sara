## A ramp's table converts its stops once for the whole table.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The structure file holds 70 gradient maps, and building each one's table
## asked `oklab_at` 256 times, which converted every stop again each time: 13 ms
## a table and 0.92 s of the frame that first drew the opened file. These read
## `oklab_samples` against `oklab_at` at every sample, in sRGB and in a wider
## space, so the table the gradient map reads is the one it read before, to the
## float.
extends "res://tests/test_framework.gd"

const SAMPLES := 256


func _ramp() -> SaColorRamp:
    var ramp := SaColorRamp.new()
    ramp.stops.append({"position": 0.0, "color": Color(0.05, 0.1, 0.4, 1.0)})
    ramp.stops.append({"position": 0.3, "color": Color(0.9, 0.2, 0.1, 0.5)})
    ramp.stops.append({"position": 0.3, "color": Color(0.2, 0.8, 0.3, 1.0)})
    ramp.stops.append({"position": 1.0, "color": Color(1.0, 0.95, 0.8, 1.0)})
    return ramp


func _per_sample(ramp: SaColorRamp, space: SaColorSpace) -> PackedFloat32Array:
    var out := PackedFloat32Array()
    for i in SAMPLES:
        var lab := ramp.oklab_at(float(i) / float(SAMPLES - 1), space)
        out.append_array([lab.r, lab.g, lab.b, lab.a])
    return out


func test_the_table_is_the_ramp_read_a_sample_at_a_time() -> void:
    var ramp := _ramp()
    assert_true(ramp.oklab_samples(SAMPLES) == _per_sample(ramp, null), "With no space, every float matches")
    var wide := SaColorSpace.display_p3()
    assert_true(ramp.oklab_samples(SAMPLES, wide) == _per_sample(ramp, wide), "and in a wider space as well")


func test_a_table_of_one_sample_is_the_ramp_s_start() -> void:
    var ramp := _ramp()
    var lab := ramp.oklab_at(0.0)
    assert_eq(ramp.oklab_samples(1), PackedFloat32Array([lab.r, lab.g, lab.b, lab.a]), "One sample is the first stop")
