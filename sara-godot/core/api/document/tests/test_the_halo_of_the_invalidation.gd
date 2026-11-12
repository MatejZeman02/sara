## A paint under a neighbourhood filter makes its halo stale.
## One dab's dirty rectangle, the one the brush hands the document, grows by the
## widest halo attached anywhere in the document and spills into the chunk
## beside it, and a document with no such filter dirties exactly what it did.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const BoxBlurFilter = preload("res://modules/sara-base-modules/base/usual/box_blur_filter.gd")

const REQUIRES_GPU := true

const KEY: StringName = &"sara-base-modules.box_blur"
const RADIUS := 20
## A dab four pixels across at the left edge of chunk (1, 0), in its own pixels.
const DAB := Rect2i(2, 100, 4, 4)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null


func before_each() -> void:
    _easel = Bench.easel(Vector2i(3 * SaChunk.SIZE, SaChunk.SIZE))
    _doc = _easel.document
    ModuleLoader.module_dirs[&"sara-base-modules"] = "res://modules/sara-base-modules/base"
    var blur := BoxBlurFilter.new()
    _easel.compositor.filter_chain.registry.register(blur, &"sara-base-modules")
    _layer = _doc.get_node("Background") as SaLayer
    _doc.fill_layer(Color(0.5, 0.5, 0.5, 1.0), _layer)
    Bench.composite(_easel)


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _layer = null


## The dirty set one dab leaves, from a clean one.
func _dab() -> Dictionary:
    _doc.consume_dirty_chunks()
    _doc.invalidate_chunk_regions({Vector2i(1, 0): DAB})
    return _doc.consume_dirty_chunks()


func test_a_dab_with_no_neighbourhood_filter_dirties_its_own_rectangle() -> void:
    var dirty := _dab()
    assert_eq(dirty.size(), 1, "One chunk, %s" % dirty)
    assert_eq(dirty.get(Vector2i(1, 0), Rect2i()), DAB, "and the dab's rectangle in it")


func test_a_dab_under_an_attached_blur_grows_by_the_halo() -> void:
    SaFilterOps.new(_doc).attach(_layer, KEY, {"radius": RADIUS})
    Bench.composite(_easel)
    var dirty := _dab()
    assert_eq(dirty.size(), 2, "The dab's chunk and the one its halo reaches across the seam, %s" % dirty)
    assert_eq(
        dirty.get(Vector2i(1, 0), Rect2i()),
        Rect2i(0, DAB.position.y - RADIUS, DAB.end.x + RADIUS, DAB.size.y + 2 * RADIUS),
        "Its own chunk, grown by the radius and cut at the chunk's left edge"
    )
    assert_eq(
        dirty.get(Vector2i(0, 0), Rect2i()),
        Rect2i(
            SaChunk.SIZE - (RADIUS - DAB.position.x), DAB.position.y - RADIUS, RADIUS - DAB.position.x, DAB.size.y + 2 * RADIUS
        ),
        "and the strip of the chunk to its left the halo reaches"
    )


func test_a_blur_on_another_layer_or_the_root_grows_it_too() -> void:
    # The document does not know which layer a dab moved, so the widest halo
    # anywhere is the one it grows by.
    var ops := SaFilterOps.new(_doc)
    ops.attach(null, KEY, {"radius": RADIUS})
    Bench.composite(_easel)
    assert_eq(_dab().size(), 2, "A blur on the root grows a dab on any layer")


func test_a_blur_switched_off_grows_nothing() -> void:
    var ops := SaFilterOps.new(_doc)
    var record := ops.attach(_layer, KEY, {"radius": RADIUS})
    Bench.composite(_easel)
    ops.set_enabled(record, false)
    Bench.composite(_easel)
    assert_eq(_dab().size(), 1, "A record that is off composites as if it were not there, and dirties as if")
    ops.set_enabled(record, true)
    Bench.composite(_easel)
    ops.detach(_layer, record)
    Bench.composite(_easel)
    assert_eq(_dab().size(), 1, "and so does one detached")
