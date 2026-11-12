## the scratch pools an isolated group composites through are bounded.
##
## gave every touched chunk of a pass its own pool slot and kept the slots
## between passes, so one opacity change inside an isolated group kept a chunk
## of VRAM for every chunk of the document until Sara closed. A pass is now
## walked in runs of `SaCompositor.SCRATCH_RUN`, and a scope level no pass
## reaches any more is dropped at the end of the pass.
##
## The second run takes the first run's slots again, so the pixel half of this
## suite is F3's claim one run later: what slot 1 held for chunk 1 must be gone
## before chunk `SCRATCH_RUN + 1` is composited through it.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const GREEN := Color(0, 1, 0, 1)
const RED := Color(1, 0, 0, 1)
const NOTHING := Color(0, 0, 0, 0)

## A run and a half, so the pass has a second run that reuses the first's slots.
## The half is a whole number of chunks, so it is a shift and not a division,
## which gdformat and the integer division warning both read without an
## annotation on a line of its own.
const CHUNKS_WIDE: int = SaCompositor.SCRATCH_RUN + (SaCompositor.SCRATCH_RUN >> 1)


func _easel() -> SaEasel:
    var easel := SaEasel.create_default(Vector2i(SaLayer.CHUNK_SIZE * CHUNKS_WIDE, SaLayer.CHUNK_SIZE))
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    return easel


func _texel(texture: SaTexture, x: int, y: int) -> Color:
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var at := (y * texture.size.x + x) * 16
    return Color(data.decode_float(at), data.decode_float(at + 4), data.decode_float(at + 8), data.decode_float(at + 12))


func _composite(easel: SaEasel) -> void:
    easel.request_full_composite()
    easel.process_pending_composite()


## Green underneath, and inside the group a layer that holds a chunk everywhere
## and paint in chunk 1 only, so every chunk of the pass takes the scratch chain
## and only one of them has anything to cover its scratch with.
func _isolated(easel: SaEasel) -> SaLayer:
    var doc := easel.document
    doc.fill_layer(GREEN, doc.active_layer)
    var inside := SaLayerOps.new(doc).add()
    var touched: Array = []
    for x in CHUNKS_WIDE:
        inside.get_or_create_chunk(Vector2i(x, 0)).clear(RED if x == 1 else NOTHING)
        touched.append(Vector2i(x, 0))
    doc.invalidate_chunks(touched)
    var groups := SaLayerOps.new(doc)
    var group := groups.group_active()
    groups.set_isolated(group, true)
    doc.set_active_layer(inside)
    return group


func test_a_pass_wider_than_a_run_keeps_no_more_slots_than_a_run() -> void:
    var easel := _easel()
    _isolated(easel)
    _composite(easel)

    var pools: Array = easel.compositor._walk._pools.scopes
    assert_eq(pools.size(), 1, "One isolated group around the active layer is one scope level")
    var slots: Array = pools[0]
    assert_eq(slots.size(), SaCompositor.SCRATCH_RUN, "and its pool holds a run of slots, not one per chunk of the pass")

    easel.free()


func test_the_second_run_does_not_see_what_the_first_left_in_its_slots() -> void:
    var easel := _easel()
    _isolated(easel)
    _composite(easel)

    var painted := SaLayer.CHUNK_SIZE + 10
    assert_almost_eq(_texel(easel.output, painted, 10).r, 1.0, 0.02, "Chunk 1 is the scope's red")
    # Slot 1 again, one run later.
    var reused := SaLayer.CHUNK_SIZE * (SaCompositor.SCRATCH_RUN + 1) + 10
    assert_almost_eq(_texel(easel.output, reused, 10).g, 1.0, 0.02, "The chunk that takes slot 1 next is the green under it")
    assert_almost_eq(_texel(easel.output, reused, 10).r, 0.0, 0.02, "and holds no red from the chunk that had the slot before")

    easel.free()


func test_a_group_that_stops_being_isolated_hands_its_pool_back() -> void:
    var easel := _easel()
    var group := _isolated(easel)
    _composite(easel)
    SaLayerOps.new(easel.document).set_isolated(group, false)
    _composite(easel)

    var pools: Array = easel.compositor._walk._pools.scopes
    assert_eq(pools.size(), 0, "No scope level is reached, so no scope pool is kept")
    var painted := SaLayer.CHUNK_SIZE + 10
    assert_almost_eq(_texel(easel.output, painted, 10).r, 1.0, 0.02, "and the picture is still the red over the green")

    easel.free()
