## `SaSelection.bounds` is the union of a coverage box per chunk, so it can
## come down as well as go up.
##
## `test_selection_drive.gd` holds two cases, driven through a
## document. This holds the maths under them, which is one static function and
## one rule about who claims what, and the cases a scenario cannot reach: a
## chunk that empties, a canvas whose last row is shorter than the chunks in it,
## and a shape a subtract must not shrink by.
extends "res://tests/test_framework.gd"


func _selection() -> SaSelection:
    return SaSelection.new()


## The three cases a rectangle minus a rectangle is a rectangle in, and the one
## it is not. Everything here is a claim about `without` alone, which is why it
## is static: a box the caller has to build a document to ask about is a box
## nobody checks the corners of.
func test_a_cut_that_misses_leaves_the_box_alone() -> void:
    var have := Rect2i(100, 100, 200, 200)
    assert_eq(SaSelection.without(have, Rect2i(400, 400, 50, 50)), have, "A cut somewhere else changes nothing")
    assert_eq(SaSelection.without(have, Rect2i(100, 100, 0, 0)), have, "and an empty cut is somewhere else")


func test_a_cut_that_swallows_the_box_empties_it() -> void:
    var have := Rect2i(100, 100, 200, 200)
    assert_eq(SaSelection.without(have, Rect2i(0, 0, 500, 500)), Rect2i(), "A cut over the whole box leaves nothing")
    assert_eq(SaSelection.without(have, have), Rect2i(), "and so does the box itself")


func test_a_strip_off_an_edge_moves_that_edge() -> void:
    var have := Rect2i(100, 100, 200, 200)
    assert_eq(SaSelection.without(have, Rect2i(0, 0, 500, 150)), Rect2i(100, 150, 200, 150), "A strip off the top lifts the top")
    assert_eq(
        SaSelection.without(have, Rect2i(0, 250, 500, 500)),
        Rect2i(100, 100, 200, 150),
        "a strip off the bottom lowers the bottom"
    )
    assert_eq(
        SaSelection.without(have, Rect2i(0, 0, 150, 500)), Rect2i(150, 100, 150, 200), "and a strip off the left moves it in"
    )


## The honest half. A cut through the middle leaves two pieces, and no rectangle
## holds both more tightly than the one that was there, so the answer is the box
## unchanged rather than a guess at which piece matters.
func test_a_cut_through_the_middle_shrinks_nothing() -> void:
    var have := Rect2i(100, 100, 200, 200)
    assert_eq(SaSelection.without(have, Rect2i(0, 150, 500, 50)), have, "A band across the middle is not a strip")
    assert_eq(SaSelection.without(have, Rect2i(150, 150, 50, 50)), have, "and neither is a hole in it")


## A subtract that empties a chunk's coverage takes the chunk with it, because a
## chunk of zeros is what "not selected here" already means everywhere else:
## `texture_for` answers null and a dispatcher skips it.
func test_a_fully_subtracted_chunk_stops_existing() -> void:
    var selection := _selection()
    selection.select_rect(Rect2i(0, 0, 512, 256))
    assert_eq(selection.chunks.size(), 2, "Two chunks across")

    selection.select_rect(Rect2i(0, 0, 256, 256), SaSelection.Mode.SUBTRACT)
    assert_eq(selection.chunks.size(), 1, "The chunk the subtract emptied is gone")
    assert_false(selection.covers(Vector2i(0, 0)), "and nothing is covered there")
    assert_eq(selection.bounds, Rect2i(256, 0, 256, 256), "so the bounds is the chunk that is left")


## An ellipse clears the pixels inside itself and not the box it is given, so a
## subtract by one must not shrink a coverage box by that box. The rectangle it
## is compared against is the same gesture with the same numbers.
func test_an_ellipse_subtract_does_not_shrink_by_its_bounding_box() -> void:
    var by_ellipse := _selection()
    by_ellipse.select_rect(Rect2i(0, 0, 256, 256))
    by_ellipse.select_ellipse(Rect2i(0, 0, 256, 100), SaSelection.Mode.SUBTRACT)
    assert_eq(by_ellipse.bounds, Rect2i(0, 0, 256, 256), "The corners the ellipse missed are still selected")

    var by_rect := _selection()
    by_rect.select_rect(Rect2i(0, 0, 256, 256))
    by_rect.select_rect(Rect2i(0, 0, 256, 100), SaSelection.Mode.SUBTRACT)
    assert_eq(by_rect.bounds, Rect2i(0, 100, 256, 156), "where the rectangle with the same numbers does shrink it")


## Select All then a strip off the bottom, on a canvas whose last row of chunks
## is shorter than the chunks holding it. The bounds has to come down to the
## strip and not to the chunk grid.
func test_select_all_shrinks_from_the_canvas_edge_not_the_chunk_edge() -> void:
    var selection := _selection()
    selection.select_all(Vector2i(400, 300))
    assert_eq(selection.bounds, Rect2i(0, 0, 400, 300), "Select All is the canvas, not the four chunks under it")

    selection.select_rect(Rect2i(0, 250, 400, 50), SaSelection.Mode.SUBTRACT)
    assert_eq(selection.bounds, Rect2i(0, 0, 400, 250), "and a strip off the bottom lands on 250")


## A write from outside is authoritative, because `SaSelectionFilters` and
## `SaWand` each know the reach of what they wrote and this file does not.
func test_a_written_bounds_replaces_every_chunk_box() -> void:
    var selection := _selection()
    selection.select_rect(Rect2i(0, 0, 512, 256))
    selection.bounds = Rect2i(0, 0, 300, 200)
    assert_eq(selection.bounds, Rect2i(0, 0, 300, 200), "The written rectangle is the answer")

    # And it is the answer the next subtract works from, rather than the boxes
    # the shapes left behind.
    selection.select_rect(Rect2i(0, 0, 512, 100), SaSelection.Mode.SUBTRACT)
    assert_eq(selection.bounds, Rect2i(0, 100, 300, 100), "and a strip off its top comes off the written one")
