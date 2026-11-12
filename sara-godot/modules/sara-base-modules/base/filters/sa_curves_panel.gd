## What the Curves filter hands its page: a channel dropdown, the curve over
## the active layer's histogram, and Reset.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## One `ui.custom` row, because a graph a painter shapes by dragging points is
## not one of the page's own widgets. It was the body of the skeleton's
## `SaCurvesDialog` until then. The graph is still the skeleton's
## `SaCurveEditor`, which the tablet sweep uses too, and the histogram behind
## it is the door's `SaGraphPlot`, the pass the Graph docker draws too.
##
## One curve per channel is kept while the filter is open, and the run sends
## all five at once, because Photoshop applies the master and the channel
## together and a painter who shaped two channels expects both.
class_name SaCurvesPanel
extends VBoxContainer

## A point moved, the channel changed or Reset was pressed, and the filter
## should run again.
signal changed

## How tall the graph is, in logical units. The page scrolls rather than
## stretches, so the graph asks for its height, and this is what fits the
## filter window with the Preview box and the buttons under it.
const GRAPH_SIZE := 380

var editor: SaCurveEditor = null

## Which channel the graph is showing.
var channel: String = "master"

var _channel_button: SaChoiceButton = null
var _plot: SaGraphPlot = null

## Channel id -> the points the painter left on it. The editor shows one at a
## time and this is where the other four wait.
var _curves: Dictionary = {}


func _init() -> void:
    name = "CurvesPanel"
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    add_theme_constant_override("separation", SaUI.px(8))

    var channel_line := HBoxContainer.new()
    channel_line.add_theme_constant_override("separation", SaUI.px(8))
    add_child(channel_line)
    var channel_label := Label.new()
    channel_label.text = tr("Channel")
    channel_label.custom_minimum_size = Vector2(float(SaUI.px(70)), 0.0)
    channel_line.add_child(channel_label)
    _channel_button = SaChoiceButton.new()
    _channel_button.name = "ChannelButton"
    _channel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var channels: Array = []
    for id: String in SaPointAdjust.CHANNELS:
        channels.append({"id": id, "label": tr(String(SaPointAdjust.CHANNEL_TITLES[id]))})
    _channel_button.set_choices(channels)
    _channel_button.select_value("master")
    _channel_button.choice_picked.connect(_on_channel_selected)
    channel_line.add_child(_channel_button)

    var reset_button := Button.new()
    reset_button.name = "ResetButton"
    reset_button.text = tr("Reset")
    reset_button.tooltip_text = tr("Put every channel's curve back on the diagonal.")
    reset_button.pressed.connect(reset)
    channel_line.add_child(reset_button)

    editor = SaCurveEditor.new()
    editor.name = "CurveEditor"
    editor.custom_minimum_size = Vector2(float(SaUI.px(GRAPH_SIZE)), float(SaUI.px(GRAPH_SIZE)))
    editor.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    editor.curve_changed.connect(_on_curve_changed)
    add_child(editor)

    var hint := Label.new()
    hint.text = tr("Click to add a point, drag it off the graph to remove it.")
    hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    hint.set_meta(SaUI.FONT_SCALE_META, 0.8)
    hint.modulate = Color(1.0, 1.0, 1.0, 0.7)
    add_child(hint)


## Draws *layer*'s histogram behind the curve, once per open: the curve is
## shaped against the picture as it stood when the filter opened. In bars as
## wide as Levels draws them, at the graph's own width, because a painted
## layer's few levels were spikes a pixel wide behind the curve too.
func take_histogram(layer: SaLayer, space: SaColorSpace) -> void:
    if _plot != null:
        return
    _plot = SaGraphPlot.new()
    _plot.bar_reach = SaGraphPlot.bar_reach_for(maxf(editor.size.x, editor.custom_minimum_size.x))
    editor.histogram = _plot.shown if _plot.run_over_layer(layer, space, "histogram") else null


## Whether the histogram has been taken for this open.
func has_histogram() -> bool:
    return _plot != null


## Every channel back on the diagonal, without touching the histogram.
func reset() -> void:
    _curves.clear()
    editor.reset()


## Shows *channel_id*, keeping what the painter left on the one before it.
func show_channel(channel_id: String) -> void:
    _remember()
    channel = channel_id if SaPointAdjust.CHANNELS.has(channel_id) else "master"
    _channel_button.select_value(channel)
    var stored: PackedVector2Array = _curves.get(channel, PackedVector2Array())
    if stored.size() >= 2:
        editor.set_points(stored)
    else:
        editor.reset()


## The five lookups, as `SaPointAdjust.table` reads them. A channel the painter
## never shaped is left out, and the table makes it the identity.
func values() -> Dictionary:
    _remember()
    var curves: Dictionary = {}
    for channel_id: String in _curves:
        var stored: PackedVector2Array = _curves[channel_id]
        if stored.size() >= 2:
            curves[channel_id] = SaCurveEditor.sample_curve(stored, SaCurveEditor.SAMPLES)
    return {"curves": curves}


## Sets a channel's points, the way a scenario or a test drives the panel.
func set_curve(channel_id: String, wanted: PackedVector2Array) -> void:
    _curves[channel_id] = wanted
    if channel_id == channel:
        editor.set_points(wanted)
    else:
        changed.emit()


## The points the painter left on each shaped channel,
## `{"curves": {channel: [[x, y], ...]}}`, which is what an attached
## filter's record keeps rather than the lookups [method values] samples
## from them.
func parameters() -> Dictionary:
    _remember()
    return {"curves": SaCurvesPanel.points_to_lists(_curves)}


## A record's points, drawn on the channel the graph shows, every other
## channel back on the diagonal unless the record shapes it.
func set_parameters(wanted: Dictionary) -> void:
    _curves = SaCurvesPanel.points_of(wanted)
    var stored: PackedVector2Array = _curves.get(channel, PackedVector2Array())
    if stored.size() >= 2:
        editor.set_points(stored)
    else:
        editor.reset()


## The shaped channels of a record as points by channel id. An entry that is
## not a list of at least two pairs is left out, so a record written wrong by
## hand loses that channel and not the filter.
static func points_of(record_values: Dictionary) -> Dictionary:
    var out: Dictionary = {}
    var shaped: Variant = record_values.get("curves", {})
    if not shaped is Dictionary:
        return out
    for channel_id: Variant in shaped:
        var entries: Variant = shaped[channel_id]
        if not SaPointAdjust.CHANNELS.has(String(channel_id)) or not entries is Array:
            continue
        var points := PackedVector2Array()
        for entry: Variant in entries:
            if entry is Array and (entry as Array).size() >= 2:
                points.append(Vector2(float(entry[0]), float(entry[1])))
        if points.size() >= 2:
            out[String(channel_id)] = points
    return out


## *curves*, points by channel id, as lists of pairs, which is what JSON carries.
static func points_to_lists(curves: Dictionary) -> Dictionary:
    var out: Dictionary = {}
    for channel_id: String in curves:
        var points: PackedVector2Array = curves[channel_id]
        if points.size() < 2:
            continue
        var pairs: Array = []
        for point in points:
            pairs.append([point.x, point.y])
        out[channel_id] = pairs
    return out


## The `curve` step's door and the `filter` step's, since the panel is a
## custom row: `{"channel": "master", "points": [[0, 0], [0.5, 0.75], [1, 1]]}`
## shapes a channel, the channel alone reads its points back, and `{"reset":
## true}` puts every channel back. `{"drag": [[1, 1], [0.8, 0.6]]}` drags
## from one point to another in curve units through the graph's own input, as a
## hand would.
func capture_option_edit(spec: Dictionary) -> String:
    if spec.get("reset", false):
        reset()
        return "SaCapture: curves reset"
    var points := PackedVector2Array()
    for entry: Variant in spec.get("points", []) as Array:
        var pair := entry as Array
        if pair != null and pair.size() >= 2:
            points.append(Vector2(float(pair[0]), float(pair[1])))
    var channel_id := String(spec.get("channel", "master"))
    if points.size() >= 2 or channel_id != channel:
        show_channel(channel_id)
    if points.size() >= 2:
        set_curve(channel_id, points)
    var ends := spec.get("drag", []) as Array
    if ends.size() == 2:
        if channel_id != channel:
            show_channel(channel_id)
        editor.drag_through(Vector2(ends[0][0], ends[0][1]), Vector2(ends[1][0], ends[1][1]))
        _remember()
    return "SaCapture: curve %s %s" % [channel_id, str(editor.points)]


func _remember() -> void:
    if editor.is_identity():
        _curves.erase(channel)
    else:
        _curves[channel] = editor.points.duplicate()


## The row's own channel id rather than a position in the list, which is the
## whole of what `SaChoiceButton` is for.
func _on_channel_selected(channel_id: Variant) -> void:
    show_channel(String(channel_id))


func _on_curve_changed() -> void:
    changed.emit()
