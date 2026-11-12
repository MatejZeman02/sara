## Filter > White Point makes a picked colour neutral.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The record is built with a warm picked colour and run over that
## colour and a white, and the picked colour's three channels read equal at its
## luminance while the white moves the same way. The same way is read where the
## filter works, in Bradford's cone space: each cone of the white is scaled by
## the gain that cone of the picked colour was scaled by. Beside it: the white
## comes out as the filter's own matrix says, a strength of a half moves the
## colour half way in linear light, nothing picked and black change nothing,
## the colour above white is not clamped, an Oklab document's picked colour
## lands on Oklab's grey axis, and the record keeps the colour it was handed
## through a save while the picture under it changes.
extends "res://tests/test_framework.gd"

const RoundTrip = preload("res://modules/sara-base-modules/base/tests/attached_round_trip.gd")

const REQUIRES_GPU := true

## A warm grey, a sheet of paper under a tungsten lamp, as an sRGB document
## stores it.
const WARM := Color(0.68, 0.55, 0.42, 1.0)

## How far apart two channels a grey holds may stand, in linear light, at F32.
const NEAR := 2e-4

var _easel: SaEasel = null
var _doc: SaDocument = null


func after_each() -> void:
    if _easel != null:
        _easel.free()
    _easel = null
    _doc = null


func _open(space: SaColorSpace) -> void:
    _easel = SaEasel.create_default(Vector2i(SaChunk.SIZE, SaChunk.SIZE), null, space)
    _doc = _easel.document
    _doc.active_layer.fill(Color(0.5, 0.5, 0.5, 1.0))


## Writes *colours* from the chunk's first texel on, at F32.
func _put(colours: Array[Color]) -> void:
    var texture := _doc.active_layer.get_field(Vector2i.ZERO)
    var rd := GlobalShaderCompiler.get_rd()
    var bytes := rd.texture_get_data(texture.rid, 0)
    for i in colours.size():
        for channel in 4:
            bytes.encode_float(i * 16 + channel * 4, colours[i][channel])
    rd.texture_update(texture.rid, 0, bytes)


## The chunk's first *count* texels, as stored.
func _texels(count: int) -> Array[Color]:
    var texture := _doc.active_layer.get_field(Vector2i.ZERO)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var out: Array[Color] = []
    for i in count:
        out.append(SaFieldSpec.decode_texel(bytes, texture.format, i))
    return out


func _light(stored: Color) -> Vector3:
    return SaWhitePointFilter.linear_of(stored, _doc.color_space)


func _apply(spec: Dictionary) -> bool:
    return SaWhitePointFilter.new().capture_apply(_doc, spec)


## Bradford's three cone responses of light-linear sRGB *colour*.
static func _cones(colour: Vector3) -> Vector3:
    var xyz := SaColorSpace.linear_srgb().rgb_to_xyz() * colour
    var rows := SaColorSpace.BRADFORD_ROWS
    return Vector3((rows[0] as Vector3).dot(xyz), (rows[1] as Vector3).dot(xyz), (rows[2] as Vector3).dot(xyz))


static func _near(a: Vector3, b: Vector3, bound: float) -> bool:
    return absf(a.x - b.x) <= bound and absf(a.y - b.y) <= bound and absf(a.z - b.z) <= bound


func test_a_warm_picked_colour_comes_out_neutral_at_its_luminance_and_a_white_moves_the_same_way() -> void:
    _open(SaColorSpace.srgb())
    _put([WARM, Color.WHITE])
    var picked := _light(WARM)
    var luma := SaWhitePointFilter.luminance(picked)
    assert_true(picked.x > picked.y and picked.y > picked.z, "the picked colour is warm, red over green over blue, %s" % picked)
    assert_true(_apply({"stored": [WARM.r, WARM.g, WARM.b]}), "the filter ran over the layer")
    var row := _texels(2)
    var grey := _light(row[0])
    assert_true(
        _near(grey, Vector3.ONE * luma, NEAR),
        "the picked colour reads three equal channels at its own luminance %.5f, read %s" % [luma, grey]
    )
    assert_almost_eq(SaWhitePointFilter.luminance(grey), luma, NEAR, "and its luminance is the one it had")
    assert_almost_eq(row[0].a, 1.0, 0.0, "its alpha is kept")
    var white := _light(row[1])
    var wanted := SaWhitePointFilter.correction(picked, 1.0) * Vector3.ONE
    assert_true(_near(white, wanted, NEAR), "the white comes out as the filter's matrix takes it, %s, read %s" % [wanted, white])
    assert_true(white.z > white.x, "a warm cast taken out leaves the white cool, read %s" % white)
    var picked_gain := _cones(grey) / _cones(picked)
    var white_gain := _cones(white) / _cones(Vector3.ONE)
    assert_true(
        _near(white_gain, picked_gain, 1e-3),
        "each cone of the white is scaled by the gain of the picked colour's, %s against %s" % [white_gain, picked_gain]
    )


func test_a_strength_of_a_half_moves_the_colour_half_way_in_linear_light() -> void:
    _open(SaColorSpace.srgb())
    _put([WARM])
    var picked := _light(WARM)
    var luma := SaWhitePointFilter.luminance(picked)
    assert_true(_apply({"stored": [WARM.r, WARM.g, WARM.b], "strength": 50}), "the filter ran")
    var half := _light(_texels(1)[0])
    assert_true(_near(half, picked.lerp(Vector3.ONE * luma, 0.5), NEAR), "half of the way to the grey, read %s" % half)


func test_nothing_picked_and_black_change_nothing() -> void:
    for held: Array in [[], [0.0, 0.0, 0.0], [0.4, "red", 0.2]]:
        var matrix := SaWhitePointFilter.document_matrix(SaWhitePointFilter.picked_of({"picked": held}), 1.0, SaColorSpace.srgb())
        assert_eq(matrix, Basis.IDENTITY, "%s picked is the identity" % [held])
    _open(SaColorSpace.srgb())
    _put([WARM])
    assert_true(_apply({}), "the filter ran with nothing picked")
    var kept := _texels(1)[0]
    assert_true(
        _near(Vector3(kept.r, kept.g, kept.b), Vector3(WARM.r, WARM.g, WARM.b), 1e-5),
        "and the colour is as it was, read %s" % kept
    )


func test_a_colour_above_white_is_scaled_and_never_clamped() -> void:
    _open(SaColorSpace.linear_srgb())
    var bright := Color(4.0, 3.0, 2.0, 1.0)
    _put([bright])
    var picked := SaWhitePointFilter.linear_of(WARM, SaColorSpace.srgb())
    assert_true(_apply({"picked": SaWhitePointFilter.as_list(picked)}), "the filter ran")
    var out := _texels(1)[0]
    var wanted := SaWhitePointFilter.correction(picked, 1.0) * Vector3(4.0, 3.0, 2.0)
    assert_true(
        _near(Vector3(out.r, out.g, out.b), wanted, 1e-3),
        "the colour above white moves as the matrix says, %s, read %s" % [wanted, out]
    )
    assert_true(out.r > 1.0, "and it stays above white, read %s" % out)


func test_an_oklab_document_s_picked_colour_lands_on_the_grey_axis() -> void:
    _open(SaColorSpace.oklab())
    var warm_lab := SaOklab.from_linear_srgb(SaWhitePointFilter.linear_of(WARM, SaColorSpace.srgb()))
    _put([Color(warm_lab.x, warm_lab.y, warm_lab.z, 1.0)])
    assert_true(absf(warm_lab.y) + absf(warm_lab.z) > 0.03, "the picked colour is off the grey axis, %s" % warm_lab)
    assert_true(_apply({"stored": [warm_lab.x, warm_lab.y, warm_lab.z]}), "the filter ran")
    var out := _texels(1)[0]
    assert_almost_eq(out.g, 0.0, 1e-3, "a is nought, read %s" % out)
    assert_almost_eq(out.b, 0.0, 1e-3, "b is nought, read %s" % out)


func test_the_record_keeps_the_picked_colour_through_a_save_and_whatever_the_picture_holds() -> void:
    var filter := SaWhitePointFilter.new()
    var picked := SaWhitePointFilter.linear_of(WARM, SaColorSpace.srgb())
    filter.set_parameters({"picked": SaWhitePointFilter.as_list(picked), "strength": 80.0})
    var filed := filter.filed_as(&"sara-base-modules.white_point")
    var saved: Variant = JSON.parse_string(JSON.stringify(filed.parameters))
    assert_true(saved is Dictionary, "the record's values go through JSON")
    var reread := SaWhitePointFilter.picked_of(saved as Dictionary)
    assert_true(_near(reread, picked, 1e-6), "and the picked colour comes back, %s, read %s" % [picked, reread])
    var before := SaWhitePointFilter.record(filed.parameters, SaColorSpace.srgb()).push
    var after := SaWhitePointFilter.record(saved as Dictionary, SaColorSpace.srgb()).push
    assert_eq(after, before, "the reopened record dispatches what the attached one did")
    # Two pictures through one record: the pick is the record's, so the second
    # picture is corrected by the matrix the first one was.
    for picture: Color in [WARM, Color(0.2, 0.6, 0.9, 1.0)]:
        _open(SaColorSpace.srgb())
        _put([picture])
        var recorded := SaWhitePointFilter.record(saved as Dictionary, _doc.color_space)
        assert_true(
            SaFilterApply.apply_point(_doc, _doc.active_layer, recorded, SaCompute.new(SaWhitePointFilter.SHADER), "White Point"),
            "the record ran over %s" % picture
        )
        var wanted := SaWhitePointFilter.correction(picked, 0.8) * _light(picture)
        var read := _light(_texels(1)[0])
        assert_true(_near(read, wanted, NEAR), "%s is corrected by the record's own pick, %s, read %s" % [picture, wanted, read])
        _easel.free()
        _easel = null


func test_attached_it_keeps_its_pick_when_the_picture_changes_and_through_a_save() -> void:
    var trip := RoundTrip.new(SaWhitePointFilter.new(), &"sara-base-modules")
    var space := trip.easel.document.color_space
    var picked := SaWhitePointFilter.linear_of(WARM, SaColorSpace.srgb())
    var balance := SaWhitePointFilter.correction(picked, 1.0)
    trip.attach({"picked": SaWhitePointFilter.as_list(picked)})
    var before := trip.texels()
    for index in RoundTrip.GRIDS.size():
        var wanted := balance * SaWhitePointFilter.linear_of(RoundTrip.COLOURS[index], space)
        var read := SaWhitePointFilter.linear_of(before[index], space)
        assert_true(_near(read, wanted, NEAR), "attached, chunk %d comes out as the record's pick says, read %s" % [index, read])
    trip.layer.get_or_create_chunk(RoundTrip.GRIDS[0]).clear(WARM)
    var changed := trip.texels()
    var grey := SaWhitePointFilter.linear_of(changed[0], space)
    assert_true(
        _near(grey, Vector3.ONE * SaWhitePointFilter.luminance(picked), NEAR),
        "the warm grey painted after the attach comes out neutral by the pick it kept, read %s" % grey
    )
    var loaded := trip.round_trip({})
    assert_true(_near(SaWhitePointFilter.picked_of(loaded), picked, 1e-6), "the saved record loads with its pick, %s" % [loaded])
    var after := trip.texels()
    assert_true(
        RoundTrip.distance(changed, after) < 1e-5, "and draws what it drew before the save: %s against %s" % [changed, after]
    )
    trip.release()


func test_the_panel_shows_the_colour_it_picked() -> void:
    _open(SaColorSpace.srgb())
    _put([WARM])
    var panel := SaWhitePointPanel.new()
    var picked := _light(WARM)
    panel.show_picked(picked)
    var swatch := panel.find_child("PickedSwatch", true, false) as ColorRect
    assert_not_null(swatch, "the panel has a swatch")
    if swatch != null:
        assert_eq(swatch.color.to_html(false), WARM.to_html(false), "and it shows the warm grey as an sRGB document stores it")
    var caption := panel.find_child("PickedCaption", true, false) as Label
    assert_true(caption != null and caption.text.contains("#" + WARM.to_html(false)), "the caption names it")
    panel.show_picked(Vector3(NAN, NAN, NAN))
    assert_true(caption != null and caption.text.begins_with("Nothing picked"), "and says when nothing is")
    panel.free()
