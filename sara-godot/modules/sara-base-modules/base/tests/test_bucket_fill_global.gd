## The bucket fill's Contiguous switch, off, fills every texel of the layer
## within the tolerance of the clicked one, joined to it or not, which is
## Krita's reading. Off must not do what on does, so the two take different
## paths and not one `SaWand.flood` into a selection `_flood` had just emptied.
##
## Three red squares: two in the first chunk with transparent ground between
## them, and one in the far chunk, so the global reading is asserted inside a
## chunk and across chunks the region never joins.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const StateBucketFillScript = preload("res://modules/sara-base-modules/base/tools/state_bucket_fill.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const RED := Color(1.0, 0.0, 0.0, 1.0)
const BLUE := Color(0.0, 0.0, 1.0, 1.0)
const GREEN := Color(0.0, 1.0, 0.0, 1.0)

var _surface: SaSurface = null
var _doc: SaDocument = null


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(768, 768))
    _doc = _surface.get_document()
    _paint_rect(Rect2i(16, 16, 40, 40), RED)
    _paint_rect(Rect2i(120, 16, 40, 40), RED)
    _paint_rect(Rect2i(600, 600, 40, 40), RED)
    # The fixture's layer holds every chunk of the grid, and a painted layer
    # holds only the chunks a stroke reached, so the empty ones go. A chunk the
    # layer does not hold reads transparent, which is what they held.
    for grid_pos: Vector2i in _doc.active_layer.chunks.keys():
        if grid_pos != Vector2i(0, 0) and grid_pos != Vector2i(2, 2):
            _doc.active_layer.chunks.erase(grid_pos)


func after_each() -> void:
    _doc.free()
    _surface.easel.free()
    _surface = null
    _doc = null


func _tool(colour: Color, contiguous: bool) -> Object:
    var fill := StateBucketFillScript.new()
    fill.surface = _surface
    SaColors.foreground = colour
    fill.antialias = false
    fill.contiguous = contiguous
    return fill


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
    var side := texture.size.x
    @warning_ignore("integer_division")
    var local := Vector2i(x % SaChunk.SIZE, y % SaChunk.SIZE) * side / SaChunk.SIZE
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var at := (local.y * side + local.x) * 16
    return Color(bytes.decode_float(at), bytes.decode_float(at + 4), bytes.decode_float(at + 8), bytes.decode_float(at + 12))


## The whole claim in one test: on fills the clicked square only,
## off fills every red square and leaves the gap between them untouched.
func test_contiguous_on_fills_one_square_and_off_fills_every_match() -> void:
    _tool(BLUE, true).fill_at(Vector2i(30, 30))
    assert_almost_eq(_texel(30, 30).b, 1.0, 0.02, "On: the clicked square is blue")
    assert_almost_eq(_texel(140, 30).r, 1.0, 0.02, "and the square beside it is still red")
    assert_almost_eq(_texel(620, 620).r, 1.0, 0.02, "and so is the one in the far chunk")

    _tool(GREEN, false).fill_at(Vector2i(140, 30))
    assert_almost_eq(_texel(140, 30).g, 1.0, 0.02, "Off: the clicked square is green")
    assert_almost_eq(_texel(620, 620).g, 1.0, 0.02, "and so is the far one, which no region joins")
    assert_almost_eq(_texel(620, 620).r, 0.0, 0.02, "with no red left in it")
    assert_almost_eq(_texel(30, 30).b, 1.0, 0.02, "and the blue square, not a match, is still blue")
    assert_almost_eq(_texel(90, 30).a, 0.0, 0.02, "and the gap between the squares is untouched")
    assert_almost_eq(_texel(300, 300).a, 0.0, 0.02, "and so is the ground between the chunks")


## Off from the transparent ground fills every transparent texel, the chunks the
## layer never held included, and leaves the squares alone. The chunks the layer
## does not hold are read through one probe, so this is the clause that says the
## probe stands for all of them.
func test_contiguous_off_from_empty_ground_reaches_the_chunks_the_layer_never_held() -> void:
    var held := _doc.active_layer.chunks.size()
    assert_eq(held, 2, "The layer holds two of nine chunks before the fill")

    var touched: int = _tool(BLUE, false).fill_at(Vector2i(90, 30))
    assert_eq(touched, 9, "The fill reached every chunk of the canvas")
    assert_almost_eq(_texel(90, 30).b, 1.0, 0.02, "The clicked ground is blue")
    assert_almost_eq(_texel(400, 100).b, 1.0, 0.02, "and so is ground in a chunk the layer never held")
    assert_almost_eq(_texel(30, 30).r, 1.0, 0.02, "and the squares are still red")
    assert_almost_eq(_texel(620, 620).r, 1.0, 0.02, "all of them")


## Off from a colour that is only in held chunks allocates nothing new: a chunk
## the layer does not hold reads transparent, which is no match for red.
func test_contiguous_off_allocates_no_chunk_that_holds_no_match() -> void:
    var held := _doc.active_layer.chunks.size()
    var touched: int = _tool(BLUE, false).fill_at(Vector2i(30, 30))
    assert_eq(touched, 2, "The fill reached the two chunks that hold red")
    assert_eq(_doc.active_layer.chunks.size(), held, "and the layer still holds %d chunks" % held)
