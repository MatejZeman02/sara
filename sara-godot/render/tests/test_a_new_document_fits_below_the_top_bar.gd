## A new document's fit lands below the top bar.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `SaCanvas.resize_canvas` with no source rectangle is the fit File > New, File >
## Open, a recovered autosave and the boot all get. d41 moved View > Fit to View
## into what the covers leave and this fit stayed on the whole window, so a 768
## square resized at an interface scale of 0.9 still had its top row of twelve
## under the menus. What is stated here is that fit on a real canvas in a viewport
## with covers, and that it is the same placement Fit to View makes. The
## documents are larger than 100% shown leaves room for, because a smaller one
## opens at 100% shown and is not fitted. The shots are
## `scenarios/a-new-documents-fit-still-puts-its-top-under-the-top-bar.json`,
## and `test_canvas_view.gd` keeps the fit on a viewport with nothing over it.
extends "res://tests/test_framework.gd"

## A real SaCanvas builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

var _host: Node = null


## Parented to an autoload rather than to the root, for the reason
## `test_canvas_view.gd` gives: the runner calls a suite from its own `_ready`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "D42TestHost"
    EventBus.add_child(_host)
    # A Size of 100, so the opening Ctrl+0's row gives is the fit read here.
    # Its 90 is `test_the_zoom_reads_as_the_picture_s_size_on_screen`'s.
    SaSettings.reset_zoom_size = 100


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    SaSettings.reset_zoom_size = SaView.RESET_SIZE


func test_a_resized_document_lands_below_a_cover_along_the_top() -> void:
    var viewport := _viewport(Vector2i(800, 600))
    var canvas := _canvas(viewport, Vector2i(256, 256))
    _cover(viewport, Rect2(0.0, 0.0, 800.0, 50.0))
    # Somewhere a painter left it, so a fit that did nothing cannot pass.
    canvas.scale = Vector2(9.0, 9.0)
    canvas.position = Vector2(-300.0, -300.0)

    canvas.resize_canvas(Vector2i(1024, 1024))

    var zoom := 550.0 / 1024.0
    assert_almost_eq(canvas.scale.x, zoom, 1e-4, "The height the cover leaves decides the zoom")
    assert_almost_eq(canvas.scale.y, zoom, 1e-4, "on both axes")
    assert_almost_eq(canvas.position.y, 50.0, 1e-3, "The document's top edge is the cover's bottom edge, not under it")
    assert_almost_eq(canvas.position.y + 1024.0 * zoom, 600.0, 1e-3, "and its bottom edge is the viewport's")
    assert_almost_eq(canvas.position.x + 512.0 * zoom, 400.0, 1e-3, "centred across the width")


func test_a_cover_along_each_edge_narrows_the_fit_from_both_ends() -> void:
    var viewport := _viewport(Vector2i(800, 600))
    var canvas := _canvas(viewport, Vector2i(256, 256))
    _cover(viewport, Rect2(0.0, 0.0, 800.0, 50.0))
    _cover(viewport, Rect2(0.0, 570.0, 800.0, 30.0))

    canvas.resize_canvas(Vector2i(1024, 1024))

    var zoom := 520.0 / 1024.0
    assert_almost_eq(canvas.scale.x, zoom, 1e-4, "What is left between the two covers decides the zoom")
    assert_almost_eq(canvas.position.y, 50.0, 1e-3, "The top is below the top cover")
    assert_almost_eq(canvas.position.y + 1024.0 * zoom, 570.0, 1e-3, "and the bottom above the bottom one")


## A document the width decides is centred in the height the cover leaves, not
## in the whole window's, which would put its middle 50 units too high.
func test_a_wide_document_is_centred_in_what_the_cover_leaves() -> void:
    var viewport := _viewport(Vector2i(800, 600))
    var canvas := _canvas(viewport, Vector2i(256, 256))
    _cover(viewport, Rect2(0.0, 0.0, 800.0, 100.0))

    canvas.resize_canvas(Vector2i(1600, 400))

    assert_almost_eq(canvas.scale.x, 0.5, 1e-4, "The width decides, 800 over 1600")
    assert_almost_eq(canvas.position.x, 0.0, 1e-3, "and the document spans it")
    assert_almost_eq(canvas.position.y + 100.0, 350.0, 1e-3, "Its middle is the middle of the 500 under the cover")


## The fit a new document gets and the fit View > Fit to View makes are one
## placement, which is the point: d41 fixed the second and left the first.
func test_the_new_documents_fit_is_the_fit_to_view_placement() -> void:
    var viewport := _viewport(Vector2i(1536, 838))
    var canvas := _canvas(viewport, Vector2i(256, 256))
    _cover(viewport, Rect2(0.0, 0.0, 1536.0, 93.6))
    var view := SaCanvasView.for_canvas(canvas)

    canvas.resize_canvas(Vector2i(768, 768))
    var fitted_scale := canvas.scale
    var fitted_position := canvas.position
    canvas.scale = Vector2(3.0, 3.0)
    canvas.position = Vector2(-500.0, 40.0)
    view.fit(Vector2i(768, 768))

    assert_almost_eq(fitted_scale.x, canvas.scale.x, 1e-4, "The two fits choose one zoom")
    assert_almost_eq(fitted_position.x, canvas.position.x, 1e-3, "and one place across")
    assert_almost_eq(fitted_position.y, canvas.position.y, 1e-3, "and one place down")


func _viewport(viewport_size: Vector2i) -> SubViewport:
    var viewport := SubViewport.new()
    viewport.size = viewport_size
    _host.add_child(viewport)
    return viewport


func _canvas(viewport: SubViewport, canvas_size: Vector2i) -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.canvas_size = canvas_size
    viewport.add_child(canvas)
    return canvas


func _cover(viewport: SubViewport, rect: Rect2) -> Control:
    var cover := Control.new()
    cover.position = rect.position
    cover.size = rect.size
    cover.add_to_group(SaCanvasView.COVER_GROUP)
    viewport.add_child(cover)
    return cover
