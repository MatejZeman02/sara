## A layer with no paint shows the checker too.
##
## The finding: "a painter cannot tell a filled layer from an empty one without
## hiding the others", and Layer 1, which holds nothing, looked the same as two
## layers painted dark. An empty layer has no texture, by design, so the kernel
## has nothing to draw the checker into, and the row draws the same squares
## itself. What they are is geometry, so it is asserted here without a GPU. That
## they match the kernel's is the suite beside this one and the scenario.
extends "res://tests/test_framework.gd"

## A default document's shape, which is a picture 32 texels by 18 and squares
## four texels across.
const CANVAS := Vector2i(1920, 1080)

## The slot a 32 by 18 picture is fitted into in a box 32 by 22 units.
const RIM := Rect2(Vector2(0.0, 2.0), Vector2(32.0, 18.0))


func _thumb(is_group: bool = false) -> SaLayerThumbnail:
    var document := SaDocument.new()
    document.canvas_size = CANVAS
    var layer := SaLayer.new()
    layer.is_group = is_group
    document.add_child(layer)
    document.active_layer = layer
    var thumb := SaLayerThumbnail.new()
    thumb.size = Vector2(SaUI.pxf(SaLayerThumbnail.BOX.x), SaUI.pxf(SaLayerThumbnail.BOX.y))
    thumb.bind_layer(layer, document)
    thumb.set_meta("document", document)
    return thumb


func _drop(thumb: SaLayerThumbnail) -> void:
    var document: SaDocument = thumb.get_meta("document")
    thumb.free()
    document.free()


func test_an_empty_layers_row_says_it_draws_the_checker() -> void:
    var thumb := _thumb()
    var report := thumb.rim_report()
    assert_true(bool(report["empty"]), "the layer holds nothing, so it has no picture")
    assert_true(bool(report["checker"]), "and the row draws the checker in the slot instead")
    _drop(thumb)


## A group has a folder mark and no chunks, and the checker would sit under the
## mark and make a folder look like a transparent layer.
func test_a_group_does_not_draw_a_checker() -> void:
    var thumb := _thumb(true)
    thumb.refresh()
    assert_false(bool(thumb.rim_report()["checker"]), "a group's row carries its folder and no checker")
    _drop(thumb)


func test_the_squares_are_the_kernels_four_texels_across_from_the_corner() -> void:
    var squares := SaLayerThumbnail.checker_squares(RIM, Vector2i(32, 18))
    assert_eq(squares.size(), 20, "light squares on an eight by five grid, the odd ones left to the ground")
    assert_eq(squares[0], Rect2(RIM.position, Vector2(4.0, 4.0)), "the first one sits in the slot's corner, four texels across")
    var next_row: Rect2 = squares[4]
    assert_eq(next_row.position, RIM.position + Vector2(4.0, 4.0), "and the next row starts one square across, the two alternate")
    for square: Rect2 in squares:
        assert_true(RIM.encloses(square), "no square leaves the slot, %s" % square)


## The last row of an 18 texel picture is two texels of a square four across, and
## it stops at the slot's edge rather than spilling into the row below.
func test_the_last_row_is_clipped_to_the_slot() -> void:
    var squares := SaLayerThumbnail.checker_squares(RIM, Vector2i(32, 18))
    var lowest := 0.0
    for square: Rect2 in squares:
        lowest = maxf(lowest, square.end.y)
    assert_almost_eq(lowest, RIM.end.y, 0.0001, "the bottom squares end at the slot's bottom")


## A slot scaled up for a bigger interface keeps the squares the same fraction
## of the picture, which is what the texel size in the maths is for.
func test_the_squares_scale_with_the_slot() -> void:
    var doubled := Rect2(RIM.position * 2.0, RIM.size * 2.0)
    var squares := SaLayerThumbnail.checker_squares(doubled, Vector2i(32, 18))
    assert_eq(squares[0].size, Vector2(8.0, 8.0), "at twice the size a square is twice as wide")
    assert_eq(squares.size(), 20, "and there are as many of them")


func test_no_slot_or_no_picture_has_no_squares() -> void:
    assert_true(SaLayerThumbnail.checker_squares(Rect2(), Vector2i(32, 18)).is_empty(), "a slot with no size has none")
    assert_true(SaLayerThumbnail.checker_squares(RIM, Vector2i.ZERO).is_empty(), "nor does a picture with no texels")
