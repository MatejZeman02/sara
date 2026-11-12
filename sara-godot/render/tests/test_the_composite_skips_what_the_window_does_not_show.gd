## The composite skips what the window does not show.
##
## The ask: "A painter zoomed into a corner of a large canvas pays for the
## composite of the whole of it on every dirty frame." The compositor already
## skipped chunks outside a visible rectangle, but the easel always handed it
## the whole canvas, so the skip never happened. The easel now hands it what the
## view shows, grown by a chunk, and holds what that leaves out in its backlog
## until the window reaches it or a reader of the whole picture flushes.
##
## Painted through a real `SaCanvas` in a viewport a quarter of its width, so
## the rectangle is the one the view itself works out from its transform.
extends "res://tests/test_framework.gd"

## A canvas builds an easel, and an easel composites.
const REQUIRES_GPU := true

## The window, and a canvas four windows wide and four tall.
const WINDOW := Vector2i(512, 512)
const CANVAS := Vector2i(2048, 2048)

const RED := Color(1.0, 0.0, 0.0, 1.0)

var _host: Node = null


## Parented to an autoload rather than to the root, because the runner calls
## this from its own `_ready` and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "B2TestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null


## A canvas of `CANVAS` at a zoom of one in a viewport of `WINDOW`, its top left
## corner in view and everything composited once. In plain sRGB, so a red
## texel is red in the exported file.
func _canvas() -> SaCanvas:
    var viewport := SubViewport.new()
    viewport.size = WINDOW
    _host.add_child(viewport)
    var canvas := SaCanvas.new()
    canvas.canvas_size = CANVAS
    canvas.easel = SaEasel.create_default(CANVAS, null, SaColorSpace.srgb())
    canvas.add_child(canvas.easel)
    viewport.add_child(canvas)
    canvas.scale = Vector2.ONE
    canvas.position = Vector2.ZERO
    canvas.easel.process_pending_composite()
    return canvas


## Paints the chunk at the canvas's top left corner red, the way a stroke
## leaves it: the texels written, then the region handed to the document.
func _paint_first_corner(canvas: SaCanvas) -> void:
    var chunk := canvas.document.active_layer.get_or_create_field(Vector2i.ZERO)
    GlobalShaderCompiler.get_rd().texture_clear(chunk.rid, RED, 0, 1, 0, 1)
    canvas.document.invalidate_chunk_regions({Vector2i.ZERO: SaDocument.WHOLE_CHUNK})


## The output's texel at *at*, read as it stands and with no flush.
static func _output_texel(canvas: SaCanvas, at: Vector2i) -> Color:
    return SaExport.get_texture_image_float(canvas.easel.output).get_pixelv(at)


func test_the_view_says_what_it_shows_in_document_pixels() -> void:
    var canvas := _canvas()
    assert_eq(canvas.shown_in_document(), Rect2(Vector2.ZERO, Vector2(WINDOW)), "At a zoom of one the window is its own size")
    canvas.scale = Vector2(2.0, 2.0)
    canvas.position = Vector2(-256.0, -128.0)
    assert_eq(canvas.shown_in_document(), Rect2(128.0, 64.0, 256.0, 256.0), "Zoomed to two, half of it from the pan on")
    canvas.scale = Vector2(-1.0, 1.0)
    canvas.position = Vector2(float(WINDOW.x), 0.0)
    assert_eq(canvas.shown_in_document(), Rect2(Vector2.ZERO, Vector2(WINDOW)), "A mirror shows the same box")


func test_a_full_composite_draws_the_window_and_holds_the_rest() -> void:
    var canvas := _canvas()
    var backlog := canvas.easel.backlog
    # The window is 512 square at the origin, and grown by one chunk it reaches
    # the cells from 0 to 2 in each direction and none past them.
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(2, 2), Vector2i(2, 0)]:
        assert_false(backlog._regions.has(grid_pos), "%s is in the window and was drawn" % grid_pos)
    for grid_pos: Vector2i in [Vector2i(3, 0), Vector2i(7, 7), Vector2i(0, 3)]:
        assert_true(backlog._regions.has(grid_pos), "%s is outside it and waits" % grid_pos)


func test_a_corner_painted_out_of_view_waits_and_the_export_holds_it() -> void:
    var canvas := _canvas()
    var easel := canvas.easel
    var before := _output_texel(canvas, Vector2i(10, 10))
    _paint_first_corner(canvas)
    # To the far corner, the window now over the last 512 of each direction.
    canvas.position = -Vector2(CANVAS - WINDOW)
    var composites := easel.composite_count
    easel.process_pending_composite()
    assert_true(easel.backlog._regions.has(Vector2i.ZERO), "The first corner's chunk waits")
    assert_eq(_output_texel(canvas, Vector2i(10, 10)), before, "and the output there is what it was before the paint")
    assert_eq(easel.composite_count, composites + 1, "The frame composited what it could reach")
    assert_false(easel.backlog._regions.has(Vector2i(7, 7)), "which is the far corner the full composite had held")

    var path := SaDataRoot.path("test_b2_the_corner.png")
    assert_eq(SaExport.export_png(easel, path), OK, "The picture exports")
    var image := Image.new()
    assert_eq(image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)), OK, "and the file reads back")
    var texel := image.get_pixel(10, 10)
    assert_almost_eq(texel.r, 1.0, 0.01, "The file holds the red of the first corner")
    assert_almost_eq(texel.g, 0.0, 0.01, "and nothing of the grey it had")
    assert_true(easel.backlog.is_empty(), "The export flushed everything held")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_a_pan_back_composites_what_it_reaches() -> void:
    var canvas := _canvas()
    var easel := canvas.easel
    canvas.position = -Vector2(CANVAS - WINDOW)
    _paint_first_corner(canvas)
    easel.process_pending_composite()
    assert_true(easel.backlog._regions.has(Vector2i.ZERO), "Painted out of view, the chunk waits")
    var composites := easel.composite_count
    easel.process_pending_composite()
    assert_eq(easel.composite_count, composites, "A frame where nothing changed and nothing moved composites nothing")
    canvas.position = Vector2.ZERO
    easel.process_pending_composite()
    assert_false(easel.backlog._regions.has(Vector2i.ZERO), "Panned back, the chunk is drawn")
    assert_almost_eq(_output_texel(canvas, Vector2i(10, 10)).r, 1.0, 0.01, "and the output shows the paint")
    assert_false(easel.backlog._regions.has(Vector2i(7, 7)), "The far corner was drawn while the window was on it")


func test_an_easel_nothing_shows_composites_everything() -> void:
    var easel := SaEasel.create_default(CANVAS, null, SaColorSpace.srgb())
    easel.process_pending_composite()
    assert_true(easel.backlog.is_empty(), "With no view the window is the whole canvas and nothing waits")
    easel.free()
