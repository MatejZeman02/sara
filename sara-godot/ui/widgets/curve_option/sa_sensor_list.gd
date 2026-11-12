## The curve option control's list of sensors: one row each, a switch, an Edit
## button, the lit row of the sensor the panel describes, and the greying of a
## sensor no input feeds.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Beside `sa_curve_option_control.gd` rather than in it, because a list of rows that answers which one is ticked is a job on its
## own. The control keeps the option, the curve and the sensor's own settings.
##
## **A sensor is greyed from `SaSensor.UNAVAILABLE`, never from a name here.**
## An availability flag on the sensor rather than a name test in the control. A second engine's sensor declares itself the
## same way and this file needs no line for it.
class_name SaSensorList
extends ScrollContainer

## The sensor list, by `SaSensor.KEYS` entry, in enum order. The deferred
## sensor is left out here rather than filtered later, so the list is one
## statement about what a painter can see. Rotation is **in** the list and
## greyed, because it is read and answers zero rather than being reserved, and
## so is tangential pressure wherever no pen source reads an airbrush's wheel.
const LABELS: Dictionary = {
    "pressure": "Pressure",
    "pressure_in": "Pressure (peak)",
    "tilt_x": "Tilt X",
    "tilt_y": "Tilt Y",
    "tilt_direction": "Tilt direction",
    "tilt_elevation": "Tilt elevation",
    "speed": "Speed",
    "drawing_angle": "Drawing angle",
    "rotation": "Rotation",
    "distance": "Distance",
    "time": "Time",
    "fade": "Fade",
    "fuzzy_per_dab": "Fuzzy per dab",
    "fuzzy_per_stroke": "Fuzzy per stroke",
    "tangential": "Tangential pressure",
    "depletion": "Depletion",
    "lift_up": "Lift-up",
    "texture": "Texture",
    "fuzzy_along_stroke": "Fuzzy along the stroke",
}

## The heading of a sensor whose curve every ticked sensor shares, whole for
## each of [constant LABELS] rather than the name dropped into one sentence, so
## a language with cases can treat it as it needs. Keyed as [constant LABELS].
const SHARED_HEADINGS: Dictionary = {
    "pressure": "Pressure. The curve is shared by every ticked sensor.",
    "pressure_in": "Pressure (peak). The curve is shared by every ticked sensor.",
    "tilt_x": "Tilt X. The curve is shared by every ticked sensor.",
    "tilt_y": "Tilt Y. The curve is shared by every ticked sensor.",
    "tilt_direction": "Tilt direction. The curve is shared by every ticked sensor.",
    "tilt_elevation": "Tilt elevation. The curve is shared by every ticked sensor.",
    "speed": "Speed. The curve is shared by every ticked sensor.",
    "drawing_angle": "Drawing angle. The curve is shared by every ticked sensor.",
    "rotation": "Rotation. The curve is shared by every ticked sensor.",
    "distance": "Distance. The curve is shared by every ticked sensor.",
    "time": "Time. The curve is shared by every ticked sensor.",
    "fade": "Fade. The curve is shared by every ticked sensor.",
    "fuzzy_per_dab": "Fuzzy per dab. The curve is shared by every ticked sensor.",
    "fuzzy_per_stroke": "Fuzzy per stroke. The curve is shared by every ticked sensor.",
    "tangential": "Tangential pressure. The curve is shared by every ticked sensor.",
    "depletion": "Depletion. The curve is shared by every ticked sensor.",
    "lift_up": "Lift-up. The curve is shared by every ticked sensor.",
    "texture": "Texture. The curve is shared by every ticked sensor.",
    "fuzzy_along_stroke": "Fuzzy along the stroke. The curve is shared by every ticked sensor.",
}

## The four sensors whose reading sweeps a length, and which therefore show a
## length spinbox and a periodic checkbox. Depletion is one of them: its length
## is what the pen holds and its sweep is what the stroke has spent.
const SWEEPING: Array[String] = ["distance", "time", "fade", "depletion"]

## Logical sizes. Both go through `SaUI.px`, and nothing here touches
## `content_scale_factor`, which is hard rule 7, one writer for UI scale.
const ROW_HEIGHT: int = 20
const LIST_HEIGHT: int = 150

## How far an unavailable row is faded. Dimmed **and** disabled, because a row a
## painter cannot use has to look like one.
const DIMMED: float = 0.5

signal sensor_toggled(key: String, on: bool)
signal sensor_picked(key: String)

## The sensor whose row is lit, by key: the one the curve and the settings
## below describe. Written by `show_picked` only.
var picked: String = ""

var _boxes: Dictionary = {}
var _rows: Dictionary = {}
var _picks: Dictionary = {}
## The lit row's ground, the Layers list's own selected row, so a picked sensor
## reads the way a picked layer does in every palette.
var _lit_style: StyleBoxFlat = SaTheme.make_row_style(true)


func _init() -> void:
    name = "SensorList"
    custom_minimum_size = Vector2(0, SaUI.px(LIST_HEIGHT))
    horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    var column := VBoxContainer.new()
    column.name = "Sensors"
    column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    for key: Variant in LABELS:
        column.add_child(_build_row(String(key)))
    add_child(column)


func _build_row(key: String) -> HBoxContainer:
    var row := HBoxContainer.new()
    row.name = "Row_" + key
    row.custom_minimum_size = Vector2(0, SaUI.px(ROW_HEIGHT))

    var box := CheckBox.new()
    box.name = "Check_" + key
    box.text = tr(String(LABELS[key]))
    box.toggled.connect(func(on: bool) -> void: sensor_toggled.emit(key, on))
    # A press on the row picks which sensor the settings and the curve below
    # belong to. The checkbox says whether it is read at all, and the two
    # questions are different: Krita puts the settings in a panel beside the list
    # for exactly this reason.
    var pick := Button.new()
    pick.name = "Pick_" + key
    pick.text = tr("Edit", "edit a sensor")
    # Framed at rest, in the theme's own button look, because a flat Edit reads
    # as plain text beside the label.
    pick.flat = false
    pick.tooltip_text = tr("Show this sensor's curve and settings.")
    pick.pressed.connect(func() -> void: sensor_picked.emit(key))
    row.draw.connect(_draw_row.bind(key, row))

    row.add_child(box)
    row.add_child(pick)
    _boxes[key] = box
    _rows[key] = row
    _picks[key] = pick
    _apply_availability(key, box, pick, row)
    return row


## Greys and disables a row whose sensor has no input behind it, and puts the
## reason on both controls so a hover anywhere on the row answers.
func _apply_availability(key: String, box: CheckBox, pick: Button, row: HBoxContainer) -> void:
    var id := SaSensor.id_of(key)
    if id < 0 or SaSensor.is_available(id as SaSensor.Id):
        return
    var why := SaSensor.unavailable_reason(id as SaSensor.Id)
    box.disabled = true
    pick.disabled = true
    box.tooltip_text = why
    pick.tooltip_text = why
    row.tooltip_text = why
    row.modulate.a = DIMMED


## Lights the picked row behind its switch and its Edit. Drawn by the row
## itself, under its children, so the row stays the `HBoxContainer` a dump and
## a scenario already name.
func _draw_row(key: String, row: HBoxContainer) -> void:
    if key == picked:
        row.draw_style_box(_lit_style, Rect2(Vector2.ZERO, row.size))


## Lights *key*'s row and puts out the one lit before, which is the only mark
## that says which sensor the panel below describes. A sweeping sensor shows
## settings of its own and a shared curve shows none, so without it a press on
## Edit could change nothing a painter can see.
func show_picked(key: String) -> void:
    if not _rows.has(key):
        return
    var before := _rows.get(picked, null) as CanvasItem
    picked = key
    if before != null:
        before.queue_redraw()
    (_rows[key] as CanvasItem).queue_redraw()


## The Edit button on *key*'s row, or null.
func edit_for(key: String) -> Button:
    return _picks.get(key, null) as Button


## The switch under *key*, or null.
func box_for(key: String) -> CheckBox:
    return _boxes.get(key, null) as CheckBox


## Whether the list carries a row for *key* at all.
func has_row(key: String) -> bool:
    return LABELS.has(key)


## Puts *key*'s switch where the option says, without emitting.
func show_ticked(key: String, on: bool) -> void:
    var box := box_for(key)
    if box != null:
        box.set_pressed_no_signal(on)


## Every key whose switch is on, in list order.
func ticked() -> Array[String]:
    var on: Array[String] = []
    for key: String in _boxes:
        if (_boxes[key] as CheckBox).button_pressed:
            on.append(key)
    return on


## Every row, for a state dump: what it is called, whether it is ticked, whether
## a painter can touch it at all, and the sentence that says why not.
##
## The tooltip is the half no shot and no geometry can show, which is the same
## reason the toolbox report carries one.
func report() -> Array[Dictionary]:
    var rows: Array[Dictionary] = []
    for key: String in _boxes:
        var box := _boxes[key] as CheckBox
        (
            rows
            . append(
                {
                    "key": key,
                    "label": box.text,
                    "ticked": box.button_pressed,
                    "disabled": box.disabled,
                    "dimmed": (_rows[key] as HBoxContainer).modulate.a < 1.0,
                    "tooltip": box.tooltip_text,
                    # Lit is the row the panel below describes, and framed
                    # is Edit drawn as a button rather than as text.
                    "lit": key == picked,
                    "edit_framed": not (_picks[key] as Button).flat,
                }
            )
        )
    return rows


## Scrolls *key*'s row into view.
##
## Picking a sensor shows its settings and its curve under a list that is a
## scrolling pane of fourteen rows in a hundred and fifty units, so the row the
## panel below is describing would often be off screen. It is also the only way a
## shot can show a row near the bottom, which the greyed one is.
func ensure_visible(key: String) -> void:
    var row := _rows.get(key, null) as Control
    if row == null:
        return
    ensure_control_visible(row)


## The line above the curve that names the sensor the panel describes.
##
## Here rather than in `sa_curve_option_control.gd`, and an inner class of the
## list, because it says one thing about the row the list lights. The control
## tells it which sensor is picked and whether the curve is shared.
##
## **A shared curve still names the sensor.** With "Use the same curve" on the
## graph does not change when another sensor is picked, so the name is the one
## thing a press on Edit changes there, and the line says the curve belongs to
## every ticked sensor so the unchanged graph reads as meant.
class Heading:
    extends Label

    func _init() -> void:
        name = "SensorHeading"
        autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        custom_minimum_size = Vector2(SaUI.px(120), 0)

    ## Names the sensor under *key*, and says the curve is every ticked
    ## sensor's when *shared*.
    func show_sensor(key: String, shared: bool) -> void:
        var title := tr(String(LABELS.get(key, key)))
        # The list's rows are [constant LABELS], so a selected sensor has its
        # whole heading. A key no row has, read from an old preset, is named
        # as it is.
        if shared and SHARED_HEADINGS.has(key):
            text = tr(SHARED_HEADINGS[key])
        else:
            text = title
