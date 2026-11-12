## Equalize on a Levels record attached to a paint layer, a group
## or the document's root takes its map from what that record filters.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The band, four levels a few bins apart, is split over two
## layers, two chunks each, and the active layer is the empty background. So no
## one layer holds the band a group's or the root's record reads, and the
## active layer the Filter menu's dialog reads holds none of it: a map taken
## from either would not spread the composite. Each press goes through the
## Levels panel in the edit window a double click opens, which is where a
## painter presses it.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## Real dispatches into real chunks.
const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
const BAND_BINS: Array[int] = [102, 108, 114, 120]
## Where the file goes for the save and reopen.
static var scratch_path: String = SaDataRoot.path("l2_attached_levels.sad")

var _easel: SaEasel = null
var _document: SaDocument = null
var _registry: SaFilterRegistry = null
var _window: SaFilterEditWindow = null
var _key: StringName = &""


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(SaChunk.SIZE * BAND_BINS.size(), SaChunk.SIZE))
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
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


## The band over two layers, "Low" holding the first two levels and "High"
## the last two, and the background emptied and made active.
func _paint_band() -> Array[SaLayer]:
    var ops := SaLayerOps.new(_document)
    var background := _document.get_node("Background") as SaLayer
    for grid_pos: Vector2i in background.chunks.keys():
        background.chunks.erase(grid_pos)
    var low := _document.get_node("Layer 1") as SaLayer
    low.name = "Low"
    var high := ops.add()
    high.name = "High"
    for index in BAND_BINS.size():
        var v := float(BAND_BINS[index]) / 255.0
        var layer := low if index < 2 else high
        layer.get_or_create_chunk(Vector2i(index, 0)).clear(Color(v, v, v, 1.0))
    _document.set_active_layer(background)
    return [low, high]


## The node each case attaches to: the low layer, a group of both, the root.
func _node_for(case: String, painted: Array[SaLayer]) -> SaLayer:
    match case:
        "layer":
            return painted[0]
        "group":
            return SaLayerOps.new(_document).group_layers(painted)
    return null


## The composite's luma row, lowest and highest occupied bin, as levels.
func _composite_span() -> Vector2:
    Bench.composite(_easel)
    var plot := SaGraphPlot.new()
    plot.scale = "linear"
    plot.histogram_channel = "master"
    assert_true(plot.run_over_document(_easel.output, _document.canvas_size, _document.color_space, "histogram"), "Binned")
    var counts := plot.read_counts()
    var low := -1
    var high := -1
    for bin in SaGraphPlot.BINS:
        if counts[SaAdjustGraph.LUMA_ROW * SaGraphPlot.BINS + bin] > 0:
            if low < 0:
                low = bin
            high = bin
    return Vector2(float(low), float(high)) / 255.0


## Opens the record in the edit window, presses Equalize in its Levels panel
## and applies, the way a painter does it.
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


## The record of the one Levels on the node of *case* after a load.
func _record_after_load(case: String) -> SaAttachedFilter:
    if case == "root":
        return _document.root_filters[0] if _document.root_filters.size() == 1 else null
    for child in _document.get_children():
        var layer := child as SaLayer
        if layer == null or layer.filters.size() != 1:
            continue
        if (case == "group") == layer.is_group:
            return layer.filters[0]
    return null


func _check(case: String) -> void:
    var painted := _paint_band()
    var node := _node_for(case, painted)
    var record := SaFilterOps.new(_document).attach(node, _key, SaLevelsFilter.new().parameters())
    assert_eq(SaNodeHistogram.node_of(_document, record), [true, node], "The record is found on its node, %s" % case)
    var before := _composite_span()
    assert_true(before.y - before.x < 0.1, "The band is narrow before, %s: %s" % [case, before])

    assert_true(_press(record), "Equalize takes a map from the record's input, %s" % case)
    var map := record.parameters.get("equalize", []) as Array
    assert_eq(map.size(), SaPointAdjust.EQUALIZE_SAMPLES, "which the record keeps, %s" % case)

    var after := _composite_span()
    # On the low layer its two levels go to black and to white, and the high
    # layer's two stay between them.
    assert_true(after.x < 0.02 and after.y > 0.98, "Equalized, the composite spans the range, %s: %s" % [case, after])

    # A stroke under the record leaves the map as it was.
    var low := painted[0]
    low.get_or_create_chunk(Vector2i(0, 0)).clear(Color(0.9, 0.9, 0.9, 1.0))
    _document.invalidate_all_allocated_chunks()
    Bench.composite(_easel)
    assert_eq(record.parameters.get("equalize"), map, "A stroke after Equalize leaves the map, %s" % case)
    low.get_or_create_chunk(Vector2i(0, 0)).clear(Color(0.4, 0.4, 0.4, 1.0))

    assert_eq(SaExport.save_sad(_document, scratch_path, 0), OK, "Saved, %s" % case)
    var loaded := SaExport.load_sad(_document, ProjectSettings.globalize_path(scratch_path))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_path))
    assert_eq(loaded, OK, "and reopened, %s" % case)
    var reopened := _record_after_load(case)
    assert_true(reopened != null, "The record comes back, %s" % case)
    if reopened == null:
        return
    var kept := reopened.parameters.get("equalize", []) as Array
    assert_eq(kept.size(), map.size(), "with its map, %s" % case)
    var most := 0.0
    for index in mini(kept.size(), map.size()):
        most = maxf(most, absf(float(kept[index]) - float(map[index])))
    assert_true(most < 1e-6, "entry for entry, %s: %f" % [case, most])


func test_a_layers_record_equalizes_from_its_paint() -> void:
    _check("layer")


func test_a_groups_record_equalizes_from_the_groups_composite() -> void:
    _check("group")


func test_the_roots_record_equalizes_from_the_composite_under_it() -> void:
    _check("root")


## The group's input is its members before its own records: a second press,
## with the first map in place, reads the band again rather than the
## equalized composite, so it takes the same map.
func test_a_second_press_reads_the_input_not_the_output() -> void:
    var painted := _paint_band()
    var group := _node_for("group", painted)
    var record := SaFilterOps.new(_document).attach(group, _key, SaLevelsFilter.new().parameters())
    assert_true(_press(record), "The first press")
    var first := record.parameters["equalize"] as Array
    assert_true(_press(record), "The second press")
    assert_eq(record.parameters["equalize"], first, "takes the same map")


## The Filter menu's dialog is no record's, so it keeps reading the active
## layer, and the node histogram answers nothing for a record the document
## does not hold.
func test_the_dialog_has_no_record_and_a_stray_record_no_node() -> void:
    var panel := SaLevelsPanel.new()
    assert_eq(panel.attached_host(), [], "A panel outside an edit window edits no record")
    panel.free()
    var stray := SaAttachedFilter.new(_key, {})
    assert_eq(SaNodeHistogram.node_of(_document, stray), [false, null], "and a stray record hangs nowhere")
