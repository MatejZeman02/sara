## the sample merged snapshot: the easel's door for a stroke that reads
## the composite.
##
## The smudge spec's first open question is where the pickup lives, and its
## own answer is that a read of the same chunks the dab is about to write
## keeps the dirty-rect discipline while the overlay mode's read of the
## composite is a read of every layer. The snapshot is what makes that read
## one copy per chunk cell under the dab rather than the whole canvas: taken
## once at the stroke's start, grown by each dab that leaves it, released
## with the stroke. Every readback here is the test's own, off the snapshot
## it holds, because reading the result is how a GPU test asserts anything.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const StateEyedropperScript = preload("res://modules/sara-base-modules/base/tools/state_eyedropper.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const RED := Color(1.0, 0.0, 0.0, 1.0)
const BLUE := Color(0.0, 0.0, 1.0, 1.0)
const GREEN := Color(0.0, 1.0, 0.0, 1.0)


## A 512 by 512 easel with a checker across two layers: the first paint layer
## holds red on the diagonal cells, a second layer above it holds blue on the
## other two, and the composite is the four flattened. Two layers rather than
## one so the snapshot is proved to read the composite, not a layer.
func _checker_easel() -> SaEasel:
    var easel := SaEasel.create_default(Vector2i(512, 512))
    var document := easel.document
    var lower := document.active_layer
    lower.get_or_create_chunk(Vector2i(0, 0)).clear(RED)
    lower.get_or_create_chunk(Vector2i(1, 1)).clear(RED)
    var upper := SaLayerOps.new(document).add()
    upper.get_or_create_chunk(Vector2i(1, 0)).clear(BLUE)
    upper.get_or_create_chunk(Vector2i(0, 1)).clear(BLUE)
    document.invalidate_chunks([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)])
    easel.request_full_composite()
    easel.process_pending_composite()
    return easel


## The test's own readback: one texel of the snapshot, addressed in document
## space through the snapshot's own mapping.
func _texel(snapshot: SaMergedSnapshot, pos: Vector2i) -> Color:
    @warning_ignore("static_called_on_instance")
    var img := SaExport.get_texture_image_float(snapshot.texture)
    if img == null:
        return Color(NAN, NAN, NAN, NAN)
    var local := snapshot.local_of(pos)
    return img.get_pixel(local.x, local.y)


func _assert_color(actual: Color, expected: Color, what: String) -> void:
    assert_almost_eq(actual.r, expected.r, 0.01, "%s: red" % what)
    assert_almost_eq(actual.g, expected.g, 0.01, "%s: green" % what)
    assert_almost_eq(actual.b, expected.b, 0.01, "%s: blue" % what)
    assert_almost_eq(actual.a, expected.a, 0.01, "%s: alpha" % what)


## The snapshot under a rectangle that crosses all four cells holds the
## composite's colour at every corner, and it took exactly four copies.
func test_a_snapshot_holds_the_composite_under_its_rectangle() -> void:
    var easel := _checker_easel()

    var snapshot := easel.snapshot_merged(Rect2i(200, 200, 112, 112))
    assert_not_null(snapshot.texture, "A rectangle on the canvas gets a texture")
    assert_eq(snapshot.rect, Rect2i(200, 200, 112, 112), "sized to the rectangle asked for")
    assert_eq(snapshot.texture.size, Vector2i(112, 112), "and the texture is that size, not the canvas")
    assert_eq(snapshot.chunk_copies, 4, "One copy per chunk cell under the rectangle, four cells here")

    _assert_color(_texel(snapshot, Vector2i(200, 200)), RED, "The top left corner is the lower layer's red")
    _assert_color(_texel(snapshot, Vector2i(311, 200)), BLUE, "the top right the upper layer's blue")
    _assert_color(_texel(snapshot, Vector2i(200, 311)), BLUE, "the bottom left blue")
    _assert_color(_texel(snapshot, Vector2i(311, 311)), RED, "and the bottom right red")

    easel.free()


## A rectangle inside one cell is one copy, a rectangle half off the canvas is
## clipped, and one wholly off it holds nothing.
func test_the_rectangle_is_clipped_to_the_canvas_and_counted_by_cell() -> void:
    var easel := _checker_easel()

    var inside := easel.snapshot_merged(Rect2i(10, 10, 20, 20))
    assert_eq(inside.chunk_copies, 1, "One cell, one copy")
    _assert_color(_texel(inside, Vector2i(15, 15)), RED, "and it holds the red cell")

    var edge := easel.snapshot_merged(Rect2i(500, 500, 40, 40))
    assert_eq(edge.rect, Rect2i(500, 500, 12, 12), "A rectangle over the edge is clipped to the canvas")
    assert_eq(edge.chunk_copies, 1, "and is still one cell")

    var outside := easel.snapshot_merged(Rect2i(600, 600, 10, 10))
    assert_null(outside.texture, "A rectangle off the canvas holds no texture")
    assert_eq(outside.chunk_copies, 0, "and copied nothing")
    assert_false(outside.covers(Rect2i(600, 600, 1, 1)), "so it covers nothing either")

    easel.free()


## A dab that leaves the snapshot grows it by the cells it reaches, and the
## part already held keeps the picture it was taken with: a stroke reads what
## stood before it, not what it has painted since.
func test_a_growth_copies_only_the_new_cells_and_keeps_the_old_picture() -> void:
    var easel := _checker_easel()

    var snapshot := easel.snapshot_merged(Rect2i(10, 10, 20, 20))
    assert_eq(snapshot.chunk_copies, 1, "One cell to start")

    snapshot.grow(Rect2i(15, 15, 5, 5))
    assert_eq(snapshot.chunk_copies, 1, "A dab inside the snapshot costs no copy")
    assert_eq(snapshot.rect, Rect2i(10, 10, 20, 20), "and moves nothing")

    # The picture changes under the stroke, the way a stroke's own dabs change
    # it. The composite is cleared to green so the old and the new part of the
    # snapshot can be told apart.
    easel.output.clear(GREEN)

    snapshot.grow(Rect2i(300, 12, 10, 10))
    assert_eq(snapshot.rect, Rect2i(10, 10, 300, 20), "The snapshot is the union of the two rectangles")
    assert_eq(snapshot.texture.size, Vector2i(300, 20), "and the texture grew with it")
    # The first cell's strip right of the old rectangle, and the second cell.
    assert_eq(snapshot.chunk_copies, 3, "The growth copied the new area of the first cell and the second cell")
    assert_true(snapshot.covers(Rect2i(300, 12, 10, 10)), "and now covers the dab")

    _assert_color(_texel(snapshot, Vector2i(15, 15)), RED, "What was held is still the red it was taken with")
    _assert_color(_texel(snapshot, Vector2i(100, 15)), GREEN, "the rest of the first cell is what stands now")
    _assert_color(_texel(snapshot, Vector2i(305, 15)), GREEN, "and so is the second cell")

    easel.free()


## RAII: the snapshot's VRAM goes when the last reference does, and the easel
## keeps no reference of its own.
func test_the_snapshot_is_released_with_its_holder() -> void:
    var easel := _checker_easel()
    var before := SaTexture.allocated_bytes

    var snapshot := easel.snapshot_merged(Rect2i(0, 0, 512, 256))
    assert_eq(snapshot.texture.bytes, SaTexture.allocated_bytes - before, "A snapshot holds its texture's VRAM while it lives")
    snapshot = null
    assert_eq(SaTexture.allocated_bytes, before, "and gives it all back when dropped")

    easel.free()


## The eyedropper is the door's first reader: sample merged picks the
## composite through the snapshot, so a two-layer checker picks each layer's
## colour where that layer shows.
func test_the_eyedropper_reads_sample_merged_through_the_door() -> void:
    var surface := Fixtures.make_surface(Vector2i(512, 512))
    var document := surface.get_document()
    var lower := document.active_layer
    lower.get_or_create_chunk(Vector2i(0, 0)).clear(RED)
    var upper := SaLayerOps.new(document).add()
    upper.get_or_create_chunk(Vector2i(1, 0)).clear(BLUE)
    document.invalidate_chunks([Vector2i(0, 0), Vector2i(1, 0)])
    surface.easel.request_full_composite()
    surface.easel.process_pending_composite()

    var eyedropper := StateEyedropperScript.new()
    eyedropper.surface = surface
    eyedropper.sample_from = StateEyedropperScript.SampleFrom.VIEW

    _assert_color(eyedropper.pick_color_at_pos(Vector2(100, 100)), RED, "One texel of the lower layer's red")
    _assert_color(eyedropper.pick_color_at_pos(Vector2(300, 100)), BLUE, "one of the upper layer's blue")

    # A square across the seam averages both, through one snapshot of the
    # square and nothing more.
    eyedropper.sample_size = 3
    var seam := eyedropper.pick_color_at_pos(Vector2(256, 100))
    assert_almost_eq(seam.r, 1.0 / 3.0, 0.01, "A third red from the left of the seam")
    assert_almost_eq(seam.b, 2.0 / 3.0, 0.01, "two thirds blue from the right")

    Fixtures.teardown(surface)
