## The ring radius answered inside a mirrored canvas.
##
## A Control mirrors by a negative scale, which `SaCanvasView.get_flip` reads the
## sign of, so a mirrored canvas's global rect comes back with a negative size.
## `Rect2.has_point` refuses such a rect, prints `Rect2 size is negative, this is
## not supported` and answers false, so the canvas both logged an error every
## frame the view was mirrored and was told it had no pointer over it.
## `scenarios/minimap-flip.json`, which touches no chord, raised 462 of them
## in one run.
##
## Same fixture note as `test_canvas_pointer_geometry.gd`: the canvas has to be a
## live one in a real window, because `canvas_ring_radius_at` walks
## `SaCanvas.live_canvases()` and skips anything not in a tree.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const RING: float = 12.0

var _host: Node = null
var _previous_embedding: bool = true


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _previous_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "MirroredCanvasTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _previous_embedding


## A live canvas covering the top left 1920 by 1080 of *window*, unmirrored.
func _registered_canvas(window: Window) -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    window.add_child(canvas)
    canvas.position = Vector2.ZERO
    canvas.scale = Vector2.ONE
    canvas.size = Vector2(1920, 1080)
    canvas.cursor_ring_radius = RING
    return canvas


func _embedded_window(parent: Node) -> Window:
    var window := Window.new()
    window.borderless = true
    window.size = Vector2i(1920, 1080)
    parent.add_child(window)
    window.show()
    return window


## The geometry on its own, with the mirror written straight onto the transform:
## the same pixels are covered and the same point is answered for.
func test_a_negative_rect_answers_for_the_pixels_it_covers() -> void:
    var window := _embedded_window(_host)
    var canvas := _registered_canvas(window)
    var at := Vector2(100, 60)
    assert_almost_eq(SaCursorPolicy.canvas_ring_radius_at(window, at), RING, 0.001, "Unmirrored, the canvas owns the point")

    # Mirrored left to right about the canvas's right edge, which leaves the same
    # 1920 by 1080 of the window covered.
    canvas.position = Vector2(1920, 0)
    canvas.scale = Vector2(-1.0, 1.0)
    # The height, not the width: `get_global_rect` multiplies the size by the
    # transform's scale, and one negated axis puts the sign on the determinant.
    assert_true(canvas.get_global_rect().size.y < 0.0, "The rect really does come back with a negative side")
    assert_almost_eq(SaCursorPolicy.canvas_ring_radius_at(window, at), RING, 0.001, "and the canvas still owns the point")

    # Both axes, which is the state `minimap-flip` leaves the view in after
    # its second click. Two negated axes are a half turn, whose determinant is
    # positive, so this one never printed and was wrong in silence.
    canvas.position = Vector2(1920, 1080)
    canvas.scale = Vector2(-1.0, -1.0)
    assert_almost_eq(SaCursorPolicy.canvas_ring_radius_at(window, at), RING, 0.001, "and with both axes mirrored")


## A point off the canvas stays off it, so the fix is not a rect that swallowed
## the window.
func test_a_point_outside_a_mirrored_canvas_is_still_outside() -> void:
    var window := _embedded_window(_host)
    var canvas := _registered_canvas(window)
    canvas.position = Vector2(960, 0)
    canvas.scale = Vector2(-1.0, 1.0)
    # The canvas now covers x from -960 to 960, so a point past 960 is off it.
    assert_true(SaCursorPolicy.canvas_ring_radius_at(window, Vector2(1400, 60)) < 0.0, "Past the mirrored canvas, no ring")
    assert_almost_eq(SaCursorPolicy.canvas_ring_radius_at(window, Vector2(400, 60)), RING, 0.001, "Inside it, the ring")


## A turned canvas answers for the pixels it draws too, which the rect form could
## not: `Control.get_global_rect` drops the rotation, so the corner of the
## unturned rectangle read as canvas and the turned canvas beside it did not.
func test_a_turned_canvas_answers_for_the_pixels_it_draws() -> void:
    var window := _embedded_window(_host)
    var canvas := _registered_canvas(window)
    # A quarter turn about the origin puts the canvas down the left edge,
    # covering x from -1080 to 0. Nothing of it is left where it was.
    canvas.rotation = PI * 0.5
    assert_true(SaCursorPolicy.canvas_ring_radius_at(window, Vector2(100, 60)) < 0.0, "Where the canvas was, it no longer is")
    assert_almost_eq(SaCursorPolicy.canvas_ring_radius_at(window, Vector2(-60, 100)), RING, 0.001, "and where it is, it is")


## The real path a painter takes: the same `SaView.flip_view` the Minimap's
## buttons and the View menu's rows both call, mirroring about the middle of the
## view, which is the anchor `flip_view` keeps still.
func test_the_view_s_own_mirror_leaves_the_centre_answering_the_same() -> void:
    var window := _embedded_window(_host)
    var canvas := _registered_canvas(window)
    var view := SaCanvasView.for_canvas(canvas)
    var centre := view.get_viewport_size() * 0.5
    var before := SaCursorPolicy.canvas_ring_radius_at(window, centre)
    assert_almost_eq(before, RING, 0.001, "The centre of the view is over the canvas to begin with")

    view.flip_view(true)
    assert_true(view.get_flip().x < 0.0, "The view is mirrored left to right")
    assert_almost_eq(
        SaCursorPolicy.canvas_ring_radius_at(window, centre),
        before,
        0.001,
        "and the point the mirror kept still answers the same"
    )

    view.flip_view(false)
    assert_true(view.get_flip().y < 0.0, "and top to bottom as well")
    assert_almost_eq(SaCursorPolicy.canvas_ring_radius_at(window, centre), before, 0.001, "and it still answers the same")
