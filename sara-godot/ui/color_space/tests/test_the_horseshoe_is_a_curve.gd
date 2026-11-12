## The CIE xy diagram's shape and its interior.
##
## The CIE xy graph needs a proper shape, where it once had odd colours and an
## edged outline. Two halves, and each is a number rather than a look.
##
## The shape is the largest gap between two adjacent drawn points, which has to
## stay under a pixel at whatever size the control is: a chord shorter than a
## pixel cannot be seen as a straight run, and the thirty-three observer samples
## the drawing shipped with are four chords a hundred and thirty pixels long
## across the green flank.
##
## The colours are the baked interior: every texel is its own chromaticity's
## colour, so the picture is a function of the chromaticity at that point rather
## than of which triangle a triangulation of the boundary put it in. What the
## suite can ask of that is the two ends: red where red is, blue where blue is,
## and nothing at all outside the horseshoe.
##
## The picture itself is `scenarios/the-cie-xy-diagram-is-a-horseshoe.json`,
## because "no visible corner" is a thing a person sees.
extends "res://tests/test_framework.gd"


func _diagram(at: Vector2) -> SaChromaticityDiagram:
    var diagram := SaChromaticityDiagram.new()
    diagram.space = SaColorSpace.srgb()
    diagram.size = at
    return diagram


## The whole of the shape half, at three sizes, because the density is supposed
## to follow the control rather than a number written into the file.
func test_no_chord_of_the_drawn_locus_reaches_a_pixel() -> void:
    for at: Vector2 in [Vector2(240.0, 250.0), Vector2(480.0, 500.0), Vector2(1400.0, 700.0)]:
        var diagram := _diagram(at)
        var longest := diagram.longest_chord()
        assert_true(longest > 0.0 and longest <= SaChromaticityDiagram.CHORD_PX, "at %s the longest gap is %f px" % [at, longest])
        assert_true(
            diagram.locus().size() > SaChromaticityDiagram.OBSERVER.size() * 4,
            "and the curve is made of far more points than the observer table: %d" % diagram.locus().size()
        )
        diagram.free()


## The fault. The observer table alone, joined by straight lines,
## puts a chord across the green flank longer than half the control.
func test_the_observer_table_on_its_own_is_the_edged_shape() -> void:
    var diagram := _diagram(Vector2(480.0, 500.0))
    var longest := 0.0
    for i in SaChromaticityDiagram.OBSERVER.size() - 1:
        var a := diagram.to_plot(SaChromaticityDiagram.OBSERVER[i])
        var b := diagram.to_plot(SaChromaticityDiagram.OBSERVER[i + 1])
        longest = maxf(longest, a.distance_to(b))
    assert_true(longest > 100.0, "the table's own longest chord is %f px, which is what was drawn" % longest)
    diagram.free()


## A bigger control asks for more points, which is the claim that the density
## follows the size rather than being a constant with a size-shaped name.
func test_a_larger_control_is_sampled_more_finely() -> void:
    var small := _diagram(Vector2(240.0, 250.0))
    var large := _diagram(Vector2(960.0, 1000.0))
    assert_true(
        large.locus().size() > small.locus().size() * 3,
        "%d points at 960 against %d at 240" % [large.locus().size(), small.locus().size()]
    )
    small.free()
    large.free()


## The curve stays inside the window it is drawn in, which is what a spline
## through bunched samples is not guaranteed to do: a uniform Catmull-Rom loops
## outside the hull where the observer's ends crowd, and centripetal is the
## reason this holds.
func test_the_curve_never_leaves_the_plot() -> void:
    var diagram := _diagram(Vector2(480.0, 500.0))
    var strayed := Vector2.INF
    for xy: Vector2 in diagram.locus():
        if xy.x < -0.001 or xy.y < -0.001 or xy.x > SaChromaticityDiagram.PLOT_MAX.x:
            strayed = xy
            break
    # One assertion rather than one per point, so the suite's count says how
    # many things this file checks rather than how many points the curve has.
    assert_eq(strayed, Vector2.INF, "every one of the %d points is inside the plotted window" % diagram.locus().size())
    diagram.free()


## The interior half. The baked picture is opaque where a chromaticity is,
## transparent where none is, and carries the colour of the place rather than a
## blend of the boundary.
func test_the_baked_interior_is_the_chromaticity_at_each_texel() -> void:
    var picture := SaChromaticityDiagram.picture()
    assert_not_null(picture, "the interior is baked once and kept")
    var image := picture.get_image()
    assert_eq(image.get_size(), SaChromaticityDiagram.PICTURE, "at the size the class declares")

    var to_rgb := SaColorSpace.srgb().xyz_to_rgb()
    var red := _texel_of(image, Vector2(0.64, 0.33))
    assert_true(red.a > 0.9, "sRGB's red primary is inside the horseshoe")
    assert_true(red.r > red.g and red.r > red.b, "and reads red: %s" % red)

    var blue := _texel_of(image, Vector2(0.15, 0.06))
    assert_true(blue.a > 0.9, "sRGB's blue primary is inside it too")
    assert_true(blue.b > blue.r and blue.b > blue.g, "and reads blue: %s" % blue)

    var green := SaChromaticityDiagram.swatch(Vector2(0.3, 0.6), to_rgb)
    assert_true(green.g > green.r and green.g > green.b, "and the swatch of a green chromaticity is green")


## Outside the locus is the panel, not a colour. The old fill was a polygon, so
## it could only ever be right on the boundary and guessed everywhere else.
func test_nothing_is_painted_outside_the_horseshoe() -> void:
    var image := SaChromaticityDiagram.picture().get_image()
    for xy: Vector2 in [Vector2(0.7, 0.7), Vector2(0.05, 0.05), Vector2(0.75, 0.05)]:
        assert_eq(_texel_of(image, xy).a, 0.0, "%s is outside the locus and is left to the panel" % xy)


## The report the scenarios read still answers every key it did, and says how
## finely the shape is drawn beside them.
func test_the_report_keeps_its_keys_and_adds_the_two_new_ones() -> void:
    var diagram := _diagram(Vector2(480.0, 500.0))
    diagram.compare = SaGamut.display_p3()
    var report := diagram.report()
    for key: String in ["space", "compare", "space_triangle", "compare_triangle", "size", "spread", "distinct"]:
        assert_true(report.has(key), "the report still answers '%s'" % key)
    assert_eq(int(report["locus_points"]), diagram.locus().size(), "and says how many points the locus is drawn as")
    assert_almost_eq(float(report["locus_chord_px"]), diagram.longest_chord(), 1e-5, "and how long its longest chord is")
    assert_true(float(report["locus_chord_px"]) <= SaChromaticityDiagram.CHORD_PX, "which is under a pixel")
    diagram.free()


## The axes are the same scale, which is what a chromaticity diagram means. The
## control is a row of the page and expands to its width, three times its own
## height on a maximised window, and the horseshoe was drawn stretched over all
## of it.
func test_the_plot_keeps_its_axes_square_inside_a_wide_control() -> void:
    var diagram := _diagram(Vector2(1500.0, 250.0))
    var rect := diagram.plot_rect()
    var max_xy := SaChromaticityDiagram.PLOT_MAX
    assert_almost_eq(rect.size.x / max_xy.x, rect.size.y / max_xy.y, 1e-4, "one xy unit is the same number of pixels either way")
    assert_true(
        rect.size.y <= 250.0 and rect.size.x < 1500.0, "and the picture is as large as fits rather than stretched: %s" % rect
    )
    assert_almost_eq(rect.get_center().x, 750.0, 0.5, "centred in the control it was given")
    diagram.free()


## The same control drawn twice as tall gives the picture twice the area, which
## is the other half of "as large as fits".
func test_a_taller_control_draws_a_larger_picture() -> void:
    # 250 rather than anything under it, because the control asks for that as a
    # minimum height and Godot will not give a Control a size below the one it
    # asks for, so a shorter one is the same control with the numbers hidden.
    var short_one := _diagram(Vector2(600.0, 250.0))
    var tall := _diagram(Vector2(600.0, 500.0))
    assert_almost_eq(
        tall.plot_rect().size.y,
        short_one.plot_rect().size.y * 2.0,
        0.5,
        "%s against %s" % [tall.plot_rect().size, short_one.plot_rect().size]
    )
    assert_almost_eq(
        tall.plot_rect().size.x, short_one.plot_rect().size.x * 2.0, 0.5, "and twice as wide, the axes staying square"
    )
    short_one.free()
    tall.free()


## The texel a chromaticity falls in, read out of the baked picture.
func _texel_of(image: Image, xy: Vector2) -> Color:
    var size := SaChromaticityDiagram.PICTURE
    var max_xy := SaChromaticityDiagram.PLOT_MAX
    var px := clampi(int(xy.x / max_xy.x * float(size.x)), 0, size.x - 1)
    var py := clampi(int((max_xy.y - xy.y) / max_xy.y * float(size.y)), 0, size.y - 1)
    return image.get_pixel(px, py)
