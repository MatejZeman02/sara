## What a `SaChoicePopup` says of its rows to a state dump.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Its own class since the kept rows went into the popup and took the file
## past a thousand lines. The cut is by responsibility: the popup owns the rows
## and what a press does, and this owns what a capture is told of them, read
## through the popup's public questions and nothing else.
class_name SaChoiceReport
extends RefCounted


## What each row is, for a state dump: the id, the label, whether it carries a
## box and whether that box is ticked, and which row is the chosen one. A
## screenshot of a list of names cannot say which of them is ticked at the width
## the docker has.
static func rows(list: SaChoicePopup) -> Array:
    var out: Array = []
    for id: StringName in list.row_ids():
        var button := list.label_button(id)
        (
            out
            . append(
                {
                    "id": String(id),
                    "label": button.text if button != null else "",
                    "checkable": list.check_box(id) != null,
                    "checked": list.is_checked(id),
                    "current": list.is_marked(id),
                    "hovered": _is_hovered(list, id),
                    # What a `PopupMenu` item could not be told, so a dump can say
                    # what a painter sees rather than only what was listed.
                    "icon": list.row_of(id).icon_name,
                    "hint": list.row_of(id).hint_text(),
                    # The second name the search finds the row by, a blend
                    # mode's English under another language, or "".
                    "other_name": list.row_of(id).other_name,
                    "disabled": list.is_disabled(id),
                    "highlighted": list.highlighted() == id,
                    # The underlined letter a key runs the row with, or "".
                    "letter": SaChoiceLetters.letter_of(list.row_of(id)),
                    # A search hides rows, and a dump of a filtered list that did
                    # not say which is a dump of the wrong list.
                    "shown": list.is_row_shown(id),
                }
            )
        )
    return out


## Whether the pointer is resting on *id*'s row, which is the one thing the whole
## list is about: the dump has to say which row is chosen **and** which row is
## under the pointer, or a capture cannot tell a mark that survived hover from a
## mark that is the hover.
static func _is_hovered(list: SaChoicePopup, id: StringName) -> bool:
    var button := list.label_button(id)
    if button == null or not button.is_inside_tree():
        return false
    return button.get_global_rect().has_point(button.get_global_mouse_position())
