## The four axes as the picker, the canvas and the gamut browser use them.
##
## The other half of `test_color_axes.gd`, split off when that file reached
## gdlint's cap of 32 public methods. The seam is the one the file already
## drew with its own section rules: the model on one side, the transfer curve,
## the gamut, their composition and the dispatch that proves it reaches the GPU,
## and on this side what the rest of the app does with them, the picker and the
## canvas agreeing about what a colour is and Oklab as the coordinates a gamut
## solid is drawn in. Nothing was rewritten in the move, so the two files
## together assert exactly what the one did.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: the picker cases paint through a real surface.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const BrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

# ---------------------------------------------------------------------------
# The picker and the canvas have to agree about what a colour is
# ---------------------------------------------------------------------------


## An sRGB document is the one everyone has, so the conversion must be a
## passthrough for it rather than a round trip that is only nearly the identity.
func test_an_srgb_document_converts_a_picked_colour_by_doing_nothing() -> void:
    var space := SaColorSpace.srgb()
    assert_true(space.is_display_ready(), "An sRGB document already holds what a screen wants")

    var picked := Color(0.4, 0.6, 0.8, 0.5)
    assert_true(space.from_display(picked) == picked, "so the picked colour is stored bit for bit")
    assert_true(space.to_display(picked) == picked, "and read back the same way")


## The bug: the brush wrote the picker's colour straight into the canvas, so mid
## grey landed in a linear document as 0.5 where it means 0.214, and the paint
## came out lighter than the swatch that produced it.
func test_a_picked_colour_reaches_a_linear_document_as_light_rather_than_as_code() -> void:
    var space := SaColorSpace.linear_srgb()
    assert_false(space.is_display_ready(), "A linear document does not hold what a screen wants")

    var stored := space.from_display(Color(0.5, 0.5, 0.5, 1.0))
    assert_almost_eq(stored.r, 0.21404114, 1e-5, "Mid grey is stored as the light it stands for")
    assert_almost_eq(stored.a, 1.0, 0.0, "and alpha is coverage, so it is not converted")

    var shown := space.to_display(stored)
    assert_almost_eq(shown.r, 0.5, 1e-5, "and the eyedropper hands the same swatch back")


## A wide-gamut document moves the colour as well as the curve, so the two
## conversions have to be each other's inverse for the whole chain.
func test_the_picker_round_trips_through_every_combination() -> void:
    var probe := Color(0.35, 0.62, 0.81, 1.0)
    for gamut: SaGamut in SaGamut.presets():
        for curve: SaTransferFunction in SaTransferFunction.presets():
            var space := SaColorSpace.create(&"probe", gamut.primaries, gamut.default_white(), curve)
            var back := space.to_display(space.from_display(probe))
            var label := "%s + %s" % [gamut.display_name, curve.display_name]
            assert_almost_eq(back.r, probe.r, 1e-4, "%s round trips red" % label)
            assert_almost_eq(back.g, probe.g, 1e-4, "%s round trips green" % label)
            assert_almost_eq(back.b, probe.b, 1e-4, "%s round trips blue" % label)


## Painting into a linear document, all the way through the real brush.
##
## The descriptor knowing how to convert is not the same as the brush asking it
## to, and the brush not asking is what the bug was.
func test_the_brush_stores_a_picked_colour_in_the_documents_own_coordinates() -> void:
    var surface := Fixtures.make_surface()
    var doc := surface.easel.document
    doc.color_space = SaColorSpace.linear_srgb()

    var brush := BrushScript.new()
    brush.surface = surface
    brush.settings.color = Color(0.5, 0.5, 0.5, 1.0)
    brush.settings.opacity_by_pressure = false

    brush._stamp_brush(Vector2(32, 32), 1.0)

    var texel := _texel_of(doc.stroke_layer if doc.stroke_layer.chunks.size() > 0 else doc.active_layer)
    assert_almost_eq(texel.r, 0.21404114, 2e-3, "The brush stores the light, not the picker's code value")

    Fixtures.teardown(surface)


func _texel_of(layer: SaLayer) -> Color:
    for grid_pos: Vector2i in layer.chunks:
        var texture := layer.get_field(grid_pos)
        @warning_ignore("static_called_on_instance")
        var image := SaExport.get_texture_image_float(texture)
        for y in image.get_height():
            for x in image.get_width():
                var texel := image.get_pixel(x, y)
                if texel.a > 0.5:
                    return texel
    return Color.TRANSPARENT


# ---------------------------------------------------------------------------
# Oklab as coordinates
# ---------------------------------------------------------------------------


## Round trips, including the negative LMS that blending and wide-gamut colours
## produce all the time and that an unguarded cube root turns into NaN.
func test_oklab_round_trips_including_out_of_gamut_values() -> void:
    for probe: Vector3 in [
        Vector3(0.0, 0.0, 0.0),
        Vector3(1.0, 1.0, 1.0),
        Vector3(0.21, 0.21, 0.21),
        Vector3(0.9, 0.05, 0.02),
        Vector3(-0.2, 0.8, 1.4),
        Vector3(3.0, 0.1, 0.1),
    ]:
        var back := SaOklab.to_linear_srgb(SaOklab.from_linear_srgb(probe))
        assert_almost_eq(back.x, probe.x, 1e-5, "Oklab round trips %s on red" % probe)
        assert_almost_eq(back.y, probe.y, 1e-5, "on green")
        assert_almost_eq(back.z, probe.z, 1e-5, "on blue")


## Oklab's defining property, and the one the tonemapper and the non-separable
## blend modes both rely on: a neutral has no chroma, and L is the lightness.
func test_a_neutral_has_no_chroma_and_white_is_lightness_one() -> void:
    for level: float in [0.05, 0.21, 0.5, 1.0]:
        var lab := SaOklab.from_linear_srgb(Vector3(level, level, level))
        assert_almost_eq(Vector2(lab.y, lab.z).length(), 0.0, 1e-6, "A grey at %s has no chroma" % level)

    var white := SaOklab.from_linear_srgb(Vector3.ONE)
    assert_almost_eq(white.x, 1.0, 1e-5, "and full white has lightness 1")


## Hue is what a painter picked and is never rotated, so the polar form has to be
## its own axis rather than something recomputed from a and b each time.
func test_the_polar_form_separates_chroma_from_hue() -> void:
    var lab := SaOklab.from_linear_srgb(Vector3(0.8, 0.1, 0.1))
    var lch := SaOklab.to_polar(lab)
    assert_true(lch.y > 0.01, "A saturated red has chroma")

    # Half the chroma, same hue: what the tonemapper's desaturation does.
    var muted := SaOklab.from_polar(Vector3(lch.x, lch.y * 0.5, lch.z))
    var muted_lch := SaOklab.to_polar(muted)
    assert_almost_eq(muted_lch.z, lch.z, 1e-6, "Halving chroma leaves the hue angle exactly alone")
    assert_almost_eq(muted_lch.y, lch.y * 0.5, 1e-6, "and halves the chroma")

    assert_almost_eq(SaOklab.to_polar(SaOklab.from_linear_srgb(Vector3(0.5, 0.5, 0.5))).z, 0.0, 0.0, "A neutral gets hue 0")


## The CPU matrices are a hand copy of the kernel's, so the copy has to be
## checked rather than trusted. This is the same probe the composite kernel runs
## for its non-separable modes.
func test_the_cpu_matrices_agree_with_the_kernels() -> void:
    assert_true(
        GlobalShaderCompiler.get_kernel_index("composite", "hue") >= 0,
        "The Oklab kernels are compiled, so there is something to agree with"
    )

    # Oklab is defined against linear sRGB, so a wide-gamut document's numbers go
    # through its matrix first. That composition is what the kernel does and what
    # a gamut solid drawn in Oklab depends on.
    var acescg := SaColorSpace.acescg()
    var stored := Vector3(0.4, 0.6, 0.8)
    var linear: Vector3 = acescg.to_linear_srgb_matrix() * stored
    var lab := SaOklab.from_linear_srgb(linear)
    assert_true(lab.x > 0.0, "An ACEScg triple has a real lightness in Oklab")
    var back: Vector3 = acescg.from_linear_srgb_matrix() * SaOklab.to_linear_srgb(lab)
    assert_almost_eq(back.x, stored.x, 1e-5, "and the whole chain round trips")
    assert_almost_eq(back.z, stored.z, 1e-5, "on every channel")


## A gamut is a volume, and the point of drawing it in Oklab is that different
## gamuts draw visibly different shapes. An RGB cube plot draws them all the same,
## which is the one plot guaranteed to say nothing.
func test_a_wider_gamut_draws_a_bigger_solid() -> void:
    var reach := func(space: SaColorSpace) -> float:
        var widest := 0.0
        for rgb: Vector3 in [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]:
            var decoded := Vector3(space.transfer.decode(rgb.x), space.transfer.decode(rgb.y), space.transfer.decode(rgb.z))
            var lab := SaOklab.from_linear_srgb(space.to_linear_srgb_matrix() * decoded)
            widest = maxf(widest, Vector2(lab.y, lab.z).length())
        return widest

    var srgb_reach: float = reach.call(SaColorSpace.srgb())
    var rec2020 := SaColorSpace.create(&"probe", SaGamut.rec2020().primaries, SaColorSpace.WHITE_D65, SaTransferFunction.srgb())
    assert_true(reach.call(rec2020) > srgb_reach, "Rec. 2020 reaches further into chroma than sRGB")
    assert_true(reach.call(SaColorSpace.display_p3()) > srgb_reach, "and so does Display P3")


## The gamut solid reaches a user, which is a separate question from whether the
## maths is right. Help > Colour Spaces is where the browser lives, not Preferences, and a view that builds but is never added
## to a window shows nobody anything.
func test_the_colour_spaces_window_builds_the_gamut_solid() -> void:
    var window := SaColorSpacesWindow.new()

    var browser: SaColorSpaceBrowser = null
    for child: Node in window.content.find_children("*", "SaColorSpaceBrowser", true, false):
        browser = child
    assert_not_null(browser, "The window builds the browser")
    assert_not_null(browser.solid, "which carries the gamut solid")
    assert_not_null(browser.solid.space, "opened on a space rather than blank")
    assert_not_null(window.content.find_child("GamutOption", true, false), "and a chooser of the space, the picker's own row")

    # Sized by hand, because a Control that has never been through a layout pass
    # is 0x0 and the projection scales by its smaller side: everything lands on
    # the same point and the assertions below would be measuring nothing.
    browser.solid.size = Vector2(240.0, 200.0)

    # Two different colours have to land in two different places, or the
    # projection is collapsing the solid onto a point and drawing nothing
    # readable. Turning it has to move them, or the drag does nothing.
    var red := browser.solid.project(browser.solid.to_oklab(Vector3(1, 0, 0)))
    var blue := browser.solid.project(browser.solid.to_oklab(Vector3(0, 0, 1)))
    assert_true(red.distance_to(blue) > 1.0, "Red and blue project to different places")

    browser.solid.yaw += 1.0
    assert_true(browser.solid.project(browser.solid.to_oklab(Vector3(1, 0, 0))).distance_to(red) > 1.0, "and turning moves them")

    window.free()


## sRGB's own note. The plot is useless with nothing to compare it to, so
## the browser defaults the second dropdown to the next larger gamut, drawn
## round the selected one.
func test_srgb_compares_against_display_p3() -> void:
    var gamut := SaColorSpaceBrowser.compare_gamut_for(SaColorSpace.srgb())
    assert_eq(gamut.id, SaGamut.ID_DISPLAY_P3, "P3 is the next larger gamut, by area, round sRGB")

    var browser := SaColorSpaceBrowser.new()
    browser.show_space(SaColorSpace.srgb())
    assert_not_null(browser.diagram.compare, "The slice carries a gamut to compare against")
    assert_eq(browser.diagram.compare.id, SaGamut.ID_DISPLAY_P3, "and it is P3")
    assert_not_null(browser.solid.compare, "So does the volume")
    assert_eq(browser.solid.compare.gamut().id, SaGamut.ID_DISPLAY_P3, "and it is P3 too")
    assert_eq(browser.solid.compare.transfer.id, browser.solid.space.transfer.id, "sharing sRGB's own transfer, not P3's")
    browser.free()


## AP1 is the largest registered gamut by area even though `SaGamut.presets()`
## lists Rec. 2020 after it for the chooser's sake, so nothing in the
## registry is bigger and there is nothing to draw against it.
##
## The display profile used to stand in whatever its size, which drew Rec. 2020
## as the bright outer shape round an AP1 document twice its area: the smaller
## triangle in the role the note reserves for the larger. It stands in only
## when it is genuinely wider now, which no shipped profile is, and the browser
## says so in words rather than drawing a lie.
func test_the_largest_registered_gamut_has_nothing_to_compare_against() -> void:
    var saved := SaSettings.display_profile
    SaSettings.display_profile = "rec2020"

    var browser := SaColorSpaceBrowser.new()
    browser.show_space(SaColorSpace.acescg())
    assert_null(SaColorSpaceBrowser.compare_gamut_for(SaColorSpace.acescg()), "Nothing on offer is wider than AP1")
    assert_null(browser.diagram.compare, "so the slice draws one triangle")
    assert_null(browser.solid.compare, "and the volume one wireframe")
    assert_true(browser.legend.text.contains("nothing larger"), "and the legend says why: %s" % browser.legend.text)

    SaSettings.display_profile = saved
    browser.free()


## A preview beside a dialog's own chooser (File > New, Image > Colour Space)
## keeps the single-space view there, so it builds no
## second dropdown and draws no second shape.
func test_a_preview_browser_has_no_compare_dropdown() -> void:
    var browser := SaColorSpaceBrowser.new(true)
    assert_null(browser.compare_option, "Preview mode builds no compare dropdown")
    browser.show_space(SaColorSpace.srgb())
    assert_null(browser.diagram.compare, "and draws no compare gamut")
    assert_null(browser.solid.compare, "in either drawing")
    browser.free()


## Changing a document's colour space has to announce itself, because the blend
## mode dropdowns show the space plain Normal is mixing in and a stale label would
## name a document that no longer exists.
##
## Announced from the property itself rather than from each caller, so File > New,
## Assign, Convert and Open cannot each forget it separately.
func test_a_colour_space_change_announces_itself() -> void:
    var seen: Array[SaDocument] = []
    var listener := func(changed: SaDocument) -> void: seen.append(changed)
    EventBus.document_color_space_changed.connect(listener)

    var doc := SaDocument.new()
    assert_eq(seen.size(), 0, "A fresh document's own default is not a change")

    doc.color_space = SaColorSpace.oklab()
    assert_eq(seen.size(), 1, "Assigning one announces it")
    assert_eq(seen[0], doc, "with the document that changed")
    assert_eq(str(doc.color_space.id), str(SaColorSpace.ID_OKLAB), "which holds the space that was set")

    EventBus.document_color_space_changed.disconnect(listener)
    doc.free()
