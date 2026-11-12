## A fill under a selection allocates only the grid positions the selection
## holds, so a small selection on a large canvas costs one chunk of VRAM rather
## than the whole grid. A fill with no selection still takes the whole grid.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const TexelProbe = preload("res://harness/report/sa_texel_probe.gd")

## Needs a RenderingDevice, because a fill dispatches into chunks.
const REQUIRES_GPU := true

## The default document, whose grid is many chunks wide.
const SIZE := Vector2i(1920, 1080)

## The rectangle the door's `select` step makes in the note, inside chunk (0, 0).
const PATCH := Rect2i(10, 10, 50, 50)

const RED := Color(1.0, 0.0, 0.0, 1.0)


## The fill lands in the one chunk the selection reaches, paints the selected
## pixels the colour asked for, leaves the rest transparent, and one undo takes
## the paint and the chunk away again.
func test_a_fill_inside_a_selection_allocates_one_chunk() -> void:
    var doc := _document()
    var layer := doc.active_layer
    assert_eq(layer.chunks.size(), 0, "a fresh layer holds no chunk")
    doc.selection.select_rect(PATCH)
    var steps := doc.undo_redo.get_history_count()

    doc.fill_layer(RED)

    assert_eq(layer.chunks.keys(), [Vector2i(0, 0)], "the fill allocates the one chunk the selection reaches")
    var stored := _stored(doc, RED)
    assert_true(_texel(doc, Vector2i(30, 30)).is_equal_approx(stored), "a selected pixel takes the colour")
    assert_eq(_texel(doc, Vector2i(100, 100)).a, 0.0, "a pixel outside the selection stays transparent")
    assert_eq(doc.undo_redo.get_history_count(), steps + 1, "the fill is one step")

    assert_true(doc.undo_redo.undo(), "one undo")
    assert_eq(layer.chunks.size(), 0, "takes the chunk the fill allocated away again")

    assert_true(doc.undo_redo.redo(), "one redo")
    assert_eq(layer.chunks.size(), 1, "brings the one chunk back")
    assert_true(_texel(doc, Vector2i(30, 30)).is_equal_approx(stored), "with the colour in it")
    doc.free()


## A selection across a chunk border reaches the chunks on both sides of it and
## no other.
func test_a_selection_across_a_border_allocates_the_chunks_on_both_sides() -> void:
    var doc := _document()
    var side := SaChunk.SIZE
    doc.selection.select_rect(Rect2i(side - 8, 4, 16, 16))
    doc.fill_layer(RED)
    var held: Array = doc.active_layer.chunks.keys()
    held.sort()
    assert_eq(held, [Vector2i(0, 0), Vector2i(1, 0)], "both chunks the selection crosses, and only those")
    doc.free()


## With no selection the fill lands everywhere, so it takes the whole grid.
func test_a_fill_with_no_selection_allocates_the_grid() -> void:
    var doc := _document()
    doc.fill_layer(RED)
    var grid := SaLayer.grid_positions(SIZE)
    assert_eq(doc.active_layer.chunks.size(), grid.size(), "every position of the canvas holds a chunk")
    assert_true(_texel(doc, Vector2i(1900, 1000)).is_equal_approx(_stored(doc, RED)), "painted to the far corner")
    assert_true(doc.undo_redo.undo(), "one undo")
    assert_eq(doc.active_layer.chunks.size(), 0, "takes the whole grid away again")
    doc.free()


func _stored(doc: SaDocument, color: Color) -> Color:
    return doc.color_space.from_display(color) if doc.color_space != null else color


func _texel(doc: SaDocument, at: Vector2i) -> Color:
    var texel: Dictionary = TexelProbe._read_point(doc, null, at)["layer"]
    return Color(texel["r"], texel["g"], texel["b"], texel["a"])


func _document() -> SaDocument:
    var compositor := SaCompositor.new()
    compositor.set_registry(Fixtures.make_registries().blend_modes)
    var doc := SaDocument.new()
    doc.setup_default_document(SIZE, compositor)
    return doc
