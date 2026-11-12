## The control that edits one `SaCurveOption`: strength, sensors, the curve and
## how the sensors combine.
##
## **In the widget toolkit, where any engine's page reaches it**, rather than in
## the brush editor or a module. Its option and its sensors, `SaCurveOption` and
## `SaSensor`, live in the door under `core/api/dynamics`, so any engine's page
## draws the curve editor a painter already knows from the stamp's. A module
## hands the control to the skeleton through `SaOptionSpec.build_control`, the
## door the base module's colour ramp uses too, and the skeleton builds the row, the page
## and the bare host from the spec without naming this class.
##
## **No title row.** The brush editor's page heading names the option and the
## bare host draws a label of its own, so the control draws no name and reports the page it was
## bound for, which a scenario reads.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The eight preset shapes and their control points are the one port in this file,
## from Krita 5.2.13 `plugins/paintops/libpaintop/KisCurveOptionWidget.cpp`, and
## **their copyright lines are in [`PROVENANCE.md`](PROVENANCE.md)**, beside this
## file. The layout is Krita's widget rearranged for a page rather than for
## its wide panel, which is an idea taken rather than a port.
##
## **Top to bottom**: the strength slider as a percentage, an "Enable pen
## settings" checkbox for `use_curve`, the eight preset buttons, the sensor
## list, the selected sensor's own settings, the graph, and under it the
## combination dropdown and "Share one curve".
##
## **The graph is `SaCurveEditor`, untouched.** It already draws a monotone
## cubic through draggable points over 0 to 1, which is exactly what a sensor
## curve is, and giving this one its own would have put two curve widgets in
## the app with two ideas of what a curve is.
##
## **Which curve the graph edits depends on one checkbox.** With "Share one
## curve" on it is the option's `common_curve`, which is Krita's default and
## what `begin_stroke` copies onto every prepared sensor. With it off it is the
## selected sensor's own `curve`. The graph does not know the difference, and
## `_write_curve` is the single place that does.
@tool
class_name SaCurveOptionControl
extends VBoxContainer

## The bound option changed, so a live preview or a dirty flag can follow.
signal option_changed

## Krita's eight preset shapes, in the order `forms/wdgcurveoption2.ui` lays the
## buttons out, which is not the order the slots are connected in.
##
## The points are `KisCurveOptionWidget::changeCurve*` verbatim. A shape is a
## control point list, not a formula: Krita's S is two inner points at 0.1 and
## 0.9 rather than a cubic, and rounding it to something tidier would change
## what a preset made in Krita does here.
const PRESET_ORDER: Array[String] = ["linear", "reverse_linear", "s", "reverse_s", "u", "arch", "j", "l"]

const PRESETS: Dictionary = {
    "linear": [Vector2(0.0, 0.0), Vector2(1.0, 1.0)],
    "reverse_linear": [Vector2(0.0, 1.0), Vector2(1.0, 0.0)],
    "s": [Vector2(0.0, 0.0), Vector2(0.25, 0.1), Vector2(0.75, 0.9), Vector2(1.0, 1.0)],
    "reverse_s": [Vector2(0.0, 1.0), Vector2(0.25, 0.9), Vector2(0.75, 0.1), Vector2(1.0, 0.0)],
    "u": [Vector2(0.0, 1.0), Vector2(0.5, 0.0), Vector2(1.0, 1.0)],
    "arch": [Vector2(0.0, 0.0), Vector2(0.5, 1.0), Vector2(1.0, 0.0)],
    "j": [Vector2(0.0, 0.0), Vector2(0.35, 0.1), Vector2(1.0, 1.0)],
    "l": [Vector2(0.0, 1.0), Vector2(0.25, 0.48), Vector2(1.0, 0.0)],
}

## What a preset button says in its tooltip, a whole sentence per preset so a
## language with cases can decline the name. The face of the button is the
## shape itself, drawn from the same points the press applies, because eight
## buttons in a row have space for a picture and not for a word, and a letter
## naming a shape is a second thing to learn.
const PRESET_TIPS: Dictionary = {
    "linear": "Set the curve to the Linear preset.",
    "reverse_linear": "Set the curve to the Reverse linear preset.",
    "s": "Set the curve to the S-curve preset.",
    "reverse_s": "Set the curve to the Reverse S-curve preset.",
    "u": "Set the curve to the U-curve preset.",
    "arch": "Set the curve to the Arch preset.",
    "j": "Set the curve to the J-curve preset.",
    "l": "Set the curve to the L-curve preset.",
}

## The drawn shape's inset inside its button, and how many segments it is made
## of, in logical units.
const PRESET_INSET: float = 5.0
const PRESET_SEGMENTS: int = 24

## The sensor list and the three sweeping sensors, which moved to
## [`sa_sensor_list.gd`](sa_sensor_list.gd) with the rows they build. Aliased
## here because `describe` reads `SENSOR_LABELS` by that name for the Tool
## Options docker's row text, and a split should move code without moving a
## name anyone types.
const SENSOR_LABELS: Dictionary = SaSensorList.LABELS
const SWEEPING: Array[String] = SaSensorList.SWEEPING

## The five combination modes, in `SaCurveOption.Combine` order so the index a
## dropdown reports is the enum value.
const COMBINE_LABELS: Array[String] = ["Multiply", "Add", "Maximum", "Minimum", "Difference"]

## Logical sizes. Every one of them goes through `SaUI.px`, and nothing here
## touches `content_scale_factor`, which is hard rule 7, one writer for UI scale.
const PRESET_SIZE: int = 26
const GRAPH_SIZE: int = 200
const SPIN_WIDTH: int = 90

## The sensor list's own floor, beside the graph rather than above it. Wide
## enough for its longest label, "Tilt elevation", plus the checkbox and the
## Edit button beside it, at the same width the list already asked for when
## it stood above the graph and had the whole control's width to answer in.
const SENSOR_LIST_WIDTH: int = 170

## The option this control is editing, or null.
var option: SaCurveOption = null
## The page the option was bound for, reported and never drawn.
var _page_title: String = ""
## Where an edit is reported beyond `option_changed`: the skeleton's write door,
## handed in by `build_control`. The option is edited in place, so what the
## door receives is the option itself, and the skeleton uses the call to know
## that something moved rather than to store a value.
var _write: Callable = Callable()
## Whether the option behind this control is read as a signed shift, which is
## the one thing the lift-up binding needs to know about the page it is on.
## Handed in by `build_control` from the option spec's key.
var _offset: bool = false
## The sensor whose own settings and own curve are shown, by key.
var selected: String = "pressure"
## True while a control is being filled in from the option, so a mirrored value
## does not write itself straight back and emit a change nobody made.
var _syncing: bool = false

var _strength: FactorSlider = null
var _use_curve: CheckBox = null
var _sensors: SaSensorList = null
var _heading: SaSensorList.Heading = null
var _extras: VBoxContainer = null
var _length: SpinBox = null
var _periodic: CheckBox = null
var _angle_offset: SpinBox = null
var _lock_angle: CheckBox = null
## Keeps `_graph` square at any width the control is given, rather than the
## graph stretching to fill a `VBoxContainer` row the way every other child
## here does.
var _graph_aspect: AspectRatioContainer = null
var _graph: SaCurveEditor = null
var _combine: SaChoiceButton = null
var _share: CheckBox = null


func _init(write: Callable = Callable(), offset: bool = false) -> void:
    _write = write
    _offset = offset
    name = "CurveOptionControl"
    add_theme_constant_override("separation", SaUI.px(6))
    _build()


func _build() -> void:
    _strength = FactorSlider.new()
    _strength.name = "Strength"
    _strength.min_value = 0.0
    _strength.max_value = 1.0
    _strength.step = 0.01
    _strength.prefix = tr("Strength") + ": "
    _strength.suffix = "%"
    _strength.normalized_display = true
    _strength.decimal_places = 0
    _strength.custom_minimum_size = Vector2(SaUI.px(180), SaUI.px(18))
    _strength.value_changed.connect(_on_strength_changed)
    add_child(_strength)

    _use_curve = CheckBox.new()
    _use_curve.name = "EnablePenSettings"
    _use_curve.text = tr("Enable pen settings")
    _use_curve.toggled.connect(_on_use_curve_toggled)
    add_child(_use_curve)

    add_child(_build_preset_row())
    _heading = SaSensorList.Heading.new()
    add_child(_heading)
    add_child(_build_curve_row())
    _extras = _build_extras()
    add_child(_extras)

    add_child(_build_footer())


## The graph, square at any width, beside the sensor list rather than under it,
## so the curve and the sensors it shapes are read side by side.
func _build_curve_row() -> HBoxContainer:
    var row := HBoxContainer.new()
    row.name = "CurveRow"
    row.add_theme_constant_override("separation", SaUI.px(8))

    _graph_aspect = AspectRatioContainer.new()
    _graph_aspect.name = "GraphAspect"
    _graph_aspect.ratio = 1.0
    _graph_aspect.stretch_mode = AspectRatioContainer.STRETCH_FIT
    _graph_aspect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _graph_aspect.size_flags_vertical = Control.SIZE_EXPAND_FILL

    _graph = SaCurveEditor.new()
    _graph.name = "CurveGraph"
    _graph.custom_minimum_size = Vector2(SaUI.px(GRAPH_SIZE), SaUI.px(GRAPH_SIZE))
    _graph.curve_changed.connect(_on_graph_changed)
    _graph_aspect.add_child(_graph)
    row.add_child(_graph_aspect)

    _sensors = SaSensorList.new()
    _sensors.custom_minimum_size = Vector2(SaUI.px(SENSOR_LIST_WIDTH), SaUI.px(SaSensorList.LIST_HEIGHT))
    _sensors.sensor_toggled.connect(_on_sensor_toggled)
    _sensors.sensor_picked.connect(_on_sensor_picked)
    row.add_child(_sensors)
    return row


func _build_preset_row() -> HBoxContainer:
    var row := HBoxContainer.new()
    row.name = "CurvePresets"
    row.add_theme_constant_override("separation", SaUI.px(2))
    for preset_name in PRESET_ORDER:
        var button := Button.new()
        button.name = "Preset_" + preset_name
        button.tooltip_text = tr(String(PRESET_TIPS[preset_name]))
        button.custom_minimum_size = Vector2(SaUI.px(PRESET_SIZE), SaUI.px(PRESET_SIZE))
        button.pressed.connect(_on_preset_pressed.bind(preset_name))
        button.draw.connect(_draw_preset.bind(button, preset_name))
        row.add_child(button)
    return row


## The preset's own shape on the face of its button, sampled through
## `SaCurveEditor` so the picture and the press cannot drift apart.
##
## Drawn from the `draw` signal rather than from a Button subclass, because a
## subclass would be a `class_name` for eight small pictures and nothing else.
func _draw_preset(button: Button, preset: String) -> void:
    var points := PackedVector2Array(PRESETS[preset] as Array)
    var samples := SaCurveEditor.sample_curve(points, PRESET_SEGMENTS)
    var inset := SaUI.pxf(PRESET_INSET)
    var span := button.size - Vector2(inset, inset) * 2.0
    if span.x <= 0.0 or span.y <= 0.0:
        return
    var line := PackedVector2Array()
    for index in samples.size():
        var at := float(index) / float(maxi(samples.size() - 1, 1))
        line.append(Vector2(inset + at * span.x, inset + (1.0 - samples[index]) * span.y))
    button.draw_polyline(line, SaCurveEditor.COLOR_CURVE, SaUI.pxf(1.5), true)


func _build_extras() -> VBoxContainer:
    var column := VBoxContainer.new()
    column.name = "SensorSettings"

    var sweep := HBoxContainer.new()
    sweep.name = "SweepRow"
    var length_label := Label.new()
    length_label.text = tr("Length")
    _length = SpinBox.new()
    _length.name = "Length"
    _length.min_value = 1
    _length.max_value = 10000
    _length.step = 1
    _length.custom_minimum_size = Vector2(SaUI.px(SPIN_WIDTH), 0)
    _length.value_changed.connect(_on_length_changed)
    _periodic = CheckBox.new()
    _periodic.name = "Periodic"
    _periodic.text = tr("Periodic")
    _periodic.toggled.connect(_on_periodic_toggled)
    sweep.add_child(length_label)
    sweep.add_child(_length)
    sweep.add_child(_periodic)
    column.add_child(sweep)

    var angle := HBoxContainer.new()
    angle.name = "AngleRow"
    var offset_label := Label.new()
    offset_label.text = tr("Offset")
    _angle_offset = SpinBox.new()
    _angle_offset.name = "AngleOffset"
    _angle_offset.min_value = 0
    _angle_offset.max_value = 360
    _angle_offset.step = 1
    _angle_offset.custom_minimum_size = Vector2(SaUI.px(SPIN_WIDTH), 0)
    _angle_offset.value_changed.connect(_on_angle_offset_changed)
    _lock_angle = CheckBox.new()
    _lock_angle.name = "LockAngle"
    _lock_angle.text = tr("Lock")
    _lock_angle.toggled.connect(_on_lock_toggled)
    angle.add_child(offset_label)
    angle.add_child(_angle_offset)
    angle.add_child(_lock_angle)
    column.add_child(angle)
    return column


func _build_footer() -> VBoxContainer:
    var column := VBoxContainer.new()
    column.name = "CurveFooter"
    _combine = SaChoiceButton.new()
    _combine.name = "Combine"
    var modes: Array = []
    for index in COMBINE_LABELS.size():
        modes.append({"id": index, "label": tr(COMBINE_LABELS[index])})
    _combine.set_choices(modes)
    _combine.choice_picked.connect(_on_combine_selected)
    _share = CheckBox.new()
    _share.name = "ShareOneCurve"
    _share.text = tr("Share one curve")
    _share.toggled.connect(_on_share_toggled)
    column.add_child(_combine)
    column.add_child(_share)
    return column


## The widget a curve option page is, which the module declaring the page
## brings rather than the skeleton.
##
## The door a module's colour ramp opens: a module's spec names this
## door, and the skeleton's editor page, bare host and docker row never name
## the control. The control lives in the toolkit because two engines draw it,
## and the skeleton outside the toolkit still does not name it. The brush
## editor's page and the bare host both build through here, and the docker's
## row is a button the skeleton draws with the words `describe` gives it.
##
## *write* goes into the control, unlike the ramp, which never calls its door:
## the option is edited in place either way, but the editor's dirty flag and its
## live preview have to hear about a moved curve, and the write door is how a
## widget the skeleton did not build tells the skeleton that something moved.
static func build_control(spec: SaOptionSpec, write: Callable) -> Control:
    return SaCurveOptionControl.new(write, spec != null and SaDynamics.is_offset(spec.key))


## Points the built control at the option behind its row. *page_title* is bound
## by whoever declares the spec, `SaCurveOptionPages.rows` for the stamp brush,
## because the binder is handed a control and a value and the spec's own label
## is what the control reports as its page.
##
## A null value is a throwaway: the capture harness's bare host opens on one so
## a scenario can drive the control with no editor in the tree, which is what
## the host is for, and the default option is the control's to make.
static func bind_control(control: Control, value: Variant, page_title: String) -> void:
    var bound := value as SaCurveOption
    if bound == null:
        bound = SaCurveOption.create_default()
    (control as SaCurveOptionControl).bind_option(bound, page_title)


## What a Tool Options docker row's button says the option is set to, in place
## of the name its own label column already carries.
##
## The percentage is the raw strength times a hundred, which is exactly what the
## editor's Strength slider shows, so a painter reading the row and a painter
## reading the page cannot be told two numbers. `enabled` off is reported as off
## rather than as a strength, because a strength behind a switch that is down is
## not what the dab is doing, and `use_curve` off is a constant for the same
## reason: the option answers its strength and reads no sensor at all. Through
## `TranslationServer` rather than `tr`, which a static function has no node to
## ask.
static func describe(value: Variant) -> String:
    var bound := value as SaCurveOption
    if bound == null:
        return TranslationServer.translate("None")
    if not bound.enabled:
        return TranslationServer.translate("Off")
    var percent := "%d%%" % roundi(bound.strength * 100.0)
    if not bound.use_curve:
        return "%s, %s" % [percent, TranslationServer.translate("Constant")]
    var names: Array[String] = []
    for sensor: SaSensor in bound.active_sensors():
        var key := SaSensor.key_of(sensor.id)
        names.append(TranslationServer.translate(String(SENSOR_LABELS.get(key, key))))
    if names.is_empty():
        return "%s, %s" % [percent, TranslationServer.translate("No sensor")]
    return "%s, %s" % [percent, " + ".join(names)]


## Points the control at *curve_option*, which it edits in place rather than
## copying.
##
## In place because the editor is open over the brush the painter is using: a
## copy would need a write-back on every change and a rule about which of the two
## is the real one while the window is up. *page_title* is what `option_report`
## answers for `page`, and nothing draws it here: the brush editor's heading is
## the name at font size 16, and this control's own title row once repeated it
## directly under it, so the page said "Size" twice and neither said what Size
## was set to. The bare host draws its own label, so the row is gone rather than
## hidden.
func bind_option(curve_option: SaCurveOption, page_title: String = "") -> void:
    option = curve_option
    _page_title = page_title
    if option != null:
        option.ensure_one_active()
        var active := option.active_sensors()
        if not active.is_empty():
            selected = SaSensor.key_of(active[0].id)
    sync()


## Fills every control from the option. The one direction that never writes.
func sync() -> void:
    _syncing = true
    if option != null:
        _strength.min_value = option.strength_min
        _strength.max_value = option.strength_max
        _strength.value = option.strength
        _use_curve.set_pressed_no_signal(option.use_curve)
        _combine.select_value(int(option.combine))
        _share.set_pressed_no_signal(option.use_same_curve)
        for key: String in SENSOR_LABELS:
            var sensor := _sensor_for(key)
            _sensors.show_ticked(key, sensor != null and sensor.active)
        _graph.set_points(_curve_points())
    _sync_extras()
    _syncing = false


## Shows the selected sensor's own settings, and only the rows that sensor has.
##
## Hidden rather than disabled: a length spinbox beside a pressure sensor is a
## question the sensor cannot answer, and a disabled control invites a painter
## to wonder what would enable it.
func _sync_extras() -> void:
    _show_pick()
    var sweeping := selected in SWEEPING
    var angular := selected == "drawing_angle"
    (_extras.get_node("SweepRow") as Control).visible = sweeping
    (_extras.get_node("AngleRow") as Control).visible = angular
    _extras.visible = sweeping or angular
    var sensor := _sensor_for(selected)
    if sensor == null:
        return
    if sweeping:
        _length.set_value_no_signal(float(sensor.length))
        _periodic.set_pressed_no_signal(sensor.periodic)
    if angular:
        _angle_offset.set_value_no_signal(sensor.angle_offset)
        _lock_angle.set_pressed_no_signal(sensor.lock_angle)


## Lights the picked sensor's row and names it above the curve, saying so when
## the curve is shared, which is all a press on Edit changes for most sensors.
func _show_pick() -> void:
    _sensors.show_picked(selected)
    _heading.show_sensor(selected, option != null and option.use_same_curve)


## The sensor stored under *key*, or null when the option carries none.
##
## Null is the ordinary case rather than an error: `SaCurveOption.sensors` holds
## only the active sensors and the ones with a curve worth keeping, so a preset
## on disk is small and everything absent reads as off with an identity curve.
func _sensor_for(key: String) -> SaSensor:
    if option == null:
        return null
    var id := SaSensor.id_of(key)
    return option.sensor_for(id) if id >= 0 else null


## The sensor under *key*, created and stored when the option had none.
func _ensure_sensor(key: String) -> SaSensor:
    var sensor := _sensor_for(key)
    if sensor != null:
        return sensor
    var id := SaSensor.id_of(key)
    if option == null or id < 0:
        return null
    sensor = SaSensor.create(id as SaSensor.Id, false)
    option.set_sensor(sensor)
    return sensor


## Which curve the graph is showing: the shared one, or the selected sensor's.
func _curve_points() -> PackedVector2Array:
    if option == null:
        return PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 1.0)])
    if option.use_same_curve:
        return option.common_curve
    var sensor := _sensor_for(selected)
    return sensor.curve if sensor != null else PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 1.0)])


func _write_curve(points: PackedVector2Array) -> void:
    if option == null:
        return
    if option.use_same_curve:
        option.common_curve = points
    else:
        var sensor := _ensure_sensor(selected)
        if sensor != null:
            sensor.curve = points
    _changed()


func _changed() -> void:
    if _syncing:
        return
    option_changed.emit()
    if _write.is_valid():
        _write.call(option)


# --- What a hand does, named for the hand ---------------------------------------


## One of the eight preset shapes onto the curve the graph is showing.
func apply_preset(preset: String) -> bool:
    if not PRESETS.has(preset):
        return false
    var points := PackedVector2Array(PRESETS[preset] as Array)
    _graph.set_points(points)
    _write_curve(_graph.points)
    return true


func set_strength(value: float) -> void:
    if option == null:
        return
    option.strength = clampf(value, option.strength_min, option.strength_max)
    _strength.value = option.strength
    _changed()


func set_use_curve(on: bool) -> void:
    if option == null:
        return
    option.use_curve = on
    _use_curve.set_pressed_no_signal(on)
    _changed()


func set_use_same_curve(on: bool) -> void:
    if option == null:
        return
    option.use_same_curve = on
    _share.set_pressed_no_signal(on)
    _graph.set_points(_curve_points())
    _show_pick()
    _changed()


func set_combine(mode: int) -> void:
    if option == null:
        return
    option.combine = mode as SaCurveOption.Combine
    _combine.select_value(mode)
    _changed()


## Switches a sensor on or off. False when the request was refused, which is
## Krita's rule: the last active sensor cannot be switched off, because an option
## with none would answer a constant while looking as though it were listening.
func set_sensor_active(key: String, on: bool) -> bool:
    if option == null or not _sensors.has_row(key):
        return false
    # A sensor no input feeds is refused rather than ticked. The row is
    # disabled, so a hand cannot reach it, and this is the door a scenario and
    # the capture step come through, which a disabled control does not close.
    var id := SaSensor.id_of(key)
    if id >= 0 and not SaSensor.is_available(id as SaSensor.Id):
        return false
    if not on:
        var active := option.active_sensors()
        if active.size() <= 1 and _sensor_for(key) != null and _sensor_for(key).active:
            _sensors.show_ticked(key, true)
            return false
    if on and id == SaSensor.Id.LIFT_UP:
        # The lift-up arrives bound, on a curve that takes paint away as the
        # pen lets go, because the identity would read it backwards. The door
        # makes the binding and the share box follows it off.
        option.bind_lift_up(_offset)
        _share.set_pressed_no_signal(option.use_same_curve)
        _sensors.show_ticked(key, true)
        select_sensor(key)
        _changed()
        return true
    var sensor := _ensure_sensor(key)
    if sensor == null:
        return false
    sensor.active = on
    option.set_sensor(sensor)
    _sensors.show_ticked(key, on)
    if on:
        select_sensor(key)
    _changed()
    return true


## Picks whose settings and whose curve are shown, without switching it on.
func select_sensor(key: String) -> bool:
    if not _sensors.has_row(key):
        return false
    selected = key
    # The list is fourteen rows in a hundred and fifty units, so the row the
    # panel below is describing would often be off screen.
    _sensors.ensure_visible(key)
    _sync_extras()
    if option != null and not option.use_same_curve:
        _graph.set_points(_curve_points())
    return true


func set_length(value: int) -> void:
    var sensor := _ensure_sensor(selected)
    if sensor == null:
        return
    sensor.length = maxi(value, 1)
    _length.set_value_no_signal(float(sensor.length))
    _changed()


func set_periodic(on: bool) -> void:
    var sensor := _ensure_sensor(selected)
    if sensor == null:
        return
    sensor.periodic = on
    _periodic.set_pressed_no_signal(on)
    _changed()


func set_angle_offset(degrees: float) -> void:
    var sensor := _ensure_sensor("drawing_angle")
    if sensor == null:
        return
    sensor.angle_offset = degrees
    _angle_offset.set_value_no_signal(degrees)
    _changed()


func set_lock_angle(on: bool) -> void:
    var sensor := _ensure_sensor("drawing_angle")
    if sensor == null:
        return
    sensor.lock_angle = on
    _lock_angle.set_pressed_no_signal(on)
    _changed()


## Moves the curve the graph is showing, as a drag on a point would.
func set_curve(points: PackedVector2Array) -> void:
    _graph.set_points(points)
    _write_curve(_graph.points)


## A hand's drag on the graph from *from* to *to*, in curve units, written back
## through the graph's own signal as a real drag is.
func drag_curve(from: Vector2, to: Vector2) -> void:
    _graph.drag_through(from, to)


# --- What the control shows, for a dump, a test and the capture door -------------


## What the control is showing and what the option holds, side by side.
##
## Both, because the two disagreeing is the bug this control invites: a graph
## drawn from a curve it then failed to write back looks right in a screenshot.
func option_report() -> Dictionary:
    var boxes := _sensors.ticked()
    var active: Array[String] = []
    if option != null:
        for sensor in option.active_sensors():
            active.append(SaSensor.key_of(sensor.id))
    return {
        "page": _page_title,
        "bound": option != null,
        "strength": option.strength if option != null else 0.0,
        "shown_strength": _strength.value,
        "use_curve": option.use_curve if option != null else false,
        "use_same_curve": option.use_same_curve if option != null else false,
        "combine": int(option.combine) if option != null else 0,
        "shown_combine": _combine.selected_value(),
        "active": active,
        "ticked": boxes,
        "selected": selected,
        "heading": _heading.text,
        # Every row, with whether a painter can touch it and the sentence
        # that says why not, which is the half no shot can show.
        "sensors": _sensors.report(),
        "curve": _points_report(_curve_points()),
        "shown_curve": _points_report(_graph.points),
        "sensor_settings": _selected_settings(),
        # The graph's own drawn size, so a scenario can read it square
        # without measuring a screenshot, and the sensor list's rect beside
        # it, both in the host's own space.
        "graph_rect": _rect(_graph.get_global_rect()),
        "sensors_rect": _rect(_sensors.get_global_rect()),
    }


static func _rect(r: Rect2) -> Dictionary:
    return {"x": r.position.x, "y": r.position.y, "w": r.size.x, "h": r.size.y}


func _selected_settings() -> Dictionary:
    var sensor := _sensor_for(selected)
    if sensor == null:
        return {}
    return {
        "length": sensor.length,
        "periodic": sensor.periodic,
        "angle_offset": sensor.angle_offset,
        "lock_angle": sensor.lock_angle,
    }


static func _points_report(points: PackedVector2Array) -> Array:
    var out: Array = []
    for point in points:
        out.append([snappedf(point.x, 0.0001), snappedf(point.y, 0.0001)])
    return out


# --- The controls' own signals ---------------------------------------------------


func _on_strength_changed(value: float) -> void:
    if not _syncing:
        set_strength(value)


func _on_use_curve_toggled(on: bool) -> void:
    if not _syncing:
        set_use_curve(on)


func _on_preset_pressed(preset: String) -> void:
    apply_preset(preset)


## The list's signal carries the key first, and so does this. With the box's
## state first, every tick a hand gave a sensor failed to convert and never
## reached the option, and only the door's `set_sensor_active` ticked one. After
## the write the box is put where the option says, so a refused or dropped tick
## shows what the brush really holds.
func _on_sensor_toggled(key: String, on: bool) -> void:
    if _syncing:
        return
    set_sensor_active(key, on)
    var sensor := _sensor_for(key)
    _sensors.show_ticked(key, sensor != null and sensor.active)


func _on_sensor_picked(key: String) -> void:
    select_sensor(key)


func _on_length_changed(value: float) -> void:
    if not _syncing:
        set_length(int(value))


func _on_periodic_toggled(on: bool) -> void:
    if not _syncing:
        set_periodic(on)


func _on_angle_offset_changed(value: float) -> void:
    if not _syncing:
        set_angle_offset(value)


func _on_lock_toggled(on: bool) -> void:
    if not _syncing:
        set_lock_angle(on)


func _on_combine_selected(mode: Variant) -> void:
    if not _syncing:
        set_combine(int(mode))


func _on_share_toggled(on: bool) -> void:
    if not _syncing:
        set_use_same_curve(on)


func _on_graph_changed() -> void:
    if not _syncing:
        _write_curve(_graph.points)
