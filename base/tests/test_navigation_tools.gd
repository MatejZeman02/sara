## StatePan, StateZoom and StateEraser: the tools with no pixels of their own.
##
## They go through SaView rather than a Control, which is what lets them be
## driven here with a fake view and no scene tree.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Zoom invalidates the document's chunks, so a real one has to exist.
const REQUIRES_GPU := true

const StatePanScript = preload("res://modules/sara-base-modules/base/tools/state_pan.gd")
const StateZoomScript = preload("res://modules/sara-base-modules/base/tools/state_zoom.gd")
const StateEraserScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_eraser.gd")

var _surface: SaSurface = null


func before_each() -> void:
    _surface = Fixtures.make_surface()


func after_each() -> void:
    Fixtures.teardown(_surface)
    _surface = null


func _press(at: Vector2 = Vector2.ZERO) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = true
    event.position = at
    event.global_position = at
    return event


func _release(at: Vector2 = Vector2.ZERO) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = false
    event.global_position = at
    return event


func _motion(relative: Vector2, at: Vector2 = Vector2.ZERO) -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.relative = relative
    event.global_position = at
    return event


# --- Pan ---------------------------------------------------------------------------


## The pointer crosses the canvas constantly without any button held. Panning on
## bare motion would drag the view whenever the mouse moved.
func test_motion_without_a_button_does_not_pan() -> void:
    var tool := StatePanScript.new()
    tool.surface = _surface

    tool.handle_input(_motion(Vector2(50, 50)))

    assert_eq(_surface.view.get_pan(), Vector2.ZERO, "Nothing moves until a button is down")


func test_a_drag_moves_the_view_by_the_pointer_delta() -> void:
    var tool := StatePanScript.new()
    tool.surface = _surface

    tool.handle_input(_press())
    tool.handle_input(_motion(Vector2(30, -12)))

    assert_eq(_surface.view.get_pan(), Vector2(30, -12), "The view follows the pointer one to one")


func test_releasing_stops_the_drag() -> void:
    var tool := StatePanScript.new()
    tool.surface = _surface

    tool.handle_input(_press())
    tool.handle_input(_motion(Vector2(10, 10)))
    tool.handle_input(_release())
    tool.handle_input(_motion(Vector2(100, 100)))

    assert_eq(_surface.view.get_pan(), Vector2(10, 10), "Motion after the release is not a pan")


## Switching tools mid-drag leaves the button state stale otherwise, and the
## next motion after switching back would pan without a press.
func test_reset_ends_a_drag_in_progress() -> void:
    var tool := StatePanScript.new()
    tool.surface = _surface
    tool.handle_input(_press())

    tool.reset()
    tool.handle_input(_motion(Vector2(40, 40)))

    assert_eq(_surface.view.get_pan(), Vector2.ZERO, "A reset tool is not mid-drag")


## Deltas arrive fractional at tablet rate. Accumulating them into anything that
## rounds loses the fraction on every event, and the view drifts away from the
## pointer over a long drag - the pitfall this asserts against.
func test_sub_pixel_deltas_accumulate_without_loss() -> void:
    var tool := StatePanScript.new()
    tool.surface = _surface
    tool.handle_input(_press())

    for i in 10:
        tool.handle_input(_motion(Vector2(0.25, 0.25)))

    assert_almost_eq(_surface.view.get_pan().x, 2.5, 0.0001, "Ten quarter-pixel moves are two and a half pixels")


# --- Zoom ---------------------------------------------------------------------------


func test_dragging_up_zooms_in_and_down_zooms_out() -> void:
    var tool := StateZoomScript.new()
    tool.surface = _surface

    tool.handle_input(_press(Vector2(500, 500)))
    tool.handle_input(_motion(Vector2.ZERO, Vector2(500, 400)))
    var zoomed_in := _surface.view.get_zoom()

    _surface.view.set_zoom(1.0)
    _surface.view.set_pan(Vector2.ZERO)
    tool.handle_input(_press(Vector2(500, 500)))
    tool.handle_input(_motion(Vector2.ZERO, Vector2(500, 600)))
    var zoomed_out := _surface.view.get_zoom()

    assert_true(zoomed_in > 1.0, "Dragging up magnifies")
    assert_true(zoomed_out < 1.0, "Dragging down shrinks")


## The reason the factor is exponential rather than added. The same drag has to
## feel the same at 10% as at 400%, which means it multiplies the scale by the
## same amount rather than moving it by a fixed step.
func test_the_same_drag_multiplies_the_zoom_by_the_same_factor() -> void:
    var ratios: Array[float] = []
    for start_scale: float in [0.1, 4.0]:
        var tool := StateZoomScript.new()
        tool.surface = _surface
        _surface.view.set_zoom(start_scale)
        _surface.view.set_pan(Vector2.ZERO)

        tool.handle_input(_press(Vector2(500, 500)))
        tool.handle_input(_motion(Vector2.ZERO, Vector2(500, 400)))
        ratios.append(_surface.view.get_zoom() / start_scale)

    assert_almost_eq(ratios[0], ratios[1], 0.0001, "A drag is a multiplier, not a step")


## What the pan adjustment is for. Zooming has to keep whatever the user is
## looking at where it is, or the canvas slides away under the pointer. The tool
## pins the press and not the screen centre, so a press on a corner does not
## zoom away from the corner. It does it through SaView.zoom_at.
func test_the_point_under_the_press_stays_there() -> void:
    var tool := StateZoomScript.new()
    tool.surface = _surface
    _surface.view.set_zoom(2.0)
    _surface.view.set_pan(Vector2(100, 40))
    var pressed := Vector2(800, 700)
    var before := (pressed - _surface.view.get_pan()) / _surface.view.get_zoom()

    tool.handle_input(_press(pressed))
    tool.handle_input(_motion(Vector2.ZERO, pressed - Vector2(0, 150)))

    assert_true(_surface.view.get_zoom() > 2.0, "The drag zoomed in")
    var after := (pressed - _surface.view.get_pan()) / _surface.view.get_zoom()
    assert_almost_eq(after.x, before.x, 0.001, "and the document point under the press is unchanged")
    assert_almost_eq(after.y, before.y, 0.001, "in both axes")


func test_the_zoom_is_clamped_at_both_ends() -> void:
    var tool := StateZoomScript.new()
    tool.surface = _surface

    _surface.view.set_zoom(50.0)
    tool.handle_input(_press(Vector2(500, 900)))
    tool.handle_input(_motion(Vector2.ZERO, Vector2(500, 0)))
    assert_almost_eq(_surface.view.get_zoom(), SaView.ZOOM_MAX, 0.001, "A huge drag stops at the ceiling")

    tool.reset()
    _surface.view.set_zoom(0.02)
    tool.handle_input(_press(Vector2(500, 0)))
    tool.handle_input(_motion(Vector2.ZERO, Vector2(500, 900)))
    assert_almost_eq(_surface.view.get_zoom(), SaView.ZOOM_MIN, 0.001, "and the other way at the floor")


## A viewport with no height happens during window setup, before the first
## resize. Dividing by it would be a division by zero on the hot path.
func test_a_viewport_with_no_height_is_a_no_op() -> void:
    var tool := StateZoomScript.new()
    tool.surface = _surface
    _surface.view.viewport_size = Vector2(1000, 0)

    tool.handle_input(_press(Vector2(500, 500)))
    tool.handle_input(_motion(Vector2.ZERO, Vector2(500, 400)))

    assert_almost_eq(_surface.view.get_zoom(), 1.0, 0.0001, "Nothing is scaled by an unmeasurable viewport")


func test_releasing_ends_the_zoom() -> void:
    var tool := StateZoomScript.new()
    tool.surface = _surface

    tool.handle_input(_press(Vector2(500, 500)))
    tool.handle_input(_release(Vector2(500, 500)))
    var clicked := _surface.view.get_zoom()
    tool.handle_input(_motion(Vector2.ZERO, Vector2(500, 200)))

    # The press and release in one place are a click, one notch in.
    assert_almost_eq(_surface.view.get_zoom(), clicked, 0.0001, "Motion after the release does not zoom")


# --- Eraser ---------------------------------------------------------------------------


## The eraser is the brush with one thing changed, which is why it is one
## tool's engine rather than two.
##
## It does not set `is_eraser`, and that field is the pen's flipped end
## telling the *brush* to erase: `state_brush.gd` overwrites it with
## `event.pen_inverted` on every motion, so a mouse cleared it before the first
## dab. The blend mode is the whole declaration, and it is what both paths
## read. `_dispatch_brush` takes the direct-paint route on `is_erasing`, which
## is the blend mode or the toggle or the pen, and `composite.gmacs` dispatches
## on the mode.
func test_the_eraser_is_a_brush_configured_to_erase() -> void:
    var tool := StateEraserScript.new()

    assert_eq(tool.settings.blend_mode, SaLayer.BLEND_MODE.ERASE, "The kernel takes the erase path from the blend mode")
    assert_false(tool.is_eraser, "and nothing rests on the flag a motion event overwrites")
