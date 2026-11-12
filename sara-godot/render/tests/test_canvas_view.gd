## What a canvas does with the user's zoom and pan.
extends "res://tests/test_framework.gd"

## A canvas builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

var _host: Node = null


## Parented to an autoload rather than to the root, because the runner calls this
## from its own `_ready` and a parent mid-`_ready` rejects `add_child`, leaving
## the node orphaned rather than failing loudly.
func before_each() -> void:
    _host = Node.new()
    _host.name = "CanvasViewTestHost"
    EventBus.add_child(_host)
    # A Size of 100, so the opening Ctrl+0's row gives is the fit read here.
    # Its 90 is `test_the_zoom_reads_as_the_picture_s_size_on_screen`'s.
    SaSettings.reset_zoom_size = 100


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    SaSettings.reset_zoom_size = SaView.RESET_SIZE


## A canvas of *canvas_size* inside a viewport of *viewport_size*, both in the tree.
func _canvas_in_viewport(viewport_size: Vector2i, canvas_size: Vector2i) -> Array:
    var viewport := SubViewport.new()
    viewport.size = viewport_size
    _host.add_child(viewport)
    var canvas := SaCanvas.new()
    canvas.canvas_size = canvas_size
    viewport.add_child(canvas)
    return [viewport, canvas]


## Resizing the window must not throw away where the user was looking.
##
## `_center_canvas` was connected straight to the viewport's `size_changed`, so
## every resize re-fitted the canvas: back to the whole document, centred, at
## whatever zoom made it fit. Dragging a window edge is not a request to lose your
## place in a drawing, and it happened on every edge drag, every maximise and every
## restore.
func test_resizing_the_viewport_keeps_the_zoom_and_the_place() -> void:
    var pair := _canvas_in_viewport(Vector2i(800, 600), Vector2i(256, 256))
    var viewport: SubViewport = pair[0]
    var canvas: SaCanvas = pair[1]

    # Where the user put it: zoomed well past the fit, looking at a corner.
    canvas.scale = Vector2(4.0, 4.0)
    canvas.position = Vector2(-100.0, -60.0)

    viewport.size = Vector2i(1000, 700)
    canvas._on_viewport_resized()

    assert_almost_eq(canvas.scale.x, 4.0, 0.0001, "The zoom is the user's, not the window's")
    # The window grew by 200 x 100, so what was under the middle stays under the
    # middle when the canvas moves by half of that.
    assert_almost_eq(canvas.position.x, 0.0, 0.0001, "and the canvas moved by half the width the window gained")
    assert_almost_eq(canvas.position.y, -10.0, 0.0001, "and half the height")


## The explicit fit still fits a document larger than 100% shown leaves room
## for. It is what a new document wants, and what the canvas wants the first
## time it appears.
func test_centring_still_fits_the_canvas_to_the_window() -> void:
    var canvas: SaCanvas = _canvas_in_viewport(Vector2i(800, 400), Vector2i(800, 800))[1]

    canvas.scale = Vector2(9.0, 9.0)
    canvas._center_canvas()

    # The short side decides, so 400 / 800 rather than 800 / 800.
    assert_almost_eq(canvas.scale.x, 0.5, 0.0001, "Fitted to the tighter axis")
    assert_almost_eq(canvas.position.x, 200.0, 0.0001, "and centred across the wider one")
    assert_almost_eq(canvas.position.y, 0.0, 0.0001, "with no room to spare on the tight one")


## The resize handler is what the viewport calls, and the re-fit is not.
func test_the_viewport_calls_the_handler_that_preserves_the_view() -> void:
    var pair := _canvas_in_viewport(Vector2i(640, 480), Vector2i(256, 256))
    var viewport: SubViewport = pair[0]
    var canvas: SaCanvas = pair[1]

    assert_true(viewport.size_changed.is_connected(canvas._on_viewport_resized), "Resize goes to the handler")
    assert_false(viewport.size_changed.is_connected(canvas._center_canvas), "and not to the old re-fit")


## The mirror rides on the sign of the Control's scale, so the child
## overlays turn with it and nothing needs a second transform. The zoom every
## other caller reads has to stay positive through all of it.
func test_a_flip_is_the_sign_of_the_canvas_scale() -> void:
    var canvas: SaCanvas = _canvas_in_viewport(Vector2i(800, 400), Vector2i(200, 200))[1]
    var view := SaCanvasView.for_canvas(canvas)
    view.set_zoom(3.0)

    view.set_flip(Vector2(-1, 1))

    assert_almost_eq(canvas.scale.x, -3.0, 0.0001, "The canvas draws mirrored")
    assert_almost_eq(canvas.scale.y, 3.0, 0.0001, "on one axis only")
    assert_almost_eq(view.get_zoom(), 3.0, 0.0001, "and the zoom is still what it was")

    view.set_zoom(5.0)

    assert_almost_eq(canvas.scale.x, -5.0, 0.0001, "A zoom keeps the mirror")
    assert_eq(view.get_flip(), Vector2(-1, 1), "which is what the view answers")


## A flip must not reach the document, which is the whole difference between
## this and Image > Flip.
func test_a_flip_leaves_the_document_alone() -> void:
    var canvas: SaCanvas = _canvas_in_viewport(Vector2i(800, 400), Vector2i(200, 200))[1]
    var before := canvas.document.canvas_size
    var chunks := canvas.document.active_layer.chunks.size() if canvas.document.active_layer != null else 0

    SaCanvasView.for_canvas(canvas).flip_view(true)

    assert_eq(canvas.document.canvas_size, before, "The document is the size it was")
    var after := canvas.document.active_layer.chunks.size() if canvas.document.active_layer != null else 0
    assert_eq(after, chunks, "and no chunk was touched")
