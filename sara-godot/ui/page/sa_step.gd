## One reading of a step gesture: the mouse wheel, a touchpad's pan and the
## arrow keys, turned into the same signed step.
##
## One reading for every control that steps a number, rather than each reading
## the wheel itself: a touchpad sends its two finger scroll as a pan on some
## systems and as a wheel with a fraction of a notch on others, so a control
## reading the wheel alone answers one of the two and a pen reaches neither.
##
## **A notch is [constant PAN_PER_NOTCH] of a pan's delta**, the axis value a
## Wayland compositor sends for one click of a wheel. Godot hands a touchpad's
## two finger scroll on Wayland over as a pan whose delta is that axis value as
## it stands, in surface pixels, so a few pixels of finger travel in one frame
## were read as a few notches, and the page ran to its bottom. A wheel that
## reports a fraction of a notch in `factor` adds up to a step the same way a
## pan does, which is how a Windows touchpad arrives.
##
## Two readings. [method notches] is the amount along the screen's axes, for a
## view that scrolls or zooms by as much as the hand moved. [method read] is
## whole steps of a number, up and right being one more, for a control that
## holds a value, and it keeps the fraction a pan or a smooth wheel left over,
## which is why it is an object and the other is not.
class_name SaStep
extends RefCounted

## A pan's delta for one wheel click, in a compositor's axis units, which are
## surface pixels.
##
## Ten, the value both reference compositors send for a click. Weston's
## `libweston/libinput-device.c` sends `10 * libinput_event_pointer_get_axis_value_discrete()`
## for a wheel, under the comment that libinput before 0.8 sent wheel clicks
## with value 10 and clients came to expect multiples of it, and Mutter's
## `src/wayland/meta-wayland-pointer.c`, the compositor GNOME runs, sends
## `DEFAULT_AXIS_STEP_DISTANCE`, `wl_fixed_from_int (10)`, and scales a smooth
## scroll's steps by the same ten. libinput's own number for a wheel click is
## 15, an angle in degrees (`libinput.h`, `libinput_event_pointer_get_scroll_value`),
## which wlroots passes on as it stands, so under sway a wheel click is 15. A
## wheel arrives in Godot as buttons whatever the number, and only a touchpad's
## pan is read here, whose value is in the units of pointer motion (the same
## page of `libinput.h`), so ten pixels of finger travel is one notch.
const PAN_PER_NOTCH: float = 10.0

## The fraction of a step the last events left, carried to the next.
var _carry: float = 0.0


## Whole steps *event* moved a number: +1 for a wheel notch up or right, a pan
## of one notch's delta up or right, or the Up or Right arrow key, and -1 for the other
## way. Zero for an event that is not a step gesture, and for one that moved
## less than a step so far.
func read(event: InputEvent) -> int:
    var key := event as InputEventKey
    if key != null:
        _carry = 0.0
        return _arrow(key)
    var moved := notches(event)
    _carry += moved.x - moved.y
    var whole := int(_carry)
    _carry -= float(whole)
    return whole


## Whether *event* is one [method read] reads, a wheel press, a pan or an arrow
## key press with no chord modifier held, whether or not it has made a whole
## step yet. A control accepts every one of them, so a wheel's fraction does not
## scroll the page around it instead.
static func reads(event: InputEvent) -> bool:
    var key := event as InputEventKey
    if key != null:
        return _arrow(key) != 0
    return notches(event) != Vector2.ZERO


## The notches *event* moved along the screen's axes, x to the right and y
## down, which is the way a page scrolls: a wheel notch down is (0, 1) and a
## pan is its delta over [constant PAN_PER_NOTCH]. A wheel reports a fraction of
## a notch in `factor` and a clicky one reports nothing, which is one notch.
## Zero for anything else, a wheel's release among them.
static func notches(event: InputEvent) -> Vector2:
    var pan := event as InputEventPanGesture
    if pan != null:
        return pan.delta / PAN_PER_NOTCH
    var button := event as InputEventMouseButton
    if button == null or not button.pressed:
        return Vector2.ZERO
    var amount := button.factor if button.factor > 0.0 else 1.0
    match button.button_index:
        MOUSE_BUTTON_WHEEL_UP:
            return Vector2(0.0, -amount)
        MOUSE_BUTTON_WHEEL_DOWN:
            return Vector2(0.0, amount)
        MOUSE_BUTTON_WHEEL_LEFT:
            return Vector2(-amount, 0.0)
        MOUSE_BUTTON_WHEEL_RIGHT:
            return Vector2(amount, 0.0)
    return Vector2.ZERO


## Where *event* happened in its control, or *otherwise* for one that has no
## place, which is a key.
static func where(event: InputEvent, otherwise: Vector2) -> Vector2:
    var pointer := event as InputEventMouse
    if pointer != null:
        return pointer.position
    var gesture := event as InputEventGesture
    return gesture.position if gesture != null else otherwise


## The step an arrow key press makes, zero for a release, another key or a
## chord with Ctrl, Alt or Meta, which is a shortcut's.
static func _arrow(key: InputEventKey) -> int:
    if not key.pressed or key.ctrl_pressed or key.alt_pressed or key.meta_pressed:
        return 0
    match key.keycode:
        KEY_UP, KEY_RIGHT:
            return 1
        KEY_DOWN, KEY_LEFT:
            return -1
    return 0
