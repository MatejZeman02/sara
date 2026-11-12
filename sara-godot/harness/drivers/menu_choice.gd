## The `choice` scenario step: opens, hovers and picks in an `SaChoiceButton`'s
## list.
##
## Every dropdown in Sara is an `SaChoiceButton` holding a list of its own, so
## there is no engine popup for this file to follow.
##
## **Why a class of its own.** `capture_choice` below is the `choice` step,
## which reads a list on screen whoever opened it, and it belongs to no control:
## the button that was named may be anywhere and the list is found by being the
## one that is visible. It reads nothing of the run, so it is a static on a
## `RefCounted` rather than a member of anything.
class_name SaMenuChoice
extends RefCounted

## The name a choice list carries under its button, so a capture and a test find
## it without a search. `SaChoiceButton` gives its own list this name.
const CHOICE_POPUP_NAME: StringName = &"ChoiceList"


## Drives a dropdown's rows: it opens the list with `{"choice": {"open":
## "PickerType"}}`, parks the pointer on row 2 of whichever list is open with
## `{"choice": {"hover": 2}}`, and presses that row with `{"choice": {"pick":
## 2}}`.
##
## The named control is an `SaChoiceButton`, everywhere, because no
## `OptionButton` is left in the tree.
##
## The list is a `Window` of its own and an injected click does not route into
## one, which is why the press is made here rather than in the scenario. The
## hover is a real injected motion, because a mark drawn by hover and a mark
## that is the choice are two different things, and only a pointer actually
## resting somewhere can tell them apart.
static func capture_choice(tree: SceneTree, spec: Dictionary) -> String:
    if spec.has("open"):
        var wanted := String(spec["open"])
        var named := tree.root.find_child(wanted, true, false)
        # The control that replaced the engine's dropdown. It holds its own
        # list, so the step opens that list and reports it in the same words a
        # scenario written against `ModeButton` has always read.
        var choice := named as SaChoiceButton
        if choice == null:
            return "SaCapture: no dropdown called '%s'" % wanted
        choice.toggle_list()
        var list := choice.popup
        # `announced` is how many picks the button has
        # let through since it was built, because a press that changes nothing
        # looks the same on screen as one that does and only the signal differs.
        return (
            "SaCapture: %s opened %d rows, marked %s, announced %d"
            % [wanted, list.row_ids().size(), list.current, choice._announced]
        )

    var popup := _open_choice_list(tree)
    if popup == null:
        return "SaCapture: no choice list is open"
    var rows := popup.row_ids()
    var at := int(spec.get("hover", spec.get("pick", -1)))
    if at < 0 or at >= rows.size():
        return "SaCapture: no row %d in a list of %d" % [at, rows.size()]
    var button := popup.label_button(rows[at])
    if spec.has("pick"):
        popup.press_row(rows[at])
        return "SaCapture: picked row %d, %s" % [at, button.text]

    # The row's centre in the list window's own coordinates is not a point on
    # the root, and sent there it rests on whatever the root has at that spot,
    # such as the Brush Presets search field. The screen transform carries
    # it out of the list, the way the Reference capture aims at a tab.
    var centre := button.get_screen_transform() * (button.size / 2.0) - Vector2(tree.root.position)
    var motion := InputEventMouseMotion.new()
    motion.position = centre
    motion.global_position = centre
    Input.parse_input_event(motion)
    Input.flush_buffered_events()
    return "SaCapture: pointer on row %d, '%s', while the marked row is '%s'" % [at, button.text, String(popup.current)]


## The choice list on screen, or null. A list is opened by a press and a press
## elsewhere closes the one that was up, so two are open only when a child list
## stands beside the menu it hangs from, and the child is the one a pick means.
## It is the menu's own child, so the walk meets it after the menu.
static func _open_choice_list(tree: SceneTree) -> SaChoicePopup:
    var found: SaChoicePopup = null
    for node in tree.root.find_children("*", "SaChoicePopup", true, false):
        var popup := node as SaChoicePopup
        if popup != null and popup.visible:
            found = popup
    return found
