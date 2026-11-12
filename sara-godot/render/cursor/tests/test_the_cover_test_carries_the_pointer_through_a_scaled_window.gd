## The cover test carries the pointer through a scaled window's own units.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter reported: "I found a bug where I see no cursor, on mouse nor
## pen." The Brush Editor was maximised, which puts it at a content scale of
## 1.25, and a note box stood over it with the pointer inside. The test of
## whether a window with nothing drawn in it covers the pointer took the
## editor's point to the root by adding the editor's position alone, so it
## landed a fifth short of the box, the box was missed, the editor's overlay
## said it was drawing, and the system cursor was hidden over a box where
## nothing drew. Here a plain window at 1.25 stands for the editor and a smaller
## one with no overlay for the box, so the answer is the policy's alone.
extends "res://tests/test_framework.gd"

## The scaled window fills most of the root, from its corner.
const SCALED_AT := Vector2i(0, 0)
const SCALED_SIZE := Vector2i(1000, 800)
const SCALE := 1.25

## The smaller window over it, where the painter's pointer was.
const SMALL_AT := Vector2i(400, 480)
const SMALL_SIZE := Vector2i(200, 120)

## Inside the smaller window, in the root's space. In the scaled window's own
## units it is this divided by the scale, which the old sum read as a point
## above and to the left of the smaller window.
const IN_THE_SMALL := Vector2(436.0, 530.0)

var _host: Node = null
var _overlays: Array[Control] = []
var _previous_mode: String = "auto"
var _kept_embedding: bool = true


func before_each() -> void:
    _previous_mode = SaSettings.software_cursor
    SaSettings.software_cursor = "always"
    SaCursorPolicy.forget_pointer_device()
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    # A window of its own would map a real OS window and block the run.
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "ScaledCoverTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    for overlay in _overlays:
        SaCursorPolicy.unregister_overlay(overlay)
    _overlays.clear()
    SaSettings.software_cursor = _previous_mode
    if _host != null:
        _host.free()
        _host = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding


## An embedded window, with an overlay registered in it when *drawn*.
func _window(at: Vector2i, size: Vector2i, drawn: bool) -> Window:
    var window := Window.new()
    window.borderless = true
    window.position = at
    window.size = size
    if drawn:
        var overlay := Control.new()
        window.add_child(overlay)
        SaCursorPolicy.register_overlay(overlay)
        _overlays.append(overlay)
    _host.add_child(window)
    window.show()
    return window


func _pen_at(window: Window, at: Vector2) -> void:
    var motion := InputEventMouseMotion.new()
    motion.tilt = Vector2(0.2, -0.1)
    motion.position = at
    SaCursorPolicy.note_pointer_device(motion, window)


func test_a_point_in_a_scaled_window_reaches_the_root_through_its_scale() -> void:
    var scaled := _window(SCALED_AT, SCALED_SIZE, true)
    scaled.content_scale_factor = SCALE
    var own := IN_THE_SMALL / SCALE
    var in_root := SaCursorPolicy.root_point_of(scaled, own)
    assert_true(
        in_root.is_equal_approx(IN_THE_SMALL), "The scaled window's %s is the root's %s, read %s" % [own, IN_THE_SMALL, in_root]
    )
    var plain := _window(Vector2i(100, 60), SMALL_SIZE, true)
    assert_true(
        SaCursorPolicy.root_point_of(plain, Vector2(10.0, 20.0)).is_equal_approx(Vector2(110.0, 80.0)),
        "and an unscaled one's is its own plus its place, as before"
    )


func test_a_smaller_window_over_a_scaled_one_covers_the_point() -> void:
    var scaled := _window(SCALED_AT, SCALED_SIZE, true)
    scaled.content_scale_factor = SCALE
    var small := _window(SMALL_AT, SMALL_SIZE, false)
    var own := IN_THE_SMALL / SCALE
    _pen_at(scaled, own)
    assert_true(
        Rect2(Vector2(small.position), Vector2(small.size)).has_point(IN_THE_SMALL), "The point is inside the smaller window"
    )
    assert_false(
        Rect2(Vector2(small.position), Vector2(small.size)).has_point(own + Vector2(scaled.position)),
        "where the old sum of the place alone missed it"
    )
    assert_false(SaCursorPolicy.wants_software_pointer(scaled, own), "The point is covered, so the scaled window hides no cursor")
    assert_false(SaCursorPolicy.arrow_drawn_in(scaled, own), "and draws no arrow beneath the smaller window")
    assert_eq(SaCursorPolicy.drawn_at(scaled, own), &"system", "The painter sees the system's pointer there")
    var root := (Engine.get_main_loop() as SceneTree).root
    assert_false(SaCursorPolicy.wants_software_pointer(root, IN_THE_SMALL), "and so does the root, asked the same point")


## Beside the covered point, the scaled window is still the one that draws, so
## the mended sum did not take the arrow away where nothing covers it.
func test_beside_the_smaller_window_the_scaled_one_still_draws() -> void:
    var scaled := _window(SCALED_AT, SCALED_SIZE, true)
    scaled.content_scale_factor = SCALE
    _window(SMALL_AT, SMALL_SIZE, false)
    var beside := Vector2(200.0, 200.0) / SCALE
    _pen_at(scaled, beside)
    assert_true(SaCursorPolicy.arrow_drawn_in(scaled, beside), "Away from the smaller window the scaled one draws the arrow")
