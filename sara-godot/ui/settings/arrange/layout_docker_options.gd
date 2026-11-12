## The per-docker option rows of a layout page: the settings that belong to one
## docker and are not rows in its element list.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## An option here is a docker's own and is not a toggle on the list. An element
## row answers whether a part of the docker is drawn and where in the order it
## sits, and these answer how the docker lays itself out, which is a different
## question and cannot be asked with a switch.
##
## Beside `layout_page.gd` rather than in it, because building a row from a
## registered spec and driving it from a scenario are one job that the reorder
## has nothing to do with.
##
## **The rows are a part of the page of their own**, the Options section a
## docker's Options… button on Layouts and dockers opens, and the list is the
## other part. `below_rows()`, `describe_rows` and `layout_gesture` read them
## through [method rows_box], the section's own container, so none of the three
## is taught about a second section.
class_name SaLayoutDockerOptions
extends RefCounted

## Which docker's page this belongs to.
var _category: String

## Option key -> the declared row drawn for it, so the capture door reaches one
## without walking the section.
var _rows: Dictionary = {}


func _init(category: String) -> void:
    _category = category


## One declared row per option the docker registered, in registration order.
## This was `build(rows)`, which drew each control by hand, wrote the setting
## from three handlers and dimmed an inert row itself.
##
## The Maximize button switch was registered here on every docker's page until
## it became one switch for every docker, on Layouts and dockers beside the hide
## button. A docker with no options of its own draws no row.
##
## **One binding for the page.** A docker option is a call and not a property,
## so the rows bind to an `SaPageBinding` whose two callables hold the category
## as a local string and name no member of this object: the page holds this
## object, this object holds its rows and a row holds the binding, and a
## callable that reached back here would close that into a ring.
func declare(section: SaPageSection) -> void:
    var category := _category
    var binding := SaPageBinding.new(
        func(key: StringName) -> Variant: return SaSettings.get_docker_option(category, String(key)),
        func(key: StringName, value: Variant) -> void: SaSettings.set_docker_option(category, String(key), value)
    )
    _rows.clear()
    var specs := SaSettings.docker_options(_category)
    for spec: Dictionary in specs:
        var key := String(spec.get("key", ""))
        var row := _row_for(section, key, spec, binding)
        if row == null:
            continue
        row.named(StringName(key)).node("Option_%s" % key).explain(tr(String(spec.get("hint", ""))))
        _rows[key] = row
    for spec: Dictionary in specs:
        _declare_rule(spec)


## The container the rows were drawn into, once the page is realized, or null
## for a docker with no options of its own. The layout page reads its rows back
## from it, the way it reads the rows under its list.
func rows_box() -> Container:
    for row: SaPageRow in _rows.values():
        if row.line != null and is_instance_valid(row.line):
            return row.line.get_parent() as Container
    return null


## `disabled_when` is a pair of an option key and the value that leaves this one
## meaning nothing. The toolbox's line cap is the case it was written for: a
## toolbox that follows its own rectangle has no cap to obey. Dimmed **and**
## disabled, because a dimmed control that still takes input reads as broken.
##
## It becomes a `dims` on the row that decides, and a rule is a list of the
## values the governed row is live under, so the pair is turned round: every
## value the deciding row can hold but the named one.
func _declare_rule(spec: Dictionary) -> void:
    var rule: Dictionary = spec.get("disabled_when", {})
    var governed := _rows.get(String(spec.get("key", "")), null) as SaPageRow
    var decides := _rows.get(String(rule.get("key", "")), null) as SaPageRow
    if governed == null or decides == null:
        return
    var inert: Variant = rule.get("value")
    var live: Array = []
    match decides.kind:
        SaPageRow.Kind.CHOICE:
            for choice: Dictionary in decides.choices:
                if choice.get("id") != inert:
                    live.append(choice.get("id"))
        SaPageRow.Kind.TOGGLE:
            live.append(not bool(inert))
        SaPageRow.Kind.NUMBER:
            for count in range(int(decides.min_value), int(decides.max_value) + 1):
                if count != int(inert):
                    live.append(count)
    decides.dims(governed, live)


## `{"option": "orientation", "value": "horizontal"}`: sets one option through
## the control a painter would use, and reports what the row now reads.
##
## Through the control rather than through `SaSettings`, because the claim a
## scenario is making is that the page offers the option, and writing the setting
## behind the page would pass on a page that draws no row at all. A press on the
## button would not do either: it opens a list that a scenario cannot then drive
## by coordinate, so the row inside the list is pressed by its own value.
func drive(key: String, value: Variant) -> String:
    var row := _rows.get(key, null) as SaPageRow
    var control: Control = row.control if row != null else null
    if control == null or not is_instance_valid(control):
        return "SaCapture: layout_gesture found no option called '%s' on '%s'" % [key, _category]
    if not SaOptionSpec.row_reads_enabled(row.line):
        return "SaCapture: layout_gesture cannot set '%s', its row is dimmed and disabled" % key
    var picker := control as SaChoiceButton
    if picker != null:
        if not picker.popup.press_row(SaChoiceButton.row_id_of(value)):
            return "SaCapture: layout_gesture has no value '%s' for '%s'" % [value, key]
        return "SaCapture: layout_gesture set '%s' to '%s'" % [key, value]
    var counter := control as SpinBox
    if counter != null:
        counter.value = float(value)
        return "SaCapture: layout_gesture set '%s' to %d" % [key, int(counter.value)]
    # A switch is set rather than pressed, and told to emit, for the reason the
    # picker above is: a press answers whatever the control is showing, so a
    # scenario asking for "on" twice would end with it off.
    var switch := control as CheckButton
    if switch != null:
        switch.button_pressed = bool(value)
        switch.toggled.emit(switch.button_pressed)
        return "SaCapture: layout_gesture set '%s' to %s" % [key, "on" if switch.button_pressed else "off"]
    return "SaCapture: layout_gesture cannot drive the '%s' row, it is a %s" % [key, control.get_class()]


## The row one option spec asks for, or null for a kind this file has never heard of,
## which is a docker to fix rather than a run to lose.
func _row_for(section: SaPageSection, key: String, spec: Dictionary, binding: SaPageBinding) -> SaPageRow:
    var title := tr(String(spec.get("title", key)))
    var kind := StringName(spec.get("kind", ""))
    if kind == SaSettingsLayout.OPTION_CHOICE:
        # Each entry carries the value the option stores, so what the row writes
        # is that value and nothing looks an index up in a list.
        var values: Array = spec.get("values", [])
        var labels: Array = spec.get("labels", values)
        var choices: Array = []
        for i in range(values.size()):
            choices.append({"id": values[i], "label": tr(String(labels[i]))})
        return section.choice(title, choices, binding, NodePath(key))
    if kind == SaSettingsLayout.OPTION_SWITCH:
        return section.toggle(title, binding, NodePath(key))
    if kind == SaSettingsLayout.OPTION_COUNT:
        return section.number(title, float(spec.get("min", 1)), float(spec.get("max", 8)), binding, NodePath(key))
    return null
