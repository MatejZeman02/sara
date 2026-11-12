## Hue, Saturation, Colour and Lightness in Oklab LCh over the whole range: up
## to white within a measured Oklab difference of the windowed reading they
## replaced, and above it a lightness that survives, no channel held at W and a
## gamut step that lowers chroma alone. Then a file saved before, which opens as
## it draws now and names the layer whose picture changed.
##
## Each kernel runs over a grid of pairs in one dispatch, a pair to a texel.
## Today's result, the reading before this row, is modelled here: the inputs
## divided by W, the components swapped in Oklab LCh, chroma bisected into the
## unit cube, and the result scaled back by W.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const MODES: Array[String] = ["hue", "saturation", "color", "lightness"]

const SIZE := Vector2i(128, 128)

## 128 / 8, the [numthreads(8, 8, 1)] the composite kernels declare.
const GROUPS: int = 16

## The values a channel takes from 0 to W, as fractions of W, so the grid holds
## 125 colours and every pair of them fits the texture.
const UNDER: Array[float] = [0.0, 0.25, 0.5, 0.75, 1.0]

## The values a channel takes in the grid above white, as fractions of W. None
## is W itself, so a channel read at W was put there by the blend.
const ABOVE: Array[float] = [0.0, 0.6, 1.5, 2.5, 4.0]

## The largest Oklab difference from today's result over the grid under white,
## as measured, at each W the suite reads on an sRGB document. At 1 the two
## readings are one arithmetic and differ by float rounding. At 2 the older one
## read the stored colour over W through the sRGB curve, whose linear toe and
## offset make that a different colour rather than a dimmer one, so its
## lightness and chroma were not the stored colour's. On a linear document the
## curve is a scale and the two agree again, to BOUND_LINEAR.
const BOUND_AT_ONE := 1e-4
const BOUND_AT_TWO := 0.05
const BOUND_LINEAR := 1e-3

## The bisection of today's gamut step, the kernel's own.
const GAMUT_EPSILON := 1e-5
const GAMUT_SEARCH_STEPS := 12

## Saved by the build before this row at version 4: a 64 by 64 sRGB document
## of a white Background, "Lightness under" at 0.5 in Lightness over it,
## "Sunset" at (3, 0.5, 0.2) in Normal, and "Lightness over" at 1.5 in
## Lightness on top. The windowed reading drew the top pixel a grey at the
## lightness of 1.5, since a lightness above 1 kept no chroma in the unit cube,
## and the reading now keeps the sunset's red at that lightness. Nothing in
## "Lightness under" meets a value above white.
const OLDER_FILE := "res://tests/data/lightness_over_a_sunset_v4.sad"


## Blends each pair of *pairs*, a source and a backdrop colour, through *mode*
## at reference white *white* on a document of *space*, and answers the stored
## colour of each.
func _blend(mode: String, pairs: Array, white: float, space: SaColorSpace) -> Array[Vector3]:
    var rd := GlobalShaderCompiler.get_rd()
    var src := PackedFloat32Array()
    var dst := PackedFloat32Array()
    src.resize(SIZE.x * SIZE.y * 4)
    dst.resize(SIZE.x * SIZE.y * 4)
    for i in pairs.size():
        var s: Vector3 = pairs[i][0]
        var d: Vector3 = pairs[i][1]
        for channel in 3:
            src[i * 4 + channel] = s[channel]
            dst[i * 4 + channel] = d[channel]
        src[i * 4 + 3] = 1.0
        dst[i * 4 + 3] = 1.0
    var canvas := SaTexture.new(SIZE)
    var chunk := SaTexture.new(SIZE)
    rd.texture_update(canvas.rid, 0, dst.to_byte_array())
    rd.texture_update(chunk.rid, 0, src.to_byte_array())
    var compute := SaCompute.new("composite")
    compute.set_texture(0, canvas.rid)
    compute.set_texture(1, chunk.rid)
    var region := Rect2i(Vector2i.ZERO, SIZE)
    compute.set_push_constant_float_array(SaCompute.pack_composite_params(Vector2.ZERO, 1.0, space, 0.0, white, region))
    compute.dispatch(GlobalShaderCompiler.get_kernel_index("composite", mode), GROUPS, GROUPS, 1)
    var data := rd.texture_get_data(canvas.rid, 0).to_float32_array()
    var out: Array[Vector3] = []
    for i in pairs.size():
        out.append(Vector3(data[i * 4], data[i * 4 + 1], data[i * 4 + 2]))
    return out


## Every colour whose channels take the *fractions* of *white*.
func _colours(fractions: Array[float], white: float) -> Array[Vector3]:
    var out: Array[Vector3] = []
    for r in fractions:
        for g in fractions:
            for b in fractions:
                out.append(Vector3(r, g, b) * white)
    return out


## Every pair of *colours* with itself, source first.
func _pairs(colours: Array[Vector3]) -> Array:
    var out := []
    for s in colours:
        for d in colours:
            out.append([s, d])
    return out


func _linear(c: Vector3, space: SaColorSpace) -> Vector3:
    return Vector3(space.transfer.decode(c.x), space.transfer.decode(c.y), space.transfer.decode(c.z))


func _encoded(c: Vector3, space: SaColorSpace) -> Vector3:
    return Vector3(space.transfer.encode(c.x), space.transfer.encode(c.y), space.transfer.encode(c.z))


## A stored colour of *space* in Oklab (L, a, b).
func _lab(c: Vector3, space: SaColorSpace) -> Vector3:
    return SaOklab.from_linear_srgb(_linear(c, space))


func _lch(c: Vector3, space: SaColorSpace) -> Vector3:
    return SaOklab.to_polar(_lab(c, space))


## The LCh *mode* gives a source *s* over a backdrop *d*, both in LCh.
func _swapped(mode: String, s: Vector3, d: Vector3) -> Vector3:
    match mode:
        "hue":
            return Vector3(d.x, d.y, s.z)
        "saturation":
            return Vector3(d.x, s.y, d.z)
        "color":
            return Vector3(d.x, s.y, s.z)
    return Vector3(s.x, d.y, d.z)


## Which input gives *mode* its hue, the source or the backdrop.
func _hue_from_source(mode: String) -> bool:
    return mode == "hue" or mode == "color"


func _in_cube(linear: Vector3, white: float, ceiling: float) -> bool:
    var low := minf(linear.x, minf(linear.y, linear.z))
    var high := maxf(linear.x, maxf(linear.y, linear.z))
    return low >= -GAMUT_EPSILON * white and high <= ceiling * (1.0 + GAMUT_EPSILON)


## The kernel's gamut step: chroma bisected until the colour is inside the cube
## whose top is *ceiling* in linear light, with the slack below zero of a
## window whose white is *white*, lightness and hue held.
func _into_cube(lch: Vector3, white: float, ceiling: float, space: SaColorSpace) -> Vector3:
    var linear := SaOklab.to_linear_srgb(SaOklab.from_polar(lch))
    if not _in_cube(linear, white, ceiling):
        var lo := 0.0
        var hi := lch.y
        linear = SaOklab.to_linear_srgb(SaOklab.from_polar(Vector3(lch.x, 0.0, lch.z)))
        for i in GAMUT_SEARCH_STEPS:
            var mid := 0.5 * (lo + hi)
            var probe := SaOklab.to_linear_srgb(SaOklab.from_polar(Vector3(lch.x, mid, lch.z)))
            if _in_cube(probe, white, ceiling):
                lo = mid
                linear = probe
            else:
                hi = mid
    return _encoded(linear, space)


## What *mode* drew for *s* over *d* before this row, through the window into
## the unit cube.
func _today(mode: String, s: Vector3, d: Vector3, white: float, space: SaColorSpace) -> Vector3:
    return _into_cube(_swapped(mode, _lch(s / white, space), _lch(d / white, space)), 1.0, 1.0, space) * white


## What *mode* draws for *s* over *d* now: the inputs as stored, into the cube
## up to W or to the brightest channel of the two in linear light.
func _now(mode: String, s: Vector3, d: Vector3, white: float, space: SaColorSpace) -> Vector3:
    var top := _linear(s, space).max(_linear(d, space))
    var linear_white := space.transfer.decode(white)
    var ceiling := maxf(linear_white, maxf(top.x, maxf(top.y, top.z)))
    return _into_cube(_swapped(mode, _lch(s, space), _lch(d, space)), linear_white, ceiling, space)


## The Oklab distance between two stored colours.
func _delta_e(a: Vector3, b: Vector3, space: SaColorSpace) -> float:
    return _lab(a, space).distance_to(_lab(b, space))


## The largest Oklab difference from today's result of *mode* over the grid
## from 0 to *white*, printed with the pair it is at.
func _worst_under_white(mode: String, white: float, space: SaColorSpace) -> float:
    var pairs := _pairs(_colours(UNDER, white))
    var got := _blend(mode, pairs, white, space)
    var worst := 0.0
    var at := 0
    for i in pairs.size():
        var difference := _delta_e(got[i], _today(mode, pairs[i][0], pairs[i][1], white, space), space)
        if difference > worst:
            worst = difference
            at = i
    var line := "m3: %s on %s at W = %s differs from today by %.6f at most" % [mode, space.id, white, worst]
    print("%s, %s over %s" % [line, pairs[at][0], pairs[at][1]])
    return worst


func test_up_to_white_each_mode_stays_within_its_measured_difference_from_today() -> void:
    var space := SaColorSpace.srgb()
    for white: float in [1.0, 2.0]:
        var bound := BOUND_AT_ONE if white == 1.0 else BOUND_AT_TWO
        for mode in MODES:
            var worst := _worst_under_white(mode, white, space)
            assert_true(worst <= bound, "%s at W = %s differs from today by %s at most, under %s" % [mode, white, worst, bound])


## The difference at W = 2 is the sRGB curve's, not the swap's: on a linear
## document dividing by W and multiplying back changes nothing the swap reads,
## since Oklab scales by a cube root, so the two readings agree.
func test_on_a_linear_document_the_readings_agree_at_twice_white() -> void:
    var space := SaColorSpace.linear_srgb()
    for mode in MODES:
        var worst := _worst_under_white(mode, 2.0, space)
        assert_true(worst <= BOUND_LINEAR, "%s on a linear document at W = 2 differs from today by %s at most" % [mode, worst])


## Whether *c* has its brightest channel at *white*, where the gamut step into
## the cube up to W held it. A channel under the brightest that lands near W
## does so by the colour it is, and is not held.
func _held_at(c: Vector3, white: float) -> bool:
    return absf(c[c.max_axis_index()] - white) <= 1e-4 * white


## Over inputs above W no channel is held at W, the lightness the mode takes
## survives whole, the hue it takes is kept and only chroma is lowered.
func test_above_white_no_channel_is_held_at_white_and_only_chroma_gives_way() -> void:
    var space := SaColorSpace.srgb()
    for white: float in [1.0, 2.0]:
        var pairs := _pairs(_colours(ABOVE, white))
        for mode in MODES:
            var got := _blend(mode, pairs, white, space)
            var read := 0
            var above := 0
            var held_today := 0
            var lowered := 0
            var problems: Array[String] = []
            for i in pairs.size():
                var s: Vector3 = pairs[i][0]
                var d: Vector3 = pairs[i][1]
                if maxf(s[s.max_axis_index()], d[d.max_axis_index()]) <= white:
                    continue
                read += 1
                var result: Vector3 = got[i]
                var today := _today(mode, s, d, white, space)
                if _held_at(today, white):
                    held_today += 1
                if _held_at(result, white):
                    problems.append("%s over %s held its brightest channel at W: %s" % [s, d, result])
                if result[result.max_axis_index()] > white * 1.001:
                    above += 1
                var taken := _swapped(mode, _lch(s, space), _lch(d, space))
                var lch := _lch(result, space)
                if absf(lch.x - taken.x) > 1e-3 * maxf(1.0, taken.x):
                    problems.append("%s over %s read L %s where it took %s" % [s, d, lch.x, taken.x])
                if lch.y > taken.y + 1e-3:
                    problems.append("%s over %s gained chroma, %s from %s" % [s, d, lch.y, taken.y])
                if lch.y < taken.y - 1e-3:
                    lowered += 1
                var hue_from: Vector3 = _lch(s, space) if _hue_from_source(mode) else _lch(d, space)
                if lch.y > 1e-2 and hue_from.y > 1e-2:
                    var turn := absf(wrapf(lch.z - taken.z, -PI, PI))
                    if turn > 1e-2:
                        problems.append("%s over %s turned its hue by %s" % [s, d, turn])
            var counted := "m3: %s at W = %s, %d pairs above white, %d held at W today" % [mode, white, read, held_today]
            print("%s, %d above W now, %d lowered in chroma, %d problems" % [counted, above, lowered, problems.size()])
            var reads := "%s at W = %s: the older reading held a channel at W, so the check reads something" % [mode, white]
            assert_true(held_today > 0, reads)
            assert_eq(problems.size(), 0, "%s at W = %s: %s" % [mode, white, "; ".join(problems.slice(0, 4))])


func test_lightness_of_four_times_white_over_a_grey_reads_a_lightness_above_one() -> void:
    var space := SaColorSpace.srgb()
    var source := Vector3(4.0, 4.0, 4.0)
    var grey := Vector3(0.5, 0.5, 0.5)
    var got := _blend("lightness", [[source, grey]], 1.0, space)
    var lightness := _lab(got[0], space).x
    print("m3: Lightness of %s over %s is %s, Oklab L %s" % [source, grey, got[0], lightness])
    assert_true(lightness > 1.0, "Lightness of four times white over a grey reads an Oklab L above 1")
    assert_almost_eq(lightness, _lab(source, space).x, 1e-3, "and it is the source's own")


func test_a_document_holding_a_component_mode_saves_at_its_stamp() -> void:
    for mode: StringName in [&"hue", &"saturation", &"color", &"lightness"]:
        var easel := SaEasel.create_default(Vector2i(64, 64))
        var doc := easel.document
        var stamp := SaSadFile.SAD_VERSION_OKLCH_ABOVE_WHITE
        assert_true(SaSadFile.version_for(doc) < stamp, "A document with no %s keeps the older stamp" % mode)
        SaLayerOps.new(doc).set_blend_mode(doc.active_layer, mode)
        assert_eq(SaSadFile.version_for(doc), stamp, "A %s layer stamps the file %d" % [mode, stamp])
        var path := SaDataRoot.path("m3_%s_saved_now.sad" % mode)
        assert_eq(SaExport.save_sad(doc, path), OK, "The document saves")
        assert_eq(SaSadFile.version_at(path), SaSadFile.SAD_VERSION_PLANES, "and reads back at the planes' stamp above it")
        assert_eq(SaSadFile.changed_since(doc, SaSadFile.version_at(path)), "", "and a file this build saved names nothing")
        DirAccess.remove_absolute(path)
        easel.free()


## The texel at (10, 10) of the document's composite.
func _composite_texel(doc: SaDocument) -> Vector3:
    var format: int = SaFieldSpec.schema_for_space(doc.color_space)[0].format
    var picture := SaTexture.new(SaDocument.WHOLE_CHUNK.size, format)
    doc.compositor.clear_scratch_batch([[picture, SaDocument.WHOLE_CHUNK]])
    SaTreeRender.new(doc).render(picture, Vector2i.ZERO)
    var data := GlobalShaderCompiler.get_rd().texture_get_data(picture.rid, 0).to_float32_array()
    var texel := (10 * SaDocument.WHOLE_CHUNK.size.x + 10) * 4
    return Vector3(data[texel], data[texel + 1], data[texel + 2])


func test_a_file_saved_before_opens_as_it_draws_now_and_names_the_layer_that_changed() -> void:
    var easel := SaEasel.create_default(Vector2i(64, 64))
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var doc := easel.document
    var version := SaSadFile.version_at(OLDER_FILE)
    assert_eq(version, 4, "The fixture was saved at version 4, before this row")
    assert_eq(SaExport.load_sad(doc, OLDER_FILE), OK, "The older file opens")

    var names: Array[String] = []
    for layer in SaOlderReading.changed(doc, version):
        names.append(String(layer.name))
    assert_eq(names, ["Lightness over"] as Array[String], "Only the Lightness layer over the sunset changed")
    var line := SaSadFile.changed_since(doc, version)
    assert_true(line.contains("'Lightness over'"), "The notice names the layer: %s" % line)
    assert_false(line.contains("Lightness under"), "and not the Lightness layer under white: %s" % line)

    var space := SaColorSpace.srgb()
    var source := Vector3(1.5, 1.5, 1.5)
    var sunset := Vector3(3.0, 0.5, 0.2)
    var got := _composite_texel(doc)
    var expected := _now("lightness", source, sunset, 1.0, space)
    var before := _today("lightness", source, sunset, 1.0, space)
    print("m3: the older file draws %s now, where it drew %s" % [got, before])
    assert_true(_delta_e(got, expected, space) < 1e-3, "The file draws the sunset's red at the lightness of 1.5 now, %s" % got)
    assert_true(got.x - got.z > 0.5, "and keeps its chroma, %s" % got)
    assert_true(before.x - before.z < 1e-3, "where it drew a grey, %s" % before)
    easel.free()


## A document of *space* at reference white *white* holding one layer in Hue
## at (0.2, 0.4, 0.6) over a backdrop at (0.6, 0.3, 0.1), all under white.
func _hue_under_white(space: SaColorSpace, white: float) -> SaEasel:
    var easel := SaEasel.create_default(Vector2i(64, 64), null, space)
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var doc := easel.document
    doc.blend_reference_white = white
    doc.fill_layer(Color(0.6, 0.3, 0.1, 1.0), doc.active_layer)
    var ops := SaLayerOps.new(doc)
    var layer := ops.add()
    layer.name = "Hue"
    ops.set_blend_mode(layer, &"hue")
    doc.fill_layer(Color(0.2, 0.4, 0.6, 1.0), layer)
    return easel


## Under white the older reading differs only on an RGB document whose white
## is not 1, so the probe names the layer there and nowhere else.
func test_a_component_layer_under_white_is_named_only_where_white_is_not_one() -> void:
    var cases := [[SaColorSpace.srgb(), 1.0, false], [SaColorSpace.srgb(), 2.0, true], [SaColorSpace.oklab(), 2.0, false]]
    for case: Array in cases:
        var space: SaColorSpace = case[0]
        var white: float = case[1]
        var easel := _hue_under_white(space, white)
        var named := SaOlderReading.changed(easel.document, SaSadFile.SAD_VERSION_PLAIN).size() == 1
        assert_eq(named, case[2], "A Hue layer under white on %s at W = %s is named: %s" % [space.id, white, case[2]])
        easel.free()
