## A filter's own chord closes its dialog as Escape does.
##
## **A filter's chord is a toggle.** While a filter's dialog is on screen,
## that filter's chord emits the window's `close_requested`, the signal
## Escape and the × emit, which the dialog answers with Cancel: the
## preview goes and the layer is as it was. With the dialog shut the next
## press is the command's again and opens it, which makes the chord a toggle.
## Another filter's chord is not this one's and does what it always does.
##
## The chord is the InputMap action of the filter's command, which is where a
## rebind is written, so a painter who rebinds the filter toggles it on the
## new chord. The router asks from two places: a dialog's own window, where
## it declines every other chord but the window's own, and `_answer`, before
## the commands, which is the canvas, a docker and a pop-up. A number field
## holding the focus keeps nothing, because the router takes the press before
## the field hears it.
##
## Beside the router rather than in it, because the router is near a thousand
## lines.
class_name SaFilterChord
extends RefCounted


## Closes the filter dialog on screen whose filter *event* is the chord of, and
## answers that filter's command, or `&""` when *event* closes nothing. A
## press only, never its repeat. *asker* is the node whose tree is looked in.
static func close_its_dialog(asker: Node, event: InputEvent) -> StringName:
    if asker == null or not asker.is_inside_tree():
        return &""
    for node: Node in asker.get_tree().get_nodes_in_group(SaDialogWindow.OPEN_GROUP):
        var window := node as SaFilterDialogWindow
        if window == null or not window.visible or window.filter == null:
            continue
        var action := SaFilterRegistry.command_for(window._key, window.filter)
        if SaShortcutKeys.pressed(event, [action], false, true):
            window.close_requested.emit()
            return action
    return &""
