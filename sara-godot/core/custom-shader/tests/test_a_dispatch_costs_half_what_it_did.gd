## A dispatch costs half what it did.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The bench the row asks for, and the count it asks to hold. A walk binds a
## chunk's texture and dispatches, chunk after chunk, the way the compositor
## walks the stack of the seasons painting, so the bench times the GDScript of
## one `set_texture` and one `dispatch_kernel` over textures whose uniform sets
## are all cached, which is the walk's steady state. It prints the figure as a
## `bench:` line, the best of [constant RUNS] walks because a gate shared
## with other clones slows a walk and never speeds one up, and asserts only a
## ceiling far above it.
extends "res://tests/test_framework.gd"

const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")
const UniformSets = preload("res://core/custom-shader/sa_uniform_sets.gd")
const PushConstants = preload("res://core/custom-shader/sa_push_constants.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

## The chunks a walk binds in turn, the chunks of a 2160 by 720 canvas.
const CHUNKS: int = 27
## Walks a measured run makes, after one that builds every set.
const WALKS: int = 40
## Measured runs, the best of which is the figure.
const RUNS: int = 5
## A ceiling no machine the gate runs on comes near: a dispatch measured
## 15 µs of GDScript, and this is ten times that.
const CEILING_USEC: float = 150.0

var _mask: SaTexture = null


func after_each() -> void:
    _mask = null


## A paint kernel with its mask and push constant bound, so the one binding that
## moves between dispatches is binding 0.
func _kernel() -> SaCompute:
    var comp := PaintKernel.compute()
    _mask = SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    _mask.clear(Color(1.0, 1.0, 1.0, 1.0))
    comp.set_texture(SaSelection.BINDING, _mask.rid)
    var params := PackedFloat32Array()
    params.resize(PaintKernel.PARAMS_FLOATS)
    comp.set_push_constant_float_array(params)
    return comp


func _textures(count: int) -> Array[SaTexture]:
    var made: Array[SaTexture] = []
    for i in count:
        made.append(SaTexture.new(Vector2i(8, 8)))
    return made


## The microseconds of GDScript one bind and one dispatch take over *chunks*,
## every set already built.
func _walk_usec(comp: SaCompute, chunks: Array[SaTexture]) -> float:
    var started := Time.get_ticks_usec()
    for walk in WALKS:
        for chunk: SaTexture in chunks:
            comp.set_texture(0, chunk.rid)
            comp.dispatch_kernel("paint", 1, 1, 1)
    return float(Time.get_ticks_usec() - started) / float(WALKS * chunks.size())


func test_the_bench_reads_the_cost_of_a_dispatch_s_setup() -> void:
    var comp := _kernel()
    var chunks := _textures(CHUNKS)
    _walk_usec(comp, chunks)
    var best := INF
    for run in RUNS:
        best = minf(best, _walk_usec(comp, chunks))
    print("bench: a bind and a dispatch over cached sets take %.2f µs of GDScript" % best)
    assert_true(best < CEILING_USEC, "a dispatch's setup stays far under its ceiling")
    SaCompute.reset_counters()


## A run of dispatches binding the same textures builds its `RDUniform`s on
## the first walk and none after it, because a bind that changes nothing is
## caught before one is made and a set seen before is found by its key.
func test_a_run_binding_the_same_textures_builds_no_uniform_after_the_first() -> void:
    var comp := _kernel()
    var chunks := _textures(CHUNKS)
    var before := UniformSets.uniforms_built
    for chunk: SaTexture in chunks:
        comp.set_texture(0, chunk.rid)
        comp.dispatch_kernel("paint", 1, 1, 1)
    assert_true(UniformSets.uniforms_built > before, "the first walk builds the sets it needs")
    var after_first := UniformSets.uniforms_built
    for walk in 3:
        for chunk: SaTexture in chunks:
            comp.set_texture(0, chunk.rid)
            comp.dispatch_kernel("paint", 1, 1, 1)
    assert_eq(UniformSets.uniforms_built - after_first, 0, "no RDUniform is built after the first walk")
    SaCompute.reset_counters()


## A run of dispatches recorded and submitted together goes out as one compute
## list with a barrier between them, and over textures already bound once it
## builds no `RDUniform` either.
func test_a_recorded_run_shares_one_list_and_builds_no_uniform() -> void:
    var comp := _kernel()
    var chunks := _textures(CHUNKS)
    _walk_usec(comp, chunks)
    var format := comp.pipelines.storage_format
    var built := UniformSets.uniforms_built
    var recorded: Array[SaCompute.Recorded] = []
    for chunk: SaTexture in chunks:
        comp.set_texture(0, chunk.rid)
        var one := comp.record("paint", format, 1, 1, 1, not recorded.is_empty())
        assert_not_null(one, "a dispatch over a bound chunk records")
        recorded.append(one)
    var lists_before := SaCompute.lists
    var dispatches_before := SaCompute.dispatches
    SaCompute.submit(recorded, "probe run")
    assert_eq(SaCompute.lists - lists_before, 1, "the run goes out as one list")
    assert_eq(SaCompute.dispatches - dispatches_before, CHUNKS, "every chunk of the run is dispatched in it")
    assert_eq(UniformSets.uniforms_built - built, 0, "the recorded run builds no RDUniform")
    SaCompute.reset_counters()


## Named params are packed from a plan read once per layout, and the bytes
## are the ones the static packer writes from scratch. The figure is printed as
## a `params:` line, about 40 µs a call.
func test_named_params_pack_the_same_bytes_from_the_plan() -> void:
    var comp := SaCompute.new("live_transform")
    var values := {
        "row_x": Vector4(1.5, -2.0, 3.25, 0.5),
        "row_y": Vector4(0, 1, 0, 0),
        "row_w": Vector4(0, 0, 1, 0),
        "region": Vector4(0, 0, 256, 256),
        "origins": Vector4(7, 9, 11, 13),
        "crop": Vector4(0, 0, 512, 512),
    }
    var layout := GlobalShaderCompiler.push_constant_layout("live_transform")
    comp.set_params(values)
    assert_eq(comp.block.bytes, PushConstants.pack(layout, values), "the plan packs what the packer packs")
    var best := INF
    for run in RUNS:
        var started := Time.get_ticks_usec()
        for i in 2000:
            comp.set_params(values)
        best = minf(best, float(Time.get_ticks_usec() - started) / 2000.0)
    print("params: set_params of six vec4 fields takes %.2f µs of GDScript" % best)
    assert_eq(comp.block.bytes, PushConstants.pack(layout, values), "a repeated fill packs the same bytes")
    values["crop"] = Color(1, 2, 3, 4)
    comp.set_params(values)
    assert_eq(comp.block.bytes, PushConstants.pack(layout, values), "a Color in a vec4 packs as the packer does")
