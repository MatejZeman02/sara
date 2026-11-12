## The top bar's overflow: a button at the end of the row the tool options are
## on, and the list it opens with every tool option control that did not fit.
##
## An overflow rather than a taller second bar. A row's slot scrolls by the wheel and by a drag
## on empty space, and a pen has neither, so a control past the edge of a row
## is one a pen can only reach by the slot's arrows. In the list it is one tap
## on this button away.
##
## The controls are the tool options bar's own and keep their owner and their
## signals, the way a control that changes rows does. `SaTopBarRows` decides
## which ones come here and in what order, and this holds them, shows itself
## only while it holds one that is shown, and opens and closes the list.
##
## The list is an `SaFloatingPanel`, a control in the window and not a
## `PopupPanel`, so a pen reaches it and the recorder sees it.
class_name SaTopBarOverflow
extends Button

## The switch on the top bar list on Layouts and dockers, a per-docker option of the bar.
const OPTION := "overflow"

## Logical pixels between the three dots, and their radius.
const DOT_GAP: int = 5
const DOT_RADIUS: float = 1.6

## The list the button opens.
var list: SaFloatingPanel

## The column in the list the controls are put in, in profile order.
var box: VBoxContainer


func _init() -> void:
    name = "OverflowButton"
    flat = true
    focus_mode = FOCUS_NONE
    visible = false
    tooltip_text = tr("Controls that do not fit on the bar.")
    size_flags_vertical = SIZE_SHRINK_CENTER
    custom_minimum_size = Vector2(SaUI.px(SaUI.BASE_ICON_SIZE + 4), SaUI.px(SaUI.BASE_ICON_SIZE + 2))

    box = SaMake.column(null, "OverflowBox", SaTheme.GAP_TIGHT)
    DockerUtils.apply_compact_ui(box)
    list = SaFloatingPanel.new(box, "OverflowList")
    add_child(list)
    pressed.connect(toggle)


## Registers the switch, through the door a module's docker uses, and answers
## nothing when it was already there.
static func register_option() -> void:
    (
        SaSettings
        . register_docker_option(
            "TopMenuBar",
            OPTION,
            {
                "title": "Overflow",
                "hint": "Controls that do not fit on their row go into a list the button at the end of the bar opens.",
                "kind": SaSettingsLayout.OPTION_SWITCH,
                "default": true,
            }
        )
    )


## Whether the switch is on. An option nobody registered reads as null, and
## that is on, since on is the default.
static func enabled() -> bool:
    return SaSettings.get_docker_option("TopMenuBar", OPTION) != false


## Opens the list under the button, or closes it when it is open. A press on the
## button while the list is open reaches here and not the list's own dismissal,
## which leaves a press on its anchor alone.
func toggle() -> void:
    list.toggle_under(self)


## Every control the list holds, in order.
func held() -> Array[Control]:
    var out: Array[Control] = []
    for child in box.get_children():
        var control := child as Control
        if control != null:
            out.append(control)
    return out


## Shows the button when the list holds a control that is shown, and hides it,
## and closes the list, when it holds none. The list takes its new size when it
## is open, since a tool change can show or hide what it holds.
func refresh() -> void:
    var any := false
    for control in held():
        if control.visible:
            any = true
            break
    visible = any
    if not any:
        list.close()
    elif list.is_open():
        list.place()


## The button and the list as numbers, for a capture and a suite.
func report() -> Dictionary:
    var names: Array = []
    for control in held():
        if control.visible:
            names.append(String(control.name))
    var out := {"enabled": enabled(), "shown": visible, "held": names}
    out.merge(list.report())
    return out


## Three dots across the middle, in the text colour, the sign a list of more is
## behind the button.
func _draw() -> void:
    var middle := size / 2.0
    var gap := float(SaUI.px(DOT_GAP))
    var radius := SaUI.pxf(DOT_RADIUS)
    for step: int in [-1, 0, 1]:
        draw_circle(middle + Vector2(gap * step, 0.0), radius, SaTheme.palette.text_primary)
