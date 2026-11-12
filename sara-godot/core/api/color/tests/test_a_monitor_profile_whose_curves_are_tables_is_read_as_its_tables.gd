## A monitor profile whose tone curves are 256-entry tables a few thousandths
## from any power curve is read, and its curve is the table: mid grey goes into
## linear light and back as the table says. Windows writes such a profile for a
## calibrated panel, `CalibratedDisplayProfile-15.icc`, whose tables stand
## 0.0066 from a gamma of 2.2, and the suite makes one of the same kind, since
## a painter's file is not in the tree. A table that falls is still refused with
## the reason, and a profile whose curve is one gamma number reads as it did.
extends "res://tests/test_framework.gd"

const SRGB: Array[Vector2] = [Vector2(0.64, 0.33), Vector2(0.30, 0.60), Vector2(0.15, 0.06)]
const D50 := Vector2(0.3457, 0.3585)
const ENTRIES := 256
## How far the made table stands from a gamma of 2.2, as Windows' does.
const BEND := 0.0066
## Half an 8-bit code value, the bound the row names.
const HALF_CODE := 0.5 / 255.0


func test_a_v2_profile_with_256_point_curves_0_0066_from_gamma_2_2_is_read() -> void:
    var table := _calibrated_table()
    var apart := 0.0
    for i in ENTRIES:
        apart = maxf(apart, absf(table[i] - pow(i / float(ENTRIES - 1), 2.2)))
    assert_almost_eq(apart, BEND, 2e-4, "The made table stands %.4f from Gamma 2.2" % apart)
    var profile := SaIccProfile.parse(_profile_with_table(table))
    assert_eq(profile.problem, "", "The profile is read")
    assert_not_null(profile.space, "and gives the panel a colour space")
    assert_true(profile.space.transfer is SaIccProfile.TableCurve, "whose curve is the table itself")


func test_mid_grey_goes_into_light_and_back_as_the_table_says() -> void:
    var table := _calibrated_table()
    var space := SaIccProfile.parse(_profile_with_table(table)).space
    # The table's own reading of a stored half, between entries 127 and 128.
    var own := _quantised(table[127]) * 0.5 + _quantised(table[128]) * 0.5
    var light := space.carried_to(SaColorSpace.linear_srgb(), Color(0.5, 0.5, 0.5))
    for channel in 3:
        assert_almost_eq(
            light[channel], own, HALF_CODE, "Stored mid grey decodes to the table's %.5f, channel %d" % [own, channel]
        )
    var back := SaColorSpace.linear_srgb().carried_to(space, Color(own, own, own))
    for channel in 3:
        assert_almost_eq(back[channel], 0.5, HALF_CODE, "and the table's light encodes back to mid grey, channel %d" % channel)
    var gamma := pow(0.5, 2.2)
    assert_true(
        absf(own - gamma) > HALF_CODE,
        "The table's mid grey %.5f is not Gamma 2.2's %.5f, so the test tells them apart" % [own, gamma]
    )
    # The gamma a kernel gets meets the table at its half, so a quarter is where
    # the table and that gamma part.
    var quarter := space.carried_to(SaColorSpace.linear_srgb(), Color(0.25, 0.25, 0.25))
    var fitted := pow(0.25, space.transfer.exponent)
    var table_quarter := lerpf(_quantised(table[63]), _quantised(table[64]), 0.75)
    assert_almost_eq(quarter.r, table_quarter, HALF_CODE, "A stored quarter decodes as the table says")
    assert_true(absf(table_quarter - fitted) > HALF_CODE, "and not as the gamma that meets it at the half")


func test_the_table_goes_both_ways_at_every_entry() -> void:
    var table := _calibrated_table()
    var curve := SaIccProfile.parse(_profile_with_table(table)).space.transfer
    var worst := 0.0
    for i in ENTRIES:
        var stored := i / float(ENTRIES - 1)
        worst = maxf(worst, absf(curve.encode(curve.decode(stored)) - stored))
        assert_almost_eq(curve.decode(stored), _quantised(table[i]), 1e-6, "Entry %d decodes to itself" % i)
    assert_true(worst < 1e-4, "and every entry encodes back to where it was, %.6f at worst" % worst)
    assert_almost_eq(curve.decode(2.0), pow(2.0, curve.exponent), 1e-4, "A value over one carries on, nothing clamps")
    assert_almost_eq(curve.decode(-0.5), -curve.decode(0.5), 1e-6, "and a negative one is mirrored")


func test_a_table_that_falls_is_refused_with_the_reason() -> void:
    var table := _calibrated_table()
    table[200] = table[180]
    var profile := SaIccProfile.parse(_profile_with_table(table))
    assert_null(profile.space, "A falling table gives no colour space")
    assert_true(profile.problem.contains("falls between entries 199 and 200"), "and says where it falls: %s" % profile.problem)


func test_a_one_point_curve_is_read_as_before() -> void:
    var profile := SaIccProfile.parse(_profile_with_gamma(563))
    assert_eq(profile.problem, "", "A one entry curve is read")
    assert_false(profile.space.transfer is SaIccProfile.TableCurve, "as a curve, not a table")
    assert_eq(profile.space.transfer.id, SaTransferFunction.ID_GAMMA, "a pure gamma")
    assert_almost_eq(profile.space.transfer.exponent, 563.0 / 256.0, 1e-6, "of its number over 256")


## A calibration's curve: Gamma 2.2 with a wave of [constant BEND] on it, which
## stays at nought at both ends, rises everywhere and is lowest at mid grey.
func _calibrated_table() -> PackedFloat32Array:
    var table := PackedFloat32Array()
    for i in ENTRIES:
        var x := i / float(ENTRIES - 1)
        table.append(pow(x, 2.2) + BEND * sin(3.0 * PI * x))
    return table


func _quantised(value: float) -> float:
    return clampi(roundi(value * 65535.0), 0, 65535) / 65535.0


func _profile_with_table(table: PackedFloat32Array) -> PackedByteArray:
    var curve := PackedByteArray("curv".to_ascii_buffer())
    curve.resize(8)
    curve.append_array(_be(table.size(), 4))
    for value in table:
        curve.append_array(_be(clampi(roundi(value * 65535.0), 0, 65535), 2))
    return _profile(curve)


func _profile_with_gamma(eighths: int) -> PackedByteArray:
    var curve := PackedByteArray("curv".to_ascii_buffer())
    curve.resize(8)
    curve.append_array(_be(1, 4))
    curve.append_array(_be(eighths, 2))
    return _profile(curve)


## A version 2 profile of sRGB's primaries at D50 whose three curves are *curve*.
func _profile(curve: PackedByteArray) -> PackedByteArray:
    var colorants := _matrix(SRGB, D50)
    var tags: Array = [["wtpt", _xyz(SaIccProfile.PCS_WHITE)]]
    for i in 3:
        tags.append([["rXYZ", "gXYZ", "bXYZ"][i], _xyz(colorants[i])])
    for signature: String in ["rTRC", "gTRC", "bTRC"]:
        tags.append([signature, curve.duplicate()])
    var start := SaIccProfile.HEADER_SIZE + 4 + 12 * tags.size()
    var table_bytes := _be(tags.size(), 4)
    var data := PackedByteArray()
    for tag: Array in tags:
        var body: PackedByteArray = tag[1]
        while body.size() % 4 != 0:
            body.append(0)
        table_bytes.append_array(String(tag[0]).to_ascii_buffer())
        table_bytes.append_array(_be(start + data.size(), 4))
        table_bytes.append_array(_be(body.size(), 4))
        data.append_array(body)
    var header := PackedByteArray()
    header.resize(SaIccProfile.HEADER_SIZE)
    header[8] = 2
    for i in 4:
        header[16 + i] = "RGB ".unicode_at(i)
        header[36 + i] = "acsp".unicode_at(i)
    header.append_array(table_bytes)
    header.append_array(data)
    return header


## RGB to XYZ for *primaries* about *white*, from xy alone.
func _matrix(primaries: Array[Vector2], white: Vector2) -> Basis:
    var columns: Array[Vector3] = []
    for p: Vector2 in primaries:
        columns.append(Vector3(p.x / p.y, 1.0, (1.0 - p.x - p.y) / p.y))
    var unscaled := Basis(columns[0], columns[1], columns[2])
    var w := Vector3(white.x / white.y, 1.0, (1.0 - white.x - white.y) / white.y)
    var scale := unscaled.inverse() * w
    return Basis(columns[0] * scale.x, columns[1] * scale.y, columns[2] * scale.z)


func _xyz(value: Vector3) -> PackedByteArray:
    var tag := PackedByteArray("XYZ ".to_ascii_buffer())
    tag.resize(8)
    for v: float in [value.x, value.y, value.z]:
        tag.append_array(_be(roundi(v * 65536.0) & 0xFFFFFFFF, 4))
    return tag


func _be(value: int, size: int) -> PackedByteArray:
    var out := PackedByteArray()
    for i in range(size - 1, -1, -1):
        out.append((value >> (i * 8)) & 0xFF)
    return out
