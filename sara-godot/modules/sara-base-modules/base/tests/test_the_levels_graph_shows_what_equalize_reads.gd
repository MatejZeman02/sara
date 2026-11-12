## The Levels graph of an attached record or an adjustment layer
## draws the input Equalize bins, and the Filter menu's dialog keeps the active
## layer.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A narrow band, four levels a few bins apart over two layers, the
## background emptied and hidden. Each case opens the record in the edit
## window a painter double clicks it into, holds the window offscreen, and
## drives the graph's poll by hand, since an offscreen window has no frame.
## The graph's counts are read off its own plot, one readback of counts and
## no texel, and compared bin for bin with what the press bins through
## `SaNodeHistogram`.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## Real dispatches into real chunks.
const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
const BAND_BINS: Array[int] = [102, 108, 114, 120]
## The channels the counts are compared on: Master and one colour channel.
const CHANNELS: Array[String] = ["master", "red"]

var _easel: SaEasel = null
var _document: SaDocument = null
var _registry: SaFilterRegistry = null
var _types: SaLayerTypeRegistry = null
var _window: SaFilterEditWindow = null
var _key: StringName = &""


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(SaChunk.SIZE * BAND_BINS.size(), SaChunk.SIZE))
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
## "High" active.
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
        var v := float(BAND_BINS[index]) / 255.0
        layer.get_or_create_chunk(Vector2i(index, 0)).clear(Color(v, v * 0.5, v, 1.0))
    _document.set_active_layer(high)
    return [low, high]


## A Levels adjustment layer above the active layer and its record.
func _adjust() -> SaAttachedFilter:
    var layer := SaFilterConversion.new(_document).add_holding(_key, SaLevelsFilter.new().parameters(), _types, "Levels")
    assert_true(layer != null and layer.is_adjustment(), "A Levels adjustment layer is added")
    return layer.filters[0] if layer != null and layer.filters.size() == 1 else null


## Opens *record* in the edit window and answers its Levels panel, with the
## graph's first poll taken, the one a window opening gets.
func _open(record: SaAttachedFilter) -> SaLevelsPanel:
    _window.open(record, _document)
    var panel := _window.find_child("LevelsPanel", true, false) as SaLevelsPanel
    assert_true(panel != null, "The edit window shows the Levels panel")
    if panel != null:
        panel._histogram.follow()
    return panel


## The graph's counts against the press's, bin for bin, on each channel of
## `CHANNELS`, and the press itself after.
func _graph_matches_the_press(panel: SaLevelsPanel, record: SaAttachedFilter, subject: String) -> void:
    var graph := panel._histogram
    assert_eq(graph.subject(), subject, "The graph draws the %s" % subject)
    var node := SaNodeHistogram.node_of(_document, record)[1] as SaLayer
    for channel in CHANNELS:
        panel.set_values({"channel": channel})
        assert_eq(graph.channel, channel, "on the %s channel" % channel)
        var pressed := SaNodeHistogram.new(_document).counts(node, channel)
        var shown := graph._plot.read_counts() if graph._plot != null else PackedInt32Array()
        assert_true(pressed.size() > 0, "The press bins something on %s" % channel)
        assert_eq(shown, pressed, "and the %s graph holds what the press bins, bin for bin" % channel)
        var passes := graph._passes
        assert_true(panel.equalize(), "Equalize takes a map on %s" % channel)
        assert_eq(graph._passes, passes + 1, "and the graph takes one pass after the press")
        assert_eq(graph._plot.read_counts(), pressed, "which still shows what the press read")


func test_an_adjustment_layers_graph_is_its_backdrop_with_it_active() -> void:
    _paint_band()
    var record := _adjust()
    if record == null:
        return
    var node := SaNodeHistogram.node_of(_document, record)[1] as SaLayer
    _document.set_active_layer(node)
    var panel := _open(record)
    if panel == null:
        return
    var tooltip := panel._histogram.tooltip_text
    var says := tooltip.contains("the picture under this adjustment layer")
    assert_true(says, "The tooltip says it graphs the picture under the layer: %s" % tooltip)
    _graph_matches_the_press(panel, record, "backdrop")


func test_an_adjustment_layers_graph_is_its_backdrop_with_the_painting_active() -> void:
    var painted := _paint_band()
    var record := _adjust()
    if record == null:
        return
    _document.set_active_layer(painted[0])
    var panel := _open(record)
    if panel == null:
        return
    _graph_matches_the_press(panel, record, "backdrop")


func test_a_groups_record_graphs_the_groups_composite() -> void:
    var painted := _paint_band()
    var group := SaLayerOps.new(_document).group_layers(painted)
    var record := SaFilterOps.new(_document).attach(group, _key, SaLevelsFilter.new().parameters())
    var panel := _open(record)
    if panel == null:
        return
    var tooltip := panel._histogram.tooltip_text
    assert_true(tooltip.contains("group"), "The tooltip says it graphs the group: %s" % tooltip)
    _graph_matches_the_press(panel, record, "group")


## The Filter menu's dialog edits no record, so its graph stays on the active
## layer and says so.
func test_the_filter_dialogs_graph_keeps_the_active_layer() -> void:
    _paint_band()
    var dialog := SaDialog.for_filter(_registry.get_filter(_key))
    var page := VBoxContainer.new()
    dialog.realize(page)
    var panel := page.find_child("LevelsPanel", true, false) as SaLevelsPanel
    assert_true(panel != null, "The Filter dialog shows the Levels panel")
    if panel != null:
        assert_eq(panel.attached_host(), [], "which edits no record")
        assert_eq(panel._histogram.subject(), "active layer", "so its graph draws the active layer")
        assert_true(panel._histogram.tooltip_text.contains("active layer"), "and its tooltip says so")
    page.free()


## A stroke under the adjustment layer takes no pass while it is held and one
## when it lets go, and a handle drag takes none.
func test_one_pass_after_a_stroke_and_none_under_a_drag() -> void:
    var painted := _paint_band()
    var record := _adjust()
    if record == null:
        return
    var panel := _open(record)
    if panel == null:
        return
    var graph := panel._histogram
    var opened := graph._passes
    assert_eq(opened, 1, "The window opening takes one pass")
    graph.follow()
    assert_eq(graph._passes, opened, "and a frame with nothing changed takes none")

    _document.set_active_layer(painted[0])
    _document.begin_stroke(1.0, &"normal")
    _document.stroke_layer.get_or_create_chunk(Vector2i(0, 0)).clear(Color(0.9, 0.9, 0.9, 1.0))
    _document.invalidate_all_allocated_chunks()
    for _frame in 3:
        Bench.composite(_easel)
        graph.follow()
    assert_eq(graph._passes, opened, "A held stroke's composites take no pass")
    _document.commit_stroke()
    for _frame in 3:
        Bench.composite(_easel)
        graph.follow()
    assert_eq(graph._passes, opened + 1, "and the stroke letting go takes one")

    var passes := graph._passes
    var before := record.parameters.duplicate(true)
    # An offscreen bar has no width to drag across until it is given one.
    panel._input_bar.size = Vector2(400.0, 40.0)
    for target: float in [0.2, 0.3, 0.4]:
        panel.drag_level_handle("in_black", target)
        _window.dialog.flush_rerun()
        Bench.composite(_easel)
        graph.follow()
    assert_true(record.parameters != before, "The drag moved the record's handles")
    assert_eq(graph._passes, passes, "and took no pass")
