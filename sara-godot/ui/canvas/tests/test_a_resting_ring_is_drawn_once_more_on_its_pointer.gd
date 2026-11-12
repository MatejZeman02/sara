## A pointer that comes to rest has its ring drawn once more, on the pointer.
##
## The ring leads a moving pointer, and a still one skips its redraw. The frame
## the speed fell under the rest threshold was still, so it skipped too, and the
## ring stayed where the last moving frame had put it, a fraction of a pixel
## along the stroke. How large a fraction was how long that frame took, so two
## runs of `scenarios/minimize-blocks-painting.json` shot the ring's edge a
## texel apart at the end of every stroke.
extends "res://tests/test_framework.gd"


## A still pointer whose ring sat on it draws nothing, which is the idle cost
## the redraw skip removes and nothing here may put back.
func test_a_still_pointer_with_its_ring_on_it_draws_nothing() -> void:
    assert_false(CursorOverlay.needs_redraw(true, false, false), "A resting ring that sits on its pointer is not drawn again")


## A still pointer whose last ring was drawn ahead of it draws once more.
func test_a_ring_left_ahead_of_a_still_pointer_is_drawn_again() -> void:
    assert_true(CursorOverlay.needs_redraw(true, false, true), "The ring a lead left ahead of the pointer is taken back")


## A pointer that moved, or one the prediction still calls moving, draws.
func test_a_moving_pointer_draws() -> void:
    assert_true(CursorOverlay.needs_redraw(false, false, false), "A pointer that moved draws its ring")
    assert_true(CursorOverlay.needs_redraw(true, true, true), "and so does one still gliding")
