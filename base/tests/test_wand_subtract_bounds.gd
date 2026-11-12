## A wand subtract leaves a box round what is left, not round where the
## selection reached before.
##
## Every other writer of `SaSelection.bounds` is bookkeeping: a shape knows the
## rectangle it drew and merges or cuts it. A subtract cannot, because `combine`
## writes `before AND NOT after` pixel by pixel and what survives is a shape
## inside the chunk rectangles rather than the rectangles. So the pixels are
## reduced on the GPU by the `bounds` kernel and four ints come back, which is
## the same shape of read the wand already makes once per flood sweep.
##
## `measure_bounds` is asserted directly as well as through the wand, because a
## box that is right for one path and wrong for the other is the failure this is
## written against.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

var _easel: SaEasel = null
var _doc: SaDocument = null


## Two by two chunks at 256, so a selection can span chunks and lose one.
func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null


func test_a_measured_box_is_the_rectangle_that_was_drawn() -> void:
    _doc.selection.select_rect(Rect2i(40, 60, 100, 80))

    assert_eq(_doc.selection.measure_bounds(), Rect2i(40, 60, 100, 80), "The reduction finds the rectangle's own corners")
    assert_eq(_doc.selection.bounds, _doc.selection.measure_bounds(), "and agrees with what the writer wrote down")


func test_a_measured_box_spans_the_chunks_a_rectangle_crosses() -> void:
    _doc.selection.select_rect(Rect2i(200, 200, 120, 120))

    assert_eq(_doc.selection.measure_bounds(), Rect2i(200, 200, 120, 120), "Four chunks, one box, and it is the rectangle")


func test_an_empty_selection_measures_the_empty_box() -> void:
    assert_eq(_doc.selection.measure_bounds(), Rect2i(), "Nothing selected is nothing to measure")


## The defect, through the shape path rather than the wand, because the kernel is
## the same one either way and a shape subtract is what a test can aim exactly.
func test_a_strip_off_the_top_lifts_the_measured_top() -> void:
    _doc.selection.select_rect(Rect2i(40, 60, 100, 80))

    _doc.selection.select_rect(Rect2i(0, 0, 512, 100), SaSelection.Mode.SUBTRACT)

    assert_eq(_doc.selection.measure_bounds(), Rect2i(40, 100, 100, 40), "The top edge moved to where the coverage starts")


## The case the filing is about and the one bookkeeping cannot answer: a subtract
## whose own rectangle covers the whole selection but whose mask does not.
func test_a_subtract_that_leaves_a_ring_keeps_the_outer_box() -> void:
    _doc.selection.select_rect(Rect2i(100, 100, 200, 200))

    _doc.selection.select_rect(Rect2i(150, 150, 100, 100), SaSelection.Mode.SUBTRACT)

    assert_eq(
        _doc.selection.measure_bounds(),
        Rect2i(100, 100, 200, 200),
        "A hole in the middle takes nothing off any edge, so the box does not move"
    )


func test_a_subtract_that_takes_everything_leaves_the_empty_box() -> void:
    _doc.selection.select_rect(Rect2i(100, 100, 200, 200))

    _doc.selection.select_rect(Rect2i(0, 0, 512, 512), SaSelection.Mode.SUBTRACT)

    assert_eq(_doc.selection.measure_bounds(), Rect2i(), "Nothing covered is the empty box")


## Fills *rect* of the active layer, then drops the selection, so a flood has a
## region to find on a transparent layer. The same shape `test_wand.gd` uses.
func _paint_rect(rect: Rect2i, color: Color) -> void:
    _doc.selection.select_rect(rect)
    _doc.fill_layer(color, _doc.active_layer)
    _doc.selection.deselect()


## The wand's own path, which is the one the defect was filed against.
##
## A band is painted across the top of a selected square and floods away, so the
## subtract takes a strip off one edge and the box has to follow it down. The
## chunk rectangles cannot say that: the band is 60 pixels of a 256 chunk.
func test_the_wand_subtract_measures_rather_than_leaving_the_box() -> void:
    _paint_rect(Rect2i(100, 100, 200, 60), Color(0.2, 0.4, 0.9, 1.0))
    _doc.selection.select_rect(Rect2i(100, 100, 200, 200))
    var before := _doc.selection.bounds

    var wand := SaWand.new()
    var reached := wand.flood(_doc, Vector2i(150, 120), 0.05, SaSelection.Mode.SUBTRACT, null, _doc.active_layer)

    assert_true(reached > 0, "The flood found the band")
    assert_eq(before, Rect2i(100, 100, 200, 200), "The selection started at the square")
    assert_eq(
        _doc.selection.bounds,
        Rect2i(100, 160, 200, 140),
        "and the box came down to the first row the band left, not to a chunk edge"
    )
