## Height moves with the transform tool.
##
## A layer's height is a lazy field that `SaChunk.create` leaves out, so a lift
## built from the schema alone took none and a move left the relief behind.
## The lift takes the height masked by the selection the way it takes the
## colour, the preview moves it by the same map and filter, and the commit
## lays it down by the mix a Merge Down uses.
## Every claim is read back texel by
## texel, because a height that went missing reads as zero, which is also what
## bare paper reads.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const RED := Color(1.0, 0.0, 0.0, 1.0)

## The thickness laid over the whole first chunk, in millimetres. Above one on
## purpose, so a clamp anywhere on the way shows as a wrong reading, and exact
## in a half float.
const THICK: float = 3.5

## A chunk and a half, the move the claim names.
const MOVE := Vector2i(384, 0)

## The selection, inside the first chunk and clear of its edges.
const BOX := Rect2i(64, 64, 128, 128)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _pass: SaTransform = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(1024, 512))
    _doc = _easel.document
    _pass = SaTransform.new(_doc)


func after_each() -> void:
    _pass = null
    _easel.free()
    _easel = null
    _doc = null


## The height of *layer* at a document position, zero where its chunk holds
## none, which is what a chunk with no height means.
func _height_at(layer: SaLayer, x: int, y: int) -> float:
    var grid := Vector2i(floori(float(x) / SaChunk.SIZE), floori(float(y) / SaChunk.SIZE))
    var texture := layer.get_field(grid, SaFieldSpec.HEIGHT)
    if texture == null:
        return 0.0
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var index := (y - grid.y * SaChunk.SIZE) * texture.size.x + (x - grid.x * SaChunk.SIZE)
    return SaFieldSpec.decode_texel(bytes, texture.format, index).r


func _alpha_at(layer: SaLayer, x: int, y: int) -> float:
    var grid := Vector2i(floori(float(x) / SaChunk.SIZE), floori(float(y) / SaChunk.SIZE))
    var texture := layer.get_field(grid)
    if texture == null:
        return 0.0
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var index := (y - grid.y * SaChunk.SIZE) * texture.size.x + (x - grid.x * SaChunk.SIZE)
    return SaFieldSpec.decode_texel(bytes, texture.format, index).a


## A red layer whose first chunk stands THICK high everywhere and whose other
## chunks hold no height at all.
func _thick_layer() -> SaLayer:
    var layer := _doc.active_layer
    layer.fill(RED)
    SaHeightOps.new(_doc).gain(layer)
    var texture := layer.get_or_create_field(Vector2i(0, 0), SaFieldSpec.HEIGHT)
    var bytes := PackedByteArray()
    bytes.resize(texture.size.x * texture.size.y * 2)
    for i in texture.size.x * texture.size.y:
        bytes.encode_half(i * 2, THICK)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, bytes)
    return layer


func test_a_move_takes_the_height_and_leaves_none_behind() -> void:
    var layer := _thick_layer()
    _doc.selection.select_rect(BOX)
    var steps := _doc.history.step_count()

    assert_true(_pass.lift(layer, BOX), "A selection over thick paint is something to lift")
    assert_almost_eq(_height_at(layer, 128, 128), 0.0, 1e-4, "The lift leaves no height in the hole")
    assert_almost_eq(_height_at(layer, 32, 32), THICK, 1e-3, "and none goes from outside the selection")
    _pass.preview(MOVE)
    _pass.tick()
    assert_almost_eq(_height_at(_doc.stroke_layer, 128 + MOVE.x, 128), THICK, 1e-3, "The preview carries the height")
    assert_true(_pass.commit(), "Enter writes the move down")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step")

    assert_almost_eq(_height_at(layer, 128 + MOVE.x, 128), THICK, 1e-3, "The height stands where the paint was dropped")
    assert_almost_eq(_height_at(layer, BOX.end.x - 1 + MOVE.x, BOX.end.y - 1), THICK, 1e-3, "to the box's last texel")
    assert_almost_eq(_height_at(layer, BOX.end.x + MOVE.x, 128), 0.0, 1e-4, "and no further")
    assert_almost_eq(_height_at(layer, 128, 128), 0.0, 1e-4, "The old place reads zero")
    assert_almost_eq(_height_at(layer, 32, 32), THICK, 1e-3, "and the rest of the first chunk keeps its height")
    assert_true(layer.chunks[Vector2i(2, 0)].has_field(SaFieldSpec.HEIGHT), "The landing chunk gained a height")
    assert_false(layer.chunks[Vector2i(3, 0)].has_field(SaFieldSpec.HEIGHT), "and a chunk the move missed gained none")

    _doc.undo()
    assert_almost_eq(_height_at(layer, 128, 128), THICK, 1e-3, "Undo puts the height back where it was")
    assert_almost_eq(_height_at(layer, 128 + MOVE.x, 128), 0.0, 1e-4, "and takes it off where it landed")
    assert_false(layer.chunks[Vector2i(2, 0)].has_field(SaFieldSpec.HEIGHT), "with the texture the landing gained")
    assert_almost_eq(_alpha_at(layer, 128 + MOVE.x, 128), 1.0, 1e-4, "and the paint that was there is still there")

    _doc.redo()
    assert_almost_eq(_height_at(layer, 128 + MOVE.x, 128), THICK, 1e-3, "Redo lays it down again")
    assert_almost_eq(_height_at(layer, 128, 128), 0.0, 1e-4, "and empties the old place")


func test_escape_puts_the_height_back() -> void:
    var layer := _thick_layer()
    _doc.selection.select_rect(BOX)
    _pass.lift(layer, BOX)
    _pass.preview(MOVE)
    _pass.tick()
    _pass.cancel()
    assert_almost_eq(_height_at(layer, 128, 128), THICK, 1e-3, "Escape fills the hole's height back in")
    assert_false(layer.chunks[Vector2i(1, 0)].has_field(SaFieldSpec.HEIGHT), "and lands nothing")


## A resample reads the height through the same filter as the colour and never
## clamps it: a piece scaled up keeps THICK in its middle, and bilinear at the
## rim goes no higher than the ridge it read.
func test_a_scaled_move_resamples_the_height_unclamped() -> void:
    var layer := _thick_layer()
    _doc.selection.select_rect(BOX)
    _pass.lift(layer, BOX)
    _pass.preview_affine(MOVE, Vector2(1.5, 1.5), 0.0)
    _pass.tick()
    assert_true(_pass.commit(), "A scaled move writes down")
    var centre := BOX.get_center() + MOVE
    assert_almost_eq(_height_at(layer, centre.x, centre.y), THICK, 1e-3, "The middle of the scaled piece is as thick")
    var rim := _height_at(layer, centre.x + 95, centre.y)
    assert_true(rim <= THICK + 1e-3, "The rim reads no higher than the ridge, %f" % rim)
    assert_almost_eq(_height_at(layer, centre.x + 110, centre.y), 0.0, 1e-4, "and past the piece there is none")


## Flat paint moved over thick paint covers its height, the rule a Merge Down
## follows: the thickness under an opaque landing
## becomes the landing's.
func test_flat_paint_moved_over_thick_paint_covers_it() -> void:
    var layer := _thick_layer()
    var flat := Rect2i(64 + SaChunk.SIZE, 64, 128, 128)
    _doc.selection.select_rect(flat)
    assert_true(_pass.lift(layer, flat), "Paint with no height lifts")
    _pass.preview(Vector2i(-SaChunk.SIZE, 0))
    _pass.tick()
    assert_true(_pass.commit(), "and lands on the first chunk")
    assert_almost_eq(_height_at(layer, 128, 128), 0.0, 1e-4, "where it covers the height it landed on")
    assert_almost_eq(_height_at(layer, 32, 32), THICK, 1e-3, "and leaves the rest standing")
