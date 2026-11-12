## One declared row of a page: its kind, its label, its binding and its rules.
##
## The row is the declaration and not the control. `build(ui)` appends these and
## instantiates nothing, `SaPage` walks them once and makes one control
## each, and after that only values move, and nothing reruns `build`: a control
## built once keeps its focus, its drag, its
## scroll position and its open tooltip, and a page rebuilt on a slider drag
## keeps none of them.
##
## A binding is an object and a property path on it, never a setter lambda, and
## the path reaches into a nested resource with a colon the way
## `SaOptionSpec.property` already does. A row with no target is bound to
## itself: it holds its own `value`, which is what a student's filter dialog
## reads back as `radius.value`.
class_name SaPageRow
extends RefCounted

## The closed set of row kinds, the declarative page table. There is no
## eleventh: `CUSTOM` is the escape hatch a page hands a control through, and it
## keeps the label column, the explanation and the dimming while losing only the
## binding.
##
## `COLOUR` rather than `COLOR` because the table writes `s.colour(...)`,
## and the row layer maps the scripting API's student-facing `color` onto it.
enum Kind { TOGGLE, SLIDER, NUMBER, CHOICE, TEXT, COLOUR, PATH, ACTION, NOTE, CUSTOM }

## The kind names a dump prints, in the enum's order.
const KIND_NAMES: Array[String] = ["toggle", "slider", "number", "choice", "text", "colour", "path", "action", "note", "custom"]

## Emitted after the row's value has been written, by a control the hand moved
## and by a rebuild alike. The page listens to every one of these to re-evaluate
## the rules that name this row.
signal changed(value: Variant)

## The row's identity, so `.dims` and `.hides` can name a row declared earlier
## and a dump can be read against a scenario. `SaPage` fills it in from the
## label when the declaration does not.
var key: StringName = &""

var label: String = ""
var kind: Kind = Kind.TOGGLE

## The dimmed sentence under the title.
var explanation: String = ""

## What the row writes to. Null means the row is bound to itself and holds
## its own `value`.
var target: Object = null

## Where on *target* the value lives, a path so a nested resource is reachable.
var property: NodePath = ^""

## What the row holds. For a row with no target this is the value itself, which
## is what a student reads back as `radius.value`, and for a bound row it is the
## last value read from the binding, so the two spellings answer the same thing.
var value: Variant = null

var min_value: float = 0.0
var max_value: float = 1.0
var step_value: float = 0.01

## Multiplies the stored value for display only, the way `SaOptionSpec` carries
## the Timelapse cap's megabytes. One number, and the builder owns both
## directions, because the pair of conversions written by hand was written twice
## with nothing checking they were inverses.
var display_scale: float = 1.0

## How many decimals the number is shown with, or -1, the default, for as many
## as the step has. A fixed two read Light direction as 315.00° and Relief
## strength as 4.00, so a row that never called `decimals` follows its step,
## the rule `SaPage` sizes a number field by.
var decimal_places: int = -1

## Written after the number with no space put in, so a unit that wants one
## carries it, " ms", and a degree sign does not, "°".
var suffix: String = ""

## For `CHOICE`: entries of `{"id": Variant, "label": String}`, the shape
## `SaOptionSpec.choices` already uses.
var choices: Array = []

## For `ACTION`: what the button calls.
var action: Callable = Callable()

## For `CUSTOM`: the control the page handed over.
var custom_control: Control = null

## The rows this one decides, as `{"key": StringName, "values": Array}`. A
## condition is a value or a list of values and never a `Callable`, for two
## reasons: a dump can print a value, and a page a module declares
## would otherwise run a module's code inside the skeleton's builder.
var dim_rules: Array[Dictionary] = []
var hide_rules: Array[Dictionary] = []

## The node name of the control the builder makes, empty for the name Godot
## gives it. Suites and capture steps find a control by name, and a number Godot
## hands out is not one.
var node_name: String = ""

## For `ACTION`: the words on the button when the row carries a title of its
## own. Empty means the label is on the button and the label column stays empty.
var button_text: String = ""

## For `TEXT` and `PATH`: the value is shown as a real path and stored as typed,
## so a `user://` setting reads as the folder it is.
var shows_global_path: bool = false

## Words the search finds the row by beside the ones it draws, for a custom row
## whose control says nothing a label walk can read.
var search_words: String = ""

## What the builder made, filled in by `SaPage.realize` and null before it runs.
var control: Control = null
## The whole labelled line, which is what dims and what hides.
var line: Control = null


## The dimmed sentence under the title. A method rather than a positional
## argument because a slider with a range and a binding already takes five.
func explain(text: String) -> SaPageRow:
    explanation = text
    return self


## Names the row, for a `.dims` written before it or a scenario reading a dump.
func named(row_key: StringName) -> SaPageRow:
    key = row_key
    return self


## Names the control the builder makes, the `HSlider` of a slider row and the
## `Label` of a note. `named` is the row's key, which a rule and a dump read, and
## this is the node's, which a suite and a capture step read.
func node(control_name: String) -> SaPageRow:
    node_name = control_name
    return self


## On an action row: *text* goes on the button and the label becomes the row's
## title, "Reset all preferences" over "Reset". Without it the button carries
## the label and the row has no title, which also keeps it out of the search.
func button(text: String) -> SaPageRow:
    button_text = text
    return self


## On a text or a path row: shown through `ProjectSettings.globalize_path` and
## stored as typed, the display conversion the Timelapse folder needs.
func globalized() -> SaPageRow:
    shows_global_path = true
    return self


## Extra words the search finds the row by.
func words(text: String) -> SaPageRow:
    search_words = text
    return self


## *other* is live only while this row's value is one of *when*, and dimmed and
## disabled otherwise. Reads left to right as the sentence it is: the roll-off
## toggle dims the Knee slider.
##
## *other* is an `SaPageRow` or the key of one, so a row declared earlier can be
## named. Kept as handed over rather than resolved to a key here: a page gives
## every row its key only once the whole declaration is in hand, so a row named
## by reference resolves through [method resolved_key] when the rule is read,
## never at the point it is written. *when* is a value or an array of values,
## defaulting to `true` because the row that decides is a toggle in every case
## in the tree today.
func dims(other: Variant, when: Variant = true) -> SaPageRow:
    dim_rules.append({"key": other, "values": _values_of(when)})
    return self


## *other* is on the page only while this row's value is one of *when*.
##
## `dims` leaves a row on screen and dead, which the Display page's roll-off
## sliders want because an operator that is not running is worth describing.
## This takes the row off, which the brush editor's Tip page wants because a
## Mask row beside a generated tip is about something that is not on screen.
func hides(other: Variant, when: Variant = true) -> SaPageRow:
    hide_rules.append({"key": other, "values": _values_of(when)})
    return self


func step(increment: float) -> SaPageRow:
    step_value = increment
    return self


## The display multiplier, one number for both directions.
func scale(factor: float) -> SaPageRow:
    # Exact zero, never `is_zero_approx`: the Timelapse cap's 1/1048576 is a
    # legitimate factor under Godot's 1e-5 epsilon, and that guard silently
    # dropped it back to 1.0, so the page read out a value in bytes.
    display_scale = factor if factor != 0.0 else 1.0
    return self


func decimals(places: int) -> SaPageRow:
    decimal_places = maxi(places, 0)
    return self


## The decimals the number is shown with: the ones the row asked for, or as
## many as its step has.
func shown_places() -> int:
    return decimal_places if decimal_places >= 0 else step_places(step_value)


## As many decimals as *increment* has, none for a whole one: 315 for a step of
## 15, 4.25 for a quarter.
static func step_places(increment: float) -> int:
    if increment <= 0.0 or is_equal_approx(increment, roundf(increment)):
        return 0
    return maxi(0, str(increment).get_slice(".", 1).length())


func with_suffix(text: String) -> SaPageRow:
    suffix = text
    return self


## A new title and explanation, in the row's fields and on the line it drew,
## so a dump and the search read the words on screen.
func retitle(title: String, text: String) -> void:
    label = title
    explanation = text
    if line != null and is_instance_valid(line):
        SaSettingsRows.retitle(line, SaPage.translated(title), SaPage.translated(text))


## The path the row reads and writes, the key itself when none was declared.
func property_path() -> NodePath:
    return property if not property.is_empty() else NodePath(String(key))


## The stored value, from the binding or from the row itself.
func read() -> Variant:
    if target != null and is_instance_valid(target):
        value = target.get_indexed(property_path())
    return value


## Writes the stored value and says so. A row with no target keeps it.
##
## A number arrives from a control as a float, whatever the property holds, so a
## target whose property is an `int` is written a rounded one: assigning 48.0 to
## a typed `int` is refused at runtime and the row would have gone on reading
## what it had. This is the same conversion `SaOptionSpec`'s surfaces do by hand
## and the reason the Timelapse cap is `int(val) * 1048576` in the page today.
func write(new_value: Variant) -> void:
    if target != null and is_instance_valid(target) and typeof(new_value) == TYPE_FLOAT:
        if typeof(target.get_indexed(property_path())) == TYPE_INT:
            new_value = roundi(new_value)
    value = new_value
    if target != null and is_instance_valid(target):
        target.set_indexed(property_path(), new_value)
    changed.emit(new_value)


## Moves this row's control as a hand would, so the write goes through the same
## signal a painter's click sends.
##
## Every kind is driven by setting the control and emitting its own signal,
## because half of them do not emit for a script: `OptionButton.select` never
## does, and a `Range` assigned to by a script emits a frame later or not at
## all. A scenario step and a suite both
## want the write to have happened by the time the next line runs, so both
## come through here.
func drive(new_value: Variant) -> void:
    if control == null or not is_instance_valid(control):
        return
    match kind:
        Kind.TOGGLE:
            (control as CheckButton).button_pressed = bool(new_value)
        Kind.SLIDER, Kind.NUMBER:
            # *new_value* is what the slider itself would show, a hand's own
            # units, not the stored one `shown_value` expects: asking a scaled
            # row for 2048 wrote 1, because it scaled the shown number down a
            # second time.
            var slider := control as Range
            slider.set_value_no_signal(float(new_value))
            slider.value_changed.emit(slider.value)
        Kind.CHOICE:
            # By the row's index, which is what a scenario and this method's own
            # callers write, and the button answers with the id behind that row.
            # `pick_row` is the press a hand would make, so the signal the page
            # listens for is the one that fires.
            (control as SaChoiceButton).pick_row(int(new_value))
        Kind.TEXT:
            var edit := control as LineEdit
            edit.text = String(new_value)
            edit.text_submitted.emit(edit.text)
        Kind.COLOUR:
            var picker := control as ColorPickerButton
            picker.color = Color(String(new_value))
            picker.color_changed.emit(picker.color)
        Kind.ACTION:
            (control as Button).pressed.emit()
        _:
            write(new_value)


## What this row's control currently shows, which is not always what `read()`
## holds: the two agree once a write has landed and differ while a page is
## being driven behind its own back.
func reads() -> Variant:
    if control == null or not is_instance_valid(control):
        return null
    if control is CheckButton:
        return (control as CheckButton).button_pressed
    if control is Range:
        return (control as Range).value
    if control is SaChoiceButton:
        return (control as SaChoiceButton).selected_value()
    if control is LineEdit:
        return (control as LineEdit).text
    if control is ColorPickerButton:
        return "#" + (control as ColorPickerButton).color.to_html(true)
    return null


## What the row shows for a stored number, the display scale applied.
func shown_value(stored: float) -> float:
    return stored * display_scale


## What the row shows for a stored string, a real path when the row asked.
func shown_text(stored: Variant) -> String:
    var text := String(stored if stored != null else "")
    return ProjectSettings.globalize_path(text) if shows_global_path and not text.is_empty() else text


## What a shown number is stored as, the same one number read backwards.
func stored_value(shown: float) -> float:
    return shown / display_scale


## The row as a dump prints it: what it is, what it holds and what it decides.
##
## `live` and `shown` come from the built control rather than from the rules, so
## a dump says what a painter can see rather than what the declaration intended,
## which is the difference the Display page's roll-off rows got wrong once.
func describe() -> Dictionary:
    var out := {
        "key": String(key),
        "label": label,
        "kind": KIND_NAMES[kind],
        "explain": explanation,
        "value": _describable(read()),
        "bound_to": bound_to(),
        "live": SaOptionSpec.row_reads_enabled(line) if line != null else true,
        "shown": line == null or line.visible,
    }
    if not node_name.is_empty():
        out["node"] = node_name
    if not button_text.is_empty():
        out["button"] = button_text
    if shows_global_path:
        out["globalized"] = true
    if not search_words.is_empty():
        out["words"] = search_words
    if not choices.is_empty():
        out["choices"] = choices
    if not dim_rules.is_empty():
        out["dims"] = _rules_described(dim_rules)
    if not hide_rules.is_empty():
        out["hides"] = _rules_described(hide_rules)
    var holds: SaValueControl = control as SaValueControl if is_instance_valid(control) else null
    if holds != null:
        out["control"] = holds.describe()
    return out


## The target and path a row writes, "itself" for a row that holds its own
## value. A name rather than the object, because a dump is read by a person.
func bound_to() -> String:
    if target == null or not is_instance_valid(target):
        return "itself"
    var name := target.get_class()
    var script := target.get_script() as Script
    if script != null and not script.resource_path.is_empty():
        name = script.resource_path.get_file().get_basename()
    return "%s.%s" % [name, String(property_path())]


## The key a `dims()` or `hides()` rule was declared against, resolved now
## rather than when it was written: *stored* is what `dim_rules` and
## `hide_rules` hold under `"key"`, a plain key or the row itself, and a row
## answers whatever `SaPage.declare_rows` or `SaPage.realize` has since given
## it. Public because `SaPage.apply_rules` reads a rule too.
static func resolved_key(stored: Variant) -> StringName:
    return (stored as SaPageRow).key if stored is SaPageRow else StringName(String(stored))


static func _values_of(when: Variant) -> Array:
    return (when as Array).duplicate() if when is Array else [when]


func _rules_described(rules: Array[Dictionary]) -> Array:
    var out: Array = []
    for rule in rules:
        var when: Array = []
        for listed: Variant in rule["values"] as Array:
            when.append(_describable(listed))
        out.append({"row": String(resolved_key(rule["key"])), "when": when})
    return out


## JSON holds no Color and no NodePath, and a dump that stringifies half a page
## is a dump a scenario cannot compare. Numbers, strings and booleans pass
## through, everything else becomes its own text.
static func _describable(held: Variant) -> Variant:
    match typeof(held):
        TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
            return held
        TYPE_COLOR:
            return "#" + (held as Color).to_html(true)
    return str(held)
