## A neighbourhood pass is a list of steps. A layer of two
## greys side by side, dark then light, so the seam between its two chunks is a
## step edge, and the fixture's pass attached to it: a list of one reads the
## source through the previous binding, and a list of several shifts the red
## one texel right per middle step and keeps the source's green, which says the
## steps ran in order, each read the one before across the chunk seam, and the
## last still read the source.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const StepsFilter = preload("res://tests/fixtures/modules/steps-fixture/steps_filter.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"steps-fixture"
const KEY: StringName = &"steps-fixture.steps_fixture"
const DARK := Color(0.25, 0.25, 0.25, 1.0)
const LIGHT := Color(0.75, 0.75, 0.75, 1.0)
const ROW := 100

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null


func before_each() -> void:
    _easel = Bench.easel(Vector2i(2 * SaChunk.SIZE, SaChunk.SIZE))
    _doc = _easel.document
    _easel.compositor.filter_chain.registry.register(StepsFilter.new(), OWNER)
    _layer = _doc.get_node("Background") as SaLayer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)
    _layer.get_or_create_chunk(Vector2i(0, 0)).clear(DARK)
    _layer.get_or_create_chunk(Vector2i(1, 0)).clear(LIGHT)


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _layer = null


func _attach(steps: int) -> SaAttachedFilter:
    var record := SaFilterOps.new(_doc).attach(_layer, KEY, {"steps": steps})
    Bench.composite(_easel)
    return record


## The chain's answer at the document column *x* along [const ROW].
func _at(x: int) -> Color:
    var grid_pos := Vector2i(floori(float(x) / SaChunk.SIZE), 0)
    var chain := _easel.compositor.filter_chain
    var answer := chain.filtered(_layer, _layer.get_field(grid_pos), grid_pos, SaDocument.WHOLE_CHUNK)
    return Bench.texel(answer, Vector2i(x - grid_pos.x * SaChunk.SIZE, ROW))


func _kernels(recorded: SaNeighbourhoodPass) -> Array:
    return recorded.steps.map(func(step: SaNeighbourhoodPass.Step) -> String: return step.kernel)


func test_a_pass_recorded_with_one_kernel_is_a_list_of_one() -> void:
    var recorded := SaNeighbourhoodPass.new("blur", "blur", {"radius": 4}, 4)
    assert_eq(_kernels(recorded), ["blur"], "The one-kernel spelling records a list of one")
    assert_eq(recorded.steps[0].params, recorded.params, "whose params are the pass's")
    assert_eq(recorded.then("down", {"radius": 2}), recorded, "A step is added to the pass it answers")
    assert_eq(_kernels(recorded), ["blur", "down"], "after the first")
    assert_eq(recorded.halo(), 4, "and the halo stays the pass's radius, the reach of every step together")
    var layout := [{"name": "radius"}, {"name": "origin"}]
    assert_eq(
        recorded.params_for(layout, Vector2i(3, 5), 4, Vector2i.ZERO, Vector2i.ZERO, recorded.steps[1].params)["radius"],
        2,
        "A step's params are its own"
    )
    assert_eq(recorded.params_for(layout, Vector2i(3, 5), 4)["radius"], 4, "and a pass of one reads the first's")


func test_a_pass_that_reads_the_whole_node_takes_no_second_step() -> void:
    var lines: Array[String] = []
    var announcing := SaProblems.announce
    SaProblems.announce = false
    # A sink is handed every line kept since the last one, and the suites run
    # before this one keep their own, so those are set aside and put back.
    var kept_faults := SaProblems.pending
    var kept_refusals := SaProblems.pending_refusals
    SaProblems.pending = PackedStringArray()
    SaProblems.pending_refusals = PackedStringArray()
    SaProblems.attach_sink(func(line: String, _kind: SaProblems.Kind) -> void: lines.append(line))
    var recorded := SaNeighbourhoodPass.new("shift", "shift", {}, SaNeighbourhoodPass.WHOLE_NODE)
    recorded.then("down", {})
    SaProblems.detach_sink()
    SaProblems.pending = kept_faults
    SaProblems.pending_refusals = kept_refusals
    SaProblems.announce = announcing
    assert_eq(_kernels(recorded), ["shift"], "A whole-node pass keeps its one kernel")
    assert_eq(lines.size(), 1, "and says so once, %s" % [lines])


func test_the_context_records_the_steps_the_filter_ran() -> void:
    var record := _attach(4)
    assert_true(record.cached_pass is SaNeighbourhoodPass, "The fixture recorded a neighbourhood pass")
    if record.cached_pass is SaNeighbourhoodPass:
        var recorded := record.cached_pass as SaNeighbourhoodPass
        assert_eq(_kernels(recorded), ["shift", "shift", "shift", "last"], "listing every step in the order it was added")
        assert_eq(recorded.halo(), 3, "padded by the reach of every step together")


func test_a_list_of_one_reads_the_source_through_the_previous_binding() -> void:
    _attach(1)
    for x: int in [SaChunk.SIZE - 1, SaChunk.SIZE]:
        var got := _at(x)
        var want := DARK if x < SaChunk.SIZE else LIGHT
        assert_almost_eq(got.r, want.r, 0.0001, "At %d the previous binding is the source, %s" % [x, got])
        assert_almost_eq(got.g, want.g, 0.0001, "and so is binding 0, %s" % got)


func test_the_steps_run_in_order_each_reading_the_one_before() -> void:
    # Three middle steps, each shifting right by one: the dark reaches three
    # texels past the seam, and the green is the source's own, unshifted.
    _attach(4)
    var seam := SaChunk.SIZE
    for x: int in [seam - 1, seam, seam + 1, seam + 2]:
        assert_almost_eq(_at(x).r, DARK.r, 0.0001, "At %d the red is the dark, shifted over the seam, %s" % [x, _at(x)])
    assert_almost_eq(_at(seam + 3).r, LIGHT.r, 0.0001, "and at three past the seam the light is back, %s" % _at(seam + 3))
    assert_almost_eq(_at(seam).g, LIGHT.g, 0.0001, "The last step read the source itself, not the chain, %s" % _at(seam))
    assert_almost_eq(_at(seam - 1).g, DARK.g, 0.0001, "on both sides of the seam, %s" % _at(seam - 1))


func test_one_shot_writes_the_same_texels() -> void:
    var filter := StepsFilter.new()
    filter.set_parameters({"steps": 4})
    var ctx := SaFilterContext.new(_doc, _layer, OWNER, filter.title(), false)
    assert_true(SaFilterApply.call_run(filter, ctx), "The run records a pass")
    assert_true(SaFilterApply.apply(ctx, "Steps Fixture"), "Apply writes it")
    var right := _layer.get_field(Vector2i(1, 0))
    assert_almost_eq(
        Bench.texel(right, Vector2i(2, ROW)).r, DARK.r, 0.0001, "Three middle steps carry the dark three texels over the seam"
    )
    assert_almost_eq(Bench.texel(right, Vector2i(3, ROW)).r, LIGHT.r, 0.0001, "and no further")
