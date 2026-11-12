## A filter on the document's root runs over the canvas once every dirty region
## holds its whole composite, so every layer is changed by it.
## A painter's global filter: one more list on the document and the same chain.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const PAINT := Color(0.25, 0.5, 0.75, 1.0)
const INVERTED := Color(0.75, 0.5, 0.25, 1.0)
const RED := Color(1.0, 0.0, 0.0, 1.0)
const CYAN := Color(0.0, 1.0, 1.0, 1.0)

var _easel: SaEasel = null
var _doc: SaDocument = null


## 300 and not 512, so the canvas ends inside its last chunk.
func before_each() -> void:
    _easel = Bench.easel(Vector2i(300, 300))
    _doc = _easel.document
    _doc.fill_layer(PAINT, _doc.get_node("Background") as SaLayer)
    # A red square on the layer above, in the first chunk.
    var upper := _doc.get_node("Layer 1") as SaLayer
    _doc.fill_layer(RED, upper)
    Bench.composite(_easel)


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null


func _shows(at: Vector2i, expected: Color, what: String) -> void:
    var found := Bench.texel(_easel.output, at)
    assert_almost_eq(found.r, expected.r, 0.01, "%s, red at %s: %s" % [what, at, found])
    assert_almost_eq(found.g, expected.g, 0.01, "%s, green at %s: %s" % [what, at, found])
    assert_almost_eq(found.b, expected.b, 0.01, "%s, blue at %s: %s" % [what, at, found])


func test_a_root_filter_changes_every_layer() -> void:
    var upper := _doc.get_node("Layer 1") as SaLayer
    upper.visible = false
    Bench.composite(_easel)
    _shows(Vector2i(10, 10), PAINT, "Before the filter the background shows")

    var ops := SaFilterOps.new(_doc)
    var record := ops.attach(null, Bench.INVERT)
    Bench.composite(_easel)
    _shows(Vector2i(10, 10), INVERTED, "The root's invert reaches the background")
    _shows(Vector2i(299, 299), INVERTED, "to the canvas's last texel, inside its last chunk")

    upper.visible = true
    Bench.composite(_easel)
    _shows(Vector2i(10, 10), CYAN, "and the layer above it, which is the whole composite inverted")

    ops.detach(null, record)
    Bench.composite(_easel)
    _shows(Vector2i(10, 10), RED, "A detach shows the document again")


func test_a_small_dirty_region_is_filtered_once_and_its_neighbours_not_again() -> void:
    SaFilterOps.new(_doc).attach(null, Bench.INVERT)
    Bench.composite(_easel)
    _shows(Vector2i(24, 24), CYAN, "The whole canvas is inverted")
    # Thirteen texels from 10, so the dispatch rounds up to sixteen and its
    # last three threads fall on texels that already hold a filtered composite.
    _doc.invalidate_chunk_regions({Vector2i(0, 0): Rect2i(10, 10, 13, 13)})
    _easel.process_pending_composite()
    _shows(Vector2i(15, 15), CYAN, "Inside the region the composite is redrawn and inverted")
    _shows(Vector2i(24, 24), CYAN, "and a texel past its edge is not inverted a second time")
    _shows(Vector2i(9, 9), CYAN, "nor one before it")
