## A filter's thumbnail is readable and its dialog leaves the
## strokes in sight.
##
## Edge Detection on a layer with black
## strokes, or on a transparent one, showed its picture on the near black of the
## frame, so black strokes and the blackened shapes of the output vanished. And
## the dialog opened centred, over the middle of the document, so with Preview on
## canvas ticked the strokes being filtered were behind it.
##
## The picture now lies on the checkerboard the canvas draws under a transparent
## texel, over the rectangle the picture covers, and the dialog opens at the
## right edge of the main window, top aligned under the bar. This suite holds
## the chequer's presence and extent through `describe()`, the corner the rule
## gives for a 1920 by 1080 window, and where an opened window stands in the
## host the test has. What the two look like is the scenario's half, in
## `scenarios/s61-a-filters-thumbnail-is-readable-and-its-dialog-leaves-the-strokes-in.json`.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const Teardown := preload("res://tests/fixtures/teardown.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"

## The 1920 by 1080 window the rule below uses, less a 30 high bar.
const WINDOW_HOST := Rect2i(0, 30, 1920, 1050)

var _easel: SaEasel = null
var _canvas: SaCanvas = null
var _window: SaFilterDialogWindow = null
var _host: Node = null
var _registry: SaFilterRegistry = null
var _blur: SaFilter = null
var _curves: SaFilter = null
var _was_embedding: bool = false
var _saved_override: float = 1.0
var _saved_user: float = 1.0
var _preview: SaFilterPreview = null
var _strip: Control = null
var _shown_canvas: SaCanvas = null


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        _was_embedding = tree.root.gui_embed_subwindows
        tree.root.gui_embed_subwindows = true
    _saved_override = SaUI.os_scale_override
    _saved_user = SaUI.user_scale
    SaUI.os_scale_override = 1.0
    SaUI.user_scale = 1.0
    _host = Node.new()
    _host.name = "S61TestHost"
    EventBus.add_child(_host)

    _easel = Bench.easel(Vector2i(512, 256))
    _canvas = SaCanvas.new()
    _canvas.easel = _easel

    _registry = SaFilterRegistry.new()
    _blur = SaGaussianBlurFilter.new()
    _curves = SaCurvesFilter.new()
    for filter: SaFilter in [_blur, _curves]:
        _registry.register(filter, OWNER)
    _easel.compositor.filter_chain.registry = _registry

    _window = SaFilterDialogWindow.new()
    _window.target_canvas = _canvas
    _window.watch(_registry)
    _host.add_child(_window)


func after_each() -> void:
    if _preview != null:
        _preview.free()
        _preview = null
    if _strip != null:
        _strip.free()
        _strip = null
    if _window != null:
        _window.target_canvas = null
        _window.free()
        _window = null
    Teardown.free_nodes([_shown_canvas, _canvas, _easel])
    _shown_canvas = null
    _canvas = null
    _easel = null
    _registry = null
    _blur = null
    _curves = null
    if _host != null:
        _host.free()
        _host = null
    SaUI.os_scale_override = _saved_override
    SaUI.user_scale = _saved_user
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = _was_embedding


## A preview laid out in a strip *strip_size* across, the way the dialog's page
## lays it, with no window in the tree.
func _laid_out_preview(strip_size: Vector2) -> SaFilterPreview:
    _strip = Control.new()
    _strip.size = strip_size
    EventBus.add_child(_strip)
    _preview = SaFilterPreview.new()
    _strip.add_child(_preview)
    _preview.size = strip_size
    _sort(_preview)
    return _preview


## Sorts every container under *node*, outside in, so the rectangles below it are
## the ones the running app would draw.
func _sort(node: Node) -> void:
    if node is Container:
        (node as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child: Node in node.get_children():
        _sort(child)


## The layer's own pixels as the dialog seeds its picture with them.
func _layer_texture() -> SaTexture:
    var doc := _easel.document
    var context := SaFilterContext.new(doc, doc.active_layer, OWNER, "Test", true)
    return context.layer_pixels(0)


## Opens *filter* and runs the fit its first frame would, answering the window's
## rectangle in the host's own space.
func _open(filter: SaFilter) -> Rect2i:
    _window.open_filter(SaFilterRegistry.key_for(OWNER, filter))
    for _pass in range(2):
        _sort(_window)
    _window.fit_opening_size()
    return Rect2i(_window.position, _window.size)


func test_the_picture_lies_on_the_canvas_chequer() -> void:
    var preview := SaFilterPreview.new()
    _preview = preview
    assert_not_null(preview.chequer, "the picture has a chequer behind it")
    var painted := preview.chequer.material as ShaderMaterial
    assert_not_null(painted, "painted with a shader")
    assert_eq(painted.shader.resource_path.get_file(), "checkerboard.gdshader", "the canvas's own chequer shader")
    assert_eq(painted.shader, load("res://shaders/canvas/checkerboard.gdshader"), "and the very shader object the canvas loads")
    assert_true(preview.chequer.show_behind_parent, "drawn behind the picture, which lands on it")
    assert_eq(preview.chequer.mouse_filter, Control.MOUSE_FILTER_IGNORE, "and it takes no press")
    assert_eq(preview.chequer.get_parent().name, "PreviewPicture", "a child of the picture, which the frame cannot stretch")
    assert_false(preview.describe()["chequer"], "with no picture shown there is no chequer, the frame stays plain")


func test_a_shown_texture_puts_the_chequer_under_the_picture_alone() -> void:
    var preview := _laid_out_preview(Vector2(400, 300))
    var texture := _layer_texture()
    assert_not_null(texture, "the layer has pixels to show")
    preview.show_texture(texture, Rect2i(0, 0, 512, 256))
    var described := preview.describe()
    assert_true(described["chequer"], "a shown texture brings the chequer up")
    assert_eq(described["chequer_shader"], "checkerboard.gdshader", "and the dump names the shader")
    var inside: Vector2 = preview._picture.size
    var drawn := SaFilterPreview.fitted(inside, Vector2(texture.size))
    assert_true(drawn.has_area(), "the picture has a drawn rectangle at %s" % inside)
    assert_eq(
        described["chequer_rect"],
        [drawn.position.x, drawn.position.y, drawn.size.x, drawn.size.y],
        "the chequer is that rectangle"
    )
    assert_true(
        drawn.size.y < inside.y,
        "a wide layer in a tall strip is chequered over its own rows alone, %s of %s" % [drawn.size, inside]
    )
    preview.show_texture(null, Rect2i())
    assert_false(preview.describe()["chequer"], "and a cleared picture takes the chequer with it")


func test_fitted_is_the_aspect_fit_the_picture_is_drawn_with() -> void:
    assert_eq(
        SaFilterPreview.fitted(Vector2(400, 200), Vector2(100, 100)),
        Rect2(100, 0, 200, 200),
        "a square in a wide strip is centred and fills the height"
    )
    assert_eq(
        SaFilterPreview.fitted(Vector2(200, 400), Vector2(100, 50)),
        Rect2(0, 150, 200, 100),
        "a wide layer in a tall strip fills the width"
    )
    assert_eq(
        SaFilterPreview.fitted(Vector2(400, 400), Vector2(1000, 1000)),
        Rect2(0, 0, 400, 400),
        "a larger layer is scaled down to fit"
    )
    assert_eq(SaFilterPreview.fitted(Vector2.ZERO, Vector2(10, 10)), Rect2(), "an unlaid strip draws nothing")
    assert_eq(SaFilterPreview.fitted(Vector2(10, 10), Vector2.ZERO), Rect2(), "and neither does a picture of no size")


func test_a_transparent_texel_reaches_the_picture_as_transparent() -> void:
    var doc := _easel.document
    var layer := doc.active_layer
    layer.get_or_create_chunk(Vector2i.ZERO)
    var texture := _layer_texture()
    assert_not_null(texture, "an empty layer still has a picture")
    var texel := Bench.texel(texture, Vector2i(10, 10))
    assert_almost_eq(
        texel.a, 0.0, 1e-5, "its transparent texel is held as alpha nought, for the chequer to show through: %s" % texel
    )


func test_the_corner_touches_the_right_edge_under_the_bar() -> void:
    var corner := SaFilterDialogWindow.corner_at_the_right_edge(WINDOW_HOST, Vector2i(520, 400))
    assert_eq(corner, Vector2i(1400, 30), "the right edge of the window, the top of the host under the bar")


func test_the_dialog_leaves_the_middle_of_a_1920_by_1080_window_clear() -> void:
    for tall: int in [300, 400, 640, 900]:
        var size := Vector2i(520, tall)
        var corner := SaFilterDialogWindow.corner_at_the_right_edge(WINDOW_HOST, size)
        assert_false(
            Rect2i(corner, size).has_point(Vector2i(960, 540)),
            "a 520 by %d window does not cover the middle of the window" % tall
        )


func test_a_window_wider_than_the_host_keeps_to_the_host_s_left_edge() -> void:
    var corner := SaFilterDialogWindow.corner_at_the_right_edge(Rect2i(0, 30, 400, 600), Vector2i(520, 400))
    assert_eq(
        corner,
        Vector2i(0, 30),
        "a window wider than its host starts at the host's left edge, where its title strip can be dragged"
    )


func test_an_opened_dialog_stands_at_the_right_edge_under_the_bar() -> void:
    var opened := _open(_blur)
    var host := _window.host_rect()
    assert_true(host.has_area(), "the host the window is kept in has a size, %s" % host)
    var margin := SaUI.window_size_for(_window, Vector2i(SaDialogWindow.HOST_MARGIN, SaDialogWindow.HOST_MARGIN))
    assert_eq(opened.end.x, host.end.x - margin.x, "the window's right edge is the host's, less the margin")
    assert_eq(opened.position.y, host.position.y + margin.y, "and its top is the host's top, less the margin")
    assert_true(host.encloses(opened), "the whole window is inside the host: %s in %s" % [opened, host])
    var described := _window.describe()
    assert_eq(described["position"], [opened.position.x, opened.position.y], "the dump says where it stands")


func test_the_open_itself_places_the_window_before_any_fit() -> void:
    _window.open_filter(SaFilterRegistry.key_for(OWNER, _blur))
    var host := _window.host_rect()
    var margin := SaUI.window_size_for(_window, Vector2i(SaDialogWindow.HOST_MARGIN, SaDialogWindow.HOST_MARGIN))
    assert_eq(_window.position.x + _window.size.x, host.end.x - margin.x, "the right edge is the host's before the fit has run")
    assert_eq(_window.position.y, host.position.y + margin.y, "and the top is the host's, not the middle's")


func test_a_tall_page_after_a_short_one_stays_at_the_edge() -> void:
    var short := _open(_blur)
    var tall := _open(_curves)
    assert_true(tall.size.y >= short.size.y, "Curves is at least as tall as Gaussian Blur")
    assert_eq(tall.end.x, short.end.x, "the right edge holds across the two, %s then %s" % [short, tall])
    assert_eq(tall.position.y, short.position.y, "and so does the top")


func test_the_fit_does_not_take_the_window_off_the_edge_it_grew_from() -> void:
    _window.open_filter(SaFilterRegistry.key_for(OWNER, _curves))
    var before := Rect2i(_window.position, _window.size)
    # A floor the page asks for beyond the opening size, which is what makes the
    # fit grow the window about its centre, past the edge the base clamp then
    # pulls it back to.
    _window.logical_min_size = Vector2i(before.size.x + 100, before.size.y + 100)
    for _pass in range(2):
        _sort(_window)
    _window.fit_opening_size()
    var host := _window.host_rect()
    var margin := SaUI.window_size_for(_window, Vector2i(SaDialogWindow.HOST_MARGIN, SaDialogWindow.HOST_MARGIN))
    assert_true(_window.size.x > before.size.x, "the fit grew the window from %s to %s" % [before.size, _window.size])
    assert_eq(_window.position.x + _window.size.x, host.end.x - margin.x, "and the right edge is still the host's")
    assert_eq(_window.position.y, host.position.y + margin.y, "and the top is still the host's")


func test_a_dialog_the_painter_dragged_is_left_where_it_was_put() -> void:
    _open(_blur)
    var host := _window.host_rect()
    var moved := host.position + Vector2i(60, 60)
    _window.position = moved
    _window.fit_opening_size()
    assert_eq(_window.position, moved, "a window dragged away from the edge stays where it was dragged")


func test_at_a_scale_of_1_25_the_window_is_whole_inside_the_host() -> void:
    SaUI.user_scale = 1.25
    var opened := _open(_curves)
    var host := _window.host_rect()
    assert_true(host.encloses(opened), "the tallest page at 1.25 is whole inside the host: %s in %s" % [opened, host])


func test_the_dump_leaves_the_middle_out_when_no_canvas_is_on_screen() -> void:
    _open(_blur)
    assert_false(
        _window.describe().has("covers_document_centre"), "a canvas off screen leaves the answer out rather than guessing it"
    )


func test_an_open_dialog_does_not_cover_the_documents_centre() -> void:
    _shown_canvas = SaCanvas.new()
    _shown_canvas.canvas_size = Vector2i(1920, 1080)
    _shown_canvas.easel = SaEasel.create_default(_shown_canvas.canvas_size)
    _shown_canvas.add_child(_shown_canvas.easel)
    _host.add_child(_shown_canvas)
    # The document's middle on the host's, as the origin put it on a 1920 by
    # 1080 screen. On a 1280 wide one under Windows the origin put it
    # under the dialog at the right edge.
    var host := _window.host_rect()
    var middle := Vector2(host.get_center())
    _shown_canvas.position = middle - Vector2(_shown_canvas.canvas_size) / 2.0
    _shown_canvas.scale = Vector2.ONE
    _window.target_canvas = _shown_canvas
    _window.open_filter(SaFilterRegistry.key_for(OWNER, _blur))
    _window.fit_opening_size()
    var described := _window.describe()
    assert_true(described.has("document_centre"), "a canvas on screen gives the dump the document's middle")
    var centre := Vector2(described["document_centre"][0], described["document_centre"][1])
    assert_eq(centre, middle, "which is the middle of the document, laid on the host's middle")
    assert_false(described["covers_document_centre"], "the dialog at the right edge does not cover it")
    host = _window.host_rect()
    var centred := Rect2(Vector2(host.get_center()) - Vector2(_window.size) / 2.0, Vector2(_window.size))
    assert_true(centred.has_point(centre), "where a centred window of this size would have: %s over %s" % [centred, centre])
