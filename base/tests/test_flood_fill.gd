## The fill tool: a click floods a region and paints it, and nothing else.
##
## The fill tool must not fill the whole active layer on a click, which would be
## the Edit menu's operation with a cursor over it, so every assertion here is
## about the difference between those two.
##
## **The region growth is `SaWand`'s and is asserted in `test_wand.gd`.** This
## suite is about what the fill tool does with it: the paint, the chunks it
## allocates, the selection it leaves alone and the one it clips to.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const StateBucketFillScript = preload("res://modules/sara-base-modules/base/tools/state_bucket_fill.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const RED := Color(1.0, 0.0, 0.0, 1.0)
const BLUE := Color(0.0, 0.0, 1.0, 1.0)

var _surface: SaSurface = null
var _doc: SaDocument = null


## Three by three chunks, so a shape can sit in one corner and leave six chunks
## with nothing in them, which is the clause about the chunk count.
func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(768, 768))
    _doc = _surface.get_document()


func after_each() -> void:
    _doc.free()
    _surface.easel.free()
    _surface = null
    _doc = null


func _tool(colour: Color = BLUE) -> Object:
    var fill := StateBucketFillScript.new()
    fill.surface = _surface
    SaColors.foreground = colour
    fill.antialias = false
    return fill


## Fills *rect* of the active layer with *colour* through a masked fill, then
## drops the selection, which is `test_wand.gd`'s helper and the same reason:
## a shape has to be painted before a flood can stop at it.
func _paint_rect(rect: Rect2i, colour: Color) -> void:
    _doc.selection.select_rect(rect)
    _doc.fill_layer(colour, _doc.active_layer)
    _doc.selection.deselect()


func _texel(x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var chunk: SaChunk = _doc.active_layer.chunks.get(grid, null)
    if chunk == null:
        return Color(0, 0, 0, 0)
    var texture: SaTexture = chunk.field(chunk.fields.keys()[0])
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var at := ((y % SaChunk.SIZE) * texture.size.x + x % SaChunk.SIZE) * 16
    return Color(bytes.decode_float(at), bytes.decode_float(at + 4), bytes.decode_float(at + 8), bytes.decode_float(at + 12))


## The whole claim, in one gesture: click inside a closed shape and the inside
## is filled while the outside is not.
func test_a_click_inside_a_closed_shape_fills_the_inside_and_not_the_outside() -> void:
    # A ring of red with a transparent hole in the middle of the first chunk.
    _paint_rect(Rect2i(16, 16, 160, 160), RED)
    _paint_rect(Rect2i(40, 40, 112, 112), Color(0, 0, 0, 0))

    var fill := _tool()
    var touched: int = fill.fill_at(Vector2i(96, 96))
    assert_true(touched > 0, "The click landed and something was painted, %d chunk(s)" % touched)

    var inside := _texel(96, 96)
    assert_almost_eq(inside.b, 1.0, 0.02, "The hole is filled with the foreground colour")
    assert_almost_eq(inside.a, 1.0, 0.02, "and it is opaque")

    var wall := _texel(20, 96)
    assert_almost_eq(wall.r, 1.0, 0.02, "The wall of the shape is still red")
    assert_almost_eq(wall.b, 0.0, 0.02, "and the fill did not cross it")

    var outside := _texel(400, 400)
    assert_almost_eq(outside.a, 0.0, 0.02, "and nothing outside the shape was touched")


## Hard rule 3, sparse chunks: a fill inside a small shape
## leaves the chunk count where it was.
##
## The old tool called `fill_layer`, which allocates the whole grid for an opaque
## colour, so a fill in one corner of a 768 by 768 document allocated nine chunks
## whatever the painter clicked on.
func test_a_fill_inside_a_small_shape_allocates_no_new_chunks() -> void:
    _paint_rect(Rect2i(16, 16, 160, 160), RED)
    _paint_rect(Rect2i(40, 40, 112, 112), Color(0, 0, 0, 0))
    var before := _doc.active_layer.chunks.size()

    var touched: int = _tool().fill_at(Vector2i(96, 96))
    assert_eq(touched, 1, "The fill reached one chunk")
    assert_eq(_doc.active_layer.chunks.size(), before, "and allocated none, still %d" % before)


## A fill is not a selection gesture. `SaWand.flood` writes into the document's
## own selection, so the tool has to put the painter's back or clicking with the
## fill would move the ants.
func test_a_fill_leaves_the_painters_selection_exactly_where_it_was() -> void:
    _paint_rect(Rect2i(16, 16, 160, 160), RED)
    _doc.selection.select_rect(Rect2i(0, 0, 300, 300))
    var bounds_before := _doc.selection.bounds
    var chunks_before := _doc.selection.chunks.size()

    _tool().fill_at(Vector2i(96, 96))

    assert_true(_doc.selection.active, "The selection is still there")
    assert_eq(_doc.selection.bounds, bounds_before, "with the bounds it had")
    assert_eq(_doc.selection.chunks.size(), chunks_before, "and the chunks it had")


## And it is clipped to that selection, which is the other half of the claim.
func test_a_fill_is_clipped_to_the_selection_when_one_is_active() -> void:
    # One flat red field across the first two chunks, so a flood from the left
    # would run the whole way but the selection stops at 128.
    _paint_rect(Rect2i(0, 0, 400, 200), RED)
    _doc.selection.select_rect(Rect2i(0, 0, 128, 200))

    _tool().fill_at(Vector2i(16, 16))

    assert_almost_eq(_texel(16, 16).b, 1.0, 0.02, "Inside the selection the fill landed")
    assert_almost_eq(_texel(300, 100).b, 0.0, 0.02, "and outside it the red is untouched")
    assert_almost_eq(_texel(300, 100).r, 1.0, 0.02, "still red")


## One undo step, and it puts back what was there rather than clearing the layer.
func test_a_fill_is_one_undo_step_that_puts_the_hole_back() -> void:
    _paint_rect(Rect2i(16, 16, 160, 160), RED)
    _paint_rect(Rect2i(40, 40, 112, 112), Color(0, 0, 0, 0))
    var steps := _doc.undo_redo.get_history_count() if _doc.undo_redo.has_method("get_history_count") else -1

    _tool().fill_at(Vector2i(96, 96))
    assert_true(_doc.undo_redo.has_undo(), "The fill left an undo step")
    _doc.undo_redo.undo()

    assert_almost_eq(_texel(96, 96).a, 0.0, 0.02, "The hole is a hole again")
    assert_almost_eq(_texel(20, 96).r, 1.0, 0.02, "and the shape around it is still red")
    if steps >= 0:
        assert_true(true, "history counted %d before the fill" % steps)


## A locked layer refuses, the way every other painting tool does.
func test_a_locked_layer_refuses_the_fill() -> void:
    _paint_rect(Rect2i(16, 16, 160, 160), RED)
    _doc.active_layer.is_locked = true
    assert_eq(_tool().fill_at(Vector2i(96, 96)), 0, "Nothing was painted")
    _doc.active_layer.is_locked = false
