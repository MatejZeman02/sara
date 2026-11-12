## What the Levels filter hands its page, as Photoshop's: a channel dropdown,
## the active layer's histogram, the black, gamma and white input handles on
## one bar under it, the two output handles on a bar below, and the five
## numbers typed rather than dragged, each under its own caption.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## One `ui.custom` row, because handles on a ramp under a histogram are not one
## of the page's own widgets. The Preview box and the two buttons under it are
## the filter window's and none of this panel's business.
##
## The fields are the truth and the bars show them, so every change ends in
## `_push_positions` and one `changed`, whether typed, set or dragged.
##
## Three eyedroppers end the channel line, black, grey and white, as
## Photoshop's. A press arms one, and the next click on the canvas reads the
## level there of what this Levels reads and writes it into the black point,
## the gamma that sends it to the middle of the output range, or the white
## point, of the chosen channel, through [method set_values], so one pick is one
## change and in the tool options panel one Edit Filter step. Escape puts it
## away. `SaLevelsSampler` says how the click is heard and the level read.
##
## Equalize sits on the line under the channel choice, with Reset after it,
## and reads pressed while a map is held, with a muted caption after Reset
## naming the channel the map was taken from, so a painter who comes back to
## the panel sees that the layer is equalized and from what. Reset raises the
## button and dims the caption beside the Reset it dims, so the line reads as
## off and still says which map was dropped. The press
## asks the door's `SaNodeHistogram` for the Lightness row of what the graph
## above draws, Oklab L, once, whatever channel the handles are on, and keeps
## the map `SaLevelsFilter.cdf_map` makes of it. The kernel reads the map on
## Oklab L alone and keeps a and b, so Equalize moves lightness and never
## chroma or hue, and the channel
## row still chooses what the handles move after it. The door bins with the
## graph's own kernel and parameters, so the row is the graph's. The counts are
## read back and no texel is, so hard rule 1 is untouched.
##
## In the edit window of an attached record, or in the tool options panel of
## one, the press reads the record's own input instead, through the door's
## `SaNodeHistogram`: the layer's paint on a paint layer, the group's composite
## before its records on a group, the composite under the root's records on
## the root and the backdrop at its scope on an adjustment layer. The map goes
## into the record's values, so it saves with it and a later stroke leaves it
## until the next press. The graph above draws that same input there, because
## the panel hands it `attached_host`, and in the Filter menu's dialog, which
## edits no record, it draws the active layer.
class_name SaLevelsPanel
extends VBoxContainer

## A number or the channel moved, and the filter should run again.
signal changed

## The five values: the key each reports under, the caption over its field,
## the sentence behind it, its range and its default. The gamma is the odd one,
## a factor about one rather than a level, which is why its handle's place on
## the bar is computed rather than read, and its caption is Midtone, the handle
## a painter moves, rather than the name of the maths.
##
## **The `label` is the caption, and the `hint` the explanation**. The fields
## once carried no visible caption, so five bare numbers sat under the bars
## and only a tooltip said which was which. Each hint opens with the name and
## then says what moving the number does.
const ROWS: Array = [
    {
        "key": "in_black",
        "label": "Black",
        "hint": "Black point: the input level that comes out black. Everything below it is clipped.",
        "min": 0.0,
        "max": 1.0,
        "step": 0.005,
        "default": 0.0,
    },
    {
        "key": "gamma",
        "label": "Midtone",
        "hint": "Midtone: the gamma, where mid grey sits. Above one lifts the midtones, below one drops them, the ends stay put.",
        "min": 0.1,
        "max": 4.0,
        "step": 0.01,
        "default": 1.0,
    },
    {
        "key": "in_white",
        "label": "White",
        "hint": "White point: the input level that comes out white. Everything above it is clipped.",
        "min": 0.0,
        "max": 1.0,
        "step": 0.005,
        "default": 1.0,
    },
    {
        "key": "out_black",
        "label": "Output black",
        "hint": "Output black: the darkest the layer may come out, so raising it lifts the blacks towards grey.",
        "min": 0.0,
        "max": 1.0,
        "step": 0.005,
        "default": 0.0,
    },
    {
        "key": "out_white",
        "label": "Output white",
        "hint": "Output white: the brightest the layer may come out, so lowering it holds the whites down.",
        "min": 0.0,
        "max": 1.0,
        "step": 0.005,
        "default": 1.0,
    },
]

## What the Channel row explains, on the label and on the dropdown alike.
## Both, because a painter points at whichever of the two their eye landed on
## and a tooltip on one of a pair reads as a tooltip on neither. Every tooltip
## in Sara wraps, so the sentence is as long as it needs to be.
const CHANNEL_HINT := (
    "Which channel the handles move. Master moves red, green and blue together, "
    + "a single channel shifts the colour too, and Lightness (Oklab) moves lightness alone."
)

## Where the input values stop and the output ones begin, so the two groups
## sit on their own bars.
const OUTPUT_FROM := 3

## The gamma's range, which is `ROWS` second entry's and is here by name for
## the maths that turns a handle's place back into a gamma.
const GAMMA_MIN := 0.1
const GAMMA_MAX := 4.0

## What the two Equalize buttons say they do.
const EQUALIZE_HINT := (
    "Spread the lightness evenly over the range, from the Oklab lightness histogram of what this Levels reads: "
    + "the layer, or for one on a group or the whole document, what is composited under it. "
    + "Chroma and hue stay as they were, and the handles then move over the equalized levels."
)
const RESET_HINT := "Drop the Equalize map, so the handles act on the layer as painted."

## What each eyedropper says it does, by `SaLevelsSampler.KINDS`.
const EYEDROPPER_HINTS := {
    "black": "Set black point: click a spot on the canvas that should come out black. Escape puts the eyedropper away.",
    "grey":
    (
        "Set midtone: click a spot on the canvas that should come out mid grey, and the gamma moves to put it there. "
        + "Escape puts the eyedropper away."
    ),
    "white": "Set white point: click a spot on the canvas that should come out white. Escape puts the eyedropper away.",
}

## The swatch each eyedropper carries in its corner.
const EYEDROPPER_SWATCHES := {
    "black": Color(0.0, 0.0, 0.0),
    "grey": Color(0.5, 0.5, 0.5),
    "white": Color(1.0, 1.0, 1.0),
}

## How far apart a picked black point and white point are kept, one step of
## their fields, so a pick never makes the two meet. `SaLevelsGap` holds every
## other way of setting them to the same.
const LEVEL_GAP := SaLevelsGap.GAP

## The channel every Equalize map is counted on and read on, Oklab L, which
## a record keeps under "equalize_channel" and the caption names.
const MAP_CHANNEL := "lightness"

## The caption once a map is held, the channel's title written into the whole
## sentence rather than dropped into one, so a language with cases can decline
## it. The title is `SaPointAdjust.CHANNEL_TITLES` of [constant MAP_CHANNEL].
const EQUALIZED_CAPTION := "Equalized using Lightness (Oklab)"

## How strongly the Equalize caption is drawn once its map is dropped.
const DROPPED_CAPTION := 0.4

## How wide a number field is, in logical units. Wide enough for four decimals
## and the spinner, narrow enough that three fit under the bar with the gaps
## that put each under its own handle.
const FIELD_WIDTH := 92

var _histogram: SaAdjustGraph = null
var _input_bar: SaLevelsBar = null
var _output_bar: SaLevelsBar = null
var _channel_button: SaChoiceButton = null
## Key -> the `SpinBox` that shows and edits it.
var _fields: Dictionary = {}
var _equalize_button: Button = null
var _reset_button: Button = null
## "Equalized from" the map's channel, at full strength while the map is held
## and dimmed once it is dropped, empty until a map was held.
var _equalize_caption: Label = null
## Kind -> the eyedropper `Button` that arms it.
var _eyedroppers: Dictionary = {}
var _sampler := SaLevelsSampler.new()
## The armed eyedropper said there was nothing to read, once an arming.
var _told_nothing_there: bool = false
## The Equalize map, `SaPointAdjust.EQUALIZE_SAMPLES` levels or empty for
## none, counted on `MAP_CHANNEL` whatever channel the handles are on.
var _map: Array = []


func _init() -> void:
    name = "LevelsPanel"
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    add_theme_constant_override("separation", SaUI.px(8))

    var channel_line := HBoxContainer.new()
    channel_line.add_theme_constant_override("separation", SaUI.px(8))
    add_child(channel_line)
    var channel_label := Label.new()
    channel_label.name = "ChannelLabel"
    channel_label.text = tr("Channel")
    channel_label.tooltip_text = tr(CHANNEL_HINT)
    # A `Label` ignores the pointer by default, and a control the pointer goes
    # straight through never shows the tooltip it carries. The dropdown beside
    # it is a word like "Master" that explains nothing, so this is the one
    # label a painter points at.
    channel_label.mouse_filter = Control.MOUSE_FILTER_STOP
    channel_label.custom_minimum_size = Vector2(float(SaUI.px(90)), 0.0)
    channel_line.add_child(channel_label)
    _channel_button = SaChoiceButton.new()
    _channel_button.name = "ChannelButton"
    _channel_button.tooltip_text = tr(CHANNEL_HINT)
    _channel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var channels: Array = []
    for id: String in SaPointAdjust.CHANNELS:
        channels.append({"id": id, "label": tr(String(SaPointAdjust.CHANNEL_TITLES[id]))})
    _channel_button.set_choices(channels)
    _channel_button.select_value("master")
    _channel_button.choice_picked.connect(_on_channel_selected)
    channel_line.add_child(_channel_button)
    for kind: String in SaLevelsSampler.KINDS:
        channel_line.add_child(_make_eyedropper(kind))
    _sampler.armed_changed.connect(_on_armed_changed)
    _sampler.sampled.connect(_on_sampled)

    var equalize_line := HBoxContainer.new()
    equalize_line.name = "EqualizeLine"
    equalize_line.add_theme_constant_override("separation", SaUI.px(8))
    add_child(equalize_line)
    _equalize_button = Button.new()
    _equalize_button.name = "EqualizeButton"
    _equalize_button.text = tr("Equalize")
    _equalize_button.tooltip_text = tr(EQUALIZE_HINT)
    _equalize_button.toggle_mode = true
    SaTheme.make_toggle(_equalize_button)
    _equalize_button.pressed.connect(_on_equalize_pressed)
    equalize_line.add_child(_equalize_button)
    _reset_button = Button.new()
    _reset_button.name = "ResetEqualizeButton"
    _reset_button.text = tr("Reset")
    _reset_button.tooltip_text = tr(RESET_HINT)
    _reset_button.disabled = true
    _reset_button.pressed.connect(reset_equalize)
    equalize_line.add_child(_reset_button)
    _equalize_caption = Label.new()
    _equalize_caption.name = "EqualizeCaption"
    SaTheme.bind_font(_equalize_caption, "text_muted")
    equalize_line.add_child(_equalize_caption)

    # The histogram and the input bar with nothing between them, so the
    # handles read as sitting under the graph the way Photoshop draws them.
    # Labelled like the output range below it, so the two ranges read as a
    # pair rather than one range with a heading and one without.
    var input_label := Label.new()
    input_label.name = "InputLabel"
    input_label.text = tr("Input levels")
    input_label.tooltip_text = tr("The range read from the layer, and the gamma between its black and its white.")
    input_label.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(input_label)
    var input_group := VBoxContainer.new()
    input_group.add_theme_constant_override("separation", 0)
    add_child(input_group)
    # The graph is inset by the bar's own margin, so the first bin stands over
    # the black handle's leftmost place and the last over the white handle's.
    var graph_margin := MarginContainer.new()
    graph_margin.add_theme_constant_override("margin_left", SaUI.px(SaLevelsBar.INSET))
    graph_margin.add_theme_constant_override("margin_right", SaUI.px(SaLevelsBar.INSET))
    input_group.add_child(graph_margin)
    _histogram = SaAdjustGraph.new(attached_host)
    graph_margin.add_child(_histogram)
    _input_bar = SaLevelsBar.new("InputBar", ["in_black", "gamma", "in_white"], "gamma")
    _input_bar.tooltip_text = tr("Drag the black, grey and white handles to set the input range and the gamma.")
    _input_bar.handle_dragged.connect(_on_handle_dragged)
    input_group.add_child(_input_bar)
    add_child(_make_fields(0, OUTPUT_FROM))

    add_child(HSeparator.new())

    var output_label := Label.new()
    output_label.name = "OutputLabel"
    output_label.text = tr("Output levels")
    output_label.tooltip_text = tr("The range the layer comes out in, after the handles above have set black and white.")
    output_label.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(output_label)
    _output_bar = SaLevelsBar.new("OutputBar", ["out_black", "out_white"], "")
    _output_bar.tooltip_text = tr("Drag the two handles to set where black and white come out.")
    _output_bar.handle_dragged.connect(_on_handle_dragged)
    add_child(_output_bar)
    add_child(_make_fields(OUTPUT_FROM, ROWS.size()))
    _push_positions()


## The eyedropper *kind*: the Eyedropper's own picture with the swatch it sets
## drawn in its corner, a toggle that reads pressed while it is armed.
func _make_eyedropper(kind: String) -> Button:
    var button := Button.new()
    button.name = kind.capitalize() + "Eyedropper"
    button.icon = SaUI.get_icon("colorpick")
    button.toggle_mode = true
    SaTheme.make_toggle(button)
    button.focus_mode = Control.FOCUS_NONE
    button.tooltip_text = tr(String(EYEDROPPER_HINTS[kind]))
    button.pressed.connect(_on_eyedropper_pressed.bind(kind))
    button.draw.connect(_draw_swatch.bind(button, EYEDROPPER_SWATCHES[kind]))
    _eyedroppers[kind] = button
    return button


static func _draw_swatch(button: Button, swatch: Color) -> void:
    var side := float(SaUI.px(7))
    var corner := Rect2(button.size - Vector2(side, side) - Vector2(2.0, 2.0), Vector2(side, side))
    button.draw_rect(corner, swatch)
    button.draw_rect(corner, SaTheme.palette.text_muted, false, 1.0)


## The number fields for `ROWS[from]` to `ROWS[until - 1]`, spread across the
## row so the first sits under the left handle, the last under the right one
## and a third, when there is one, in the middle. Each has its row's label over
## it in a muted caption, the way the adjust filters head their sliders.
func _make_fields(from: int, until: int) -> Control:
    var line := HBoxContainer.new()
    line.add_theme_constant_override("separation", SaUI.px(8))
    for index in range(from, until):
        if index > from:
            var gap := Control.new()
            gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            line.add_child(gap)
        var row: Dictionary = ROWS[index]
        var key := String(row["key"])
        var column := VBoxContainer.new()
        column.name = key.capitalize().replace(" ", "") + "Column"
        column.add_theme_constant_override("separation", SaUI.px(2))
        line.add_child(column)
        var caption := Label.new()
        caption.name = key.capitalize().replace(" ", "") + "Caption"
        caption.text = tr(String(row["label"]))
        SaTheme.bind_font(caption, "text_muted")
        column.add_child(caption)
        var field := SpinBox.new()
        field.name = key.capitalize().replace(" ", "") + "Field"
        field.min_value = float(row["min"])
        field.max_value = float(row["max"])
        field.step = float(row["step"])
        field.value = float(row["default"])
        field.tooltip_text = tr(String(row["hint"]))
        field.custom_minimum_size = Vector2(float(SaUI.px(FIELD_WIDTH)), 0.0)
        field.value_changed.connect(func(_v: float) -> void: _on_field_changed(key))
        column.add_child(field)
        _fields[key] = field
    return line


## Redraws the graph now. Public because the capture door and a channel change
## both want it without waiting for a frame that changed.
func refresh_histogram() -> void:
    _histogram.refresh()


## The handles as `SaPointAdjust.params_for` takes them.
func values() -> Dictionary:
    var out: Dictionary = {}
    for row: Dictionary in ROWS:
        out[String(row["key"])] = _value(String(row["key"]))
    out["channel"] = _chosen_channel()
    out["equalize"] = _map.duplicate()
    out["equalize_channel"] = MAP_CHANNEL if has_map() else ""
    return out


## Presses Equalize: asks the door's `SaNodeHistogram` for the Oklab L counts
## of what the graph above shows, the active layer's paint in the Filter menu's
## dialog or the input of the record this panel edits, and keeps the map of
## that row. The graph then draws the same input on the channel the handles
## are on. False, and nothing changes, when there is nothing to read or it
## sits on one level.
func equalize() -> bool:
    var subject := _subject()
    _histogram.channel = _chosen_channel()
    refresh_histogram()
    if subject.is_empty():
        return false
    return equalize_from_counts(SaNodeHistogram.new(subject[0]).counts(subject[1], MAP_CHANNEL))


## What this Levels reads, as `[document, node]`: the input of the record it
## edits, the node null for the document's root, or in the Filter menu's
## dialog the active layer's paint. Empty when there is nothing to read.
func _subject() -> Array:
    var host := attached_host()
    var found := SaNodeHistogram.node_of(host[0], host[1]) if not host.is_empty() else [false, null]
    if bool(found[0]):
        return [host[0], found[1]]
    var document := _histogram.easel_document()
    var layer := _painted_layer(document)
    return [document, layer] if layer != null else []


## Arms the eyedropper *kind* over the main canvas, or puts it away when it is
## the armed one, as its button's press does.
func arm_eyedropper(kind: String) -> void:
    if _sampler.kind == kind:
        _sampler.disarm()
        return
    _sampler.arm(kind, _histogram.easel_machine(), get_window() if is_inside_tree() else null)


## The level the chosen channel's handles see at *at*, in document
## coordinates, in what this Levels reads, after the Equalize map when one is
## held. NAN where nothing is painted there.
func level_at(at: Vector2) -> float:
    var subject := _subject()
    if subject.is_empty():
        return NAN
    var document: SaDocument = subject[0]
    var stored := _sampler.read_texel(SaNodeInput.new(document, subject[1]), at, document.canvas_size)
    if stored.a <= 0.0:
        return NAN
    return SaLevelsSampler.level_of(stored, document.color_space, _chosen_channel(), _map)


## The eyedropper *kind*'s pick at *at*: the level there written into the black
## point, the gamma or the white point of the chosen channel, as one change.
## False, and nothing moves, where nothing is painted.
func sample_at(kind: String, at: Vector2) -> bool:
    var level := level_at(at)
    if is_nan(level):
        return false
    take_level(kind, level)
    return true


## Writes *level* the way the eyedropper *kind* does. The black point stays
## below the white point and the white above the black, a step apart, and the
## grey one moves the gamma so *level* comes out in the middle of the output
## range.
func take_level(kind: String, level: float) -> void:
    var in_black := _value("in_black")
    var in_white := _value("in_white")
    match kind:
        "black":
            set_values({"in_black": minf(level, in_white - LEVEL_GAP)})
        "white":
            set_values({"in_white": maxf(level, in_black + LEVEL_GAP)})
        "grey":
            set_values({"gamma": gamma_at(in_black, level, in_white)})


## The active layer of *document* when it holds paint of its own, which is
## what the Filter menu's dialog graphs, and null for a group, an adjustment
## layer or no document, which it graphs nothing of.
static func _painted_layer(document: SaDocument) -> SaLayer:
    var layer := document.active_layer if document != null else null
    if layer == null or layer.is_group or layer.is_adjustment():
        return null
    return layer


## The document and the record this panel edits, as `[document, record]`,
## when it stands in the edit window of an attached record or in the tool
## options panel of one, and empty in the Filter menu's dialog. Asked of the
## nearest ancestor that holds a `record`, which both hosts do, read by name so
## the module names neither: the window keeps its document private, and a
## private member may be read from outside.
func attached_host() -> Array:
    var node: Node = get_parent()
    while node != null:
        var record: Variant = node.get("record")
        if record is SaAttachedFilter:
            var document: Variant = node.get("_document")
            return [document, record] if document is SaDocument else []
        node = node.get_parent()
    return []


## The map from *counts*, the graph's count buffer binned for `MAP_CHANNEL`
## as `SaNodeHistogram.counts` answers it, taken from the row
## `SaAdjustGraph.DUMP_ROWS` names for it, which holds Oklab L when the
## buffer was binned for Lightness.
func equalize_from_counts(counts: PackedInt32Array) -> bool:
    var row := int(SaAdjustGraph.DUMP_ROWS[MAP_CHANNEL])
    var bins := SaPointAdjust.EQUALIZE_SAMPLES
    var map := SaLevelsFilter.cdf_map(counts.slice(row * bins, (row + 1) * bins))
    if map.size() != bins:
        return false
    _map = map
    _show_map()
    changed.emit()
    return true


## Presses Reset: the map goes, and the handles act on the layer as painted.
func reset_equalize() -> void:
    _take_map([], "")
    changed.emit()


## Whether a map is held, for a capture and a test.
func has_map() -> bool:
    return not _map.is_empty()


## Holds *map* when it is a whole map under a channel word Levels knows. An
## older record names the channel the handles were on rather than Lightness,
## and its map is held all the same and read on Oklab L like
## any other, so the next change writes it back under `MAP_CHANNEL`.
func _take_map(map: Variant, channel: Variant) -> void:
    var held: Array = []
    if map is Array or map is PackedFloat32Array or map is PackedFloat64Array:
        held = Array(map)
    var ok := held.size() == SaPointAdjust.EQUALIZE_SAMPLES and SaPointAdjust.CHANNELS.has(String(channel))
    _map = held if ok else []
    _show_map()


## Equalize reads pressed and the caption names the channel at full strength
## while a map is held, and Reset is offered only then. Without one the
## caption keeps the last channel it named, dimmed.
func _show_map() -> void:
    var held := has_map()
    _equalize_button.set_pressed_no_signal(held)
    _reset_button.disabled = not held
    _equalize_caption.modulate.a = 1.0 if held else DROPPED_CAPTION
    if held:
        _equalize_caption.text = tr(EQUALIZED_CAPTION)


## Sets values by key, and the channel by its id, the way a scenario or a
## test drives them, and announces once.
func set_values(wanted: Dictionary) -> void:
    if wanted.has("equalize"):
        _take_map(wanted["equalize"], wanted.get("equalize_channel", ""))
    for key: String in wanted:
        if key == "channel":
            _channel_button.select_value(String(wanted[key]))
            _histogram.channel = _chosen_channel()
            refresh_histogram()
            continue
        var field := _fields.get(key, null) as SpinBox
        if field != null:
            field.set_value_no_signal(float(wanted[key]))
    _hold_gap("in_white" if wanted.has("in_white") and not wanted.has("in_black") else "in_black")
    _push_positions()
    changed.emit()


## The handles as an attached filter's record keeps them, which are the
## numbers [method values] answers and the channel by its id.
func parameters() -> Dictionary:
    return values()


## A record's handles, drawn without announcing a change, because a panel is
## built from them and building one moves nothing. A key the panel has no
## field for is ignored.
func set_parameters(wanted: Dictionary) -> void:
    if wanted.has("equalize"):
        _take_map(wanted["equalize"], wanted.get("equalize_channel", ""))
    for key: String in wanted:
        if key == "channel":
            _channel_button.select_value(String(wanted[key]))
            _histogram.channel = _chosen_channel()
            continue
        var field := _fields.get(key, null) as SpinBox
        if field != null:
            field.set_value_no_signal(float(wanted[key]))
    _hold_gap()
    _push_positions()


## Drags the handle *key* to *target* through the bar's own motion path, the
## way a pointer would: *target* is a level for the four level handles and a
## gamma for the grey one.
func drag_level_handle(key: String, target: float) -> void:
    var bar := _input_bar if _input_bar.has_handle(key) else _output_bar
    if not bar.has_handle(key):
        return
    var at := target
    if key == "gamma":
        at = gamma_position(_value("in_black"), target, _value("in_white"))
    bar.drag_to(key, at)


## Where the grey handle sits for *gamma* between the black and white
## handles: the input level the curve sends to the middle of the output range.
## The kernel raises to one over gamma, so that level is a half to the gamma,
## and a gamma above one puts the handle left of centre, which is the drag
## that brightens the midtones, as in Photoshop.
static func gamma_position(in_black: float, gamma: float, in_white: float) -> float:
    return in_black + (in_white - in_black) * pow(0.5, gamma)


## The inverse: the gamma whose grey handle sits at *position*. Held inside
## the gamma's range, and one when the two level handles have met, because
## there is no middle to speak of then.
static func gamma_at(in_black: float, at: float, in_white: float) -> float:
    var span := in_white - in_black
    if span <= 0.0:
        return 1.0
    var t := clampf((at - in_black) / span, 0.001, 0.999)
    return clampf(log(t) / log(0.5), GAMMA_MIN, GAMMA_MAX)


## The `levels` step's door and the `filter` step's, since the panel is a
## custom row: `{"drag": {"handle": "in_black", "to": 0.3}}` drags one handle
## through the bar's own motion path, `{"in_white": 0.8, "channel": "red"}`
## sets values the way typing them would, `{"equalize": true}` presses
## Equalize and `{"reset": true}` Reset, `{"tooltips": true}` prints every
## control's sentence, and `{"read": true}` prints the values and touches
## nothing. Every branch but the report answers the values it left, the map
## as whether one is held rather than its 256 numbers, whether Equalize reads
## pressed and what its caption says, and the armed eyedropper.
## `{"arm": "black"}` presses an eyedropper's button, and
## `{"sample": {"kind": "white", "at": [x, y]}}` takes its pick at a document
## place without the click.
func capture_option_edit(spec: Dictionary) -> String:
    if spec.get("tooltips", false):
        return tooltip_report()
    if spec.has("arm"):
        arm_eyedropper(String(spec["arm"]))
    if spec.has("sample"):
        var sample := spec["sample"] as Dictionary
        var at: Array = sample.get("at", [0, 0])
        sample_at(String(sample.get("kind", "black")), Vector2(float(at[0]), float(at[1])))
    if spec.get("reset", false):
        reset_equalize()
    if bool(spec.get("equalize", false)):
        equalize()
    if spec.has("drag"):
        var drag := spec["drag"] as Dictionary
        drag_level_handle(String(drag.get("handle", "in_black")), float(drag.get("to", 0.0)))
    var wanted: Dictionary = {}
    if spec.has("channel"):
        wanted["channel"] = spec["channel"]
    for row: Dictionary in ROWS:
        var key := String(row["key"])
        if spec.has(key):
            wanted[key] = spec[key]
    if not wanted.is_empty():
        set_values(wanted)
    var shown := values()
    shown["equalize"] = has_map()
    shown["equalize_pressed"] = _equalize_button.button_pressed
    shown["equalize_caption"] = _equalize_caption.text
    shown["equalize_caption_dimmed"] = _equalize_caption.modulate.a < 1.0
    shown["armed"] = _sampler.kind
    return "SaCapture: levels %s" % JSON.stringify(shown)


## Every control a painter can point at, with the text on it and the sentence
## behind it, and the window's Apply and Cancel beside them.
##
## A tooltip is the one thing a screenshot cannot show, and here it is what
## says what a field does, where its caption only names it. So the claim
## "Levels says what it does" is read back rather than photographed, one line
## per control, with the pointer's own place beside it so a scenario can hover
## the control the line names.
func tooltip_report() -> String:
    var lines: Array[String] = ["SaCapture: levels tooltips"]
    var window := get_window() if is_inside_tree() else null
    var origin := Vector2(window.position) if window != null and window.is_embedded() else Vector2.ZERO
    var walked: Array[Control] = []
    for child in find_children("*", "Control", true, false):
        var control := child as Control
        if control != null and worth_a_tooltip(control):
            walked.append(control)
    if window != null:
        for button_name: String in ["CancelButton", "ApplyButton"]:
            var button := window.find_child(button_name, true, false) as Button
            if button != null:
                walked.append(button)
    for control in walked:
        var at := origin + control.get_global_rect().get_center()
        var label := ""
        if control is Label:
            label = (control as Label).text
        elif control is Button:
            label = (control as Button).text
        (
            lines
            . append(
                (
                    "  %-14s %-16s at=(%4d, %4d) reads=%s tooltip=%s"
                    % [
                        control.name,
                        control.get_class(),
                        at.x,
                        at.y,
                        JSON.stringify(label),
                        JSON.stringify(control.tooltip_text),
                    ]
                )
            )
        )
    return "\n".join(lines)


## Which controls the report walks: the ones a painter can point at and act on,
## plus the labels that carry a sentence of their own. A container, a separator
## and a spacer are not things anybody points at.
##
## A row of the channel list is not one of them either. The list is a real
## `Window` of rows built out of real `Button`s and `Label`s, a child of the
## dropdown that opens it, so a plain recursive walk reaches straight into it,
## and the panel says what the *button* does.
static func worth_a_tooltip(control: Control) -> bool:
    if _inside_a_choice_list(control):
        return false
    if control is Label:
        return not control.tooltip_text.is_empty()
    return control is BaseButton or control is SpinBox or control is SaLevelsBar or control is SaAdjustGraph


static func _inside_a_choice_list(control: Control) -> bool:
    var node: Node = control
    while node != null:
        if node is SaChoicePopup:
            return true
        node = node.get_parent()
    return false


func _value(key: String) -> float:
    var field := _fields.get(key, null) as SpinBox
    return field.value if field != null else 0.0


func _push_positions() -> void:
    var in_black := _value("in_black")
    var in_white := _value("in_white")
    (
        _input_bar
        . set_positions(
            {
                "in_black": in_black,
                "gamma": gamma_position(in_black, _value("gamma"), in_white),
                "in_white": in_white,
            }
        )
    )
    _output_bar.set_positions({"out_black": _value("out_black"), "out_white": _value("out_white")})


## A handle moved under the pointer. The grey handle's place is a gamma, the
## other four are levels, and the black and white handles carry the grey one
## along so the gamma survives a drag on either end.
func _on_handle_dragged(key: String, at: float) -> void:
    var field := _fields.get(key, null) as SpinBox
    if field == null:
        return
    if key == "gamma":
        field.set_value_no_signal(gamma_at(_value("in_black"), at, _value("in_white")))
    else:
        field.set_value_no_signal(at)
        _hold_gap(key)
    _push_positions()
    changed.emit()


func _on_field_changed(key: String) -> void:
    _hold_gap(key)
    _push_positions()
    changed.emit()


## The black and white fields held a gap apart by `SaLevelsGap`, the one that
## was just set, *moved*, giving way. Typed 80, the Black field holds 1 and
## then White less the gap rather than a span the kernel would turn over.
func _hold_gap(moved := "") -> void:
    var held := SaLevelsGap.held({"in_black": _value("in_black"), "in_white": _value("in_white")}, moved)
    for key: String in ["in_black", "in_white"]:
        var field := _fields.get(key, null) as SpinBox
        if field != null:
            field.set_value_no_signal(float(held[key]))


## An armed eyedropper goes when the panel is hidden or leaves, whichever way
## its window closed, so the tool and the foreground come back.
func _notification(what: int) -> void:
    if what == NOTIFICATION_EXIT_TREE or (what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()):
        _sampler.disarm()


## The press toggles the button before it arrives here, so the mark is drawn
## again from the map, which a press with nothing to read leaves as it was.
func _on_equalize_pressed() -> void:
    equalize()
    _show_map()


func _on_eyedropper_pressed(kind: String) -> void:
    arm_eyedropper(kind)


## Each button reads pressed while its eyedropper is the armed one.
func _on_armed_changed(kind: String) -> void:
    _told_nothing_there = false
    for each: String in _eyedroppers:
        (_eyedroppers[each] as Button).set_pressed_no_signal(each == kind)


## A click on the canvas while an eyedropper is armed. Where Levels reads
## nothing the eyedropper stays armed and says so in the corner, once.
func _on_sampled(kind: String, at: Vector2) -> void:
    if sample_at(kind, at):
        _sampler.land()
    elif not _told_nothing_there:
        _told_nothing_there = true
        EventBus.corner_notice.emit(tr("Nothing painted there for Levels to read, so the handles stay as they are."))


## The dropdown is about the graph as much as about the maths: the graph
## draws the channel the handles move, rather than a picture of three curves
## while the handles move one.
func _on_channel_selected(_channel_id: Variant) -> void:
    _histogram.channel = _chosen_channel()
    refresh_histogram()
    changed.emit()


## The channel id the dropdown is showing, off the row's own value rather than
## off a position in the list.
func _chosen_channel() -> String:
    var chosen: Variant = _channel_button.selected_value()
    return String(chosen) if chosen != null else "master"
