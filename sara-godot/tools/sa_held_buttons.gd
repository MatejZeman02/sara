## The pen's buttons that are down and bound to a tool while held, and the
## stroke one of them makes when the pen touches with it down.
##
## **Windows Ink reports the barrel held with the tip down as the second
## button and not as the first.** Its pointer message carries
## `POINTER_FLAG_SECONDBUTTON` in place of `FIRSTBUTTON`, so Godot hands over a
## right press, motions whose mask is the right button's and a right release,
## and no left event at all. The eyedropper and the eraser open their stroke on
## a left press, so under the barrel they were swapped in and then heard nothing
## they act on: the Toolbox showed each while the barrel was held, and the
## eyedropper picked nothing and the eraser erased nothing. Under Wayland the
## lower barrel button is a right press as well, sent in the air as readily as
## on the surface, and the tip is a left press of its own that the tool
## already takes.
##
## So the stroke opens on **the first motion that says the pen is on the
## surface**: a held button's tool active, pressure above zero, and no left
## button in the mask. Windows' barrel motions answer all three. A Wayland hover
## has no pressure, and a Wayland touch carries the left button, which opens the
## stroke the usual way. The press is not the trigger because a press in the air
## and a press on the surface arrive as the same event, and opening on it erased
## along the path of a pen held above the tablet.
##
## Under Wayland the upper barrel button is the tip's own left press, and
## [UpperBarrel] below tells the two apart where Sara can.
##
## Private to the tools package. The machine hands it the button events it
## binds to a tool and, while a button is held, every event bound for the tool,
## and gives the tool what it answers. It holds no reference to the machine.
class_name SaHeldButtons
extends RefCounted


## The upper barrel button under Wayland, told from the tip and handed on as
## the middle button it is.
##
## **Godot 4.7's Wayland driver turns the code GNOME sends for the upper button
## into the left button**, the tip's own (godotengine/godot#124067), so it
## would reach Sara as a left press that no row of the Tablet page could bind.
## What tells them apart is the pressure around the press, which a virtual pen
## under GNOME's mutter shows. The tip's
## press comes after a motion that already carries its pressure, at the
## lightest touch as well, because libinput opens a touch only above a
## threshold, so it goes on at once. The upper's comes after a hover at no
## pressure, and hovers at none follow it. A pen is told from a mouse by the
## hover's tilt or its inverted flag, which no mouse reports.
##
## So a left press after a pen's hover is held back until the next motion says
## whose it is: one with pressure is the tip after all, and the press goes on
## one motion late, which is how a desktop that sends the tip's pressure after
## its press still paints. One with none is the upper, handed on as a middle
## press, the button GTK makes of the same code and the one the issue asks
## Godot for, so the Tablet page's Middle row binds it now and still does once
## a release maps it. Its motions go on as the middle button's, and the left
## release as the middle one's.
##
## **On the surface nothing tells them apart.** The tip already holds the left
## button, so the upper pressed there changes nothing Godot reports, and let go
## there it ends the stroke. The tip touching with the upper held in the air is
## a motion with pressure and no press, which opens a held tool's stroke the
## way a Windows barrel's does, and the tip lifting lets the one left button
## go, so a tool it holds goes back when the tip lifts.
##
## **The upper's own release in the air is never heard.** The driver keeps one
## left bit for the tip and the upper together, so the upper let go with the
## tip up clears a bit that is clear, and Godot hands over no event for it. A
## second touch with the upper still held is then a motion with pressure and a
## left press, the tip's own shape to the last field (measured with a virtual
## pen under GNOME, a third touch the same). Sara cannot know and has to
## presume, so a touch that ends with the tip's lift leaves the upper
## **presumed still held**: the next touch's press goes on as the middle
## button's, its motions with it and its lift as the middle release, each touch
## its own stroke and undo step.
## The presumption ends where the driver or the pen says the button's state was
## lost: the upper pressed again in the air, which is a press Godot does hand
## over, a motion's silence of [constant LOST_AFTER_MSEC], which is the pen out
## of the tablet's range where libinput lets every button go, and [method
## forget]. It does not end when the button is let go in the air with the pen
## still in range, because nothing says so, and that touch erases until the
## upper is pressed and let go once.
##
## **Where a module reads the pen from the kernel, nothing is presumed.** A
## source on the door's [SaPenRegistry] says which barrel buttons the kernel
## holds, so at a touch's press the upper is held exactly while the kernel
## says so, across any number of touches, and a touch after it was let go in
## the air is the tip's. Which of the kernel's barrels is the upper depends on
## the pen and on the desktop, mutter sending the Intuos Pro's `BTN_STYLUS2`
## as the code Godot makes the left press, so it is learned rather than
## assumed: the barrel the kernel pressed last, at the moment the upper is told
## from the tip in the air. Until it is learned, and whenever the source knows
## nothing, the presumption above stands as it was.
class UpperBarrel:
    extends RefCounted

    ## How long the pen's motions may stop, in milliseconds, before it is taken
    ## to have left the tablet's range with the upper's state lost. A pen in
    ## range reports through the hand's own tremor, so a silence this long
    ## between two touches is the pen away and not a still hand.
    const LOST_AFTER_MSEC := 400

    ## The meta key on a middle event that came from the upper barrel button.
    const _MADE: StringName = &"from_the_upper_barrel"

    ## What the kernel says of the upper at a press: held, let go, or nothing
    ## because no source reads the pen or the upper is not learned yet.
    enum Held { UNKNOWN, YES, NO }

    ## Whether the display server is Wayland, where the driver does this.
    ## Elsewhere every event goes on as it came.
    var _wayland: bool = false

    ## The left press held back until a motion says whose it is, or null.
    var _pending: InputEventMouseButton = null

    ## Whether the last motion was a pen's in the air: no pressure, and a tilt
    ## or the inverted flag.
    var _pen_in_air: bool = false

    ## Whether the left button Godot holds down is the upper's, so the machine
    ## does not read it as the tip's.
    var down: bool = false

    ## Whether the tip has touched since the upper went down, which tells the
    ## tip's lift from the upper let go in the air.
    var _touched: bool = false

    ## Whether the touch that just ended did so with the upper presumed held,
    ## and the next touch is the upper's as well. See the class's note.
    var _presumed_held: bool = false

    ## Whether the next motion says what the last left release was: pressure
    ## still on means the upper let go with the tip down, none that the tip
    ## lifted.
    var _release_unread: bool = false

    ## The last motion with pressure while no button was down, which a second
    ## touch's press opens its stroke on, since the motion came before it.
    var _touch_motion: InputEventMouseMotion = null

    ## When the last motion was heard, in the clock's milliseconds.
    var _last_heard: int = 0

    ## The clock, which a suite answers for itself.
    var _clock: Callable = Time.get_ticks_msec

    ## Where the pen's state is read outside Godot, which the machine hands
    ## over when it binds, or null. See the class's note.
    var pens: SaPenRegistry = null

    ## The kernel's barrel that is the upper, learned the first time the upper
    ## is told from the tip in the air, none before.
    var _upper_barrel: SaPenSource.Barrel = SaPenSource.Barrel.NONE

    func _init(wayland: bool, clock: Callable = Callable()) -> void:
        _wayland = wayland
        if clock.is_valid():
            _clock = clock

    ## The focus went to another window, where a button may change unheard.
    func forget() -> void:
        down = false
        _touched = false
        _presumed_held = false
        _release_unread = false
        _pending = null

    ## What the machine acts on for *event*, in order. Empty while a press is
    ## held back.
    func told(event: InputEvent) -> Array[InputEvent]:
        if not _wayland:
            return [event]
        var motion := event as InputEventMouseMotion
        if motion != null:
            return _moved(motion)
        var button := event as InputEventMouseButton
        if button == null or button.button_index != MOUSE_BUTTON_LEFT:
            return [event]
        return _pressed(button) if button.pressed else _released(button)

    func _moved(motion: InputEventMouseMotion) -> Array[InputEvent]:
        var out: Array[InputEvent] = []
        _note_silence()
        if _release_unread:
            _release_unread = false
            if motion.pressure > 0.0:
                # The tip is still down, so the left release was the upper's.
                _presumed_held = false
        if _pending != null:
            if motion.pressure > 0.0:
                out.append(_pending)
            else:
                down = true
                _touched = false
                _learn_the_upper()
                out.append(_middle(_pending, true))
            _pending = null
        elif down and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
            # The release never came: the pen left the window with the button
            # held, and Godot let the button go without a word.
            down = false
            _presumed_held = false
            out.append(_middle(motion, false))
        if down and motion.pressure > 0.0:
            _touched = true
        _touch_motion = motion if not down and motion.pressure > 0.0 else null
        _pen_in_air = _in_air(motion)
        out.append(_as_middle(motion) if down else motion)
        return out

    ## Lets the presumption go when the motions stopped for [constant
    ## LOST_AFTER_MSEC], and notes that one has come now.
    func _note_silence() -> void:
        var now: int = _clock.call()
        if _presumed_held and now - _last_heard > LOST_AFTER_MSEC:
            _presumed_held = false
        _last_heard = now

    ## *motion* reached the window, wherever the focus is, and the tool may
    ## never hear it. **While another window holds the focus the engine hands
    ## it every motion over the canvas**, so a pen hovering there never reached
    ## [method told], the left press that took the focus back found the pen on
    ## the surface as the last stroke left it, and went on as the tip: with
    ## Preferences clicked into, the upper held to the eraser painted. This
    ## learns only whether the pen is in the air, so the tool still hears each
    ## motion once, through [method told].
    func heard(motion: InputEventMouseMotion) -> void:
        if _wayland:
            _note_silence()
            _pen_in_air = _in_air(motion)

    ## Whether *motion* is a pen's in the air: no pressure, and a tilt or the
    ## inverted flag, which no mouse reports.
    static func _in_air(motion: InputEventMouseMotion) -> bool:
        return motion.pressure <= 0.0 and (motion.tilt != Vector2.ZERO or motion.pen_inverted)

    func _pressed(button: InputEventMouseButton) -> Array[InputEvent]:
        var out: Array[InputEvent] = []
        if down:
            down = false
            out.append(_middle(button, false))
        elif not _pen_in_air:
            var held := _held_says()
            if held == Held.YES or (held == Held.UNKNOWN and _presumed_held):
                return _touched_again(button)
        _presumed_held = false
        if _pen_in_air:
            _pending = button
            return out
        out.append(button)
        return out

    ## What the kernel says of the upper, through the door's pen source.
    func _held_says() -> Held:
        if pens == null or _upper_barrel == SaPenSource.Barrel.NONE:
            return Held.UNKNOWN
        var pen := pens.now()
        if pen == null:
            return Held.UNKNOWN
        return Held.YES if pen.held(_upper_barrel) else Held.NO

    ## Takes the barrel the kernel pressed last as the upper, when the kernel
    ## still holds it as the upper is told from the tip in the air.
    func _learn_the_upper() -> void:
        var pen := pens.now() if pens != null else null
        if pen != null and pen.held(pen.last_pressed):
            _upper_barrel = pen.last_pressed

    ## The tip's press with the upper presumed still held: the upper's own
    ## touch, the middle button pressed. The motion that carried the pressure
    ## came before the press and went on as the tip's, so it is handed on again
    ## as the middle button's for the held tool's stroke to open on, as the
    ## first touch's does.
    func _touched_again(button: InputEventMouseButton) -> Array[InputEvent]:
        down = true
        _touched = true
        var out: Array[InputEvent] = [_middle(button, true)]
        if _touch_motion != null:
            var again := _as_middle(_touch_motion)
            again.relative = Vector2.ZERO
            out.append(again)
        return out

    ## A release with the press still held back is the upper clicked with the
    ## pen held still, since the tip's press always comes with its pressure.
    ## One with the tip touched since the upper went down is the tip's lift, and
    ## leaves the upper presumed held.
    func _released(button: InputEventMouseButton) -> Array[InputEvent]:
        if _pending != null:
            var press := _pending
            _pending = null
            return [_middle(press, true), _middle(button, false)]
        if not down:
            return [button]
        down = false
        _presumed_held = _touched
        _release_unread = _touched
        _touched = false
        return [_middle(button, false)]

    ## Whether *event* is a middle press or release this class made from the
    ## pen's upper button, and so the pen's and never a wheel's.
    static func made(event: InputEvent) -> bool:
        return event.has_meta(_MADE)

    ## A middle press or release where *at* is, with its modifiers, because a
    ## Shift press of the pan button turns the view. Marked as the pen's.
    static func _middle(at: InputEventMouse, pressed: bool) -> InputEventMouseButton:
        var event := InputEventMouseButton.new()
        event.set_meta(_MADE, true)
        event.button_index = MOUSE_BUTTON_MIDDLE
        event.pressed = pressed
        event.device = at.device
        event.window_id = at.window_id
        event.position = at.position
        event.global_position = at.global_position
        event.shift_pressed = at.shift_pressed
        event.ctrl_pressed = at.ctrl_pressed
        event.alt_pressed = at.alt_pressed
        event.meta_pressed = at.meta_pressed
        var others := at.button_mask & ~(MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE)
        event.button_mask = others | MOUSE_BUTTON_MASK_MIDDLE if pressed else others
        return event

    static func _as_middle(motion: InputEventMouseMotion) -> InputEventMouseMotion:
        var moved := motion.duplicate() as InputEventMouseMotion
        moved.button_mask = (motion.button_mask & ~MOUSE_BUTTON_MASK_LEFT) | MOUSE_BUTTON_MASK_MIDDLE
        return moved


## The upper barrel button under Wayland, which the machine hands every event
## to before anything else reads it.
var upper: UpperBarrel = null

## Godot button index to the tool id a button bound to a tool while held asks
## for, one entry a button that is down.
var _tools: Dictionary = {}

## The held button whose tool is taking a stroke from it, none while no stroke
## is open.
var _stroke_button: MouseButton = MOUSE_BUTTON_NONE

## The last motion the open stroke carried, where a release that brings no
## position of its own, a focus loss, closes it.
var _last_motion: InputEventMouseMotion = null

## Whether the tip's left press came while the open stroke was under way and
## was taken into it, so the left release that follows is the one that closes
## it.
var _tip_joined: bool = false


## *wayland* says whether the upper barrel button is the tip's left press here,
## and *clock* the milliseconds the upper's silence is measured in, which a
## suite answers for itself.
func _init(wayland: bool = DisplayServer.get_name() == "Wayland", clock: Callable = Callable()) -> void:
    upper = UpperBarrel.new(wayland, clock)


func is_empty() -> bool:
    return _tools.is_empty()


## The button *index* went down asking for *tool_id* while it is held.
func press(index: MouseButton, tool_id: StringName) -> void:
    _tools[index] = tool_id


## The button went up. Answers the left release that closes the stroke it was
## making, for the tool to hear before it is handed back, or null.
func release(button: InputEventMouseButton) -> InputEventMouseButton:
    _tools.erase(button.button_index)
    if button.button_index != _stroke_button:
        return null
    _stroke_button = MOUSE_BUTTON_NONE
    _tip_joined = false
    return _left(button, false)


## Every button let go at once, which is a focus loss swallowing the releases.
## Answers the left release that closes an open stroke, or null.
func clear() -> InputEventMouseButton:
    _tools.clear()
    upper.forget()
    if _stroke_button == MOUSE_BUTTON_NONE:
        return null
    _stroke_button = MOUSE_BUTTON_NONE
    _tip_joined = false
    return _left(_last_motion if _last_motion != null else InputEventMouseMotion.new(), false)


## The tool the held buttons ask for, the first one *registered* holds, or
## empty.
func wanted(registered: Dictionary) -> StringName:
    for tool_id: StringName in _tools.values():
        if registered.has(tool_id):
            return tool_id
    return &""


## What the tool *active* hears for *event* while a button is held, in order.
##
## A motion carries the left button in its mask while a stroke is open, so a
## tool that reads the mask rather than its own press sees a drag. The motion
## that opens one is handed over first as it came, which is how a Wayland touch
## arrives, so the brush reads its pressure and tilt before the press and holds
## the first dab for the pen's own pressure.
##
## **A left press while one is open is the tip of the same touch**, reported a
## motion late. Under XWayland the upper barrel is the middle button, the
## pressed motion opens the held tool's stroke, and the tip's left press comes
## after it. Closing the stroke there and opening a second made one touch two
## undo steps, so the press is swallowed and the left release that follows
## closes the stroke, one touch one step under every driver. Windows' barrel
## sends no left event and never comes here.
func route(event: InputEvent, active: StringName) -> Array[InputEvent]:
    var motion := event as InputEventMouseMotion
    if motion != null:
        if _stroke_button != MOUSE_BUTTON_NONE:
            var drag := motion.duplicate() as InputEventMouseMotion
            drag.button_mask |= MOUSE_BUTTON_MASK_LEFT
            _last_motion = drag
            return [drag]
        var touching := _touching(motion, active)
        if touching == MOUSE_BUTTON_NONE:
            return [event]
        _stroke_button = touching
        _last_motion = motion
        return [event, _left(motion, true)]
    var button := event as InputEventMouseButton
    if button == null or button.button_index != MOUSE_BUTTON_LEFT:
        return [event]
    if button.pressed and _stroke_button != MOUSE_BUTTON_NONE:
        _tip_joined = true
        return []
    if not button.pressed and _tip_joined:
        _tip_joined = false
        _stroke_button = MOUSE_BUTTON_NONE
    return [event]


## The held button *motion* strokes with, or none: the one whose tool is
## *active*, with the pen on the surface and no left button down.
func _touching(motion: InputEventMouseMotion, active: StringName) -> MouseButton:
    if motion.pressure <= 0.0 or (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
        return MOUSE_BUTTON_NONE
    for index: MouseButton in _tools:
        if _tools[index] == active:
            return index
    return MOUSE_BUTTON_NONE


## A left press or release where *at* is, which is what the tool opens and
## closes a stroke on.
static func _left(at: InputEventMouse, pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.device = at.device
    event.position = at.position
    event.global_position = at.global_position
    if pressed:
        event.button_mask = at.button_mask | MOUSE_BUTTON_MASK_LEFT
    else:
        event.button_mask = at.button_mask & ~MOUSE_BUTTON_MASK_LEFT
    return event
