## A line in the log for every key the shortcut router hears, when asked for,
## naming what the platform made of the key: its keycode, its physical keycode,
## its label and its character.
##
## A chord matches by keycode, and the keycode is the platform's reading of the
## key under its layout and its Num Lock, which no event built in GDScript
## shows. A key such as the numpad's slash can pass every suite and still do
## nothing on a painter's Windows machine, so a test run needs the key as the
## platform delivered it. `scripts/virtual_keyboard.py --play numpad-slash`
## reads these lines on Linux, and a Windows run reads its own the same way.
##
## Off unless `SARA_LOG_KEYS=1` is in the environment or `--log-keys` follows
## the `--` of the command line, so a painter's log never fills with keys.
class_name SaKeyLog
extends RefCounted

## What every line starts with, which a reader of the log looks for.
const MARK := "key heard:"

## -1 until the first key asks, then 0 or 1.
static var _asked: int = -1


## Whether the lines are wanted, read once.
static func asked() -> bool:
    if _asked == -1:
        var wanted := OS.get_environment("SARA_LOG_KEYS") == "1" or OS.get_cmdline_user_args().has("--log-keys")
        _asked = 1 if wanted else 0
    return _asked == 1


## Prints *event*'s line when it is a key and the lines are wanted.
static func note(event: InputEvent) -> void:
    var key := event as InputEventKey
    if key != null and asked():
        print(line(key))


## One key's line, the four readings by name and number, and the press.
static func line(key: InputEventKey) -> String:
    return (
        "%s %s, keycode %d, physical %d (%s), label %d, unicode %d, %s%s"
        % [
            MARK,
            key.as_text_keycode() if key.keycode != KEY_NONE else "no keycode",
            key.keycode,
            key.physical_keycode,
            key.as_text_physical_keycode(),
            key.key_label,
            key.unicode,
            "pressed" if key.pressed else "released",
            ", echo" if key.echo else "",
        ]
    )
