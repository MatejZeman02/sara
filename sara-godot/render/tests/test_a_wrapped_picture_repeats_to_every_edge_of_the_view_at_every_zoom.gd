## A wrapped picture repeats to every edge of the view at
## every zoom.
##
## A painter asked: "when wrapping or infinite canvas is
## on, then the repeating around the edges sometimes (on different zoom levels)
## dissapear. And it should repeat infinitely". The first version drew one ring of eight
## copies, so past the ring the view was the empty ground.
##
## **What the view shows is read back.** A suite cannot let a frame pass, and a
## control's draw waits on the message queue the main loop flushes, so the view
## is put down through the server as the repeat's `_draw` puts it down: the
## page's own rectangle, then every rectangle of `SaWrapRepeat.bands` tiled,
## under the canvas's own material and transform and with the repeat's own
## `texture_repeat`. A pixel of the view is then the page's texel folded by
## whole turns when it reads as the same pixel of a second frame that draws
## the page alone at that turn, so the material's filtering is the same in both
## and only the fold is under test.
extends "res://tests/test_framework.gd"

## A canvas builds an easel, and an easel needs a RenderingDevice.
const REQUIRES_GPU := true

## The tool descriptor the stroke's tool machine is built from.
const Fixtures = preload("res://tests/fixtures.gd")

## The view, and a page far larger than it so that at 800% the view is a part
## of one turn and at the smallest zoom it holds dozens.
const WINDOW := Vector2i(192, 128)
const PAGE := Vector2i(1024, 1024)

## The document point the view is centred on, near the page's bottom right
## corner, so the view straddles a seam at every zoom.
const CENTRE := Vector2(1000.0, 990.0)

## The smallest zoom, six between it and 800%, and 800%.
const ZOOMS: Array[float] = [SaView.ZOOM_MIN, 0.025, 0.07, 0.2, 0.6, 1.5, 4.0, 8.0]

## How far a pixel of the wrapped frame may read from the page drawn alone.
const SAME := 3.0 / 255.0

var _host: Node = null
var _page: ImageTexture = null


func before_each() -> void:
    _host = Node.new()
    _host.name = "RepeatTestHost"
    EventBus.add_child(_host)
    _page = ImageTexture.create_from_image(_quadrants())


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    _page = null


## The page as four quadrants of four colours, so a fold off by half a turn
## reads a different colour, and every colour opaque, so a pixel the draw
## missed reads as the clear ground.
static func _quadrants() -> Image:
    var image := Image.create_empty(PAGE.x, PAGE.y, false, Image.FORMAT_RGBA8)
    var half := Vector2i(PAGE.x >> 1, PAGE.y >> 1)
    image.fill_rect(Rect2i(0, 0, half.x, half.y), Color(0.8, 0.2, 0.2))
    image.fill_rect(Rect2i(half.x, 0, half.x, half.y), Color(0.2, 0.7, 0.2))
    image.fill_rect(Rect2i(0, half.y, half.x, half.y), Color(0.2, 0.3, 0.9))
    image.fill_rect(Rect2i(half.x, half.y, half.x, half.y), Color(0.9, 0.8, 0.3))
    return image


## A canvas of `PAGE` in a viewport of `WINDOW`, wrapping as *edges* says,
## with its infinite canvas switch as *infinite* says, at *zoom* turned by
## *degrees* round `CENTRE`, which stands at the view's middle.
func _canvas(edges: SaProjection.Wrap, zoom: float, infinite: bool = false, degrees: float = 0.0) -> SaCanvas:
    var viewport := SubViewport.new()
    viewport.size = WINDOW
    viewport.transparent_bg = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    _host.add_child(viewport)
    var canvas := SaCanvas.new()
    canvas.canvas_size = PAGE
    viewport.add_child(canvas)
    canvas.document.infinite_canvas.on = infinite
    SaProjection.wrap_flat(canvas.document, edges)
    canvas.scale = Vector2(zoom, zoom)
    canvas.rotation = deg_to_rad(degrees)
    canvas.position = Vector2(WINDOW) / 2.0 - (Transform2D(canvas.rotation, canvas.scale, 0.0, Vector2.ZERO) * CENTRE)
    canvas.add_child(_machine())
    return canvas


## A tool machine whose tool in hand paints, which is what folds a press.
func _machine() -> ToolMachine:
    var descriptor := Fixtures.make_tool_descriptor(&"brush")
    descriptor.is_painting = true
    var registry := SaToolRegistry.new()
    registry.register(descriptor)
    var machine := ToolMachine.new()
    machine.name = "ToolMachine"
    machine.registry = registry
    machine.active_tool_name = &"brush"
    return machine


## The frame *canvas*'s view shows, each of *rects* drawn with the page, tiled
## when *tiled*, through the canvas's material and transform.
func _frame(canvas: SaCanvas, rects: Array[Rect2], tiled: bool) -> Image:
    var viewport := canvas.get_viewport() as SubViewport
    var item := RenderingServer.canvas_item_create()
    RenderingServer.canvas_item_set_parent(item, viewport.find_world_2d().canvas)
    RenderingServer.canvas_item_set_draw_index(item, 1000)
    RenderingServer.canvas_item_set_transform(item, canvas.get_transform())
    RenderingServer.canvas_item_set_material(item, (canvas.material as ShaderMaterial).get_rid())
    RenderingServer.canvas_item_set_default_texture_repeat(item, _repeat_of(SaWrapRepeat.of_canvas(canvas)))
    for rect: Rect2 in rects:
        RenderingServer.canvas_item_add_texture_rect(item, rect, _page.get_rid(), tiled)
    # The canvas's own nodes have drawn nothing yet, the reason above, so only
    # this item is in the frame.
    canvas.visible = false
    RenderingServer.force_draw(false, 0.0)
    var image := viewport.get_texture().get_image()
    RenderingServer.free_rid(item)
    canvas.visible = true
    return image


static func _repeat_of(repeat: SaWrapRepeat) -> RenderingServer.CanvasItemTextureRepeat:
    if repeat.texture_repeat == CanvasItem.TEXTURE_REPEAT_ENABLED:
        return RenderingServer.CANVAS_ITEM_TEXTURE_REPEAT_ENABLED
    return RenderingServer.CANVAS_ITEM_TEXTURE_REPEAT_DISABLED


## What the view shows of *canvas*: the page, and the repeat's bands tiled.
func _view(canvas: SaCanvas) -> Image:
    var rects: Array[Rect2] = [Rect2(Vector2.ZERO, Vector2(PAGE))]
    rects.append_array(SaWrapRepeat.of_canvas(canvas).bands())
    return _frame(canvas, rects, true)


## The view's four corners and its middle, each moved inwards until its
## document point stands two screen pixels clear of every seam, so the
## filtering of the material reads no texel across a seam in either frame.
func _probes(canvas: SaCanvas) -> Array[Vector2i]:
    var to_document := canvas.get_transform().affine_inverse()
    var clear := 2.0 / canvas.scale.x + 1.0
    var out: Array[Vector2i] = []
    var middle := Vector2i(WINDOW.x >> 1, WINDOW.y >> 1)
    var far := WINDOW - Vector2i(2, 2)
    var corners: Array[Vector2i] = [Vector2i(1, 1), Vector2i(far.x, 1), Vector2i(1, far.y), far, middle]
    for corner: Vector2i in corners:
        var inward := Vector2i(signi(middle.x - corner.x), signi(middle.y - corner.y))
        if inward == Vector2i.ZERO:
            inward = Vector2i(1, 1)
        var at := corner
        for _step: int in 24:
            var point := to_document * (Vector2(at) + Vector2(0.5, 0.5))
            var within := Vector2(fposmod(point.x, PAGE.x), fposmod(point.y, PAGE.y))
            if within.x > clear and within.x < PAGE.x - clear and within.y > clear and within.y < PAGE.y - clear:
                break
            at += inward
        out.append(at)
    return out


## Whether *canvas*'s view, at each probe, reads as the page drawn alone at the
## turn the probe's document point stands on, and whether that is the page
## rather than the clear ground. With *sides_only*, for Wrap the Sides Only, a
## probe on any row but the page's own is the ground.
func _check_the_view(canvas: SaCanvas, label: String, sides_only: bool = false) -> void:
    var view := _view(canvas)
    var to_document := canvas.get_transform().affine_inverse()
    for at: Vector2i in _probes(canvas):
        var point := to_document * (Vector2(at) + Vector2(0.5, 0.5))
        var turn := SaWrapRepeat.turn_of(point, Vector2(PAGE))
        var shown := view.get_pixelv(at)
        if sides_only and turn.y != 0:
            assert_true(shown.a < 0.01, "%s: %s, off the page's row, is the empty ground" % [label, at])
            continue
        var alone := _frame(canvas, [Rect2(Vector2(turn) * Vector2(PAGE), Vector2(PAGE))] as Array[Rect2], false)
        var expected := alone.get_pixelv(at)
        assert_true(expected.a > 0.99, "%s: the page drawn alone at turn %s covers %s" % [label, turn, at])
        var off := maxf(maxf(absf(shown.r - expected.r), absf(shown.g - expected.g)), absf(shown.b - expected.b))
        assert_true(
            shown.a > 0.99 and off <= SAME,
            "%s: %s, on turn %s, shows the page's texel there, %s against %s" % [label, at, turn, shown, expected]
        )


func _sweep(edges: SaProjection.Wrap, infinite: bool) -> void:
    for zoom: float in ZOOMS:
        var canvas := _canvas(edges, zoom, infinite)
        _check_the_view(canvas, "zoom %s" % zoom, edges == SaProjection.Wrap.X)
        canvas.get_viewport().free()


func test_wrap_all_edges_fills_the_view_at_every_zoom() -> void:
    _sweep(SaProjection.Wrap.XY, false)


func test_wrap_the_sides_only_fills_the_row_and_leaves_the_ground_above_and_below() -> void:
    _sweep(SaProjection.Wrap.X, false)


## The infinite canvas and a wrap cannot both be on from the bar, the
## infinite canvas stops the wrap. A document that holds both, the switch on
## and a wrap set on the projection, repeats as one with the switch off.
func test_the_infinite_canvas_switch_on_changes_nothing_of_the_repeat() -> void:
    _sweep(SaProjection.Wrap.XY, true)
    _sweep(SaProjection.Wrap.X, true)


## The other way the repeat went: turning the infinite canvas on stops the
## wrap, so every copy goes at once, and the corner says so.
func test_turning_the_infinite_canvas_on_stops_the_wrap() -> void:
    var canvas := _canvas(SaProjection.Wrap.XY, 0.25)
    assert_true(SaInfiniteCanvas.turn(canvas.document, true), "Turning the growth on stops a wrap and says it did")
    assert_true(SaWrapRepeat.of_canvas(canvas).bands().is_empty(), "so no copy is drawn")


func test_a_turned_view_fills_to_its_edges_too() -> void:
    for zoom: float in [SaView.ZOOM_MIN, 0.2, 4.0]:
        var canvas := _canvas(SaProjection.Wrap.XY, zoom, false, 30.0)
        _check_the_view(canvas, "zoom %s turned 30 degrees" % zoom)
        canvas.get_viewport().free()


## However many turns a view holds, the draw is at most the four bands round
## the page, so the smallest zoom costs what the largest does.
func test_the_draw_is_four_bands_at_the_smallest_zoom() -> void:
    var canvas := _canvas(SaProjection.Wrap.XY, SaView.ZOOM_MIN)
    var repeat := SaWrapRepeat.of_canvas(canvas)
    var reach := repeat.reach()
    assert_true(reach.size.x >= float(WINDOW.x) / SaView.ZOOM_MIN, "The reach is the whole view wide, %s" % reach)
    assert_true(reach.size.x / PAGE.x >= 18.0, "which is eighteen turns or more")
    assert_eq(repeat.bands().size(), 4, "and four bands draw it")


func test_a_stroke_started_three_turns_from_the_page_lands_on_the_page() -> void:
    var canvas := _canvas(SaProjection.Wrap.XY, SaView.ZOOM_MIN)
    var repeat := SaWrapRepeat.of_canvas(canvas)
    var far := Vector2(3.0 * PAGE.x + 40.0, -3.0 * PAGE.y + 70.0)
    assert_eq(repeat.fold(far), Vector2(40.0, 70.0), "Three turns right and three up is the page")
    assert_eq(repeat.fold(-far), Vector2(984.0, 954.0), "and three left and three down is the page too")
