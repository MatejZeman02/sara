## What the three slider adjustments share as filters: rows declared from a
## table, a gradient slider per number, and a run that records a point
## pass.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A kind is a subclass that answers five questions: which kernel, which rows,
## what the sliders mean to that kernel, what colours sit behind a slider, and
## the chord and command it carries. Everything else is here, because those
## five answers are the whole of what one kind differs from another by.
##
## The sliders are `ui.custom` rows, because a slider over a ramp of the colour
## it moves towards is not one of the dialog's own widgets, so each number is
## declared with `ui.parameter` and its slider writes the filter's value. The
## pictures and the two buttons are the dialog's.
class_name SaAdjustFilter
extends SaFilter

## How many colours a gradient is sampled at.
const GRADIENT_STOPS := 24


## The box a number row's slider sits in, and the row's door for a scenario's
## `widget` step.
##
## The box is the custom row's control, so the step asks it and not the slider.
## A box that answered no door was driven by the row's own write, which moved
## the row's number and asked for a rerun while the filter's value, the one the
## slider's signal writes, stayed where it was: the step printed `contrast ->
## 100.0` and the picture never changed. This moves the slider and raises the
## signal a drag raises, so the step and the hand write through one path.
class SliderRow:
    extends HBoxContainer

    var _key := ""
    var _slider: SaGradientSlider = null

    func _init(key: String, slider: SaGradientSlider) -> void:
        _key = key
        _slider = slider

    ## `{"value": 100}`, in the row's own units, and what the slider holds after.
    func capture_option_edit(spec: Dictionary) -> String:
        if _slider == null or not is_instance_valid(_slider):
            return "SaCapture: the %s row has no slider" % _key
        if spec.has("value"):
            _slider.value = float(spec["value"])
            _slider.value_changed.emit(_slider.value)
        return "%s -> %s" % [_key, _slider.value]


var _engine := SaPointAdjust.new()

## Row key -> the slider the last `build` made for it. A control goes with the
## dialog that held it, so every read asks whether it is still there.
var _sliders: Dictionary = {}
## Row key -> the checkbox row of the last `build`, which a capture drives.
var _checks: Dictionary = {}


## The kernel this filter runs, one of `SaPointAdjust.KINDS`.
func kind() -> StringName:
    return SaPointAdjust.BRIGHTNESS_CONTRAST


## The rows, in order. A slider is `key`, `label`, `min`, `max`, `default` and
## `suffix`, a heading is `type` "heading" and `label`, and a toggle is `type`
## "check", `key`, `label` and `default`. A slider's `soft_min` and `soft_max`
## are optional, where a drag stops inside `min` and `max`, which a typed
## number still reaches.
func rows() -> Array:
    return []


## What the kernel is handed for *raw*, the rows' own numbers by key:
## percentages to factors and offsets.
func to_pass_units(raw: Dictionary) -> Dictionary:
    return raw


## The colours behind the slider of that key, left to right.
func gradient_for(_key: String) -> PackedColorArray:
    return PackedColorArray()


func id() -> StringName:
    return kind()


func build(ui: SaDialog) -> void:
    ui.title(title())
    _sliders.clear()
    _checks.clear()
    for row: Dictionary in rows():
        match String(row.get("type", "slider")):
            "heading":
                ui.custom("", _make_heading.bind(row)).named(StringName(String(row["label"]).to_lower() + "_heading"))
            "check":
                var key := StringName(String(row["key"]))
                _checks[String(key)] = ui.checkbox(String(row["label"]), bool(row.get("default", false))).named(key)
            _:
                var key := StringName(String(row["key"]))
                ui.parameter(key, float(row["default"]), float(row["min"]), float(row["max"]))
                ui.custom(String(row["label"]), _make_slider.bind(row)).named(key)
    # Under the sliders rather than above them, where the dialog would put them.
    ui.thumbnail()
    ui.canvas_preview()


func run(ctx: SaFilterContext) -> void:
    # The descriptor and not the name `ctx.color_space()` answers, because the
    # kernel wants the matrices. The context's own docstring sends a filter
    # here for it.
    var recorded := _engine.record(kind(), values(), ctx.document.color_space)
    if recorded != null:
        ctx.point_pass(recorded.shader, recorded.kernel, recorded.push, recorded.buffers, recorded.origin_slot)


## The rows as the kernel takes them, which is what a `preview` step's read
## prints and what Apply commits. The record keeps [method parameters], the
## rows' own numbers, because a factor recomputed from a stored factor drifts.
func values() -> Dictionary:
    return to_pass_units(parameters())


## `{"hue": 120, "saturation": 140}` moves the open dialog's rows in their own
## units, the way a capture scenario drives them, and answers what it moved.
## Each goes through the signal its control raises, so one rerun follows.
func capture_set(spec: Dictionary) -> Dictionary:
    var moved: Dictionary = {}
    for row: Dictionary in rows():
        var key := String(row.get("key", ""))
        if key.is_empty() or not spec.has(key):
            continue
        var slider := _slider(key)
        var check := _checks.get(key, null) as SaPageRow
        if slider != null:
            slider.value = float(spec[key])
            slider.value_changed.emit(slider.value)
        elif check != null:
            check.drive(bool(spec[key]))
        else:
            continue
        moved[key] = spec[key]
    return moved


## `{"brightness": 0.2, "contrast": 1.5}`, in the units the pass takes, over
## *document*'s active layer as one step with no dialog. The `adjust` step's
## door, reached by name so the harness names no module class.
func capture_apply(document: SaDocument, spec: Dictionary) -> bool:
    if document == null:
        return false
    return _engine.apply(document, document.active_layer, kind(), spec, title())


func _slider(key: String) -> SaGradientSlider:
    var found: Variant = _sliders.get(key, null)
    if found == null or not is_instance_valid(found):
        return null
    return found as SaGradientSlider


## What `ui.custom` calls for a number row: a slider over its ramp, which asks
## for a rerun when it moves.
func _make_slider(rerun: Callable, row: Dictionary) -> Control:
    var key := String(row["key"])
    var slider := SaGradientSlider.new()
    slider.name = key.capitalize() + "Slider"
    slider.min_value = float(row["min"])
    slider.max_value = float(row["max"])
    slider.soft_min_value = float(row.get("soft_min", 0.0))
    slider.soft_max_value = float(row.get("soft_max", 0.0))
    slider.step = float(row.get("step", 1.0))
    slider.suffix = String(row.get("suffix", ""))
    slider.decimal_places = int(row.get("decimals", 0))
    slider.value = float(parameter(StringName(key)))
    slider.custom_minimum_size = Vector2(0.0, float(SaUI.px(26)))
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider.set_stops(gradient_for(key))
    slider.value_changed.connect(
        func(moved: float) -> void:
            write_parameter(StringName(key), moved)
            rerun.call()
    )
    _sliders[key] = slider
    # In a box of its own, so the name sits beside the slider rather than
    # inside it. The page leaves the label column empty for a bare
    # `FactorSlider`, which carries its caption as a prefix, and that prefix is
    # cut at ten characters where "Magenta-Green" is thirteen.
    var box := SliderRow.new(key, slider)
    box.name = key.capitalize() + "Row"
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_child(slider)
    return box


## The band a run of sliders belongs to, so nine rows read as three groups of
## three rather than as nine names that repeat.
func _make_heading(_rerun: Callable, row: Dictionary) -> Control:
    var label := Label.new()
    label.name = String(row["label"]).replace(" ", "") + "Heading"
    label.text = tr(String(row["label"]))
    # The theme pass writes font_size onto every Control it walks, so the meta
    # is what survives it.
    label.set_meta(SaUI.FONT_SCALE_META, 1.0)
    SaTheme.bind_font(label, "text_muted")
    return label


## *lab* as a display colour, clamped to what a ramp can draw.
static func oklab_to_color(lab: Vector3) -> Color:
    var linear := OkhsvConversions.oklab_to_linear_srgb(lab)
    var clamped := Vector3(clampf(linear.x, 0.0, 1.0), clampf(linear.y, 0.0, 1.0), clampf(linear.z, 0.0, 1.0))
    var encoded := OkhsvConversions.srgb_transfer_function(clamped)
    return Color(encoded.x, encoded.y, encoded.z, 1.0)


## A chord of one printed key under Ctrl, the shape the skeleton writes its own
## chords in.
static func ctrl_chord(keycode: Key, shift: bool = false) -> Array[InputEvent]:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.ctrl_pressed = true
    event.shift_pressed = shift
    return [event]
