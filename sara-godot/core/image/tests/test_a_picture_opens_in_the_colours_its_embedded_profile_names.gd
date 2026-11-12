## A picture opens in the colours its embedded profile names: a photograph in
## Adobe RGB or Display P3 is read in its own gamut and curve, not as sRGB.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The pictures are `scripts/make_profiled_pictures.py`'s, each profile built
## there from the published primaries and curves, so the numbers this suite
## checks against are the published ones and not a reading of the file. Every
## picture is 32 by 16, pure green on its left half.
extends "res://tests/test_framework.gd"

## Opening a picture into a document is a real upload and a real kernel.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const FOLDER := "res://core/image/tests/fixtures/profiled/"
## How near a read primary has to stand to the published one, in CIE xy.
const PRIMARY_BOUND := 0.0005
## How near the green patch has to land to the green computed here.
const TEXEL_BOUND := 0.002

const D65 := Vector2(0.3127, 0.3290)
const D50 := Vector2(0.3457, 0.3585)
const ADOBE: Array[Vector2] = [Vector2(0.64, 0.33), Vector2(0.21, 0.71), Vector2(0.15, 0.06)]
const P3: Array[Vector2] = [Vector2(0.680, 0.320), Vector2(0.265, 0.690), Vector2(0.150, 0.060)]
const PROPHOTO: Array[Vector2] = [Vector2(0.7347, 0.2653), Vector2(0.1596, 0.8404), Vector2(0.0366, 0.0001)]
const REC2020: Array[Vector2] = [Vector2(0.708, 0.292), Vector2(0.170, 0.797), Vector2(0.131, 0.046)]
const SRGB: Array[Vector2] = [Vector2(0.64, 0.33), Vector2(0.30, 0.60), Vector2(0.15, 0.06)]

## The skeleton's formats with the image formats module's after them, for the
## TIFF, as the running app registers them.
var _formats: SaRegistries


func before_each() -> void:
    _formats = Fixtures.make_picture_registries()


## Each picture's file, the primaries and white it was made in, and the curve:
## the exponent a pure gamma has, or the preset id.
func _cases() -> Array[Dictionary]:
    return [
        {"file": "adobe_rgb.jpg", "primaries": ADOBE, "white": D65, "gamma": 563.0 / 256.0},
        {"file": "display_p3_split.jpg", "primaries": P3, "white": D65, "curve": SaTransferFunction.ID_SRGB},
        {"file": "prophoto.png", "primaries": PROPHOTO, "white": D50, "gamma": 1.8},
        {"file": "display_p3.webp", "primaries": P3, "white": D65, "curve": SaTransferFunction.ID_SRGB},
        {"file": "adobe_rgb.tif", "primaries": ADOBE, "white": D65, "gamma": 563.0 / 256.0},
        {"file": "rec2020.exr", "primaries": REC2020, "white": D65, "curve": SaTransferFunction.ID_LINEAR},
    ]


func test_every_picture_names_the_primaries_and_the_curve_of_its_profile() -> void:
    for case: Dictionary in _cases():
        var file: String = case["file"]
        var space := SaImageImport.named_space_for(FOLDER + file)
        assert_not_null(space, "%s names a space" % file)
        if space == null:
            continue
        var published: Array[Vector2] = case["primaries"]
        for i in 3:
            var apart := space.primaries[i].distance_to(published[i])
            assert_true(
                apart <= PRIMARY_BOUND,
                "%s: primary %d is %s, %.5f from the published %s" % [file, i, space.primaries[i], apart, published[i]]
            )
        var white: Vector2 = case["white"]
        assert_true(space.white.distance_to(white) <= PRIMARY_BOUND, "%s: the white is %s" % [file, space.white])
        if case.has("gamma"):
            var exponent: float = case["gamma"]
            assert_eq(space.transfer.id, SaTransferFunction.ID_GAMMA, "%s: the curve is a pure gamma" % file)
            # The `curv` tag holds a gamma in eighths of a 256th, so 1.8 is 461/256.
            assert_almost_eq(space.transfer.exponent, exponent, 0.002, "%s: of %.4f" % [file, exponent])
            assert_true(space.transfer.threshold == 0.0, "%s: with no straight segment" % file)
        else:
            assert_eq(space.transfer.id, case["curve"], "%s: the curve is %s" % [file, case["curve"]])


## A profile that is a preset's opens on the preset, so the row lists it by
## the preset's name.
func test_a_display_p3_profile_opens_on_the_display_p3_preset() -> void:
    for file: String in ["display_p3_split.jpg", "display_p3.webp"]:
        assert_eq(SaImageImport.named_space_for(FOLDER + file).id, SaColorSpace.ID_DISPLAY_P3, "%s opens on Display P3" % file)
    assert_eq(SaImageImport.named_space_for(FOLDER + "rec2020.exr").id, SaColorSpace.ID_REC2020, "and the EXR on Rec. 2020")


## The profile split over two `APP2` segments is put back together, and one
## part missing reads as no profile at all rather than half of one.
func test_a_profile_split_over_two_segments_is_put_together_in_order() -> void:
    var whole := SaEmbeddedProfile.jpeg(FOLDER + "display_p3_split.jpg")
    assert_eq(whole.slice(36, 40).get_string_from_ascii(), "acsp", "The two parts make a profile")
    assert_eq(whole.decode_u8(3) | (whole.decode_u8(2) << 8), whole.size() & 0xFFFF, "of the size its header says")
    var bytes := FileAccess.get_file_as_bytes(FOLDER + "display_p3_split.jpg")
    var second := _find(bytes, "ICC_PROFILE".to_ascii_buffer(), _find(bytes, "ICC_PROFILE".to_ascii_buffer(), 0) + 1)
    var cut := bytes.slice(0, second - 4)
    var length := (bytes[second - 2] << 8) | bytes[second - 1]
    cut.append_array(bytes.slice(second - 2 + length))
    var path := SaDataRoot.path("one-part.jpg")
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(cut)
    file.close()
    assert_true(SaEmbeddedProfile.jpeg(path).is_empty(), "One part alone is no profile")
    assert_null(SaImageImport.named_space_for(path), "and names nothing")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The green patch of the Adobe RGB JPEG lands in a linear sRGB document as
## Adobe RGB's green, computed here from the published primaries alone: green
## well outside sRGB, so its red and blue are negative and kept.
func test_the_adobe_rgb_green_lands_as_adobe_rgb_green() -> void:
    var easel := SaEasel.create_default(Vector2i(32, 16))
    easel.document.reset_to_default(Vector2i(32, 16), SaColorSpace.linear_srgb())
    var path := FOLDER + "adobe_rgb.jpg"
    var layer := SaImageImport.open_into(easel.document, path)
    assert_not_null(layer, "The JPEG opens")
    if layer == null:
        easel.free()
        return
    var texture := layer.get_field(Vector2i.ZERO)
    @warning_ignore("static_called_on_instance")
    var got := SaExport.get_texture_image_float(texture).get_pixel(4, 4)
    var expected := _matrix(SRGB, D65).inverse() * _matrix(ADOBE, D65) * Vector3(0.0, 1.0, 0.0)
    assert_true(expected.x < -0.3, "Adobe RGB's green is outside sRGB, red %.4f" % expected.x)
    assert_almost_eq(got.r, expected.x, TEXEL_BOUND, "Red is Adobe RGB's green's: %.4f against %.4f" % [got.r, expected.x])
    assert_almost_eq(got.g, expected.y, TEXEL_BOUND, "green: %.4f against %.4f" % [got.g, expected.y])
    assert_almost_eq(got.b, expected.z, TEXEL_BOUND, "blue: %.4f against %.4f" % [got.b, expected.z])
    easel.free()


func test_a_lookup_table_profile_leaves_the_picture_on_srgb_with_the_reason() -> void:
    var path := FOLDER + "lookup_table.jpg"
    assert_null(SaImageImport.named_space_for(path), "A lookup table profile names no space Sara uses")
    assert_eq(SaImageImport.space_for(path).id, SaColorSpace.ID_SRGB, "so the JPEG opens on sRGB")
    var profile := SaImageImport.profile_for(path)
    assert_not_null(profile, "The profile is found")
    assert_eq(profile.name, "Coated Paper LUT", "and named")
    assert_true(profile.problem.contains("lookup table"), "and the reason says what it is: %s" % profile.problem)


func test_a_png_with_cicp_and_iccp_is_named_by_its_cicp() -> void:
    var path := FOLDER + "cicp_and_iccp.png"
    assert_false(SaEmbeddedProfile.png(path).is_empty(), "The PNG carries an iCCP")
    assert_eq(SaImageImport.named_space_for(path).id, SaColorSpace.ID_DISPLAY_P3, "and is named by its cICP, Display P3")
    assert_null(SaImageImport.profile_for(path), "with the iCCP set aside")


## A curve table stands as the nearest Sara curve within the bound, and one
## past it is read as the table itself.
func test_a_curve_table_stands_as_the_nearest_sara_curve_or_as_itself() -> void:
    var srgb := PackedFloat32Array()
    var bent := PackedFloat32Array()
    for i in 1024:
        var x := i / 1023.0
        srgb.append(SaTransferFunction.srgb().decode(x))
        # A curve that dips under a straight line and back: no gamma meets it.
        bent.append(x * x * x * (2.0 - x) if x < 0.5 else x)
    var read := SaIccProfile.parse(_profile_with_table(srgb))
    assert_eq(read.problem, "", "An sRGB table is read")
    assert_eq(read.space.transfer.id, SaTransferFunction.ID_SRGB, "as sRGB's curve")
    var own := SaIccProfile.parse(_profile_with_table(bent))
    assert_eq(own.problem, "", "A table no Sara curve meets is read")
    assert_true(own.space.transfer is SaIccProfile.TableCurve, "as the table itself")


## RGB to XYZ for *primaries* about *white*, from xy alone.
func _matrix(primaries: Array[Vector2], white: Vector2) -> Basis:
    var columns: Array[Vector3] = []
    for p: Vector2 in primaries:
        columns.append(Vector3(p.x / p.y, 1.0, (1.0 - p.x - p.y) / p.y))
    var unscaled := Basis(columns[0], columns[1], columns[2])
    var w := Vector3(white.x / white.y, 1.0, (1.0 - white.x - white.y) / white.y)
    var scale := unscaled.inverse() * w
    return Basis(columns[0] * scale.x, columns[1] * scale.y, columns[2] * scale.z)


## A version 2 profile of sRGB's primaries at D50 whose three curves are the
## table *table*.
func _profile_with_table(table: PackedFloat32Array) -> PackedByteArray:
    var curve := PackedByteArray("curv".to_ascii_buffer())
    curve.resize(8)
    curve.append_array(_be(table.size(), 4))
    for value in table:
        curve.append_array(_be(clampi(roundi(value * 65535.0), 0, 65535), 2))
    var colorants := _matrix(SRGB, D50)
    var tags: Array = [["wtpt", _xyz(SaIccProfile.PCS_WHITE)]]
    for i in 3:
        tags.append([["rXYZ", "gXYZ", "bXYZ"][i], _xyz(colorants[i])])
    for signature: String in ["rTRC", "gTRC", "bTRC"]:
        tags.append([signature, curve])
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


func _find(bytes: PackedByteArray, needle: PackedByteArray, from: int) -> int:
    for i in range(from, bytes.size() - needle.size()):
        if bytes.slice(i, i + needle.size()) == needle:
            return i
    return -1
