## Whether the interface names keys at all, and a sentence with its key names
## taken out where it should not.
##
## **A tablet with no keyboard has no keys to name.** On an Android tablet
## with only its pen, a menu row that drew a chord would show a key a painter
## there cannot press, and a tooltip ending in "(E)" the same. So on Android
## the menus draw no key column and a tooltip loses the chord it carries, and
## the desktop is never asked at all.
##
## **A key typed is the only proof of a keyboard.** Android's configuration is
## not asked, because it reports a keyboard where there is none: the emulator's
## image says "qwerty", and a tablet with no keyboard ever attached can
## says the same through a connector, its pen or some other device that calls
## itself a keyboard. So the keys show once a key from a physical keyboard has
## reached Sara in this run, and a volume key, the back key, a pen's button or
## the on-screen keyboard's letters prove nothing.
##
## **Asked each time, never cached**, because a keyboard can be plugged into a
## tablet while Sara runs. A menu is rebuilt before every open and a tooltip is
## built when it shows, so both follow the first typed key without a restart.
##
## **A tooltip is cleaned as it shows** rather than at every place one is
## written. `SaTooltip` already catches every tooltip label on its way into the
## tree, a third-party module's as well as the built-ins', so one call there
## covers the erase toggle, the toolbox, the colour pair and whatever a module
## writes next. A parenthesis is taken out only when what it holds is a chord the
## input map answers right now, so "(Oklab)" stays and so does a key nobody binds.
class_name SaKeyLabels
extends RefCounted

## What `OS.get_name()` is taken to answer, for a suite, or "" for the truth.
static var os_name_override: String = ""
## Whether a hardware keyboard is taken to be attached, for a suite: 1 attached,
## 0 none, and -1 for whether one has typed in this run.
static var keyboard_override: int = -1
## Whether a key from a physical keyboard has reached Sara in this run. Written
## by `hear()`, and cleared by a suite that starts a run of its own.
static var keyboard_typed: bool = false

## Keys that reach Sara from something other than a keyboard: the volume rocker,
## the back, home and menu buttons, a headset's media keys, and `KEY_UNKNOWN`,
## which is what Godot makes of an Android key code it does not map, a pen's
## `KEYCODE_STYLUS_BUTTON_*` among them.
const NOT_A_KEYBOARD: Array[Key] = [
    KEY_NONE,
    KEY_UNKNOWN,
    KEY_VOLUMEUP,
    KEY_VOLUMEDOWN,
    KEY_VOLUMEMUTE,
    KEY_BACK,
    KEY_FORWARD,
    KEY_HOMEPAGE,
    KEY_MENU,
    KEY_SEARCH,
    KEY_STANDBY,
    KEY_MEDIAPLAY,
    KEY_MEDIASTOP,
    KEY_MEDIAPREVIOUS,
    KEY_MEDIANEXT,
    KEY_MEDIARECORD,
    KEY_LAUNCHMAIL,
    KEY_LAUNCHMEDIA,
]

## Takes the tablet to have no keyboard, on Android alone.
##
## It holds even after a key has typed, so a run on the emulator driven by
## `adb shell input keyevent` still shows the tablet with no keyboard. Passed
## through the launch intent's `command_line_params`.
const NO_KEYBOARD_FLAG := "--no-keyboard"


## Whether a menu row and a tooltip may name a key.
static func shown() -> bool:
    var os_name := os_name_override if not os_name_override.is_empty() else OS.get_name()
    if os_name != "Android":
        return true
    listen(Engine.get_main_loop() as SceneTree)
    if keyboard_override >= 0:
        return keyboard_override == 1
    if OS.get_cmdline_args().has(NO_KEYBOARD_FLAG) or OS.get_cmdline_user_args().has(NO_KEYBOARD_FLAG):
        return false
    return keyboard_typed


## Hears every event the root window takes from here on, which on Android is
## every event, because there every window is embedded in the root.
##
## Called by `shown()` rather than by main, so the one place that asks is the
## one place that listens, and a desktop never listens at all. Every menu asks
## as the bar is built at boot, so the listening starts with the run.
static func listen(tree: SceneTree) -> void:
    if tree == null or tree.root == null:
        return
    if not tree.root.window_input.is_connected(hear):
        tree.root.window_input.connect(hear)


## Takes *event* as proof of a keyboard when it is a key pressed on one.
##
## While the on-screen keyboard is up its letters arrive as key events too, so
## nothing pressed then counts.
static func hear(event: InputEvent) -> void:
    if keyboard_typed:
        return
    var key := event as InputEventKey
    if key == null or not key.pressed or key.echo:
        return
    var code := key.keycode if key.keycode != KEY_NONE else key.physical_keycode
    if NOT_A_KEYBOARD.has(code):
        return
    var on_screen := DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD)
    if on_screen and DisplayServer.virtual_keyboard_get_height() > 0:
        return
    keyboard_typed = true


## *chord* when keys are shown, otherwise "", for a menu row's key column.
static func column(chord: String) -> String:
    return chord if shown() else ""


## *text* with every " (chord)" the input map answers taken out, when keys are
## not shown, and *text* as it is when they are.
##
## "Erase with the brush (E)" becomes "Erase with the brush", and "Brush (B).
## Paints with the colour." keeps its sentence after the name.
static func without_keys(text: String) -> String:
    if shown() or not text.contains("("):
        return text
    var bound := bound_chords()
    var out := text
    var at := out.find("(")
    while at != -1:
        var close := out.find(")", at)
        if close == -1:
            break
        var inside := out.substr(at + 1, close - at - 1)
        if _is_bound_list(inside, bound):
            var start := at
            while start > 0 and out[start - 1] == " ":
                start -= 1
            out = out.substr(0, start) + out.substr(close + 1)
            at = out.find("(", start)
        else:
            at = out.find("(", close)
    return out


## Every chord the input map answers, in the words a row or a tooltip writes it
## in, chord -> true.
static func bound_chords() -> Dictionary:
    var out := {}
    for action: StringName in InputMap.get_actions():
        for event: InputEvent in InputMap.action_get_events(action):
            var key := event as InputEventKey
            if key == null:
                continue
            out[SaCommandRegistry.key_text(key)] = true
            if key.keycode == KEY_NONE and key.physical_keycode != KEY_NONE:
                var twin := key.duplicate() as InputEventKey
                twin.keycode = key.physical_keycode
                twin.physical_keycode = KEY_NONE
                out[SaCommandRegistry.key_text(twin)] = true
    return out


## Whether *inside* is one chord or a list of them, each one in *bound*.
static func _is_bound_list(inside: String, bound: Dictionary) -> bool:
    var chords := inside.split(", ", false)
    if chords.is_empty():
        return false
    for chord: String in chords:
        if not bound.has(chord.strip_edges()):
            return false
    return true
