## The button half of a dropdown: the chrome, the arrow, and the press that
## opens or closes the list under it.
##
## Shared by `SaChoiceButton` and `BlendModeButton`, so a second click on an
## open list's button closes it in both. The click outside the list is what
## closes it, and the engine closes it on the press, deferred to the end of the
## frame, while a `Button` answers on the release by default. So by the release
## the list would be gone, the button would find it closed, and open it again.
## Two answers, both here so the two buttons cannot drift apart:
##
## - **The button answers on the press**, `ACTION_MODE_BUTTON_PRESS`, which is
##   what the engine's own `OptionButton` and `MenuButton` do. On the press the
##   list is still showing, so the press is the close.
## - **The list remembers the frame it was hidden in.** A press that finds the
##   list closed in the frame that closed it is that same close, not a reopen,
##   so a hide that is not deferred would be answered the same way.
##
## **Ctrl and the wheel step through the options** with the list closed, so a
## painter tries blend modes or a filter's choices without a click each. The
## wheel, the run of steps and the ends are here, and which row comes next is
## each subclass's answer in `_row_after`, because only it knows which rows
## stand for one value each.
##
## Not a base for the rows or the values: `SaChoiceButton` keys its rows on the
## caller's values and `BlendModeButton` on a registry with favourites and
## sections, and the two have nothing to share below the button.
class_name SaDropdownButton
extends Button

## How long the wheel may rest, in milliseconds, before the next notch starts a
## new run of steps. Under the 800 the engine's `UndoRedo` folds a merge within,
## so a step this calls a run's own is one the history can still fold.
const RUN_PAUSE_MSEC: int = 700

## The list, a child of the button so the theme pass reaches it and so it goes
## when the button does. Public for a capture that presses a row and a test that
## reads one.
var popup: SaChoicePopup = null
## The process frame the list was last hidden in, or -1 for never.
var _closed_frame: int = -1
## The part of a notch a touchpad's smooth scroll has sent so far, signed, wheel
## down positive. A step is taken each time it reaches a whole notch.
var _wheel_carry: float = 0.0
## How many steps the run in hand has taken, and when it took the last one, by
## `Time.get_ticks_msec`. A pause or the pointer leaving ends the run.
var _run_steps: int = 0
var _run_last_msec: int = -RUN_PAUSE_MSEC
## Whether the pick being announced now is a wheel step, true only while the
## step presses its row, so a caller reading `continues_a_run` from the signal
## hears about this pick and never a later click.
var _stepping: bool = false


## *list* is the popup the subclass built for its rows, named *list_name* so a
## dump can tell the two kinds apart.
func _init(list: SaChoicePopup, list_name: String) -> void:
    # A dropdown reads as something to press, so it is not flat, its text
    # clips rather than widening the row it sits in, ending in an ellipsis so a
    # cut name reads as cut, and the label is left of the arrow.
    flat = false
    clip_text = true
    text_overrun_behavior = SaTheme.TEXT_CUT
    alignment = HORIZONTAL_ALIGNMENT_LEFT
    icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    # A dropdown that kept the keyboard after its click answered the next Space
    # itself, as `ui_accept`, and reopened its list where the painter wanted to
    # pan. The list takes the keyboard while it is open, and the button never
    # does, on the bar or in a docker that reuses it.
    focus_mode = Control.FOCUS_NONE
    action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS

    popup = list
    popup.name = list_name
    popup.popup_hide.connect(_on_list_hidden)
    add_child(popup)
    pressed.connect(toggle_list)
    mouse_exited.connect(_end_run)


## Makes the button as wide as its words, for a dropdown in a row with room to
## grow, so a longer language widens it rather than cutting its label. A width
## the caller gave stays the narrowest it goes, so a label that fitted it does
## not move.
func ask_for_its_words() -> void:
    clip_text = false
    text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING


## Breaks the label onto as many lines as the button's width needs, for a
## dropdown that fills a column too narrow to grow, so a long label is read
## whole on two lines. A label that fits stays the one line it was. With
## *whole* false the label goes back to the one cut line it was made with, for a
## button whose label is sometimes the painter's own word.
func wrap_its_words(whole := true) -> void:
    clip_text = not whole
    text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING if whole else SaTheme.TEXT_CUT
    autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if whole else TextServer.AUTOWRAP_OFF


## Opens the list under the button, or closes it when it is already open. A
## press in the frame the list was closed in is the close itself, see above.
func toggle_list() -> void:
    if popup == null:
        return
    if popup.visible:
        popup.hide()
        return
    if closed_this_frame():
        return
    popup.open_under(self)


## Whether the list went away in the frame that is running now, which is the
## one thing a press has to ask before it opens the list again.
func closed_this_frame() -> bool:
    return _closed_frame == Engine.get_process_frames()


func _on_list_hidden() -> void:
    _closed_frame = Engine.get_process_frames()


## Ctrl and the wheel over the closed list step through its options, a notch a
## row, wheel down to the row below. The wheel without Ctrl is left to the
## docker under the button, which scrolls as it always did. A touchpad sends a
## notch in parts, a pan's delta or a wheel's `factor`, read by `SaStep` as every
## stepping control reads them, and the parts add up to a step, so one swipe
## does not run through the whole list.
func _gui_input(event: InputEvent) -> void:
    var held := event as InputEventWithModifiers
    if held == null or not held.ctrl_pressed:
        return
    var notches := SaStep.notches(event).y
    if notches == 0.0 or disabled or (popup != null and popup.visible):
        return
    accept_event()
    if signf(notches) != signf(_wheel_carry):
        _wheel_carry = 0.0
    _wheel_carry += notches
    while absf(_wheel_carry) >= 1.0:
        var direction := 1 if _wheel_carry > 0.0 else -1
        _wheel_carry -= direction
        if not step_choice(direction):
            # At an end, so what is left of the swipe is spent there rather
            # than kept for a turn back.
            _wheel_carry = 0.0
            break


## Chooses the row *direction* rows from the chosen one in the order the list
## shows, one for down and minus one for up, exactly as pressing it in the list
## would, the same signal included. Headings, gaps and disabled rows are passed
## over, and there is no wrapping: false at the first or the last row, which
## leaves the choice where it was.
func step_choice(direction: int) -> bool:
    var row := _row_after(direction)
    if popup == null or row == &"":
        return false
    var now := Time.get_ticks_msec()
    if now - _run_last_msec > RUN_PAUSE_MSEC:
        _run_steps = 0
    _run_steps += 1
    _run_last_msec = now
    _stepping = true
    var took := popup.press_row(row)
    _stepping = false
    return took


## Whether the pick being announced is a wheel step after the first of its run,
## for a caller whose picks are history steps: a run of notches on one button,
## ended by a pause or the pointer leaving it, is meant as one step, so the
## caller folds this pick into the one before it. False for a click in the list.
func continues_a_run() -> bool:
    return _stepping and _run_steps > 1


## `continues_a_run` as the history's own word, `MERGE_ENDS` for a step that
## folds into the one before it and `MERGE_DISABLE` for any other pick.
func run_merge() -> UndoRedo.MergeMode:
    return UndoRedo.MERGE_ENDS if continues_a_run() else UndoRedo.MERGE_DISABLE


## The row a step of *direction* lands on, or an empty name at an end. Each
## kind of dropdown answers for its own rows, because only it knows which of
## them stand for a value once.
func _row_after(_direction: int) -> StringName:
    return &""


func _end_run() -> void:
    _run_steps = 0
    _run_last_msec = -RUN_PAUSE_MSEC
    _wheel_carry = 0.0


## The arrow an `OptionButton` draws for itself, taken from the theme so a theme
## that restyles its dropdowns restyles this one. Read on the notification and
## not in `_init`, because a control outside the tree has no theme to ask.
func _notification(what: int) -> void:
    if what == NOTIFICATION_THEME_CHANGED and has_theme_icon(&"arrow", &"OptionButton"):
        icon = get_theme_icon(&"arrow", &"OptionButton")
