## Scale and rotate on the transform tool, as pixels.
##
## The first pass in Sara that reads between texels, so the claims are about
## what comes out: a doubled picture covers four times the area, a quarter turn
## puts a tall box on its side, values above 1.0 survive the filter, and the
## whole thing is still one undo step.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const RED := Color(1.0, 0.0, 0.0, 1.0)
## Well outside 0 to 1 in every channel, which is what hard rule 5 (colour precision) is about.
const BRIGHT := Color(3.5, 2.25, -0.5, 1.0)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _pass: SaTransform = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(1024, 1024))
    _doc = _easel.document
    _pass = SaTransform.new(_doc)


func after_each() -> void:
    _pass = null
    _easel.free()
    _easel = null
    _doc = null


func _texel(texture: SaTexture, x: int, y: int) -> Color:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, y * texture.size.x + x)


func _layer_texel(layer: SaLayer, x: int, y: int) -> Color:
    var grid := Vector2i(floori(float(x) / SaChunk.SIZE), floori(float(y) / SaChunk.SIZE))
    var texture := layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    return _texel(texture, x - grid.x * SaChunk.SIZE, y - grid.y * SaChunk.SIZE)


## A square of paint inside one chunk, with the box around exactly that square.
func _lift_a_square(colour: Color = RED) -> void:
    _doc.active_layer.fill(colour)
    _doc.selection.select_rect(Rect2i(256, 256, 256, 256))
    _pass.lift(_doc.active_layer, Rect2i(256, 256, 256, 256))


func test_the_box_grows_with_the_scale_and_keeps_its_centre() -> void:
    _lift_a_square()

    _pass.preview_affine(Vector2i.ZERO, Vector2(2.0, 2.0), 0.0)

    var grown := _pass.landed_bounds()
    assert_eq(grown.get_center(), Vector2i(384, 384), "A scale about the centre leaves the centre where it was")
    assert_almost_eq(float(grown.size.x), 514.0, 1.5, "and a doubled 256 square is 512 wide, plus the filter's skirt")


func test_a_doubled_picture_fills_where_it_was_not_before() -> void:
    _lift_a_square()

    _pass.preview_affine(Vector2i.ZERO, Vector2(2.0, 2.0), 0.0)
    _pass.tick()

    assert_almost_eq(_layer_texel(_doc.stroke_layer, 384, 384).a, 1.0, 1e-3, "The middle is opaque")
    assert_almost_eq(_layer_texel(_doc.stroke_layer, 200, 384).a, 1.0, 1e-3, "and so is a point the square did not reach")
    assert_almost_eq(_layer_texel(_doc.stroke_layer, 200, 384).r, 1.0, 1e-3, "in the colour it was painted")
    assert_almost_eq(_layer_texel(_doc.stroke_layer, 100, 384).a, 0.0, 1e-3, "Outside the doubled square there is nothing")


func test_a_quarter_turn_puts_a_tall_box_on_its_side() -> void:
    _doc.active_layer.fill(RED)
    _doc.selection.select_rect(Rect2i(256, 256, 128, 384))
    _pass.lift(_doc.active_layer, Rect2i(256, 256, 128, 384))

    _pass.preview_affine(Vector2i.ZERO, Vector2.ONE, PI * 0.5)

    var turned := _pass.landed_bounds()
    assert_almost_eq(float(turned.size.x), 386.0, 1.5, "The box is as wide as it was tall")
    assert_almost_eq(float(turned.size.y), 130.0, 1.5, "and as tall as it was wide")
    assert_eq(turned.get_center(), Vector2i(320, 448), "about the same centre")
    _pass.tick()
    assert_almost_eq(_layer_texel(_doc.stroke_layer, 500, 448).a, 1.0, 1e-3, "and the paint reaches where only the turn puts it")


func test_the_quad_turns_while_the_box_only_grows() -> void:
    _lift_a_square()

    _pass.preview_affine(Vector2i.ZERO, Vector2.ONE, PI * 0.25)

    var quad := _pass.landed_quad()
    assert_eq(quad.size(), 4, "Four corners")
    var centre := Vector2(384, 384)
    for corner: Vector2 in quad:
        assert_almost_eq(corner.distance_to(centre), 181.02, 0.5, "each the same distance from the centre a turn cannot change")


func test_out_of_range_values_survive_the_filter() -> void:
    _lift_a_square(BRIGHT)

    _pass.preview_affine(Vector2i.ZERO, Vector2(2.0, 2.0), 0.0)
    _pass.tick()

    var read := _layer_texel(_doc.stroke_layer, 384, 384)
    assert_almost_eq(read.r, BRIGHT.r, 1e-2, "A channel above 1.0 comes through the resample unclamped")
    assert_almost_eq(read.g, BRIGHT.g, 1e-2, "and so does the second one")
    assert_almost_eq(read.b, BRIGHT.b, 1e-2, "and a negative one is still negative")


func test_a_scaled_commit_is_one_step_and_undoes_whole() -> void:
    _lift_a_square()
    var steps := _doc.history.step_count()

    _pass.preview_affine(Vector2i.ZERO, Vector2(2.0, 2.0), 0.0)
    assert_true(_pass.commit(), "A scale with no move is still a transform")

    assert_eq(_doc.history.step_count(), steps + 1, "as one step")
    assert_almost_eq(_layer_texel(_doc.active_layer, 200, 384).a, 1.0, 1e-3, "The doubled picture is in the layer")

    _doc.undo()
    assert_almost_eq(_layer_texel(_doc.active_layer, 384, 384).a, 1.0, 1e-3, "and one undo puts the square back")
    assert_almost_eq(_layer_texel(_doc.active_layer, 200, 384).a, 1.0, 1e-3, "over paint that was always there")
