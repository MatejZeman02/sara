## The one place a search field gets Alt+F, which empties it as it does in Blender.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A field that filters a list is made a search field by [method mark], which
## every such field in the interface calls once. The clear goes through
## `LineEdit.clear`, which announces `text_changed` as a typed edit does, so the
## list the field filters shows everything again by the listener it already
## has and no field needs a clear of its own.
##
## **The field wins over the menus.** The key is taken in the field's own
## `gui_input`, ahead of the window's shortcut pass, and marked handled, so an
## Alt+letter accelerator never also opens a menu. [method keeps] tells the
## shortcut router the same, for a docker's or a pop-up's window, which asks the
## router before the field has the key.
class_name SaSearchField
extends RefCounted

## The meta a search field carries.
const META: StringName = &"sa_search_field"


## Makes *field* a search field and answers it, so a builder can chain the call.
static func mark(field: LineEdit) -> LineEdit:
    if field == null or field.has_meta(META):
        return field
    field.set_meta(META, true)
    field.gui_input.connect(_on_gui_input.bind(field))
    return field


## Whether *event* is Alt+F pressed while *focus_owner* is a search field, the
## key the field takes for itself.
static func keeps(focus_owner: Object, event: InputEvent) -> bool:
    var field := focus_owner as LineEdit
    if field == null or not field.has_meta(META):
        return false
    var key := event as InputEventKey
    if key == null or key.keycode != KEY_F:
        return false
    return key.alt_pressed and not (key.ctrl_pressed or key.shift_pressed or key.meta_pressed)


static func _on_gui_input(event: InputEvent, field: LineEdit) -> void:
    if not keeps(field, event):
        return
    if (event as InputEventKey).pressed and not field.text.is_empty():
        field.clear()
    field.accept_event()
