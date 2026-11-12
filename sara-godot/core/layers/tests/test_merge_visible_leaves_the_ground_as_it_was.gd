## Merge Visible leaves the Ground as it was and merges the
## visible layers above it.
##
## A painter's note of 2026-10-31 is "bug: CTRL +SHIFT + E destroys the
## Ground layer". The merge drew the paper into a finite paint layer and took
## the paper's row out, so its colour stopped being a setting. Each test lays a
## document on a paper ground, as New Document does with a ground picked, and
## reads the stack, the paper's colour, the canvas and the corner.
extends "res://tests/test_framework.gd"

const Teardown := preload("res://tests/fixtures/teardown.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

## The proof is the pixels the merge leaves, which needs a RenderingDevice.
const REQUIRES_GPU := true

const SIZE := Vector2i(256, 256)
const RED := Color(0.8, 0.2, 0.1, 1.0)
const HALF := Color(0.1, 0.6, 0.3, 0.5)
const BLUE := Color(0.2, 0.3, 0.9, 0.7)
## Where all three paint layers draw, where two do, and where only the paper
## shows.
const POINTS: Array[Vector2i] = [Vector2i(20, 20), Vector2i(100, 40), Vector2i(200, 200)]

var _registries: SaRegistries = null
var _types: SaLayerTypeRegistry = null
var _easel: SaEasel = null
var _doc: SaDocument = null
var _heard: Array[String] = []


func before_each() -> void:
    _registries = Fixtures.make_picture_registries()
    _types = SaLayerTypeRegistry.new()
    _types.register(SaLayerTypeDescriptor.paper())
    _easel = SaEasel.create_default(SIZE, null, null)
    _easel.compositor.set_registry(_registries.blend_modes)
    _doc = _easel.document
    _heard.clear()
    EventBus.corner_notice.connect(_hear)
    EventBus.paint_refused.connect(_hear)


func after_each() -> void:
    EventBus.corner_notice.disconnect(_hear)
    EventBus.paint_refused.disconnect(_hear)
    Teardown.free_nodes([_easel])
    _easel = null
    _doc = null
    _types = null
    _registries = null


func _hear(line: String) -> void:
    _heard.append(line)


## A document laid on *ground*, a paper when it is `&"paper"` and nothing at
## all when it is empty, and its one empty paint layer.
func _laid(ground: StringName) -> void:
    var background := SaDocumentBackground.default_choice()
    if String(ground).is_empty():
        background[SaDocumentBackground.KIND] = SaDocumentBackground.TRANSPARENT
    background[SaDocumentBackground.GROUND] = ground
    _doc.reset_to_default(SIZE, SaColorSpace.srgb(), SaDocument.DEFAULT_DPI, background, _types)
    _easel.process_pending_composite()


## *layer* filled with *color* over *rect*.
func _fill(layer: SaLayer, color: Color, rect: Rect2i) -> void:
    _doc.selection.select_rect(rect)
    _doc.fill_layer(color, layer)
    _doc.selection.deselect()


## Three visible paint layers over whatever the document stands on, the first
## the one it was laid with, each filled over its own part of the first chunk.
func _three() -> Array[SaLayer]:
    var ops := SaLayerOps.new(_doc)
    var first := _doc.active_layer
    assert_false(first.is_generated(), "The document opens on a paint layer")
    _fill(first, RED, Rect2i(0, 0, 128, 128))
    var second := ops.add()
    _fill(second, HALF, Rect2i(0, 0, 160, 64))
    var third := ops.add()
    _fill(third, BLUE, Rect2i(0, 0, 64, 64))
    return [first, second, third]


func _ground() -> SaLayer:
    for layer in SaLayerOps.new(_doc).layers():
        if SaMergeVisible.is_ground(layer):
            return layer
    return null


## The canvas's own composite at each of `POINTS`.
func _output() -> Array[Color]:
    Bench.composite(_easel)
    var found: Array[Color] = []
    for at in POINTS:
        found.append(Bench.texel(_easel.output, at))
    return found


func _same(was: Array[Color], now: Array[Color], what: String) -> void:
    for i in was.size():
        var a: Color = was[i]
        var b: Color = now[i]
        var moved := maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))
        assert_true(moved < 0.01, "%s, point %s: %s against %s" % [what, POINTS[i], a, b])


## A paper and three Normal layers: the merge leaves two, the paper first with
## its colour and the merged layer above it, the canvas the same, nothing said
## in the corner, and one undo gives the four back.
func test_a_merge_over_a_ground_keeps_the_ground_and_its_colour() -> void:
    _laid(&"paper")
    var ops := SaLayerOps.new(_doc)
    var ground := _ground()
    assert_not_null(ground, "The document stands on a paper")
    if ground == null:
        return
    var colour: Color = ground.generator_params["color"]
    var before := ops.layers()
    var three := _three()
    var four := ops.layers()
    assert_eq(four.size(), before.size() + 2, "Two layers were added over the first")
    var shown := _output()

    assert_true(SaMergeVisible.new(_doc).merge(), "The merge runs")

    var left := ops.layers()
    assert_eq(left.size(), 2, "Two layers are left")
    assert_eq(left[0], ground, "the paper first, the same layer")
    assert_true(ground.visible, "still shown")
    assert_eq(ground.generator_params["color"], colour, "with its colour as it was")
    assert_false(left[1].is_generated(), "and one merged paint layer above it")
    assert_eq(str(left[1].name), str(three[2].name), "named for the topmost layer merged")
    _same(shown, _output(), "The canvas did not move")
    assert_true(_heard.is_empty(), "A Normal merge says nothing: %s" % ", ".join(_heard))

    assert_true(_doc.undo(), "One undo takes a step back")
    assert_eq(ops.layers(), four, "and gives every layer back in its order")
    _same(shown, _output(), "the canvas as it was")


## With no ground, the merge takes every visible layer into one, as it always
## did, and one undo gives them back.
func test_a_merge_with_no_ground_takes_every_visible_layer() -> void:
    _laid(&"")
    var ops := SaLayerOps.new(_doc)
    assert_null(_ground(), "The document stands on no ground")
    _three()
    var three := ops.layers()
    var shown := _output()

    assert_true(SaMergeVisible.new(_doc).merge(), "The merge runs")

    assert_eq(ops.layers().size(), 1, "One layer is left")
    _same(shown, _output(), "The canvas did not move")
    assert_true(_doc.undo(), "One undo takes a step back")
    assert_eq(ops.layers(), three, "and gives every layer back")


## A hidden paper is no ground the canvas shows, and it stays where it is too.
func test_a_hidden_ground_stays_hidden() -> void:
    _laid(&"paper")
    var ops := SaLayerOps.new(_doc)
    var ground := _ground()
    assert_not_null(ground, "The document stands on a paper")
    if ground == null:
        return
    _three()
    ops.set_visible(ground, false)

    assert_true(SaMergeVisible.new(_doc).merge(), "The merge runs")

    var left := ops.layers()
    assert_eq(left.size(), 2, "The hidden paper and the merged layer are left")
    assert_eq(left[0], ground, "the paper first")
    assert_false(ground.visible, "still hidden")


## One layer over a paper is nothing to merge, and nothing moves.
func test_one_layer_over_a_ground_is_nothing_to_merge() -> void:
    _laid(&"paper")
    var ops := SaLayerOps.new(_doc)
    var before := ops.layers()
    var steps := _doc.history.step_count()

    assert_false(SaMergeVisible.new(_doc).merge(), "Nothing is merged")

    assert_eq(ops.layers(), before, "The stack is as it was")
    assert_eq(_doc.history.step_count(), steps, "with no step in the history")


## A Multiply layer read the paper under it: the merge still runs, the paper
## stays, and the corner names the layer and says undo brings it back.
func test_a_multiply_layer_merged_off_a_ground_is_named_in_the_corner() -> void:
    _laid(&"paper")
    var ops := SaLayerOps.new(_doc)
    var three := _three()
    ops.set_blend_mode(three[1], &"multiply")
    var four := ops.layers()

    assert_true(SaMergeVisible.new(_doc).merge(), "The merge runs")

    assert_eq(ops.layers().size(), 2, "The paper and the merged layer are left")
    assert_true(SaMergeVisible.is_ground(ops.layers()[0]), "the paper first")
    assert_eq(_heard.size(), 1, "The corner says one line: %s" % ", ".join(_heard))
    if _heard.size() == 1:
        assert_true(_heard[0].contains(str(three[1].name)), "naming the Multiply layer: %s" % _heard[0])
        assert_true(_heard[0].contains("Undo"), "and that undo brings it back: %s" % _heard[0])
    assert_true(_doc.undo(), "One undo takes a step back")
    assert_eq(ops.layers(), four, "and gives every layer back")
    assert_eq(three[1].blend_mode, &"multiply", "the Multiply layer still multiplying")
