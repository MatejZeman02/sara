## A named group of rows on a declared page, and the only nesting there is.
##
## A bold heading over a rule with its rows under it, which is what
## `SaSettingsRows.section` draws today. There are no sections inside sections,
## because none of the 3758 hand-written lines under `ui/settings/` has one and
## a layer that permits what nothing uses is a layer with an untested branch in
## it.
##
## Every kind takes a label first, its own shape next and the binding last, so
## the ten methods here read down the page as one sentence each. Each answers
## the row it appended, which is what `.explain`, `.dims` and `.hides` chain
## onto and what a page keeps when it wants to read a widget back.
##
## **Holds no page**, rather than calling back into the page that made it to
## key each row as it is appended, which would be a reference cycle held only
## weakly. A page gives every row its key in one pass, once [method
## SaPage.declare_rows] or [method SaPage.realize] has the whole declaration in
## hand, so a section is free to hold nothing back.
class_name SaPageSection
extends RefCounted

var title: String = ""
var rows: Array[SaPageRow] = []


func _init(section_title: String = "") -> void:
    title = section_title


## A `CheckButton`, the row a toggle is.
func toggle(label: String, target: Object = null, property: NodePath = ^"") -> SaPageRow:
    return _add(SaPageRow.Kind.TOGGLE, label, target, property)


## An `HSlider` with the value read out beside it, so the number is never
## carried in the title.
func slider(label: String, minimum: float, maximum: float, target: Object = null, property: NodePath = ^"") -> SaPageRow:
    var row := _add(SaPageRow.Kind.SLIDER, label, target, property)
    row.min_value = minimum
    row.max_value = maximum
    return row


## A `SpinBox`, for a number typed rather than dragged.
func number(label: String, minimum: float, maximum: float, target: Object = null, property: NodePath = ^"") -> SaPageRow:
    var row := _add(SaPageRow.Kind.NUMBER, label, target, property)
    row.min_value = minimum
    row.max_value = maximum
    row.step_value = 1.0
    return row


## An `SaChoiceButton` over a fixed list, rather than the engine's
## `OptionButton`.
##
## *entries* are `{"id": Variant, "label": String}` or bare labels, whose id is
## then their index. A choice list a registry owns is a call and never a
## literal, so a module that registers a view transform appears in the row.
func choice(label: String, entries: Array, target: Object = null, property: NodePath = ^"") -> SaPageRow:
    var row := _add(SaPageRow.Kind.CHOICE, label, target, property)
    row.choices = SaPageSection.normalize_choices(entries)
    return row


## A `LineEdit`, committed on submit and on focus loss. Both, because the one
## bound text row in the tree wires both by hand and the pattern is written
## down nowhere.
func text(label: String, target: Object = null, property: NodePath = ^"") -> SaPageRow:
    return _add(SaPageRow.Kind.TEXT, label, target, property)


## The colour button. British here to match the row table, and
## the row layer adds the scripting API's `color` beside it for a student.
func colour(label: String, target: Object = null, property: NodePath = ^"") -> SaPageRow:
    return _add(SaPageRow.Kind.COLOUR, label, target, property)


## A path label over a Choose and a Use Default button, the settings folder's row.
func path(label: String, target: Object = null, property: NodePath = ^"") -> SaPageRow:
    return _add(SaPageRow.Kind.PATH, label, target, property)


## A `Button`, the one kind that carries no value at all.
func action(label: String, pressed: Callable) -> SaPageRow:
    var row := _add(SaPageRow.Kind.ACTION, label)
    row.action = pressed
    return row


## A dimmed paragraph across the row, for text belonging to no one control.
func note(body: String) -> SaPageRow:
    var row := _add(SaPageRow.Kind.NOTE, "")
    row.explanation = body
    return row


## Whatever the page hands over: the Colour Spaces page's gamut solid, the
## Tablet page's pressure readout. The row keeps its label column, its
## explanation and its dimming, and loses only the binding, which is what it
## wanted.
func custom(label: String, control: Control) -> SaPageRow:
    var row := _add(SaPageRow.Kind.CUSTOM, label)
    row.custom_control = control
    return row


## Entries as the builder wants them, from ids and labels or from bare labels,
## with an entry's tooltip kept where it carries one.
static func normalize_choices(entries: Array) -> Array:
    var out: Array = []
    for index in entries.size():
        var entry: Variant = entries[index]
        if entry is Dictionary:
            var made := {"id": (entry as Dictionary).get("id", index), "label": String((entry as Dictionary).get("label", ""))}
            if (entry as Dictionary).has("tooltip"):
                made["tooltip"] = String((entry as Dictionary)["tooltip"])
            out.append(made)
        else:
            out.append({"id": index, "label": String(entry)})
    return out


func _add(kind: SaPageRow.Kind, label: String, target: Object = null, property: NodePath = ^"") -> SaPageRow:
    var row := SaPageRow.new()
    row.kind = kind
    row.label = label
    row.target = target
    row.property = property
    rows.append(row)
    return row
