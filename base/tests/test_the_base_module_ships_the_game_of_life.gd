## The base module ships the Game of Life, a simulation rule
## registered through the call a stranger's rule makes (hard rule 6).
##
## A glider painted texel by texel is the same five cells four steps on, one
## cell down and one right, and a blinker stands on end after one step and is
## back as painted after two. Both hold only when every cell counts its eight
## neighbours as they stood before the step and is born on three and lives on
## two or three. The glider starts against a chunk's right edge, so its last
## cell is born in the next chunk from the halo, diagonals and all. The colours
## are sums of halves, so a mean of three alike is exact and a picture reads
## back as painted to the byte.
extends "res://tests/test_framework.gd"

const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

## Two chunks side by side, so the glider has a chunk edge to cross.
const SIZE := Vector2i(512, 256)
const GREEN := Color(0.25, 0.75, 0.5, 1.0)
const RED := Color(0.75, 0.25, 0.125, 0.75)
const BLUE := Color(0.125, 0.25, 0.75, 1.0)
const CLEAR := Color(0.0, 0.0, 0.0, 0.0)
const TOLERANCE := 2.0e-3

## The glider that travels down and right, as cells from its corner.
const GLIDER: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)]

## Where the blinker's middle cell is painted, well inside the first chunk.
const BLINKER_AT := Vector2i(100, 50)

var _registries: SaRegistries
var _base: BaseModule
var _easels: Array[SaEasel] = []


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()
    _registries = Fixtures.make_registries()
    _base = BaseModule.new()
    _base.register(_registries.context.for_module(_base.get_id()))


func after_each() -> void:
    for easel in _easels:
        easel.free()
    _easels.clear()


## A canvas of two chunks whose background holds both, transparent, so the
## layer Life steps holds only what the suite paints.
func _layer() -> SaLayer:
    var easel := SaEasel.create_default(SIZE)
    _easels.append(easel)
    var layer := easel.document.get_node("Background") as SaLayer
    for grid_pos: Vector2i in layer.chunks.keys():
        layer.chunks.erase(grid_pos)
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0)]:
        _write(layer.get_or_create_chunk(grid_pos).albedo(), {})
    easel.document.set_active_layer(layer)
    return layer


## The side of one of *layer*'s chunks in texels, asked of the chunk rather
## than assumed (hard rule 3).
func _side(layer: SaLayer) -> int:
    return (layer.chunks[Vector2i(0, 0)] as SaChunk).pixel_size()


## *texture* transparent but for *texels*, chunk-local position to colour.
func _write(texture: SaTexture, texels: Dictionary) -> void:
    var image := Image.create_empty(texture.size.x, texture.size.y, false, _image_format(texture))
    image.fill(CLEAR)
    for at: Vector2i in texels:
        image.set_pixelv(at, texels[at])
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())


func _image_format(texture: SaTexture) -> Image.Format:
    return Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF


## *layer* holding *cells*, layer position to colour, and nothing else.
func _paint(layer: SaLayer, cells: Dictionary) -> void:
    var side := _side(layer)
    var by_chunk: Dictionary[Vector2i, Dictionary] = {Vector2i(0, 0): {}, Vector2i(1, 0): {}}
    for at: Vector2i in cells:
        @warning_ignore("integer_division")
        by_chunk[at / side][at % side] = cells[at]
    for grid_pos: Vector2i in by_chunk:
        _write(layer.get_field(grid_pos), by_chunk[grid_pos])


## Every texel of *layer* that holds any paint, layer position to colour.
## Each chunk's picture says where its paint lies, and only that rectangle is
## read texel by texel.
func _held(layer: SaLayer) -> Dictionary[Vector2i, Color]:
    var side := _side(layer)
    var out: Dictionary[Vector2i, Color] = {}
    for grid_pos: Vector2i in layer.chunks:
        var texture := layer.get_field(grid_pos)
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        var image := Image.create_from_data(texture.size.x, texture.size.y, false, _image_format(texture), bytes)
        var used := image.get_used_rect()
        for y in range(used.position.y, used.end.y):
            for x in range(used.position.x, used.end.x):
                var colour := image.get_pixel(x, y)
                if colour.a != 0.0:
                    out[grid_pos * side + Vector2i(x, y)] = colour
    return out


## *cells* moved by *offset*, each in *colour*.
func _at(cells: Array, offset: Vector2i, colour: Color) -> Dictionary[Vector2i, Color]:
    var out: Dictionary[Vector2i, Color] = {}
    for cell: Vector2i in cells:
        out[cell + offset] = colour
    return out


func _put(layer: SaLayer, values: Dictionary = {}) -> SaSimulationRecord:
    var found := _registries.simulation_rules.find(&"life")
    assert_not_null(found, "Life is registered")
    return SaSimulation.put_on(layer, found, values)


func _step(layer: SaLayer, count: int = 1) -> void:
    var document := layer.get_parent() as SaDocument
    for _i in count:
        assert_true(SaSimulation.step(document, layer, _registries.simulation_rules), "The step is taken")


func _near(got: Color, want: Color) -> bool:
    return (
        absf(got.r - want.r) <= TOLERANCE
        and absf(got.g - want.g) <= TOLERANCE
        and absf(got.b - want.b) <= TOLERANCE
        and absf(got.a - want.a) <= TOLERANCE
    )


func test_life_comes_from_the_base_module_with_conways_counts() -> void:
    var found := _registries.simulation_rules.find(&"life")
    assert_not_null(found, "The base module registers Life")
    assert_eq(found.label, "Life", "under the name the painter reads")
    assert_eq(found.shader, "sara-base-modules/life", "its kernel in the base module's own file")
    assert_eq(found.reach, 1, "reading its eight neighbours, a reach of one")
    assert_eq(found.defaults, {"birth": 3, "survival": 23}, "born on three and living on two or three, Conway's")
    assert_true(GlobalShaderCompiler.get_kernel_index(found.shader, found.kernel) >= 0, "and its kernel compiles")
    _registries.simulation_rules.unregister_module(_base.get_id())
    assert_null(_registries.simulation_rules.find(&"life"), "It goes with the module, as a stranger's rule does")


func test_a_glider_is_one_cell_down_and_right_at_step_four() -> void:
    var layer := _layer()
    # Its right column on the chunk's last texel, so the step that carries it
    # on is born in the next chunk.
    var corner := Vector2i(_side(layer) - 3, 100)
    var painted := _at(GLIDER, corner, GREEN)
    _paint(layer, painted)
    var record := _put(layer)
    assert_not_null(record, "Life goes on a paint layer")
    assert_eq(record.params, {}, "with no counts of the layer's own")
    _step(layer, 2)
    var halfway := _held(layer)
    assert_eq(halfway.size(), 5, "Two steps on it still has five cells")
    assert_false(halfway == painted, "in another phase")
    _step(layer, 2)
    assert_eq(record.steps, 4, "Four steps are counted")
    var moved := _at(GLIDER, corner + Vector2i(1, 1), GREEN)
    assert_eq(_held(layer), moved, "At step four the glider is one cell down and one right, in its colour, and nothing else")
    assert_true(moved.has(Vector2i(_side(layer), 102)), "its right column in the next chunk")


func test_a_blinker_stands_on_end_and_is_back_as_painted_at_step_two() -> void:
    var layer := _layer()
    var painted := _at([Vector2i.LEFT, Vector2i.ZERO, Vector2i.RIGHT], BLINKER_AT, GREEN)
    _paint(layer, painted)
    var seed_bytes := _bytes(layer)
    _put(layer)
    _step(layer)
    assert_eq(_held(layer), _at([Vector2i.UP, Vector2i.ZERO, Vector2i.DOWN], BLINKER_AT, GREEN), "One step stands it on end")
    _step(layer)
    assert_eq(_held(layer), painted, "and two lay it down again")
    assert_eq(_bytes(layer), seed_bytes, "every texel as it was painted")


func test_the_birth_and_survival_counts_are_parameters() -> void:
    var standing := _at([Vector2i.UP, Vector2i.ZERO, Vector2i.DOWN], BLINKER_AT, GREEN)
    var cases := [
        [{"survival": 0}, _at([Vector2i.UP, Vector2i.DOWN], BLINKER_AT, GREEN), "With no survival count the middle dies"],
        [{"birth": 0}, _at([Vector2i.ZERO], BLINKER_AT, GREEN), "With no birth count only the middle lives on"],
        [{"survival": 32}, standing, "The digits are counts in any order"],
        [{"birth": 3, "survival": 23}, standing, "Conway's counts given are the defaults"],
    ]
    for case: Array in cases:
        var layer := _layer()
        _paint(layer, _at([Vector2i.LEFT, Vector2i.ZERO, Vector2i.RIGHT], BLINKER_AT, GREEN))
        var record := _put(layer, case[0])
        assert_eq(record.params, case[0], "The layer keeps the counts it was given")
        _step(layer)
        assert_eq(_held(layer), case[1], case[2])
    var seeds := _layer()
    _paint(seeds, _at([Vector2i.LEFT, Vector2i.ZERO, Vector2i.RIGHT], BLINKER_AT, GREEN))
    _put(seeds, {"birth": 2, "survival": 0})
    _step(seeds)
    var corners: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]
    assert_eq(_held(seeds), _at(corners, BLINKER_AT, GREEN), "Seeds, B2 with no survival, bears the four cells two ends see")


func test_a_cell_lives_above_half_coverage_and_keeps_the_colour_it_was_painted_with() -> void:
    var layer := _layer()
    _paint(layer, {BLINKER_AT + Vector2i.LEFT: BLUE, BLINKER_AT: RED, BLINKER_AT + Vector2i.RIGHT: BLUE})
    _put(layer)
    _step(layer)
    var held := _held(layer)
    assert_eq(held.size(), 3, "Coverage of three quarters lives, %s" % [held.keys()])
    assert_eq(held.get(BLINKER_AT, CLEAR), RED, "The middle lives on in the red it was painted, alpha and all")
    var parents := [BLUE, RED, BLUE]
    var mean := Color(0.0, 0.0, 0.0, 0.0)
    for colour: Color in parents:
        mean += Color(colour.r * colour.a, colour.g * colour.a, colour.b * colour.a, colour.a) / 3.0
    var born := Color(mean.r / mean.a, mean.g / mean.a, mean.b / mean.a, mean.a)
    for cell: Vector2i in [BLINKER_AT + Vector2i.UP, BLINKER_AT + Vector2i.DOWN]:
        assert_true(_near(held.get(cell, CLEAR), born), "%s is born in its parents' colour, %s" % [cell, held.get(cell, CLEAR)])

    var half := _layer()
    _paint(half, {BLINKER_AT + Vector2i.LEFT: GREEN, BLINKER_AT: GREEN, BLINKER_AT + Vector2i.RIGHT: Color(GREEN, 0.5)})
    _put(half)
    _step(half)
    assert_eq(_held(half), {}, "Coverage of a half is dead, so two cells alone die and the half is cleared")


## Both chunks of *layer*'s albedo, as bytes.
func _bytes(layer: SaLayer) -> PackedByteArray:
    var rd := GlobalShaderCompiler.get_rd()
    var left := rd.texture_get_data(layer.get_field(Vector2i(0, 0)).rid, 0)
    return left + rd.texture_get_data(layer.get_field(Vector2i(1, 0)).rid, 0)
