## The randomise control that sits under a slider on the noise brush's page: how
## far the setting is rolled below its row, and whether along the stroke or once
## per stroke.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Beside every slider.** A randomise slider sits next to each slider, with
## two clocks, so a Hardness rolled along the stroke gives hard, soft and lost
## edges in one stroke without a painter building a fuzzy curve in the curve
## editor. The curve editor does the same thing, and this is the same binding
## reached from the row: `SaCurveOption.bind_random` writes the fuzzy sensor
## under the setting's curve option, and this control reads it back from there,
## so the settings stay one model and a preset carries the roll.
##
## **Along the stroke rather than per dab**, because a roll drawn afresh at
## every point is the stamp again. The first clock is the door's smooth noise
## of the travelled length, the second one number a stroke.
##
## **One call per row.** [method beside] makes the row's spec from the slider's
## own, so an engine appends one line after each numeric row it declares and a
## row added later gains its control the same way. The skeleton builds it through
## the `CUSTOM` door like any module's widget and never names this class.
##
## **It lives with the noise brush,** its one user, as a tool's engine does. The
## day a second engine puts one under its sliders it moves to
## `ui/widgets/curve_option`, beside the curve option control, and nothing in it
## names the noise brush. It has a folder of its own in the module, a whole
## widget the module names by its class alone.
##
## **The option is edited in place,** as the curve option control edits it, and
## *write* is called with the option itself so the editor's dirty flag and the
## other surface hear that something moved.
@tool
class_name SaRandomiseControl
extends HBoxContainer

## What the two clocks are called in a scenario and on the choice, and the
## fuzzy sensor each binds.
const ALONG: String = "along"
const PER_STROKE: String = "stroke"
const CLOCKS: Dictionary = {
    ALONG: SaSensor.Id.FUZZY_ALONG_STROKE,
    PER_STROKE: SaSensor.Id.FUZZY_PER_STROKE,
}

## The option this control edits, or null before it is bound.
var option: SaCurveOption = null
## The name the roll is drawn by, the option's own without its `_option`
## suffix. Handed in by `build_control` from the spec's property.
var _key: String = ""
## Where an edit is reported, the skeleton's write door.
var _write: Callable = Callable()
## The clock picked while the amount is nought, when no sensor holds it.
var _clock_id: SaSensor.Id = SaSensor.Id.FUZZY_ALONG_STROKE
## True while the controls are filled in from the option, so a mirrored value
## does not write itself straight back.
var _syncing: bool = false

var _amount: FactorSlider = null
var _clock: SaChoiceButton = null


## The clock's choice, as wide as its longest label as drawn, which the
## constant of 76 logical pixels it had never was: "Per stroke" read "Per..." at
## every width of the Brush Editor, and "Along the stroke" is longer still.
## Fitted on its own theme change, which is how entering the tree and a new font
## size reach it. A subclass because the button's own notification is the first
## moment its theme reads fresh: the `theme_changed` signal and this row's
## notification both come before it, and both measured the font the button was
## built with.
class FittedChoice:
    extends SaChoiceButton

    func _notification(what: int) -> void:
        if what == NOTIFICATION_THEME_CHANGED:
            custom_minimum_size = Vector2(SaRandomiseControl.fitting_width(self), 0)


## *prefix* names the two controls, the row's key in Pascal case, so a scenario
## moves one by name with the `control` step.
func _init(write: Callable = Callable(), key: String = "", prefix: String = "Random") -> void:
    _write = write
    _key = key
    name = prefix + "Randomise"
    add_theme_constant_override("separation", SaUI.px(4))
    # An indent, so the row reads as the slider's above it and not as a row of
    # its own.
    var indent := Control.new()
    indent.name = "Indent"
    indent.custom_minimum_size = Vector2(SaUI.px(8), 0)
    add_child(indent)

    _amount = SaMake.slider(self, prefix + "RandomAmount", 0.0, 1.0, 0.01, 0.0)
    _amount.prefix = tr("Random") + ": "
    _amount.suffix = "%"
    _amount.normalized_display = true
    _amount.decimal_places = 0
    _amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    # Narrower than a slider's own floor, so the row and its clock fit a docker
    # at its narrowest beside the label column.
    _amount.preferred_width = SaUI.px(60)
    _amount.tooltip_text = tr("How far below the set value the random value may go. 0 turns randomness off.")
    _amount.value_changed.connect(_on_amount_changed)

    var clocks := [{"id": ALONG, "label": tr("Along the stroke")}, {"id": PER_STROKE, "label": tr("Per stroke")}]
    # Placed by hand as `SaMake.choice` places one, kind and all, because the
    # choice is the fitted one below rather than the plain button.
    _clock = FittedChoice.new()
    _clock.name = prefix + "RandomClock"
    _clock.set_meta(SaMake.KIND_META, SaMake.Kind.CHOICE)
    _clock.set_choices(clocks)
    add_child(_clock)
    _clock.tooltip_text = tr("Change the random value slowly along the stroke, over a few brush widths, or once per stroke.")
    _clock.select_value(ALONG)
    _clock.choice_picked.connect(_on_clock_picked)


## The width *choice* needs to show each of its labels whole: the longest
## label at the button's own font, the arrow and its gap, and the chrome's
## margins, which is what the button draws when its text is not cut. Read from
## the theme rather than off the button, because the arrow is put on the button
## after the theme has already told this control it moved.
static func fitting_width(choice: SaChoiceButton) -> float:
    var font := choice.get_theme_font(&"font")
    var font_size := choice.get_theme_font_size(&"font_size")
    var widest := 0.0
    for label: String in choice.choice_labels():
        widest = maxf(widest, font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
    var arrow := 0.0
    if choice.has_theme_icon(&"arrow", &"OptionButton"):
        arrow = float(choice.get_theme_icon(&"arrow", &"OptionButton").get_width())
        var cap := choice.get_theme_constant(&"icon_max_width")
        if cap > 0:
            arrow = minf(arrow, float(cap))
        arrow += maxf(0.0, float(choice.get_theme_constant(&"h_separation")))
    var chrome := 0.0
    for state: StringName in [&"normal", &"hover", &"pressed"]:
        chrome = maxf(chrome, choice.get_theme_stylebox(state).get_minimum_size().x)
    return ceilf(widest + arrow + chrome)


## The spec of the randomise row under *row*, bound to the curve option called
## *option_property* on the same settings. It sits on the row's page, under the
## same conditions, and stays off the bar, which has no room for a second
## control per slider.
static func beside(row: SaOptionSpec, option_property: StringName) -> SaOptionSpec:
    var spec := SaOptionSpec.make_custom(
        StringName(String(row.key) + "_random"),
        "",
        build_control,
        bind_control,
        {
            "property": NodePath(String(option_property)),
            "page": row.page,
            "advanced": row.advanced,
            "shown_when": row.shown_when,
            "in_editor": row.in_editor,
            "in_docker": row.in_docker,
            "bar": false,
            "tooltip": "Randomize %s along the stroke or once per stroke." % row.label
        }
    )
    return spec


## The `CUSTOM` door's factory. The option's name is the spec's property with
## its suffix taken off, and the controls are named after the slider's key.
static func build_control(spec: SaOptionSpec, write: Callable) -> Control:
    var property := String(spec.property) if spec != null else ""
    var key := property.trim_suffix("_option")
    var row_key := String(spec.key).trim_suffix("_random") if spec != null else "random"
    return SaRandomiseControl.new(write, key, row_key.to_pascal_case())


## The `CUSTOM` door's binder: points the control at the option behind its
## row. A null value is a throwaway, as the curve option control's is.
static func bind_control(control: Control, value: Variant) -> void:
    var bound := value as SaCurveOption
    (control as SaRandomiseControl).bind_option(bound if bound != null else SaCurveOption.new())


## Points the control at *curve_option* and shows what its fuzzy sensor holds.
func bind_option(curve_option: SaCurveOption) -> void:
    option = curve_option
    sync()


## Fills both controls from the option. The one direction that never writes.
func sync() -> void:
    if option == null:
        return
    _syncing = true
    _amount.value = option.random_amount()
    if option.random_amount() > 0.0:
        _clock_id = CLOCKS[_clock_name(option.random_clock())]
    _clock.select_value(_clock_name(_clock_id))
    _syncing = false


func _on_amount_changed(value: float) -> void:
    _apply(value)


func _on_clock_picked(value: Variant) -> void:
    _clock_id = CLOCKS.get(String(value), SaSensor.Id.FUZZY_ALONG_STROKE)
    # The amount as the option holds it, which the slider only shows.
    _apply(option.random_amount() if option != null else 0.0)


func _apply(amount: float) -> void:
    if _syncing or option == null:
        return
    option.bind_random(amount, _clock_id, _key)
    if _write.is_valid():
        _write.call(option)


## The choice's name for *clock*. A roll on a clock the choice does not offer,
## a per dab sensor ticked in the curve editor, shows as along the stroke,
## which is what the control's next edit binds in its place.
static func _clock_name(clock: SaSensor.Id) -> String:
    return PER_STROKE if clock == SaSensor.Id.FUZZY_PER_STROKE else ALONG
