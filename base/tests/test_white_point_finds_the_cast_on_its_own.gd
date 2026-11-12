## White Point's Auto finds the cast on its own.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The note: a grey card scene of several greys and colours is tinted with a
## known warm cast, and each way's estimate reads within a stated bound of the
## cast's chromaticity, and the applied result's average within that bound of
## neutral. The same scene with no cast reads an estimate within the bound of
## grey.
##
## The scene is two chunks of upright stripes. Greys of several luminances, and
## beside a grey of 0.3 and of 0.5 each colour a step of one channel above that
## grey and below it, red, green and blue, so that with no cast the colours
## average to grey and their steps are as large in every channel. The second
## chunk holds besides a band of near black blue, a band of blown white and a
## strip of transparent pure blue, any of which would pull the estimate, and
## none of which may be counted. The cast is a 4000 K lamp, taken in by the
## Bradford scaling a camera's white balance undoes, applied to the stripes and
## not to the bands, which a camera clips or loses whatever the light.
##
## **The bound is a hundredth in CIE 1931 xy**, an eighth of the lamp's own
## distance from D65. A colour step under a cast is not the cast times the step,
## since a cone sees a mix of channels, so the edges miss the lamp by about half
## of that on this scene and the surfaces by a fiftieth of it.
##
## Beside it: the bands read exactly as ground never painted, a document on
## sRGB's curve and an Oklab one find what a linear one does, the root's
## composite reads as its one layer's paint, a layer with nothing counted finds
## nothing, a flat grey has no edges, and the panel's caption says how its
## colour was found.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

## A lamp of about 4000 K, warm and a little green of the daylight locus.
const LAMP := Vector2(0.3805, 0.3768)
## How near in CIE 1931 xy an estimate has to come, the note's bound.
const BOUND := 0.01
## How far a step of one channel goes above and below its grey, linear.
const STEP := 0.05
## How many stripes a chunk is cut into.
const STRIPES := 16
## The bands the estimate has to leave out, as linear sRGB: a background nearly
## black and bluish, and a sky blown to white.
const DARK_BAND := Color(0.002, 0.003, 0.012, 1.0)
const BLOWN_BAND := Color(1.0, 1.0, 1.0, 1.0)
## The colour of the transparent strip, which no alpha of nought may let in.
const EMPTY_STRIP := Color(0.0, 0.0, 1.0, 0.0)

const WAYS: Array[int] = [SaWhitePointEstimate.From.SURFACES, SaWhitePointEstimate.From.EDGES]

var _easel: SaEasel = null
var _doc: SaDocument = null


func after_each() -> void:
    _close()


func _close() -> void:
    if _easel != null:
        _easel.free()
    _easel = null
    _doc = null


## A document in *space* at F32, two chunks across, with one Paint layer filled
## so both chunks exist.
func _open(space: SaColorSpace) -> int:
    _close()
    var held := space.with_depth(SaColorSpace.Depth.F32)
    _easel = SaEasel.create_default(Vector2i(SaChunk.SIZE * 2, SaChunk.SIZE), null, held)
    _doc = _easel.document
    _doc.active_layer.fill(Color(0.5, 0.5, 0.5, 1.0))
    var field := _doc.active_layer.get_field(Vector2i.ZERO)
    assert_eq(field.format, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, "the layer stores F32")
    return field.size.x


static func _grey(level: float) -> Vector3:
    return Vector3.ONE * level


## A grey, then for each channel a step above it and a step below it, each
## between two stripes of the grey: thirteen stripes.
static func _steps_around(level: float) -> Array[Vector3]:
    var out: Array[Vector3] = []
    for channel in 3:
        var up := _grey(level)
        up[channel] += STEP
        var down := _grey(level)
        down[channel] -= STEP
        out.append_array([_grey(level), up, _grey(level), down])
    out.append(_grey(level))
    return out


## The first chunk's sixteen stripes and the second chunk's thirteen, linear.
static func _first_stripes() -> Array[Vector3]:
    var out := _steps_around(0.3)
    out.append_array([_grey(0.1), _grey(0.2), _grey(0.6)])
    return out


static func _second_stripes() -> Array[Vector3]:
    return _steps_around(0.5)


## The Bradford scaling from D65 to *white*, in linear sRGB.
static func _cast_to(white: Vector2) -> Basis:
    var srgb := SaColorSpace.linear_srgb()
    return srgb.xyz_to_rgb() * SaColorSpace.adaptation(srgb.white, white) * srgb.rgb_to_xyz()


static func _xy(colour: Vector3) -> Vector2:
    var xyz := SaColorSpace.linear_srgb().rgb_to_xyz() * colour
    var total := xyz.x + xyz.y + xyz.z
    return Vector2(xyz.x / total, xyz.y / total)


## Linear sRGB *colour* with *alpha* as the document stores it.
func _stored(colour: Vector3, alpha: float) -> Color:
    var space := _doc.color_space
    if space.coordinates == SaColorSpace.Coordinates.OKLAB:
        var lab := SaOklab.from_linear_srgb(colour)
        return Color(lab.x, lab.y, lab.z, alpha)
    var own := space.from_linear_srgb_matrix() * colour
    var curve := space.transfer
    return Color(curve.encode(own.x), curve.encode(own.y), curve.encode(own.z), alpha)


## Linear sRGB *colour*, its alpha with it, as the document stores it.
func _stored_colour(colour: Color) -> Color:
    return _stored(Vector3(colour.r, colour.g, colour.b), colour.a)


## Writes the scene into the two chunks, the stripes taken through *cast* and
## the bands as they are. With *bands* false the bands and the strip are
## transparent black instead, ground that was never painted, so what is left
## out can be compared with what was never there.
func _paint_scene(edge: int, cast: Basis, bands: bool = true) -> void:
    @warning_ignore("integer_division")
    var width := edge / STRIPES
    @warning_ignore("integer_division")
    var dark_from := edge / 2
    @warning_ignore("integer_division")
    var blown_from := edge * 3 / 4
    var empty := EMPTY_STRIP if bands else Color.TRANSPARENT
    var first := _stripe_row(_first_stripes(), edge, width, cast, empty)
    var second := _stripe_row(_second_stripes(), edge, width, cast, empty)
    var empty_from := _second_stripes().size() * width
    var dark := _band_row(DARK_BAND if bands else Color.TRANSPARENT, edge, empty_from, empty)
    var blown := _band_row(BLOWN_BAND if bands else Color.TRANSPARENT, edge, empty_from, empty)
    var whole := PackedFloat32Array()
    var lower := PackedFloat32Array()
    for y in edge:
        whole.append_array(first)
        if y < dark_from:
            lower.append_array(second)
        elif y < blown_from:
            lower.append_array(dark)
        else:
            lower.append_array(blown)
    var rd := GlobalShaderCompiler.get_rd()
    rd.texture_update(_doc.active_layer.get_field(Vector2i(0, 0)).rid, 0, whole.to_byte_array())
    rd.texture_update(_doc.active_layer.get_field(Vector2i(1, 0)).rid, 0, lower.to_byte_array())


## One row of *stripes*, each *width* texels wide, taken through *cast*, and
## *empty* after the last stripe to the chunk's edge.
func _stripe_row(stripes: Array[Vector3], edge: int, width: int, cast: Basis, empty: Color) -> PackedFloat32Array:
    var row := PackedFloat32Array()
    for x in edge:
        @warning_ignore("integer_division")
        var index := x / width
        var texel := _stored(cast * stripes[index], 1.0) if index < stripes.size() else _stored_colour(empty)
        row.append_array(PackedFloat32Array([texel.r, texel.g, texel.b, texel.a]))
    return row


## One row of the band *colour* up to *empty_from*, and *empty* after it.
func _band_row(colour: Color, edge: int, empty_from: int, empty: Color) -> PackedFloat32Array:
    var row := PackedFloat32Array()
    for x in edge:
        var texel := _stored_colour(colour if x < empty_from else empty)
        row.append_array(PackedFloat32Array([texel.r, texel.g, texel.b, texel.a]))
    return row


## The mean of the stripes as the layer holds them now, on a linear sRGB
## document, where a stored texel is its own light: the whole first chunk and
## the second's stripes above its bands.
func _stripes_mean(edge: int) -> Vector3:
    assert_eq(_doc.color_space.transfer.decode(0.5), 0.5, "the mean is read on a linear document")
    var rd := GlobalShaderCompiler.get_rd()
    var sum := Vector3.ZERO
    var count := 0
    @warning_ignore("integer_division")
    var stripes_end := _second_stripes().size() * (edge / STRIPES)
    @warning_ignore("integer_division")
    var half := edge / 2
    for grid: Vector2i in [Vector2i(0, 0), Vector2i(1, 0)]:
        var floats := rd.texture_get_data(_doc.active_layer.get_field(grid).rid, 0).to_float32_array()
        var rows := edge if grid.x == 0 else half
        var columns := edge if grid.x == 0 else stripes_end
        for y in rows:
            for x in columns:
                var at := (y * edge + x) * 4
                sum += Vector3(floats[at], floats[at + 1], floats[at + 2])
                count += 1
    return sum / float(count)


func _way_name(way: int) -> String:
    return "from surfaces" if way == SaWhitePointEstimate.From.SURFACES else "from edges"


func test_with_no_cast_each_way_finds_grey() -> void:
    var edge := _open(SaColorSpace.linear_srgb())
    _paint_scene(edge, Basis.IDENTITY)
    var white := SaColorSpace.linear_srgb().white
    for way in WAYS:
        var found := SaWhitePointEstimate.neutral(_doc, _doc.active_layer, way)
        assert_true(found.is_finite(), "%s finds a colour, %s" % [_way_name(way), found])
        var off := _xy(found).distance_to(white)
        assert_true(off <= BOUND, "%s finds grey, %s off D65 in xy, within %.3f" % [_way_name(way), off, BOUND])


func test_a_warm_cast_is_found_each_way_and_taking_it_out_leaves_the_scene_neutral() -> void:
    var white := SaColorSpace.linear_srgb().white
    assert_true(LAMP.distance_to(white) > 8.0 * BOUND, "the lamp stands well off D65, %.4f" % LAMP.distance_to(white))
    for way in WAYS:
        var edge := _open(SaColorSpace.linear_srgb())
        _paint_scene(edge, _cast_to(LAMP))
        var found := SaWhitePointEstimate.neutral(_doc, _doc.active_layer, way)
        var off := _xy(found).distance_to(LAMP)
        assert_true(off <= BOUND, "%s finds the lamp, %s off it in xy, within %.3f" % [_way_name(way), off, BOUND])
        var before := _stripes_mean(edge)
        assert_true(_xy(before).distance_to(white) > 8.0 * BOUND, "the scene reads warm before, %s" % _xy(before))
        var applied := SaWhitePointFilter.new().capture_apply(_doc, {"picked": SaWhitePointFilter.as_list(found)})
        assert_true(applied, "White Point ran with what %s found" % _way_name(way))
        var after := _xy(_stripes_mean(edge)).distance_to(white)
        assert_true(
            after <= BOUND, "%s, the scene's mean after is %.4f off neutral, within %.3f" % [_way_name(way), after, BOUND]
        )


func test_a_dark_background_a_blown_sky_and_empty_ground_are_left_out() -> void:
    for way in WAYS:
        var edge := _open(SaColorSpace.linear_srgb())
        _paint_scene(edge, _cast_to(LAMP), false)
        var without := SaWhitePointEstimate.neutral(_doc, _doc.active_layer, way)
        _paint_scene(edge, _cast_to(LAMP), true)
        var with_bands := SaWhitePointEstimate.neutral(_doc, _doc.active_layer, way)
        var moved := with_bands.distance_to(without)
        assert_true(
            moved < 1e-5 * without.length(),
            "%s reads the bands as ground never painted, %s against %s" % [_way_name(way), with_bands, without]
        )


func test_a_document_on_a_curve_and_an_oklab_one_find_what_a_linear_one_does() -> void:
    var found: Dictionary = {}
    for space: SaColorSpace in [SaColorSpace.linear_srgb(), SaColorSpace.srgb(), SaColorSpace.oklab()]:
        var edge := _open(space)
        _paint_scene(edge, _cast_to(LAMP))
        for way in WAYS:
            var guess := SaWhitePointEstimate.neutral(_doc, _doc.active_layer, way)
            if found.has(way):
                var apart := _xy(guess).distance_to(_xy(found[way] as Vector3))
                assert_true(apart < 1e-3, "%s in %s finds what linear sRGB found, %.6f apart" % [_way_name(way), space.id, apart])
            else:
                found[way] = guess


func test_the_root_reads_its_composite_as_the_layer_reads_its_paint() -> void:
    var edge := _open(SaColorSpace.linear_srgb())
    _paint_scene(edge, _cast_to(LAMP))
    # The grey ground under the layer would show through the transparent
    # strip, so it is hidden, and the root's composite is the layer's paint.
    var ground := _doc.find_child(SaDocumentBackground.LAYER_NAME, false, false) as SaLayer
    assert_not_null(ground, "the document has its ground")
    if ground != null:
        ground.visible = false
    for way in WAYS:
        var layer := SaWhitePointEstimate.neutral(_doc, _doc.active_layer, way)
        var root := SaWhitePointEstimate.neutral(_doc, null, way)
        var apart := _xy(root).distance_to(_xy(layer))
        assert_true(apart < 1e-4, "%s, the root's composite reads as the layer does, %.6f apart" % [_way_name(way), apart])


func test_nothing_counted_finds_nothing() -> void:
    _open(SaColorSpace.linear_srgb())
    for colour: Color in [Color(0.003, 0.003, 0.003, 1.0), Color(1.0, 0.9, 0.7, 1.0)]:
        _doc.active_layer.fill(colour)
        for way in WAYS:
            var found := SaWhitePointEstimate.neutral(_doc, _doc.active_layer, way)
            assert_false(found.is_finite(), "%s finds nothing in a layer of %s, read %s" % [_way_name(way), colour, found])
    var none := PackedFloat64Array()
    none.resize(SaWhitePointEstimate.RECORD)
    none.fill(0.0)
    assert_false(SaWhitePointEstimate.neutral_of(none, SaWhitePointEstimate.From.SURFACES).is_finite(), "no sums is no guess")


func test_a_flat_grey_has_no_edges_and_its_surfaces_are_the_grey() -> void:
    _open(SaColorSpace.linear_srgb())
    _doc.active_layer.fill(Color(0.4, 0.4, 0.4, 1.0))
    var surfaces := SaWhitePointEstimate.neutral(_doc, _doc.active_layer, SaWhitePointEstimate.From.SURFACES)
    assert_true(surfaces.distance_to(Vector3.ONE * 0.4) < 1e-4, "from surfaces a flat grey is that grey, read %s" % surfaces)
    var edges := SaWhitePointEstimate.neutral(_doc, _doc.active_layer, SaWhitePointEstimate.From.EDGES)
    assert_false(edges.is_finite(), "and from edges it has none to read, read %s" % edges)


func test_the_panel_shows_what_auto_found_and_how() -> void:
    var panel := SaWhitePointPanel.new()
    var auto := panel.find_child("WhitePointAuto", true, false) as Button
    assert_true(auto != null and auto.text == "Auto", "the panel has an Auto button")
    var from := panel.find_child("WhitePointAutoFrom", true, false) as SaChoiceButton
    assert_not_null(from, "and the choice beside it")
    if from != null:
        assert_eq(from.choice_labels(), ["From surfaces", "From edges"] as Array[String], "of the two ways")
        assert_eq(from.selected_value(), SaWhitePointEstimate.From.SURFACES, "from surfaces at first")
    var warm := SaWhitePointFilter.linear_of(Color(0.68, 0.55, 0.42), SaColorSpace.srgb())
    panel.show_picked(warm, SaWhitePointEstimate.From.EDGES)
    var caption := panel.find_child("PickedCaption", true, false) as Label
    var says := caption.text if caption != null else ""
    assert_true(says.begins_with("Found #ad8c6b from the edges"), "the caption says how, %s" % says)
    panel.show_picked(warm)
    assert_true(caption != null and caption.text.begins_with("Picked #ad8c6b"), "and a pick is a pick, %s" % caption.text)
    var shown := panel.capture_option_edit({"from": "edges"})
    assert_true(shown.contains('"from":"edges"'), "the door moves the choice, %s" % shown)
    panel.free()
