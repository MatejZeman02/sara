## Attach and flatten: a filter attached to a layer is written
## into the layer's own texels by a flatten, which takes the record off and is
## one history step whose undo brings back both the pixels and the record. The
## fixture is an invert, so a texel says which of the two happened.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const PAINT := Color(0.25, 0.5, 0.75, 1.0)
const INVERTED := Color(0.75, 0.5, 0.25, 1.0)
const NEAR := Vector2i(10, 10)
const FAR := Vector2i(300, 300)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null
var _ops: SaFilterOps = null


func before_each() -> void:
    _easel = Bench.easel(Vector2i(512, 512))
    _doc = _easel.document
    _layer = _doc.get_node("Background") as SaLayer
    _doc.fill_layer(PAINT, _layer)
    _ops = SaFilterOps.new(_doc)
    Bench.composite(_easel)


func after_each() -> void:
    _ops = null
    _easel.free()
    _easel = null
    _doc = null
    _layer = null


## The layer's own stored texel at *at*, which a flatten writes and a
## composite does not.
func _stored(layer: SaLayer, at: Vector2i) -> Color:
    @warning_ignore("integer_division")
    var grid := Vector2i(at.x / SaChunk.SIZE, at.y / SaChunk.SIZE)
    return Bench.texel(layer.get_field(grid), at - grid * SaChunk.SIZE)


func _is(found: Color, expected: Color, epsilon: float, what: String) -> void:
    assert_almost_eq(found.r, expected.r, epsilon, "%s, red: %s" % [what, found])
    assert_almost_eq(found.b, expected.b, epsilon, "%s, blue: %s" % [what, found])


func test_a_flatten_writes_what_the_composite_showed_and_takes_the_record_off() -> void:
    var record := _ops.attach(_layer, Bench.INVERT)
    Bench.composite(_easel)
    var shown_near := Bench.texel(_easel.output, NEAR)
    var shown_far := Bench.texel(_easel.output, FAR)
    _is(shown_near, INVERTED, 0.01, "The attached invert shows before the flatten")
    _is(_stored(_layer, NEAR), PAINT, 1e-5, "while the layer holds what it held")

    var steps := _doc.history.step_count()
    assert_true(_ops.flatten(_layer, record), "The flatten writes")
    assert_eq(_doc.history.step_count(), steps + 1, "as one history step")
    assert_true(_layer.filters.is_empty(), "and the record is gone from the layer")
    _is(_stored(_layer, NEAR), shown_near, 1e-3, "The layer's texel is what the composite showed")
    _is(_stored(_layer, FAR), shown_far, 1e-3, "in every chunk")
    Bench.composite(_easel)
    _is(Bench.texel(_easel.output, NEAR), shown_near, 1e-3, "and the canvas has not moved")

    assert_true(_doc.undo(), "The step undoes")
    assert_eq(_layer.filters, [record] as Array[SaAttachedFilter], "bringing back the same record")
    _is(_stored(_layer, NEAR), PAINT, 1e-5, "and the pixels it was flattened over")
    Bench.composite(_easel)
    _is(Bench.texel(_easel.output, NEAR), INVERTED, 0.01, "so the canvas shows the attached invert again")

    assert_true(_doc.redo(), "and redoes")
    assert_true(_layer.filters.is_empty(), "taking the record off again")
    _is(_stored(_layer, NEAR), INVERTED, 1e-3, "and writing the pixels again")


func test_the_records_under_it_are_written_too_and_those_above_stay() -> void:
    var first := _ops.attach(_layer, Bench.INVERT)
    var second := _ops.attach(_layer, Bench.INVERT)
    var third := _ops.attach(_layer, Bench.INVERT)
    Bench.composite(_easel)
    _is(Bench.texel(_easel.output, NEAR), INVERTED, 0.01, "Three inverts show one")

    assert_true(_ops.flatten(_layer, second), "Flattening the middle record writes")
    _is(_stored(_layer, NEAR), PAINT, 1e-3, "two inverts, the one under it first, which is no change")
    assert_eq(_layer.filters, [third] as Array[SaAttachedFilter], "and leaves only the record above it")
    Bench.composite(_easel)
    _is(Bench.texel(_easel.output, NEAR), INVERTED, 0.01, "so the canvas still shows one invert")

    assert_true(_doc.undo(), "The step undoes")
    assert_eq(_layer.filters, [first, second, third] as Array[SaAttachedFilter], "with both records back in their places")


func test_a_record_switched_off_is_not_flattened() -> void:
    var record := _ops.attach(_layer, Bench.INVERT)
    _ops.set_enabled(record, false)
    var steps := _doc.history.step_count()
    assert_false(_ops.flatten(_layer, record), "A record that is off is refused")
    assert_eq(_doc.history.step_count(), steps, "with no step")
    assert_eq(_layer.filters.size(), 1, "and the record kept")
    _is(_stored(_layer, NEAR), PAINT, 1e-5, "and the pixels untouched")


func test_a_record_on_the_root_is_written_into_every_layer() -> void:
    var top := _doc.active_layer
    assert_true(top != _layer, "The default document has a layer above the background")
    _doc.fill_layer(PAINT, top)
    var record := _ops.attach(null, Bench.INVERT)
    var said := _ops.flatten_sentence(null, record)
    assert_true(said.contains("2 layers"), "The sentence says how many layers it writes: %s" % said)
    assert_true(_ops.flatten(null, record), "The root's record flattens")
    assert_true(_doc.root_filters.is_empty(), "and leaves the root")
    _is(_stored(_layer, NEAR), INVERTED, 1e-3, "into the background")
    _is(_stored(top, NEAR), INVERTED, 1e-3, "and into the layer above it")
    assert_true(_doc.undo(), "as one step")
    _is(_stored(_layer, NEAR), PAINT, 1e-5, "whose undo puts back the background")
    _is(_stored(top, NEAR), PAINT, 1e-5, "and the layer above it")
    assert_eq(_doc.root_filters.size(), 1, "and the record")


func test_the_record_is_found_under_its_node() -> void:
    var on_layer := _ops.attach(_layer, Bench.INVERT)
    var on_root := _ops.attach(null, Bench.INVERT)
    assert_eq(_ops.node_of(on_layer), _layer, "A layer's record answers its layer")
    assert_null(_ops.node_of(on_root), "and the root's answers null")
    assert_true(_ops.filters_of(null).has(on_root), "which the root's list tells apart from a stranger")
