## A duplicate carries its source's attached filters, and a merge or a flatten
## applies a layer's filters on the way in.
##
## Before it, `SaLayerOps.duplicate` copied a layer member by member and
## `filters` was not among them, so the copy showed something else than its
## source the moment the chain evaluated the records. `merge_down` and `flatten`
## composited a layer's stored albedo and freed it, so its filters vanished
## unapplied and the picture changed under the painter.
##
## The merge cases read the easel's output before and after: the step is right
## when no texel of it moved.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const PAINT := Color(0.8, 0.2, 0.1, 1.0)
const NEAR := Vector2i(40, 10)
const HIDDEN := Vector2i(200, 10)
const FAR := Vector2i(300, 10)

var _easel: SaEasel
var _doc: SaDocument
var _ops: SaLayerOps
var _upper: SaLayer


func before_each() -> void:
    _easel = Bench.easel(Vector2i(512, 256))
    _doc = _easel.document
    _ops = SaLayerOps.new(_doc)
    _upper = _ops.add()
    _doc.fill_layer(PAINT, _upper)


func after_each() -> void:
    _ops = null
    _upper = null
    _doc = null
    _easel.free()
    _easel = null


## A record on *layer* whose mask is one over the left half of the first chunk
## and zero over the right half.
func _attach_half_masked(layer: SaLayer) -> SaAttachedFilter:
    var record := SaFilterOps.new(_doc).attach(layer, Bench.INVERT, {"strength": 1.0})
    record.mask = SaMask.own()
    var coverage := record.mask.get_or_create(Vector2i(0, 0))
    var values := PackedFloat32Array()
    values.resize(coverage.size.x * coverage.size.y)
    for y in coverage.size.y:
        for x in coverage.size.x:
            values[y * coverage.size.x + x] = 1.0 if x < 128 else 0.0
    GlobalShaderCompiler.get_rd().texture_update(coverage.rid, 0, values.to_byte_array())
    record.touch()
    return record


func _output_at(points: Array) -> Array:
    Bench.composite(_easel)
    var found: Array = []
    for at: Vector2i in points:
        found.append(Bench.texel(_easel.output, at))
    return found


func _same(before: Array, after: Array, what: String) -> void:
    for i in before.size():
        var was: Color = before[i]
        var now: Color = after[i]
        var moved := maxf(maxf(absf(was.r - now.r), absf(was.g - now.g)), maxf(absf(was.b - now.b), absf(was.a - now.a)))
        assert_true(moved < 0.01, "%s, point %d: %s became %s" % [what, i, was, now])


func test_a_duplicate_carries_the_records_with_masks_of_their_own() -> void:
    var record := _attach_half_masked(_upper)
    var second := SaFilterOps.new(_doc).attach(_upper, Bench.INVERT)
    SaFilterOps.new(_doc).set_enabled(second, false)
    var copy := _ops.duplicate(_upper)
    assert_eq(copy.filters.size(), 2, "The copy holds as many records as its source")
    var held := copy.filters[0]
    assert_true(held != record, "each a record of its own")
    assert_eq(held.key, record.key, "with the same key")
    assert_eq(held.parameters, record.parameters, "the same values")
    assert_true(held.enabled, "and the same flag")
    assert_false(copy.filters[1].enabled, "a record that was off stays off")
    assert_not_null(held.mask, "The mask came along")
    var source_texture := record.mask.texture_for(Vector2i(0, 0))
    var copy_texture := held.mask.texture_for(Vector2i(0, 0))
    assert_not_null(copy_texture, "with coverage where the source has it")
    assert_true(copy_texture.rid != source_texture.rid, "in a texture of its own")
    assert_almost_eq(Bench.texel(copy_texture, NEAR).r, 1.0, 0.001, "holding one where the source holds one")
    assert_almost_eq(Bench.texel(copy_texture, HIDDEN).r, 0.0, 0.001, "and zero where it holds zero")

    assert_true(_doc.undo(), "The duplicate is one step")
    assert_null(copy.get_parent(), "whose undo takes the copy out, records and all")
    assert_eq(_upper.filters.size(), 2, "and leaves the source's records alone")
    assert_true(_doc.redo(), "Redo")
    assert_eq(copy.filters.size(), 2, "brings the copy back with its records")


func test_a_merge_down_applies_the_upper_layers_filters() -> void:
    _attach_half_masked(_upper)
    var points := [NEAR, HIDDEN, FAR]
    var before := _output_at(points)
    assert_almost_eq((before[0] as Color).r, 1.0 - PAINT.r, 0.02, "The filter shows before the merge")
    assert_true(_ops.merge_down(_upper), "The merge runs")
    _same(before, _output_at(points), "The merged picture is the picture that was on screen")
    assert_true(_doc.undo(), "One step")
    assert_eq(_upper.filters.size(), 1, "whose undo brings the layer back with its record")
    _same(before, _output_at(points), "and the same picture")


func test_a_merge_down_bakes_the_lower_layers_filters_and_takes_them_off() -> void:
    var lower := _ops.layers()[_upper.get_index() - 1]
    _doc.fill_layer(Color(0.2, 0.4, 0.6, 1.0), lower)
    var on := _attach_half_masked(lower)
    var off := SaFilterOps.new(_doc).attach(lower, Bench.INVERT)
    SaFilterOps.new(_doc).set_enabled(off, false)
    _ops.set_opacity(_upper, 0.5)
    var points := [NEAR, HIDDEN, FAR]
    var before := _output_at(points)
    assert_true(_ops.merge_down(_upper), "The merge runs")
    assert_false(lower.filters.has(on), "A record that was on is baked and gone")
    assert_true(lower.filters.has(off), "one that was off changes nothing and stays")
    _same(before, _output_at(points), "No texel moved")
    assert_true(_doc.undo(), "One step")
    assert_eq(lower.filters, [on, off] as Array[SaAttachedFilter], "whose undo puts the record back where it was")
    _same(before, _output_at(points), "with the picture it had")
    assert_true(_doc.redo(), "Redo")
    assert_false(lower.filters.has(on), "takes it off again")
    _same(before, _output_at(points), "and still no texel moved")


func test_a_flatten_applies_every_layers_filters_and_keeps_the_roots() -> void:
    var lower := _ops.layers()[0]
    var held := _ops.layers().size()
    _doc.fill_layer(Color(0.2, 0.4, 0.6, 1.0), lower)
    _attach_half_masked(lower)
    SaFilterOps.new(_doc).attach(_upper, Bench.INVERT)
    _ops.set_opacity(_upper, 0.5)
    var top := _ops.add()
    _doc.fill_layer(Color(0.1, 0.9, 0.3, 1.0), top)
    _ops.set_opacity(top, 0.25)
    _attach_half_masked(top)
    var root := SaFilterOps.new(_doc).attach(null, Bench.INVERT)
    var points := [NEAR, HIDDEN, FAR]
    var before := _output_at(points)
    assert_true(_ops.flatten(), "The flatten runs")
    assert_eq(_ops.layers().size(), 1, "One layer is left")
    assert_true(lower.filters.is_empty(), "with its filters baked")
    assert_eq(_doc.root_filters, [root] as Array[SaAttachedFilter], "The root's filter stays, because the root is still there")
    _same(before, _output_at(points), "No texel moved")
    assert_true(_doc.undo(), "One step")
    assert_eq(_ops.layers().size(), held + 1, "whose undo brings every layer back")
    assert_eq(lower.filters.size(), 1, "and the bottom one's record")
    _same(before, _output_at(points), "with the picture it had")
