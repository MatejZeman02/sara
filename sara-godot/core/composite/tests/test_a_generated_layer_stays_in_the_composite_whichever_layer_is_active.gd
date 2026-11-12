## A generated layer stays in the composite whichever layer is active.
##
## Day 9 of a painting pass laid three Multiply layers over a generated Paper and
## lost the paper's tone and grain from the canvas and the export once two of
## them lay between the paper and the active layer. Below the active layer the
## fold put the two into a cache over transparent, past the paper that broke
## their run, and laid the cache Normal over the paper, so they multiplied
## nothing and covered it. The suite composites the same stack with each of
## the four layers active in turn and reads one composite every time, and an
## export with the top layer active against one with the paper active.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const FIRST := Color(0.95, 0.7, 0.55, 1.0)
const SECOND := Color(0.6, 0.85, 0.9, 1.0)
const THIRD := Color(0.8, 0.75, 0.5, 1.0)
## Float rounding between two folds of the same stack, well under a step of a
## 16-bit export.
const ROUNDING := 0.0001

var _registries: SaRegistries = null
var _easel: SaEasel = null
var _doc: SaDocument = null
## The paper, then the three Multiply layers bottom to top.
var _stack: Array[SaLayer] = []
## Three chunks wide and one high: the first chunk under the first and second
## Multiply layers, the next under the first and third, the last under the
## paper alone.
var _size := Vector2i(SaLayer.CHUNK_SIZE * 3, SaLayer.CHUNK_SIZE)


func before_each() -> void:
    _registries = Fixtures.make_registries()
    _easel = SaEasel.create_default(_size)
    _easel.compositor.set_registry(_registries.blend_modes)
    _doc = _easel.document
    _stack = _paper_under_three_multiply_layers()


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _stack = []
    _registries = null


## Day 9's stack: a Paper ground under Layer 1 and two layers more, all three
## in Multiply, each painted over chunks of its own so that every pair of them
## overlaps somewhere and the last chunk shows the paper alone.
func _paper_under_three_multiply_layers() -> Array[SaLayer]:
    var ops := SaLayerOps.new(_doc)
    var first := _doc.active_layer
    var paper := ops.add(&"paper", _registries.layer_types)
    _doc.set_active_layer(first)
    var second := ops.add()
    var third := ops.add()
    var painted: Array = [[first, FIRST, [0, 1]], [second, SECOND, [0]], [third, THIRD, [1]]]
    for each: Array in painted:
        var layer: SaLayer = each[0]
        ops.set_blend_mode(layer, &"multiply")
        for column: int in each[2]:
            layer.get_or_create_chunk(Vector2i(column, 0)).clear(each[1])
    assert_true(paper.is_generated(), "The Paper stores nothing and is generated")
    assert_eq(paper.get_index() + 1, first.get_index(), "and lies right under the first Multiply layer")
    return [paper, first, second, third]


## The composite with *active* the active layer, read back whole as floats.
func _composite_with(active: SaLayer) -> Image:
    _doc.set_active_layer(active)
    _doc.update_caches()
    _easel.request_full_composite()
    _easel.process_pending_composite()
    return SaExport.get_easel_image_float(_easel)


## The largest difference in any channel of any pixel between *a* and *b*.
func _largest_difference(a: Image, b: Image) -> float:
    var largest := 0.0
    for y in a.get_height():
        for x in a.get_width():
            var p := a.get_pixel(x, y)
            var q := b.get_pixel(x, y)
            largest = maxf(largest, maxf(maxf(absf(p.r - q.r), absf(p.g - q.g)), maxf(absf(p.b - q.b), absf(p.a - q.a))))
    return largest


## The mean of one row of *image* across the chunk at *column*, red green and
## blue summed, which is the tone there.
func _tone(image: Image, column: int) -> float:
    var total := 0.0
    var chunk := SaLayer.CHUNK_SIZE
    for x in range(column * chunk + 8, (column + 1) * chunk - 8):
        var here := image.get_pixel(x, floori(chunk / 2.0))
        total += here.r + here.g + here.b
    return total / float(chunk - 16)


## How much neighbouring pixels of one row across the chunk at *column*
## differ on average, which is the grain there: a flat fill reads nought.
func _grain(image: Image, column: int) -> float:
    var total := 0.0
    var chunk := SaLayer.CHUNK_SIZE
    var previous := image.get_pixel(column * chunk + 8, floori(chunk / 2.0))
    for x in range(column * chunk + 9, (column + 1) * chunk - 8):
        var here := image.get_pixel(x, floori(chunk / 2.0))
        total += absf(here.r - previous.r) + absf(here.g - previous.g) + absf(here.b - previous.b)
        previous = here
    return total / float(chunk - 17)


## The paper active is the walk that was always right, with all three layers
## above it. Each other layer active reads the same composite, the top one
## above all, which is the one Day 9 lost the paper under.
func test_the_composite_is_the_same_whichever_of_the_four_is_active() -> void:
    var paper := _stack[0]
    var expected := _composite_with(paper)
    assert_true(_grain(expected, 0) > 0.001, "With the paper active its grain shows through the Multiply layers")
    assert_true(_tone(expected, 0) < _tone(expected, 2) - 0.1, "and the layers darken it where they overlap")
    for i in range(1, _stack.size()):
        var active := _stack[i]
        var read := _composite_with(active)
        var difference := _largest_difference(read, expected)
        assert_true(
            difference <= ROUNDING,
            "With %s active the composite is the paper's own to within float rounding, %.6f off" % [active.name, difference]
        )
        assert_almost_eq(_grain(read, 0), _grain(expected, 0), ROUNDING, "%s active keeps the paper's grain" % active.name)


## Below the top layer the paper is a step of its own, and the two Multiply
## layers past it are each a step of their own over it rather than a cache
## laid Normal, which is what Day 9's walk was.
func test_the_layers_past_the_paper_composite_over_it_below_the_active_layer() -> void:
    var paper := _stack[0]
    _doc.set_active_layer(_stack[3])
    _doc.update_caches()
    var walked: Array[SaLayer] = []
    for atom: Dictionary in _doc.fold.bottom_stack:
        walked.append(SaLayerStack.layer_of(atom))
    var at := walked.find(paper)
    assert_true(at >= 0, "The paper is walked below the top layer")
    assert_eq(walked.slice(at), [paper, _stack[1], _stack[2]] as Array[SaLayer], "and each Multiply layer after it, itself")


## An export with the top layer active holds the paper's tone and grain: it
## reads as the export with the paper active does, to within a level.
func test_an_export_with_the_top_layer_active_holds_the_paper() -> void:
    var path := SaDataRoot.path("test_d18_paper.png")
    _composite_with(_stack[0])
    assert_eq(SaExport.export_png(_easel, path, 16), OK, "The export with the paper active is written")
    var expected := Image.load_from_file(path)
    _composite_with(_stack[3])
    assert_eq(SaExport.export_png(_easel, path, 16), OK, "and the one with the top layer active")
    var read := Image.load_from_file(path)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    assert_eq(read.get_size(), _size, "The export is the canvas")
    expected.convert(Image.FORMAT_RGBAF)
    read.convert(Image.FORMAT_RGBAF)
    for column in 3:
        assert_almost_eq(_tone(read, column), _tone(expected, column), 0.0005, "Chunk %d keeps the paper's tone" % column)
        assert_almost_eq(_grain(read, column), _grain(expected, column), 0.0002, "and its grain")
    assert_true(_grain(read, 0) > 0.001, "The paper's grain shows under all three layers in the export")
    var difference := _largest_difference(read, expected)
    assert_true(difference <= 1.0 / 65535.0 + ROUNDING, "and no pixel of it is a level off, %.6f" % difference)
