## The Display page's gamut preview, and the cusp maths under it.
##
## `ui/color_space/tests/test_display_curve.gd` beside this keeps the curve plot honest against
## the shader it transcribes. This widget transcribes nothing, so what is worth
## asserting is different: that the texture is in a format the operator can work
## in, that the material is the canvas tonemapper itself rather than a copy, and
## that the cusp loop landed on the cube's real corners rather than on the ones
## a bisection in Oklab finds.
extends "res://tests/test_framework.gd"

const SHADER_PATH := "res://shaders/canvas/tonemap.gdshader"

## Coarse enough to run in a test, fine enough that every column holds a sample.
const COLUMNS := 240

## The six saturated corners of the RGB cube, in light-linear sRGB. Every one of
## them is a cusp by definition, so its own hue column has to hold it exactly.
const CORNERS: Array[Vector3] = [
    Vector3(1, 0, 0),
    Vector3(1, 1, 0),
    Vector3(0, 1, 0),
    Vector3(0, 1, 1),
    Vector3(0, 0, 1),
    Vector3(1, 0, 1),
]

## Pure blue's cusp, the one the guide warns about. A ray of constant lightness
## towards blue leaves the RGB cube by 0.0007 and comes back, so a bisection in
## chroma stops on the near branch at about 0.287. The cube edge itself carries
## 0.313, and that is what a correct loop returns.
const NEAR_BRANCH_CHROMA := 0.29


func _cusps() -> PackedVector3Array:
    return SaOklab.gamut_cusps(COLUMNS)


func _column_of(hue: float) -> int:
    return int(fposmod(hue, TAU) * float(COLUMNS) / TAU) % COLUMNS


## The trap the build guide spent an afternoon on. The column a cube corner
## falls in has to hold a colour at least as saturated as that corner: blue's
## holding about 0.287 rather than 0.313 means the loop was replaced by a search
## and pure blue was cut out of the picture.
##
## At least as saturated, rather than exactly. Red, green, blue and magenta are
## the chroma maximum of their own Oklab hue and come back to four decimal
## places, but yellow and cyan are not. Chroma keeps rising for about 1.2
## degrees past each of them along the edge towards green, to 0.2120 against
## yellow's 0.2110 and 0.1548 against cyan's 0.1545, and a column is 1.5 degrees
## wide, so the maximum in the column is that slightly greener colour. A cube
## corner is a corner of the cube, not a peak of Oklab chroma.
func test_every_cube_corner_is_reached_by_its_own_hue_column() -> void:
    var cusps := _cusps()
    var column_width := TAU / float(COLUMNS)
    for corner: Vector3 in CORNERS:
        var polar := SaOklab.to_polar(SaOklab.from_linear_srgb(corner))
        var cusp := cusps[_column_of(polar.z)]
        var where := "corner %v" % corner
        assert_true(cusp.y >= polar.y - 1e-6, "%s, chroma %.4f under %.4f" % [where, cusp.y, polar.y])
        assert_true(cusp.y <= polar.y + 0.002, "%s, chroma %.4f far over %.4f" % [where, cusp.y, polar.y])
        var drift: float = absf(cusp.z - fposmod(polar.z, TAU))
        assert_true(drift <= column_width, "%s, hue %.4f is outside its own column" % [where, cusp.z])


## And blue's number said the other way round, because this is the one an
## otherwise reasonable implementation gets wrong.
func test_blues_cusp_is_not_the_near_branch() -> void:
    var cusps := _cusps()
    var blue := SaOklab.to_polar(SaOklab.from_linear_srgb(Vector3(0, 0, 1)))
    var cusp := cusps[_column_of(blue.z)]
    assert_true(cusp.y > NEAR_BRANCH_CHROMA, "blue's cusp chroma is %.4f, the near branch" % cusp.y)


## Every cusp is on the boundary from both sides: the colour itself is inside
## the cube, and a little more chroma at its own hue and lightness is outside
## it. That is what makes it a corner rather than a point somewhere under one.
func test_every_cusp_sits_on_the_gamut_boundary() -> void:
    for cusp: Vector3 in _cusps():
        var cos_hue := cos(cusp.z)
        var sin_hue := sin(cusp.z)
        var at := SaOklab.to_linear_srgb(Vector3(cusp.x, cusp.y * cos_hue, cusp.y * sin_hue))
        assert_true(SaOklab.gamut_overshoot(at) <= 1e-6, "a cusp at hue %.4f is outside the cube" % cusp.z)
        var beyond := Vector3(cusp.x, (cusp.y + 0.01) * cos_hue, (cusp.y + 0.01) * sin_hue)
        assert_true(
            SaOklab.gamut_overshoot(SaOklab.to_linear_srgb(beyond)) > 0.0, "a cusp at hue %.4f has chroma left above it" % cusp.z
        )


## The bisection the picture rides between white and the cusp. It is sound in
## lightness where it is not in chroma, and this is the property that makes it
## so: the answer is in gamut and a step above it is not.
func test_max_lightness_lands_on_the_upper_boundary() -> void:
    for cusp: Vector3 in _cusps():
        var cos_hue := cos(cusp.z)
        var sin_hue := sin(cusp.z)
        for fraction: float in [0.25, 0.6, 0.9]:
            var chroma := cusp.y * fraction
            var lightness := SaOklab.max_lightness(chroma, cusp.z, cusp.x)
            var at := SaOklab.to_linear_srgb(Vector3(lightness, chroma * cos_hue, chroma * sin_hue))
            assert_true(SaOklab.gamut_overshoot(at) <= 1e-6, "hue %.4f, chroma %.4f is outside" % [cusp.z, chroma])
            var above := Vector3(lightness + 0.01, chroma * cos_hue, chroma * sin_hue)
            assert_true(
                SaOklab.gamut_overshoot(SaOklab.to_linear_srgb(above)) > 0.0,
                "hue %.4f, chroma %.4f stopped short of the boundary" % [cusp.z, chroma]
            )
            assert_true(lightness >= cusp.x, "hue %.4f fell below its own cusp" % cusp.z)


## Half-float, never 8-bit. Eight bits clamp at 1.0 and the roll-off then has
## nothing above the knee to work on, which is the failure that looks like a
## working widget until someone drags the Knee slider.
func test_the_picture_is_a_float_format() -> void:
    var image := SaGamutPreview.build_image(Vector2i(64, 24))
    assert_eq(image.get_format(), Image.FORMAT_RGBAH, "the picture is not half-float")


## And it is baked above white, which is the whole reason for the stored 3.0.
## A picture topping out at 1.0 barely moves as the sliders drag.
func test_the_picture_holds_values_above_white() -> void:
    var image := SaGamutPreview.build_image(Vector2i(64, 24))
    var brightest := 0.0
    for y in image.get_height():
        for x in image.get_width():
            var texel := image.get_pixel(x, y)
            brightest = maxf(brightest, maxf(texel.r, maxf(texel.g, texel.b)))
    assert_true(brightest > 1.0, "the brightest texel is %.3f, so nothing is above white" % brightest)


## The bottom row is every hue's cusp and the top row is white where the widest
## hue runs out, which is the geometry `scripts/gen_gamut_images.py` describes.
## A picture drawn upside down passes every other assertion here.
func test_white_is_at_the_top_and_colour_at_the_bottom() -> void:
    var image := SaGamutPreview.build_image(Vector2i(64, 24))
    var curve := SaTransferFunction.srgb()
    var white := curve.encode(SaGamutPreview.STORED_SCALE)
    var top := image.get_pixel(0, 0)
    assert_almost_eq(top.r, white, 1e-3, "the top row is not white")
    assert_almost_eq(top.g, white, 1e-3, "the top row is not white")
    assert_almost_eq(top.b, white, 1e-3, "the top row is not white")
    var bottom := image.get_pixel(0, image.get_height() - 1)
    var spread := maxf(bottom.r, maxf(bottom.g, bottom.b)) - minf(bottom.r, minf(bottom.g, bottom.b))
    assert_true(spread > 0.1, "the bottom row is not coloured, spread %.3f" % spread)


## The bottom row is the cube's own saturated edge loop, which is what a cusp
## is: one channel at 1 and another at 0. Dividing by `STORED_SCALE` here is
## exactly what the reference half's `display_exposure` does in the shader, so
## this doubles as the reading of what that half puts on screen. It is the assertion the committed
## `tests/data/oklch_gamut_srgb.png` would otherwise be needed for, and it is
## exact where a comparison against that picture is not, because its 2048
## columns and this one's 240 disagree by a lot wherever the loop doubles back.
func test_the_bottom_row_rides_the_cubes_saturated_edge() -> void:
    var image := SaGamutPreview.build_image(Vector2i(120, 8))
    var curve := SaTransferFunction.srgb()
    var bottom := image.get_height() - 1
    for x in image.get_width():
        var texel := image.get_pixel(x, bottom)
        var linear := Vector3(curve.decode(texel.r), curve.decode(texel.g), curve.decode(texel.b))
        linear /= SaGamutPreview.STORED_SCALE
        var high: float = maxf(linear.x, maxf(linear.y, linear.z))
        var low: float = minf(linear.x, minf(linear.y, linear.z))
        assert_almost_eq(high, 1.0, 0.01, "column %d tops out at %.3f, not on an edge" % [x, high])
        assert_almost_eq(low, 0.0, 0.01, "column %d floors at %.3f, not on an edge" % [x, low])


## The material is the canvas operator itself. A widget that grew its own shader
## is the one thing the build guide asked nobody to do, and it would go wrong on
## the Oklab desaturation first, which is the half these sliders are here for.
func test_the_material_is_the_canvas_tonemapper() -> void:
    var preview := SaGamutPreview.new()
    var shader_material := preview.material as ShaderMaterial
    assert_not_null(shader_material, "the preview carries no ShaderMaterial")
    assert_eq(shader_material.shader.resource_path, SHADER_PATH, "the preview grew its own shader")
    assert_eq(shader_material.get_shader_parameter("tonemap_enabled"), true, "the roll-off is off")
    preview.free()


## The reference half of the Preferences pair. Same shader, the operator
## off, and the exposure that undoes the bake.
##
## Clearing the material was the first answer and it is why the exposure matters. The
## picture is stored at `STORED_SCALE`, three stops above white, and drawn raw
## the display clips it channel by channel, so the reference came up pale and
## flat beside a left half whose first act is to bring that same peak back to
## white. Switching `tonemap_enabled` off on its own would have changed nothing
## at all: with the passthrough defaults the shader skips its whole fragment
## body, so off and no material are the same pixels. The exposure is the fix.
func test_the_reference_half_runs_the_same_shader_with_the_operator_off() -> void:
    var preview := SaGamutPreview.new(false)
    var shader_material := preview.material as ShaderMaterial
    assert_not_null(shader_material, "the reference half carries no ShaderMaterial")
    assert_eq(shader_material.shader.resource_path, SHADER_PATH, "the reference half grew its own shader")
    assert_eq(shader_material.get_shader_parameter("tonemap_enabled"), false, "the roll-off is on")
    assert_almost_eq(
        float(shader_material.get_shader_parameter("display_exposure")),
        1.0 / SaGamutPreview.STORED_SCALE,
        1e-6,
        "the reference half does not undo the bake"
    )
    preview.free()


## And what the exposure leaves on screen is the picture at display white, which
## is where the operator's magnitude half lands the other one, so the two halves
## coincide wherever the desaturation is zero.
##
## Read off the picture rather than transcribed from the shader: every texel of
## it rides the gamut boundary, so its peak channel is 1.0 once the bake is
## undone, and the roll-off's `min(peak, 1.0)` therefore has nothing left to do.
func test_the_reference_halfs_exposure_lands_the_picture_on_white() -> void:
    var image := SaGamutPreview.build_image(Vector2i(120, 12))
    var curve := SaTransferFunction.srgb()
    for y in image.get_height():
        for x in image.get_width():
            var texel := image.get_pixel(x, y)
            var shown := (
                Vector3(curve.decode(texel.r), curve.decode(texel.g), curve.decode(texel.b)) / SaGamutPreview.STORED_SCALE
            )
            var peak: float = maxf(shown.x, maxf(shown.y, shown.z))
            assert_almost_eq(peak, 1.0, 0.01, "texel %d,%d peaks at %.4f rather than on white" % [x, y, peak])


## The dump reads both halves out of one call, and a uniform nobody wrote is
## left out of it. Without that the two lists are every uniform the shader
## declares and the difference between them says nothing.
func test_the_shader_report_names_the_shader_and_only_the_written_uniforms() -> void:
    var operated := SaGamutPreview.new()
    operated.configure(0.4, 0.6)
    var plain := SaGamutPreview.new(false)
    plain.configure(0.4, 0.6)

    var left: Dictionary = operated.shader_report()
    var right: Dictionary = plain.shader_report()
    assert_eq(left["shader"], SHADER_PATH, "the report names the wrong shader")
    assert_eq(left["shader"], right["shader"], "the two halves do not share a shader")

    var written: Dictionary = right["uniforms"]
    assert_false(written.has("document_is_srgb"), "a uniform nobody wrote is in the report")
    assert_false(written.has("view_mode"), "a uniform nobody wrote is in the report")

    var differing: Array = []
    for name: String in left["uniforms"].keys() + written.keys():
        if left["uniforms"].get(name) != written.get(name) and not differing.has(name):
            differing.append(name)
    differing.sort()
    assert_eq(differing, ["display_exposure", "tonemap_enabled"] as Array, "the pair differs by %s" % [differing])

    operated.free()
    plain.free()


## Both uniforms follow the sliders, and nothing else is touched: every other
## uniform already defaults to an sRGB document on an sRGB display, so a value
## set here would be a second place for that to drift. The reference half's
## `display_exposure` is the one exception and it is written in `_init`, never
## here, which is why the operated half below still has none.
func test_configure_pushes_only_the_two_slider_uniforms() -> void:
    var preview := SaGamutPreview.new()
    var shader_material := preview.material as ShaderMaterial
    preview.configure(0.35, 0.8)
    assert_almost_eq(shader_material.get_shader_parameter("knee"), 0.35, 1e-6, "the knee did not follow")
    assert_almost_eq(shader_material.get_shader_parameter("desaturation"), 0.8, 1e-6, "the desaturation did not follow")
    for name: String in ["document_is_srgb", "display_passthrough", "view_mode", "display_exposure"]:
        assert_null(shader_material.get_shader_parameter(name), "%s was set, leave it at its default" % name)
    preview.free()


## One texture per session. Rebuilding it on a slider tick is the obvious wrong
## turn, and rebuilding it per Preferences window is a slower one.
func test_the_picture_is_built_once_and_shared() -> void:
    var first := SaGamutPreview.picture()
    var second := SaGamutPreview.picture()
    assert_true(first == second, "the picture is rebuilt on every ask")
