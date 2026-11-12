## Read and write pixels.
##
## The readback is the point of the unit and also its risk: an image read from
## the wrong corner of the rectangle, or written back one chunk over, is a
## plausible picture rather than an error. So every assertion here reads the
## layer back through `SaExport` afterwards, the way the other filter suites do,
## and the colours are chosen so a copy that lands in the wrong place says so.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const SaExportScript = preload("res://core/export/sa_export.gd")

const RED := Color(1.0, 0.0, 0.0, 1.0)
const BLUE := Color(0.0, 0.0, 1.0, 1.0)

## Where every case below runs: inside chunk (1,1) and well away from its
## edges, so "unchanged outside the rectangle" has room to be read.
const RUN_RECT := Rect2i(300, 300, 100, 40)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(1024, 1024))
    _doc = _easel.document
    _layer = _doc.active_layer
    _layer.get_or_create_chunk(Vector2i(1, 1)).clear(RED)


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _layer = null


## A context over [constant RUN_RECT], which is a selection so the rectangle is
## exactly the one the assertions name rather than the whole allocated chunk.
func _context(step_name: String = "Box blur") -> SaFilterContext:
    _doc.selection.select_rect(RUN_RECT)
    return SaFilterContext.new(_doc, _layer, &"", step_name)


## One texel of the layer, in document coordinates.
func _layer_texel(x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var texture := _layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    var image := SaExportScript.get_texture_image_float(texture)
    return image.get_pixel(x - grid.x * SaChunk.SIZE, y - grid.y * SaChunk.SIZE)


# ---------------------------------------------------------------------------
# Reading
# ---------------------------------------------------------------------------


func test_read_pixels_answers_the_rectangle_as_a_float_image() -> void:
    var ctx := _context()

    var image := ctx.read_pixels(0)

    assert_not_null(image, "The readback answered")
    assert_eq(image.get_size(), RUN_RECT.size, "the size of the rectangle the run covers")
    assert_eq(image.get_format(), Image.FORMAT_RGBAF, "in RGBAF, whatever depth the document stores")
    assert_eq(ctx.rect, RUN_RECT, "and the rectangle is left on the context to write back into")
    assert_almost_eq(image.get_pixel(0, 0).r, 1.0, 1e-3, "The corner is the layer's own colour")
    assert_almost_eq(image.get_pixel(99, 39).r, 1.0, 1e-3, "and so is the far corner")


func test_a_margin_widens_what_is_read() -> void:
    var ctx := _context()

    var image := ctx.read_pixels(8)

    assert_eq(image.get_size(), RUN_RECT.size + Vector2i(16, 16), "The margin is added on every side")
    assert_eq(ctx.rect, Rect2i(292, 292, 116, 56), "and the rectangle says so")


func test_read_pixels_keeps_a_value_the_display_cannot_hold() -> void:
    _layer.get_or_create_chunk(Vector2i(1, 1)).clear(Color(2.5, -0.5, 0.0, 1.0))
    var ctx := _context()

    var image := ctx.read_pixels(0)

    assert_almost_eq(image.get_pixel(4, 4).r, 2.5, 1e-3, "Above one survives the readback")
    assert_almost_eq(image.get_pixel(4, 4).g, -0.5, 1e-3, "and so does below zero, which is hard rule 5")


# ---------------------------------------------------------------------------
# The edge-clamped read
# ---------------------------------------------------------------------------


func test_a_read_outside_the_rectangle_is_the_edge() -> void:
    var ctx := _context()
    var image := ctx.read_pixels(0)
    image.set_pixel(0, 0, BLUE)
    image.set_pixel(99, 39, BLUE)

    assert_eq(ctx.pixel(image, Vector2i(-5, -5)), BLUE, "Past the top left corner is the corner")
    assert_eq(ctx.pixel(image, Vector2i(0, -1)), BLUE, "Straight above the first row is the first row")
    assert_eq(ctx.pixel(image, Vector2i(-1, 0)), BLUE, "and left of the first column is the first column")
    assert_eq(ctx.pixel(image, Vector2i(500, 500)), BLUE, "Past the bottom right corner is that corner")
    assert_eq(ctx.pixel(image, Vector2i(0, 0)), BLUE, "and a read inside is the plain pixel")


func test_the_clamped_read_survives_no_image_at_all() -> void:
    var ctx := _context()
    assert_eq(ctx.pixel(null, Vector2i(0, 0)), Color(0.0, 0.0, 0.0, 0.0), "No image reads as transparent, not as an error")


# ---------------------------------------------------------------------------
# Writing
# ---------------------------------------------------------------------------


func test_a_changed_pixel_written_back_reaches_the_layer() -> void:
    var ctx := _context()
    var image := ctx.read_pixels(0)
    image.set_pixel(50, 20, BLUE)

    assert_true(ctx.write_pixels(image), "The write landed")
    assert_almost_eq(_layer_texel(350, 320).b, 1.0, 1e-3, "The pixel it changed is blue in the layer")
    assert_almost_eq(_layer_texel(350, 320).r, 0.0, 1e-3, "and no longer red")
    assert_almost_eq(_layer_texel(351, 320).r, 1.0, 1e-3, "Its neighbour inside the rectangle is untouched")
    assert_almost_eq(_layer_texel(280, 320).r, 1.0, 1e-3, "and so is the layer outside it")
    assert_almost_eq(_layer_texel(420, 320).r, 1.0, 1e-3, "on the other side too")


func test_the_write_is_one_step_named_after_the_filter_and_undoes() -> void:
    var ctx := _context("Threshold")
    var image := ctx.read_pixels(0)
    image.set_pixel(50, 20, BLUE)
    ctx.write_pixels(image)

    assert_true(_doc.undo_redo.has_undo(), "One step, and there was none before")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Threshold", "named after the filter, the way an apply names one")
    assert_true(_doc.undo(), "which undoes")
    assert_almost_eq(_layer_texel(350, 320).r, 1.0, 1e-3, "and puts the pixel back")
    assert_almost_eq(_layer_texel(350, 320).b, 0.0, 1e-3, "with nothing of the write left")


func test_an_image_of_the_wrong_size_is_refused_whole() -> void:
    var ctx := _context()
    ctx.read_pixels(0)
    var wrong := Image.create_empty(10, 10, false, Image.FORMAT_RGBAF)
    wrong.fill(BLUE)

    assert_false(ctx.write_pixels(wrong), "A picture that is not the region read is refused")
    assert_almost_eq(_layer_texel(350, 320).r, 1.0, 1e-3, "and the layer is untouched")
    assert_false(_doc.undo_redo.has_undo(), "with no step behind it")


func test_a_write_before_any_read_is_refused() -> void:
    var ctx := _context()
    var image := Image.create_empty(RUN_RECT.size.x, RUN_RECT.size.y, false, Image.FORMAT_RGBAF)

    assert_false(ctx.write_pixels(image), "There is no rectangle yet, so there is nowhere to write")
    assert_false(_doc.undo_redo.has_undo(), "and nothing was recorded")


func test_the_write_does_not_narrow_the_callers_image() -> void:
    var ctx := _context()
    var image := ctx.read_pixels(0)
    image.set_pixel(50, 20, Color(3.0, 0.0, 0.0, 1.0))

    ctx.write_pixels(image)

    assert_eq(image.get_format(), Image.FORMAT_RGBAF, "The caller keeps the image it handed over")
    assert_almost_eq(image.get_pixel(50, 20).r, 3.0, 1e-3, "at the value it wrote, not at a converted one")
    assert_almost_eq(_layer_texel(350, 320).r, 3.0, 1e-3, "and the layer took the value above one whole")
