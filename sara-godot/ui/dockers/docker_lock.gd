## The lock on a summoned docker: the state, the button on the docker's own bar
## that sets it, and the reading the summon's leave timer asks before it runs.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The state is the window's own metadata**, like the maximise's kept
## rectangle, because it is one per window and this file has no instance to hang
## it on. A docker that closes forgets it and nothing writes it to the profile,
## because the lock holds a summon open, and a summon is a gesture rather than
## an arrangement.
class_name SaDockerLock
extends RefCounted

## Whether this window is being held out, on the window itself.
##
## Metadata rather than a member, for the reason the maximise's kept rectangle
## gives: what it describes is one window, and it is dropped with that window.
const LOCK_META := &"sa_summon_lock"

## The button in the docker's drag bar. Named, because the summon offers it by
## name and a scenario reaches it the same way.
const BUTTON_NAME := &"LockButton"

## What the button says it will do, which is the whole of what a painter is
## told about the lock. The second is the state a summon starts in.
const HOLD_TOOLTIP := "Keep this docker open."
const RELEASE_TOOLTIP := "Close this docker when the pointer leaves it."


## Whether *window* is held open, which is the question the summon's leave timer
## asks before it runs.
static func is_locked(window: Window) -> bool:
    return window != null and window.has_meta(LOCK_META)


## Holds *window* out or lets it go, and draws the button to match.
##
## The one writer: the button, the summon chord with its modifier and the
## summon's own returning all come through here, so the state and what a painter
## sees of it cannot drift apart.
static func set_locked(window: Window, locked: bool) -> void:
    if window == null:
        return
    if locked:
        window.set_meta(LOCK_META, true)
    else:
        window.remove_meta(LOCK_META)
    _draw_state(_button_of(window), locked)


## Forgets the lock, which is what a docker that closes does. A closed docker is
## not held open, and nothing about a lock is written down, so there is nothing
## else to clean up.
static func forget(window: Window) -> void:
    set_locked(window, false)


## The button, built into the drag bar row the hide and maximise buttons sit in.
##
## After the title and before those two, because the bar ends with the close
## button in every window Sara draws. It is built hidden, because a docker that is
## not out on a summon has nothing to hold open.
static func build_button(row: Container, window: Window) -> Button:
    var button := SaMake.button(row, BUTTON_NAME)
    row.move_child(button, 1)
    button.flat = true
    # Toggle mode, so the button holds its pressed look for as long as the lock
    # is on. Godot's `set_pressed_no_signal` does nothing without it.
    button.toggle_mode = true
    button.focus_mode = Control.FOCUS_NONE
    button.custom_minimum_size = Vector2(float(SaUI.px(24)), 0.0)
    button.visible = false
    button.pressed.connect(_toggle.bind(window))
    _draw_state(button, is_locked(window))
    return button


## Offers the button for as long as *window* is out on a summon, and takes it
## away with the borrow. The docker a painter summoned is the only one a lock
## means anything for, so the rest of the time the bar carries no button.
static func offer(window: Window, offered: bool) -> void:
    var button := _button_of(window)
    if button == null:
        return
    button.visible = offered
    if offered:
        _draw_state(button, is_locked(window))


## The button this owns on *window*, or null where there is none: a window that
## is not a docker draws none, and neither does a docker built without a bar.
static func _button_of(window: Window) -> Button:
    if window == null:
        return null
    return window.find_child(BUTTON_NAME, true, false) as Button


## Flips the lock, which is all a press of the button means.
static func _toggle(window: Window) -> void:
    set_locked(window, not is_locked(window))


## Draws *locked* on *button*: the pressed look, the icon and the tooltip, so a
## lock the chord set reads exactly like one the pointer set.
static func _draw_state(button: Button, locked: bool) -> void:
    if button == null:
        return
    button.set_pressed_no_signal(locked)
    button.tooltip_text = TranslationServer.translate(HOLD_TOOLTIP if locked else RELEASE_TOOLTIP)
    SaUI.set_button_icon(button, "lock" if locked else "unlock", "L")
