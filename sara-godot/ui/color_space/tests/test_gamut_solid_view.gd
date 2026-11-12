## The Oklab solid turns the right way and answers zoom and pan.
##
## The solid in Preferences > Colour Spaces had its Y axis rotation reversed and
## could not zoom or pan.
##
## The solid is built and sized by hand rather than laid out, because a Control
## that has never been through a layout pass is 0x0 and the projection scales by
## its shorter side: everything would land on one point and every assertion here
## would be measuring nothing. That the gestures reach it on screen, and that the
## picture actually moves, is proved on the running app by
## `scenarios/the-oklab-solid-turns-and-zooms.json`.
extends "res://tests/test_framework.gd"

## Wide enough that the shorter side is the height, so a test that gets the two
## the wrong way round reads differently from one that does not.
const PANEL := Vector2(320.0, 240.0)


## A solid on sRGB, sized, at the view a fresh page opens on.
func _solid() -> SaGamutSolid:
    var solid := SaGamutSolid.new()
    solid.space = SaColorSpace.srgb()
    solid.size = PANEL
    return solid


## One whole left drag, press to release, through the door the pointer uses.
func _drag(solid: SaGamutSolid, relative: Vector2, shift: bool) -> void:
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.shift_pressed = shift
    solid.apply_gesture(press)
    var motion := InputEventMouseMotion.new()
    motion.relative = relative
    solid.apply_gesture(motion)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    solid.apply_gesture(release)


## One wheel notch at *at*, in on *up*.
func _wheel(solid: SaGamutSolid, up: bool, at: Vector2) -> void:
    var wheel := InputEventMouseButton.new()
    wheel.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
    wheel.pressed = true
    wheel.position = at
    solid.apply_gesture(wheel)


## The white corner where it lands on screen, which is the reading that matters: it sits at the top of the
## neutral axis, so a tip of the solid moves it.
func _white(solid: SaGamutSolid) -> Vector2:
    return solid.project(solid.to_oklab(Vector3(1, 1, 1)))


# --- The reversed axis ----------------------------------------------------------


## The first half. Every orbit control
## lowers the eye when the pointer goes down, so a downward drag has to raise the
## top of the solid on screen. Adding the drag to the pitch, which is what the
## drawing shipped with, carried it down instead.
func test_a_downward_drag_raises_the_white_corner() -> void:
    var solid := _solid()
    var before := _white(solid)
    _drag(solid, Vector2(0.0, 40.0), false)
    var after := _white(solid)
    var pitch := solid.pitch
    solid.free()

    assert_true(after.y < before.y, "A drag down moves the white corner up, %s then %s" % [before.y, after.y])
    assert_true(pitch < SaGamutSolid.PITCH, "because the drag lowered the pitch rather than raising it")


## And the other way, or the fix is a sign that only reads right in one place.
func test_an_upward_drag_lowers_the_white_corner() -> void:
    var solid := _solid()
    var before := _white(solid)
    _drag(solid, Vector2(0.0, -40.0), false)
    var after := _white(solid)
    solid.free()

    assert_true(after.y > before.y, "A drag up moves the white corner down, %s then %s" % [before.y, after.y])


## The yaw is untouched by the fix, so a sideways drag still turns the way it did.
func test_a_sideways_drag_still_turns_the_solid() -> void:
    var solid := _solid()
    var before := solid.project(solid.to_oklab(Vector3(1, 0, 0)))
    _drag(solid, Vector2(60.0, 0.0), false)
    var yaw := solid.yaw
    var after := solid.project(solid.to_oklab(Vector3(1, 0, 0)))
    solid.free()

    assert_almost_eq(yaw, SaGamutSolid.YAW + 60.0 * SaGamutSolid.TURN_PER_PIXEL, 0.0001, "A sideways drag adds to the yaw")
    assert_true(after.distance_to(before) > 1.0, "and red moves with it")


## The clamp the pitch always had, kept through the flipped sign, or a long drag
## turns the solid edge-on and there is nothing left to read.
func test_the_pitch_stops_at_its_limit() -> void:
    var solid := _solid()
    _drag(solid, Vector2(0.0, -10_000.0), false)
    var up := solid.pitch
    _drag(solid, Vector2(0.0, 10_000.0), false)
    var down := solid.pitch
    solid.free()

    assert_eq(up, SaGamutSolid.PITCH_LIMIT, "A drag far enough up stops at the limit")
    assert_eq(down, -SaGamutSolid.PITCH_LIMIT, "and far enough down at the other one")


# --- The zoom -------------------------------------------------------------------


## The second half. A wheel notch has to make the picture larger.
func test_the_wheel_zooms_in_and_out() -> void:
    var solid := _solid()
    var before := solid.project(solid.to_oklab(Vector3(1, 0, 0))).distance_to(solid.project(solid.to_oklab(Vector3(0, 0, 1))))
    _wheel(solid, true, PANEL * 0.5)
    var zoomed := solid.zoom
    var wider := solid.project(solid.to_oklab(Vector3(1, 0, 0))).distance_to(solid.project(solid.to_oklab(Vector3(0, 0, 1))))
    _wheel(solid, false, PANEL * 0.5)
    var back := solid.zoom
    solid.free()

    assert_eq(zoomed, SaGamutSolid.WHEEL_STEP, "One notch in multiplies the zoom by the step")
    assert_true(wider > before * 1.05, "and red and blue are further apart for it")
    assert_true(is_equal_approx(back, 1.0), "and a notch out puts it back")


## About the pointer, which is the whole of "zoom on this graph": whatever sits
## under the pointer has to stay under it, or a wheel over a corner throws that
## corner off the panel.
func test_the_wheel_keeps_the_point_under_the_pointer() -> void:
    var solid := _solid()
    # A point well off the middle, so a zoom about the centre would move it.
    var at := Vector2(PANEL.x * 0.25, PANEL.y * 0.25)
    # The Oklab coordinate that lands there now, found by inverting nothing: the
    # red corner is wherever it is, so the panel is moved until it sits at *at*.
    var red := solid.project(solid.to_oklab(Vector3(1, 0, 0)))
    solid.pan += (at - red) / solid.shorter_side()
    var before := solid.project(solid.to_oklab(Vector3(1, 0, 0)))

    _wheel(solid, true, at)
    var after := solid.project(solid.to_oklab(Vector3(1, 0, 0)))
    solid.free()

    assert_true(before.distance_to(at) < 0.01, "Red is under the pointer to start with")
    assert_true(after.distance_to(at) < 0.01, "and a wheel notch about that point leaves it there, at %s" % after)


## The range the clouds use, so a painter cannot wheel the solid into a dot or
## past the panel's edges for good.
func test_the_zoom_stops_at_both_ends() -> void:
    var solid := _solid()
    for i in 60:
        _wheel(solid, true, PANEL * 0.5)
    var most := solid.zoom
    for i in 120:
        _wheel(solid, false, PANEL * 0.5)
    var least := solid.zoom
    solid.free()

    assert_true(most <= SaGamutSolid.ZOOM_MAX, "The zoom stops at the far end, %s" % most)
    assert_true(least >= SaGamutSolid.ZOOM_MIN, "and at the near one, %s" % least)


# --- The pan --------------------------------------------------------------------


## Shift and the middle button both pan, which is the clouds' gesture set.
func test_shift_and_the_middle_button_both_pan() -> void:
    var solid := _solid()
    var before := _white(solid)
    _drag(solid, Vector2(30.0, 20.0), true)
    var shifted := _white(solid)
    var yaw := solid.yaw
    var pitch := solid.pitch

    var middle := InputEventMouseButton.new()
    middle.button_index = MOUSE_BUTTON_MIDDLE
    middle.pressed = true
    solid.apply_gesture(middle)
    var motion := InputEventMouseMotion.new()
    motion.relative = Vector2(-30.0, -20.0)
    solid.apply_gesture(motion)
    var back := _white(solid)
    solid.free()

    assert_true(shifted.distance_to(before + Vector2(30.0, 20.0)) < 0.01, "A shift drag moves the picture by the drag")
    assert_eq(yaw, SaGamutSolid.YAW, "and turns nothing")
    assert_eq(pitch, SaGamutSolid.PITCH, "in either axis")
    assert_true(back.distance_to(before) < 0.01, "and a middle drag the other way puts it back")


## The pan is in unit coordinates of the shorter side, so the same number means
## the same fraction of the picture in a panel of any size.
##
## The two panels are asked what their shorter side is rather than told: a
## Control clamps `size` up to its combined minimum, so a panel set to 320 by 240
## is 320 by 340 and the shorter side is the width. That clamp cost this test a
## run, and it is the only reason `shorter_side` is public.
func test_the_pan_is_in_units_of_the_shorter_side() -> void:
    var small := _solid()
    var large := _solid()
    large.size = PANEL * 2.0
    var small_side := small.shorter_side()
    var large_side := large.shorter_side()
    var small_before := _white(small).x
    var large_before := _white(large).x
    small.pan_by(Vector2(0.25, 0.0))
    large.pan_by(Vector2(0.25, 0.0))
    var moved_small := _white(small).x - small_before
    var moved_large := _white(large).x - large_before
    small.free()
    large.free()

    assert_true(large_side > small_side, "The larger panel has the larger shorter side, %s over %s" % [large_side, small_side])
    assert_almost_eq(moved_small, small_side * 0.25, 0.01, "A quarter pan moves the small panel by a quarter of its shorter side")
    assert_almost_eq(moved_large, large_side * 0.25, 0.01, "and the large one by a quarter of its own")


## A control that has never been laid out is 0x0, and the pan divides by its
## shorter side. A NaN there is unrecoverable: no later gesture clears it and the
## solid never draws again.
func test_a_solid_with_no_size_does_not_divide_by_zero() -> void:
    var solid := SaGamutSolid.new()
    solid.space = SaColorSpace.srgb()
    # The minimum has to go first, or the Control clamps the size back up to it
    # and this test never reaches the case it is named for.
    solid.custom_minimum_size = Vector2.ZERO
    solid.size = Vector2.ZERO
    _drag(solid, Vector2(20.0, 20.0), true)
    _wheel(solid, true, Vector2.ZERO)
    var pan := solid.pan
    var zoom := solid.zoom
    solid.free()

    assert_false(is_nan(pan.x) or is_nan(pan.y), "The pan survives a panel with no size, %s" % pan)
    assert_false(is_nan(zoom), "and so does the zoom, %s" % zoom)


# --- The way back ---------------------------------------------------------------


## The view has zoom and pan, and anything a painter can move they can get
## lost in. A double click is the way back, and it is what the tooltip says.
func test_a_double_click_puts_the_view_back() -> void:
    var solid := _solid()
    _drag(solid, Vector2(60.0, 40.0), false)
    _drag(solid, Vector2(30.0, 30.0), true)
    _wheel(solid, true, PANEL * 0.25)
    var moved := [solid.yaw, solid.pitch, solid.zoom, solid.pan]

    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.double_click = true
    solid.apply_gesture(press)
    var after := [solid.yaw, solid.pitch, solid.zoom, solid.pan]
    var tip := solid.tooltip_text
    solid.free()

    assert_false(moved == [SaGamutSolid.YAW, SaGamutSolid.PITCH, 1.0, Vector2.ZERO], "The gestures moved the view")
    assert_eq(after, [SaGamutSolid.YAW, SaGamutSolid.PITCH, 1.0, Vector2.ZERO], "and a double click puts all four back")
    assert_true(tip.contains("double-click"), "with the tooltip saying so: %s" % tip)


# --- What a dump can read -------------------------------------------------------


## A screenshot of a turned wireframe cannot say a wheel notch landed, so the
## four numbers and the white corner go into the report the dump already carries.
func test_the_report_says_where_the_solid_is_looked_at_from() -> void:
    var solid := _solid()
    _drag(solid, Vector2(0.0, 40.0), false)
    _wheel(solid, true, PANEL * 0.5)
    var report := solid.report()
    solid.free()

    for key: String in ["yaw", "pitch", "zoom", "pan", "white"]:
        assert_true(report.has(key), "The report says %s" % key)
    assert_true(float(report["pitch"]) < SaGamutSolid.PITCH, "and the pitch it says is the one the drag left")
    assert_eq(float(report["zoom"]), SaGamutSolid.WHEEL_STEP, "and the zoom the notch left")
    # The scenarios read these four off the same block, so a key it loses is a scenario
    # that stops reading rather than a test that fails.
    for key: String in ["space", "compare", "space_box", "compare_box", "size", "spread", "distinct"]:
        assert_true(report.has(key), "and it still says %s, which the scenarios read" % key)
