## The brush builds its stroke's kernels at the depth of the
## document it paints before that document's first stroke, not on the first
## dab, which is where an F16 document spent 72 ms building `dab` at F16.
##
## A build, once made, is the compiler's for the rest of the session, so a suite
## that ran earlier may already have made one of these. What this holds without
## depending on the order is the brush's own `compute`: it is pointed at the
## document's depth before any stroke, and after one, which is the pipeline the
## first dab would otherwise have made.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const F16 := RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
const F32 := RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT

## The easels the brushes paint on, freed after each test because an easel is a
## node that no tree owns here.
var _easels: Array[SaEasel] = []


func after_each() -> void:
    for easel: SaEasel in _easels:
        easel.free()
    _easels.clear()


## A brush on a document at *depth*, the way the machine binds one: built
## first, handed its surface after.
func _brush_on(depth: SaColorSpace.Depth) -> RefCounted:
    var space := SaColorSpace.srgb().with_depth(depth)
    var easel := SaEasel.create_default(Vector2i(256, 256), null, space)
    _easels.append(easel)
    var brush := StateBrushScript.new()
    brush.surface = SaSurface.create(&"test", easel, Fixtures.FakeView.new())
    return brush


## Whether the compiler holds *shader* built at *format*.
func _built(shader: String, format: int) -> bool:
    var variants: Dictionary = GlobalShaderCompiler._format_variants.get(GlobalShaderCompiler.resolve_shader_name(shader), {})
    var made: Array = variants.get(GlobalShaderCompiler.source.variant_key(format), [])
    return not made.is_empty() and (made[0] as RID).is_valid()


func test_the_brush_is_at_its_documents_depth_before_the_first_stroke() -> void:
    var brush := _brush_on(SaColorSpace.Depth.F16)
    assert_eq(brush.compute.pipelines.storage_format, F32, "A brush is built at the default depth, before it has a document")
    brush.warm()
    assert_eq(brush.compute.pipelines.storage_format, F16, "and warming it points the dab at the F16 document's depth")
    assert_false(brush.compute.pipelines.kernels.is_empty(), "with its pipeline made")
    assert_true(brush.compute.pipelines.kernels[0].is_valid(), "and valid")
    assert_true(_built("dab", F16), "The compiler holds `dab` built at F16")
    assert_true(_built("smudge_pickup", F16), "and the smudge pickup too, for a smudge stroke's first dab")


func test_a_stroke_leaves_the_next_one_at_the_documents_depth() -> void:
    var brush := _brush_on(SaColorSpace.Depth.F16)
    brush.warm()
    brush.reset()
    assert_eq(
        brush.compute.pipelines.storage_format,
        F16,
        "The fresh `compute` a pen lift makes is at the document's depth, not the default's"
    )


func test_a_brush_with_no_document_builds_nothing() -> void:
    var brush := StateBrushScript.new()
    brush.warm()
    assert_eq(brush.compute.pipelines.storage_format, F32, "A brush built alone stays at the default depth")


## File > New, File > Open, Assign and Convert all set the space through the
## document's setter, which announces it. The brush builds its own document's
## announced depth and leaves its `compute` alone, which only [method warm] moves.
func test_an_announced_depth_is_built_and_the_brush_left_where_it_was() -> void:
    var brush := _brush_on(SaColorSpace.Depth.F32)
    brush.warm()
    brush.surface.get_document().color_space = SaColorSpace.srgb().with_depth(SaColorSpace.Depth.F16)
    assert_true(_built("dab", F16), "The announced depth's `dab` is built")
    assert_true(_built("smudge_pickup", F16), "and its pickup")
    assert_eq(brush.compute.pipelines.storage_format, F32, "and the brush still points at its own document's depth")
