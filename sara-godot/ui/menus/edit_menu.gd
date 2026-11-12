## The Edit menu: undo, redo, the clipboard, the fills, the quick commands and
## Preferences.
##
## A list of commands. Each row reads its words, its chord and its sentence
## from the command it runs, and a press runs that command, so the row and the
## key are one implementation. Undo and Redo keep the action `project.godot`
## binds and the router answers, and their commands carry none, so the chord
## beside them is read from that action rather than dispatched a second time.
##
## **The fills and the clear are here as well as on their keys.** A key a painter
## is not told about is a key they never find, and a row is where the chord is
## told. The clear is the Layer menu's Clear Layer, one command on two rows, and
## is drawn as Clear here, where every row acts on the selection.
##
## **Repeat Last, the command search and Quick Favourites** are Blender's
## habits, and sit where a Blender hand looks for them: Repeat Last under Redo,
## the other two over Preferences.
class_name SaEditMenu
extends SaMenu

const ID_PREFERENCES := 100
const ID_UNDO := 101
const ID_REDO := 102
const ID_CUT := 104
const ID_COPY := 105
const ID_PASTE := 106
const ID_COPY_MERGED := 107
const ID_FILL_FOREGROUND := 108
const ID_FILL_BACKGROUND := 109
const ID_CLEAR := 110
const ID_REPEAT_LAST := 111
const ID_SEARCH_COMMANDS := 112
const ID_QUICK_FAVOURITES := 113
const ID_PASTE_SPECIAL := 114


func _add_items() -> void:
    add_commands(
        [
            [ID_UNDO, &"edit_undo"],
            [ID_REDO, &"edit_redo"],
            [ID_REPEAT_LAST, SaQuickCommands.REPEAT],
            LINE,
            [ID_CUT, &"edit_cut"],
            [ID_COPY, &"edit_copy"],
            [ID_COPY_MERGED, &"edit_copy_merged"],
            [ID_PASTE, &"edit_paste"],
            [ID_PASTE_SPECIAL, &"edit_paste_special", "Paste Special..."],
            LINE,
            [ID_FILL_FOREGROUND, &"fill_foreground"],
            [ID_FILL_BACKGROUND, &"fill_background"],
            [ID_CLEAR, &"layer_clear", "Clear"],
            LINE,
            [ID_SEARCH_COMMANDS, SaQuickCommands.SEARCH],
            [ID_QUICK_FAVOURITES, SaQuickCommands.FAVOURITES],
            LINE,
            [ID_PREFERENCES, &"edit_preferences"],
        ]
    )
