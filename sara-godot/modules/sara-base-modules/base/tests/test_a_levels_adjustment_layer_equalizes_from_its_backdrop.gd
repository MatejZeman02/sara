## Equalize on a Levels adjustment layer takes its map from the
## backdrop the layer reads, what the walk has drawn when it reaches the layer.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The band of the Levels suite, four levels a few bins apart split over two layers,
## sits under an adjustment layer holding one Levels record, the background
## emptied and hidden. An adjustment layer holds no chunk, so the active
## layer's paint is nothing to bin, and the backdrop is drawn over by the
## canvas before the frame ends: a map taken from either would not spread the
## output. Each press goes through the Levels panel in the edit window, where a
## painter presses it.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## Real dispatches into real chunks.
const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
const BAND_BINS: Array[int] = [102, 108, 114, 120]
## The level of a layer the backdrop must not hold, one bin of its own.
const STRAY_BIN := 230
## A fifth chunk across, beside the band, for the layer outside the group.
const BESIDE := Vector2i(4, 0)
## Where the file goes for the save and reopen.
static var scratch_path: String = SaDataRoot.path("f5_levels_adjustment.sad")

var _easel: SaEasel = null
var _document: SaDocument = null
var _registry: SaFilterRegistry = null
var _types: SaLayerTypeRegistry = null
var _window: SaFilterEditWindow = null
var _key: StringName = &""


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(SaChunk.SIZE * (BAND_BINS.size() + 1), SaChunk.SIZE))
    var registries := Fixtures.make_registries()
    _easel.compositor.set_registry(registries.blend_modes)
    _types = registries.layer_types
    _registry = SaFilterRegistry.new()
    var levels := SaLevelsFilter.new()
    _registry.register(levels, OWNER)
    _key = SaFilterRegistry.key_for(OWNER, levels)
    _easel.compositor.filter_chain.registry = _registry
    _document = _easel.document
    _window = SaFilterEditWindow.new()
    _window.watch(_registry)


func after_each() -> void:
    _window.free()
    _window = null
    _easel.free()
    _easel = null
    _document = null
    _registry = null
    _types = null


## The band over "Low" and "High", the background emptied and hidden, and
## "High" active, where the Filter dialog's Layer way puts the adjustment.
func _paint_band() -> Array[SaLayer]:
    var ops := SaLayerOps.new(_document)
    var background := _document.get_node("Background") as SaLayer
    for grid_pos: Vector2i in background.chunks.keys():
        background.chunks.erase(grid_pos)
    background.visible = false
    var low := _document.get_node("Layer 1") as SaLayer
    low.name = "Low"
    var high := ops.add()
    high.name = "High"
    for index in BAND_BINS.size():
        var layer := low if index < 2 else high
        layer.get_or_create_chunk(Vector2i(index, 0)).clear(_grey(BAND_BINS[index]))
    _document.set_active_layer(high)
    return [low, high]


static func _grey(bin: int) -> Color:
    var v := float(bin) / 255.0
    return Color(v, v, v, 1.0)


## A Levels adjustment layer above the active layer, as the Filter dialog's
## Layer way adds it, and its record.
func _adjust() -> SaAttachedFilter:
    var layer := SaFilterConversion.new(_document).add_holding(_key, SaLevelsFilter.new().parameters(), _types, "Levels")
    assert_true(layer != null and layer.is_adjustment(), "A Levels adjustment layer is added")
    if layer == null:
        return null
    assert_eq(layer.filters.size(), 1, "holding one record")
    return layer.filters[0]


## The output's luma row, lowest and highest occupied bin, as levels.
func _output_span() -> Vector2:
    Bench.composite(_easel)
    var plot := SaGraphPlot.new()
    plot.scale = "linear"
    plot.histogram_channel = "master"
    assert_true(plot.run_over_document(_easel.output, _document.canvas_size, _document.color_space, "histogram"), "Binned")
    var counts := plot.read_counts()
    var low := -1
    var high := -1
    for bin in SaGraphPlot.BINS:
        if _at(counts, bin) > 0:
            if low < 0:
                low = bin
            high = bin
    return Vector2(float(low), float(high)) / 255.0


static func _at(counts: PackedInt32Array, bin: int) -> int:
    var index := SaAdjustGraph.LUMA_ROW * SaGraphPlot.BINS + bin
    return counts[index] if index < counts.size() else 0


## Opens the record in the edit window, presses Equalize and applies.
func _press(record: SaAttachedFilter) -> bool:
    _window.open(record, _document)
    var panel := _window.find_child("LevelsPanel", true, false) as SaLevelsPanel
    assert_true(panel != null, "The edit window shows the Levels panel")
    if panel == null:
        return false
    assert_eq(panel.attached_host(), [_document, record], "which knows the record it edits")
    var pressed := panel.equalize()
    _window.dialog.flush_rerun()
    _window.accept()
    return pressed


## The one adjustment layer's record after a load, its kind bound again the
## way opening a file binds it.
func _record_after_load() -> SaAttachedFilter:
    var layers: Array[SaLayer] = []
    for child in _document.get_children():
        if child is SaLayer:
            layers.append(child)
    _types.rebind(layers)
    for layer in layers:
        if layer.is_adjustment() and layer.filters.size() == 1:
            return layer.filters[0]
    return null


func test_equalize_spreads_the_output_and_the_map_holds() -> void:
    var painted := _paint_band()
    var record := _adjust()
    if record == null:
        return
    var adjustment := SaNodeHistogram.node_of(_document, record)
    assert_true(adjustment[0] and (adjustment[1] as SaLayer).is_adjustment(), "The record is found on its adjustment layer")
    var before := _output_span()
    assert_true(before.y - before.x < 0.1, "The band is narrow before: %s" % before)

    assert_true(_press(record), "Equalize takes a map from the backdrop")
    var map := record.parameters.get("equalize", []) as Array
    assert_eq(map.size(), SaPointAdjust.EQUALIZE_SAMPLES, "which the record keeps")
    var after := _output_span()
    assert_true(after.x < 0.02 and after.y > 0.98, "Equalized, the output spans the range: %s" % after)

    # A stroke below the adjustment leaves the map as it was.
    var low := painted[0]
    low.get_or_create_chunk(Vector2i(0, 0)).clear(Color(0.9, 0.9, 0.9, 1.0))
    _document.invalidate_all_allocated_chunks()
    Bench.composite(_easel)
    assert_eq(record.parameters.get("equalize"), map, "A stroke below after Equalize leaves the map")

    assert_eq(SaExport.save_sad(_document, scratch_path, 0), OK, "Saved")
    var loaded := SaExport.load_sad(_document, ProjectSettings.globalize_path(scratch_path))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_path))
    assert_eq(loaded, OK, "and reopened")
    var reopened := _record_after_load()
    assert_true(reopened != null, "The adjustment layer's record comes back")
    if reopened == null:
        return
    var kept := reopened.parameters.get("equalize", []) as Array
    assert_eq(kept.size(), map.size(), "with its map")
    var most := 0.0
    for index in mini(kept.size(), map.size()):
        most = maxf(most, absf(float(kept[index]) - float(map[index])))
    assert_true(most < 1e-6, "entry for entry: %f" % most)


## At the top level the backdrop is every layer below the adjustment and none
## above it.
func test_the_backdrop_holds_the_layers_below_and_none_above() -> void:
    _paint_band()
    var record := _adjust()
    if record == null:
        return
    var above := SaLayerOps.new(_document).add()
    above.name = "Above"
    above.get_or_create_chunk(BESIDE).clear(_grey(STRAY_BIN))
    var node := SaNodeHistogram.node_of(_document, record)[1] as SaLayer
    var counts := SaNodeHistogram.new(_document).counts(node, "master")
    for bin in BAND_BINS:
        assert_true(_at(counts, bin) > 0, "The backdrop holds the band's level %d" % bin)
    assert_eq(_at(counts, STRAY_BIN), 0, "and nothing of the layer above it")


## Inside an isolated group the backdrop is the members below the adjustment,
## and neither a layer under the group nor a member above it.
func test_inside_an_isolated_group_it_reads_the_members_below_only() -> void:
    var painted := _paint_band()
    var ops := SaLayerOps.new(_document)
    var outside := ops.add()
    outside.name = "Outside"
    _document.move_child(outside, 0)
    outside.get_or_create_chunk(BESIDE).clear(_grey(STRAY_BIN))
    outside.get_or_create_chunk(Vector2i(0, 0)).clear(_grey(STRAY_BIN))
    # Low at half alpha over the outside layer: the group's composite is Low
    # over transparent, and the top level's would be Low over the stray grey.
    var v := float(BAND_BINS[0]) / 255.0
    painted[0].get_or_create_chunk(Vector2i(0, 0)).clear(Color(v, v, v, 0.5))
    var group := ops.group_layers(painted)
    ops.set_isolated(group, true)
    _document.set_active_layer(painted[1])
    var record := _adjust()
    if record == null:
        return
    var node := SaNodeHistogram.node_of(_document, record)[1] as SaLayer
    assert_eq(SaLayerStack.parent_of(node), group, "The adjustment is a member of the group")
    assert_eq(SaTreeRender.scope_of(node), group, "whose composite it reads")
    var top := ops.add()
    top.name = "Top member"
    top.group = group
    _document.move_child(top, node.get_index() + 1)
    top.get_or_create_chunk(Vector2i(1, 0)).clear(_grey(40))

    var counts := SaNodeHistogram.new(_document).counts(node, "master")
    for bin: int in BAND_BINS.slice(1):
        assert_true(_at(counts, bin) > 0, "The backdrop holds the member's level %d" % bin)
    assert_eq(_at(counts, STRAY_BIN), 0, "and nothing of the layer under the group")
    assert_eq(_at(counts, 40), 0, "nor of the member above it")

    var chunk := SaTexture.new(SaDocument.WHOLE_CHUNK.size, SaFieldSpec.schema_for_space(_document.color_space)[0].format)
    _easel.compositor.clear_scratch_batch([[chunk, SaDocument.WHOLE_CHUNK]])
    SaTreeRender.new(_document).render_below(chunk, Vector2i(0, 0), node)
    var texel := Bench.texel(chunk, Vector2i(8, 8))
    assert_true(absf(texel.a - 0.5) < 0.01, "The render up to the adjustment is Low over transparent: %s" % texel)
    ops.set_isolated(group, false)
    assert_eq(SaTreeRender.scope_of(node), null, "A pass-through group reads the top level")
    _easel.compositor.clear_scratch_batch([[chunk, SaDocument.WHOLE_CHUNK]])
    SaTreeRender.new(_document).render_below(chunk, Vector2i(0, 0), node)
    texel = Bench.texel(chunk, Vector2i(8, 8))
    assert_true(texel.a > 0.99, "and there Low sits over the stray grey: %s" % texel)
