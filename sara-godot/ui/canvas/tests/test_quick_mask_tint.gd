## The quick mask's tint covers the canvas and nothing else.
##
## The red of the quick mask must cover the canvas and nothing more.
## `ui/canvas/selection_overlay.gd` could tint one whole chunk per grid position the
## selection did not hold, so on a canvas whose side is not a multiple of the
## chunk the last row and column of tint ran past the edge, and the chunks the
## selection holds were drawn whole through the shader, which tints their
## texels past the edge too, because past the edge a mask texel is zero.
##
## The geometry is a static on the overlay, so this suite asks it directly.
## `scenarios/the-quick-mask-tint-covers-the-canvas-and-nothing-else.json`
## is the same claim on the running app, where the state dump's
## `selection_overlay.tint.rect` is read against the canvas.
extends "res://tests/test_framework.gd"

## Not a multiple of the chunk on either side, so the grid's last row and
## column both reach past it.
const CANVAS := Vector2i(700, 500)


func _union(quads: Array[Rect2]) -> Rect2:
    var covered := Rect2()
    for quad: Rect2 in quads:
        covered = quad if covered.size == Vector2.ZERO else covered.merge(quad)
    return covered


func test_with_no_chunk_held_the_tint_is_exactly_the_canvas() -> void:
    var quads := SaSelectionOverlay.tint_quads(CANVAS, [])
    var canvas := Rect2(Vector2.ZERO, Vector2(CANVAS))
    assert_eq(quads.size(), 6, "Three columns by two rows of chunks cover 700 by 500")
    assert_eq(_union(quads), canvas, "The tint's union is the canvas rectangle")
    for quad: Rect2 in quads:
        assert_true(canvas.encloses(quad), "No quad reaches past the canvas: %s" % quad)


func test_a_held_chunk_is_left_to_the_shader_and_the_rest_still_ends_at_the_edge() -> void:
    var held: Array = [Vector2i(0, 0), Vector2i(2, 1)]
    var quads := SaSelectionOverlay.tint_quads(CANVAS, held)
    assert_eq(quads.size(), 4, "The two held chunks are not tinted by the plain child")
    for quad: Rect2 in quads:
        for grid_pos: Vector2i in held:
            var chunk := Rect2(Vector2(grid_pos) * float(SaChunk.SIZE), Vector2.ONE * float(SaChunk.SIZE))
            assert_false(quad.intersects(chunk), "A held chunk's square is not under a quad")
    # The last column's quad is cut to the 188 pixels the canvas has there,
    # and the last row's to its 244.
    var corner := SaSelectionOverlay.clip_chunk(Vector2i(2, 0), CANVAS)
    assert_eq(corner, Rect2(512, 0, 188, 256), "The last column is cut at the canvas edge")
    var bottom := SaSelectionOverlay.clip_chunk(Vector2i(1, 1), CANVAS)
    assert_eq(bottom, Rect2(256, 256, 256, 244), "The last row is cut at the canvas edge")


func test_the_plain_quads_and_the_clipped_held_chunks_together_are_the_canvas() -> void:
    var held: Array = [Vector2i(2, 1)]
    var pieces := SaSelectionOverlay.tint_quads(CANVAS, held)
    for grid_pos: Vector2i in held:
        pieces.append(SaSelectionOverlay.clip_chunk(grid_pos, CANVAS))
    assert_eq(_union(pieces), Rect2(Vector2.ZERO, Vector2(CANVAS)), "Shader draws and tint quads meet at the canvas")
    var area := 0.0
    for piece: Rect2 in pieces:
        area += piece.get_area()
    assert_almost_eq(area, 700.0 * 500.0, 0.001, "and cover it once, with no overlap and no gap")


func test_a_chunk_wholly_outside_the_canvas_clips_to_nothing() -> void:
    var outside := SaSelectionOverlay.clip_chunk(Vector2i(4, 4), CANVAS)
    assert_true(outside.size.x <= 0.0 or outside.size.y <= 0.0, "A chunk past the canvas draws nothing")


func test_a_canvas_that_is_a_multiple_of_the_chunk_is_unchanged() -> void:
    var quads := SaSelectionOverlay.tint_quads(Vector2i(512, 256), [])
    assert_eq(quads.size(), 2, "Two whole chunks")
    for quad: Rect2 in quads:
        assert_eq(quad.size, Vector2(256, 256), "and each is drawn whole, as before")
