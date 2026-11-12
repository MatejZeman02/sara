## The crop box with a locked aspect ratio, as arithmetic.
##
## A sibling of `test_crop.gd` rather than an addition to it, because that
## suite is about `SaCrop` re-tiling a document and this one never commits
## anything: it drives the gestures and reads `pending_rect()` back.
##
## The four claims worth pinning are the ones a wrong sign makes plausible: a
## draw takes its shape from the longer axis, a corner pull holds the opposite
## corner, an edge pull drives the other axis about the centre rather than
## sliding the rectangle, and a locked rectangle keeps its shape and its size
## when the hand pulls it off the canvas.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")
const StateCropScript = preload("res://modules/sara-base-modules/base/tools/state_crop.gd")


func test_a_locked_draw_takes_its_shape_from_the_longer_axis() -> void:
    var surface := Fixtures.make_surface(Vector2i(512, 512))
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"crop")
    var tool := machine.active_tool
    tool.ratio = StateCropScript.Ratio.SQUARE

    _drag(tool, surface.view, Vector2(100, 100), Vector2(300, 200))
    assert_eq(tool.pending_rect(), Rect2i(100, 100, 200, 200), "A square lock grows the shorter axis to the longer")

    tool.ratio = StateCropScript.Ratio.R16_9
    _draw(tool, surface.view, Vector2(100, 100), Vector2(300, 200))
    assert_eq(tool.pending_rect(), Rect2i(100, 100, 200, 113), "and 16:9 derives the height from the width")

    tool.ratio = StateCropScript.Ratio.FREE
    _draw(tool, surface.view, Vector2(100, 100), Vector2(300, 200))
    assert_eq(tool.pending_rect(), Rect2i(100, 100, 200, 100), "Free is the drag the tool always had")
    Fixtures.teardown(surface, machine)


func test_the_document_ratio_follows_the_canvas() -> void:
    var surface := Fixtures.make_surface(Vector2i(400, 200))
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"crop")
    var tool := machine.active_tool
    tool.ratio = StateCropScript.Ratio.DOCUMENT
    assert_almost_eq(tool.locked_ratio(), 2.0, 0.001, "A 400 by 200 canvas is 2:1")

    _drag(tool, surface.view, Vector2(10, 10), Vector2(110, 60))
    assert_eq(tool.pending_rect(), Rect2i(10, 10, 100, 50), "and the box comes out the document's own shape")
    Fixtures.teardown(surface, machine)


func test_a_corner_holds_its_opposite_and_an_edge_drives_the_other_axis() -> void:
    var surface := Fixtures.make_surface(Vector2i(512, 512))
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"crop")
    var tool := machine.active_tool
    tool.ratio = StateCropScript.Ratio.SQUARE

    _drag(tool, surface.view, Vector2(100, 100), Vector2(300, 200))
    assert_eq(tool.pending_rect(), Rect2i(100, 100, 200, 200), "A square to pull on")

    # The bottom right handle, which holds the top left corner.
    _drag(tool, surface.view, Vector2(300, 300), Vector2(260, 260))
    assert_eq(tool.pending_rect(), Rect2i(100, 100, 160, 160), "A corner pull holds the opposite corner")

    # The right edge handle. Its own axis is pulled and the other follows,
    # about the centre, so the rectangle does not walk up the canvas.
    _drag(tool, surface.view, Vector2(260, 180), Vector2(300, 180))
    assert_eq(tool.pending_rect(), Rect2i(100, 80, 200, 200), "An edge pull drives the other axis about the centre")
    Fixtures.teardown(surface, machine)


## The canvas is not part of the lock. The rectangle is not shrunk to fit,
## because a clipped square is not a square. The
## commit grows, so the shape and the size the hand gave it both survive and
## the document gains the ground beyond the edge.
func test_a_locked_rectangle_keeps_its_shape_off_the_canvas() -> void:
    var surface := Fixtures.make_surface(Vector2i(512, 512))
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"crop")
    var tool := machine.active_tool
    tool.ratio = StateCropScript.Ratio.SQUARE

    # Drawn from 400 to the right, so 200 of square ends at 600 and the canvas
    # ends at 512. The held corner stays and nothing is cut back.
    _drag(tool, surface.view, Vector2(400, 100), Vector2(500, 300))
    var drawn: Rect2i = tool.pending_rect()
    assert_eq(drawn.position, Vector2i(400, 100), "The corner the hand holds does not move")
    assert_eq(drawn.size, Vector2i(200, 200), "the square is the size the longer axis asked for")
    assert_false(Rect2i(Vector2i.ZERO, Vector2i(512, 512)).encloses(drawn), "and it hangs off the canvas")

    # A move no longer slides back inside either, which was the other clamp.
    _drag(tool, surface.view, Vector2(450, 150), Vector2(520, 150))
    assert_eq(tool.pending_rect(), Rect2i(470, 100, 200, 200), "A move takes the rectangle where the hand put it")

    tool.ratio = StateCropScript.Ratio.FREE
    _draw(tool, surface.view, Vector2(400, 100), Vector2(600, 300))
    assert_eq(tool.pending_rect(), Rect2i(400, 100, 200, 200), "A free rectangle leaves the canvas as it always did")
    Fixtures.teardown(surface, machine)


## A fresh rectangle, with whatever was there dropped first. Without the drop
## the press lands on a handle of the old rectangle and pulls it instead, which
## is the tool working correctly and not what these cases are asking about.
static func _draw(tool: StateCropScript, view: SaView, from: Vector2, to: Vector2) -> void:
    tool.reset()
    _drag(tool, view, from, to)


## One press, one motion and one release, which is what the tool needs to see
## before `pending_rect()` is the rectangle it would commit.
static func _drag(tool: StateCropScript, view: SaView, from: Vector2, to: Vector2) -> void:
    view.mouse_position = from
    tool.handle_input(_button(true))
    view.mouse_position = to
    tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_button(false))


static func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event
