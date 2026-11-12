## Deleting layers over the layer pool keeps every step before the delete.
##
## A hunt saw three filled layers of a 1920x1080 document
## deleted as one set write one `Delete Layers` step and drop the six before it,
## `dropped: 6, steps: 1`. The three layers are about 120 MiB against the 96 MiB
## pool, and the adds and fills before the delete keep no layer at all, so the
## pool they never drew on had no business dropping them.
extends "res://tests/test_framework.gd"

## Snapshots and layers are real chunk textures, so this needs a RenderingDevice.
const REQUIRES_GPU := true

## The document the note was written on. Its whole grid is forty chunks, so three
## filled layers are 120 chunks and over the layer pool at 32-bit chunks.
const CANVAS := Vector2i(1920, 1080)


func test_three_filled_layers_deleted_as_a_set_keep_every_earlier_step() -> void:
    var easel := SaEasel.create_default(CANVAS)
    var doc := easel.document
    var colours: Array[Color] = [Color(0.9, 0.1, 0.1, 1.0), Color(0.1, 0.9, 0.1, 1.0), Color(0.1, 0.1, 0.9, 1.0)]
    var picked: Array[SaLayer] = []
    for colour in colours:
        var layer := SaLayerOps.new(doc).add()
        doc.fill_layer(colour, layer)
        picked.append(layer)
    var names_before := _names(doc)
    var steps_before := doc.history.step_count()
    assert_eq(steps_before, 6, "Three adds and three fills are six steps")

    var weight := 0
    for layer in picked:
        weight += _layer_bytes(layer)
    assert_true(weight > doc.history.layer_budget_bytes, "The three filled layers are over the layer pool")

    assert_true(SaLayerOps.new(doc).remove_many(picked), "The three come off as one set")
    assert_eq(doc.history.step_count(), steps_before + 1, "as one more step beside the six")
    assert_eq(doc.history.dropped_steps, 0, "and nothing before it is dropped")
    assert_eq(doc.undo_redo.get_action_name(doc.undo_redo.get_current_action()), "Delete Layers", "The newest step is the delete")

    assert_true(doc.undo(), "Undo brings the three back")
    assert_eq(_names(doc), names_before, "in the stack they stood in")
    for i in picked.size():
        assert_almost_eq(_texel(picked[i]).r, colours[i].r, 1e-6, "with the pixels each was filled with")
    for i in steps_before:
        assert_true(doc.undo(), "and every step before the delete undoes too")
    assert_false(doc.undo_redo.has_undo(), "down to the document as it was made")
    assert_eq(_names(doc).size(), names_before.size() - picked.size(), "which has none of the three")

    easel.free()


## A second delete over the pool still pushes the first out, because the pool is
## a cap and a step that keeps a layer is exactly what it caps.
func test_a_second_large_delete_still_pushes_the_first_out() -> void:
    var easel := SaEasel.create_default(CANVAS)
    var doc := easel.document
    doc.history.announce_drops = false
    var first: Array[SaLayer] = []
    var second: Array[SaLayer] = []
    for i in 6:
        var layer := SaLayerOps.new(doc).add()
        doc.fill_layer(Color(float(i) / 6.0, 0.5, 0.5, 1.0), layer)
        (first if i < 3 else second).append(layer)

    assert_true(SaLayerOps.new(doc).remove_many(first), "The first three come off")
    assert_eq(doc.history.dropped_steps, 0, "keeping the twelve steps before them")
    assert_true(SaLayerOps.new(doc).remove_many(second), "and then the other three")
    assert_true(doc.history.dropped_steps > 0, "which drops the first delete and what came before it")
    assert_false(is_instance_valid(first[0]), "freeing the layers the first delete kept")
    assert_eq(doc.history.step_count(), 1, "so the newest delete stands alone over its pool")

    easel.free()


func _names(doc: SaDocument) -> Array:
    var names: Array = []
    for layer in SaLayerOps.new(doc).layers():
        names.append(str(layer.name))
    return names


func _layer_bytes(layer: SaLayer) -> int:
    var total := 0
    for grid_pos: Vector2i in layer.chunks:
        var chunk: SaChunk = layer.chunks[grid_pos]
        if chunk != null:
            total += chunk.byte_size()
    return total


func _texel(layer: SaLayer) -> Color:
    var texture := layer.get_field(Vector2i(0, 0))
    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(texture)
    return image.get_pixel(0, 0)
