## The picture repeated around the page while the document wraps.
##
## Krita's wrap mode: the view shows the document again in every direction its
## wrap joins, and a stroke on any copy paints the document. One `Control`
## beside the canvas's own draw, under the canvas's material, so every copy is
## the same `SaEasel.output` under the same view transform: no second
## composite, no copy of the texture, and paint that lands on the page is on
## every copy in the same frame because the copies are that one texture. A
## child of the canvas, so the zoom, the pan and the rotation carry the copies
## with the picture and a copy's local space is the page's.
##
## **To every edge of the view.** The page repeats over the whole view in every
## direction its wrap joins, at any zoom, pan and rotation, through draws whose
## texture coordinates run past the page and wrap round it, the node's
## `texture_repeat` on. It was one ring of eight copies once, chosen so the
## smallest zoom did not cost hundreds of draws, and the repeat stopped at the
## ring's edge, which left a gap at a small zoom. A tiled
## draw costs the same at any zoom, so the reason for the ring went with it. The
## page itself is the canvas's own draw, so the repeat is the band above it, the
## band below it and the two beside it, at most four draws, never one over the
## page, where a transparent texel drawn twice would read darker.
##
## **The window the easel composites.** `SaEasel` composites what its
## `shown_rect` reaches and holds the rest in its backlog, so a view panned onto
## a copy would ask for a part of the page nothing on screen stands over,
## composite nothing, and leave the copy showing what the page held before.
## [method folded] is what the canvas hands the easel in place of its own
## window: the shown rectangle folded onto the page by whole turns however far
## out it stands, so what a copy shows is composited because the copy shows it.
##
## **The press.** A press on a copy is taken back into the page by whole turns,
## [method in_the_page], before the stroke starts, so the pen paints wherever it
## is. The cursor's outline is drawn in window space at the pointer,
## `CursorOverlay`, so it stays under the pen whichever copy the paint went to.
class_name SaWrapRepeat
extends Control

## The node's name beside the canvas's own draw, which [method of_canvas] finds
## it by, the way `SaEnvironmentView` is found beside the canvas.
const NODE_NAME := "WrapRepeat"

## The page's outline among its copies: a mid grey, which reads over a white
## page and a black one, at the alpha of a guide rather than of a drawn line.
const PAGE_OUTLINE := Color(0.55, 0.55, 0.55, 0.85)

## Which turn of the page the pointer was last read on, held through a press and
## the drag after it by [method holding].
var _turn := Vector2i.ZERO

## Whether the last reading was taken with the button already down, which is
## what tells a drag from the press that opened it.
var _was_down := false

## What the copies were last drawn from, so a frame that changed none of it
## queues no redraw.
var _drawn_state: Array = []

## The page's outline, a child rather than a line in [method _draw], because
## this node draws under the canvas's material.
var _outline: Control = null


func _init() -> void:
    name = NODE_NAME
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    # The copies are the canvas's own picture, so they take the canvas's
    # material: the roll-off, the profile and the view modes reach a copy as
    # they reach the page. `SaDetailDraw` holds the display chunks the same way.
    use_parent_material = true
    # The draws run their texture coordinates past the page, and the wrap is
    # what lays the next turn of the page there.
    texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
    _outline = Outline.new()
    add_child(_outline)


## Builds the repeat into *canvas* and answers it, which the canvas does as it
## builds the rest of its own draw, before the overlays and after the easel.
static func attach_to(canvas: SaCanvas) -> SaWrapRepeat:
    var made := SaWrapRepeat.new()
    canvas.add_child(made)
    return made


## The repeat beside *canvas*, or null on one built without it, which is every
## canvas a suite news and never puts in a tree.
static func of_canvas(canvas: SaCanvas) -> SaWrapRepeat:
    if canvas == null:
        return null
    return canvas.get_node_or_null(NODE_NAME) as SaWrapRepeat


## *point*, in document pixels under the pointer, taken back into the page of
## *canvas*. The one call `SaCanvasView.get_document_mouse_position` makes, and
## *point* itself where there is no repeat to ask.
static func in_the_page(canvas: SaCanvas, point: Vector2) -> Vector2:
    var repeat := of_canvas(canvas)
    return repeat.fold(point) if repeat != null else point


## Which turn of a page *step* wide and tall *point* stands on, nought on an
## axis that does not repeat. Whole turns, so the fold is exact at any distance
## from the page and a point inside it is left alone.
static func turn_of(point: Vector2, step: Vector2) -> Vector2i:
    var turn := Vector2i.ZERO
    if step.x > 0.0:
        turn.x = floori(point.x / step.x)
    if step.y > 0.0:
        turn.y = floori(point.y / step.y)
    return turn


## Whether the tool in hand paints, so a press on a copy is taken into the page.
##
## A transform's box, a crop's handles and a marquee are dragged past an edge on
## purpose, and a folded point would jump them a page across. The same question
## `SaEnvironmentView` asks before it takes a reading the short way round a
## seam, and a canvas with no tool machine, which is a scratchpad's and most
## suites', paints with none.
static func paints(canvas: SaCanvas) -> bool:
    var machine := canvas.tool_machine() if canvas != null else null
    if machine == null:
        return false
    var descriptor := machine.get_descriptor(machine.active_tool_name)
    return descriptor != null and descriptor.is_painting


## How far a copy of the page stands from it on each axis, nought on an axis the
## document does not wrap: the page's width on either wrap, and its height on
## Wrap All Edges alone.
func across() -> Vector2:
    var canvas := get_parent() as SaCanvas
    var document := canvas.document if canvas != null else null
    if document == null:
        return Vector2.ZERO
    var page := Vector2(document.canvas_size)
    if document.projection.wrapping == SaProjection.Wrap.XY:
        return page
    if document.projection.wrapping == SaProjection.Wrap.X:
        return Vector2(page.x, 0.0)
    return Vector2.ZERO


## The rectangle the repeat covers, in document pixels: the box round what
## the window shows, widened to whole turns of the page on each axis the
## document wraps, and the page's own extent on an axis it does not. Empty while
## nothing repeats or the canvas shows no window, which is a canvas out of the
## tree and the Environment view's sky.
func reach() -> Rect2:
    var canvas := get_parent() as SaCanvas
    var step := across()
    if canvas == null or step == Vector2.ZERO:
        return Rect2()
    var shown := canvas.shown_in_document()
    if not shown.has_area():
        return Rect2()
    var start := Vector2.ZERO
    var end := Vector2(canvas.document.canvas_size)
    if step.x > 0.0:
        start.x = floorf(shown.position.x / step.x) * step.x
        end.x = ceilf(shown.end.x / step.x) * step.x
    if step.y > 0.0:
        start.y = floorf(shown.position.y / step.y) * step.y
        end.y = ceilf(shown.end.y / step.y) * step.y
    return Rect2(start, end - start)


## What [method _draw] lays down, in document pixels: [method reach] less the
## page, as the band above the page, the band below it and the two beside it,
## each starting on a whole turn so its texture coordinates start on the page's
## corner. A band the reach does not cover is left out, so Wrap the Sides Only
## answers the two beside the page and no wrap answers none.
func bands() -> Array[Rect2]:
    var out: Array[Rect2] = []
    var covered := reach()
    if not covered.has_area():
        return out
    var page := Vector2((get_parent() as SaCanvas).document.canvas_size)
    var low := covered.position
    var high := covered.end
    var row_top := maxf(low.y, 0.0)
    var row_bottom := minf(high.y, page.y)
    for band: Rect2 in [
        Rect2(low.x, low.y, high.x - low.x, minf(high.y, 0.0) - low.y),
        Rect2(low.x, maxf(low.y, page.y), high.x - low.x, high.y - maxf(low.y, page.y)),
        Rect2(low.x, row_top, minf(high.x, 0.0) - low.x, row_bottom - row_top),
        Rect2(maxf(low.x, page.x), row_top, high.x - maxf(low.x, page.x), row_bottom - row_top),
    ]:
        if band.size.x > 0.0 and band.size.y > 0.0:
            out.append(band)
    return out


## What the easel composites, in document pixels: the rectangle the window
## shows folded onto the page by whole turns, so the page under every copy on
## screen is kept fresh. The window itself while the document does not wrap,
## which is `SaCanvas.shown_in_document` and the composite as it was.
##
## A window that reaches no copy at all, which is a view above or below the row
## Wrap the Sides Only repeats, is answered with itself rather than with
## nothing: the easel reads an empty rectangle as the whole canvas, and a view
## with no page in it is the last place to composite one.
func folded() -> Rect2:
    var canvas := get_parent() as SaCanvas
    if canvas == null:
        return Rect2()
    var shown := canvas.shown_in_document()
    var step := across()
    if step == Vector2.ZERO or not shown.has_area():
        return shown
    var page := Vector2(canvas.document.canvas_size)
    var across_x := Folding.span(shown.position.x, shown.end.x, step.x, page.x)
    var across_y := Folding.span(shown.position.y, shown.end.y, step.y, page.y)
    if across_x.y <= across_x.x or across_y.y <= across_y.x:
        return shown
    return Rect2(across_x.x, across_y.x, across_x.y - across_x.x, across_y.y - across_y.x)


## *point* in the page, by whole turns of it, for a painting tool on a document
## that wraps, and *point* itself for anything else.
##
## The turn is worked out at the press and held through the drag, so a stroke
## dragged from a copy across the seam onto the page is one line: the dab that
## passes the page's edge is laid on the far side by `SaPaintContext`, which is
## this arithmetic from the other end. Worked out again at every reading, the
## folded point would jump a page across the moment the pen reached the seam.
func fold(point: Vector2) -> Vector2:
    var step := across()
    if step == Vector2.ZERO or not paints(get_parent() as SaCanvas):
        return point
    if not holding():
        _turn = turn_of(point, step)
    return point - Vector2(_turn) * step


## Whether the turn the pointer was last read on is held rather than worked out
## again: the drag of a press this class has already answered, and any reading
## while the document has a stroke open.
##
## The press itself is not held. Godot has the button down before the event
## reaches the tool that asks where the pointer is, so "the button is down" on
## its own would answer a press on a copy with the turn of whatever was read
## before it, and a scenario's injected press, which no hover comes before,
## would paint on the page it never pressed on.
func holding() -> bool:
    var canvas := get_parent() as SaCanvas
    var down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
    var held := (down and _was_down) or SaHalfSizeView.stroke_open(canvas.document if canvas != null else null)
    _was_down = down
    return held


## The canvas's picture, which is the easel's output bound once by the canvas
## and never a second texture.
##
## The canvas lets go of it while the half size view draws a smaller mirror in
## its place and holds it there, and the copies draw at full size through that
## pan: a pan that left the page on screen and every copy gone is a worse
## picture than one drawn whole. The copies are at most four tiled draws of one
## texture, though over a view they fill they shade the window at full size, so
## a wrapped pan at a small zoom pays the full size the half size spares a plain
## one.
func picture() -> Texture2D:
    var canvas := get_parent() as SaCanvas
    if canvas == null:
        return null
    return canvas.texture if canvas.texture != null else canvas._texture_while_half


## Queues a draw when what the copies are made of has changed, rather than once
## a frame. The texture is the easel's own, so paint that lands on the page is
## on every copy with no redraw at all, and only the wrap, the page's size, the
## texture the canvas holds, the zoom the outline is a pixel wide at and a view
## that has moved onto a turn of the page the reach did not cover ask for one.
func _process(_delta: float) -> void:
    var canvas := get_parent() as SaCanvas
    if canvas == null:
        return
    var state := [across(), picture(), canvas.pixels_per_texel(), reach()]
    if state == _drawn_state:
        return
    _drawn_state = state
    queue_redraw()
    _outline.queue_redraw()


## Every band round the page, tiled from the canvas's own texture at the
## page's own size, over the background and under the detail view and the
## overlays. The page is the canvas's own draw.
func _draw() -> void:
    var drawn := picture()
    if drawn == null:
        return
    for band: Rect2 in bands():
        draw_texture_rect(drawn, band, true)


## Lets go of the canvas's texture before the canvas lets go of the one under
## it. A child leaves the tree ahead of its parent, so the draw commands
## holding the `Texture2DRD` are cleared while `SaCanvas._cleanup_resources`
## has still to drop it, and no binding outlives the `RenderingDevice`. The
## state is emptied with them, so a node put back in a tree draws again.
func _exit_tree() -> void:
    RenderingServer.canvas_item_clear(get_canvas_item())
    _drawn_state = []


## The page's outline among its copies, so the painter sees where the document
## is.
##
## A child of the repeat rather than a line in its draw, because the repeat
## draws under the canvas's material, the view transform, and that shader
## writes the colour from the picture: a grey line through it comes out
## whatever the shader makes of a white texel. A child that does not take its
## parent's material draws with none, the way the axes and the marching ants
## over the canvas do.
class Outline:
    extends Control

    func _init() -> void:
        name = "PageOutline"
        mouse_filter = Control.MOUSE_FILTER_IGNORE

    ## One device pixel wide at any zoom, laid inside the page so the line
    ## stands over the picture's own edge texels and never over a copy's.
    func _draw() -> void:
        var repeat := get_parent() as SaWrapRepeat
        var canvas := repeat.get_parent() as SaCanvas if repeat != null else null
        if canvas == null or repeat.across() == Vector2.ZERO:
            return
        var page := Rect2(Vector2.ZERO, Vector2(canvas.document.canvas_size))
        var hair := 1.0 / maxf(canvas.pixels_per_texel(), 0.0001)
        draw_rect(page.grow(-0.5 * hair), SaWrapRepeat.PAGE_OUTLINE, false, hair)


## The fold of one axis of the window onto the page, for [method folded].
class Folding:
    extends RefCounted

    ## The part of the page from *low* to *high* reaches on an axis whose
    ## copies stand *step* apart on a page *length* long, as the span from its
    ## `x` to its `y`, empty when `y` is not past `x`. A window a whole turn
    ## wide or wider reaches all of it, and one that crosses a seam reaches the
    ## end of the page and its start, which is the span round both. On an axis
    ## that does not repeat, *step* nought, it is the window cut to the page.
    static func span(low: float, high: float, step: float, length: float) -> Vector2:
        if step <= 0.0:
            return Vector2(maxf(low, 0.0), minf(high, length))
        if high - low >= step:
            return Vector2(0.0, length)
        var turn := floorf(low / step) * step
        var start := low - turn
        var end := high - turn
        if end <= length:
            return Vector2(start, end)
        return Vector2(0.0, length)
