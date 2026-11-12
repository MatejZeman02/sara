## Flatten works over a ground or a filter layer at the bottom.
##
## A document laid on a paper at File > New has a generated layer named
## Background at the bottom, which stores no paint, and Flatten refused it
## with "'Background' stores no paint, so there is nothing to flatten into."
## So did an adjustment or an effect layer left at the bottom. Now the flatten
## draws the tree into a new paint layer of the bottom's name and takes every
## other layer out, as one step. Each case reads the easel's output before,
## after the flatten, after its undo and after its redo: the step is right
## when no texel moved and the stack is what it was. The dimmed Merge Down
## above a ground is `test_the_dimmed_merge_down_says_why`, beside the
## menu's rows, since a core suite names no ui class.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(512, 512)
const PAINT := Color(0.8, 0.2, 0.1, 1.0)
const WASH := Color(0.2, 0.6, 0.9, 0.5)
## What a half float leaves between the paper the compositor draws and the
## paper baked into a chunk and drawn again.
const TOLERANCE := 2.0e-3

var _types: SaLayerTypeRegistry
var _easel: SaEasel
var _doc: SaDocument
var _ops: SaLayerOps


func before_each() -> void:
    _types = Fixtures.make_registries().layer_types
    _easel = Bench.easel(SIZE)
    _doc = _easel.document
    _ops = SaLayerOps.new(_doc)
    SaProblems.pending_refusals = PackedStringArray()


func after_each() -> void:
    _ops = null
    _doc = null
    _easel.free()
    _easel = null
    _types = null


## A fresh document laid on a paper, as File > New with Ground Paper lays it,
## and paint on two layers: an opaque square on Layer 1 and a half wash over
## it and past it on a second layer.
func _papered() -> void:
    var choice := {
        SaDocumentBackground.KIND: SaDocumentBackground.COLOUR,
        SaDocumentBackground.COLOR: Color.WHITE,
        SaDocumentBackground.GROUND: &"paper",
    }
    _doc.reset_to_default(SIZE, _doc.color_space, SaDocument.DEFAULT_DPI, choice, _types)
    _ops = SaLayerOps.new(_doc)
    _doc.get_node("Layer 1").get_or_create_chunk(Vector2i(0, 0)).clear(PAINT)
    var wash := _ops.add()
    wash.get_or_create_chunk(Vector2i(0, 0)).clear(WASH)
    wash.get_or_create_chunk(Vector2i(1, 0)).clear(WASH)
    Bench.composite(_easel)


func _output() -> PackedByteArray:
    Bench.composite(_easel)
    return GlobalShaderCompiler.get_rd().texture_get_data(_easel.output.rid, 0)


## The widest gap between two canvases over a sparse grid of texels.
func _worst(a: PackedByteArray, b: PackedByteArray) -> float:
    var worst := 0.0
    for y in range(0, SIZE.y, 5):
        for x in range(0, SIZE.x, 5):
            var p := SaFieldSpec.decode_texel(a, _easel.output.format, y * SIZE.x + x)
            var q := SaFieldSpec.decode_texel(b, _easel.output.format, y * SIZE.x + x)
            worst = maxf(worst, maxf(maxf(absf(p.r - q.r), absf(p.g - q.g)), maxf(absf(p.b - q.b), absf(p.a - q.a))))
    return worst


func _same(before: PackedByteArray, what: String) -> void:
    var worst := _worst(before, _output())
    assert_true(worst <= TOLERANCE, "%s, worst %s" % [what, worst])


func _names() -> Array[String]:
    var found: Array[String] = []
    for layer in _ops.layers():
        found.append(str(layer.name))
    return found


## The flatten's step and its two directions, over whatever stack is there:
## one Flatten row, one layer of plain paint named *name* holding what the
## canvas showed, and the stack and the canvas back on undo and flat again on
## redo.
func _flattens_into_paint(name: String) -> void:
    var before := _output()
    var stack := _ops.layers()
    var old_bottom := stack[0]
    var names := _names()
    var steps := _doc.undo_redo.get_history_count()
    assert_true(_ops.flatten(), "The flatten runs")
    assert_eq(SaProblems.pending_refusals.size(), 0, "with no refusal: %s" % "\n".join(SaProblems.pending_refusals))
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "as one step")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Flatten", "named Flatten")
    var flat := _ops.layers()
    assert_eq(flat.size(), 1, "One layer is left")
    var left := flat[0]
    assert_eq(str(left.name), name, "named as the bottom layer was")
    assert_true(SaLayerRefusals.new(_doc).stores_paint(left), "and it is a plain paint layer")
    assert_false(left.chunks.is_empty(), "holding chunks")
    assert_eq(_doc.active_layer, left, "and it is the active layer")
    for grid_pos: Vector2i in left.chunks:
        var albedo: SaTexture = left.get_field(grid_pos)
        assert_eq(albedo.format, _doc.color_space.texel_format(), "Each chunk stays at the document's float format")
    assert_null(old_bottom.get_parent(), "The old bottom layer is out of the document")
    _same(before, "The flattened canvas is the canvas before it")

    assert_true(_doc.undo(), "Ctrl+Z")
    assert_eq(_names(), names, "brings back every layer in its place")
    assert_eq(_ops.layers()[0], old_bottom, "the old bottom among them")
    assert_null(left.get_parent(), "and takes the new layer out")
    assert_true(left.chunks.is_empty(), "emptied")
    _same(before, "The canvas is the one before the flatten")

    assert_true(_doc.redo(), "Ctrl+Shift+Z")
    assert_eq(_ops.layers(), [left] as Array[SaLayer], "flattens again into the same layer")
    assert_false(left.chunks.is_empty(), "holding its chunks again")
    _same(before, "and the canvas is still the canvas before it")


func test_a_flatten_over_a_paper_bakes_it_under_the_paint() -> void:
    _papered()
    var ground := _ops.layers()[0]
    assert_true(ground.is_generated() and str(ground.name) == SaDocumentBackground.LAYER_NAME, "The paper lies at the bottom")
    _flattens_into_paint(SaDocumentBackground.LAYER_NAME)
    var flat := _ops.layers()[0]
    assert_eq(flat.chunks.size(), SaLayer.grid_positions(_doc.canvas_size).size(), "The paper reaches the whole document")


func test_a_flatten_over_an_effect_layer_at_the_bottom() -> void:
    var source := _doc.get_node("Layer 1") as SaLayer
    source.name = "Source"
    source.get_or_create_chunk(Vector2i(0, 0)).clear(PAINT)
    _doc.set_active_layer(source)
    var effect := _ops.add(SaEffectLayer.TYPE_ID, _types)
    effect.name = "Effect"
    assert_not_null(SaFilterOps.new(_doc).attach(effect, Bench.INVERT), "The invert attaches to the effect layer")
    _doc.move_child(effect, 0)
    var wash := _ops.add()
    wash.get_or_create_chunk(Vector2i(1, 1)).clear(WASH)
    assert_true(_ops.layers()[0].is_effect(), "The effect layer is at the bottom")
    _flattens_into_paint("Effect")


func test_the_old_bottom_layer_still_takes_a_flatten_that_stores_paint() -> void:
    var bottom := _ops.layers()[0]
    _ops.add().get_or_create_chunk(Vector2i(0, 0)).clear(WASH)
    assert_true(_ops.flatten(), "A flatten over a stored background runs")
    assert_eq(_ops.layers(), [bottom] as Array[SaLayer], "into the background itself, as before")
