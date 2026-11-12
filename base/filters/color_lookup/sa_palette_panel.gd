## What the Colour Lookup filter hands its page: the palette as a strip of
## chips, and the selected chip's own bands as four sliders under it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The palette is every chip of the strip, which starts as the kept swatches,
## and a double click on a chip edits its colour. The three sliders are how
## far the shadows, the midtones and the highlights move towards the nearest
## palette colour, and they are the selected chip's own, with an influence
## beside them, so one colour of the palette can pull on the shadows while
## another pulls on the highlights.
##
## One `ui.custom` row, because a strip of swatches is not one of the page's
## own widgets. The word palette stays for the list of colours a painter
## picks, and the filter that applies it is the colour lookup.
##
## Every chip of the strip is in the palette, so a click only selects and never
## takes a colour out of the pass. The `-` is what takes a chip out, and the
## strip holds no more chips than the pass takes, `PALETTE_MAX`.
##
## The panel starts at the defaults every time the filter opens, because the
## window builds its page afresh: none selected and every chip's bands at
## nothing, so the picture is the picture before until the painter asks for
## something, since the pass skips a colour with no reach, and a palette left
## over from the last open is not applied to a picture that has moved on since.
class_name SaPalettePanel
extends VBoxContainer

## A chip, a colour or a band moved, and the filter should run again.
signal changed

## The three sliders, in the order the bands run, dark first, then the
## influence. Each is a percentage a painter reads and a fraction the pass
## takes, and the influence runs to twice a colour's reach.
const ROWS: Array[Dictionary] = [
    {"key": "shadows", "label": "Shadows", "max": 100.0},
    {"key": "midtones", "label": "Midtones", "max": 100.0},
    {"key": "highlights", "label": "Highlights", "max": 100.0},
    {"key": "influence", "label": "Influence", "max": 100.0 * SaPointAdjust.INFLUENCE_MAX},
]

## A chip is a swatch this big, logical units, and the strip wraps at the
## page's width.
const CHIP_SIZE: int = 22

## How many colours a slider's ramp is sampled at.
const GRADIENT_STOPS: int = 24

## The palette's colours, one chip each: the painter's kept strip as it was
## when the filter opened, to the first `PALETTE_MAX`, and this panel's own copy.
var swatches: Array[Color] = []

var _chips: HFlowContainer = null
## The last cell of the strip, a `+` that opens a picker and keeps what was
## picked as a swatch.
var _add_chip: ColorPickerButton = null
## The cell after the `+`, which takes the selected chip out of the strip.
var _remove_chip: Button = null
## The colour the `+` picker opened on, and the last colour the picker
## reported that was another one. Closing it after such a pick is what adds a
## swatch, and closing it with none adds nothing, so a press that was a look
## costs no swatch.
var _opened_with: Color = Color.BLACK
var _picked: bool = false
var _pick: Color = Color.BLACK
## The muted line under the heading while the strip has no chip, which says
## how a colour gets there.
var _hint: Label = null
## The picker a double click on a chip opens, one for the whole strip, and the
## index of the chip it is editing, or -1 while it is shut.
var _chip_editor: PopupPanel = null
var _chip_picker: ColorPicker = null
var _editing: int = -1
var _sliders: Dictionary = {}
## The chips the `palette` step named or added, by index into `swatches`,
## which its bands go to when it names no `select`.
var _named: Dictionary = {}
## Each swatch's own bands, by index into `swatches`, in the keys
## `SaPointAdjust.BAND_KEYS` names and the pass's fractions.
var _bands: Array[Dictionary] = []
## The chip whose bands the sliders show and write, or -1 for none.
var _selected: int = -1
var _band_heading: Label = null
var _rows: VBoxContainer = null


## *kept* is the swatch strip to offer as chips.
func _init(kept: Array[Color] = SaInHand.Pair.swatches()) -> void:
    name = "PalettePanel"
    swatches = kept.slice(0, SaPointAdjust.PALETTE_MAX)
    add_theme_constant_override("separation", SaUI.px(10))
    size_flags_horizontal = Control.SIZE_EXPAND_FILL

    var palette_label := Label.new()
    palette_label.name = "PaletteHeading"
    palette_label.text = tr("Palette")
    palette_label.set_meta(SaUI.FONT_SCALE_META, 1.0)
    SaTheme.bind_font(palette_label, "text_muted")
    add_child(palette_label)

    _hint = Label.new()
    _hint.name = "EmptyHint"
    _hint.text = tr("No colours yet. Click + to add one, or save swatches in the Colour Picker docker and reopen this.")
    _hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _hint.set_meta(SaUI.FONT_SCALE_META, 1.0)
    SaTheme.bind_font(_hint, "text_muted")
    add_child(_hint)

    _chips = HFlowContainer.new()
    _chips.name = "Chips"
    _chips.add_theme_constant_override("h_separation", SaUI.px(4))
    _chips.add_theme_constant_override("v_separation", SaUI.px(4))
    add_child(_chips)
    _add_chip = _make_add_chip()
    _remove_chip = _make_remove_chip()
    _chip_editor = _make_chip_editor()
    add_child(_chip_editor)

    _band_heading = Label.new()
    _band_heading.name = "BandsHeading"
    _band_heading.set_meta(SaUI.FONT_SCALE_META, 1.0)
    SaTheme.bind_font(_band_heading, "text_muted")
    add_child(_band_heading)

    _rows = VBoxContainer.new()
    _rows.name = "Rows"
    _rows.add_theme_constant_override("separation", SaUI.px(8))
    add_child(_rows)
    for row in ROWS:
        _rows.add_child(_make_row(row))

    _rebuild_chips()
    _show_selected()


## One chip per swatch and then the `+` and the `-`, so the two reflow with
## the chips and are always the cells after the last of them. The `+` is kept
## rather than rebuilt, because its picker is what the painter is looking at
## when a swatch lands and a rebuilt button would close it under them. The
## hint over the strip shows while there is no chip and goes with the first.
func _rebuild_chips() -> void:
    _bands.resize(mini(_bands.size(), swatches.size()))
    while _bands.size() < swatches.size():
        _bands.append(SaPointAdjust.BAND_DEFAULTS.duplicate())
    for child in _chips.get_children():
        _chips.remove_child(child)
        if child != _add_chip and child != _remove_chip:
            # A record's chips are laid before the panel joins a tree, and a
            # node freed by the queue outside a tree is never collected.
            if is_inside_tree():
                child.queue_free()
            else:
                child.free()
    for i in swatches.size():
        _chips.add_child(_make_chip(i))
    _chips.add_child(_add_chip)
    _chips.add_child(_remove_chip)
    _hint.visible = swatches.is_empty()
    _add_chip.disabled = swatches.size() >= SaPointAdjust.PALETTE_MAX


## The `+` that ends the strip, where a painter adds a colour of their own. A
## `ColorPickerButton` the size of a chip, because a chip is a colour and the
## picker is where a colour is chosen, and the docker's own `+` beside its
## swatches is the precedent. It starts at the foreground colour, and closing
## it on another colour keeps that colour through `SaInHand.Pair.keep_swatch`,
## the one door the store has, so the docker's strip gains the same chip.
func _make_add_chip() -> ColorPickerButton:
    var button := ColorPickerButton.new()
    button.name = "AddChip"
    button.text = "+"
    button.tooltip_text = tr("Pick a colour to keep as a swatch.")
    button.edit_alpha = false
    button.custom_minimum_size = Vector2(float(SaUI.px(CHIP_SIZE)), float(SaUI.px(CHIP_SIZE)))
    button.focus_mode = Control.FOCUS_NONE
    button.color = SaTheme.palette.bg_input
    _opened_with = button.color
    # A `ColorPickerButton` paints its colour over its own text, so the `+`
    # is a label laid on top, click-through, the way `FactorSlider` lays its
    # text over its bar.
    var plus := Label.new()
    plus.name = "Plus"
    plus.text = "+"
    plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    plus.set_anchors_preset(Control.PRESET_FULL_RECT)
    plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
    SaTheme.bind_font(plus, "text_primary")
    button.add_child(plus)
    button.button_down.connect(_on_add_chip_down)
    button.button_up.connect(_on_add_chip_up)
    button.color_changed.connect(_on_add_chip_picked)
    button.popup_closed.connect(_on_add_chip_closed)
    return button


## The way a painter takes a colour out, beside the `+` that adds one. It acts
## on the selected chip, because a mark on a chip that small is hit by the
## click that selects it.
func _make_remove_chip() -> Button:
    var button := Button.new()
    button.name = "RemoveChip"
    button.text = "-"
    button.tooltip_text = tr("Take the selected colour out of this filter. Your swatches keep it.")
    button.custom_minimum_size = Vector2(float(SaUI.px(CHIP_SIZE)), float(SaUI.px(CHIP_SIZE)))
    button.focus_mode = Control.FOCUS_NONE
    button.pressed.connect(func() -> void: remove_chip(_selected))
    return button


## The picker opens on the foreground colour, so what a painter has on the
## brush is one close away from the strip. It is set as the button goes down
## and not on its `pressed`, which comes once the popup is up, because the
## picker keeps the colour the button held as the popup opened and hands it
## back as a pick when Escape is pressed. Set on `pressed`, that colour was
## the empty cell's own, and the first Escape kept it as a swatch.
func _on_add_chip_down() -> void:
    _add_chip.color = SaInHand.Pair.foreground()
    _opened_with = _add_chip.color
    _picked = false


## A press that slid off the button opens nothing, and the cell goes back to
## its own colour once the frame has shown whether a popup came up.
func _on_add_chip_up() -> void:
    _rest_add_chip.call_deferred()


func _rest_add_chip() -> void:
    if not _add_chip.get_popup().visible:
        _add_chip.color = SaTheme.palette.bg_input


## A colour the picker reports that is not the one it opened on, compared as an
## eight bit hex the way a field submitting its text would hand it back. The
## opening colour itself is what Escape reports, so it is no pick.
func _on_add_chip_picked(color: Color) -> void:
    if color.to_html(true) != _opened_with.to_html(true):
        _picked = true
        _pick = color


## Closing the picker is the choice, because a `ColorPickerButton` has no
## other way out, so a pick made and then closed with Escape is kept as well
## and only a close with no pick adds nothing. The new swatch is ticked into
## the selected chip, since a colour added from this filter was added to be
## used by it. It is appended to the panel's strip, which holds a record's
## colours and chips edited here as well, rather than the kept swatches being
## copied over it. The kept swatches get it too.
func _on_add_chip_closed() -> void:
    var chosen := _pick
    _add_chip.color = SaTheme.palette.bg_input
    _opened_with = _add_chip.color
    if not _picked:
        return
    _picked = false
    SaInHand.Pair.keep_swatch(chosen)
    swatches.append(chosen)
    _named[swatches.size() - 1] = true
    _selected = swatches.size() - 1
    _rebuild_chips()
    _show_selected()
    _announce()


## One swatch as a button, a square of its colour that a click selects.
## Named by index so a capture can find it.
func _make_chip(index: int) -> Button:
    var chip := Button.new()
    chip.name = "Chip%d" % index
    chip.custom_minimum_size = Vector2(float(SaUI.px(CHIP_SIZE)), float(SaUI.px(CHIP_SIZE)))
    _paint_chip(chip, swatches[index], index == _selected)
    chip.pressed.connect(select_chip.bind(index))
    chip.gui_input.connect(_on_chip_input.bind(index))
    return chip


## The one picker the strip shares, in a popup a double click puts under the
## chip. A `ColorPicker` in a `PopupPanel` rather than a `ColorPickerButton` per
## chip, because a chip's single click is the selection and a picker button would
## take that click to open. Alpha is off, as it is on the `+`, since the pass
## reads colours and not their coverage.
func _make_chip_editor() -> PopupPanel:
    var editor := PopupPanel.new()
    editor.name = "ChipEditor"
    # Opaque for the reason the colour ramp's stop popup is.
    editor.transparent = false
    editor.transparent_bg = false
    editor.visible = false
    _chip_picker = ColorPicker.new()
    _chip_picker.name = "ChipPicker"
    _chip_picker.edit_alpha = false
    _chip_picker.color_changed.connect(_on_chip_picked)
    editor.add_child(_chip_picker)
    editor.popup_hide.connect(func() -> void: _editing = -1)
    return editor


## A double click on a chip edits its colour rather than only toggling the
## selection. A double click reaches
## the chip as two presses. The first is a click like any other, which selects
## it, and the second is taken here before the button sees it.
func _on_chip_input(event: InputEvent, index: int) -> void:
    var press := event as InputEventMouseButton
    if press != null and press.pressed and press.double_click and press.button_index == MOUSE_BUTTON_LEFT:
        var chip := _chips.get_node_or_null("Chip%d" % index) as Button
        if chip != null:
            chip.accept_event()
        select_chip(index)
        edit_chip(index)


## Opens the picker on chip *index*'s colour, under the chip. Public so the
## capture step can reach it, since an injected double click does not reach an
## embedded subwindow.
func edit_chip(index: int) -> void:
    if index < 0 or index >= swatches.size():
        return
    _editing = index
    _chip_picker.color = swatches[index]
    var chip := _chips.get_node_or_null("Chip%d" % index) as Control
    if chip != null and chip.is_inside_tree():
        var below := chip.get_screen_position() + Vector2(0.0, chip.size.y)
        _chip_editor.popup(Rect2i(Vector2i(below), Vector2i.ZERO))
    else:
        _chip_editor.visible = true


## A pick writes the chip being edited and the preview, and nothing else. The
## swatches are this panel's copy of the kept strip, so a colour tried here for
## a filter does not rewrite the painter's own swatches behind their back.
func _on_chip_picked(color: Color) -> void:
    if _editing < 0 or _editing >= swatches.size():
        return
    swatches[_editing] = color
    var chip := _chips.get_node_or_null("Chip%d" % _editing) as Button
    if chip != null:
        _paint_chip(chip, color, _editing == _selected)
    _show_selected()
    _announce()


## A chip's two looks for *color*: flat, and sunk with a white rim while the
## pen is down on it, its tooltip the hex a painter would type, and a glow in
## the accent colour on the chip whose bands the sliders show.
static func _paint_chip(chip: Button, color: Color, selected: bool = false) -> void:
    chip.tooltip_text = "#" + color.to_html(false)
    var plain := StyleBoxFlat.new()
    plain.bg_color = color
    plain.set_corner_radius_all(SaUI.px(3))
    if selected:
        plain.shadow_color = SaTheme.palette.accent_primary
        plain.shadow_size = SaUI.px(3)
    var sunk := plain.duplicate() as StyleBoxFlat
    sunk.border_color = Color.WHITE
    sunk.set_border_width_all(SaUI.px(2))
    chip.add_theme_stylebox_override("normal", plain)
    chip.add_theme_stylebox_override("hover", plain)
    chip.add_theme_stylebox_override("pressed", sunk)
    chip.add_theme_stylebox_override("hover_pressed", sunk)


## Selects chip *index*, so the sliders show and write its bands, or none for
## -1, and leaves the palette as it was. A chip's click comes here.
func select_chip(index: int) -> void:
    _selected = index if index >= 0 and index < swatches.size() else -1
    for i in swatches.size():
        var chip := _chips.get_node_or_null("Chip%d" % i) as Button
        if chip != null:
            _paint_chip(chip, swatches[i], i == _selected)
    _show_selected()


## Takes chip *index* out of this panel's strip with its bands, as if that
## colour had never been there, and leaves the kept swatches as they were. No
## chip is selected after, so a second `-` takes nothing the painter did not pick.
func remove_chip(index: int) -> void:
    if index < 0 or index >= swatches.size():
        return
    _chip_editor.hide()
    swatches.remove_at(index)
    _bands.remove_at(index)
    var named: Dictionary = {}
    for at: Variant in _named:
        if int(at) != index:
            named[int(at) - 1 if int(at) > index else int(at)] = true
    _named = named
    _selected = -1
    _rebuild_chips()
    select_chip(-1)
    _announce()


## The sliders and the heading over them for the selected chip. With none
## selected the rows show the bands a new chip starts at and are dimmed and
## take no press, because there is no colour for them to write.
func _show_selected() -> void:
    var bands: Dictionary = _bands[_selected] if _selected >= 0 else SaPointAdjust.BAND_DEFAULTS
    for key: String in _sliders:
        var slider := _sliders[key] as SaGradientSlider
        slider.set_value_no_signal(float(bands[key]) * 100.0)
        slider.set_stops(_gradient_for(key))
    var live := _selected >= 0
    _remove_chip.disabled = not live
    _rows.modulate = Color(1.0, 1.0, 1.0, 1.0 if live else SaOptionSpec.DIMMED_ALPHA)
    for key: String in _sliders:
        (_sliders[key] as Control).mouse_filter = Control.MOUSE_FILTER_STOP if live else Control.MOUSE_FILTER_IGNORE
    if live:
        _band_heading.text = tr("Bands of %s") % ("#" + swatches[_selected].to_html(false))
    else:
        _band_heading.text = tr("Click a colour to set its own bands.")


func _on_slider_changed(value: float, key: String) -> void:
    if _selected >= 0:
        _bands[_selected][key] = value / 100.0
    _announce()


## A slider row, the name beside the slider, with a ramp from grey to the
## band's own lightness behind it.
func _make_row(row: Dictionary) -> Control:
    var line := HBoxContainer.new()
    line.add_theme_constant_override("separation", SaUI.px(8))
    var label := Label.new()
    label.text = tr(String(row["label"]))
    label.custom_minimum_size = Vector2(float(SaUI.px(90)), 0.0)
    line.add_child(label)
    var slider := SaGradientSlider.new()
    slider.name = String(row["key"]).capitalize() + "Slider"
    slider.min_value = 0.0
    slider.max_value = float(row["max"])
    slider.step = 1.0
    slider.suffix = "%"
    slider.decimal_places = 0
    slider.value = float(SaPointAdjust.BAND_DEFAULTS[row["key"]]) * 100.0
    slider.custom_minimum_size = Vector2(0.0, float(SaUI.px(26)))
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider.value_changed.connect(_on_slider_changed.bind(String(row["key"])))
    line.add_child(slider)
    _sliders[String(row["key"])] = slider
    return line


## The ramp behind a band's slider: the band's own grey at the left, so the
## three rows read as dark, middle and light, and the selected chip's colour at
## the right once there is one, which is where the slider takes the band.
func _gradient_for(key: String) -> PackedColorArray:
    var lightness := 0.25 if key == "shadows" else 0.75 if key == "highlights" else 0.5
    var grey := Color(lightness, lightness, lightness, 1.0)
    var towards := swatches[_selected] if _selected >= 0 and _selected < swatches.size() else grey
    var stops := PackedColorArray()
    for i in GRADIENT_STOPS:
        stops.append(grey.lerp(towards, float(i) / float(GRADIENT_STOPS - 1)))
    return stops


## What the pass takes: every chip in strip order, each chip's own bands
## beside them in "bands" as fractions, and the selected chip's bands at the
## top level, or the defaults when none is selected.
func values() -> Dictionary:
    var palette: Array = []
    var bands: Array = []
    for index in swatches.size():
        palette.append(swatches[index])
        bands.append(_bands[index].duplicate())
    var out: Dictionary = {"palette": palette, "bands": bands}
    out.merge(_bands[_selected] if _selected >= 0 else SaPointAdjust.BAND_DEFAULTS)
    return out


## The chips as an attached filter's record keeps them, each colour a
## hex string with its alpha and its bands beside it in the same order, the
## shape `SaPointAdjust.palette_chips` reads.
func parameters() -> Dictionary:
    var palette: Array = []
    var bands: Array = []
    for index in swatches.size():
        palette.append("#" + swatches[index].to_html(true))
        bands.append(_bands[index].duplicate())
    return {"palette": palette, "bands": bands}


## A record's chips, each with its own bands. A colour the strip does not
## carry becomes a chip of this panel's strip, the way a scenario's `colours`
## does, and the store is not written. The last chip is selected, so the
## sliders show a colour the record holds. A strip that would pass the cap
## with them gives up from its end the chips the record does not hold.
func set_parameters(wanted: Dictionary) -> void:
    _named.clear()
    var placed: Array[int] = []
    var chips := SaPointAdjust.palette_chips(wanted)
    var held := chips.map(func(chip: Dictionary) -> String: return (chip["color"] as Color).to_html(true))
    var spare := SaPointAdjust.PALETTE_MAX - held.size()
    var kept: Array[Color] = []
    for color: Color in swatches:
        if held.has(color.to_html(true)) or spare > 0:
            kept.append(color)
            spare -= 0 if held.has(color.to_html(true)) else 1
    swatches = kept
    _bands.clear()
    for chip: Dictionary in chips:
        var index := _swatch_index(chip["color"])
        if index < 0:
            swatches.append(chip["color"])
            index = swatches.size() - 1
        _named[index] = true
        placed.append(index)
    _rebuild_chips()
    for at in placed.size():
        for key: String in SaPointAdjust.BAND_DEFAULTS:
            _bands[placed[at]][key] = float(chips[at][key])
    select_chip(placed[placed.size() - 1] if not placed.is_empty() else -1)


## Where *color* sits on the strip, by the hex a record writes, or -1.
func _swatch_index(color: Color) -> int:
    var wanted := color.to_html(true)
    for index in swatches.size():
        if swatches[index].to_html(true) == wanted:
            return index
    return -1


## Names chips by `chips`, a list of swatch indexes, and adds `colours`, a
## list of hex strings, the way a capture scenario drives them, then sets the
## bands by key in percentages, and announces once. The last chip named is
## selected, and `select` names one instead. The bands go to the selected chip
## when `select` is given and to every named chip when it is not, which is how
## a scenario written for one set of sliders still sets the colours it named.
##
## `colours` is a chip each, appended to this panel's strip and named, in the
## order given, and a word that is not a colour skipped. The store is not
## written, for the reason a chip edit does not write it.
func set_values(wanted: Dictionary) -> void:
    if wanted.has("chips"):
        _named.clear()
        for index: Variant in wanted["chips"] as Array:
            if int(index) >= 0 and int(index) < swatches.size():
                _named[int(index)] = true
                _selected = int(index)
    if wanted.has("colours"):
        for entry: Variant in wanted["colours"] as Array:
            var text := String(entry).strip_edges()
            if Color.html_is_valid(text) and swatches.size() < SaPointAdjust.PALETTE_MAX:
                swatches.append(Color.html(text))
                _named[swatches.size() - 1] = true
                _selected = swatches.size() - 1
        _rebuild_chips()
    select_chip(int(wanted.get("select", _selected)))
    var targets: Array = [_selected] if wanted.has("select") else _named.keys()
    for row in ROWS:
        var key := String(row["key"])
        if not wanted.has(key):
            continue
        for index: Variant in targets:
            if int(index) >= 0 and int(index) < _bands.size():
                _bands[int(index)][key] = clampf(float(wanted[key]), 0.0, float(row["max"])) / 100.0
    _show_selected()
    _announce()


func _announce() -> void:
    for key: String in _sliders:
        (_sliders[key] as SaGradientSlider).set_stops(_gradient_for(key))
    changed.emit()


## The `palette` step's door and the `filter` step's, since the panel is a
## custom row.
## `{"colours": ["#ff0000", "#0000ff"], "chips": [0, 2], "shadows": 100, "midtones": 50, "highlights": 0}`
## sets it, in percentages, with each of `colours` a new ticked chip,
## `{"select": 1, "highlights": 100, "influence": 150}` selects chip 1 and sets
## its own bands alone, and `{"read": true}` prints the values and touches
## nothing else. `{"press_add": true}` opens the `+` chip's picker the way a
## press does, `{"pick_add": "#ff6600"}` picks that colour in it and leaves it up,
## `{"add": "#ff6600"}` picks that colour in it and closes it, which is the
## whole of the add, and `{"close_add": true}` closes it the way Escape does. `{"edit": [1, "#2060c0"]}` opens chip 1's
## picker the way a double click does, picks that colour and leaves the picker
## up for a shot, and `{"close_edit": true}` shuts it. `{"click": 1}` sends chip
## 1 a click's `pressed`, `{"remove": 1}` presses the `-` on it. The window's own half,
## Apply, Cancel and the Preview box, is the step's and never reaches here.
func capture_option_edit(spec: Dictionary) -> String:
    if spec.has("edit"):
        var pair := spec["edit"] as Array
        var index := int(pair[0])
        edit_chip(index)
        _chip_picker.color = Color.html(String(pair[1]))
        _chip_picker.color_changed.emit(_chip_picker.color)
        return "SaCapture: palette chip %d edited to %s, picker shown=%s" % [index, String(pair[1]), str(_chip_editor.visible)]
    if spec.has("click"):
        var clicked := _chips.get_node_or_null("Chip%d" % int(spec["click"])) as Button
        if clicked != null:
            clicked.pressed.emit()
        return "SaCapture: palette chip %d clicked, selected=%d chips=%d" % [int(spec["click"]), _selected, swatches.size()]
    if spec.has("remove"):
        var removed := int(spec["remove"])
        select_chip(removed)
        _remove_chip.pressed.emit()
        return "SaCapture: palette chip %d taken out, chips=%d" % [removed, swatches.size()]
    if spec.get("close_edit", false):
        _chip_editor.hide()
        return "SaCapture: palette chip editor closed"
    if spec.get("press_add", false):
        # The order a real press has: down, then the popup, and the focus.
        _on_add_chip_down()
        # A panel outside a tree has nothing to put a popup in, and a suite
        # drives it so.
        if _add_chip.is_inside_tree():
            # Screen position rather than the button's global one, which is the
            # window's own frame: a popup is placed in the embedder's.
            var below := _add_chip.get_screen_position() + Vector2(0.0, _add_chip.size.y)
            _add_chip.get_popup().popup(Rect2i(Vector2i(below), Vector2i.ZERO))
            _add_chip.get_picker().set_focus_on_line_edit()
        return "SaCapture: palette + pressed, picker shown=%s chips=%d" % [str(_add_chip.get_popup().visible), swatches.size()]
    if spec.has("pick_add"):
        var open_picker := _add_chip.get_picker()
        open_picker.color = Color.html(String(spec["pick_add"]))
        open_picker.color_changed.emit(open_picker.color)
        return "SaCapture: palette + picked %s, picker shown=%s" % [spec["pick_add"], str(_add_chip.get_popup().visible)]
    if spec.get("close_add", false):
        # Escape on a `ColorPickerButton` hands back the colour it opened on
        # before it closes, which is what this does, so a close here is one.
        var closing := _add_chip.get_picker()
        closing.color = _opened_with
        closing.color_changed.emit(closing.color)
        _shut_add_picker()
        return "SaCapture: palette + closed as Escape does, chips=%d" % swatches.size()
    if spec.has("add"):
        var picker := _add_chip.get_picker()
        picker.color = Color.html(String(spec["add"]))
        picker.color_changed.emit(picker.color)
        _shut_add_picker()
        var kept := SaInHand.Pair.swatches().size()
        return "SaCapture: palette added %s, swatches=%d chips=%d" % [spec["add"], kept, swatches.size()]
    if spec.get("read", false):
        return (
            "SaCapture: palette read %s, picker shown=%s"
            % [JSON.stringify(readable(values())), str(_add_chip.get_popup().visible)]
        )
    set_values(spec)
    return "SaCapture: palette %s" % JSON.stringify(readable(values()))


## Shuts the `+` picker, and says so itself when it never came up, which is a
## panel a suite drives outside a tree.
func _shut_add_picker() -> void:
    var popup := _add_chip.get_popup()
    if popup.visible:
        popup.hide()
    else:
        _add_chip.popup_closed.emit()


## The values with the colours as hex, which is what a log line can hold.
static func readable(taken: Dictionary) -> Dictionary:
    var out := taken.duplicate()
    var palette: Array = []
    for color: Variant in taken.get("palette", []) as Array:
        palette.append("#" + (color as Color).to_html(false))
    out["palette"] = palette
    return out
