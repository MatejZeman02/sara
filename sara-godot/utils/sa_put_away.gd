## The press that puts a window away, which goes no further than that.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A top menu and the Welcome window go away on a press outside them, and the
## press paints no stroke where it lands. Krita closes the menu and swallows the
## press, and so does Sara. The windows are `ui`'s and the canvas that swallows is `render`'s,
## which never names `ui`, so the record the two share is here, in the door both
## may name, and depends on nothing but the engine.
##
## **Two halves, because the window hands its input signal round in the order
## its listeners connected.** The canvas hears a press at its window, before the
## engine routes it, and so do the bar and the Welcome window, which put
## themselves away there. Whichever connected first hears the press first. A
## window that heard it first is gone when the canvas asks, so it names the press
## it went away on, and a window that has not heard it yet is still up, so it is
## in `GROUP`. [method is_spent] reads both.
class_name SaPutAway
extends RefCounted

## The group a window joins to be put away by a press outside it. Joined once,
## for the window's life, and asked about only while the window is visible.
const GROUP := &"sa_put_away_by_a_press"

## The instance id of the press that last put a window away, as the window that
## went away heard it, or 0 before any. An id and not a frame, because a suite
## runs many presses in one frame and a frame would spend every one of them.
static var _spent: int = 0


## Makes *window* one that a press outside it puts away, for as long as it lives.
static func join(window: Window) -> void:
    window.add_to_group(GROUP)


## Says that *press* put a window away, called with the event as the window
## heard it, in the call that hid the window.
static func put_away(press: InputEvent) -> void:
    _spent = press.get_instance_id()


## Whether *press*, heard now at the window and outside every window of
## `GROUP`, is spent putting one away: a window it put away named it, or one is
## still up, which the press is about to put away.
static func is_spent(press: InputEvent, tree: SceneTree) -> bool:
    if press.get_instance_id() == _spent:
        return true
    for node in tree.get_nodes_in_group(GROUP):
        var window := node as Window
        if window != null and window.visible:
            return true
    return false


## Whether *event* is a press: a mouse button going down, the wheel aside,
## which scrolls rather than presses, or a touch landing.
static func is_press(event: InputEvent) -> bool:
    var button := event as InputEventMouseButton
    if button != null:
        var wheel := [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]
        return button.pressed and not wheel.has(button.button_index)
    var touch := event as InputEventScreenTouch
    return touch != null and touch.pressed
