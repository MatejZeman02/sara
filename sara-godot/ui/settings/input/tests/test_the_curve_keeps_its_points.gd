## The pressure curve reopens on the points the painter placed.
##
## The graph in Preferences > Tablet must not add points on its own when closed
## and reopened. The page once stored only the sampled
## table and rebuilt the editor from it on every open at nine evenly spaced
## places, so two handles came back as nine and a handle placed at 0.3 came back
## as two nobody placed. The table a stroke reads never moved, which is why no
## stroke test caught it: the bug is only in what the painter can drag.
##
## No GPU and no pen. The page is built, a curve is set on it, the page is freed,
## the correction is read back from the settings folder the way startup reads it,
## and a second page is built over it.
extends "res://tests/test_framework.gd"

var _saved_correction: PackedFloat32Array
var _saved_points: PackedVector2Array


func before_each() -> void:
    _saved_correction = SaTablet.correction
    _saved_points = SaTablet.correction_points


func after_each() -> void:
    SaTablet.save_correction(PackedFloat32Array())
    SaTablet.correction = _saved_correction
    SaTablet.correction_points = _saved_points


## The editor on *page*, which is where the handles a painter drags live.
func _editor(page: SaTabletCalibration) -> SaCurveEditor:
    return page.find_child("PressureCurve", true, false) as SaCurveEditor


## A page built fresh over whatever is stored, the way Preferences opens it after
## a restart: the correction is read from disk first, as `SaSettings` does at
## startup, so nothing held in memory by the page before it can leak through.
func _reopened() -> SaTabletCalibration:
    SaTablet.correction = PackedFloat32Array()
    SaTablet.correction_points = PackedVector2Array()
    SaTablet.load_correction()
    var page := SaTabletCalibration.new()
    page.refresh()
    return page


## The regression. Two handles shaped by hand, saved, and read back as two, at
## the places they were put.
func test_two_placed_points_reopen_as_two() -> void:
    var page := SaTabletCalibration.new()
    _editor(page).set_points(PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 0.8)]))
    page.free()

    var reopened := _reopened()
    var points := _editor(reopened).points
    assert_eq(points.size(), 2, "Two points were placed and two come back, not nine")
    if points.size() == 2:
        assert_almost_eq(points[1].y, 0.8, 1e-4, "and the top one is still where it was dragged")
    reopened.free()


## A handle placed on purpose at 0.3 comes back at 0.3,
## and not as the samples at 0.25 and 0.375 either side of it.
func test_a_point_placed_at_0_3_is_still_at_0_3() -> void:
    var page := SaTabletCalibration.new()
    _editor(page).set_points(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.3, 0.6), Vector2(1.0, 1.0)]))
    page.free()

    var reopened := _reopened()
    var points := _editor(reopened).points
    assert_eq(points.size(), 3, "Three points in, three out")
    if points.size() == 3:
        assert_almost_eq(points[1].x, 0.3, 1e-4, "and the middle one is at 0.3")
        assert_almost_eq(points[1].y, 0.6, 1e-4, "at the height it was put")
    reopened.free()


## Every reopen keeps the count, so a reopen that
## added points once would go to nine and stay there, and a test of one reopen
## alone would pass on a curve that started at nine.
func test_three_reopens_in_a_row_add_nothing() -> void:
    var page := SaTabletCalibration.new()
    _editor(page).set_points(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.5, 0.7), Vector2(1.0, 1.0)]))
    page.free()

    for i in range(3):
        var reopened := _reopened()
        assert_eq(_editor(reopened).points.size(), 3, "Reopen %d still has three points" % (i + 1))
        reopened.free()


## A curve the sweep dialog fitted has no placed points, so the page opens on the
## nine samples that dialog drew. That is the dialog's own record, by the same
## rule, and not a shape invented here.
func test_a_fitted_table_opens_on_nine() -> void:
    var table := PackedFloat32Array()
    for i in range(256):
        table.append(sqrt(float(i) / 255.0))
    SaTablet.save_correction(table)

    var reopened := _reopened()
    assert_eq(_editor(reopened).points.size(), 9, "A fitted table with no handles opens on nine")
    reopened.free()


## A hand edit after a sweep replaces the sweep's nine with the painter's own,
## and a sweep after a hand edit removes the handles, so a stale points file can
## never describe a table it did not make.
func test_a_sweep_after_a_hand_edit_takes_the_handles_away() -> void:
    var page := SaTabletCalibration.new()
    _editor(page).set_points(PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 0.8)]))
    page.free()
    assert_true(FileAccess.file_exists(SaTablet.curve_points_path()), "The hand edit wrote its points")

    var table := PackedFloat32Array()
    for i in range(256):
        table.append(sqrt(float(i) / 255.0))
    SaTablet.save_correction(table)
    assert_false(FileAccess.file_exists(SaTablet.curve_points_path()), "and the sweep removed them")

    var reopened := _reopened()
    assert_eq(_editor(reopened).points.size(), 9, "so the page opens on the sweep's nine")
    reopened.free()


## Reset stores none, neither the table nor the points.
func test_reset_leaves_no_points_behind() -> void:
    var page := SaTabletCalibration.new()
    _editor(page).set_points(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.4, 0.7), Vector2(1.0, 1.0)]))
    page.reset_curve()
    page.free()

    assert_false(FileAccess.file_exists(SaTablet.curve_path()), "Reset removes the table")
    assert_false(FileAccess.file_exists(SaTablet.curve_points_path()), "and the points")
    var reopened := _reopened()
    assert_eq(_editor(reopened).points.size(), 2, "and the page reopens on the straight line")
    reopened.free()


## The table a stroke reads is the same one it was before this unit: the points
## ride beside it and change nothing a brush sees.
func test_the_table_is_still_what_the_editor_sampled() -> void:
    var page := SaTabletCalibration.new()
    var editor := _editor(page)
    editor.set_points(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.3, 0.6), Vector2(1.0, 1.0)]))
    var sampled := editor.samples()
    page.free()

    SaTablet.correction = PackedFloat32Array()
    SaTablet.load_correction()
    assert_eq(SaTablet.correction.size(), sampled.size(), "The stored table is the editor's samples")
    assert_almost_eq(SaTablet.correction[64], sampled[64], 1e-5, "with the same numbers in it")
