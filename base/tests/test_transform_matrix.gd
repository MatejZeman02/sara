## One matrix behind all four gestures.
##
## The claims are about composition rather than about pixels: a shear is a
## matrix like the other three, the four compose in either order without a
## branch, and a transform followed by its own inverse gives the canvas back
## within the filter's tolerance, which is the cheapest proof that the map is
## composed the right way round and inverted the right way round.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const RED := Color(1.0, 0.0, 0.0, 1.0)

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


## A quarter of the canvas painted, with the box around exactly that.
func _lift_a_square(box: Rect2i = Rect2i(256, 256, 256, 256)) -> void:
    _doc.active_layer.fill(RED)
    _doc.selection.select_rect(box)
    _pass.lift(_doc.active_layer, box)


func test_a_shear_leans_the_quad_and_keeps_its_area() -> void:
    _lift_a_square()
    var lean := Transform2D(Vector2(1.0, 0.0), Vector2(-0.5, 1.0), Vector2(0.5 * 384.0, 0.0))

    _pass.preview_matrix(lean)

    var quad := _pass.landed_quad()
    assert_eq(quad.size(), 4, "Four corners")
    assert_almost_eq(quad[0].distance_to(quad[1]), 256.0, 1e-3, "The top edge is the length it was")
    assert_almost_eq(quad[1].distance_to(quad[2]), 286.22, 0.1, "and the side is longer, which is what leaning does")
    var across: Vector2 = quad[1] - quad[0]
    var down: Vector2 = quad[3] - quad[0]
    assert_almost_eq(absf(across.cross(down)), 65536.0, 1.0, "A shear keeps the area, which is the determinant of one")


func test_the_matrix_carries_all_four_and_the_builder_agrees_with_it() -> void:
    _lift_a_square()

    _pass.preview_affine(Vector2i(40, -20), Vector2(1.5, 0.5), PI * 0.25)
    var built := _pass.matrix

    var centre := Vector2(384, 384)
    var basis := Transform2D(PI * 0.25, Vector2.ZERO).scaled_local(Vector2(1.5, 0.5))
    var by_hand := Transform2D(basis.x, basis.y, centre + Vector2(40, -20) - basis.basis_xform(centre))
    assert_true(built.is_equal_approx(by_hand), "The offset, the scale and the angle are one map and nothing else")
    assert_almost_eq(built.get_rotation(), PI * 0.25, 1e-4, "which still answers the angle it was built from")
    assert_almost_eq(built.get_scale().x, 1.5, 1e-4, "and the scale")
    assert_almost_eq((built * centre - centre).x, 40.0, 1e-3, "and moves the centre by the offset it was given")


func test_a_transform_and_its_inverse_give_the_canvas_back() -> void:
    var box := Rect2i(256, 256, 256, 256)
    _doc.active_layer.fill(Color(0.0, 0.0, 0.0, 0.0))
    _doc.active_layer.get_or_create_chunk(Vector2i(1, 1)).clear(RED)
    _doc.selection.select_rect(box)

    var lean := Transform2D(Vector2(1.2, 0.15), Vector2(-0.3, 0.9), Vector2(37.0, -14.0))
    _pass.lift(_doc.active_layer, box)
    _pass.preview_matrix(lean)
    # Read before the commit: committing forgets the gesture, which is what
    # makes a second one start from the layer rather than from the first.
    var moved := _pass.landed_bounds()
    assert_true(_pass.commit(), "The first transform lands")

    # The mask has to be out of the way for the second lift: the selection is
    # still the rectangle the first one used, and the picture is not in it any
    # more, so a masked lift would take a corner of the round trip and nothing
    # else.
    _doc.selection.deselect()
    assert_true(_pass.lift(_doc.active_layer, moved), "The transformed picture lifts again")
    # The box the second lift takes is not the box the first one used, so the
    # inverse has to be expressed about the same origin the first one was.
    _pass.preview_matrix(lean.affine_inverse())
    assert_true(_pass.commit(), "and its inverse lands on top of it")

    assert_almost_eq(_layer_texel(_doc.active_layer, 384, 384).a, 1.0, 0.02, "The middle of the square is opaque again")
    assert_almost_eq(_layer_texel(_doc.active_layer, 384, 384).r, 1.0, 0.02, "in the colour it was")
    assert_almost_eq(_layer_texel(_doc.active_layer, 300, 300).a, 1.0, 0.05, "and so is a point well inside it")
    assert_almost_eq(_layer_texel(_doc.active_layer, 700, 700).a, 0.0, 0.02, "with nothing left where the round trip passed")
