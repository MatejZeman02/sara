## A choice as a button and a list of rows.
##
## What an `OptionButton` is for, over `SaChoicePopup` instead of over the
## engine's `PopupMenu`. The button reads the chosen label and opens the list,
## the list marks the chosen row, and a press writes the caller's own value back
## rather than an index into a list the caller does not hold.
##
## **Why not the engine's dropdown.** Its list is a `PopupMenu`, so an item
## has no rect: the note mode cannot point at one, an icon is drawn at the
## texture's own size, and the only per-row mark is `hover`, which follows the
## pointer exactly while a painter is choosing. `SaChoicePopup` answers every
## one of those, and this is the control that carries it to every dropdown.
##
## **The value, not the index.** `OptionButton` answered `item_selected(index)`
## and every caller then asked for `get_item_metadata(index)` to get back the
## thing it had put in. A row here is keyed on the value it stands for, so
## `choice_picked` carries that value and nothing counts rows.
##
## `BlendModeButton` is the same shape and is deliberately not built on this: its
## rows carry a favourites box each, its list has sections and its labels follow
## the document's colour space, so a common base would be this file plus four
## hooks nothing else uses. What the two do share is the button under the rows,
## `SaDropdownButton`.
class_name SaChoiceButton
extends SaDropdownButton

## The choice moved. The caller's own value for the new row, never an index.
##
## Only when it moved: pressing the row that is already marked writes nothing
## and says nothing, which is what an `OptionButton` does and what
## a caller reading the signal reasonably assumes. A capture that wants the
## write to happen anyway emits this by hand, the way
## `SaCaptureLayers._drive_bar_control` does.
signal choice_picked(value: Variant)

## The narrowest the button goes, in logical pixels, when a caller names none.
const MIN_WIDTH: int = 54

## The values behind the rows, in the order they were added, so a row id maps
## back to what the caller put in.
var _values: Array = []
var _labels: Array[String] = []
## What the button is showing. Held rather than read off `text`, because two
## choices may carry the same label and the value is what a caller wrote.
var _current: Variant = null
var _has_current: bool = false
## How many picks this button has announced since it was built, which is the one
## thing about the repeat guard the running app can be asked. The press, the mark
## and the list closing are the same whether or not the value moved, so a capture
## that only looks at the screen cannot tell the guard from no guard, and a unit
## test alone cannot show the guard at work in the running app. Read by the `choice` step,
## and written here alone.
var _announced: int = 0


func _init() -> void:
    super(SaChoicePopup.new(), "ChoiceList")
    # Exactly one row is the answer, so the mark is the engine's pressed
    # stylebox on a toggle in one group, which is the mark that survives the
    # pointer moving over the list.
    popup.one_of = true
    popup.chosen.connect(_on_row_chosen)


## Fills the list from *choices*, `[{"id": Variant, "label": String}]`, which is
## the shape `SaOptionSpec` already declares an `ENUM`'s rows in. An optional
## `"icon"` per entry names a file under `res://assets/icons/`, and an optional
## `"disabled"` dims the row and takes its press away, and an optional
## `"tooltip"` is shown over the row, translated. An entry of `"section"`
## alone is a heading over the rows after it, which takes no press.
##
## The chosen value survives a refill when the new list still holds it, so a
## rebuild after a tool change does not silently move the painter's choice.
func set_choices(choices: Array) -> void:
    popup.clear()
    _values.clear()
    _labels.clear()
    for choice: Dictionary in choices:
        if choice.has("section"):
            popup.add_section(String(choice["section"]))
            continue
        var value: Variant = choice.get("id")
        var label := String(choice.get("label", ""))
        popup.add_row(
            row_id_of(value), label, false, false, String(choice.get("icon", "")), "", bool(choice.get("disabled", false))
        )
        if choice.has("tooltip"):
            popup.label_button(row_id_of(value)).tooltip_text = tr(String(choice["tooltip"]))
        _values.append(value)
        _labels.append(label)
    if not (_has_current and select_value(_current)) and not _values.is_empty():
        select_value(_values[0])


## Shows the row standing for *value* as the chosen one. False when no row does,
## which leaves the button on what it showed.
func select_value(value: Variant) -> bool:
    var index := _values.find(value)
    if index < 0:
        return false
    _current = value
    _has_current = true
    text = _labels[index]
    popup.set_current(row_id_of(value))
    return true


## What the button is showing, or null before anything has been chosen.
func selected_value() -> Variant:
    return _current if _has_current else null


## Shows *words* on the button, marks no row and holds no value.
##
## The state an `OptionButton` draws as `select(-1)`. Here rather than in a
## caller writing the list's mark and the button's text itself, which leaves the
## last value held behind the words, so a press on that row reads as no move and
## the guard in `_on_row_chosen` swallows it.
func clear_choice(words: String) -> void:
    _current = null
    _has_current = false
    text = words
    popup.set_current(&"")


## The values the list offers, in order, for a test and for the capture driver.
func choice_values() -> Array:
    return _values.duplicate()


## The words on the rows, in order, so a step can pick one by what it reads.
func choice_labels() -> Array[String]:
    return _labels.duplicate()


## Presses the row whose label is *label*, or whose index it is, the way a hand
## would: the value is written, and `choice_picked` fires when it moved. True
## says the row took the press, not that the choice changed. False when the list
## holds no such row, and the caller says so rather than this printing.
func pick_row(row: Variant) -> bool:
    var index := int(row) if (row is int or row is float) else _labels.find(String(row))
    if index < 0 or index >= _values.size():
        return false
    return popup.press_row(row_id_of(_values[index]))


## Which row stands for *value*. The string of the value rather than a slug of
## the label, so the id a dump prints is the thing the caller wrote and two rows
## reading the same words are still two rows.
static func row_id_of(value: Variant) -> StringName:
    return StringName(str(value))


## The next row from the chosen one in the list's own order, which is the order
## the values were added in, passing over a disabled row. With nothing chosen a
## step down lands on the first row and a step up on the last.
func _row_after(direction: int) -> StringName:
    var index := _values.find(_current) if _has_current else -1
    if index < 0:
        index = -1 if direction > 0 else _values.size()
    index += direction
    while index >= 0 and index < _values.size():
        var row := row_id_of(_values[index])
        if not popup.is_disabled(row):
            return row
        index += direction
    return &""


## A row took a press. The mark and the button's words follow it either way, and
## the signal only when the value is not the one already showing: the list runs
## this on the press rather than on the value moving, so without the guard a
## caller that rebuilds on every pick rebuilds once for nothing.
func _on_row_chosen(row_id: StringName) -> void:
    for index in _values.size():
        if row_id_of(_values[index]) != row_id:
            continue
        var moved: bool = not _has_current or _current != _values[index]
        if select_value(_values[index]) and moved:
            _announced += 1
            choice_picked.emit(_values[index])
        return


## Every choice list open under *root*, by path, for the state dump. A list is a
## `Window` of its own, so a screenshot of a closed one and of one hidden behind
## a docker are the same picture, and the one claim a scenario about Space wants
## to make is that no list came back.
static func open_lists(root: Node) -> Array[String]:
    var out: Array[String] = []
    for node in root.find_children("*", "SaChoicePopup", true, false):
        var list := node as Window
        if list != null and list.visible:
            out.append(String(list.get_path()))
    return out
