## What a pen and a finger on a touch screen reach the canvas as, and the trail
## that says so.
##
## The trail is off unless Sara was started with `--trail-input`, with
## `SARA_TRAIL_INPUT=1`, or with a file named `trail-input` in its data
## folder. The file is for Android, where a start takes neither an environment
## nor a flag: Godot's activity logged `with parameters []` for an
## `am start --esa command_line_params --trail-input` on the emulator. A debug
## build lets `adb shell run-as org.sara.paint touch files/trail-input` make it.
## Each pointer event the canvas's window hears is then one line of the log,
## its class, its device, the touch index, where it landed, its pressure, its
## tilt, whether the pen is upside down and the buttons held, which is what
## tells a stylus from a finger on a platform nobody has read it on. A press and
## a touch carry no pressure, and their line says `pressure -1.000`.
##
## Private to the tools package and to the canvas that hands it the window's
## events, and it holds no reference to either.
class_name SaInputTrail
extends RefCounted

const TRAIL_FLAG := "--trail-input"
const TRAIL_ENV := "SARA_TRAIL_INPUT"
const TRAIL_FILE := "trail-input"

## Whether the trail prints, read once from the flag, the environment and the
## file. Public as the docker's drag trail is, so a suite turns it on and off.
static var trail: bool = (
    OS.get_cmdline_args().has(TRAIL_FLAG)
    or OS.get_cmdline_user_args().has(TRAIL_FLAG)
    or OS.get_environment(TRAIL_ENV) == "1"
    or FileAccess.file_exists(SaDataRoot.path(TRAIL_FILE))
)


## Prints *event*'s line when the trail is on, and answers the line, empty for
## an event that is not a pointer's, so a suite reads it without the log.
static func note(event: InputEvent) -> String:
    if not trail:
        return ""
    var line := describe(event)
    if not line.is_empty():
        print(line)
    return line


## One line naming what *event* is, or empty when it is neither a mouse event
## nor a screen one.
static func describe(event: InputEvent) -> String:
    var kind := ""
    var index := -1
    var at := Vector2.ZERO
    var pressure := -1.0
    var tilt := Vector2.ZERO
    var inverted := false
    var buttons := 0
    var pressed := ""
    var motion := event as InputEventMouseMotion
    var button := event as InputEventMouseButton
    var touch := event as InputEventScreenTouch
    var drag := event as InputEventScreenDrag
    if motion != null:
        kind = "MouseMotion"
        at = motion.position
        pressure = motion.pressure
        tilt = motion.tilt
        inverted = motion.pen_inverted
        buttons = motion.button_mask
    elif button != null:
        kind = "MouseButton %d" % button.button_index
        at = button.position
        buttons = button.button_mask
        pressed = " pressed" if button.pressed else " released"
    elif touch != null:
        kind = "ScreenTouch"
        index = touch.index
        at = touch.position
        pressed = " pressed" if touch.pressed else " released"
    elif drag != null:
        kind = "ScreenDrag"
        index = drag.index
        at = drag.position
        pressure = drag.pressure
        tilt = drag.tilt
        inverted = drag.pen_inverted
    else:
        return ""
    return (
        "input %s%s device %d index %d at (%.0f, %.0f) pressure %.3f tilt (%.3f, %.3f) inverted %s buttons %d"
        % [kind, pressed, event.device, index, at.x, at.y, pressure, tilt.x, tilt.y, inverted, buttons]
    )
