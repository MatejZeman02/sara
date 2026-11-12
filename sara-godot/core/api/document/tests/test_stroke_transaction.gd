## SaStrokeTransaction: the "before" side of one stroke's undo record.
##
## The class is twenty lines and every one of them is load-bearing, because
## undo restores whatever it kept. Getting a snapshot wrong does not fail, it
## makes Ctrl+Z put back the wrong picture, and only at the moment the user
## needs it to be right.
extends "res://tests/test_framework.gd"

## Snapshots are real texture copies.
const REQUIRES_GPU := true

const ORIGINAL := Color(1.0, 0.0, 0.0, 1.0)
const PAINTED_OVER := Color(0.0, 1.0, 0.0, 1.0)


func _layer(size: Vector2i = Vector2i(256, 256)) -> SaLayer:
    var layer := SaLayer.new()
    layer.allocate_grid(size)
    return layer


## The red of a snapshot's first texel. A snapshot is a SaChunkDelta now, a
## rectangle of a chunk rather than all of it, so this reaches for the albedo
## piece rather than for a whole chunk.
func _red_of(delta: SaChunkDelta) -> float:
    var rd := GlobalShaderCompiler.get_rd()
    return rd.texture_get_data((delta.fields[&"albedo"] as SaTexture).rid, 0).decode_float(0)


## A stroke is many dabs over the same chunk. Only the state before the *first*
## one is the state undo has to return to, so a later dab must not overwrite it.
## If it did, undo would restore a half-painted stroke.
func test_the_first_snapshot_of_a_position_is_the_one_kept() -> void:
    var layer := _layer()
    layer.fill(ORIGINAL)
    var transaction := SaStrokeTransaction.new()

    transaction.capture_before(layer, Vector2i.ZERO)
    layer.get_or_create_chunk(Vector2i.ZERO).clear(PAINTED_OVER)
    transaction.capture_before(layer, Vector2i.ZERO)

    assert_almost_eq(_red_of(transaction.before_chunks[Vector2i.ZERO]), 1.0, 0.001, "Undo returns to the first state")
    layer.free()


## The snapshot has to be a copy. Sharing the texture would make undo restore
## exactly the pixels the stroke just wrote, which looks like undo doing nothing.
func test_the_snapshot_is_a_copy_rather_than_the_live_chunk() -> void:
    var layer := _layer()
    layer.fill(ORIGINAL)
    var transaction := SaStrokeTransaction.new()

    transaction.capture_before(layer, Vector2i.ZERO)
    var snapshot: SaChunkDelta = transaction.before_chunks[Vector2i.ZERO]
    layer.get_or_create_chunk(Vector2i.ZERO).clear(PAINTED_OVER)

    var piece: SaTexture = snapshot.fields[&"albedo"]
    assert_true(piece.rid != layer.get_field(Vector2i.ZERO).rid, "A distinct texture, not an alias")
    assert_almost_eq(_red_of(snapshot), 1.0, 0.001, "Painting afterwards must not reach the snapshot")
    layer.free()


## Painting outside the allocated grid is allowed, so a stroke can create a
## chunk where there was none. "Nothing was here" is recorded as a null value
## under a key that exists, and set_chunk(pos, null) is what removes it again.
func test_a_position_that_held_no_chunk_is_recorded_as_null() -> void:
    var layer := _layer()
    var far_away := Vector2i(9, 9)
    var transaction := SaStrokeTransaction.new()

    transaction.capture_before(layer, far_away)

    assert_true(transaction.before_chunks.has(far_away), "The position is recorded")
    assert_null(transaction.before_chunks[far_away], "and what it held was nothing")
    layer.free()


## The trap in the line above. Dictionary.has() is true for a stored null, which
## is what stops the second capture. A guard written as "if the entry is null,
## capture it" would replace the null with the chunk the stroke had just
## created, and undo would leave that paint on the canvas for ever.
func test_recording_nothing_still_blocks_a_later_capture() -> void:
    var layer := _layer()
    var far_away := Vector2i(9, 9)
    var transaction := SaStrokeTransaction.new()

    transaction.capture_before(layer, far_away)
    layer.get_or_create_chunk(far_away).clear(PAINTED_OVER)
    transaction.capture_before(layer, far_away)

    assert_null(transaction.before_chunks[far_away], "Undo must still remove the chunk the stroke created")
    layer.free()


func test_each_position_is_captured_on_its_own() -> void:
    var layer := _layer(Vector2i(512, 512))
    layer.fill(ORIGINAL)
    var transaction := SaStrokeTransaction.new()

    transaction.capture_before(layer, Vector2i.ZERO)
    transaction.capture_before(layer, Vector2i(1, 1))

    assert_eq(transaction.before_chunks.size(), 2, "Two touched chunks are two records")
    layer.free()


## The erase path paints straight onto the active layer, so commit_stroke takes
## a different branch entirely. The flag is what selects it.
func test_direct_paint_is_off_until_it_is_marked() -> void:
    var transaction := SaStrokeTransaction.new()
    assert_false(transaction.direct_paint, "An ordinary stroke goes through the stroke layer")

    transaction.mark_direct_paint()
    assert_true(transaction.direct_paint, "Erasing is direct")


## The transaction outlives the stroke, so anything it keeps is carried into the
## next one. A snapshot left behind would make the following stroke's undo
## restore a chunk from the stroke before it.
func test_reset_clears_the_snapshots_and_the_flag() -> void:
    var layer := _layer()
    layer.fill(ORIGINAL)
    var transaction := SaStrokeTransaction.new()
    transaction.capture_before(layer, Vector2i.ZERO)
    transaction.mark_direct_paint()

    transaction.reset()

    assert_true(transaction.before_chunks.is_empty(), "Nothing is carried into the next stroke")
    assert_false(transaction.direct_paint, "including the branch it would take")
    layer.free()
