## White Point takes two sliders that move the white along the two tint axes.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The note: White Point applied with nothing picked to a mid grey reads Oklab
## b rise when Blue to yellow moves towards yellow and fall towards blue, a do
## the same for Green to magenta, the lightness held within a bound stated here,
## both at nought leave the grey as it was, and a document saved before the
## sliders draws as it did.
##
## **The lightness bounds are two**, since the sliders move the colour made grey
## and the von Kries scaling keeps that colour's luminance and not the grey's.
## Within half the reach, where a fine tune lives, a mid grey's Oklab lightness
## stays within [const NEAR_LIGHTNESS]. At the ends it stays within
## [const FAR_LIGHTNESS], reached towards blue, where the colour made grey is a
## strong yellow whose blue cone the scaling raises eightfold, and a pick of that
## yellow would brighten the grey just as far.
##
## Beside it: the dialog lists the two sliders under the pick and before the
## Strength, the sliders move the colour made grey from a pick by exactly their
## numbers in Oklab and it comes out grey, a pick too dark to use leaves them to
## start from the white, Strength scales the whole of it, and an Oklab document
## moves as an sRGB one does.
extends "res://tests/test_framework.gd"

const RoundTrip = preload("res://modules/sara-base-modules/base/tests/attached_round_trip.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"sara-base-modules"
## A mid grey as an sRGB document stores it.
const GREY := Color(0.5, 0.5, 0.5, 1.0)
## A warm grey, a sheet of paper under a tungsten lamp, as F4 picks it.
const WARM := Color(0.68, 0.55, 0.42, 1.0)
## How far a mid grey's Oklab lightness may move with a slider within half its
## reach, and at either end.
const NEAR_LIGHTNESS := 0.015
const FAR_LIGHTNESS := 0.09
## The least a slider at a tenth of its reach moves its own axis, in Oklab.
const LEAST_MOVE := 0.005
## How far apart a grey's channels may stand, in linear light, at F32.
const NEAR := 2e-4

const YELLOW := SaWhitePointFilter.YELLOW_KEY
const MAGENTA := SaWhitePointFilter.MAGENTA_KEY

var _easel: SaEasel = null
var _doc: SaDocument = null


func after_each() -> void:
    _close()


func _close() -> void:
    if _easel != null:
        _easel.free()
    _easel = null
    _doc = null


## A one chunk document in *space* at F32, filled with *fill*.
func _open(space: SaColorSpace, fill: Color = GREY) -> void:
    _close()
    _easel = SaEasel.create_default(Vector2i(SaChunk.SIZE, SaChunk.SIZE), null, space.with_depth(SaColorSpace.Depth.F32))
    _doc = _easel.document
    _doc.active_layer.fill(fill)


## Writes *colours* from the chunk's first texel on.
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


## White Point applied over a fresh mid grey in *space* with *spec*, and the
## grey's Oklab before and after.
func _grey_moved(space: SaColorSpace, spec: Dictionary) -> Array[Vector3]:
    _open(space)
    var before := SaOklab.from_linear_srgb(_light(_texels(1)[0]))
    assert_true(SaWhitePointFilter.new().capture_apply(_doc, spec), "White Point ran with %s" % spec)
    return [before, SaOklab.from_linear_srgb(_light(_texels(1)[0]))]


static func _near(a: Vector3, b: Vector3, bound: float) -> bool:
    return absf(a.x - b.x) <= bound and absf(a.y - b.y) <= bound and absf(a.z - b.z) <= bound


## Reads one slider, *key*, over a mid grey with nothing picked, through
## Oklab's channel *axis*, 1 for a and 2 for b: the axis moves the slider's way
## and further the further it goes, and the lightness stays within the bounds.
func _reads_its_axis(key: StringName, axis: int) -> void:
    var reach := SaWhitePointFilter.TINT_REACH
    for way: float in [1.0, -1.0]:
        var last := 0.0
        for share: float in [0.1, 0.5, 1.0]:
            var number := way * share * reach
            var read := _grey_moved(SaColorSpace.srgb(), {String(key): number})
            var moved: float = read[1][axis] - read[0][axis]
            var lightness: float = read[1].x - read[0].x
            assert_true(moved * way >= LEAST_MOVE, "%s at %.1f moves the grey its way, by %.5f" % [key, number, moved])
            assert_true(absf(moved) > absf(last), "and further than at the step before, %.5f against %.5f" % [moved, last])
            last = moved
            var bound := NEAR_LIGHTNESS if share <= 0.5 else FAR_LIGHTNESS
            assert_true(absf(lightness) <= bound, "the lightness moves %.5f, within %.3f" % [lightness, bound])


func test_the_dialog_shows_the_two_sliders_under_the_pick_and_before_the_strength() -> void:
    var host := VBoxContainer.new()
    # Held here, since a `Callable` keeps no filter alive and a bare one would
    # leave the dialog nothing to declare.
    var filter := SaWhitePointFilter.new()
    var dialog := SaDialog.new(filter.build)
    dialog.declare_rows()
    dialog.realize(host)
    var keys: Array[StringName] = []
    for row in dialog.rows():
        if row.key in [&"white_point", YELLOW, MAGENTA, &"strength"]:
            keys.append(row.key)
    assert_eq(keys, [&"white_point", YELLOW, MAGENTA, &"strength"] as Array[StringName], "the sliders stand under the pick")
    for key: StringName in [YELLOW, MAGENTA]:
        var row := dialog.row(key)
        assert_not_null(row, "the dialog has %s" % key)
        if row != null:
            assert_almost_eq(float(row.value), 0.0, 0.0, "%s starts at nought" % key)
            assert_almost_eq(row.min_value, -SaWhitePointFilter.TINT_REACH, 0.0, "and reaches down to the reach")
            assert_almost_eq(row.max_value, SaWhitePointFilter.TINT_REACH, 0.0, "and up to it")
    assert_eq(String(dialog.row(YELLOW).label), "Blue to yellow", "the b slider names its two ends")
    assert_eq(String(dialog.row(MAGENTA).label), "Green to magenta", "and so does the a slider")
    host.free()


func test_towards_yellow_raises_b_and_towards_blue_lowers_it() -> void:
    _reads_its_axis(YELLOW, 2)


func test_towards_magenta_raises_a_and_towards_green_lowers_it() -> void:
    _reads_its_axis(MAGENTA, 1)


func test_both_at_nought_leave_the_grey_as_it_was() -> void:
    var nothing := Vector3(NAN, NAN, NAN)
    assert_false(SaWhitePointFilter.neutral(nothing, 0.0, 0.0).is_finite(), "nothing picked stays nothing")
    assert_eq(
        SaWhitePointFilter.document_matrix(SaWhitePointFilter.neutral(nothing, 0.0, 0.0), 1.0, SaColorSpace.srgb()),
        Basis.IDENTITY,
        "and is the identity"
    )
    var read := _grey_moved(SaColorSpace.srgb(), {String(YELLOW): 0.0, String(MAGENTA): 0})
    var kept := _texels(1)[0]
    assert_true(
        _near(Vector3(kept.r, kept.g, kept.b), Vector3(GREY.r, GREY.g, GREY.b), 1e-6), "the grey is as it was, read %s" % kept
    )
    assert_true(_near(read[1], read[0], 1e-6), "in Oklab too, %s against %s" % [read[1], read[0]])
    var picked := SaWhitePointFilter.linear_of(WARM, SaColorSpace.srgb())
    assert_eq(SaWhitePointFilter.neutral(picked, 0.0, 0.0), picked, "a pick with both at nought is the pick, untouched")


## A record saved before the sliders names neither. It dispatches the push the
## filter built from its pick before this row, bit for bit, and attached and
## saved it loads and draws what F4's own formula says.
func test_a_document_saved_before_the_sliders_draws_as_it_did() -> void:
    var picked := SaWhitePointFilter.linear_of(WARM, SaColorSpace.srgb())
    var before := {"picked": SaWhitePointFilter.as_list(picked), "strength": 80.0}
    for space: SaColorSpace in [SaColorSpace.srgb(), SaColorSpace.linear_srgb(), SaColorSpace.oklab()]:
        var old := SaWhitePointFilter.push_for(SaWhitePointFilter.document_matrix(picked, 0.8, space), space)
        assert_eq(SaWhitePointFilter.record(before, space).push, old, "%s dispatches the push it did" % space.id)
    var trip := RoundTrip.new(SaWhitePointFilter.new(), OWNER)
    var space := trip.easel.document.color_space
    trip.record = SaFilterOps.new(trip.easel.document).attach(
        trip.layer, trip.key, {"picked": SaWhitePointFilter.as_list(picked)}
    )
    var balance := SaWhitePointFilter.correction(picked, 1.0)
    var attached := trip.texels()
    for index in RoundTrip.GRIDS.size():
        var wanted := balance * SaWhitePointFilter.linear_of(RoundTrip.COLOURS[index], space)
        var read := SaWhitePointFilter.linear_of(attached[index], space)
        assert_true(_near(read, wanted, NEAR), "chunk %d draws as the pick alone says, read %s" % [index, read])
    var loaded := trip.round_trip({String(YELLOW): 12.0, String(MAGENTA): -7.0})
    assert_false(loaded.is_empty(), "the document saves and loads with its White Point")
    assert_almost_eq(SaWhitePointFilter.tint_of(loaded, YELLOW), 0.0, 0.0, "and the loaded record reads Blue to yellow at nought")
    assert_almost_eq(SaWhitePointFilter.tint_of(loaded, MAGENTA), 0.0, 0.0, "and Green to magenta at nought")
    var after := trip.texels()
    assert_true(RoundTrip.distance(attached, after) < 1e-5, "and draws what it drew: %s against %s" % [attached, after])
    trip.release()


## From a pick the two numbers are the colour made grey's own move in Oklab,
## made at a luminance of one and the other way, and that colour comes out grey
## at its luminance while the pick itself takes the tint the sliders name.
func test_the_sliders_move_the_colour_made_grey_from_the_pick() -> void:
    _open(SaColorSpace.srgb())
    var picked := _light(WARM)
    var moved := SaWhitePointFilter.neutral(picked, 6.0, -4.0)
    var from := SaOklab.from_linear_srgb(picked / SaWhitePointFilter.luminance(picked))
    var wanted := SaOklab.to_linear_srgb(from + Vector3(0.0, 0.04, -0.06))
    var tint := moved / SaWhitePointFilter.luminance(moved)
    assert_true(
        _near(tint, wanted / SaWhitePointFilter.luminance(wanted), 1e-5),
        (
            "six towards yellow and four towards green move the colour made grey 0.06 towards blue and 0.04 towards magenta, %s"
            % tint
        )
    )
    assert_almost_eq(
        SaWhitePointFilter.luminance(moved), SaWhitePointFilter.luminance(picked), 1e-6, "handed back at the pick's luminance"
    )
    _put(_as_stored([picked, moved]))
    var spec := {"picked": SaWhitePointFilter.as_list(picked), String(YELLOW): 6.0, String(MAGENTA): -4.0}
    assert_true(SaWhitePointFilter.new().capture_apply(_doc, spec), "White Point ran with the pick and the sliders")
    var row := _texels(2)
    var grey := _light(row[1])
    var luma := SaWhitePointFilter.luminance(moved)
    assert_true(_near(grey, Vector3.ONE * luma, NEAR), "the moved colour comes out grey at %.5f, read %s" % [luma, grey])
    var pick_out := SaOklab.from_linear_srgb(_light(row[0]))
    assert_true(pick_out.z > LEAST_MOVE, "the pick itself comes out towards yellow, b %.5f" % pick_out.z)
    assert_true(pick_out.y < -LEAST_MOVE, "and towards green, a %.5f" % pick_out.y)


## The stored colours of an sRGB document for light-linear *colours*.
static func _as_stored(colours: Array[Vector3]) -> Array[Color]:
    var out: Array[Color] = []
    var curve := SaTransferFunction.srgb()
    for colour in colours:
        out.append(Color(curve.encode(colour.x), curve.encode(colour.y), curve.encode(colour.z), 1.0))
    return out


func test_a_pick_too_dark_to_use_leaves_the_sliders_to_start_from_the_white() -> void:
    var white := SaWhitePointFilter.neutral(Vector3(NAN, NAN, NAN), -8.0, 5.0)
    var black := SaWhitePointFilter.neutral(Vector3.ZERO, -8.0, 5.0)
    assert_true(white.is_finite() and SaWhitePointFilter.can_neutralise(white), "nothing picked moves the white, %s" % white)
    assert_true(_near(black, white, 1e-6), "and black picked moves it as nothing picked does, %s against %s" % [black, white])


func test_strength_scales_the_whole_of_it() -> void:
    var spec := {String(YELLOW): 12.0, String(MAGENTA): 7.0}
    _grey_moved(SaColorSpace.srgb(), spec)
    var full := _light(_texels(1)[0])
    var half_spec := spec.duplicate()
    half_spec["strength"] = 50.0
    _grey_moved(SaColorSpace.srgb(), half_spec)
    var half := _light(_texels(1)[0])
    var grey := SaWhitePointFilter.linear_of(GREY, SaColorSpace.srgb())
    assert_true(
        _near(half, grey.lerp(full, 0.5), NEAR),
        "half the strength is half of the way, %s against %s" % [half, grey.lerp(full, 0.5)]
    )


func test_an_oklab_document_moves_as_an_srgb_one_does() -> void:
    var spec := {String(YELLOW): 10.0, String(MAGENTA): -6.0}
    var srgb := _grey_moved(SaColorSpace.srgb(), spec)
    var srgb_moved: Vector3 = srgb[1] - srgb[0]
    _open(SaColorSpace.oklab())
    var start := SaOklab.from_linear_srgb(SaWhitePointFilter.linear_of(GREY, SaColorSpace.srgb()))
    _put([Color(start.x, start.y, start.z, 1.0)])
    assert_true(SaWhitePointFilter.new().capture_apply(_doc, spec), "White Point ran on the Oklab document")
    var out := _texels(1)[0]
    var moved := Vector3(out.r, out.g, out.b) - start
    assert_true(_near(moved, srgb_moved, 1e-4), "the Oklab grey moves %s, as the sRGB one moves %s" % [moved, srgb_moved])
