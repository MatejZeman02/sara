## A simulation steps a paint layer's own paint, reading its
## halo from the previous state of the chunks beside it, writing a second copy
## and swapping, and Reset puts back what was painted.
##
## The suite registers two rules of its own through a module's context,
## `shift_right`, which moves every cell one texel right a step, and `scatter`,
## which writes the hash of the cell and the step. A texel moved across a chunk
## edge lands where the count of steps says only when the halo reads the chunk
## beside it as it was before the step, and a picture stepped twice on two
## documents is the same only when nothing in a step depends on the order the
## GPU ran it in. Spread comes from the base module through the same call.
extends "res://tests/test_framework.gd"

const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

## Two chunks side by side, so a texel has a chunk edge to cross.
const SIZE := Vector2i(512, 256)
const RED := Color(1.0, 0.25, 0.125, 1.0)
const OCHRE := Color(0.8, 0.4, 0.2, 1.0)
const ROW := 10
const TOLERANCE := 2.0e-3

var _registries: SaRegistries
var _easels: Array[SaEasel] = []


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()
    _registries = Fixtures.make_registries()
    var suite := _registries.context.for_module(&"k3-suite")
    suite.register_simulation_rule(&"shift_right", "Shift Right", "sara/simulation_test_rules", "shift_right", 1)
    suite.register_simulation_rule(&"scatter", "Scatter", "sara/simulation_test_rules", "scatter", 0)
    var base := BaseModule.new()
    base.register(_registries.context.for_module(base.get_id()))


func after_each() -> void:
    for easel in _easels:
        easel.free()
    _easels.clear()


## A canvas of two chunks whose background holds both, transparent, so the
## layer the rule steps is the one the suite paints.
func _layer() -> SaLayer:
    var easel := SaEasel.create_default(SIZE)
    _easels.append(easel)
    var layer := easel.document.get_node("Background") as SaLayer
    for grid_pos: Vector2i in layer.chunks.keys():
        layer.chunks.erase(grid_pos)
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0)]:
        _fill(layer.get_or_create_chunk(grid_pos).albedo(), {})
    easel.document.set_active_layer(layer)
    return layer


## *texture* transparent but for the texels of *texels*, position to colour.
func _fill(texture: SaTexture, texels: Dictionary) -> void:
    var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    var image := Image.create_empty(texture.size.x, texture.size.y, false, Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF)
    image.fill(Color(0.0, 0.0, 0.0, 0.0))
    for at: Vector2i in texels:
        image.set_pixelv(at, texels[at])
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())


func _texel(layer: SaLayer, grid_pos: Vector2i, at: Vector2i) -> Color:
    var texture := layer.get_field(grid_pos)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


func _near(got: Color, want: Color) -> bool:
    return (
        absf(got.r - want.r) <= TOLERANCE
        and absf(got.g - want.g) <= TOLERANCE
        and absf(got.b - want.b) <= TOLERANCE
        and absf(got.a - want.a) <= TOLERANCE
    )


func _put(layer: SaLayer, rule_key: StringName, values: Dictionary = {}) -> SaSimulationRecord:
    var found := _registries.simulation_rules.find(rule_key)
    assert_not_null(found, "%s is registered" % rule_key)
    return SaSimulation.put_on(layer, found, values)


func _step(layer: SaLayer) -> void:
    var document := layer.get_parent() as SaDocument
    assert_true(SaSimulation.step(document, layer, _registries.simulation_rules), "The step is taken")


func test_a_texel_beside_a_chunks_right_edge_steps_into_the_next_chunk_and_reset_puts_it_back() -> void:
    var layer := _layer()
    var side := layer.get_field(Vector2i(0, 0)).size.x
    var painted := Vector2i(side - 2, ROW)
    _fill(layer.get_field(Vector2i(0, 0)), {painted: RED})
    var record := _put(layer, &"shift_right")
    assert_not_null(record, "The rule goes on a paint layer")
    assert_true(SaSimulation.record_of(layer) == record, "and the layer holds its record")
    for _i in 3:
        _step(layer)
    assert_eq(record.steps, 3, "Three steps are counted")
    assert_true(
        _near(_texel(layer, Vector2i(1, 0), Vector2i(1, ROW)), RED), "Three to the right is the next chunk's second texel"
    )
    for x: int in [side - 2, side - 1]:
        assert_eq(_texel(layer, Vector2i(0, 0), Vector2i(x, ROW)).a, 0.0, "Nothing is left at %d" % x)
    for x: int in [0, 2]:
        assert_eq(_texel(layer, Vector2i(1, 0), Vector2i(x, ROW)).a, 0.0, "Nothing is at %d of the next chunk" % x)
    var document := layer.get_parent() as SaDocument
    assert_true(SaSimulation.reset(document, layer), "Reset is taken")
    assert_eq(record.steps, 0, "and counts from nought again")
    assert_true(_near(_texel(layer, Vector2i(0, 0), painted), RED), "The texel is back where it was painted")
    assert_eq(_texel(layer, Vector2i(1, 0), Vector2i(1, ROW)).a, 0.0, "and gone from where it went")


func test_two_documents_step_one_seed_into_one_picture_and_the_second_copy_goes_with_the_record() -> void:
    var layers: Array[SaLayer] = [_layer(), _layer()]
    for layer in layers:
        _fill(layer.get_field(Vector2i(0, 0)), {Vector2i(40, ROW): RED, Vector2i(41, ROW + 1): OCHRE})
        # The document's mask of one texel, made once and the document's own.
        (layer.get_parent() as SaDocument).selection.everything()
    var held_before := SaTexture.allocated_bytes
    var pictures: Array[PackedByteArray] = []
    for layer in layers:
        _put(layer, &"scatter")
        _step(layer)
        var once := _bytes(layer)
        _step(layer)
        var twice := _bytes(layer)
        assert_false(once == twice, "The second step is a picture of its own")
        pictures.append(twice)
    assert_eq(pictures[0], pictures[1], "Two documents stepped twice from one seed hold the same texels")
    var a := _texel(layers[0], Vector2i(0, 0), Vector2i(3, 3))
    var b := _texel(layers[0], Vector2i(0, 0), Vector2i(4, 3))
    assert_false(a == b, "and the hash differs from one cell to the next")

    var record := SaSimulation.record_of(layers[0])
    var second: Array[WeakRef] = []
    for grid_pos: Vector2i in record._second:
        second.append(weakref(record._second[grid_pos]))
    assert_eq(second.size(), 2, "A second copy is held for each chunk")
    record = null
    SaSimulation.take_off(layers[0])
    assert_null(layers[0].simulation, "The record goes")
    for gone in second:
        assert_null(gone.get_ref(), "and its second copy is freed with it")
    SaSimulation.take_off(layers[1])
    assert_eq(SaTexture.allocated_bytes, held_before, "Nothing a record held is held once both are off")


## Both chunks of *layer*'s albedo, as bytes.
func _bytes(layer: SaLayer) -> PackedByteArray:
    var rd := GlobalShaderCompiler.get_rd()
    var left := rd.texture_get_data(layer.get_field(Vector2i(0, 0)).rid, 0)
    return left + rd.texture_get_data(layer.get_field(Vector2i(1, 0)).rid, 0)


func test_spread_steps_one_texel_into_its_four_neighbours_and_moves_no_paint_in_or_out() -> void:
    var layer := _layer()
    var at := Vector2i(100, 100)
    _fill(layer.get_field(Vector2i(0, 0)), {at: OCHRE})
    var record := _put(layer, &"spread")
    assert_not_null(record, "Spread goes on from the base module")
    assert_eq(record.params, {}, "with no values of the layer's own")
    _step(layer)
    var sum := Color(0.0, 0.0, 0.0, 0.0)
    var flow := 0.2
    for offset: Vector2i in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
        var got := _texel(layer, Vector2i(0, 0), at + offset)
        var weight := 1.0 - 4.0 * flow if offset == Vector2i.ZERO else flow
        assert_true(absf(got.a - OCHRE.a * weight) <= TOLERANCE, "%s holds %s of the paint, %s" % [offset, weight, got.a])
        sum += Color(got.r * got.a, got.g * got.a, got.b * got.a, got.a)
    assert_true(_near(sum, OCHRE), "The weights round it sum to what was painted, %s" % sum)
    assert_eq(_texel(layer, Vector2i(0, 0), at + Vector2i(1, 1)).a, 0.0, "and a diagonal takes nothing in one step")
