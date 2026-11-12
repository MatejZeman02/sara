## A crop must not throw the painter's zoom and pan away.
##
## The note: "Cropping should not change the zoom level. Right now it auto scales
## down to the cropped variant to be on 100%. I wanna retain the same zoom.
## Recalculate it behind the scenes so it doesn't jump for the user."
##
## `SaCanvas.resize_canvas` ended in `_center_canvas`, which writes the fit
## outright, so every crop, every undo of one and every Image > Canvas Size
## refitted the whole document to the viewport. The same bug one gesture over is
## already recorded in this file's sibling, `test_canvas_view.gd`: `_center_canvas`
## was connected straight to `size_changed` and a window drag lost your place.
##
## What is asserted here is the stronger of the two readings of "it doesn't jump":
## not merely that the zoom survives, but that every texel the crop kept stays on
## the screen pixel it was already on, which is what the rectangle riding on
## `SaDocument.resize_source` buys.
extends "res://tests/test_framework.gd"

## A canvas builds an easel, and a crop dispatches `crop.gmacs`.
const REQUIRES_GPU := true

var _host: Node = null


## Parented to an autoload rather than to the root, because the runner calls this
## from its own `_ready` and a parent mid-`_ready` rejects `add_child`, leaving
## the node orphaned rather than failing loudly.
func before_each() -> void:
    _host = Node.new()
    _host.name = "CropZoomTestHost"
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


## Where a document point is drawn, in the viewport's own pixels. Through the
## Control's transform rather than through `position` and `scale` by hand, so a
## mirrored or turned view is read the same way the screen reads it.
func _drawn_at(canvas: SaCanvas, point: Vector2) -> Vector2:
    return canvas.get_transform() * point


## The case that matters: the zoom is read across a `resize_canvas`.
##
## The rectangle says the new document is the old one from (120, 90) on, so the
## texel that was at (120, 90) is the origin now and has to still be drawn where
## it was.
func test_a_resize_over_a_source_keeps_the_zoom_and_the_place() -> void:
    var canvas: SaCanvas = _canvas_in_viewport(Vector2i(800, 600), Vector2i(400, 300))[1]
    canvas.scale = Vector2(2.5, 2.5)
    canvas.position = Vector2(-60.0, -40.0)
    var was := _drawn_at(canvas, Vector2(120.0, 90.0))

    canvas.resize_canvas(Vector2i(200, 150), Rect2i(120, 90, 200, 150))

    assert_almost_eq(canvas.scale.x, 2.5, 1e-4, "The zoom is the painter's, not the fit")
    assert_almost_eq(canvas.scale.y, 2.5, 1e-4, "on both axes")
    var now := _drawn_at(canvas, Vector2.ZERO)
    assert_almost_eq(now.x, was.x, 1e-3, "and the texel that became the origin did not move")
    assert_almost_eq(now.y, was.y, 1e-3, "on either axis")


## The other half of the same call. A resize nobody described is File > New, File
## > Open, a recovered autosave and the boot, and every one of those wants the
## document shown the way a new one opens, fitted when it is larger than 100%
## shown would leave room for.
func test_a_resize_with_no_source_still_fits() -> void:
    var canvas: SaCanvas = _canvas_in_viewport(Vector2i(800, 400), Vector2i(400, 300))[1]
    canvas.scale = Vector2(9.0, 9.0)
    canvas.position = Vector2(-500.0, -500.0)

    canvas.resize_canvas(Vector2i(800, 800))

    # The short side decides, so 400 / 800 rather than 800 / 800.
    assert_almost_eq(canvas.scale.x, 0.5, 1e-4, "Fitted to the tighter axis")
    assert_almost_eq(canvas.position.x, 200.0, 1e-3, "and centred across the wider one")
    assert_almost_eq(canvas.position.y, 0.0, 1e-3, "with no room to spare on the tight one")


## The whole path, the way a painter walks it: a real crop through `SaCrop`, which
## announces `document_resized`, which the view is listening to.
func test_a_crop_leaves_the_picture_where_it_was() -> void:
    var canvas: SaCanvas = _canvas_in_viewport(Vector2i(800, 600), Vector2i(512, 512))[1]
    canvas.scale = Vector2(3.0, 3.0)
    canvas.position = Vector2(-220.0, -140.0)
    var kept := Vector2(300.0, 260.0)
    var was := _drawn_at(canvas, kept)

    var crop := SaCrop.new(canvas.document)
    assert_true(crop.crop_to(Rect2i(100, 80, 300, 320)), "The crop happens")

    assert_eq(canvas.canvas_size, Vector2i(300, 320), "and the view is the rectangle")
    assert_almost_eq(canvas.scale.x, 3.0, 1e-4, "The zoom did not auto scale to the cropped variant")
    var now := _drawn_at(canvas, kept - Vector2(100.0, 80.0))
    assert_almost_eq(now.x, was.x, 1e-3, "and a texel the crop kept is on the pixel it was on")
    assert_almost_eq(now.y, was.y, 1e-3, "on either axis")


## Undo is the same move backwards, and the view has to follow it back. The
## rectangle for the undo is kept in the history step rather than re-derived,
## because from the cropped document the old origin is off its top left.
func test_the_undo_of_a_crop_puts_the_view_back() -> void:
    var canvas: SaCanvas = _canvas_in_viewport(Vector2i(800, 600), Vector2i(512, 512))[1]
    canvas.scale = Vector2(3.0, 3.0)
    canvas.position = Vector2(-220.0, -140.0)
    var kept := Vector2(300.0, 260.0)
    var was := _drawn_at(canvas, kept)

    var crop := SaCrop.new(canvas.document)
    assert_true(crop.crop_to(Rect2i(100, 80, 300, 320)), "The crop happens")
    assert_true(canvas.document.undo(), "and undo takes it back")

    assert_eq(canvas.canvas_size, Vector2i(512, 512), "The document is the size it was")
    assert_almost_eq(canvas.scale.x, 3.0, 1e-4, "and the zoom is still the painter's")
    var now := _drawn_at(canvas, kept)
    assert_almost_eq(now.x, was.x, 1e-3, "and the texel is back where it was drawn")
    assert_almost_eq(now.y, was.y, 1e-3, "on either axis")


## The redo after that undo, which is where a rectangle stored at the wrong size
## would show: the state dictionary swaps the move each time it fires.
func test_the_redo_of_a_crop_moves_the_view_again() -> void:
    var canvas: SaCanvas = _canvas_in_viewport(Vector2i(800, 600), Vector2i(512, 512))[1]
    canvas.scale = Vector2(3.0, 3.0)
    canvas.position = Vector2(-220.0, -140.0)
    var kept := Vector2(300.0, 260.0)
    var was := _drawn_at(canvas, kept)

    var crop := SaCrop.new(canvas.document)
    assert_true(crop.crop_to(Rect2i(100, 80, 300, 320)), "The crop happens")
    assert_true(canvas.document.undo(), "and undo takes it back")
    assert_true(canvas.document.redo(), "and redo puts it on again")

    assert_eq(canvas.canvas_size, Vector2i(300, 320), "The document is the rectangle again")
    assert_almost_eq(canvas.scale.x, 3.0, 1e-4, "at the zoom it has kept throughout")
    var now := _drawn_at(canvas, kept - Vector2(100.0, 80.0))
    assert_almost_eq(now.x, was.x, 1e-3, "and the texel is on the pixel it started on")
    assert_almost_eq(now.y, was.y, 1e-3, "on either axis")


## the mirror rides on the sign of the Control's scale and the view turns about
## a pivot pinned at the origin. Reading the correction off `position` and `scale`
## by hand would come out mirrored or turned by the rotation, so the code reads
## the Control's transform and this asks whether that was enough.
func test_a_turned_and_mirrored_view_keeps_its_place_too() -> void:
    var canvas: SaCanvas = _canvas_in_viewport(Vector2i(800, 600), Vector2i(512, 512))[1]
    var view := SaCanvasView.for_canvas(canvas)
    view.set_zoom(2.0)
    view.set_flip(Vector2(-1, 1))
    view.set_rotation(0.4)
    canvas.position = Vector2(420.0, -60.0)
    var kept := Vector2(300.0, 260.0)
    var was := _drawn_at(canvas, kept)

    var crop := SaCrop.new(canvas.document)
    assert_true(crop.crop_to(Rect2i(100, 80, 300, 320)), "The crop happens")

    assert_almost_eq(view.get_zoom(), 2.0, 1e-4, "The zoom survived")
    assert_almost_eq(canvas.rotation, 0.4, 1e-4, "and so did the turn")
    assert_eq(view.get_flip(), Vector2(-1, 1), "and the mirror")
    var now := _drawn_at(canvas, kept - Vector2(100.0, 80.0))
    assert_almost_eq(now.x, was.x, 1e-3, "and the texel is on the pixel it was on")
    assert_almost_eq(now.y, was.y, 1e-3, "on either axis")


## The contract the rectangle travels under. `document_resized` has six listeners
## and only the view wants the rectangle, so it rides on the document for exactly
## the length of the emit: a listener of any later resize that read the field
## would otherwise get a stale crop and move the picture for nothing.
func test_the_source_rectangle_lives_only_inside_the_emit() -> void:
    var easel := SaEasel.create_default(Vector2i(512, 512))
    var doc: SaDocument = easel.document
    var seen: Array[Rect2i] = []
    var watcher := func(which: SaDocument, _size: Vector2i) -> void:
        if which == doc:
            seen.append(doc.resize_source)
    EventBus.document_resized.connect(watcher)

    var crop := SaCrop.new(doc)
    assert_true(crop.crop_to(Rect2i(100, 80, 300, 320)), "The crop happens")
    EventBus.document_resized.disconnect(watcher)

    assert_eq(seen.size(), 1, "One announcement")
    assert_eq(seen[0], Rect2i(100, 80, 300, 320), "carrying the rectangle the crop was")
    assert_eq(doc.resize_source, Rect2i(), "and the document says nothing once it is over")
    easel.free()


## Image > Canvas Size runs the same pass with a rectangle that reaches outside
## the document, and a grow moves the origin the other way. The view has to follow
## a negative origin as readily as a positive one.
func test_a_grow_moves_the_view_the_other_way() -> void:
    var canvas: SaCanvas = _canvas_in_viewport(Vector2i(800, 600), Vector2i(256, 256))[1]
    canvas.scale = Vector2(2.0, 2.0)
    canvas.position = Vector2(100.0, 40.0)
    var kept := Vector2(64.0, 64.0)
    var was := _drawn_at(canvas, kept)

    var crop := SaCrop.new(canvas.document)
    # Centred, so the old picture sits 32 texels in on each side of a 320 square.
    assert_true(crop.resize_to(Vector2i(320, 320), Vector2i(1, 1)), "The grow happens")

    assert_eq(canvas.canvas_size, Vector2i(320, 320), "The view is the bigger document")
    assert_almost_eq(canvas.scale.x, 2.0, 1e-4, "at the zoom it had")
    var now := _drawn_at(canvas, kept + Vector2(32.0, 32.0))
    assert_almost_eq(now.x, was.x, 1e-3, "and the picture did not move under the margin it gained")
    assert_almost_eq(now.y, was.y, 1e-3, "on either axis")
