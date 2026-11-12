## The curve maths, and what the kernel does with it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Moved from the skeleton's suites with the Curves filter, and read against
## the base module's `SaPointAdjust`.
##
## The interpolation is checked without a GPU, because it is arithmetic. The
## pass itself is checked the way Levels is: a flat fill through the kernel and
## the texel read back off the chunk.
extends "res://tests/test_framework.gd"

## A real dispatch, and a real storage buffer.
const REQUIRES_GPU := true

const CANVAS := Vector2i(64, 64)


func _texel(layer: SaLayer) -> Color:
    var texture := layer.get_field(Vector2i.ZERO)
    if texture == null:
        return Color(0.0, 0.0, 0.0, 0.0)
    @warning_ignore("static_called_on_instance")
    return SaExport.get_texture_image_float(texture).get_pixel(4, 4)


## *fill* through the curves pass with *curves*, as the colour that comes out.
func _through(easel: SaEasel, fill: Color, curves: Dictionary) -> Color:
    var layer := easel.document.get_node_or_null("Layer 1") as SaLayer
    layer.fill(fill)
    easel.document.set_active_layer(layer)
    var applied := SaPointAdjust.new().apply(easel.document, layer, SaPointAdjust.CURVES, {"curves": curves}, "Curves")
    assert_true(applied, "The pass runs")
    return _texel(layer)


## The samples of a curve through *points*.
func _samples(points: Array) -> PackedFloat32Array:
    return SaCurveEditor.sample_curve(PackedVector2Array(points), SaCurveEditor.SAMPLES)


## Two points and nothing else is the diagonal, sampled evenly, which is what
## every channel the painter never touched has to be.
func test_the_diagonal_samples_to_itself() -> void:
    var samples := _samples([Vector2(0.0, 0.0), Vector2(1.0, 1.0)])
    assert_eq(samples.size(), 256, "One entry per step")
    for i: int in [0, 64, 128, 200, 255]:
        assert_almost_eq(samples[int(i)], float(i) / 255.0, 1e-3, "Entry %s is its own input" % i)


## A point dragged up lifts the middle and leaves the ends, which is the whole
## of a tone curve.
func test_a_point_lifts_the_middle_and_leaves_the_ends() -> void:
    var samples := _samples([Vector2(0.0, 0.0), Vector2(0.5, 0.75), Vector2(1.0, 1.0)])
    assert_almost_eq(samples[0], 0.0, 1e-3, "Black stays black")
    assert_almost_eq(samples[255], 1.0, 1e-3, "white stays white")
    assert_almost_eq(samples[128], 0.75, 4e-3, "and the middle is where it was put")


## The monotone fit is the reason this is not a Catmull-Rom: a step between two
## close points must not dip below the lower one on the way.
func test_the_curve_never_overshoots() -> void:
    var samples := _samples([Vector2(0.0, 0.0), Vector2(0.48, 0.05), Vector2(0.52, 0.95), Vector2(1.0, 1.0)])
    var previous := -1.0
    for i in range(samples.size()):
        assert_true(samples[i] >= previous - 1e-4, "Entry %d does not fall back, %.4f after %.4f" % [i, samples[i], previous])
        previous = samples[i]
    assert_true(samples[100] <= 0.06, "and the shadow stays where it was put, got %.4f" % samples[100])


## The lookup table is five channels laid end to end, and a channel nobody
## shaped is the identity so the kernel can apply all five without asking.
func test_the_table_is_five_identities_until_it_is_not() -> void:
    var table := SaPointAdjust.table({})
    assert_eq(
        table.size(),
        5 * 256 + SaPointAdjust.BALANCE_FLOATS + SaPointAdjust.PALETTE_FLOATS + SaPointAdjust.EQUALIZE_FLOATS,
        "Five channels of samples, then colour balance's nine, then the colour lookup's palette, one layout"
    )
    assert_almost_eq(table[128], 128.0 / 255.0, 1e-4, "The master starts as the identity")
    assert_almost_eq(table[4 * 256 + 128], 128.0 / 255.0, 1e-4, "and so does the lightness")

    var lifted := SaPointAdjust.table({"curves": {"red": _samples([Vector2(0.0, 0.0), Vector2(0.5, 0.75), Vector2(1.0, 1.0)])}})
    assert_almost_eq(lifted[128], 128.0 / 255.0, 1e-4, "The master is still the diagonal")
    assert_almost_eq(lifted[256 + 128], 0.75, 4e-3, "and only red moved")


## The Oklab round trip is the expensive half, so it runs only when the
## lightness curve is not the diagonal.
func test_the_oklab_pass_is_asked_for_only_when_it_is_needed() -> void:
    var flat := SaPointAdjust.params_for(SaPointAdjust.CURVES, {})
    assert_almost_eq(float(flat[5]), 0.0, 1e-6, "Nothing shaped, nothing to do")

    var shaped := SaPointAdjust.params_for(
        SaPointAdjust.CURVES, {"curves": {"lightness": _samples([Vector2(0.0, 0.0), Vector2(0.5, 0.7), Vector2(1.0, 1.0)])}}
    )
    assert_almost_eq(float(shaped[5]), 1.0, 1e-6, "A shaped lightness asks for the pass")

    var identity := SaPointAdjust.params_for(
        SaPointAdjust.CURVES, {"curves": {"lightness": _samples([Vector2(0.0, 0.0), Vector2(1.0, 1.0)])}}
    )
    assert_almost_eq(float(identity[5]), 0.0, 1e-6, "and a lightness left on the diagonal does not")


## The master curve on the canvas: a mid grey lands where the point was put.
func test_the_master_curve_maps_a_grey() -> void:
    var easel := SaEasel.create_default(CANVAS)
    var curve := _samples([Vector2(0.0, 0.0), Vector2(0.5, 0.75), Vector2(1.0, 1.0)])
    var out := _through(easel, Color(0.5, 0.5, 0.5, 1.0), {"master": curve})
    assert_almost_eq(out.r, 0.75, 5e-3, "The grey went to the point")
    assert_almost_eq(out.g, out.r, 1e-3, "on every channel")
    assert_almost_eq(out.b, out.r, 1e-3, "of the master")
    easel.free()


## One channel's curve on top of the master's, which is the order Photoshop
## applies them in and the reason both are in the table at once.
func test_a_channel_curve_runs_after_the_master() -> void:
    var easel := SaEasel.create_default(CANVAS)
    var half := _samples([Vector2(0.0, 0.0), Vector2(0.5, 0.25), Vector2(1.0, 1.0)])
    var out := _through(easel, Color(0.5, 0.5, 0.5, 1.0), {"red": half})
    assert_almost_eq(out.r, 0.25, 5e-3, "Red went through its own curve")
    assert_almost_eq(out.g, 0.5, 3e-3, "and green did not")
    easel.free()


## Outside 0 to 1 the curve is not defined, so the value rides on the offset
## the nearest end has rather than being clamped away (hard rule 5).
func test_out_of_range_paint_rides_on_the_end() -> void:
    var easel := SaEasel.create_default(CANVAS)
    var lifted := _samples([Vector2(0.0, 0.1), Vector2(1.0, 1.0)])
    var out := _through(easel, Color(-0.25, -0.25, -0.25, 1.0), {"master": lifted})
    assert_almost_eq(out.r, -0.15, 8e-3, "Minus a quarter came back lifted by the same tenth")
    easel.free()


## Apply is one history step, like the other three adjustments.
func test_apply_is_one_undoable_step() -> void:
    var easel := SaEasel.create_default(CANVAS)
    var before := easel.document.history.step_count()
    var curve := _samples([Vector2(0.0, 0.0), Vector2(0.5, 0.75), Vector2(1.0, 1.0)])
    _through(easel, Color(0.5, 0.5, 0.5, 1.0), {"master": curve})
    assert_eq(easel.document.history.step_count(), before + 1, "One step")
    easel.document.undo_redo.undo()
    assert_almost_eq(_texel(easel.document.get_node("Layer 1")).r, 0.5, 2e-3, "which one undo puts back")
    easel.free()


## The editor keeps its points in x order however they arrive, because a
## curve out of order is not a function of input. The ends keep the x they
## were given, since a painter may move them inward like any other point.
func test_the_editor_sorts_its_points_and_keeps_its_ends() -> void:
    var editor := SaCurveEditor.new()
    editor.set_points(PackedVector2Array([Vector2(0.8, 0.9), Vector2(0.2, 0.1), Vector2(0.5, 0.5)]))
    assert_eq(editor.points.size(), 3, "Three points")
    assert_almost_eq(editor.points[0].x, 0.2, 1e-6, "The first keeps its x")
    assert_almost_eq(editor.points[2].x, 0.8, 1e-6, "and so does the last")
    assert_true(editor.points[1].x > editor.points[0].x, "and the middle is between them")
    assert_false(editor.is_identity(), "A shaped curve is not the diagonal")
    editor.reset()
    assert_true(editor.is_identity(), "and a reset one is")
    editor.free()
