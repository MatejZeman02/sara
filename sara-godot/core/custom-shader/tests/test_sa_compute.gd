## GPU integration tests for SaCompute abstraction.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true
const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")


func test_compute_initialization() -> void:
    var comp := SaCompute.new("composite")
    assert_eq(comp.shader_name, "composite", "Shader name should match")
    assert_true(comp.pipelines.kernels.size() > 0, "Should have loaded at least one kernel")
    assert_true(comp.pipelines.shader_id.is_valid(), "Shader ID should be valid")


func test_push_constants_packing() -> void:
    var comp := SaCompute.new("composite")
    var params := SaCompute.pack_composite_params(Vector2(10.0, 20.0), 0.8)
    assert_eq(params.size(), 32, "pack_composite_params should return 32 floats")
    assert_almost_eq(params[0], 10.0, 0.0001, "Offset X should match")
    assert_almost_eq(params[1], 20.0, 0.0001, "Offset Y should match")
    assert_almost_eq(params[2], 0.8, 0.0001, "Opacity should match")
    # W fills out the 16-byte header the two matrices start after, which is what
    # freed the four trailing floats for the transfer curve.
    assert_almost_eq(params[SaCompute.COMPOSITE_BLEND_WHITE_INDEX], 1.0, 0.0, "and the default blend reference white")

    # No document means sRGB: an identity matrix pair, then the sRGB curve. Nine
    # floats a matrix now, three to a column, because both are float[9] rather
    # than mat3 and std430 pads a mat3 column out to four.
    assert_almost_eq(params[4], 1.0, 0.0, "A default document needs no colour matrix")
    assert_almost_eq(params[5], 0.0, 0.0, "A default document needs no colour matrix")
    assert_almost_eq(params[8], 1.0, 0.0, "A default document needs no colour matrix")
    assert_almost_eq(params[12], 1.0, 0.0, "A default document needs no colour matrix")
    assert_almost_eq(params[13], 1.0, 0.0, "and its inverse is the identity too")

    # The curve as four numbers, not a flag naming one, then the coordinate
    # system. Pinned by value because the kernel reads these positionally and a
    # reordering is silent.
    var srgb := SaTransferFunction.srgb()
    assert_almost_eq(params[22], srgb.slope, 0.0001, "then the transfer slope")
    assert_almost_eq(params[23], srgb.threshold, 0.0001, "its threshold")
    assert_almost_eq(params[24], srgb.gain, 0.0001, "its gain")
    assert_almost_eq(params[25], srgb.exponent, 0.0001, "and its exponent")
    assert_almost_eq(params[26], float(SaColorSpace.Coordinates.RGB), 0.0, "then what the chunks hold")

    comp.set_push_constant_float_array(params)
    assert_eq(comp.block.bytes.size(), 128, "Push constant byte array should be 128 bytes (32 floats)")


## An empty region must not reach RenderingDevice, which rejects a zero group count
## with "Dispatch amount of X compute groups (0) is zero" instead of treating it as
## a no-op. Regression test for that crash during fast strokes.
func test_empty_dispatch_is_skipped_not_submitted() -> void:
    var comp := PaintKernel.compute()
    var texture := SaTexture.new(Vector2i(64, 64))
    comp.set_texture(0, texture.rid)
    var mask_1 := SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    mask_1.clear(Color(1.0, 1.0, 1.0, 1.0))
    comp.set_texture(SaSelection.BINDING, mask_1.rid)
    # The paint fixture declares 16 floats of push constants. A short array is rejected by
    # RenderingDevice before the dispatch is even reached.
    var params := PackedFloat32Array()
    params.resize(16)
    comp.set_push_constant_float_array(params)

    comp.list_begin(comp.index_of_kernel("paint"))
    comp.list_dispatch(0, 8, 1)
    comp.list_dispatch(8, 0, 1)
    comp.list_dispatch(8, 8, 0)
    comp.list_end()

    assert_true(comp.list._warned_empty, "An empty dispatch should be detected and skipped")

    # The guard must not disable the compute list: real work still goes through.
    comp.list_begin(comp.index_of_kernel("paint"))
    comp.list_dispatch(8, 8, 1)
    comp.list_end()
    assert_true(comp.uniforms.gpu_id.is_valid(), "A non-empty dispatch should still build its uniform set")


## The dispatch counters have to count, or the batching work lands unmeasured.
##
## Asserted exactly rather than "moved at all". `lists` sitting level with
## `dispatches` is precisely the finding the batching work exists to fix, and a test that only
## checked for movement would go on passing after batching separated them, which is
## the one moment anyone would want to be told.
##
## The last call deliberately prints one "no kernel named" error, an expected
## refusal.
func test_gpu_work_is_counted() -> void:
    var comp := PaintKernel.compute()
    var texture := SaTexture.new(Vector2i(64, 64))
    comp.set_texture(0, texture.rid)
    var mask_2 := SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    mask_2.clear(Color(1.0, 1.0, 1.0, 1.0))
    comp.set_texture(SaSelection.BINDING, mask_2.rid)
    var params := PackedFloat32Array()
    params.resize(16)
    comp.set_push_constant_float_array(params)

    SaCompute.reset_counters()
    assert_eq(int(SaCompute.counters()["dispatches"]), 0, "A reset zeroes the counters")

    comp.dispatch_kernel("paint", 8, 8, 1)
    var once := SaCompute.counters()
    assert_eq(int(once["dispatches"]), 1, "One dispatch is counted once")
    assert_eq(int(once["lists"]), 1, "and today it opens a list of its own, which is what the batching work is about")
    assert_eq(int(once["workgroups"]), 64, "Workgroups are counted as dispatched: 8 x 8 x 1")
    assert_eq(int(once["uniform_sets"]), 1, "The first dispatch after a set_texture builds a uniform set")

    comp.dispatch_kernel("paint", 8, 8, 1)
    var twice := SaCompute.counters()
    assert_eq(int(twice["dispatches"]), 2, "The counters accumulate rather than sample")
    assert_eq(int(twice["uniform_sets"]), 1, "and an unchanged binding does not rebuild its set")

    comp.dispatch_kernel("no_such_kernel", 8, 8, 1)
    assert_eq(int(SaCompute.counters()["dispatches"]), 2, "A refused kernel name is not GPU work and is not counted")

    SaCompute.reset_counters()


## Alternating between two sets of bindings must not rebuild on every dispatch.
##
## This is the exact shape of the binding-cache problem. The old cache compared
## each binding against the last value seen, which answers "changed" every time for
## a caller that alternates, and `composite_chunk` alternates by construction: it
## walks chunks, so no two consecutive dispatches share a source. The bindings
## repeat constantly, they just never repeat twice in a row.
func test_alternating_bindings_reuse_their_uniform_sets() -> void:
    var comp := PaintKernel.compute()
    var first := SaTexture.new(Vector2i(64, 64))
    var second := SaTexture.new(Vector2i(64, 64))
    var params := PackedFloat32Array()
    params.resize(16)
    comp.set_push_constant_float_array(params)

    # The paint kernel binds the selection mask too, and a fresh mask per
    # dispatch would be a fresh set per dispatch, which is what this measures.
    var mask := SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    mask.clear(Color(1.0, 1.0, 1.0, 1.0))
    comp.set_texture(SaSelection.BINDING, mask.rid)

    SaCompute.reset_counters()
    for round_index in 4:
        for texture: SaTexture in [first, second]:
            comp.set_texture(0, texture.rid)
            comp.dispatch_kernel("paint", 8, 8, 1)

    var counted := SaCompute.counters()
    assert_eq(int(counted["dispatches"]), 8, "Eight dispatches went out")
    assert_eq(int(counted["uniform_sets"]), 2, "and built two sets, one per texture, not one per dispatch")

    # Rebinding what is already bound is not even a lookup.
    comp.set_texture(0, second.rid)
    comp.dispatch_kernel("paint", 8, 8, 1)
    assert_eq(int(SaCompute.counters()["uniform_sets"]), 2, "Rebinding the same texture builds nothing")

    SaCompute.reset_counters()


## Sending the wrong number of bytes is reported, naming both numbers.
##
## The point of the push-constant size check. RenderingDevice does refuse a wrong size,
## but it says the push constant is *absent*, which sends you looking for a
## binding bug rather than at the two lines that disagree.
##
## Deliberately prints one "SaCompute" error, an expected refusal.
func test_a_push_constant_of_the_wrong_size_says_so() -> void:
    var comp := SaCompute.new("composite")
    assert_false(comp.block._warned_size, "Nothing wrong yet")

    # The composite block is 32 floats. Four is a plausible-looking mistake: it is
    # what the offset and opacity alone would be.
    var short := PackedFloat32Array()
    short.resize(4)
    comp.set_push_constant_float_array(short)
    assert_true(comp.block._warned_size, "A short block is caught where it is packed")

    var right := SaCompute.pack_composite_params(Vector2.ZERO, 1.0)
    var honest := SaCompute.new("composite")
    honest.set_push_constant_float_array(right)
    assert_false(honest.block._warned_size, "and the real packer is not caught, because it agrees")
    assert_eq(honest.block.bytes.size(), GlobalShaderCompiler.push_constant_bytes("composite"), "byte for byte")


## A dispatch notices a recompile without asking the compiler every time.
##
## `list_begin` used to pull the shader's whole kernel array out of a Dictionary on
## every dispatch, 360 times a stroke by the counters, to spot a hot reload that
## happens when a file is saved. The generation counter is the same question asked
## with an integer, and it has to keep working: a reload that goes unnoticed leaves
## the instance dispatching pipelines the compiler has already freed.
func test_a_recompile_is_noticed_without_a_lookup_per_dispatch() -> void:
    var comp := PaintKernel.compute()
    var texture := SaTexture.new(Vector2i(64, 64))
    comp.set_texture(0, texture.rid)
    var mask_5 := SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    mask_5.clear(Color(1.0, 1.0, 1.0, 1.0))
    comp.set_texture(SaSelection.BINDING, mask_5.rid)
    var params := PackedFloat32Array()
    params.resize(16)
    comp.set_push_constant_float_array(params)

    comp.dispatch_kernel("paint", 8, 8, 1)
    var settled := comp.pipelines.seen_generation
    assert_eq(settled, GlobalShaderCompiler.compile_generation, "A dispatch brings the instance up to date")

    comp.dispatch_kernel("paint", 8, 8, 1)
    assert_eq(comp.pipelines.seen_generation, settled, "and a second one has nothing to check")

    # What a hot reload does to the compiler, without touching a file.
    GlobalShaderCompiler.compile_generation += 1
    comp.dispatch_kernel("paint", 8, 8, 1)
    assert_eq(
        comp.pipelines.seen_generation, GlobalShaderCompiler.compile_generation, "A recompile is picked up on the next dispatch"
    )
    assert_true(comp.pipelines.shader_id.is_valid(), "and the instance still holds a usable shader")
