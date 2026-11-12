## An Ellipse Select drag held to a circle.
##
## Lessons start with balls drawn with the circle selection tools. A ball's outline is a
## circle and a learner's drag is never one by hand, so Shift pressed after the
## press holds the box square, as in Krita and Photoshop. A press made with
## Shift still adds.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")

## A drag selects on the GPU.
const REQUIRES_GPU := true


func _button(pressed: bool, shift: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.shift_pressed = shift
    return event


func _motion(shift: bool) -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.shift_pressed = shift
    return event


## Presses at *from* with *press_shift*, moves halfway with Shift as it was on
## the press, then to *to* with *drag_shift* down through the move and the
## release, and hands back the document, the machine,
## the surface and the tool. *before*, when not empty, is a box Marquee drags
## first with no key, so a press with Shift has something to add to.
func _drag(tool_id: StringName, from: Vector2, to: Vector2, press_shift: bool, drag_shift: bool, before := Rect2()) -> Array:
    var surface := Fixtures.make_surface(Vector2i(512, 512))
    var machine := Fixtures.make_bound_machine(surface)
    if before.has_area():
        machine.set_active_tool(&"marquee")
        _play(machine.active_tool, surface, before.position, before.end, false, false)
    machine.set_active_tool(tool_id)
    var tool := machine.active_tool
    _play(tool, surface, from, to, press_shift, drag_shift)
    return [surface.get_document(), machine, surface, tool]


func _play(tool: ToolState, surface: Variant, from: Vector2, to: Vector2, press_shift: bool, drag_shift: bool) -> void:
    surface.view.mouse_position = from
    tool.handle_input(_button(true, press_shift))
    surface.view.mouse_position = (from + to) * 0.5
    tool.handle_input(_motion(press_shift))
    surface.view.mouse_position = to
    tool.handle_input(_motion(drag_shift))
    tool.handle_input(_button(false, drag_shift))


func test_shift_after_the_press_holds_ellipse_select_to_a_circle() -> void:
    var parts := _drag(&"ellipse_select", Vector2(100, 100), Vector2(300, 160), false, true)
    var doc: SaDocument = parts[0]
    assert_eq(doc.selection.bounds, Rect2i(100, 100, 200, 200), "The circle's side is the longer of the drag's two")
    Fixtures.teardown(parts[2], parts[1])


## Dragged up and to the left, from a press a fraction into a pixel, the box
## is still square to the pixel and lies towards the pointer.
func test_the_circle_lies_towards_the_pointer_and_is_square_to_the_pixel() -> void:
    var parts := _drag(&"ellipse_select", Vector2(300.4, 300.7), Vector2(220.2, 150.9), false, true)
    var doc: SaDocument = parts[0]
    var bounds := doc.selection.bounds
    assert_eq(bounds.size.x, bounds.size.y, "Square to the pixel: %s" % bounds)
    assert_eq(bounds.end, Vector2i(300, 301), "Its far corner is the press")
    assert_eq(bounds.size.x, 150, "and its side the longer reach, rounded")
    Fixtures.teardown(parts[2], parts[1])


func test_the_same_drag_without_shift_is_the_box_as_before() -> void:
    var parts := _drag(&"ellipse_select", Vector2(100, 100), Vector2(300, 160), false, false)
    var doc: SaDocument = parts[0]
    assert_eq(doc.selection.bounds, Rect2i(100, 100, 200, 60), "Without the key the ellipse fills the box dragged")
    Fixtures.teardown(parts[2], parts[1])


func test_shift_after_the_press_holds_the_marquee_square() -> void:
    var parts := _drag(&"marquee", Vector2(100, 100), Vector2(160, 300), false, true)
    var doc: SaDocument = parts[0]
    assert_eq(doc.selection.bounds, Rect2i(100, 100, 200, 200), "The Marquee drags a square")
    Fixtures.teardown(parts[2], parts[1])


## Shift on the press adds, and held on through the drag it adds without
## squaring, since it has not been let go since the press chose its mode.
func test_a_press_with_shift_still_adds() -> void:
    var parts := _drag(&"ellipse_select", Vector2(300, 300), Vector2(400, 340), true, true, Rect2(20, 20, 50, 50))
    var doc: SaDocument = parts[0]
    var tool: ToolState = parts[3]
    assert_eq(tool._press_mode, SaSelection.Mode.ADD, "The press with Shift is in Add mode")
    assert_eq(doc.selection.bounds, Rect2i(20, 20, 380, 320), "The ellipse joins the box, unsquared")
    Fixtures.teardown(parts[2], parts[1])


func test_shift_let_go_and_pressed_again_squares_an_added_drag() -> void:
    var surface := Fixtures.make_surface(Vector2i(512, 512))
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"ellipse_select")
    var tool := machine.active_tool
    surface.view.mouse_position = Vector2(100, 100)
    tool.handle_input(_button(true, true))
    surface.view.mouse_position = Vector2(150, 120)
    tool.handle_input(_motion(false))
    surface.view.mouse_position = Vector2(200, 140)
    tool.handle_input(_motion(true))
    tool.handle_input(_button(false, true))
    assert_eq(tool._press_mode, SaSelection.Mode.ADD, "The press still adds")
    assert_eq(surface.get_document().selection.bounds, Rect2i(100, 100, 100, 100), "and Shift pressed again squares it")
    Fixtures.teardown(surface, machine)


func test_each_tools_tooltip_says_so() -> void:
    assert_true(BaseModule.marquee_options()[0].tooltip.contains("keeps the box square"), "The Marquee's mode row says so")
    assert_true(BaseModule.ellipse_options()[0].tooltip.contains("a circle"), "and Ellipse Select's")
    assert_false(BaseModule.lasso_options()[1].tooltip.contains("square"), "and the lasso's does not")
