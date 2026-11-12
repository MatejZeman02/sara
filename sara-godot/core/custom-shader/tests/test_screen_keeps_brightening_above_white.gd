## Screen above white: the formula itself wherever both inputs are
## at or under the document's blend reference white W, and above it a result
## continuous at W, no darker than the brighter input and rising with each
## input, so a sun screened over a sky stays a sun. Then a file saved before,
## which opens as it draws now and names the layer whose picture changed.
##
## The kernel runs over a grid of pairs in one dispatch, a pair to a texel, and
## every expectation is computed here in double precision.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const SIZE := Vector2i(32, 32)

## 32 / 8, the [numthreads(8, 8, 1)] the composite kernels declare.
const GROUPS: int = 4

## Screen's index in the order composite.gmacs declares its kernels.
const KERNEL_SCREEN := 2

## Saved by the build before this row at version 4: a 64 by 64 sRGB document
## of a white Background, "Screen under" at 0.5 in Screen over it, "Twice
## white" at 2.0 in Normal, and "Screen over" at 0.5 in Screen on top. The
## formula drew the top pixel 0.5 + 2 - 0.5 * 2 = 1.5, and the extension draws
## it 0.5 + 2 - 0.5 * share(2) = 2.25, the share of 2 being 1 / (1 + 1). Nothing
## in "Screen under" meets a value above white.
const OLDER_FILE := "res://tests/data/screen_over_twice_white_v4.sad"

## The steps of the grid under white, and how far above white it goes.
const STEPS := 8
const ABOVE := [1.0, 1.25, 1.5, 2.0, 3.0, 4.0, 8.0, 40.0]

## How close to W a value counts as just under or just over it.
const NEAR := 1e-3


## Screens each pair of *pairs*, a `Vector2(src, dst)` to a texel and the same
## value in every channel, at reference white *white*, and answers the stored
## colour of each.
func _screen(pairs: Array[Vector2], white: float) -> Array[Color]:
    var rd := GlobalShaderCompiler.get_rd()
    var src := PackedFloat32Array()
    var dst := PackedFloat32Array()
    src.resize(SIZE.x * SIZE.y * 4)
    dst.resize(SIZE.x * SIZE.y * 4)
    for i in pairs.size():
        for channel in 3:
            src[i * 4 + channel] = pairs[i].x
            dst[i * 4 + channel] = pairs[i].y
        src[i * 4 + 3] = 1.0
        dst[i * 4 + 3] = 1.0
    var canvas := SaTexture.new(SIZE)
    var chunk := SaTexture.new(SIZE)
    rd.texture_update(canvas.rid, 0, dst.to_byte_array())
    rd.texture_update(chunk.rid, 0, src.to_byte_array())
    var compute := SaCompute.new("composite")
    compute.set_texture(0, canvas.rid)
    compute.set_texture(1, chunk.rid)
    compute.set_push_constant_float_array(SaCompute.pack_composite_params(Vector2.ZERO, 1.0, null, 0.0, white))
    compute.dispatch(KERNEL_SCREEN, GROUPS, GROUPS, 1)
    var data := rd.texture_get_data(canvas.rid, 0).to_float32_array()
    var out: Array[Color] = []
    for i in pairs.size():
        out.append(Color(data[i * 4], data[i * 4 + 1], data[i * 4 + 2], data[i * 4 + 3]))
    return out


## The values from 0 to *white* in STEPS steps.
func _under(white: float) -> Array[float]:
    var out: Array[float] = []
    for step in STEPS + 1:
        out.append(white * step / STEPS)
    return out


## The values from *white* up, ABOVE times it.
func _above(white: float) -> Array[float]:
    var out: Array[float] = []
    for times: float in ABOVE:
        out.append(white * times)
    return out


## Every pair of *values* with itself.
func _pairs(values: Array[float]) -> Array[Vector2]:
    var out: Array[Vector2] = []
    for s in values:
        for d in values:
            out.append(Vector2(s, d))
    return out


func test_at_or_under_white_screen_is_the_formula() -> void:
    for white: float in [1.0, 2.0]:
        var pairs := _pairs(_under(white))
        var got := _screen(pairs, white)
        for i in pairs.size():
            var s := pairs[i].x / white
            var d := pairs[i].y / white
            var expected := white * (1.0 - (1.0 - s) * (1.0 - d))
            assert_almost_eq(
                got[i].r, expected, 1e-5, "Screen(%s, %s) at W = %s is the formula" % [pairs[i].x, pairs[i].y, white]
            )


## Each input in turn steps over W from just under it, against every value of
## the other input from 0 to well above white.
func test_above_white_screen_is_continuous_with_just_under_white() -> void:
    for white: float in [1.0, 2.0]:
        var others: Array[float] = _under(white)
        others.append_array(_above(white))
        var pairs: Array[Vector2] = []
        for other in others:
            pairs.append(Vector2(white * (1.0 - NEAR), other))
            pairs.append(Vector2(white * (1.0 + NEAR), other))
            pairs.append(Vector2(other, white * (1.0 - NEAR)))
            pairs.append(Vector2(other, white * (1.0 + NEAR)))
        var got := _screen(pairs, white)
        for i in range(0, pairs.size(), 2):
            var jump := absf(got[i + 1].r - got[i].r)
            assert_true(
                jump <= 2.0 * NEAR * white + 1e-5,
                (
                    "Screen steps %s from (%s, %s) to (%s, %s) at W = %s"
                    % [jump, pairs[i].x, pairs[i].y, pairs[i + 1].x, pairs[i + 1].y, white]
                )
            )


func test_above_white_screen_is_no_darker_than_the_brighter_input() -> void:
    for white: float in [1.0, 2.0]:
        var values: Array[float] = _under(white)
        values.append_array(_above(white))
        var pairs := _pairs(values)
        var got := _screen(pairs, white)
        for i in pairs.size():
            var brighter := maxf(pairs[i].x, pairs[i].y)
            assert_true(
                got[i].r >= brighter - 1e-5,
                "Screen(%s, %s) at W = %s is %s, under %s" % [pairs[i].x, pairs[i].y, white, got[i].r, brighter]
            )


## Above white an input brightens the result with every step, whatever the
## other input is.
func test_above_white_screen_rises_with_each_input() -> void:
    for white: float in [1.0, 2.0]:
        var others: Array[float] = _under(white)
        others.append_array(_above(white))
        var above := _above(white)
        var pairs: Array[Vector2] = []
        for other in others:
            for value in above:
                pairs.append(Vector2(value, other))
            for value in above:
                pairs.append(Vector2(other, value))
        var got := _screen(pairs, white)
        for i in pairs.size():
            if i % above.size() == 0:
                continue
            assert_true(
                got[i].r > got[i - 1].r,
                (
                    "Screen rises from (%s, %s) to (%s, %s) at W = %s: %s then %s"
                    % [pairs[i - 1].x, pairs[i - 1].y, pairs[i].x, pairs[i].y, white, got[i - 1].r, got[i].r]
                )
            )


## With the other input above white, every step of an input brightens the
## result, from 0 through white and on: the overlap the formula takes away
## fades as the other climbs, so no stretch of either input is flat.
func test_with_the_other_above_white_every_step_of_an_input_brightens() -> void:
    for white: float in [1.0, 2.0]:
        var values: Array[float] = _under(white)
        values.append_array(_above(white).slice(1))
        var pairs: Array[Vector2] = []
        for other: float in _above(white).slice(1):
            for value in values:
                pairs.append(Vector2(value, other))
            for value in values:
                pairs.append(Vector2(other, value))
        var got := _screen(pairs, white)
        for i in pairs.size():
            if i % values.size() == 0:
                continue
            assert_true(
                got[i].r > got[i - 1].r,
                (
                    "Screen rises from (%s, %s) to (%s, %s) at W = %s: %s then %s"
                    % [pairs[i - 1].x, pairs[i - 1].y, pairs[i].x, pairs[i].y, white, got[i - 1].r, got[i].r]
                )
            )


## The spec's own example: a source of 40 over a sky of 0.5 stays a sun with
## the sky added, where the formula alone drew 40 + 0.5 - 40 * 0.5 = 20.5.
func test_a_sun_screened_over_a_sky_stays_a_sun() -> void:
    var got := _screen([Vector2(40.0, 0.5)] as Array[Vector2], 1.0)
    var expected := 40.0 + 0.5 - 0.5 / (1.0 + 39.0 * 39.0)
    assert_almost_eq(got[0].r, expected, 1e-4, "40 screened over 0.5 is 40 + 0.5 less the sky's overlap with a share of 1 / 1522")


func test_a_document_holding_screen_saves_at_the_stamp_above_white() -> void:
    var easel := SaEasel.create_default(Vector2i(64, 64))
    var doc := easel.document
    var plain := SaSadFile.version_for(doc)
    assert_true(plain < SaSadFile.SAD_VERSION_ABOVE_WHITE, "A document with no Screen keeps the older stamp, %d" % plain)
    doc.active_layer.blend_mode = SaLayer.BLEND_MODE.SCREEN
    assert_eq(SaSadFile.version_for(doc), SaSadFile.SAD_VERSION_ABOVE_WHITE, "A Screen layer stamps the file 10")
    var path := SaDataRoot.path("m1_screen_saved_now.sad")
    assert_eq(SaExport.save_sad(doc, path), OK, "The document saves")
    assert_eq(SaSadFile.version_at(path), SaSadFile.SAD_VERSION_PLANES, "and reads back as 14, for its planes")
    assert_eq(SaSadFile.changed_since(doc, SaSadFile.version_at(path)), "", "and a file this build saved names nothing")
    DirAccess.remove_absolute(path)
    easel.free()


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
    assert_eq(names, ["Screen over"] as Array[String], "Only the Screen layer over twice white changed")
    var line := SaSadFile.changed_since(doc, version)
    assert_true(line.contains("'Screen over'"), "The notice names the layer: %s" % line)
    assert_false(line.contains("Screen under"), "and not the Screen layer under white: %s" % line)

    var format: int = SaFieldSpec.schema_for_space(doc.color_space)[0].format
    var picture := SaTexture.new(SaDocument.WHOLE_CHUNK.size, format)
    doc.compositor.clear_scratch_batch([[picture, SaDocument.WHOLE_CHUNK]])
    SaTreeRender.new(doc).render(picture, Vector2i.ZERO)
    var data := GlobalShaderCompiler.get_rd().texture_get_data(picture.rid, 0).to_float32_array()
    var texel := (10 * SaDocument.WHOLE_CHUNK.size.x + 10) * 4
    assert_almost_eq(data[texel], 2.25, 1e-4, "The file draws 0.5 screened over 2.0 as 2.25 now, where it drew 1.5")
    easel.free()
