## A simulation grows into empty chunks inside its domain. A
## rule of reach r moves paint at most r texels a step, so the layer allocates
## the ring of empty chunks round the ones it holds before the first step and
## again every time a chunk's side over r steps have gone, kept to the domain
## the record holds, and Reset drops what the rings grew.
##
## The suite registers `shift_right`, which moves every cell one texel right a
## step, through a module's context as the sibling suite does, and seeds one texel at
## the centre of the middle chunk of a canvas five chunks square, so a texel
## that crosses a chunk and the second ring both fit inside the canvas.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

## Five chunks square, so the middle one has two rings round it on the canvas.
const CHUNKS := 5
const MIDDLE := Vector2i(2, 2)
const RED := Color(1.0, 0.25, 0.125, 1.0)
const TOLERANCE := 2.0e-3

var _registries: SaRegistries
var _easels: Array[SaEasel] = []


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()
    _registries = Fixtures.make_registries()
    var suite := _registries.context.for_module(&"k5-suite")
    suite.register_simulation_rule(&"shift_right", "Shift Right", "sara/simulation_test_rules", "shift_right", 1)


func after_each() -> void:
    for easel in _easels:
        easel.free()
    _easels.clear()


## The background of a canvas five chunks square holding the middle chunk
## alone, transparent but for one red texel at its centre, with the test rule on
## it and *domain* as its domain.
func _seeded(domain: Rect2i = Rect2i()) -> SaLayer:
    var easel := SaEasel.create_default(Vector2i(CHUNKS, CHUNKS) * SaChunk.SIZE)
    _easels.append(easel)
    var layer := easel.document.get_node("Background") as SaLayer
    for grid_pos: Vector2i in layer.chunks.keys():
        layer.chunks.erase(grid_pos)
    var texture := layer.get_or_create_chunk(MIDDLE).albedo()
    _fill(texture, {_centre(layer): RED})
    easel.document.set_active_layer(layer)
    var record := SaSimulation.put_on(layer, _registries.simulation_rules.find(&"shift_right"))
    assert_not_null(record, "The test rule goes on the layer")
    record.domain = domain
    return layer


## The centre of a chunk of *layer*, in its texels.
func _centre(layer: SaLayer) -> Vector2i:
    var side := _side(layer)
    var half := side >> 1
    return Vector2i(half, half)


## A chunk's side in texels, asked of the chunk rather than assumed.
func _side(layer: SaLayer) -> int:
    return (layer.chunks[MIDDLE] as SaChunk).pixel_size()


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


## Steps *layer* until its record has counted *count* steps.
func _step_to(layer: SaLayer, count: int) -> void:
    var document := layer.get_parent() as SaDocument
    var record := SaSimulation.record_of(layer)
    var taken := 0
    while record.steps < count and taken < count:
        if not SaSimulation.step(document, layer, _registries.simulation_rules):
            assert_true(false, "Step %d is taken" % record.steps)
            return
        taken += 1
    assert_eq(record.steps, count, "The record counts every step taken")


## The grid positions *layer* holds, sorted.
func _held(layer: SaLayer) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    out.assign(layer.chunks.keys())
    out.sort()
    return out


## Every grid position within *rings* of the middle chunk, sorted.
func _square(rings: int) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    for y in range(MIDDLE.y - rings, MIDDLE.y + rings + 1):
        for x in range(MIDDLE.x - rings, MIDDLE.x + rings + 1):
            out.append(Vector2i(x, y))
    out.sort()
    return out


func test_a_texel_crosses_into_the_ring_and_the_next_ring_grows_on_the_step_the_light_cone_gives() -> void:
    var layer := _seeded()
    var side := _side(layer)
    var centre := _centre(layer)
    assert_eq(_held(layer), [MIDDLE] as Array[Vector2i], "The seed is the middle chunk alone")
    _step_to(layer, 1)
    assert_eq(_held(layer), _square(1), "The first step grows the ring round it")
    _step_to(layer, side - centre.x)
    assert_true(
        _near(_texel(layer, MIDDLE + Vector2i.RIGHT, Vector2i(0, centre.y)), RED),
        "%d steps carry the texel to the first texel of the chunk beside" % (side - centre.x)
    )
    _step_to(layer, side)
    assert_eq(_held(layer), _square(1), "A chunk's side of steps grows no second ring")
    assert_true(
        _near(_texel(layer, MIDDLE + Vector2i.RIGHT, centre), RED),
        "and has moved the texel one chunk's width, to the centre of the chunk beside"
    )
    _step_to(layer, side + 1)
    assert_eq(_held(layer), _square(2), "The step after a chunk's side of them grows the second ring")
    assert_true(
        _near(_texel(layer, MIDDLE + Vector2i.RIGHT, centre + Vector2i.RIGHT), RED),
        "and the texel goes on past the chunk's width"
    )
    assert_eq(_texel(layer, MIDDLE, centre).a, 0.0, "Nothing is left where it was painted")


func test_a_domain_one_chunk_wide_grows_nothing_past_it() -> void:
    var column := Rect2i(Vector2i(MIDDLE.x * SaChunk.SIZE, 0), Vector2i(SaChunk.SIZE, CHUNKS * SaChunk.SIZE))
    var layer := _seeded(column)
    var side := _side(layer)
    _step_to(layer, side + 1)
    var held := _held(layer)
    var want: Array[Vector2i] = [MIDDLE + Vector2i.UP, MIDDLE, MIDDLE + Vector2i.DOWN]
    want.append_array([MIDDLE + Vector2i(0, -2), MIDDLE + Vector2i(0, 2)])
    want.sort()
    assert_eq(held, want, "Two rings in a column one chunk wide are the column")
    for grid_pos: Vector2i in held:
        assert_eq(grid_pos.x, MIDDLE.x, "%s is inside the domain" % grid_pos)
    assert_null(layer.get_field(MIDDLE + Vector2i.RIGHT), "The chunk the texel would have crossed into is not allocated")
    var edge := Vector2i(side - 1, _centre(layer).y)
    assert_eq(_texel(layer, MIDDLE, edge).a, 0.0, "and the texel went past the domain's edge rather than piling there")


func test_reset_drops_what_the_rings_grew_and_puts_back_the_seed() -> void:
    var layer := _seeded()
    var record := SaSimulation.record_of(layer)
    var side := _side(layer)
    _step_to(layer, side + 1)
    assert_eq(_held(layer), _square(2), "Two rings are held before the reset")
    assert_eq(record._second.size(), _square(2).size(), "with a second copy for each")
    var document := layer.get_parent() as SaDocument
    assert_true(SaSimulation.reset(document, layer), "Reset is taken")
    assert_eq(_held(layer), [MIDDLE] as Array[Vector2i], "Reset leaves the seed's chunks alone")
    assert_eq(record._second.keys(), [MIDDLE], "and the second copy of the seed's chunk alone")
    assert_true(_near(_texel(layer, MIDDLE, _centre(layer)), RED), "The texel is back where it was painted")
    _step_to(layer, 1)
    assert_eq(_held(layer), _square(1), "and the first step after it grows the first ring again")


func test_a_chunk_painted_between_rings_takes_its_ring_before_the_next_step() -> void:
    var layer := _seeded()
    _step_to(layer, 1)
    var corner := Vector2i(0, 0)
    _fill(layer.get_or_create_chunk(corner).albedo(), {Vector2i(_side(layer) - 1, 0): RED})
    _step_to(layer, 2)
    for grid_pos: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
        assert_not_null(layer.get_field(grid_pos), "%s is allocated round the painted chunk" % grid_pos)
    assert_true(_near(_texel(layer, Vector2i(1, 0), Vector2i.ZERO), RED), "so its paint crossed into the chunk beside")
    assert_eq(_held(layer).size(), _square(1).size() + 3, "and nothing else grew")
