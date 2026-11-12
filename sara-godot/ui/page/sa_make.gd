## One call per control: make it, name it, give it what its kind always needs,
## add it to its parent and hand it back typed.
##
## The commonest shape in the interface was five lines for one control, and the
## lines were the same in every file. Typed functions rather than one function
## taking a dictionary of properties, because a dictionary loses the language
## server's checking, which the gate runs. What a kind needs only sometimes, a
## width, an expand flag, a signal, stays a line under the call.
##
## A null parent makes and names the control without adding it, for a control
## whose place is decided later, such as the options a bar moves between rows.
## Spacing is in logical pixels and goes through `SaUI.px` here, so a caller
## passes `SaTheme.GAP` and not a scaled number.
##
## Every control made here carries its kind under [constant KIND_META], beside
## the name it was given, so the harness's walker prints any of them and moves
## the plain ones without a hook written for the screen.
class_name SaMake
extends Object

## The gap a container gets when the call names none: no override at all, so
## the theme pass keeps writing the base separation for the interface scale.
const THEMED: int = -1

## The meta a made control carries its [enum Kind] under.
const KIND_META: StringName = &"sa_make_kind"

## What a made control is, in the words the walker prints. A slider, a spin box,
## a toggle, a choice and a text field hold a value a hand moves, and the rest
## hold words or other controls. Stops came last, so every kind before it keeps
## its number.
enum Kind { LABEL, BUTTON, TOGGLE, TEXT, SPIN, SLIDER, CHOICE, ROW, COLUMN, GRID, MARGIN, SCROLL, SEPARATOR, STOPS }


## The kind *control* was made as, or -1 for a control this file did not make.
static func kind_of(control: Node) -> int:
    if control == null or not control.has_meta(KIND_META):
        return -1
    return int(control.get_meta(KIND_META))


static func label(parent: Node, node_name: String, text: String = "") -> Label:
    var made := Label.new()
    made.text = text
    return _placed(parent, node_name, made, Kind.LABEL) as Label


static func button(parent: Node, node_name: String, text: String = "", tooltip: String = "") -> Button:
    var made := Button.new()
    made.text = text
    made.tooltip_text = tooltip
    return _placed(parent, node_name, made, Kind.BUTTON) as Button


static func check_box(parent: Node, node_name: String, text: String = "", pressed: bool = false) -> CheckBox:
    var made := CheckBox.new()
    made.text = text
    made.button_pressed = pressed
    return _placed(parent, node_name, made, Kind.TOGGLE) as CheckBox


## The switch an on or off choice is, the `CheckButton` a page's toggle row
## draws. Its words go in a label on its left and *text* stays empty, so its
## box rims the switch alone and not a row of words that reads as a field.
static func switch(parent: Node, node_name: String, text: String = "", pressed: bool = false) -> CheckButton:
    var made := CheckButton.new()
    made.text = text
    made.button_pressed = pressed
    return _placed(parent, node_name, made, Kind.TOGGLE) as CheckButton


static func line_edit(parent: Node, node_name: String, text: String = "", placeholder: String = "") -> LineEdit:
    var made := LineEdit.new()
    made.text = text
    made.placeholder_text = placeholder
    return _placed(parent, node_name, made, Kind.TEXT) as LineEdit


## The range is set before the value, so a value outside the engine's default
## range of 0 to 100 is not clamped on the way in.
static func spin_box(parent: Node, node_name: String, min_value: float, max_value: float, step: float, value: float) -> SpinBox:
    var made := SpinBox.new()
    made.min_value = min_value
    made.max_value = max_value
    made.step = step
    made.value = value
    return _placed(parent, node_name, made, Kind.SPIN) as SpinBox


## Sara's own slider, the one that carries its value as text inside the bar.
static func slider(
    parent: Node, node_name: String, min_value: float, max_value: float, step: float, value: float
) -> FactorSlider:
    var made := FactorSlider.new()
    made.min_value = min_value
    made.max_value = max_value
    made.step = step
    made.value = value
    return _placed(parent, node_name, made, Kind.SLIDER) as FactorSlider


## What an `OptionButton` was for. *choices* is `[{"id": Variant, "label":
## String}]`, the shape `SaChoiceButton.set_choices` reads, and an empty list
## leaves the button to be filled later.
static func choice(parent: Node, node_name: String, choices: Array = []) -> SaChoiceButton:
    var made := SaChoiceButton.new()
    if not choices.is_empty():
        made.set_choices(choices)
    return _placed(parent, node_name, made, Kind.CHOICE) as SaChoiceButton


## A choice of a few ways as one thumb sliding between a stop per choice, each
## choice's label over its stop. *choices* is the shape `choice` takes, and an
## entry may carry a `tooltip` as well.
static func stops(parent: Node, node_name: String, choices: Array) -> SaStopSlider:
    return _placed(parent, node_name, SaStopSlider.new(choices), Kind.STOPS) as SaStopSlider


static func row(parent: Node, node_name: String, gap: int = THEMED) -> HBoxContainer:
    var made := HBoxContainer.new()
    _gap(made, "separation", gap)
    return _placed(parent, node_name, made, Kind.ROW) as HBoxContainer


## A row that stands its children one over the other when their words do not
## fit side by side, `SaTurningRow`. *measure* reads a child that is not a
## button, as that class says.
static func turning_row(parent: Node, node_name: String, gap: int = THEMED, measure: Callable = Callable()) -> SaTurningRow:
    var made := SaTurningRow.new(measure)
    _gap(made, "separation", gap)
    return _placed(parent, node_name, made, Kind.ROW) as SaTurningRow


static func column(parent: Node, node_name: String, gap: int = THEMED) -> VBoxContainer:
    var made := VBoxContainer.new()
    _gap(made, "separation", gap)
    return _placed(parent, node_name, made, Kind.COLUMN) as VBoxContainer


static func grid(parent: Node, node_name: String, columns: int, gap: int = THEMED) -> GridContainer:
    var made := GridContainer.new()
    made.columns = columns
    _gap(made, "h_separation", gap)
    _gap(made, "v_separation", gap)
    return _placed(parent, node_name, made, Kind.GRID) as GridContainer


## The same margin on all four sides, which is what every margin in the tree
## was when this was written.
static func margin(parent: Node, node_name: String, pad: int) -> MarginContainer:
    var made := MarginContainer.new()
    for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
        made.add_theme_constant_override(side, SaUI.px(pad))
    return _placed(parent, node_name, made, Kind.MARGIN) as MarginContainer


static func scroll(parent: Node, node_name: String) -> ScrollContainer:
    return _placed(parent, node_name, ScrollContainer.new(), Kind.SCROLL) as ScrollContainer


static func separator(parent: Node, node_name: String, vertical: bool = false) -> Separator:
    if vertical:
        return _placed(parent, node_name, VSeparator.new(), Kind.SEPARATOR) as Separator
    return _placed(parent, node_name, HSeparator.new(), Kind.SEPARATOR) as Separator


static func _gap(container: Control, constant: StringName, gap: int) -> void:
    if gap != THEMED:
        container.add_theme_constant_override(constant, SaUI.px(gap))


## Named before it is added, so the parent never holds a child under the
## engine's generated name, and a parent's `child_entered_tree` reads the name
## the control keeps. The kind is written here too, the one place every call
## passes through.
static func _placed(parent: Node, node_name: String, made: Control, kind: Kind) -> Control:
    made.name = node_name
    made.set_meta(KIND_META, kind)
    if parent != null:
        parent.add_child(made)
    return made
