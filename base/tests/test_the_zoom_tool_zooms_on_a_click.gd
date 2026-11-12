## A click with the Zoom tool zooms in about the point and a Shift+click
## zooms out, by the wheel's notch.
##
## The tool zoomed on the vertical drag alone, so a click had a distance of zero
## and a factor of one and the `canvas` sweep found the zoom unchanged at 0.8741
## after a click, a Shift+click and a sideways drag. The drag cases stay in
## `test_navigation_tools.gd`, and these extend them.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Zoom invalidates the document's chunks, so a real one has to exist.
const REQUIRES_GPU := true

const StateZoomScript = preload("res://modules/sara-base-modules/base/tools/state_zoom.gd")

var _surface: SaSurface = null


func before_each() -> void:
    _surface = Fixtures.make_surface()


func after_each() -> void:
    Fixtures.teardown(_surface)
    _surface = null


func _button(at: Vector2, pressed: bool, shift: bool = false) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.shift_pressed = shift
    event.position = at
    event.global_position = at
    return event


func _motion(at: Vector2) -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.position = at
    event.global_position = at
    return event


func _tool() -> Object:
    var tool := StateZoomScript.new()
    tool.surface = _surface
    return tool


func _document_point(screen: Vector2) -> Vector2:
    return _surface.view.screen_to_document(screen)


func test_a_click_zooms_in_by_one_step_about_the_point() -> void:
    _surface.view.set_zoom(0.8)
    _surface.view.set_pan(Vector2(60, 30))
    var at := Vector2(700, 420)
    var before := _document_point(at)
    var tool := _tool()

    tool.handle_input(_button(at, true))
    tool.handle_input(_button(at, false))

    assert_almost_eq(_surface.view.get_zoom(), 0.8 * SaView.ZOOM_STEP, 0.0001, "A click is one notch in")
    var after := _document_point(at)
    assert_almost_eq(after.x, before.x, 0.001, "and the document point under the click stays there")
    assert_almost_eq(after.y, before.y, 0.001, "in both axes")


func test_a_shift_click_zooms_out_by_the_same_step() -> void:
    _surface.view.set_zoom(2.0)
    var at := Vector2(300, 250)
    var before := _document_point(at)
    var tool := _tool()

    tool.handle_input(_button(at, true, true))
    tool.handle_input(_button(at, false))

    assert_almost_eq(_surface.view.get_zoom(), 2.0 / SaView.ZOOM_STEP, 0.0001, "A Shift+click is one notch out")
    var after := _document_point(at)
    assert_almost_eq(after.x, before.x, 0.001, "about the point clicked")
    assert_almost_eq(after.y, before.y, 0.001, "in both axes")


## Shift is read off the press, so letting go of it before the button still
## zooms out, and pressing it only for the release does not.
func test_shift_is_what_the_press_had() -> void:
    var tool := _tool()

    tool.handle_input(_button(Vector2(500, 500), true))
    tool.handle_input(_button(Vector2(500, 500), false, true))

    assert_almost_eq(_surface.view.get_zoom(), SaView.ZOOM_STEP, 0.0001, "Shift held on the release alone zooms in")


## A hand is never still. A press that wanders a few pixels is still a click,
## and it is exactly one notch, not one notch on top of what the wander dragged.
func test_a_jitter_inside_the_slop_is_still_one_step() -> void:
    var tool := _tool()

    tool.handle_input(_button(Vector2(500, 500), true))
    tool.handle_input(_motion(Vector2(502, 497)))
    tool.handle_input(_button(Vector2(501, 498), false))

    assert_almost_eq(_surface.view.get_zoom(), SaView.ZOOM_STEP, 0.0001, "A wobbly click is one notch")


func test_a_vertical_drag_zooms_as_before_and_adds_no_step() -> void:
    var tool := _tool()

    tool.handle_input(_button(Vector2(500, 500), true))
    tool.handle_input(_motion(Vector2(500, 400)))
    var dragged := _surface.view.get_zoom()
    tool.handle_input(_button(Vector2(500, 400), false))

    assert_true(dragged > 1.0, "Dragging up magnifies")
    assert_almost_eq(_surface.view.get_zoom(), dragged, 0.0001, "and the release of a drag is not a click")


## Out past the slop and back again is a drag that ended where it began, and it
## leaves the zoom where the drag put it, which is one.
func test_a_drag_that_returns_to_the_press_is_not_a_click() -> void:
    var tool := _tool()

    tool.handle_input(_button(Vector2(500, 500), true))
    tool.handle_input(_motion(Vector2(500, 450)))
    tool.handle_input(_motion(Vector2(500, 500)))
    tool.handle_input(_button(Vector2(500, 500), false))

    assert_almost_eq(_surface.view.get_zoom(), 1.0, 0.0001, "A drag back to the start is no click")


func test_the_tool_declares_its_hint_for_the_docker() -> void:
    var specs: Array[SaOptionSpec] = StateZoomScript.options()

    assert_eq(specs.size(), 1, "One row, the sentence")
    assert_eq(specs[0].kind, SaOptionSpec.Kind.CUSTOM, "built by the tool")
    assert_false(specs[0].bar, "and kept off the bar")
    var built := specs[0].build_control.call(specs[0], Callable()) as Control
    # A bare `Label` is what the docker's row takes for its label column, and it
    # was never placed, so the sentence has to come in a box.
    assert_false(built is Label, "The row is not a bare label")
    var label := built.get_node_or_null("Hint") as Label
    assert_not_null(label, "and holds the sentence")
    if label != null:
        assert_eq(label.text, StateZoomScript.HINT, "saying what a click, a Shift+click and a drag do")
    built.free()
