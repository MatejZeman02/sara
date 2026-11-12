## *Both* draws what *Always* draws and leaves the OS pointer where it is.
##
## The point of the mode is a measurement a suite cannot take: the lag between Sara's ring
## and the system's pointer is the distance between them, and no other mode
## shows both at once. *Always* hides the OS pointer wherever the overlay draws,
## and *Auto* is *Always* under Wayland, so the two were never on screen
## together.
##
## What a test can hold is the half that is not a photograph: the mode resolves
## the way *Always* does, and the one thing it changes, the OS pointer staying
## visible, is read in the same tick as the ring being asked for. The distance
## on a real desktop is the painter's own reading, and
## `scenarios/both-cursor-mode.json` is what puts the row on screen for it.
##
## Same fixture note as `test_cursor_modes.gd`: the canvas has to be a live
## one in a real window, because everything here walks `SaCanvas.live_canvases()`
## and skips anything not in a tree. The pointer is pinned rather than moved,
## because Wayland will not let a client place it and the pin is the one reading
## every part of the policy shares.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const RING: float = 12.0
## Over the canvas, which covers the whole of the test window.
const ON_CANVAS := Vector2(100, 60)

var _host: Node = null
var _previous_mode: String = "auto"
var _previous_mouse_mode: int = Input.MOUSE_MODE_VISIBLE


func before_each() -> void:
    _previous_mode = SaSettings.software_cursor
    _previous_mouse_mode = Input.get_mouse_mode()
    _host = Node.new()
    _host.name = "BothCursorModeTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaCursorPolicy.unpin_pointer(self)
    SaCursorPolicy.forget_pointer_device()
    SaSettings.software_cursor = _previous_mode
    if _host != null:
        _host.free()
        _host = null
    # The mouse mode is process-wide, so a suite that hid the pointer and left
    # it hidden takes every suite after it with it.
    if Input.get_mouse_mode() != _previous_mouse_mode:
        Input.set_mouse_mode(_previous_mouse_mode as Input.MouseMode)


func _window() -> Window:
    var window := Window.new()
    window.borderless = true
    window.size = Vector2i(1920, 1080)
    _host.add_child(window)
    window.show()
    return window


## A live canvas covering the whole of *window*, asking for a ring.
func _canvas(window: Window) -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    window.add_child(canvas)
    canvas.position = Vector2.ZERO
    canvas.size = Vector2(1920, 1080)
    canvas.cursor_ring_radius = RING
    return canvas


## The whole claim: the ring is asked for under both modes and only
## *Always* takes the OS pointer away for it.
##
## The mouse mode is read in the same tick the ring is asked for, because the
## rule this file's subject exists under is that the two answers are decided
## together: a pointer hidden on one frame's reading and a ring drawn on
## another's is how a session ends up with nothing under the hand at all.
func test_both_keeps_the_os_pointer_while_always_takes_it() -> void:
    if DisplayServer.get_name() == "headless":
        return
    var window := _window()
    _canvas(window)
    SaCursorPolicy.pin_pointer(self, window, ON_CANVAS)

    SaSettings.software_cursor = "always"
    SaCursorPolicy.sync_os_cursor_visibility()
    assert_almost_eq(SaCursorPolicy.cursor_ring_radius_at(window, ON_CANVAS), RING, 0.001, "Always asks for the ring")
    assert_eq(Input.get_mouse_mode(), Input.MOUSE_MODE_HIDDEN, "and hides the OS pointer to draw it")

    SaSettings.software_cursor = "both"
    SaCursorPolicy.sync_os_cursor_visibility()
    assert_almost_eq(SaCursorPolicy.cursor_ring_radius_at(window, ON_CANVAS), RING, 0.001, "Both asks for the same ring")
    assert_eq(Input.get_mouse_mode(), Input.MOUSE_MODE_VISIBLE, "and leaves the OS pointer beside it, which is the mode")
    assert_eq(SaCursorPolicy.drawn_at(window, ON_CANVAS), &"ring", "so what Sara draws is what Always draws")


## A hidden pointer already standing when the mode is switched has to come back,
## or the painter switches to *Both* and sees one of the two things they asked
## for.
func test_switching_to_both_gives_a_hidden_pointer_back() -> void:
    if DisplayServer.get_name() == "headless":
        return
    var window := _window()
    _canvas(window)
    SaCursorPolicy.pin_pointer(self, window, ON_CANVAS)

    SaSettings.software_cursor = "both"
    Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
    SaCursorPolicy.sync_os_cursor_visibility()
    assert_eq(Input.get_mouse_mode(), Input.MOUSE_MODE_VISIBLE, "Both restores a pointer somebody else hid")


## *Both* differs from *Always* in one thing, so everything else it is asked
## must give the same answer.
##
## The window here is a loose one rather than `_window()`'s, because a window in
## the tree is a subwindow of the root with no overlay in it, and
## `_covered_by_an_undrawn_window` rightly answers that something undrawn stands
## over the point. That is a guard of its own and not this unit's subject,
## so the question is asked where it can be answered, the way
## `test_cursor_overlay.gd` asks it.
func test_both_resolves_everywhere_else_as_always_does() -> void:
    var pen := InputEventMouseMotion.new()
    pen.pressure = 0.7
    SaCursorPolicy.note_pointer_device(pen)
    var window := Window.new()
    window.size = Vector2i(1920, 1080)

    for mode: String in ["always", "both"]:
        SaSettings.software_cursor = mode
        assert_true(SaCursorPolicy.software_pointer_mode_active(), "%s draws Sara's own pointer, whatever the driver is" % mode)
        assert_true(SaCursorPolicy.wants_software_pointer(window, ON_CANVAS), "%s wants it under a pen" % mode)
    window.free()


## A tool's own picture is the eyedropper's today, and *Both* is not *Never*, so
## the picture stays.
func test_both_keeps_a_tools_own_picture() -> void:
    var window := _window()
    var canvas := _canvas(window)
    var registry := Fixtures.make_tool_registry()
    var dropper := registry.get_descriptor(&"eyedropper")
    assert_not_null(dropper.cursor_texture, "the eyedropper names a picture, which is what this is about")

    SaCursorPolicy.apply_tool_cursor(canvas, dropper, dropper.cursor_shape)
    SaSettings.software_cursor = "both"
    assert_true(SaCursorPolicy.tool_cursor_shows_at(window, ON_CANVAS), "Both shows the tool's picture over the canvas")
    SaSettings.software_cursor = "never"
    assert_false(SaCursorPolicy.tool_cursor_shows_at(window, ON_CANVAS), "and Never is still the one that takes it")
    SaCursorPolicy.clear_tool_cursor()


## The row is built from the constant, so the constant is where the order and
## the wording are held.
func test_the_page_offers_four_modes_with_both_last() -> void:
    var ids: Array[String] = []
    var labels: Dictionary = {}
    for mode: Dictionary in SaCursorPolicy.CURSOR_MODES:
        ids.append(String(mode["id"]))
        labels[String(mode["id"])] = String(mode["label"])
    assert_eq(ids, ["auto", "always", "never", "both"] as Array[String], "Both goes beside Never, after the painter's two")
    assert_true(
        String(labels["both"]).to_lower().contains("debugging"),
        "and says on the page that it is a debugging switch, which is what it was added as"
    )
