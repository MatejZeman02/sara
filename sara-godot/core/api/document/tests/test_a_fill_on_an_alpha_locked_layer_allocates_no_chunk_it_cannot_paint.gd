## A fill on a layer whose alpha is locked paints only the chunks the layer
## already holds. A chunk that does not exist holds no alpha for the fill to
## keep, so a chunk allocated for it would stay transparent for the rest of the
## session, about a megabyte of VRAM each, against hard rule 3. Without the lock
## the fill still takes every position `SaLayer.fill_reach` answers.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const TexelProbe = preload("res://harness/report/sa_texel_probe.gd")

## Needs a RenderingDevice, because a fill dispatches into chunks.
const REQUIRES_GPU := true

## The default document, whose grid is many chunks wide.
const SIZE := Vector2i(1920, 1080)

## The shape laid before the lock, across the border of chunks (0, 0) and
## (1, 0), so the layer holds paint on exactly those two.
const SHAPE := Rect2i(SaChunk.SIZE - 20, 10, 40, 40)

## Half covered, so a lock that kept alpha reads 0.5 where a fill that broke it
## would read 1.
const BLUE := Color(0.0, 0.0, 1.0, 0.5)
const RED := Color(1.0, 0.0, 0.0, 1.0)

## A texel inside the shape on each of the two chunks, and one outside it.
const LEFT := Vector2i(SaChunk.SIZE - 10, 20)
const RIGHT := Vector2i(SaChunk.SIZE + 10, 20)
const OUTSIDE := Vector2i(SaChunk.SIZE + 100, 200)


## Through the document's fill, the one Edit > Fill and the door's `fill` step
## take: the layer keeps its two chunks, the shape takes the colour with its
## alpha as it was, and one undo gives the shape back as it was painted.
func test_a_locked_fill_layer_keeps_its_two_chunks() -> void:
    var doc := _document()
    var layer := doc.active_layer
    var before := _texel(doc, LEFT)
    layer.alpha_locked = true

    doc.fill_layer(RED)

    assert_eq(_held(layer), _two(), "the layer still holds exactly the two chunks of its shape")
    _assert_recoloured(doc)
    assert_true(doc.undo_redo.undo(), "one undo")
    assert_eq(_held(layer), _two(), "the undo leaves the same two chunks")
    var undone := _texel(doc, LEFT)
    assert_true(undone.is_equal_approx(before), "and the shape as it was painted, read %s against %s" % [undone, before])
    assert_true(_texel(doc, RIGHT).is_equal_approx(before), "on both of its chunks")
    doc.free()


## The same through the layer's own fill, which a caller with a layer in hand
## reaches without the document's undo.
func test_a_locked_layer_fill_keeps_its_two_chunks() -> void:
    var doc := _document()
    var layer := doc.active_layer
    layer.alpha_locked = true

    layer.fill(doc.color_space.from_display(RED) if doc.color_space != null else RED)

    assert_eq(_held(layer), _two(), "the layer still holds exactly the two chunks of its shape")
    _assert_recoloured(doc)
    doc.free()


## Unlocked, the same layer's fill lands everywhere, so it takes every position
## `fill_reach` answers, the whole grid with no selection.
func test_an_unlocked_fill_still_takes_the_whole_reach() -> void:
    var doc := _document()
    var layer := doc.active_layer
    var reach := SaLayer.fill_reach(doc, layer)
    assert_eq(reach.size(), SaLayer.grid_positions(SIZE).size(), "the reach of an unlocked fill is the whole grid")

    doc.fill_layer(RED)

    assert_eq(layer.chunks.size(), reach.size(), "every position of the reach holds a chunk")
    assert_true(_texel(doc, OUTSIDE).is_equal_approx(_stored(doc, RED)), "painted where nothing was")
    doc.free()


## A locked layer reaches nothing new, whatever the selection.
func test_a_locked_layer_reaches_no_position() -> void:
    var doc := _document()
    doc.active_layer.alpha_locked = true
    assert_eq(SaLayer.fill_reach(doc, doc.active_layer).size(), 0, "no position with no selection")
    doc.selection.select_rect(Rect2i(600, 300, 50, 50))
    assert_eq(SaLayer.fill_reach(doc, doc.active_layer).size(), 0, "nor under a selection")
    doc.free()


func _assert_recoloured(doc: SaDocument) -> void:
    var red := _stored(doc, RED)
    for at: Vector2i in [LEFT, RIGHT]:
        var texel := _texel(doc, at)
        assert_almost_eq(texel.a, BLUE.a, 0.001, "the alpha at %s is as it was" % at)
        assert_almost_eq(texel.r, red.r, 0.001, "and the colour there is the fill's, read %s" % texel)
        assert_almost_eq(texel.b, 0.0, 0.001, "with nothing of the blue left")
    assert_eq(_texel(doc, OUTSIDE).a, 0.0, "a pixel outside the shape stays transparent")


func _held(layer: SaLayer) -> Array:
    var held: Array = layer.chunks.keys()
    held.sort()
    return held


func _two() -> Array:
    return [Vector2i(0, 0), Vector2i(1, 0)]


func _stored(doc: SaDocument, color: Color) -> Color:
    return doc.color_space.from_display(color) if doc.color_space != null else color


func _texel(doc: SaDocument, at: Vector2i) -> Color:
    var texel: Dictionary = TexelProbe._read_point(doc, null, at)["layer"]
    return Color(texel["r"], texel["g"], texel["b"], texel["a"])


## A document whose active layer holds a half covered blue shape on two chunks,
## laid by a fill under a selection that is dropped after, with the history
## cleared so an undo in a test reaches only what the test did.
func _document() -> SaDocument:
    var compositor := SaCompositor.new()
    compositor.set_registry(Fixtures.make_registries().blend_modes)
    var doc := SaDocument.new()
    doc.setup_default_document(SIZE, compositor)
    doc.selection.select_rect(SHAPE)
    doc.fill_layer(BLUE)
    doc.selection.drop()
    doc.undo_redo.clear_history()
    assert_eq(_held(doc.active_layer), _two(), "the shape lies on two chunks")
    return doc
