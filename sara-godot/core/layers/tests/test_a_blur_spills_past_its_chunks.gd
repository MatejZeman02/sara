## An attached neighbourhood filter draws where its node holds no chunk. One chunk of a layer is painted red,
## the box blur is attached at
## radius 8, and the composite is read four pixels into the position beside it,
## which the layer never allocated. Once with the layer under the active one,
## which is the tier and the fold, once with the layer active, once inside an
## isolated group, and once with no full composite at all, where the dirty set
## the attach left has to reach the empty position by itself.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const BoxBlurFilter = preload("res://modules/sara-base-modules/base/usual/box_blur_filter.gd")

const REQUIRES_GPU := true

const MODULE_DIR := "res://modules/sara-base-modules/base"
const KEY: StringName = &"sara-base-modules.box_blur"
const RADIUS := 8
const RED := Color(1.0, 0.0, 0.0, 1.0)
const ROW := 128
## Four pixels into the empty chunk: the box of seventeen columns reaches the
## last five of the red chunk.
const INTO := SaChunk.SIZE + 3
const SPILL := 5.0 / 17.0

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null


func before_each() -> void:
    # Three chunks across: (0, 0) red, the other two never allocated.
    _easel = Bench.easel(Vector2i(3 * SaChunk.SIZE, SaChunk.SIZE))
    _doc = _easel.document
    ModuleLoader.module_dirs[&"sara-base-modules"] = MODULE_DIR
    var blur := BoxBlurFilter.new()
    _easel.compositor.filter_chain.registry.register(blur, &"sara-base-modules")
    _layer = _doc.get_node("Background") as SaLayer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)
    _layer.get_or_create_chunk(Vector2i(0, 0)).clear(RED)


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _layer = null


func _assert_spilled(where: String) -> void:
    var into := Bench.texel(_easel.output, Vector2i(INTO, ROW))
    assert_almost_eq(into.a, SPILL, 0.01, "%s: four pixels into the empty chunk is five columns of seventeen, %s" % [where, into])
    assert_true(into.r > 0.0, "%s: and what it carries is the red, %s" % [where, into])
    var far := Bench.texel(_easel.output, Vector2i(2 * SaChunk.SIZE + 128, ROW))
    assert_almost_eq(far.a, 0.0, 0.001, "%s: a position out of the blur's reach stays transparent, %s" % [where, far])
    assert_eq(_layer.chunks.size(), 1, "%s: and the layer allocated nothing for it" % where)


func test_a_layer_under_the_active_one_spills() -> void:
    assert_true(_doc.active_layer != _layer, "The blurred layer is not the active one")
    SaFilterOps.new(_doc).attach(_layer, KEY, {"radius": RADIUS})
    Bench.composite(_easel)
    _assert_spilled("under the active layer")


func test_the_active_layer_spills() -> void:
    _doc.set_active_layer(_layer)
    SaFilterOps.new(_doc).attach(_layer, KEY, {"radius": RADIUS})
    Bench.composite(_easel)
    _assert_spilled("the active layer")


func test_a_member_of_an_isolated_group_spills() -> void:
    var above := _doc.active_layer
    _doc.set_active_layer(_layer)
    var ops := SaLayerOps.new(_doc)
    var group := ops.group_active()
    ops.set_isolated(group, true)
    _doc.set_active_layer(above)
    SaFilterOps.new(_doc).attach(_layer, KEY, {"radius": RADIUS})
    Bench.composite(_easel)
    _assert_spilled("inside an isolated group")


func test_the_group_itself_spills() -> void:
    var above := _doc.active_layer
    _doc.set_active_layer(_layer)
    var ops := SaLayerOps.new(_doc)
    var group := ops.group_active()
    ops.set_isolated(group, true)
    _doc.set_active_layer(above)
    SaFilterOps.new(_doc).attach(group, KEY, {"radius": RADIUS})
    Bench.composite(_easel)
    _assert_spilled("the blur on the group")


func test_the_attach_alone_dirties_the_position_it_spills_into() -> void:
    # The picture without the filter first, so what follows is a composite of
    # the dirty set the attach left and of nothing else.
    Bench.composite(_easel)
    var before := Bench.texel(_easel.output, Vector2i(INTO, ROW))
    assert_almost_eq(before.a, 0.0, 0.001, "Unfiltered, the empty chunk is empty, %s" % before)
    SaFilterOps.new(_doc).attach(_layer, KEY, {"radius": RADIUS})
    _easel.request_composite()
    _easel.process_pending_composite()
    _assert_spilled("the dirty set of an attach")


func test_a_record_switched_off_takes_its_spill_with_it() -> void:
    var ops := SaFilterOps.new(_doc)
    var record := ops.attach(_layer, KEY, {"radius": RADIUS})
    Bench.composite(_easel)
    _assert_spilled("before it is switched off")
    # No full composite: the dirty set the switch left has to reach the ring,
    # though the record that reached it no longer counts.
    ops.set_enabled(record, false)
    _easel.request_composite()
    _easel.process_pending_composite()
    var into := Bench.texel(_easel.output, Vector2i(INTO, ROW))
    assert_almost_eq(into.a, 0.0, 0.001, "Switched off, the empty chunk is empty again, %s" % into)
    ops.detach(_layer, record)
    _easel.request_composite()
    _easel.process_pending_composite()
    into = Bench.texel(_easel.output, Vector2i(INTO, ROW))
    assert_almost_eq(into.a, 0.0, 0.001, "and detached it stays so, %s" % into)


func test_a_point_filter_walks_no_ring() -> void:
    SaFilterOps.new(_doc).attach(_layer, Bench.INVERT)
    Bench.composite(_easel)
    assert_eq(_easel.compositor.filter_chain.reach_of(_layer), 0, "An invert gathers nothing")
    var into := Bench.texel(_easel.output, Vector2i(INTO, ROW))
    assert_almost_eq(into.a, 0.0, 0.001, "so the position beside the paint stays transparent, %s" % into)
