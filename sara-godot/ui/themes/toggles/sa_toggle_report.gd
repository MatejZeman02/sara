## Which toggle buttons a state dump shows and what each says of itself.
##
## Moved out of `SaTheme` when the switch family took the lines that file's
## folder had left: the report is the question of whether a toggle went through
## the door `SaTheme.make_toggle` is, which is a toggle's business and not the
## palette's.
class_name SaToggleReport
extends RefCounted


## Every toggle button under *root*, for a state dump: its name, whether it is
## down, and whether it carries a pressed box of its own rather than the engine's
## default one.
##
## It asks whether the door `SaTheme.make_toggle` was walked through, which
## is why it sits with the toggle family and not in the state report.
##
## **Three families are left out, each named rather than guessed at.** A
## `CheckBox`, an `OptionButton` and a `MenuButton` are all `Button` subclasses
## the engine builds with `toggle_mode` on, and none of them is the control the
## note is about: a box says where it stands with a tick, and the two lists say
## so with the row they show. A dropdown has its own door in this file already.
## And a row of a list is not a toggle button either: `SaChoicePopup`'s rows are
## toggles in a `ButtonGroup` whose mark is the list's own business and whose
## file owns it, and `UndoDocker`'s rows are the same shape.
static func of(root: Window) -> Array:
    var out: Array = []
    if root == null:
        return out
    for node in root.find_children("*", "Button", true, false):
        var button := node as Button
        if button == null or not button.toggle_mode:
            continue
        if button is CheckBox or button is OptionButton or button is MenuButton:
            continue
        if _sits_in_a_list(button):
            continue
        (
            out
            . append(
                {
                    "name": String(button.name),
                    "path": String(root.get_path_to(button)),
                    "pressed": button.button_pressed,
                    "styled": button.has_theme_stylebox_override("pressed"),
                    "text": button.text,
                }
            )
        )
    return out


## Whether *button* is a row of a list rather than a toggle of its own.
static func _sits_in_a_list(button: Button) -> bool:
    var walk: Node = button
    while walk != null:
        if walk is SaChoicePopup or walk.name == SaDockerIds.UNDO:
            return true
        walk = walk.get_parent()
    return false
