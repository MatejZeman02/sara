## A control a module writes that holds one number, the base class beside
## [SaDialog] for a widget of a filter's own.
##
## A filter's own control would otherwise write the rest of a row by hand: a
## rerun callable passed in, a scenario hook of its own and its own reading of
## every input device, and it would answer a mouse wheel and not a touchpad or
## a pen. This carries the value, the signal, the line of the
## dump and the scenario edit, and takes its steps from [SaStep], so a subclass
## draws and reads its own drag and writes nothing else.
##
## **A row binds it like any other.** On a filter's dialog a `ui.custom` row
## named after a key the filter declared with `ui.parameter` binds the control
## to that parameter, so the filter reads `parameter(&"angle")` and keeps no
## copy, a record or a preset moves the control, and a move reruns the preview.
## On any page the row writes what the control moved to.
##
## A number and not a `Variant`, because a step is arithmetic. A control that
## holds a curve or a palette keeps writing its own row.
class_name SaValueControl
extends Control

## The value moved, by a hand or a scenario, once for each move and never for a
## value put back from outside with [method show_value].
signal value_changed(value: float)

var value: float = 0.0
var low: float = 0.0
var high: float = 1.0
## What one step of the wheel, a pan or an arrow key moves the value by.
var step: float = 1.0

var _steps: SaStep = SaStep.new()


## Holds *start* within *from* and *to*, moved *by* a step. Takes the keyboard
## on a click or a Tab, since the arrow keys are one of its three gestures and
## the one a pen's hand has.
func _init(start: float, from: float, to: float, by: float) -> void:
    low = from
    high = to
    step = by
    value = clampf(start, low, high)
    focus_mode = Control.FOCUS_ALL
    mouse_filter = Control.MOUSE_FILTER_STOP


## Moves to *wanted*, within the range, and says so when that is a change.
func move_to(wanted: float) -> void:
    var fitted := clampf(wanted, low, high)
    if is_equal_approx(fitted, value):
        return
    value = fitted
    queue_redraw()
    value_changed.emit(value)


## Shows *shown* without saying so, for a record or a preset that already holds
## it. The page's refresh calls this.
func show_value(shown: float) -> void:
    value = clampf(shown, low, high)
    queue_redraw()


## A step gesture moves the value, and anything else goes to the subclass's
## [method _pointer_input]. A wheel's fraction is accepted too, so it does not
## scroll the page round the control while it adds up to a step.
func _gui_input(event: InputEvent) -> void:
    if SaStep.reads(event):
        var steps := _steps.read(event)
        if steps != 0:
            move_to(value + float(steps) * step)
        accept_event()
        return
    if _pointer_input(event):
        accept_event()


## The subclass's own reading of the pointer, a drag for a dial, answering
## whether it took *event*. Nothing here.
func _pointer_input(_event: InputEvent) -> bool:
    return false


## The line of the dump, what the control holds and how far a step moves it.
func describe() -> Dictionary:
    return {"value": value, "low": low, "high": high, "step": step}


## A scenario's edit: `{"value": 30}` moves it there, and `{"wheel": 2}`,
## `{"pan": -3.0}` and `{"key": "right", "times": 4}` are the three gestures,
## handed to the control as the events a hand sends, so the helper reads them
## as it reads the hand's. A wheel's notches are up for a positive count, and
## a pan's number is its vertical delta, negative for fingers moving up.
func capture_option_edit(spec: Dictionary) -> String:
    if spec.has("value"):
        move_to(float(spec["value"]))
    var notches := int(spec.get("wheel", 0))
    for _notch in absi(notches):
        for pressed: bool in [true, false]:
            var wheel := InputEventMouseButton.new()
            wheel.button_index = MOUSE_BUTTON_WHEEL_UP if notches > 0 else MOUSE_BUTTON_WHEEL_DOWN
            wheel.pressed = pressed
            wheel.factor = 1.0
            wheel.position = size / 2.0
            _gui_input(wheel)
    if spec.has("pan"):
        var pan := InputEventPanGesture.new()
        pan.delta = Vector2(0.0, float(spec["pan"]))
        pan.position = size / 2.0
        _gui_input(pan)
    if spec.has("key"):
        var code := OS.find_keycode_from_string(String(spec["key"]).capitalize())
        for _press in maxi(1, int(spec.get("times", 1))):
            for pressed: bool in [true, false]:
                var key := InputEventKey.new()
                key.keycode = code
                key.pressed = pressed
                _gui_input(key)
    return "%s holds %s" % [name, str(value)]


## The theme's focus frame while the control has the keyboard, so a hand on
## the arrow keys can see which control they move. A notification rather than
## `_draw`, which a subclass writes, since every class's `_notification` runs.
func _notification(what: int) -> void:
    match what:
        NOTIFICATION_FOCUS_ENTER, NOTIFICATION_FOCUS_EXIT:
            queue_redraw()
        NOTIFICATION_DRAW:
            if has_focus():
                draw_style_box(get_theme_stylebox("focus", "Button"), Rect2(Vector2.ZERO, size))
