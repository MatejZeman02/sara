## A filter moved to another layer
## is refused where attaching it there would be.
##
## A filter that reads the whole layer is attached to a layer at the document's
## resolution and moved onto a layer at twice it, which the attach refuses. The
## move is refused as well, with the same line, and the record stays where it
## was. A move onto a second plain layer still takes, so the refusal is the
## check and not a broken move.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const WholeShiftFilter = preload("res://tests/fixtures/modules/whole-fixture/whole_shift_filter.gd")

const REQUIRES_GPU := true

const CANVAS := Vector2i(512, 256)
const WHOLE_OWNER: StringName = &"whole-fixture"
const WHOLE_KEY: StringName = &"whole-fixture.whole_fixture_shift"
const VALUES := {"offset_x": 256.0, "offset_y": 0.0, "mode": 0, "reach": SaNeighbourhoodPass.WHOLE_NODE}

var _easel: SaEasel = null


func after_each() -> void:
    if _easel != null:
        _easel.free()
    _easel = null


## A fresh easel whose chain answers the whole-node shift.
func _open() -> SaDocument:
    _easel = Bench.easel(CANVAS)
    _easel.compositor.filter_chain.registry.register(WholeShiftFilter.new(), WHOLE_OWNER)
    return _easel.document


func test_a_whole_reading_filter_is_refused_a_move_onto_a_double_resolution_layer() -> void:
    var doc := _open()
    var plain := SaLayerOps.new(doc).add(&"", null, 1.0)
    var double := SaLayerOps.new(doc).add(&"", null, 2.0)
    var ops := SaFilterOps.new(doc)
    var record := ops.attach(plain, WHOLE_KEY, VALUES)
    assert_not_null(record, "The whole-node filter attaches to the plain layer")
    var before := SaProblems.pending_refusals.size()
    assert_false(ops.move_to(plain, record, double), "The move onto the double resolution layer is refused")
    assert_eq(SaProblems.pending_refusals.size(), before + 1, "with a line the painter reads")
    assert_true(double.filters.is_empty(), "and nothing hangs on the double layer")
    assert_eq(plain.filters, [record] as Array[SaAttachedFilter], "while the record is still on the first")


func test_the_same_filter_still_moves_onto_a_plain_layer() -> void:
    var doc := _open()
    var first := SaLayerOps.new(doc).add(&"", null, 1.0)
    var second := SaLayerOps.new(doc).add(&"", null, 1.0)
    var ops := SaFilterOps.new(doc)
    var record := ops.attach(first, WHOLE_KEY, VALUES)
    var before := SaProblems.pending_refusals.size()
    assert_true(ops.move_to(first, record, second), "The move onto a plain layer takes")
    assert_eq(SaProblems.pending_refusals.size(), before, "with no refusal")
    assert_true(first.filters.is_empty(), "and the record leaves the first")
    assert_eq(second.filters, [record] as Array[SaAttachedFilter], "for the second")
