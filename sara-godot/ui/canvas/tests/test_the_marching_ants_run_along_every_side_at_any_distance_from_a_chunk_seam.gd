## The marching ants run along every edge of a selection, its
## edge five pixels from a chunk seam included.
##
## The ants once vanished on the left side of a selection. The selection's box read x 763 from the door,
## five texels short of the seam at 768, but the box only ever grows, and the
## mask itself began at 768 with an empty chunk left of the seam. Two things in
## `ui/canvas/selection_overlay.gd` and `shaders/canvas/selection.gdshader`
## hid that side. A sample past a chunk's square clamped to the texel itself,
## so an edge on a chunk's first column read no change, and the chunk was drawn
## with `clip_uv`, which held the texture coordinate still in the helper lanes
## beside its edge, so the screen derivative on that column was a quarter of a
## texel at a zoom of 0.88 and the step never left the chunk at all.
##
## This suite renders the real overlay over a real canvas into a viewport, for
## rectangles whose four sides each lie 0, 1, 5 and 128 texels from a seam, on
## the seam's near side and on its far side, at four zooms, and asks that every
## run of four screen pixels along every side holds an ant. A rectangle that
## crosses a seam is asked for no line along it.
extends "res://tests/test_framework.gd"

## A canvas builds an easel, and a selection's chunks are textures on the
## RenderingDevice.
const REQUIRES_GPU := true

const CANVAS := Vector2i(1536, 1536)
const WINDOW := Vector2i(1200, 1200)
const DISTANCES: Array[int] = [0, 1, 5, 128]
## A zoom that once failed, and three around it.
const ZOOMS: Array[float] = [0.5, 0.8787, 1.0, 2.0]
## How many screen pixels from each corner a side is read from, so a corner's
## ants, which the other side also draws, never stand in for a side's own.
const CORNER := 6

var _host: Node = null


func before_each() -> void:
    _host = Node.new()
    _host.name = "U686AntsTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null


## The second seam of *canvas*'s chunk grid, in document pixels, from the side
## of a chunk the selection is cut into, asked rather than assumed. The one
## texel selected to ask is replaced by the next selection.
func _seam(canvas: SaCanvas) -> int:
    var selection := canvas.document.selection
    selection.select_rect(Rect2i(0, 0, 1, 1))
    for grid_pos: Vector2i in selection.chunks:
        return (selection.chunks[grid_pos] as SaChunk).pixel_size() * 2
    return 0


## Puts the document point *centre* in the middle of the window.
static func _centre_on(canvas: SaCanvas, centre: Vector2) -> void:
    canvas.position = Vector2(WINDOW) / 2.0 - centre * canvas.scale.x


## A canvas in a viewport, its paper hidden so the overlay draws over the
## canvas's grey ground alone, at *zoom*.
func _canvas(zoom: float) -> SaCanvas:
    var viewport := SubViewport.new()
    viewport.size = WINDOW
    viewport.transparent_bg = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    _host.add_child(viewport)
    var canvas := SaCanvas.new()
    canvas.canvas_size = CANVAS
    viewport.add_child(canvas)
    canvas.self_modulate = Color(1.0, 1.0, 1.0, 0.0)
    canvas.scale = Vector2(zoom, zoom)
    var overlay := SaSelectionOverlay.attach_to(canvas)
    overlay.hold_the_ants()
    return canvas


## What the window shows once the overlay has laid its chunks out and drawn
## them, which takes a frame of the tree and a frame of the server.
func _frame(canvas: SaCanvas) -> Image:
    var tree := Engine.get_main_loop() as SceneTree
    for _i in 3:
        await tree.process_frame
    RenderingServer.force_draw(false, 0.0)
    return canvas.get_viewport().get_texture().get_image()


## Whether the pixel is an ant, pure black or pure white. The canvas's own
## ground draws a mid grey under the overlay however its paper is hidden.
static func _is_ant(image: Image, x: int, y: int) -> bool:
    if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
        return false
    var pixel := image.get_pixel(x, y)
    var dark := pixel.r < 0.01 and pixel.g < 0.01 and pixel.b < 0.01
    var light := pixel.r > 0.99 and pixel.g > 0.99 and pixel.b > 0.99
    return pixel.a > 0.99 and (dark or light)


## The runs of four screen pixels along one side with no ant in them. A side is
## the line of screen pixels that holds the selection's first texel past the
## boundary at *at*, in document pixels, and a pixel either way of it.
func _gaps(image: Image, canvas: SaCanvas, vertical: bool, at: float, from: float, to: float) -> int:
    var zoom := canvas.scale.x
    var offset := canvas.position
    var across := (offset.x if vertical else offset.y) + at * zoom
    var start := int((offset.y if vertical else offset.x) + from * zoom) + CORNER
    var stop := int((offset.y if vertical else offset.x) + to * zoom) - CORNER
    var hits: Array[bool] = []
    for along in range(start, stop):
        var hit := false
        for step in range(-2, 2):
            var x := int(floor(across)) + step if vertical else along
            var y := along if vertical else int(floor(across)) + step
            hit = hit or _is_ant(image, x, y)
        hits.append(hit)
    var gaps := 0
    for i in range(hits.size() - 3):
        if not (hits[i] or hits[i + 1] or hits[i + 2] or hits[i + 3]):
            gaps += 1
    return gaps


## Every side of *box* outlined on *canvas*, run by run of four pixels.
func _check_every_side(canvas: SaCanvas, box: Rect2i, said: String) -> void:
    var image: Image = await _frame(canvas)
    var left := float(box.position.x)
    var top := float(box.position.y)
    # The first texel inside the far sides, so the line read is the inside one.
    var right := float(box.end.x) - 0.5
    var bottom := float(box.end.y) - 0.5
    var gaps := {
        "left": _gaps(image, canvas, true, left, top, float(box.end.y)),
        "right": _gaps(image, canvas, true, right, top, float(box.end.y)),
        "top": _gaps(image, canvas, false, top, left, float(box.end.x)),
        "bottom": _gaps(image, canvas, false, bottom, left, float(box.end.x)),
    }
    for side: String in gaps:
        assert_eq(gaps[side], 0, "%s: every four screen pixels of the %s side hold an ant" % [said, side])


func _sweep(near_side: bool) -> void:
    for zoom: float in ZOOMS:
        for distance: int in DISTANCES:
            var canvas := _canvas(zoom)
            var seam := _seam(canvas)
            var shift := -distance if near_side else distance
            var box := Rect2i(seam + shift, seam + shift, seam, seam)
            _centre_on(canvas, Vector2(box.get_center()))
            canvas.document.selection.select_rect(box)
            var said := "zoom %s, sides %d texels %s a seam" % [zoom, distance, "before" if near_side else "past"]
            await _check_every_side(canvas, box, said)
            canvas.get_viewport().free()


## Sides on the seam and inside the chunks past each one, the left and top
## sides starting a chunk the selection begins in.
func test_sides_on_a_seam_or_past_it_are_outlined_at_every_zoom() -> void:
    await _sweep(false)


## Sides inside the chunks before each seam, so the selection runs on into the
## next chunk and its far sides end inside one.
func test_sides_before_a_seam_are_outlined_at_every_zoom() -> void:
    await _sweep(true)


## A mask with a chunk left of the seam held and empty, and the selection
## beginning on the seam's first texel. The clamp read that texel as its own
## neighbour and the left side drew nothing.
func test_a_side_on_a_seam_beside_an_empty_chunk_is_outlined() -> void:
    for zoom: float in ZOOMS:
        var canvas := _canvas(zoom)
        var selection := canvas.document.selection
        var seam := _seam(canvas)
        var wide := Rect2i(seam - 5, seam - 200, 300, 500)
        selection.select_rect(wide)
        selection.select_rect(Rect2i(0, 0, seam, CANVAS.y), SaSelection.Mode.SUBTRACT)
        var box := Rect2i(seam, wide.position.y, wide.end.x - seam, wide.size.y)
        _centre_on(canvas, Vector2(box.get_center()))
        await _check_every_side(canvas, box, "zoom %s, an emptied chunk" % zoom)
        canvas.get_viewport().free()


## A selection running across a seam draws no line along it, because the texel
## past the seam is selected too.
func test_a_selection_across_a_seam_draws_no_line_along_it() -> void:
    for zoom: float in ZOOMS:
        var canvas := _canvas(zoom)
        var seam := _seam(canvas)
        var box := Rect2i(seam - 100, seam - 100, 300, 300)
        _centre_on(canvas, Vector2(box.get_center()))
        canvas.document.selection.select_rect(box)
        var image: Image = await _frame(canvas)
        var ants := 0
        var first := int(canvas.position.y + (box.position.y + 20) * zoom)
        var last := int(canvas.position.y + (box.end.y - 20) * zoom)
        for along in range(first, last):
            for step in range(-2, 3):
                for seam_at: float in [float(seam), float(seam) - 0.5]:
                    if _is_ant(image, int(floor(canvas.position.x + seam_at * zoom)) + step, along):
                        ants += 1
        assert_eq(ants, 0, "zoom %s: no ant stands along the vertical seam inside the selection" % zoom)
        canvas.get_viewport().free()
