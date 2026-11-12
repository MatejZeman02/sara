## An export copies the whole canvas and dispatches over it.
##
## read every merged row against the hard rules and found one no: the
## `encoded_texture` copied `easel.output` whole through `_copy_of` and ran
## `convert_color_space` over all of it through `_dispatch_over`, and d73's
## `byte_image` did the same with `round_to_bytes` on every PNG and JPEG export,
## an sRGB document's included. Hard rule 2 says a compute shader is never
## dispatched over the whole canvas, and rule 1's export allowance names a
## readback, not a dispatch.
##
## These hold the new shape: every rectangle this path copies or dispatches over
## is a chunk cell, and no texture it allocates is the size of the document.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

## Bigger than one chunk in both directions, so the walk has a whole cell and
## two edge cells rather than one cell that is the whole picture.
const WIDE := Vector2i(700, 300)

const RED := Color(1.0, 0.0, 0.0, 1.0)


## A filled picture in *space*, composited so `output` holds it.
func _easel(space: SaColorSpace) -> SaEasel:
    var easel := SaEasel.create_default(WIDE, null, space)
    easel.document.fill_layer(RED)
    easel.request_full_composite()
    easel.process_pending_composite()
    return easel


## The rectangles of the grid: whole cells for all but the last column and row.
func test_the_cells_tile_the_picture_and_the_edges_are_clipped() -> void:
    var cells := SaExportGamut.cells_of(WIDE)
    var pitch := SaChunk.SIZE
    assert_eq(cells.size(), 3 * 2, "700 by 300 is three cells across and two down")
    var covered := 0
    for cell: Rect2i in cells:
        assert_true(cell.position.x % pitch == 0 and cell.position.y % pitch == 0, "%s sits on the grid" % cell)
        assert_true(cell.size.x <= pitch and cell.size.y <= pitch, "%s is never wider than a chunk" % cell)
        assert_true(cell.end.x <= WIDE.x and cell.end.y <= WIDE.y, "and is inside the picture")
        covered += cell.size.x * cell.size.y
    assert_eq(covered, WIDE.x * WIDE.y, "the cells tile the picture with no gap and no overlap")


## A picture smaller than a chunk is one cell the size of the picture, which is
## the whole texture and is what a small document always was.
func test_a_picture_under_a_chunk_is_one_cell_of_itself() -> void:
    var cells := SaExportGamut.cells_of(Vector2i(40, 12))
    assert_eq(cells.size(), 1, "one cell")
    assert_eq(cells[0], Rect2i(Vector2i.ZERO, Vector2i(40, 12)), "the size of the picture")


## The conversion no longer holds a second texture the size of the document.
##
## What it holds is one scratch cell at the pitch whatever the document is, so
## the VRAM an export of a big document adds does not grow with the document.
func test_a_converting_export_holds_one_cell_and_never_the_whole_output() -> void:
    for space: SaColorSpace in [SaColorSpace.oklab(), SaColorSpace.srgb().with_gamut(SaGamut.from_id(SaGamut.ID_DISPLAY_P3))]:
        var easel := _easel(space)
        var image := SaExportGamut.byte_image(easel.output)
        assert_not_null(image, "the export read something back")
        assert_eq(image.get_size(), WIDE, "as the whole picture")
        assert_eq(SaExportGamut.cells_visited, 6, "the walk visited the picture's six cells")
        var texel: int = int(SaFieldSpec.BYTES_PER_TEXEL[easel.output.format])
        var cell_bytes := SaChunk.SIZE * SaChunk.SIZE * texel
        var document_bytes := WIDE.x * WIDE.y * texel
        assert_eq(SaExportGamut.peak_scratch_bytes, cell_bytes, "and held one cell, not the picture")
        assert_true(cell_bytes < document_bytes, "which is the smaller of the two by the picture's own shape")
        easel.free()


## A per-cell export writes the same bytes a whole-canvas one would have: every
## cell's texels are its own and a seam between two cells is not a seam.
func test_the_export_lands_every_cell_where_the_picture_has_it() -> void:
    var easel := _easel(SaColorSpace.oklab())
    var image := SaExportGamut.byte_image(easel.output)
    assert_not_null(image, "the export read back")
    # The fill is one colour everywhere, so every probe reads the same bytes
    # whatever cell it fell in. A cell written at the wrong place, or skipped,
    # leaves a transparent one and reads as a nought.
    var probes: Array[Vector2i] = [
        Vector2i(0, 0),
        Vector2i(SaChunk.SIZE - 1, SaChunk.SIZE - 1),
        Vector2i(SaChunk.SIZE, SaChunk.SIZE),
        Vector2i(WIDE.x - 1, WIDE.y - 1),
        Vector2i(SaChunk.SIZE + 5, SaChunk.SIZE + 5),
    ]
    var first := image.get_pixel(probes[0].x, probes[0].y)
    assert_true(first.r > 0.0 or first.g > 0.0, "an Oklab red is not black")
    for at: Vector2i in probes:
        assert_eq(image.get_pixel(at.x, at.y), first, "the cell holding %s holds the picture" % at)
    easel.free()


## The recorder converts per cell too, and its frame is what the view drew.
##
## Its copy of the conversion is the one `sa_recorder.gd` holds beside
## `encoded_texture`'s: a whole-canvas copy and one dispatch over the frame. It
## takes `encoded_byte_image` now, so a recorded frame is under the same bound.
func test_a_recorded_frame_is_still_read_back_converted() -> void:
    var canvas := SaCanvas.new()
    canvas.canvas_size = WIDE
    canvas.easel = _easel(SaColorSpace.oklab())
    canvas.add_child(canvas.easel)
    var recorder := SaRecorder.new()
    recorder.bind_canvas(canvas)
    var frame := recorder.display_image(canvas)
    assert_not_null(frame, "the recorder read a frame")
    assert_eq(frame.get_format(), Image.FORMAT_RGBA8, "eight bits, as a frame is")
    assert_true(frame.get_pixel(0, 0).r > 0.0 or frame.get_pixel(0, 0).g > 0.0, "and not a frame of black")
    assert_eq(SaExportGamut.cells_visited, 6, "the frame was read a cell at a time")
    recorder.free()
    canvas.free()
