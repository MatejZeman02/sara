## The dim the crop tool asks the selection overlay for, as geometry.
##
## What a person sees is in `scenarios/crop-dims-outside-the-rectangle.json`, because a fill is an
## appearance and a screenshot is the only honest proof of one. What is here is
## the part a screenshot reads badly: that the four quads cover everything
## outside the rectangle exactly once, so no seam is left undimmed and no
## overlap is drawn twice as dark.
extends "res://tests/test_framework.gd"


func _area(quads: Array[Rect2]) -> float:
    var total := 0.0
    for quad: Rect2 in quads:
        total += quad.size.x * quad.size.y
    return total


func test_the_quads_cover_the_outside_and_nothing_else() -> void:
    var outer := Rect2(0, 0, 100, 100)
    var inner := Rect2(20, 30, 40, 50)
    var quads := SaSelectionOverlay.dim_quads(outer, inner)
    assert_eq(quads.size(), 4, "A rectangle clear of every edge leaves four quads")
    assert_almost_eq(_area(quads), 100.0 * 100.0 - 40.0 * 50.0, 1e-3, "which cover the outside exactly")
    for quad: Rect2 in quads:
        assert_false(quad.intersects(inner), "and none of them reaches inside the rectangle")


## Twice as dark is how an overlap shows, so the areas are checked to add up
## rather than merely to cover: two quads that overlapped would sum to more.
func test_no_two_quads_overlap() -> void:
    var quads := SaSelectionOverlay.dim_quads(Rect2(-10, -10, 200, 120), Rect2(15, 25, 60, 40))
    for i in quads.size():
        for j in range(i + 1, quads.size()):
            assert_false(quads[i].intersects(quads[j]), "Quad %d and quad %d are disjoint" % [i, j])


## A rectangle that reaches an edge, which is what dragging the crop out to the
## side does, must drop that quad rather than emit an inside-out one.
func test_a_rectangle_on_an_edge_drops_that_quad() -> void:
    var outer := Rect2(0, 0, 100, 100)
    assert_eq(SaSelectionOverlay.dim_quads(outer, Rect2(0, 0, 100, 40)).size(), 1, "A full-width band leaves the strip below")
    assert_eq(SaSelectionOverlay.dim_quads(outer, Rect2(0, 0, 40, 100)).size(), 1, "and a full-height one the strip beside")
    assert_eq(SaSelectionOverlay.dim_quads(outer, outer).size(), 0, "A rectangle over the whole box dims nothing")


## The rectangle can be dragged past the canvas, and the reach is what keeps the
## quads sane there: they still surround it, they just fall off the screen.
func test_a_rectangle_outside_the_box_still_surrounds_it() -> void:
    var quads := SaSelectionOverlay.dim_quads(Rect2(0, 0, 100, 100), Rect2(-50, -50, 20, 20))
    for quad: Rect2 in quads:
        assert_false(quad.intersects(Rect2(-50, -50, 20, 20)), "No quad covers the rectangle itself")
    assert_true(_area(quads) > 0.0, "and something is still dimmed")
