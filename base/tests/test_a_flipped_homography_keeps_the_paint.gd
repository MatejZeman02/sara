## A homography that turns the picture over keeps the paint.
##
## `SaHomography.inverse_of` is the adjugate, and the adjugate is the inverse
## times the determinant. A map that mirrors the picture has a negative
## determinant, so the third row `kernel_rows` handed the resample kernel came
## out negative over the whole picture, the kernel took every texel for "behind
## the horizon", and a flipped Mirrored or Perspective drag previewed nothing
## and baked nothing.
##
## Two claims. The rows have a positive `w` over the lifted box for every flip,
## which is the arithmetic, and a resample through them lays the picture down
## as an exact mirror, which is the pixels. The picture is a ramp in red across
## and in green down, so a turned-over picture cannot pass for an untouched one.
##
## **A third case the first fix got wrong.** A corner dragged through its
## opposite is not a flip, it puts the map's horizon across the box. Making the
## inverse positive by the determinant's sign alone drew the corner's own sliver
## and blanked the rest, where the map as it was drew the other half, so
## `corners_to_quad` now picks the sign that keeps the box's centre in front and
## the cases below hold the centre drawn wherever the box sits.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

## Inside one chunk, so the arithmetic below stays readable.
const BOX := Rect2i(64, 64, 128, 128)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _pass: SaTransform = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document
    _pass = SaTransform.new(_doc)


func after_each() -> void:
    _pass = null
    _easel.free()
    _easel = null
    _doc = null


## The picture at document position *at*, a ramp in red across the box and in
## green down it, opaque.
func _picture_at(at: Vector2i) -> Color:
    var across := float(at.x - BOX.position.x) / float(BOX.size.x - 1)
    var down := float(at.y - BOX.position.y) / float(BOX.size.y - 1)
    return Color(across, down, 0.5, 1.0)


## Paints the ramp over the active layer's first chunk, selects BOX and lifts it.
func _lift_the_ramp() -> void:
    var layer := _doc.active_layer
    var chunk := layer.get_or_create_chunk(Vector2i.ZERO)
    var texture := chunk.albedo()
    var format := Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF
    var image := Image.create_empty(SaChunk.SIZE, SaChunk.SIZE, false, format)
    for y in range(BOX.position.y, BOX.end.y):
        for x in range(BOX.position.x, BOX.end.x):
            image.set_pixel(x, y, _picture_at(Vector2i(x, y)))
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
    layer.mark_unresolved(Vector2i.ZERO)
    _doc.invalidate_chunks(layer.chunks.keys())
    _doc.selection.select_rect(BOX)
    assert_true(_pass.lift(layer, BOX), "There is a picture to lift")


func _texel(layer: SaLayer, at: Vector2i) -> Color:
    var texture := layer.get_field(Vector2i.ZERO)
    if texture == null:
        return Color.TRANSPARENT
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


## BOX's corners clockwise from the top left, in the order *order* names, so
## `[1, 0, 3, 2]` puts the top right where the top left was and so on.
func _quad(order: Array) -> PackedVector2Array:
    var corners := SaHomography.corners_of(BOX)
    var quad := PackedVector2Array()
    for index: int in order:
        quad.append(corners[index])
    return quad


## The kernel's third row at *at*.
func _w(rows: Array, at: Vector2) -> float:
    var third: Vector3 = rows[3]
    return third.x * at.x + third.y * at.y + third.z


## The two flips and the half turn, as the corners' new order. The half turn
## has a positive determinant and always worked, so it is here to say the fix
## leaves it alone.
func _flips() -> Dictionary:
    return {
        "A flip across": [1, 0, 3, 2],
        "A flip down": [3, 2, 1, 0],
        "A half turn": [2, 3, 0, 1],
    }


## Positions inside the box, the four corners' texels and the middle.
func _probes() -> Array:
    return [Vector2(64.5, 64.5), Vector2(191.5, 64.5), Vector2(128.0, 128.0), Vector2(64.5, 191.5), Vector2(191.5, 191.5)]


func test_a_flipped_map_has_a_positive_third_row_over_the_box() -> void:
    var flips := _flips()
    for what: String in flips:
        var h := SaHomography.corners_to_quad(BOX, _quad(flips[what]))
        assert_eq(h.size(), 9, "%s has a homography" % what)
        var rows := SaHomography.kernel_rows(h, Transform2D.IDENTITY, Vector2(BOX.position))
        # The kernel reads the third row at the position a texel lands on, so
        # the positions to ask are the box's own, which every flip here maps
        # onto itself.
        for at: Vector2 in _probes():
            assert_true(_w(rows, at) > 0.0, "%s keeps w positive at %s, it is %f" % [what, at, _w(rows, at)])


func test_the_inverse_of_a_flipped_map_takes_a_point_home() -> void:
    var flips := _flips()
    for what: String in flips:
        var h := SaHomography.corners_to_quad(BOX, _quad(flips[what]))
        var back := SaHomography.inverse_of(h)
        for at: Vector2 in [Vector2(70.0, 80.0), Vector2(180.0, 100.0), Vector2(128.0, 128.0)]:
            var there := SaHomography.through(h, at)
            assert_almost_eq((SaHomography.through(back, there) - at).length(), 0.0, 1e-2, "%s out and back from %s" % [what, at])


func test_a_flip_across_lands_as_an_exact_mirror() -> void:
    _lift_the_ramp()
    _pass.preview_homography(SaHomography.corners_to_quad(BOX, _quad([1, 0, 3, 2])))
    _pass.tick()
    var preview := _doc.stroke_layer
    for y: int in [64, 100, 127, 191]:
        for x: int in [64, 80, 127, 128, 150, 191]:
            var wanted := _picture_at(Vector2i(BOX.position.x + BOX.end.x - 1 - x, y))
            var got := _texel(preview, Vector2i(x, y))
            assert_almost_eq(got.a, 1.0, 1e-3, "The preview is opaque at (%d, %d)" % [x, y])
            assert_almost_eq(got.r, wanted.r, 1e-2, "and holds the mirrored red at (%d, %d)" % [x, y])
            assert_almost_eq(got.g, wanted.g, 1e-2, "and the green a flip across leaves alone at (%d, %d)" % [x, y])


func test_a_flip_down_lands_as_an_exact_mirror() -> void:
    _lift_the_ramp()
    _pass.preview_homography(SaHomography.corners_to_quad(BOX, _quad([3, 2, 1, 0])))
    _pass.tick()
    var preview := _doc.stroke_layer
    for y: int in [64, 100, 127, 191]:
        for x: int in [64, 80, 127, 128, 150, 191]:
            var wanted := _picture_at(Vector2i(x, BOX.position.y + BOX.end.y - 1 - y))
            var got := _texel(preview, Vector2i(x, y))
            assert_almost_eq(got.a, 1.0, 1e-3, "The preview is opaque at (%d, %d)" % [x, y])
            assert_almost_eq(got.r, wanted.r, 1e-2, "and holds the red a flip down leaves where it was at (%d, %d)" % [x, y])
            assert_almost_eq(got.g, wanted.g, 1e-2, "and the mirrored green at (%d, %d)" % [x, y])


## Enter bakes the mirror into the layer and one undo puts the paint back.
func test_a_flipped_commit_bakes_the_mirror_and_undoes_whole() -> void:
    _lift_the_ramp()
    var steps := _doc.history.step_count()
    _pass.preview_homography(SaHomography.corners_to_quad(BOX, _quad([1, 0, 3, 2])))
    assert_true(_pass.commit(), "A flip is a transform")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step")
    var layer := _doc.active_layer
    var mirrored := _texel(layer, Vector2i(80, 100))
    var wanted := _picture_at(Vector2i(BOX.position.x + BOX.end.x - 1 - 80, 100))
    assert_almost_eq(mirrored.a, 1.0, 1e-3, "The layer holds paint where the flip put it")
    assert_almost_eq(mirrored.r, wanted.r, 1e-2, "and it is the mirrored picture")

    _doc.undo()
    var home := _texel(layer, Vector2i(80, 100))
    var original := _picture_at(Vector2i(80, 100))
    assert_almost_eq(home.r, original.r, 1e-2, "One undo puts the original red back")
    assert_almost_eq(home.g, original.g, 1e-2, "and the original green")


## The corner dragged through its opposite, with the box near the origin and
## far from it, which is the position the solve's own sign depended on.
func test_a_corner_dragged_through_its_opposite_keeps_the_centre_in_front() -> void:
    for box: Rect2i in [Rect2i(64, 64, 128, 128), Rect2i(300, 300, 128, 128), Rect2i(200, 40, 96, 200)]:
        var quad := SaHomography.corners_of(box)
        quad[0] = Vector2(box.end) + Vector2(38.0, 38.0)
        var h := SaHomography.corners_to_quad(box, quad)
        assert_eq(h.size(), 9, "%s has a homography" % box)
        var centre := Vector2(box.position) + Vector2(box.size) * 0.5
        assert_true(h[6] * centre.x + h[7] * centre.y + h[8] > 0.0, "%s keeps its centre in front of the horizon" % box)
        var rows := SaHomography.kernel_rows(h, Transform2D.IDENTITY, Vector2(box.position))
        var landed := SaHomography.through(h, centre)
        assert_true(_w(rows, landed) > 0.0, "and the kernel draws where the centre lands, %s" % landed)


## The same through the pass, as pixels: the centre of the picture is drawn
## where the map sends it, and holds the colour it had.
func test_a_corner_dragged_through_its_opposite_draws_the_centre() -> void:
    _lift_the_ramp()
    var quad := SaHomography.corners_of(BOX)
    quad[0] = Vector2(BOX.end) + Vector2(38.0, 38.0)
    var h := SaHomography.corners_to_quad(BOX, quad)
    _pass.preview_homography(h)
    _pass.tick()
    var centre := Vector2(BOX.position) + Vector2(BOX.size) * 0.5
    var landed := Vector2i(SaHomography.through(h, centre).round())
    assert_true(Rect2i(0, 0, SaChunk.SIZE, SaChunk.SIZE).has_point(landed), "The centre lands inside the chunk, at %s" % landed)
    var got := _texel(_doc.stroke_layer, landed)
    var wanted := _picture_at(Vector2i(centre))
    assert_almost_eq(got.a, 1.0, 1e-3, "and the preview is opaque there")
    assert_almost_eq(got.r, wanted.r, 5e-2, "in the red the picture has at its centre")
    assert_almost_eq(got.g, wanted.g, 5e-2, "and the green")


## How much of the mask covers the document position *at*, read off the GPU.
func _covered(at: Vector2i) -> float:
    var texture := _doc.selection.texture_for(Vector2i.ZERO)
    if texture == null or not texture.rid.is_valid():
        return 0.0
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x).r


## The selection is carried through the same map as the pixels, so a flip that
## also moves the box takes the mask with it. A mask resampled through a
## negative `w` would be blank, and the marching ants would be left on nothing.
func test_a_flipped_commit_carries_the_selection() -> void:
    _lift_the_ramp()
    var shift := Vector2(100.0, 0.0)
    var quad := _quad([1, 0, 3, 2])
    for i in 4:
        quad[i] += shift
    _pass.preview_homography(SaHomography.corners_to_quad(BOX, quad))
    assert_true(_pass.commit(), "A flip that moves the box commits")
    assert_almost_eq(_covered(Vector2i(250, 128)), 1.0, 1e-2, "The mask is on the box where the flip put it")
    assert_almost_eq(_covered(Vector2i(80, 128)), 0.0, 1e-2, "and no longer on the box it came from")
