## The door's `SaNodeHistogram` answers a node's input binned for
## a channel, and its counts are the Graph docker's plot's for the same input,
## bin for bin, on every channel.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Beside the plot rather than beside the door, because the plot is what the
## door is measured against and a suite under `core` names no `ui` class.
## Two paint layers hold a chunk each, a chunk apart, in two colours no channel
## of which is flat, and the background is emptied. The four nodes a record
## hangs on are each asked: a paint layer, a group of both, the root and an
## adjustment layer over both, whose input is its backdrop. The plot bins the
## very input the door does, `SaNodeInput`, through `run_over_sources`, and a
## paint layer through `run_over_layer` as well, which is what the Filter
## menu's dialog graphs.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const WARM := Color(0.8, 0.35, 0.1, 1.0)
const COOL := Color(0.15, 0.55, 0.9, 1.0)
const LEFT := Vector2i(0, 0)
const RIGHT := Vector2i(2, 0)
const CHANNELS: Array[String] = ["master", "red", "green", "blue", "lightness"]

var _easel: SaEasel = null
var _doc: SaDocument = null
var _left: SaLayer = null
var _right: SaLayer = null


func before_each() -> void:
    _easel = Bench.easel(Vector2i(3 * SaChunk.SIZE, SaChunk.SIZE))
    _doc = _easel.document
    var background := _doc.get_node("Background") as SaLayer
    for grid_pos: Vector2i in background.chunks.keys():
        background.chunks.erase(grid_pos)
    _left = _doc.get_node("Layer 1") as SaLayer
    _left.get_or_create_chunk(LEFT).clear(WARM)
    _right = SaLayerOps.new(_doc).add()
    _right.get_or_create_chunk(RIGHT).clear(COOL)
    _doc.update_caches()


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _left = null
    _right = null


## The plot's count buffer of *node*'s input on *channel*, binned the way the
## Levels graph bins it: linear, histogram, the channel's rows.
func _plotted(node: SaLayer, channel: String) -> PackedInt32Array:
    var plot := _levels_plot(channel)
    var input := SaNodeInput.new(_doc, node)
    if not plot.run_over_sources(input.positions(), input.at, _doc.color_space, "histogram"):
        return PackedInt32Array()
    return plot.read_counts()


func _levels_plot(channel: String) -> SaGraphPlot:
    var plot := SaGraphPlot.new()
    plot.scale = "linear"
    plot.histogram_channel = channel
    return plot


## The door's counts against the plot's on every channel, and something binned.
func _door_matches_the_plot(node: SaLayer, subject: String) -> void:
    for channel in CHANNELS:
        var door := SaNodeHistogram.new(_doc).counts(node, channel)
        var whole := "The door answers the whole count buffer for the %s on %s" % [subject, channel]
        assert_eq(door.size(), SaGraphParams.LIVE_SLOT, whole)
        var total := 0
        for bin in SaGraphParams.BINS * 4:
            total += door[bin]
        assert_true(total > 0, "and bins the %s's input on %s" % [subject, channel])
        assert_eq(door, _plotted(node, channel), "and the %s's %s counts are the plot's, bin for bin" % [subject, channel])


func test_a_paint_layer() -> void:
    _door_matches_the_plot(_left, "paint layer")
    for channel in CHANNELS:
        var plot := _levels_plot(channel)
        assert_true(plot.run_over_layer(_left, _doc.color_space, "histogram"), "The plot bins the layer's own chunks")
        var door := SaNodeHistogram.new(_doc).counts(_left, channel)
        assert_eq(door, plot.read_counts(), "and the door's %s counts are the Filter dialog's graph's too" % channel)


func test_a_group() -> void:
    var group := SaLayerOps.new(_doc).group_layers([_left, _right])
    _doc.update_caches()
    _door_matches_the_plot(group, "group")


func test_the_root() -> void:
    _door_matches_the_plot(null, "root")


func test_an_adjustment_layer() -> void:
    _doc.set_active_layer(_right)
    var types := Fixtures.make_registries().layer_types
    var layer := SaLayerOps.new(_doc).add(SaBackdropLayer.TYPE_ID, types)
    assert_true(layer != null and layer.is_adjustment(), "An adjustment layer is added over both")
    if layer == null:
        return
    _doc.update_caches()
    _door_matches_the_plot(layer, "adjustment layer")


func test_a_node_with_nothing_to_bin_answers_empty() -> void:
    var empty := SaLayerOps.new(_doc).add()
    assert_eq(SaNodeHistogram.new(_doc).counts(empty, "master"), PackedInt32Array(), "A layer with no paint answers nothing")
    assert_eq(SaNodeHistogram.new(null).counts(null, "master"), PackedInt32Array(), "and so does no document")
