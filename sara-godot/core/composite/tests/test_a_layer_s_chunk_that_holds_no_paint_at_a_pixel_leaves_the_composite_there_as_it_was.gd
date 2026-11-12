## A layer's chunk that holds no paint at a pixel leaves the composite there as
## it was.
##
## A large painting's white Multiply relief, painted only inside a box, moved
## a few pixels of the export far outside it by one level of eight bits, and
## hiding it put them back. The relief broke the run of plain Normal layers the
## fold caches above the active layer, so shown, the layers past it were folded
## into a cache of their own over transparent and laid over the rest, and
## hidden, they were folded onto the layers before them in one cache. Over is
## not associative once each fold rounds to the document's half precision, so
## the two groupings differed by a rounding wherever the stack held paint. The
## suite composites a half precision stack with the Multiply layer shown,
## hidden, and with an empty chunk of its own, and asks each pair to agree to
## the bit outside the Multiply layer's paint.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

## The corner of the first chunk the Multiply layer paints, in pixels.
const PAINTED := 64

var _registries: SaRegistries = null
var _easel: SaEasel = null
var _doc: SaDocument = null
## The active layer at the bottom, a Normal layer, the Multiply layer, and two
## Normal layers above it, bottom to top.
var _stack: Array[SaLayer] = []
## Two chunks wide: the Multiply layer holds the first, painted in one corner.
var _size := Vector2i(SaLayer.CHUNK_SIZE * 2, SaLayer.CHUNK_SIZE)


func before_each() -> void:
    _registries = Fixtures.make_registries()
    _easel = SaEasel.create_default(_size, null, SaColorSpace.srgb().with_depth(SaColorSpace.Depth.F16))
    _easel.compositor.set_registry(_registries.blend_modes)
    _doc = _easel.document
    _stack = _relief_among_normal_layers()


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _stack = []
    _registries = null


## A large painting's shape: Normal layers of random half transparent paint
## either side of a Multiply layer, the bottom layer active, so every layer
## above it is in the fold's top stack.
func _relief_among_normal_layers() -> Array[SaLayer]:
    var ops := SaLayerOps.new(_doc)
    var bottom := _doc.active_layer
    var under := ops.add()
    var relief := ops.add()
    var over := ops.add()
    var top := ops.add()
    ops.set_blend_mode(relief, &"multiply")
    var rng := RandomNumberGenerator.new()
    rng.seed = 732
    for layer: SaLayer in [bottom, under, over, top]:
        for column in 2:
            _fill(layer, Vector2i(column, 0), rng, SaLayer.CHUNK_SIZE)
    _fill(relief, Vector2i(0, 0), rng, PAINTED)
    _doc.set_active_layer(bottom)
    return [bottom, under, relief, over, top]


## Writes random paint into *layer*'s chunk at *grid_pos* over the square of
## *side* pixels at its corner, and nothing past it.
func _fill(layer: SaLayer, grid_pos: Vector2i, rng: RandomNumberGenerator, side: int) -> void:
    var texture := layer.get_or_create_field(grid_pos, SaFieldSpec.ALBEDO)
    var layout: Vector2i = SaSadBlob.LAYOUT[texture.format]
    assert_eq(layout.y, 2, "The document keeps its paint at half precision")
    var bytes := PackedByteArray()
    bytes.resize(texture.size.x * texture.size.y * layout.x * layout.y)
    for y in mini(side, texture.size.y):
        for x in mini(side, texture.size.x):
            var at := (y * texture.size.x + x) * layout.x * layout.y
            for channel in 3:
                bytes.encode_half(at + channel * 2, rng.randf_range(0.05, 1.0))
            bytes.encode_half(at + 6, rng.randf_range(0.2, 0.9))
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, bytes)


## The composite of the stack as it stands, read back whole as floats.
func _composite() -> Image:
    _doc.update_caches()
    _easel.request_full_composite()
    _easel.process_pending_composite()
    return SaExport.get_easel_image_float(_easel)


## How many pixels of *a* and *b* differ in any bit, outside the corner the
## Multiply layer paints.
func _differing(a: Image, b: Image) -> int:
    var count := 0
    for y in a.get_height():
        for x in a.get_width():
            if x < PAINTED and y < PAINTED:
                continue
            if a.get_pixel(x, y) != b.get_pixel(x, y):
                count += 1
    return count


func test_hiding_the_multiply_layer_changes_no_pixel_where_it_holds_no_paint() -> void:
    var relief := _stack[2]
    var shown := _composite()
    relief.visible = false
    var hidden := _composite()
    assert_eq(_differing(shown, hidden), 0, "Hidden, the Multiply layer leaves every pixel past its paint as it was shown")
    relief.visible = true
    assert_eq(_differing(_composite(), shown), 0, "and shown again, the composite is the one it was")


func test_an_empty_chunk_of_the_multiply_layer_changes_no_pixel() -> void:
    var relief := _stack[2]
    var without := _composite()
    relief.get_or_create_chunk(Vector2i(1, 0))
    assert_true(relief.chunks.has(Vector2i(1, 0)), "The Multiply layer holds the second chunk, with no paint in it")
    assert_eq(_differing(_composite(), without), 0, "and the composite is the one it was without the chunk, to the bit")


func test_a_hidden_multiply_layer_still_parts_the_runs_of_normal_layers_either_side() -> void:
    var relief := _stack[2]
    relief.visible = false
    _doc.update_caches()
    var walked: Array[SaLayer] = []
    for atom: Dictionary in _doc.fold.top_stack:
        walked.append(SaLayerStack.layer_of(atom))
    assert_true(_stack[1] in walked, "The Normal layer under the hidden Multiply layer is a step of its own")
    assert_false(_stack[3] in walked or _stack[4] in walked, "and the two over it are folded into a cache together")
    assert_eq(walked.size(), 2, "so the walk is the one the shown layer parts, less the layer")
