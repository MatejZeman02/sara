## Levels and Curves give a readable histogram, eyedroppers
## and an Equalize mark.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A layer of three flat levels, one chunk each, which is the painted layer
## the row was about: each level is one bin. The bars are read off the plot's
## own picture, one readback in a suite, and off what the Levels graph reports
## to a capture. The eyedroppers take their picks through the panel's own
## `sample_at`, which is what a click on the canvas lands in, and the click
## itself, the hold and Escape are the running app's, in
## `scenarios/levels-and-curves-give-a-readable-histogram-eyedroppers-and-an.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Real dispatches into real chunks.
const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"

## Three levels, each exactly on a bin and far apart, so each draws a bar of
## its own.
const STROKE_BINS: Array[int] = [38, 128, 217]

## How wide the Levels dialog shows its graph, in logical pixels, measured on
## the running app at a scale of one.
const DIALOG_GRAPH_WIDTH := 480.0

## A texel row near the foot of the picture, inside every bar and on no grid
## line.
const FOOT_ROW := 250

var _easel: SaEasel = null
var _registry: SaFilterRegistry = null
var _key: StringName = &""
var _window: SaFilterEditWindow = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(SaChunk.SIZE * STROKE_BINS.size(), SaChunk.SIZE))
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _registry = SaFilterRegistry.new()
    var levels := SaLevelsFilter.new()
    _registry.register(levels, OWNER)
    _key = SaFilterRegistry.key_for(OWNER, levels)
    _easel.compositor.filter_chain.registry = _registry
    _window = SaFilterEditWindow.new()
    _window.watch(_registry)


func after_each() -> void:
    _window.free()
    _window = null
    _easel.free()
    _easel = null
    _registry = null


## A Levels record attached to *layer*, opened in the edit window a painter
## double clicks it into, and its panel.
func _open_levels(layer: SaLayer) -> SaLevelsPanel:
    var record := SaFilterOps.new(_easel.document).attach(layer, _key, SaLevelsFilter.new().parameters())
    _window.open(record, _easel.document)
    var panel := _window.find_child("LevelsPanel", true, false) as SaLevelsPanel
    assert_true(panel != null, "The edit window shows the Levels panel")
    return panel


## The three flat levels on the easel's first layer, made active.
func _paint_strokes() -> SaLayer:
    var layer := _easel.document.get_node_or_null("Layer 1") as SaLayer
    for index in STROKE_BINS.size():
        var v := float(STROKE_BINS[index]) / 255.0
        layer.get_or_create_chunk(Vector2i(index, 0)).clear(Color(v, v, v, 1.0))
    _easel.document.set_active_layer(layer)
    return layer


## The columns of *plot*'s picture lit at `FOOT_ROW`, brighter than the grid
## drawn over the background, as runs `[first, width]` from left to right.
func _lit_runs(plot: SaGraphPlot) -> Array[Vector2i]:
    var runs: Array[Vector2i] = []
    if plot.shown == null:
        return runs
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(plot.shown.texture_rd_rid, 0)
    var width := plot.plot_size.x
    var lit := 0.35
    for x in width:
        # RGBA16F, eight bytes a texel.
        var value := bytes.decode_half((FOOT_ROW * width + x) * 8)
        if value < lit:
            continue
        if not runs.is_empty() and runs[-1].x + runs[-1].y == x:
            runs[-1].y += 1
        else:
            runs.append(Vector2i(x, 1))
    return runs


## The Master histogram of *layer* drawn at *reach*, the plot answered.
func _draw(layer: SaLayer, reach: int) -> SaGraphPlot:
    var plot := SaGraphPlot.new()
    plot.scale = "linear"
    plot.histogram_channel = "master"
    plot.bar_reach = reach
    assert_true(plot.run_over_layer(layer, SaColorSpace.srgb(), "histogram"), "The pass runs at a reach of %d" % reach)
    return plot


func test_a_lone_level_is_a_bar_at_least_three_pixels_wide_in_the_dialog() -> void:
    var layer := _paint_strokes()
    var reach := SaGraphPlot.bar_reach_for(DIALOG_GRAPH_WIDTH)
    assert_true(reach >= 1, "The dialog's width asks for bars, a reach of %d" % reach)
    var width := SaGraphPlot.bar_width(reach, DIALOG_GRAPH_WIDTH)
    assert_true(width >= 3.0, "and a lone level is %.2f logical pixels wide, three at the least" % width)
    var runs := _lit_runs(_draw(layer, reach))
    assert_eq(runs.size(), STROKE_BINS.size(), "Three strokes draw three bars: %s" % str(runs))
    for index in mini(runs.size(), STROKE_BINS.size()):
        var bin := STROKE_BINS[index]
        assert_eq(runs[index], Vector2i(bin - reach, 2 * reach + 1), "the bar of bin %d spans its reach either side" % bin)


func test_the_graph_docker_keeps_a_column_a_bin() -> void:
    var layer := _paint_strokes()
    var runs := _lit_runs(_draw(layer, 0))
    assert_eq(runs.size(), STROKE_BINS.size(), "The docker's picture shows the three levels: %s" % str(runs))
    # The docker spreads 256 bins over 256 texels by rounding, which gives the
    # odd bin two columns, the middle one among them.
    for run in runs:
        assert_true(run.y <= 2, "each a column a texel or two wide, as it was: %s" % str(run))


func test_a_narrow_graph_asks_for_a_wider_reach() -> void:
    for shown: float in [128.0, 256.0, 380.0, 480.0, 900.0]:
        var reach := SaGraphPlot.bar_reach_for(shown)
        var width := SaGraphPlot.bar_width(reach, shown)
        assert_true(width >= SaGraphPlot.BAR_MIN_WIDTH, "At %d pixels a bar is %.2f wide" % [int(shown), width])
        assert_true(reach >= 1 and reach <= SaGraphParams.BAR_MASK, "with a reach the flags word carries, %d" % reach)


func test_the_levels_graph_reports_its_bar_width() -> void:
    var panel := _open_levels(_paint_strokes())
    if panel == null:
        return
    var graph := panel._histogram
    graph.size = Vector2(DIALOG_GRAPH_WIDTH, float(SaAdjustGraph.HEIGHT))
    graph.refresh()
    var state := graph.capture_state()
    assert_eq(int(state.get("bar_reach", -1)), SaGraphPlot.bar_reach_for(DIALOG_GRAPH_WIDTH), "The capture says the reach")
    var width := float(state.get("bar_width", 0.0))
    assert_true(width >= 3.0, "and the width a lone level is drawn at, %.2f" % width)
    var bins: Array = state.get("bins", [])
    var filled := 0
    for count: int in bins:
        filled += 1 if count > 0 else 0
    assert_eq(filled, STROKE_BINS.size(), "over the three levels the layer holds")


func test_the_curves_graph_draws_the_same_bars() -> void:
    var layer := _paint_strokes()
    var panel := SaCurvesPanel.new()
    panel.take_histogram(layer, SaColorSpace.srgb())
    var reach := panel._plot.bar_reach
    assert_eq(reach, SaGraphPlot.bar_reach_for(float(SaCurvesPanel.GRAPH_SIZE)), "Curves asks for the reach of its own width")
    var width := SaGraphPlot.bar_width(reach, float(SaCurvesPanel.GRAPH_SIZE))
    assert_true(width >= 3.0, "so a lone level behind the curve is %.2f pixels wide" % width)
    panel.free()


## The middle of the stroke at *index*, in document coordinates.
static func _stroke(index: int) -> Vector2:
    return Vector2((float(index) + 0.5) * SaChunk.SIZE, 0.5 * SaChunk.SIZE)


func test_the_black_eyedropper_writes_the_level_it_reads_into_the_black_point() -> void:
    var panel := _open_levels(_paint_strokes())
    if panel == null:
        return
    var heard := [0]
    panel.changed.connect(func() -> void: heard[0] += 1)
    assert_true(panel.sample_at("black", _stroke(0)), "A pick on the dark stroke lands")
    assert_almost_eq(panel.values()["in_black"], float(STROKE_BINS[0]) / 255.0, 0.003, "and the black point is its level")
    assert_eq(heard[0], 1, "as one change, so one step where the panel writes steps")


func test_the_grey_eyedropper_moves_the_gamma_so_the_level_lands_in_the_middle() -> void:
    var panel := _open_levels(_paint_strokes())
    if panel == null:
        return
    panel.set_values({"in_black": 0.1, "in_white": 0.9})
    var level := float(STROKE_BINS[1]) / 255.0
    assert_true(panel.sample_at("grey", _stroke(1)), "A pick on the middle stroke lands")
    var shown: Dictionary = panel.values()
    var gamma := float(shown["gamma"])
    assert_true(absf(gamma - 1.0) > 0.01, "and moves the gamma off one, to %.3f" % gamma)
    var t := (level - 0.1) / 0.8
    assert_almost_eq(pow(t, 1.0 / gamma), 0.5, 0.01, "so the stroke's level comes out half way")
    var grey_handle := SaLevelsPanel.gamma_position(0.1, gamma, 0.9)
    assert_almost_eq(grey_handle, level, 0.005, "with the grey handle standing under it")
    assert_almost_eq(float(shown["in_black"]), 0.1, 0.0001, "and the black point")
    assert_almost_eq(float(shown["in_white"]), 0.9, 0.0001, "and the white point where they were")


func test_the_white_eyedropper_writes_the_level_it_reads_into_the_white_point() -> void:
    var panel := _open_levels(_paint_strokes())
    if panel == null:
        return
    assert_true(panel.sample_at("white", _stroke(2)), "A pick on the light stroke lands")
    assert_almost_eq(panel.values()["in_white"], float(STROKE_BINS[2]) / 255.0, 0.003, "and the white point is its level")


func test_a_pick_never_crosses_the_black_and_white_points() -> void:
    var panel := _open_levels(_paint_strokes())
    if panel == null:
        return
    panel.set_values({"in_white": 0.3})
    panel.sample_at("black", _stroke(2))
    var shown: Dictionary = panel.values()
    var under := float(shown["in_black"]) < float(shown["in_white"])
    assert_true(under, "A black pick lighter than the white point stays under it: %s" % str(shown))


func test_a_pick_where_nothing_is_painted_moves_nothing() -> void:
    var panel := _open_levels(_paint_strokes())
    if panel == null:
        return
    var before: Dictionary = panel.values()
    assert_false(panel.sample_at("black", Vector2(-4.0, -4.0)), "Off the canvas there is nothing to read")
    var layer := _easel.document.active_layer
    layer.chunks.erase(Vector2i(1, 0))
    assert_false(panel.sample_at("white", _stroke(1)), "nor where the layer holds no chunk")
    assert_eq(panel.values(), before, "and the handles stay")


func test_a_colour_channel_reads_its_own_value_and_lightness_reads_oklab_l() -> void:
    var layer := _paint_strokes()
    layer.get_or_create_chunk(Vector2i(0, 0)).clear(Color(0.8, 0.3, 0.1, 1.0))
    var panel := _open_levels(layer)
    if panel == null:
        return
    panel.set_values({"channel": "red"})
    assert_almost_eq(panel.level_at(_stroke(0)), 0.8, 0.001, "Red reads the red value")
    panel.set_values({"channel": "master"})
    assert_almost_eq(panel.level_at(_stroke(0)), Vector3(0.8, 0.3, 0.1).dot(SaLevelsSampler.LUMA), 0.001, "Master reads the luma")
    panel.set_values({"channel": "lightness"})
    var curve := SaTransferFunction.srgb()
    var light := Vector3(curve.decode(0.8), curve.decode(0.3), curve.decode(0.1))
    assert_almost_eq(panel.level_at(_stroke(0)), SaOklab.from_linear_srgb(light).x, 0.001, "and Lightness reads Oklab L")


func test_an_equalized_panel_reads_the_level_the_handles_move_over() -> void:
    var panel := _open_levels(_paint_strokes())
    if panel == null:
        return
    var plain := panel.level_at(_stroke(0))
    assert_true(panel.equalize(), "Equalize takes a map")
    # Three levels of a third each: the map spreads them over the whole range,
    # the darkest to black and the lightest to white.
    assert_almost_eq(panel.level_at(_stroke(0)), 0.0, 0.02, "The dark stroke reads black after it, from %.3f" % plain)
    assert_almost_eq(panel.level_at(_stroke(2)), 1.0, 0.02, "and the light one white")


func test_an_eyedropper_button_reads_pressed_while_it_is_armed() -> void:
    var panel := _open_levels(_paint_strokes())
    if panel == null:
        return
    var buttons := {}
    for kind: String in SaLevelsSampler.KINDS:
        buttons[kind] = panel.find_child(kind.capitalize() + "Eyedropper", true, false) as Button
        assert_true(buttons[kind] != null, "The %s eyedropper stands on the channel line" % kind)
    if buttons.values().has(null):
        return
    (buttons["black"] as Button).pressed.emit()
    assert_eq(panel._sampler.kind, "black", "Its press arms the black eyedropper")
    assert_true((buttons["black"] as Button).button_pressed, "which reads pressed")
    panel.arm_eyedropper("white")
    assert_eq(panel._sampler.kind, "white", "Another one's press arms that one instead")
    assert_false((buttons["black"] as Button).button_pressed, "and the first lets go")
    panel.arm_eyedropper("white")
    assert_eq(panel._sampler.kind, "", "A second press puts it away")
    assert_false((buttons["white"] as Button).button_pressed, "and nothing reads pressed")


func test_escape_puts_the_armed_eyedropper_away_and_hiding_the_panel_does_too() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var embedding := tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "S62EscapeHost"
    EventBus.add_child(host)
    host.add_child(_window)
    var panel := _open_levels(_paint_strokes())
    if panel != null:
        _escape_and_hide(panel, tree)
    host.remove_child(_window)
    host.free()
    tree.root.gui_embed_subwindows = embedding


func _escape_and_hide(panel: SaLevelsPanel, tree: SceneTree) -> void:
    panel.arm_eyedropper("grey")
    var escape := InputEventKey.new()
    escape.keycode = KEY_ESCAPE
    escape.pressed = true
    tree.root.window_input.emit(escape)
    assert_eq(panel._sampler.kind, "", "Escape on the root window puts the grey eyedropper away")
    panel.arm_eyedropper("black")
    _window.hide()
    assert_eq(panel._sampler.kind, "", "and the window closing puts the black one away")


func test_equalize_reads_pressed_with_its_caption_while_a_map_is_held() -> void:
    var panel := _open_levels(_paint_strokes())
    if panel == null:
        return
    var button := panel.find_child("EqualizeButton", true, false) as Button
    var caption := panel.find_child("EqualizeCaption", true, false) as Label
    assert_true(button != null and caption != null, "Equalize and its caption stand on their line")
    if button == null or caption == null:
        return
    assert_true(button.toggle_mode, "Equalize is a button that can read pressed")
    assert_false(button.button_pressed, "and does not before a press")
    assert_eq(caption.text, "", "with no caption")
    panel.set_values({"channel": "red"})
    button.button_pressed = true
    button.pressed.emit()
    assert_true(panel.has_map(), "The press takes a map")
    assert_true(button.button_pressed, "and Equalize reads pressed")
    assert_eq(caption.text, "Equalized using Lightness (Oklab)", "naming Oklab L, which the map is counted on, beside Reset")
    panel.set_values({"channel": "master"})
    assert_eq(caption.text, "Equalized using Lightness (Oklab)", "which a later channel change leaves as it was")
    var report := panel.capture_option_edit({"read": true})
    assert_true(report.contains('"equalize_pressed":true'), "The capture says so: %s" % report)
    panel.reset_equalize()
    assert_false(button.button_pressed, "Reset raises the button")
    assert_eq(caption.text, "Equalized using Lightness (Oklab)", "and the caption still says which map went")
    assert_true(caption.modulate.a < 0.5, "dimmed, %.2f, beside the Reset it dims" % caption.modulate.a)
    button.button_pressed = true
    button.pressed.emit()
    assert_eq(caption.modulate.a, 1.0, "A second press draws it at full strength again")


func test_a_press_with_nothing_to_read_leaves_equalize_raised() -> void:
    var panel := _open_levels(_easel.document.get_node_or_null("Layer 1") as SaLayer)
    if panel == null:
        return
    var button := panel.find_child("EqualizeButton", true, false) as Button
    button.button_pressed = true
    button.pressed.emit()
    assert_false(panel.has_map(), "An empty layer gives no map")
    assert_false(button.button_pressed, "so the button the press toggled reads raised again")


func test_a_record_holding_a_map_opens_with_equalize_pressed() -> void:
    var layer := _paint_strokes()
    var map: Array = []
    for index in SaPointAdjust.EQUALIZE_SAMPLES:
        map.append(float(index) / float(SaPointAdjust.EQUALIZE_SAMPLES - 1))
    var values := SaLevelsFilter.new().parameters()
    values["equalize"] = map
    values["equalize_channel"] = "lightness"
    var record := SaFilterOps.new(_easel.document).attach(layer, _key, values)
    _window.open(record, _easel.document)
    var panel := _window.find_child("LevelsPanel", true, false) as SaLevelsPanel
    assert_true(panel != null and panel.has_map(), "The record's map comes into the panel")
    if panel == null:
        return
    assert_true((panel.find_child("EqualizeButton", true, false) as Button).button_pressed, "Equalize reads pressed")
    var caption := panel.find_child("EqualizeCaption", true, false) as Label
    assert_eq(caption.text, "Equalized using Lightness (Oklab)", "and the caption names the channel")
