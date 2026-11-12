## Overlay, Soft Light, Hard Light, Colour Dodge, Exclusion and Hard Mix above
## white: each the formula itself wherever both inputs are at or under the
## document's blend reference white W, and above it a result continuous at W
## and rising with each input above white, so a layer painted above white over
## a grey never draws below what the same mode draws at white. Then the stamp,
## which tells a file that drew these by the formula alone from one that drew
## only Screen the new way.
##
## Each kernel runs over a grid of pairs in one dispatch, a pair to a texel,
## and every expectation is computed here in double precision.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const SIZE := Vector2i(32, 32)

## 32 / 8, the [numthreads(8, 8, 1)] the composite kernels declare.
const GROUPS: int = 4

## The kernel of each mode, in its shader. Hard Mix was a module's kernel once
## and is the skeleton's now, a formula of `libs/composite_blend_modes.gmacs`
## like the other five.
const MODES: Array[Array] = [
    ["composite", "overlay"],
    ["composite", "soft_light"],
    ["composite", "hard_light"],
    ["composite", "color_dodge"],
    ["composite", "exclusion"],
    ["composite", "hard_mix"],
]

## The steps of the grid under white, and how far above white it goes.
const STEPS := 8
const ABOVE := [1.0, 1.25, 1.5, 2.0, 3.0, 4.0, 8.0, 40.0]

## How close to W a value counts as just under or just over it.
const NEAR := 1e-3

## What each mode draws of a source at four times white over a grey of 0.5, the
## scenario's picture, at W = 1. Overlay and Hard Light are the source itself,
## because the grey is neutral to both: overlay(share, 0.5) is the share, and
## the remainder is the rest of the source. Soft Light is 0.3 from its formula
## on the share 0.1 and the grey, and 3.9 above it. Exclusion is
## 4 + 0.5 - 2 * 0.1 * 0.5. Colour Dodge and Hard Mix read the source at white,
## so they draw 1 and the 3 above it.
const FOUR_OVER_GREY := {
    "overlay": 4.0,
    "soft_light": 4.2,
    "hard_light": 4.0,
    "color_dodge": 4.0,
    "exclusion": 4.4,
    "hard_mix": 4.0,
}


## Composites each pair of *pairs*, a `Vector2(src, dst)` to a texel and the
## same value in every channel, through *kernel* of *shader* at reference white
## *white*, and answers the stored colour of each.
func _blend(shader: String, kernel: String, pairs: Array[Vector2], white: float) -> Array[Color]:
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
    var compute := SaCompute.new(shader)
    compute.set_texture(0, canvas.rid)
    compute.set_texture(1, chunk.rid)
    compute.set_push_constant_float_array(SaCompute.pack_composite_params(Vector2.ZERO, 1.0, null, 0.0, white))
    compute.dispatch_kernel(kernel, GROUPS, GROUPS, 1)
    var data := rd.texture_get_data(canvas.rid, 0).to_float32_array()
    var out: Array[Color] = []
    for i in pairs.size():
        out.append(Color(data[i * 4], data[i * 4 + 1], data[i * 4 + 2], data[i * 4 + 3]))
    return out


## The W3C formula of *kernel* on a source *s* and a backdrop *d* in 0 to 1,
## written the way `libs/composite_blend_modes.gmacs` writes it.
static func _formula(kernel: String, s: float, d: float) -> float:
    match kernel:
        "overlay":
            return 1.0 - 2.0 * (1.0 - s) * (1.0 - d) if d >= 0.5 else 2.0 * s * d
        "hard_light":
            return 1.0 - 2.0 * (1.0 - s) * (1.0 - d) if s >= 0.5 else 2.0 * s * d
        "soft_light":
            var lift := sqrt(d) if d >= 0.25 else ((16.0 * d - 12.0) * d + 4.0) * d
            return d + (2.0 * s - 1.0) * (lift - d) if s >= 0.5 else d - (1.0 - 2.0 * s) * d * (1.0 - d)
        "color_dodge":
            return 0.0 if d <= 0.0 else clampf(d / maxf(1.0 - s, 1e-6), 0.0, 1.0)
        "exclusion":
            return d + s - 2.0 * d * s
        "hard_mix":
            return 1.0 if s + d >= 1.0 else 0.0
    return NAN


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


func test_at_or_under_white_each_mode_is_its_formula() -> void:
    for mode: Array in MODES:
        for white: float in [1.0, 2.0]:
            var pairs := _pairs(_under(white))
            var got := _blend(mode[0], mode[1], pairs, white)
            for i in pairs.size():
                var expected := white * _formula(mode[1], pairs[i].x / white, pairs[i].y / white)
                assert_almost_eq(
                    got[i].r, expected, 1e-5, "%s(%s, %s) at W = %s is the formula" % [mode[1], pairs[i].x, pairs[i].y, white]
                )


## Each input in turn steps from W to just above it, against every value of
## the other input from 0 to forty times white. The share of white has no
## slope at W, so leaving the window moves a result by the step itself and no
## more, whichever mode it is.
func test_just_above_white_each_mode_is_continuous_with_its_result_at_white() -> void:
    for mode: Array in MODES:
        for white: float in [1.0, 2.0]:
            var others: Array[float] = _under(white)
            others.append_array(_above(white))
            var pairs: Array[Vector2] = []
            for other in others:
                pairs.append(Vector2(white, other))
                pairs.append(Vector2(white * (1.0 + NEAR), other))
                pairs.append(Vector2(other, white))
                pairs.append(Vector2(other, white * (1.0 + NEAR)))
            var got := _blend(mode[0], mode[1], pairs, white)
            for i in range(0, pairs.size(), 2):
                var jump := absf(got[i + 1].r - got[i].r)
                assert_true(
                    jump <= 1.01 * NEAR * white + 1e-5,
                    (
                        "%s steps %s from (%s, %s) to (%s, %s) at W = %s"
                        % [mode[1], jump, pairs[i].x, pairs[i].y, pairs[i + 1].x, pairs[i + 1].y, white]
                    )
                )


## The same step from just under W to just over it. The formulas of Overlay,
## Soft Light, Hard Light and Exclusion climb at most twice as fast as their
## input under white, and the extension as fast as it just above, so the
## result moves at most three times NEAR * W across the step.
## Colour Dodge's source and Hard Mix's two inputs are left to the case below:
## the dodge's quotient is as steep as 1 / (1 - s)^2 just under white, and
## Hard Mix steps from 0 to 1 where s + d reaches W, the corner (W, 0), both
## the formula's own and under white, where the extension changes nothing.
func test_across_white_the_formulas_with_a_bounded_slope_are_continuous() -> void:
    for mode: Array in MODES:
        if mode[1] == "hard_mix":
            continue
        for white: float in [1.0, 2.0]:
            var others: Array[float] = _under(white)
            others.append_array(_above(white))
            var pairs: Array[Vector2] = []
            for other in others:
                if mode[1] != "color_dodge":
                    pairs.append(Vector2(white * (1.0 - NEAR), other))
                    pairs.append(Vector2(white * (1.0 + NEAR), other))
                pairs.append(Vector2(other, white * (1.0 - NEAR)))
                pairs.append(Vector2(other, white * (1.0 + NEAR)))
            var got := _blend(mode[0], mode[1], pairs, white)
            for i in range(0, pairs.size(), 2):
                var jump := absf(got[i + 1].r - got[i].r)
                assert_true(
                    jump <= 3.01 * NEAR * white + 1e-5,
                    (
                        "%s steps %s from (%s, %s) to (%s, %s) at W = %s"
                        % [mode[1], jump, pairs[i].x, pairs[i].y, pairs[i + 1].x, pairs[i + 1].y, white]
                    )
                )


## Colour Dodge's source and Hard Mix's two inputs across white, off the
## formulas' own steps. The dodge's quotient has already reached its clamp a
## ten-thousandth under white over every backdrop of the grid but black,
## since the least backdrop share there is 1 / 1522, and over black it is 0,
## so the step is that close. Hard Mix's threshold sits at W only where the
## other input is 0, so that one value is left out and the rest cross at NEAR.
func test_across_white_dodges_source_and_hard_mixs_inputs_are_continuous() -> void:
    for mode: Array in MODES:
        if mode[1] != "color_dodge" and mode[1] != "hard_mix":
            continue
        var near := 1e-4 if mode[1] == "color_dodge" else NEAR
        for white: float in [1.0, 2.0]:
            var others: Array[float] = _under(white)
            others.append_array(_above(white))
            var pairs: Array[Vector2] = []
            for other in others:
                if other == 0.0 and mode[1] == "hard_mix":
                    continue
                pairs.append(Vector2(white * (1.0 - near), other))
                pairs.append(Vector2(white * (1.0 + near), other))
                if mode[1] == "hard_mix":
                    pairs.append(Vector2(other, white * (1.0 - near)))
                    pairs.append(Vector2(other, white * (1.0 + near)))
            var got := _blend(mode[0], mode[1], pairs, white)
            for i in range(0, pairs.size(), 2):
                var jump := absf(got[i + 1].r - got[i].r)
                assert_true(
                    jump <= 2.01 * near * white + 2e-5,
                    (
                        "%s steps %s from (%s, %s) to (%s, %s) at W = %s"
                        % [mode[1], jump, pairs[i].x, pairs[i].y, pairs[i + 1].x, pairs[i + 1].y, white]
                    )
                )


## Above white an input brightens the result with every step, whatever the
## other input is, for all six: the input above white is the one that
## brightens, whichever it brightens under white.
func test_above_white_each_mode_rises_with_each_input() -> void:
    for mode: Array in MODES:
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
            var got := _blend(mode[0], mode[1], pairs, white)
            for i in pairs.size():
                if i % above.size() == 0:
                    continue
                assert_true(
                    got[i].r > got[i - 1].r,
                    (
                        "%s rises from (%s, %s) to (%s, %s) at W = %s: %s then %s"
                        % [mode[1], pairs[i - 1].x, pairs[i - 1].y, pairs[i].x, pairs[i].y, white, got[i - 1].r, got[i].r]
                    )
                )


## The scenario's picture in numbers: a source above white over a grey never
## draws below what the same mode draws at white, and four times white draws
## what the Done paragraph says.
func test_a_source_above_white_over_a_grey_is_no_darker_than_at_white() -> void:
    for mode: Array in MODES:
        var pairs: Array[Vector2] = []
        for value in _above(1.0):
            pairs.append(Vector2(value, 0.5))
        var got := _blend(mode[0], mode[1], pairs, 1.0)
        for i in pairs.size():
            assert_true(
                got[i].r >= got[0].r - 1e-6,
                "%s of %s over grey is %s, under %s at white" % [mode[1], pairs[i].x, got[i].r, got[0].r]
            )
        assert_almost_eq(got[ABOVE.find(4.0)].r, FOUR_OVER_GREY[mode[1]], 1e-5, "%s of 4 over 0.5" % mode[1])


## Colour Dodge's source cannot take Screen's share of white, and this is the
## pair that showed it: on the share the quotient left the clamp just above
## white, and 1.1 over 0.001 drew 0.21 where white drew 1. Read as white past
## it, the source draws itself.
func test_a_dodge_source_just_above_white_over_a_dark_backdrop_draws_itself() -> void:
    var got := _blend("composite", "color_dodge", [Vector2(1.0, 0.001), Vector2(1.1, 0.001)] as Array[Vector2], 1.0)
    assert_almost_eq(got[0].r, 1.0, 1e-6, "White dodges 0.001 to white")
    assert_almost_eq(got[1].r, 1.1, 1e-5, "and 1.1 dodges it to 1.1, the source itself")


func test_each_of_the_six_saves_at_the_stamp_after_screens() -> void:
    for mode: Array in MODES:
        var easel := SaEasel.create_default(Vector2i(64, 64))
        var doc := easel.document
        doc.active_layer.blend_mode = StringName(mode[1])
        assert_eq(
            SaSadFile.version_for(doc),
            SaSadFile.SAD_VERSION_SEPARABLE_ABOVE_WHITE,
            "A layer in %s stamps the file %d" % [mode[1], SaSadFile.SAD_VERSION_SEPARABLE_ABOVE_WHITE]
        )
        easel.free()
    assert_true(
        SaSadFile.SAD_VERSION_SEPARABLE_ABOVE_WHITE > SaSadFile.SAD_VERSION_ABOVE_WHITE,
        "a version after Screen's, so a file at Screen's is known to have drawn these by the formula alone"
    )


## A file that a build between the two stamps saved: Screen drawn the new way
## and Overlay by its formula. The words of the file are the same at 10 and
## 11, so the fixture is a save made now with its version word put back to 10,
## which is what that build wrote for a document whose only extended mode was
## Screen. Both layers sit over twice white, so either would be named by a
## file older than Screen's stamp, and only Overlay by one at it.
func test_a_file_saved_at_screens_stamp_names_the_overlay_layer_and_not_the_screen_one() -> void:
    var easel := SaEasel.create_default(Vector2i(64, 64))
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var doc := easel.document
    var ops := SaLayerOps.new(doc)
    var bright := ops.add()
    bright.name = "Twice white"
    bright.fill(Color(2.0, 2.0, 2.0, 1.0))
    for named: Array in [["Screen over", &"screen"], ["Overlay over", &"overlay"]]:
        var layer := ops.add()
        layer.name = named[0]
        layer.fill(Color(0.5, 0.5, 0.5, 1.0))
        layer.blend_mode = named[1]
    var path := SaDataRoot.path("m2_overlay_saved_at_screens_stamp.sad")
    assert_eq(SaExport.save_sad(doc, path), OK, "The document saves")
    assert_eq(SaSadFile.version_at(path), SaSadFile.SAD_VERSION_PLANES, "at 14, for its planes above its Overlay layer's 11")
    var file := FileAccess.open(path, FileAccess.READ_WRITE)
    file.seek(4)
    file.store_32(SaSadFile.SAD_VERSION_ABOVE_WHITE)
    file.close()
    var version := SaSadFile.version_at(path)
    assert_eq(version, SaSadFile.SAD_VERSION_ABOVE_WHITE, "and the fixture reads as Screen's stamp")

    var opened := SaEasel.create_default(Vector2i(64, 64))
    opened.compositor.set_registry(Fixtures.make_registries().blend_modes)
    assert_eq(SaExport.load_sad(opened.document, path), OK, "The file opens")
    assert_eq(_named(opened.document, version), ["Overlay over"] as Array[String], "Only Overlay changed since 10")
    assert_eq(
        _named(opened.document, SaSadFile.SAD_VERSION_PLAIN),
        ["Screen over", "Overlay over"] as Array[String],
        "both since 4, before Screen's stamp"
    )
    assert_eq(_named(opened.document, SaSadFile.SAD_VERSION_SEPARABLE_ABOVE_WHITE), [] as Array[String], "and none at 11")
    var line := SaSadFile.changed_since(opened.document, version)
    assert_true(line.contains("'Overlay over'"), "The notice names the Overlay layer: %s" % line)
    assert_false(line.contains("Screen over"), "and not the Screen one: %s" % line)
    DirAccess.remove_absolute(path)
    opened.free()
    easel.free()


## The names of the layers of *doc* that SaOlderReading finds changed since a
## file of *version*.
func _named(doc: SaDocument, version: int) -> Array[String]:
    var names: Array[String] = []
    for layer in SaOlderReading.changed(doc, version):
        names.append(String(layer.name))
    return names
