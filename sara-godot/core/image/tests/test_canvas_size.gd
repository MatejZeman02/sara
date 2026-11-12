## Image > Canvas Size: growing and trimming the document about an anchor,
## read back texel by texel.
##
## The crop suite beside this one covers the pass that takes away. What is new
## here is a rectangle that reaches outside the canvas, which `crop_to` clips
## and `resize_to` does not, so every test below puts a mark somewhere known and
## asks where it ended up.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

var _easel: SaEasel = null
var _doc: SaDocument = null
var _crop: SaCrop = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(1024, 768))
    _doc = _easel.document
    _crop = SaCrop.new(_doc)


func after_each() -> void:
    _crop = null
    _easel.free()
    _easel = null
    _doc = null


func _texel(x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var texture := _doc.active_layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(
        bytes, texture.format, (y - grid.y * SaChunk.SIZE) * texture.size.x + (x - grid.x * SaChunk.SIZE)
    )


## An 8 by 8 square of a colour nothing else is, through the selection and a
## fill, which is the door a painter would use.
func _mark(at: Vector2i, color: Color) -> void:
    _doc.selection.select_rect(Rect2i(at, Vector2i(8, 8)))
    _doc.fill_layer(color)
    _doc.selection.deselect()


## The nine cells, without touching a document. This is the whole of where the
## old picture lands, so it is worth asserting on its own rather than only
## through the six texel tests below.
func test_the_anchor_places_the_old_origin() -> void:
    var from := Vector2i(1000, 800)
    var bigger := Vector2i(1400, 1000)
    assert_eq(SaCrop.offset_for(from, bigger, Vector2i(0, 0)), Vector2i(0, 0), "Top left keeps the origin")
    assert_eq(SaCrop.offset_for(from, bigger, Vector2i(1, 1)), Vector2i(200, 100), "Centre halves the growth")
    assert_eq(SaCrop.offset_for(from, bigger, Vector2i(2, 2)), Vector2i(400, 200), "Bottom right takes all of it")

    var smaller := Vector2i(600, 400)
    assert_eq(SaCrop.offset_for(from, smaller, Vector2i(0, 0)), Vector2i(0, 0), "and a trim from the top left")
    assert_eq(SaCrop.offset_for(from, smaller, Vector2i(2, 2)), Vector2i(-400, -400), "or from the bottom right")


## `floori` rather than an integer division, because a trim makes the difference
## negative and an integer division truncates towards zero: the extra column of
## an odd difference would come off one side growing and the other trimming.
func test_an_odd_difference_rounds_the_same_way_both_directions() -> void:
    assert_eq(
        SaCrop.offset_for(Vector2i(100, 100), Vector2i(105, 105), Vector2i(1, 1)),
        Vector2i(2, 2),
        "A centred grow of five puts two before the picture"
    )
    assert_eq(
        SaCrop.offset_for(Vector2i(100, 100), Vector2i(95, 95), Vector2i(1, 1)),
        Vector2i(-3, -3),
        "and a centred trim of five takes three off the same side"
    )


## The case that matters, growing. The picture stays put under a top left anchor
## and the new region holds no chunks at all, which is hard rule 3 rather than a
## sheet of transparent texels.
func test_growing_from_the_top_left_leaves_the_picture_where_it_was() -> void:
    _mark(Vector2i(500, 400), Color(1.0, 0.0, 0.5, 1.0))
    var held := _doc.active_layer.chunks.size()

    assert_true(_crop.resize_to(Vector2i(1536, 1024), Vector2i(0, 0)), "The resize happens")
    assert_eq(_doc.canvas_size, Vector2i(1536, 1024), "and the document is the new size")
    assert_almost_eq(_texel(502, 402).r, 1.0, 1e-4, "The mark did not move")
    assert_eq(_doc.active_layer.chunks.size(), held, "and the added region allocated nothing")


## The far edge anchor pushes the old picture across by the whole difference,
## which is the case a centred-only implementation gets right by accident.
func test_growing_from_the_bottom_right_pushes_the_picture_across() -> void:
    _mark(Vector2i(100, 100), Color(0.0, 0.25, 1.0, 1.0))

    assert_true(_crop.resize_to(Vector2i(1524, 1268), Vector2i(2, 2)), "The resize happens")
    assert_eq(_doc.canvas_size, Vector2i(1524, 1268), "at the new size")
    assert_almost_eq(_texel(602, 602).r, 0.0, 1e-4, "The mark moved by the whole difference")
    assert_almost_eq(_texel(602, 602).b, 1.0, 1e-4, "and arrived whole")
    assert_eq(_texel(102, 102).a, 0.0, "leaving nothing where it was")


## Trimming is the same pass with a rectangle inside the canvas, and it throws
## away what falls outside.
func test_trimming_from_the_bottom_right_keeps_that_corner() -> void:
    _mark(Vector2i(900, 700), Color(0.0, 1.0, 0.25, 1.0))
    _mark(Vector2i(100, 100), Color(1.0, 1.0, 0.0, 1.0))

    assert_true(_crop.resize_to(Vector2i(512, 384), Vector2i(2, 2)), "The trim happens")
    assert_eq(_doc.canvas_size, Vector2i(512, 384), "at the new size")
    assert_almost_eq(_texel(390, 318).g, 1.0, 1e-4, "The bottom right corner survived")
    assert_almost_eq(_texel(390, 318).r, 0.0, 1e-4, "unchanged")


## One step that undo restores whole, size and released chunks together, which
## is what makes a trim safe to try.
func test_undo_restores_the_size_and_what_a_trim_threw_away() -> void:
    _mark(Vector2i(900, 700), Color(0.0, 1.0, 0.25, 1.0))
    var steps := _doc.history.step_count()

    assert_true(_crop.resize_to(Vector2i(400, 300), Vector2i(0, 0)), "A trim that throws that corner away")
    assert_eq(_doc.history.step_count(), steps + 1, "is one step")

    assert_true(_doc.undo(), "which undoes")
    assert_eq(_doc.canvas_size, Vector2i(1024, 768), "restoring the size")
    assert_almost_eq(_texel(902, 702).g, 1.0, 1e-4, "and the paint it released")


## A grow undoes as cleanly as a trim, and it is recorded under a name of its
## own. `SaHistory` has no reader for a step's name, so the assertion is that
## the two constants differ rather than that the stack says so: the undo menu is
## where a painter finds out what they just did, and a grow reading "Crop" is a
## lie about the thing it is offering to undo.
func test_a_grow_undoes_and_carries_a_name_of_its_own() -> void:
    assert_true(SaCrop.RESIZE_ACTION_NAME != SaCrop.ACTION_NAME, "A resize is not a crop in the history")
    _mark(Vector2i(500, 400), Color(1.0, 0.0, 0.5, 1.0))

    assert_true(_crop.resize_to(Vector2i(2048, 1536), Vector2i(1, 1)), "A centred grow")
    assert_almost_eq(_texel(1014, 784).r, 1.0, 1e-4, "moves the mark by half the growth")

    assert_true(_doc.undo(), "which undoes")
    assert_eq(_doc.canvas_size, Vector2i(1024, 768), "restoring the size")
    assert_almost_eq(_texel(502, 402).r, 1.0, 1e-4, "and putting the mark back")


## A resize to the size it already is must not put a step on the stack that
## does nothing when it fires, the same guard the crop pass has.
func test_a_resize_that_changes_nothing_records_nothing() -> void:
    var steps := _doc.history.step_count()
    assert_false(_crop.resize_to(_doc.canvas_size, Vector2i(1, 1)), "The same size is not a resize")
    assert_false(_crop.resize_to(Vector2i(0, 400), Vector2i(1, 1)), "and neither is a zero dimension")
    assert_eq(_doc.history.step_count(), steps, "so nothing is recorded")
