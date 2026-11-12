## With wrap on the view shows the picture repeated around the
## page, and with wrap off it draws one copy, as before.
##
## The ask was "like Krita, the wrap mode": the view shows the document
## repeated in every direction and a stroke on any copy paints the document.
## This half is the draw and the window the easel composites. The press is
## `test_a_press_on_a_copy_lands_in_the_page.gd`.
##
## **The bands round the page**, which replace an earlier ring of
## eight: the copies are read through `SaWrapRepeat.bands`, the list `_draw`
## tiles, because what a canvas item drew cannot be read back here. What the
## view shows at every zoom is a suite of its own.
##
## **The window** is the other half of "a change on the page shows on every
## copy in the same frame": the easel composites what `shown_rect` reaches and
## holds the rest, so a view panned onto a copy has to ask for the page under
## that copy or the copy shows what the page held before.
extends "res://tests/test_framework.gd"

## A canvas builds an easel, and an easel needs a RenderingDevice.
const REQUIRES_GPU := true

## The window, and a page twice its width and twice its height.
const WINDOW := Vector2i(128, 128)
const PAGE := Vector2i(256, 256)

var _host: Node = null


## Parented to an autoload rather than to the root, because the runner calls
## this from its own `_ready` and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "CopyRepeatTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null


## A canvas of `PAGE` at a zoom of one in a viewport of `WINDOW`, its top left
## corner in view, with the repeat its own `_ready` attached.
func _canvas() -> SaCanvas:
    var viewport := SubViewport.new()
    viewport.size = WINDOW
    _host.add_child(viewport)
    var canvas := SaCanvas.new()
    canvas.canvas_size = PAGE
    viewport.add_child(canvas)
    canvas.scale = Vector2.ONE
    canvas.position = Vector2.ZERO
    return canvas


## The canvas with its document wrapping as *edges* says.
func _wrapping(edges: SaProjection.Wrap) -> SaCanvas:
    var canvas := _canvas()
    SaProjection.wrap_flat(canvas.document, edges)
    return canvas


func test_the_canvas_hands_the_easel_the_folded_window() -> void:
    var canvas := _canvas()
    var repeat := SaWrapRepeat.of_canvas(canvas)
    assert_true(repeat != null, "The canvas builds the repeat beside its own draw")
    assert_eq(canvas.easel.shown_rect.get_object(), repeat, "and hands the easel that node's window")
    assert_eq(canvas.easel.shown_rect.get_method(), &"folded", "which is the window folded onto the page")
    assert_true(repeat.use_parent_material, "The copies take the canvas's material, the view transform")
    assert_true(repeat.get_node_or_null("PageOutline") != null, "and the page's outline is a child of its own")


func test_a_document_that_does_not_wrap_draws_one_copy() -> void:
    var canvas := _wrapping(SaProjection.Wrap.NONE)
    var repeat := SaWrapRepeat.of_canvas(canvas)
    assert_eq(repeat.across(), Vector2.ZERO, "Nothing repeats, so no copy stands anywhere")
    assert_true(repeat.bands().is_empty(), "No band round the page, which is the canvas's own draw")
    assert_eq(repeat.folded(), canvas.shown_in_document(), "and the easel is handed the window it always was")


## The window at the page's top left corner, so the reach is the page alone
## and nothing round it shows.
func test_wrap_at_every_edge_tiles_what_the_window_reaches() -> void:
    var canvas := _wrapping(SaProjection.Wrap.XY)
    var repeat := SaWrapRepeat.of_canvas(canvas)
    assert_eq(repeat.across(), Vector2(PAGE), "A copy stands a page away on both axes")
    assert_true(repeat.texture_repeat == CanvasItem.TEXTURE_REPEAT_ENABLED, "and the draw's coordinates wrap round the page")
    assert_true(repeat.bands().is_empty(), "A window inside the page reaches no copy")
    canvas.position = Vector2(64.0, 64.0)
    var reached := Rect2(-256.0, -256.0, 512.0, 512.0)
    assert_eq(repeat.reach(), reached, "Moved down and right, it reaches the turns above and to the left")
    var bands := repeat.bands()
    assert_eq(bands.size(), 2, "the band above the page and the one beside it")
    assert_true(bands.has(Rect2(-256.0, -256.0, 512.0, 256.0)), "above, two turns wide from a whole turn")
    assert_true(bands.has(Rect2(-256.0, 0.0, 256.0, 256.0)), "and to the left, the page's height")


func test_wrap_the_sides_only_tiles_the_row_of_the_page() -> void:
    var canvas := _wrapping(SaProjection.Wrap.X)
    canvas.position = Vector2(64.0, 64.0)
    var repeat := SaWrapRepeat.of_canvas(canvas)
    assert_eq(repeat.across(), Vector2(float(PAGE.x), 0.0), "A copy stands a page away across and none down")
    assert_eq(repeat.reach(), Rect2(-256.0, 0.0, 512.0, 256.0), "The reach is the page's row, never above or below it")
    assert_eq(repeat.bands(), [Rect2(-256.0, 0.0, 256.0, 256.0)] as Array[Rect2], "the copy to the left and nothing else")


## The view is panned onto the copy to the right of the page: the whole window
## stands over that copy and none of it over the page.
func test_the_easel_is_asked_for_the_page_under_the_copy_on_screen() -> void:
    var canvas := _wrapping(SaProjection.Wrap.XY)
    canvas.position = Vector2(-300.0, -20.0)
    var shown := Rect2(300.0, 20.0, float(WINDOW.x), float(WINDOW.y))
    assert_eq(canvas.shown_in_document(), shown, "The window shows the copy one page to the right")
    var repeat := SaWrapRepeat.of_canvas(canvas)
    assert_eq(repeat.folded(), Rect2(44.0, 20.0, float(WINDOW.x), float(WINDOW.y)), "folded back onto the page")
    SaProjection.wrap_flat(canvas.document, SaProjection.Wrap.NONE)
    assert_eq(repeat.folded(), shown, "With wrap off the easel is asked for the window itself, as before")


## A window over the page and the copy below it at once is folded into one
## rectangle covering both bands of the page.
func test_a_window_across_the_seam_asks_for_both_bands() -> void:
    var canvas := _wrapping(SaProjection.Wrap.XY)
    canvas.position = Vector2(-40.0, -200.0)
    assert_eq(canvas.shown_in_document(), Rect2(40.0, 200.0, 128.0, 128.0), "Half on the page, half on the copy below")
    var repeat := SaWrapRepeat.of_canvas(canvas)
    assert_eq(repeat.folded(), Rect2(40.0, 0.0, 128.0, 256.0), "The page's bottom band and its top one, merged")


## A view panned far from the page, which the old ring left empty, is folded
## onto the page like any other: the turn it stands on is whole however far out.
func test_a_view_far_from_the_page_is_folded_by_whole_turns() -> void:
    var canvas := _wrapping(SaProjection.Wrap.XY)
    canvas.position = Vector2(-5000.0, -5000.0)
    var repeat := SaWrapRepeat.of_canvas(canvas)
    var page := Rect2(0.0, 0.0, 256.0, 256.0)
    assert_eq(repeat.folded(), page, "From 136 to 264 the window crosses a seam on both axes, so the whole page")
    canvas.position = Vector2(-5130.0, -5130.0)
    assert_eq(repeat.folded(), Rect2(10.0, 10.0, 128.0, 128.0), "and one inside a far turn folds to the same place in the page")


## The copies are the canvas's own picture, never a second texture: the one
## `Texture2DRD` the canvas bound to `easel.output` is what `_draw` lays down.
func test_the_copies_are_the_canvas_s_own_texture() -> void:
    var canvas := _wrapping(SaProjection.Wrap.XY)
    var repeat := SaWrapRepeat.of_canvas(canvas)
    assert_eq(repeat.picture(), canvas.texture, "One texture for the page and every copy of it")
    assert_true(canvas.texture is Texture2DRD, "which is the easel's output bound once")
