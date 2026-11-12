## The per-kernel dispatch tally, the buffer byte sum and the undo copy count.
##
## The four session-wide counters on SaCompute say
## whether a stroke did more or less work, and never which kernel did it. This
## proves the per-kernel ledger answers that, without disturbing the totals it
## sits beside.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, real dispatches and real buffers.
const REQUIRES_GPU := true
const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")


## Two dispatches batched under one list land 2 dispatches, 1 list and the
## workgroup product under the kernel's own key, and move the session counters
## by the same 2.
func test_kernel_tally_counts_dispatches_lists_and_workgroups() -> void:
    var comp := PaintKernel.compute()
    var canvas := SaTexture.new(Vector2i(64, 64))
    comp.set_texture(0, canvas.rid)
    var mask := SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    mask.clear(Color(1.0, 1.0, 1.0, 1.0))
    comp.set_texture(SaSelection.BINDING, mask.rid)
    var params := PackedFloat32Array()
    params.resize(16)
    comp.set_push_constant_float_array(params)

    SaCompute.reset_counters()
    assert_eq(SaCompute.kernel_counters().size(), 0, "A reset empties the tally too")

    comp.list_begin(comp.index_of_kernel("paint"))
    comp.list_dispatch(8, 8, 1)
    comp.list_dispatch(8, 8, 1)
    comp.list_end()

    var tally := SaCompute.kernel_counters()
    assert_true(tally.has(PaintKernel.NAME + "/paint"), "The key is shader name slash kernel name")
    var entry: Dictionary = tally[PaintKernel.NAME + "/paint"]
    assert_eq(int(entry["dispatches"]), 2, "Both dispatches of the batch are counted")
    assert_eq(int(entry["lists"]), 1, "and they shared the one list that batched them")
    assert_eq(int(entry["workgroups"]), 128, "8 x 8 x 1 twice")
    assert_eq(int(SaCompute.counters()["dispatches"]), 2, "The session counter moved the same amount")

    SaCompute.reset_counters()


## Kernel names repeat across shaders, so the key is not the kernel name alone.
func test_kernel_tally_counts_dispatches_only_once() -> void:
    var comp := PaintKernel.compute()
    var canvas := SaTexture.new(Vector2i(64, 64))
    comp.set_texture(0, canvas.rid)
    var mask := SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    mask.clear(Color(1.0, 1.0, 1.0, 1.0))
    comp.set_texture(SaSelection.BINDING, mask.rid)
    var params := PackedFloat32Array()
    params.resize(16)
    comp.set_push_constant_float_array(params)

    SaCompute.reset_counters()
    comp.dispatch_kernel("paint", 8, 8, 1)
    var tally := SaCompute.kernel_counters()
    var entry: Dictionary = tally[PaintKernel.NAME + "/paint"]
    assert_eq(int(entry["dispatches"]), 1, "One dispatch is counted once")
    assert_eq(int(entry["lists"]), 1, "and a lone dispatch still opens its own list")

    SaCompute.reset_counters()


## Two different shaders' kernels are two different keys, and the per-kernel
## tally accounts for every dispatch the session counter saw, not a subset.
func test_kernel_tally_sums_to_the_session_total_under_mixed_work() -> void:
    var paint := PaintKernel.compute()
    var canvas := SaTexture.new(Vector2i(64, 64))
    paint.set_texture(0, canvas.rid)
    var mask := SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    mask.clear(Color(1.0, 1.0, 1.0, 1.0))
    paint.set_texture(SaSelection.BINDING, mask.rid)
    var paint_params := PackedFloat32Array()
    paint_params.resize(16)
    paint.set_push_constant_float_array(paint_params)

    var background := SaCompute.new("background")
    var target := SaTexture.new(Vector2i(64, 64))
    background.set_texture(0, target.rid)
    var background_bytes := PackedByteArray()
    background_bytes.resize(GlobalShaderCompiler.push_constant_bytes("background"))
    background.set_push_constant(background_bytes)

    SaCompute.reset_counters()
    paint.dispatch_kernel("paint", 8, 8, 1)
    paint.dispatch_kernel("paint", 8, 8, 1)
    background.dispatch_kernel("generate", 1, 1, 1)

    var tally := SaCompute.kernel_counters()
    assert_true(tally.has(PaintKernel.NAME + "/paint"), "Two different kernels ran")
    assert_true(tally.has("background/generate"), "and both keys are present")

    var summed := 0
    for key: String in tally:
        summed += int((tally[key] as Dictionary)["dispatches"])
    assert_eq(summed, int(SaCompute.counters()["dispatches"]), "The tally accounts for every dispatch the session counted")

    SaCompute.reset_counters()


## A storage buffer's bytes are counted the way SaTexture.allocated_bytes counts
## a texture's, and given back the moment the buffer is dropped.
##
## The buffer is built and dropped inside a helper rather than a local here, so
## its last reference goes when that call returns, before this reads the count
## back, and not whenever this function's own stack frame happens to unwind.
func test_buffer_bytes_tracks_a_storage_buffer() -> void:
    var before := SaCompute.buffer_bytes
    var during := _make_and_drop_a_buffer(64)
    assert_eq(during, before + 64, "A 64-byte buffer moves buffer_bytes by 64")
    assert_eq(SaCompute.buffer_bytes, before, "and PREDELETE gives it back once it is dropped")


func _make_and_drop_a_buffer(size_bytes: int) -> int:
    var bytes := PackedByteArray()
    bytes.resize(size_bytes)
    # Held only for its RAII side effect, read while still in scope: PREDELETE
    # runs when this function returns and drops it.
    @warning_ignore("unused_variable")
    var buffer := SaCompute.Buffer.new(bytes)
    return SaCompute.buffer_bytes


func _two_field_schema() -> Array[SaFieldSpec]:
    return [SaFieldSpec.albedo(), SaFieldSpec.create(&"height", RenderingDevice.DATA_FORMAT_R32_SFLOAT, false)]


## A chunk snapshot for undo, SaChunk's own duplicate, counts one copy per
## field of the schema it was allocated with.
func test_a_chunk_duplicate_counts_one_copy_per_field() -> void:
    var schema := _two_field_schema()
    var chunk := SaChunk.create(schema)
    chunk.clear(Color(1.0, 0.0, 0.0, 1.0))

    var before := SaTexture.copies
    chunk.duplicate_chunk()
    assert_eq(SaTexture.copies, before + schema.size(), "One copy per field of the chunk")


## The other undo snapshot site, SaChunkDelta.capture, counts the same way, and
## restoring a captured delta counts nothing: the invariant is that a restore
## reads no texture back and copies only what the capture already read.
func test_a_delta_capture_counts_one_copy_per_field_and_a_restore_counts_none() -> void:
    var schema := _two_field_schema()
    var chunk := SaChunk.create(schema)
    chunk.clear(Color(1.0, 0.0, 0.0, 1.0))

    var before := SaTexture.copies
    var delta := SaChunkDelta.capture(chunk, Rect2i(0, 0, 64, 64))
    assert_eq(SaTexture.copies, before + schema.size(), "One capture copy per field")

    var after_capture := SaTexture.copies
    delta.apply_to(chunk)
    assert_eq(SaTexture.copies, after_capture, "A restore is not counted")
