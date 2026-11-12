## Which four corners `SaHomography.folds` calls folded.
##
## A Perspective corner dragged through its opposite folds the quad, the map's
## horizon then crosses the box, and the preview and Enter kept only the half
## the box's centre is in. The drag now refuses a quad that
## folds, so this holds what folds: a bowtie and a concave quad do, and the box,
## a perspective quad and the box turned over across either axis do not,
## because a quad turned over whole is what a flip and Mirrored make.
extends "res://tests/test_framework.gd"

const BOX := Rect2i(64, 64, 128, 128)


func _box() -> PackedVector2Array:
    return SaHomography.corners_of(BOX)


## The box's corners in the order *order* names, clockwise from the top left.
func _box_in(order: Array) -> PackedVector2Array:
    var corners := _box()
    var out := PackedVector2Array()
    for index: int in order:
        out.append(corners[index])
    return out


func test_the_box_does_not_fold() -> void:
    assert_false(SaHomography.folds(_box()), "The box is convex")


func test_a_perspective_quad_does_not_fold() -> void:
    var quad := PackedVector2Array([Vector2(90, 70), Vector2(170, 50), Vector2(200, 210), Vector2(60, 180)])
    assert_false(SaHomography.folds(quad), "A quad pulled into perspective is still convex")


func test_the_box_turned_over_does_not_fold() -> void:
    assert_false(SaHomography.folds(_box_in([1, 0, 3, 2])), "The box turned over left for right is a quad")
    assert_false(SaHomography.folds(_box_in([3, 2, 1, 0])), "The box turned over top for bottom is a quad")


func test_a_bowtie_folds() -> void:
    # The top two corners traded, so the top and bottom edges cross.
    assert_true(SaHomography.folds(_box_in([1, 0, 2, 3])), "A bowtie folds")


func test_a_concave_quad_folds() -> void:
    # The top left corner dragged through the bottom right, part way: the
    # bottom right is then a reflex corner.
    var quad := _box()
    quad[0] = Vector2(170, 170)
    assert_true(SaHomography.folds(quad), "An arrowhead folds")
    quad[0] = Vector2(260, 260)
    assert_true(SaHomography.folds(quad), "The corner past the bottom right folds")


func test_corners_in_a_line_fold() -> void:
    var quad := _box()
    quad[0] = (quad[1] + quad[3]) * 0.5
    assert_true(SaHomography.folds(quad), "A corner on the diagonal through its neighbours folds")
