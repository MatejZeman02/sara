## The ordered composite: a layer above the active one blends against what is
## under it, and the caches hold chunks only where the layers they stand for do.
##
## Seventeen blend modes were ticked as working and above the active layer none
## of them was. The top cache was cleared to transparent, the layers above
## composited into it, and Porter-Duff over an empty destination returns the
## source, so Multiply on top of a painting did nothing. Nothing in 2107
## assertions read a composited result above the active layer, which is why it
## survived every gate. This is the test that would have caught it.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true


## An easel whose compositor resolves modes. Without a registry every mode is
## Normal, which is the fallback this suite must not be fooled by.
func _easel(size: Vector2i) -> SaEasel:
    var easel := SaEasel.create_default(size)
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    return easel


## One texel of a texture, as stored.
func _texel(texture: SaTexture, x: int, y: int) -> Color:
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var at := (y * texture.size.x + x) * 16
    return Color(data.decode_float(at), data.decode_float(at + 4), data.decode_float(at + 8), data.decode_float(at + 12))


func _composite(easel: SaEasel) -> void:
    easel.request_full_composite()
    easel.process_pending_composite()


func _layer_named(doc: SaDocument, layer_name: String) -> SaLayer:
    return doc.get_node(layer_name) as SaLayer


## The bug, pinned: mid grey under a Multiply layer of mid grey is a quarter,
## not a half.
func test_a_multiply_layer_above_the_active_one_darkens_what_is_under_it() -> void:
    var easel := _easel(Vector2i(256, 256))
    var doc := easel.document
    var above := SaLayerOps.new(doc).add()
    SaLayerOps.new(doc).set_blend_mode(above, &"multiply")
    doc.fill_layer(Color(0.5, 0.5, 0.5, 1.0), above)
    doc.set_active_layer(_layer_named(doc, "Layer 1"))
    doc.fold.debt.settle(doc)
    assert_eq(doc.fold.top_stack.size(), 1, "One layer above the active one")
    assert_eq(doc.fold.top_stack[0][SaLayerStack.LAYER], above, "walked from its own chunks")

    _composite(easel)
    var texel := _texel(easel.output, 10, 10)
    assert_almost_eq(texel.r, 0.25, 0.02, "Multiply above the painting multiplies the painting, not nothing")
    assert_almost_eq(texel.a, 1.0, 0.01, "and the backdrop is kept")

    easel.free()


## A Normal layer above the active one, alone, needs no cache and gets none.
## Two in a row fold into the top cache, because over is associative. A mode
## that is not Normal splits the run, because no other mode is.
func test_only_runs_of_normal_layers_above_the_active_one_are_cached() -> void:
    var easel := SaEasel.create_default(Vector2i(256, 256))
    var doc := easel.document
    var a := SaLayerOps.new(doc).add()
    var b := SaLayerOps.new(doc).add()
    a.get_or_create_chunk(Vector2i(0, 0)).clear(Color.RED)
    doc.set_active_layer(_layer_named(doc, "Layer 1"))
    doc.fold.debt.settle(doc)

    assert_eq(doc.fold.top_stack.size(), 1, "Two Normal layers are one step")
    assert_eq(doc.fold.top_stack[0][SaLayerStack.LAYER], doc.fold.top_cache, "through the top cache")
    assert_eq(doc.fold.top_cache.chunks.size(), 1, "which holds a chunk only where either layer does")

    SaLayerOps.new(doc).set_blend_mode(b, &"multiply")
    doc.update_caches()
    assert_eq(doc.fold.top_stack.size(), 2, "A Multiply above a Normal is two steps")
    assert_eq(doc.fold.top_stack[0][SaLayerStack.LAYER], a, "the Normal from its own chunks, being alone")
    assert_eq(doc.fold.top_stack[1][SaLayerStack.LAYER], b, "and the Multiply from its own")
    assert_eq(doc.fold.top_stack[1][SaLayerStack.MODE], &"multiply", "with its own mode")
    assert_true(doc.fold.top_cache.chunks.is_empty(), "and the cache nothing uses holds nothing")

    # Added above the active layer, so moved to the top by hand: the run has to
    # sit above the Multiply for this to be the case it claims to be.
    var c := SaLayerOps.new(doc).add()
    var d := SaLayerOps.new(doc).add()
    doc.move_child(c, doc.get_child_count() - 1)
    doc.move_child(d, doc.get_child_count() - 1)
    c.get_or_create_chunk(Vector2i(0, 0)).clear(Color.GREEN)
    doc.set_active_layer(_layer_named(doc, "Layer 1"))
    doc.fold.debt.settle(doc)
    assert_eq(doc.fold.top_stack.size(), 3, "Normal, Multiply, then a run of two Normals")
    assert_eq(doc.fold.top_stack[2][SaLayerStack.LAYER], doc.fold.top_cache, "The run after the Multiply is the first cached run")
    assert_true(doc.fold.top_run_caches.is_empty(), "and no second run cache was needed")
    assert_true(d.chunks.is_empty(), "A layer nothing painted on has no chunks")

    easel.free()


## Below the active layer one visible layer is walked directly, and two fold
## into the bottom cache, where the layers hold chunks and nowhere else. The
## old code allocated both caches over the whole canvas plus one row and one
## column past it: 6 chunks here, for 1 chunk of paint.
func test_the_bottom_cache_is_as_sparse_as_the_layers_it_stands_for() -> void:
    var easel := _easel(Vector2i(512, 256))
    var doc := easel.document
    var background := _layer_named(doc, "Background")
    assert_eq(doc.fold.bottom_stack.size(), 1, "One layer below the active one")
    assert_eq(doc.fold.bottom_stack[0][SaLayerStack.LAYER], background, "is walked from its own chunks")
    assert_true(doc.fold.bottom_cache.chunks.is_empty(), "and the bottom cache holds nothing")

    SaLayerOps.new(doc).set_visible(background, false)
    var x := SaLayerOps.new(doc).add()
    var y := SaLayerOps.new(doc).add()
    x.get_or_create_chunk(Vector2i(1, 0)).clear(Color.BLUE)
    doc.move_child(x, 1)
    doc.move_child(y, 2)
    doc.set_active_layer(_layer_named(doc, "Layer 1"))
    doc.fold.debt.settle(doc)

    assert_eq(doc.fold.bottom_stack.size(), 1, "Two visible layers below fold into one step")
    assert_eq(doc.fold.bottom_stack[0][SaLayerStack.LAYER], doc.fold.bottom_cache, "the bottom cache")
    assert_eq(doc.fold.bottom_cache.chunks.size(), 1, "which holds the one chunk either layer has, not 6")
    assert_true(doc.fold.bottom_cache.chunks.has(Vector2i(1, 0)), "where the paint is")

    _composite(easel)
    assert_almost_eq(_texel(easel.output, 300, 10).b, 1.0, 0.02, "and the paint is composited")
    assert_almost_eq(_texel(easel.output, 10, 10).a, 0.0, 0.01, "over nothing where nothing is")

    easel.free()


## Hard rule 3, at the three call sites: a layer allocates where paint lands.
func test_a_new_or_duplicated_layer_allocates_nothing() -> void:
    var easel := SaEasel.create_default(Vector2i(1920, 1080))
    var doc := easel.document
    assert_eq(_layer_named(doc, "Background").chunks.size(), 40, "The background holds paint everywhere")
    assert_true(_layer_named(doc, "Layer 1").chunks.is_empty(), "The paint layer holds paint nowhere yet")

    var added := SaLayerOps.new(doc).add()
    assert_true(added.chunks.is_empty(), "An added layer holds nothing")
    var copy := SaLayerOps.new(doc).duplicate(added)
    assert_true(copy.chunks.is_empty(), "A copy of nothing is nothing")
    var background_copy := SaLayerOps.new(doc).duplicate(_layer_named(doc, "Background"))
    assert_eq(background_copy.chunks.size(), 40, "and a copy of the background is the background")

    easel.free()


## A fill lands everywhere, so it is the one operation after the background
## that allocates the grid, and an undo takes those chunks away again rather
## than leaving forty blank ones. Clearing is the other way round: no paint
## anywhere is no chunks anywhere.
func test_a_fill_allocates_the_grid_and_its_undo_removes_it() -> void:
    var easel := SaEasel.create_default(Vector2i(512, 512))
    var doc := easel.document
    var layer := doc.active_layer
    assert_true(layer.chunks.is_empty(), "Nothing before the fill")

    doc.fill_layer(Color.RED)
    assert_eq(layer.chunks.size(), 4, "A fill covers the canvas")
    doc.undo()
    assert_true(layer.chunks.is_empty(), "and undoing it takes the chunks with it")
    doc.redo()
    assert_eq(layer.chunks.size(), 4, "and redo brings them back")

    doc.clear_layer()
    assert_true(layer.chunks.is_empty(), "Clearing releases rather than blanks")
    doc.undo()
    assert_eq(layer.chunks.size(), 4, "and its undo restores the paint")
    assert_almost_eq(_texel(layer.get_field(Vector2i(0, 0)), 5, 5).r, 1.0, 0.01, "red again")

    easel.free()
