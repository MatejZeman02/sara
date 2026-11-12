## A stroke on a layer that runs a simulation is a history step, and its undo
## and its redo move the seed as the stroke did, so Reset after an undo leaves
## the stroke out and Reset after a redo puts it back.
##
## The suite registers `shift_right`, which moves every cell one texel right a
## step, through a module's context as the sibling suite does. The stroke is one red
## texel written as a pixel step through `SaDocument.record_pixel_step`, the
## call every stroke ends in, and the undo and the redo are the document's own.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(512, 256)
const RED := Color(1.0, 0.25, 0.125, 1.0)
const CLEAR := Color(0.0, 0.0, 0.0, 0.0)
const PAINTED := Vector2i(10, 10)
const STEPS := 5
const TOLERANCE := 2.0e-3

var _registries: SaRegistries
var _easels: Array[SaEasel] = []


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()
    _registries = Fixtures.make_registries()
    var suite := _registries.context.for_module(&"h3702-suite")
    suite.register_simulation_rule(&"shift_right", "Shift Right", "sara/simulation_test_rules", "shift_right", 1)


func after_each() -> void:
    for easel in _easels:
        easel.free()
    _easels.clear()


## A canvas of two transparent chunks on the background, active, with the rule
## put on it before anything is painted.
func _layer() -> SaLayer:
    var easel := SaEasel.create_default(SIZE)
    _easels.append(easel)
    var layer := easel.document.get_node("Background") as SaLayer
    for grid_pos: Vector2i in layer.chunks.keys():
        layer.chunks.erase(grid_pos)
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0)]:
        _write(layer.get_or_create_chunk(grid_pos).albedo(), {})
    easel.document.set_active_layer(layer)
    assert_not_null(SaSimulation.put_on(layer, _registries.simulation_rules.find(&"shift_right")), "The rule goes on")
    return layer


## The stroke: what chunk (0, 0) held is kept as the step's state, the red
## texel is written, and the step is recorded as a stroke's is.
func _stroke(layer: SaLayer) -> void:
    var document := layer.get_parent() as SaDocument
    var chunk := layer.get_or_create_chunk(Vector2i.ZERO)
    var state := {Vector2i.ZERO: SaChunkDelta.capture(chunk, Rect2i(PAINTED, Vector2i.ONE))}
    _write(chunk.albedo(), {PAINTED: RED})
    document.record_pixel_step("Brush Stroke", layer, state)


## *texture* transparent but for the texels of *texels*, position to colour.
func _write(texture: SaTexture, texels: Dictionary) -> void:
    var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    var image := Image.create_empty(texture.size.x, texture.size.y, false, Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF)
    image.fill(CLEAR)
    for at: Vector2i in texels:
        image.set_pixelv(at, texels[at])
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())


## The colour at *at* of chunk (0, 0), transparent where the layer holds no
## chunk there.
func _texel(layer: SaLayer, at: Vector2i) -> Color:
    var texture := layer.get_field(Vector2i.ZERO)
    if texture == null:
        return CLEAR
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


func _near(got: Color, want: Color) -> bool:
    return (
        absf(got.r - want.r) <= TOLERANCE
        and absf(got.g - want.g) <= TOLERANCE
        and absf(got.b - want.b) <= TOLERANCE
        and absf(got.a - want.a) <= TOLERANCE
    )


func _step(layer: SaLayer, count: int) -> void:
    var document := layer.get_parent() as SaDocument
    for _i in count:
        assert_true(SaSimulation.step(document, layer, _registries.simulation_rules), "The step is taken")


func _reset(layer: SaLayer) -> void:
    assert_true(SaSimulation.reset(layer.get_parent() as SaDocument, layer), "Reset is taken")


func test_reset_after_an_undone_stroke_that_stepped_reads_the_texel_transparent() -> void:
    var layer := _layer()
    var document := layer.get_parent() as SaDocument
    var record := SaSimulation.record_of(layer)
    _stroke(layer)
    _step(layer, STEPS)
    var moved := PAINTED + Vector2i(STEPS, 0)
    assert_true(_near(_texel(layer, moved), RED), "five steps moved the stroke five texels right, got %s" % _texel(layer, moved))
    assert_true(document.undo_redo.undo(), "the stroke is undone")
    assert_true(_near(_texel(layer, PAINTED), CLEAR), "the undo gave the stroke's texel back, got %s" % _texel(layer, PAINTED))
    assert_eq(record.steps, 0, "the undo is the seed from here, so the count goes back to nought")
    # The undo exchanges only the rectangle the stroke painted, so the paint
    # five steps carried out of it stays on the canvas, and Reset returns to
    # the canvas as the undo left it, that included.
    var left := _texel(layer, moved)
    _reset(layer)
    assert_true(_near(_texel(layer, PAINTED), CLEAR), "Reset leaves the undone stroke out, got %s" % _texel(layer, PAINTED))
    assert_true(_near(_texel(layer, moved), left), "and returns to what the undo left beside it, got %s" % _texel(layer, moved))
    # The redo puts back what the undo took off, the stroke's rectangle as five
    # steps left it, and Reset keeps the canvas the redo leaves.
    assert_true(document.undo_redo.redo(), "the stroke is redone")
    var redone := _texel(layer, PAINTED)
    _reset(layer)
    var got := _texel(layer, PAINTED)
    assert_true(_near(got, redone), "Reset after the redo keeps what the redo put back, got %s" % got)
    assert_true(_near(_texel(layer, moved), left), "and what stood beside it, got %s" % _texel(layer, moved))


func test_reset_after_a_redone_stroke_reads_the_texel_painted() -> void:
    var layer := _layer()
    var document := layer.get_parent() as SaDocument
    _stroke(layer)
    assert_true(document.undo_redo.undo(), "the stroke is undone")
    _reset(layer)
    var undone := _texel(layer, PAINTED)
    assert_true(_near(undone, CLEAR), "Reset after the undo leaves the stroke out, got %s" % undone)
    assert_true(document.undo_redo.redo(), "the stroke is redone")
    _step(layer, STEPS)
    assert_true(_near(_texel(layer, PAINTED), CLEAR), "the steps moved the redone stroke away, got %s" % _texel(layer, PAINTED))
    _reset(layer)
    var got := _texel(layer, PAINTED)
    assert_true(_near(got, RED), "Reset after the redo puts the stroke back where it was painted, got %s" % got)
