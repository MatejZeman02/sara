## The canvas as an element on a reference board: a live `Texture2DRD` over the
## easel's output, drawn where the board says.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## An element rather than a pane beside the board, so the canvas takes the
## per-picture toggles a pane could not. `SaReferenceBoard.Picture` holds it in the same list as every
## other element, so a flip, a crop, a raise and a resize are the board's own
## operations rather than four new ones.
##
## **Nothing is read back and nothing is composited twice.** The easel's output
## is bound by RID, exactly as the minimap binds it, and drawn
## through the canvas's own display material, so the rolloff, the display
## exposure and the profile are the ones the painter is looking at. There is no
## `Image` on the CPU at any point, which is what keeps hard rule 1 (no CPU-GPU ping-pong) true for an
## element that is the canvas.
##
## **A Control of its own, and the one element that is.** The board draws every
## picture in one pass in `ReferencePictureView.draw_board`, because a picture
## is an `ImageTexture` and a rectangle and that is all a pass needs. This one
## needs a material, and a material is a property of a `CanvasItem` rather than
## of a draw call, so it is a child Control placed over the element's rectangle.
## One Control for one element, not one per picture.
##
## **Redrawn when the composite moved, not per frame.** The board is not the
## canvas: a painter watching a stroke land looks at the canvas, and this is
## what they compare against. The easel emits nothing when it composites, so
## [method refresh] reads its `composite_count`, which it bumps once per
## composite, and asks for a redraw only when that number moved. The RID is read
## beside it, because a File New swaps the easel under this element and nothing
## says so either. Two integer comparisons a poll, which is the minimap's price.
class_name ReferenceCanvasElement
extends Control

## What is drawn where the element's rectangle is larger than the canvas, which
## is a crop dragged past the document's edge. The board's own empty colour, so
## the element does not draw a bright hole.
const OUTSIDE := Color(0.12, 0.12, 0.12, 1.0)

## The output the picture is bound to, so a swap is seen.
var _bound_rid: RID = RID()
var _shown: Texture2DRD = null

## The region of the canvas that is drawn, in texels, and whether it is
## mirrored. Written by the view when it places this element, because the crop
## and the flip belong to the `Picture` and this Control draws what it is told.
var region: Rect2i = Rect2i()
var flipped: bool = false

## Whether the element is drawn without its colour.
##
## The one toggle that costs something here. Every other element greys by
## converting its `Image` once, which a live element has none of, so this asks
## the display material for a greyscale view instead: `greyscale_view` on
## `shaders/canvas/tonemap.gdshader`, a view-time uniform beside the ones the
## rolloff and the false colour already use. Nothing is read back for it and no
## second pass is drawn.
var greyscale: bool = false

## The material this element draws with, a duplicate of the canvas's own.
##
## A duplicate rather than the canvas's material itself, which is what the old
## pane shared, because this element sets one uniform the canvas must not have
## set: a painter greying the reference is not asking for a grey canvas. The
## parameters are copied across whenever the canvas's material changes, which
## is what keeps the two views the same picture.
var _material: ShaderMaterial = null

## The material the copy was last taken from, so a canvas that rebuilt its
## material is copied again.
var _copied_from: ShaderMaterial = null

## The smallest interval between two flushes of the canvas's backlog, the
## minimap's, and when the last one was, in the ticks of `Time.get_ticks_msec`.
const FLUSH_SECONDS := 0.25
var _flushed_msec: int = -1000000

## The easel's `composite_count` at the last redraw, so a poll with no new
## composite draws nothing. Read by a test, which is how "on a composite change
## rather than on a frame" is asserted rather than argued.
var drawn_composite: int = -1

## How many times [method refresh] asked for a redraw, for the same test.
var redraws: int = 0


func _init() -> void:
    name = "CanvasElement"
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    clip_contents = true
    visible = false


## The canvas this element mirrors, looked up rather than injected, the way the
## docker reaches its document.
func canvas() -> SaCanvas:
    return SaCanvasView.front_canvas() if is_inside_tree() else null


## The canvas's size in texels, or zero when there is no document behind it.
## What the board writes onto the element's `live_size`.
func canvas_size() -> Vector2i:
    var shown := canvas()
    if shown == null or not is_instance_valid(shown) or shown.easel == null:
        return Vector2i.ZERO
    return shown.easel.canvas_size


## Binds the easel's current output and takes the canvas's material, and
## answers whether anything moved.
##
## Called from the docker's own poll rather than from `_process`, so an element
## on a board nobody is looking at costs nothing: the docker is the one thing
## that knows whether the Reference docker is on screen.
func refresh() -> bool:
    var shown := canvas()
    if shown == null or not is_instance_valid(shown) or shown.easel == null:
        return false
    return refresh_from(shown.easel, shown.material as ShaderMaterial)


## [method refresh] against *easel* and *source*, the canvas's display material,
## rather than the canvas the scene holds.
##
## The half that decides, split out so a test can hand it a surface's easel: a
## headless run has no main scene to look a canvas up in, and the claim "on a
## composite change rather than on a frame" is about this arithmetic and not
## about the lookup.
func refresh_from(easel: SaEasel, source: ShaderMaterial) -> bool:
    if easel == null:
        return false
    # The element shows the whole picture, so what the window left unshown is
    # composited as soon as there is any.
    _flush_now(easel, Time.get_ticks_msec())
    var moved := false
    var output := easel.output
    if output != null and output.rid != _bound_rid:
        _shown = Texture2DRD.new()
        _shown.texture_rd_rid = output.rid
        _bound_rid = output.rid
        moved = true
    if source != null and (source != _copied_from or _material == null):
        _material = source.duplicate() as ShaderMaterial
        _copied_from = source
        material = _material
        moved = true
    if _material != null and source != null:
        _copy_parameters(source)
        _material.set_shader_parameter("greyscale_view", greyscale)
    if easel.composite_count != drawn_composite:
        drawn_composite = easel.composite_count
        moved = true
    if moved:
        redraws += 1
        queue_redraw()
    return moved


## Composites what the canvas's window left unshown, at most every
## [constant FLUSH_SECONDS] and not while Thumbnails while painting asks for
## the pen to lift or the painter to stop first, the minimap's own rule. Flushed on every frame, a
## fill or a stroke out of the window's reach was a whole composite a frame while
## the canvas sat on a board.
func _flush_now(easel: SaEasel, now_msec: int) -> void:
    if easel.backlog.is_empty() or SaSettingsPerformance.holds_redraw(SaSettings.thumbnails_while_painting):
        return
    if now_msec - _flushed_msec < FLUSH_SECONDS * 1000.0:
        return
    _flushed_msec = now_msec
    easel.flush()


## The canvas material's uniforms onto this element's copy.
##
## Every parameter rather than the ones this element cares about, because the
## list is the shader's and a uniform added to it later would
## otherwise stop reaching this view without anybody noticing. `greyscale_view`
## is set after this and is therefore the one value the copy does not share.
func _copy_parameters(source: ShaderMaterial) -> void:
    if _material == null or source.shader == null:
        return
    for uniform: Dictionary in source.shader.get_shader_uniform_list():
        var key := StringName(uniform["name"])
        _material.set_shader_parameter(key, source.get_shader_parameter(key))


func _draw() -> void:
    if _shown == null or region.size.x <= 0 or region.size.y <= 0:
        return
    draw_rect(Rect2(Vector2.ZERO, size), OUTSIDE, true)
    # The region is the crop or the whole canvas, and a flip is the same region
    # drawn through a mirror about this Control's own middle: a negative source
    # width draws nothing on this renderer, as the comment in
    # `ReferencePictureView.draw_board` says for the pictures.
    if flipped:
        draw_set_transform(Vector2(size.x, 0.0), 0.0, Vector2(-1.0, 1.0))
    draw_texture_rect_region(_shown, Rect2(Vector2.ZERO, size), Rect2(region))
    if flipped:
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## What a dump reads: whether the element is bound to an output, where it is
## drawn, and the three things a shot cannot tell apart at a glance.
func report() -> Dictionary:
    return {
        "bound": _bound_rid.is_valid(),
        "visible": visible,
        "rect": {"x": position.x, "y": position.y, "w": size.x, "h": size.y},
        "region": {"x": region.position.x, "y": region.position.y, "w": region.size.x, "h": region.size.y},
        "flipped": flipped,
        "greyscale": greyscale,
        "canvas_size": {"w": canvas_size().x, "h": canvas_size().y},
    }
