## The Oklab solid clips its wireframe to its own frame.
##
## In Preferences > Colour Spaces the Oklab graph could render outside its black
## background window and should be clipped. `_draw` is `draw_line` calls and nothing stops a line at the control's edge,
## so the control has to ask for the clip itself. The picture on screen is
## `scenarios/the-oklab-solid-clips-to-its-frame.json`, and this suite holds
## the property and the report that scenario's dump reads.
extends "res://tests/test_framework.gd"

## Taller than the control's own minimum, or the size write is clamped to it.
const PANEL := Vector2(480.0, 360.0)


func _solid() -> SaGamutSolid:
    var solid := SaGamutSolid.new()
    solid.space = SaColorSpace.srgb()
    solid.size = PANEL
    return solid


func test_the_solid_clips_its_contents() -> void:
    var solid := _solid()
    assert_true(solid.clip_contents, "the wireframe is cut at the frame, not drawn over the page")
    assert_true(bool(solid.report()["clipped"]), "the report says so, for the scenario's dump")
    solid.free()


func test_the_default_view_fits_and_a_deep_zoom_does_not() -> void:
    var solid := _solid()
    assert_false(bool(solid.report()["overflows"]), "at zoom one the cube sits inside its frame")
    for _i in range(15):
        solid.zoom_at(SaGamutSolid.WHEEL_STEP, PANEL * 0.5)
    var report := solid.report()
    assert_almost_eq(float(report["zoom"]), SaGamutSolid.ZOOM_MAX, 0.001, "fifteen notches reach the zoom ceiling")
    assert_true(bool(report["overflows"]), "at the ceiling the cube's box leaves the frame, which is what the clip is for")
    var frame: Array = report["frame"]
    assert_eq(frame.size(), 4, "the frame is x, y, w, h")
    assert_almost_eq(float(frame[2]), PANEL.x, 0.001, "the frame is the control's own rectangle")
    assert_almost_eq(float(frame[3]), PANEL.y, 0.001, "the frame is the control's own rectangle")
    solid.free()
