## The gradient's first move of a session cost 84 ms where
## every later one cost 32 ms. Two things paid for it. The ramp's texels asked
## for the document's gamut matrix at every stop of every one of 1024 texels,
## and the pass built its kernel at the document's depth on that move.
##
## The texels are held to the walk they replaced, value for value, because the
## lookup the kernel samples must not move by a bit for being built faster. The
## warm is held the way the brush's suite holds its own: by the pass's own
## `compute`, which a suite that ran earlier cannot have pointed anywhere.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const StateGradientScript = preload("res://modules/sara-base-modules/base/gradient/state_gradient.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const F16 := RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
const F32 := RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT

## The easels the tools paint on, freed after each test because an easel is a
## node that no tree owns here.
var _easels: Array[SaEasel] = []


func after_each() -> void:
    for easel: SaEasel in _easels:
        easel.free()
    _easels.clear()


## A ramp of four stops, two of them in one place, so the walk crosses every
## case it has: a pair, a hard edge, and the ends.
func _ramp() -> SaColorRamp:
    var ramp := SaColorRamp.from_pair(Color(1.0, 0.0, 0.0, 1.0), Color(0.1, 0.2, 0.9, 0.0))
    ramp.add_stop(0.4, Color(0.2, 0.9, 0.3, 0.5))
    ramp.add_stop(0.4, Color(1.2, 0.8, -0.1, 1.0))
    return ramp


## The texels as they were built: every texel converts its two
## stops through `to_oklab`, which asks *space* for its matrix each time.
func _texels_the_old_way(ramp: SaColorRamp, width: int, space: SaColorSpace) -> PackedFloat32Array:
    var data := PackedFloat32Array()
    for i in width:
        var position := clampf((float(i) + 0.5) / float(width), 0.0, 1.0)
        var lower := 0
        while lower < ramp.size() - 1 and ramp.position_of(lower + 1) <= position:
            lower += 1
        var lab := SaColorRamp.to_oklab(ramp.color_of(lower), space)
        if lower < ramp.size() - 1:
            var upper := SaColorRamp.to_oklab(ramp.color_of(lower + 1), space)
            var from := ramp.position_of(lower)
            var to := ramp.position_of(lower + 1)
            lab = upper if to - from <= 0.0 else lab.lerp(upper, (position - from) / (to - from))
        data.append_array([lab.r, lab.g, lab.b, lab.a])
    return data


## A gradient tool on a document at *depth*, the way the machine binds one:
## built first, handed its surface after.
func _gradient_on(depth: SaColorSpace.Depth) -> RefCounted:
    var space := SaColorSpace.srgb().with_depth(depth)
    var easel := SaEasel.create_default(Vector2i(256, 256), null, space)
    _easels.append(easel)
    var tool := StateGradientScript.new()
    tool.surface = SaSurface.create(&"test", easel, Fixtures.FakeView.new())
    return tool


## Whether the compiler holds *shader* built at *format*.
func _built(shader: String, format: int) -> bool:
    var variants: Dictionary = GlobalShaderCompiler._format_variants.get(GlobalShaderCompiler.resolve_shader_name(shader), {})
    var made: Array = variants.get(GlobalShaderCompiler.source.variant_key(format), [])
    return not made.is_empty() and (made[0] as RID).is_valid()


func test_the_texels_are_the_walk_they_replaced_in_every_gamut() -> void:
    var ramp := _ramp()
    for space: SaColorSpace in [null, SaColorSpace.srgb(), SaColorSpace.display_p3(), SaColorSpace.rec2020()]:
        var name := "no document" if space == null else String(space.id)
        var built := ramp.to_oklab_texels(64, space)
        var wanted := _texels_the_old_way(ramp, 64, space)
        assert_eq(built.size(), wanted.size(), "%s: one texel each" % name)
        assert_true(built == wanted, "%s: every texel is the old walk's to the bit" % name)


func test_a_texel_is_what_oklab_at_reads_there() -> void:
    var ramp := _ramp()
    var space := SaColorSpace.display_p3()
    var built := ramp.to_oklab_texels(16, space)
    for i in 16:
        var lab := ramp.oklab_at((float(i) + 0.5) / 16.0, space)
        assert_true(
            PackedFloat32Array([lab.r, lab.g, lab.b, lab.a]) == built.slice(i * 4, i * 4 + 4),
            "texel %d is the ramp read at its centre" % i
        )


func test_the_pass_is_at_its_documents_depth_before_the_first_move() -> void:
    var tool := _gradient_on(SaColorSpace.Depth.F16)
    tool.warm()
    var pipelines: SaCompute.Pipelines = tool._pass_for(tool.surface.get_document())._compute.pipelines
    assert_eq(pipelines.storage_format, F16, "Warming points the pass's kernel at the F16 document's depth")
    assert_false(pipelines.kernels.is_empty(), "with its pipeline made")
    assert_true(pipelines.kernels[0].is_valid(), "and valid")
    assert_true(_built("gradient", F16), "The compiler holds `gradient` built at F16")


func test_a_tool_with_no_document_builds_nothing() -> void:
    var tool := StateGradientScript.new()
    tool.warm()
    assert_null(tool._pass, "A gradient built alone makes no pass to warm")


## File > New, File > Open, Assign and Convert announce the space on the bus,
## and the gradient builds its own document's announced depth without touching
## its pass, which only [method warm] moves.
func test_an_announced_depth_is_built_and_the_pass_left_where_it_was() -> void:
    var tool := _gradient_on(SaColorSpace.Depth.F32)
    tool.warm()
    tool.surface.get_document().color_space = SaColorSpace.srgb().with_depth(SaColorSpace.Depth.F16)
    assert_true(_built("gradient", F16), "The announced depth's `gradient` is built")
    var pipelines: SaCompute.Pipelines = tool._pass_for(tool.surface.get_document())._compute.pipelines
    assert_eq(pipelines.storage_format, F32, "and the pass still points at its own document's depth")
