## What each of the pen's buttons does, as a preference: the four buttons a
## driver can report, the five things one can be bound to, and how any stored
## table becomes exactly those four answers.
##
## Its own class because the vocabulary is a rule three readers agree on, the
## profile's setter, the Tablet page that builds a row a button and the tool
## machine that acts on a press, and none of them is a preference. The values
## file holds the one stored table and nothing else of it.
##
## **A button is named by what the driver reports it as**, because that is all
## Sara ever sees of a pen, and its hint says which button of a usual pen that
## is. The hints are what was measured rather than what a driver's convention
## promises. The lower barrel button, nearer the tip, came in as a right press
## under Windows Ink and under Wayland. The upper came in as none of the four
## under either Windows driver on the pen it was measured with, and as the tip's
## own left press under Wayland (godotengine/godot#124067), so the middle row's
## hint says it is the upper button only where the driver sends it as the middle
## one. Under Wayland the tool machine tells that left press from the tip with
## the pen in the air and hands it on as the middle button, so there the row
## says so in a hint of its own, `wayland_hint`. The two extra buttons are
## Godot's `MOUSE_BUTTON_XBUTTON1` and `XBUTTON2`, a mouse's back and forward,
## which no usual pen sends unless its driver is set to.
##
## **The mouse's wheel press has a row of its own**, `mouse_middle` in the
## profile and Pan by default, because the pen's middle can be bound to Eraser
## while held and the wheel then erased too. A middle press follows the pen's
## row when a pen made it and this one otherwise, and the tool machine says
## which, see [method ToolMachine._middle_action].
##
## `@tool` because the autoload that reads it is.
@tool
class_name SaSettingsPenButtons
extends RefCounted

## The actions. Pan is a drag that moves the view, and turns it when Shift is
## down at the press, as the middle button always did. The two held ones swap
## the tool for as long as the button is down and hand it back on the release.
const CONTEXT_MENU: String = "context_menu"
const PAN: String = "pan"
const EYEDROPPER: String = "eyedropper"
const ERASER: String = "eraser"
const NOTHING: String = "nothing"
const ACTIONS: Array[Dictionary] = [
    {"id": CONTEXT_MENU, "label": "Brush docker or the tool's menu"},
    {"id": PAN, "label": "Pan"},
    {"id": EYEDROPPER, "label": "Eyedropper while held"},
    {"id": ERASER, "label": "Eraser while held"},
    {"id": NOTHING, "label": "Nothing"},
]

## What each row of [constant BUTTONS] says under its title, kept apart from the
## table so the template reads every sentence and a catalogue can translate it.
const HINTS: Dictionary[String, String] = {
    "right":
    (
        "The barrel's lower button on most pens, the one nearer the tip. The mouse's right button follows it too. "
        + "Under the Brush and the Eraser it lends Brush Presets, or the pop-up palette as Preferences > Brushes "
        + "chooses, and a second press sends it home. Under any other tool it opens that tool's menu."
    ),
    "middle":
    (
        "The barrel's upper button, where the tablet's driver sends it as the middle one, which not every "
        + "driver does. The mouse's wheel press has the row below."
    ),
    "extra1": "No button of a usual pen, unless the tablet's driver sends one as Back. The mouse's back button follows it too.",
    "extra2":
    "No button of a usual pen, unless the tablet's driver sends one as Forward. The mouse's forward button " + "follows it too.",
}

## What a row says instead under Wayland, where the compositor hides a button
## the tablet's driver sends, by the same id.
const WAYLAND_HINTS: Dictionary[String, String] = {
    "middle":
    (
        "The barrel's upper button. On Wayland, Sara cannot tell this button from the tip while the pen "
        + "touches the tablet. It works while the pen hovers. Let go in the air, it still counts for the next "
        + "touch until the pen leaves the tablet's range or you press it again. The mouse's wheel press has "
        + "the row below."
    ),
}

## The buttons, in the order the Tablet page shows them, each with the Godot
## button it arrives as, its default and the hint its row carries. The defaults
## are what a pen does with nothing bound: a right press opens the context menu,
## a middle drag pans, and nothing reads the extra buttons. Each hint ends on
## the mouse's own button, because the tool machine reads a button by its index
## and a mouse's press follows the row as a pen's does, the wheel press
## excepted, which has the row of [method mouse_middle_bound] and is named in
## the Middle row's hints.
const BUTTONS: Array[Dictionary] = [
    {
        "id": "right",
        "label": "Right button",
        "index": MOUSE_BUTTON_RIGHT,
        "default": CONTEXT_MENU,
        "hint": HINTS["right"],
    },
    {
        "id": "middle",
        "label": "Middle button",
        "index": MOUSE_BUTTON_MIDDLE,
        "default": PAN,
        "hint": HINTS["middle"],
        "wayland_hint": WAYLAND_HINTS["middle"],
    },
    {
        "id": "extra1",
        "label": "First extra button",
        "index": MOUSE_BUTTON_XBUTTON1,
        "default": NOTHING,
        "hint": HINTS["extra1"],
    },
    {
        "id": "extra2",
        "label": "Second extra button",
        "index": MOUSE_BUTTON_XBUTTON2,
        "default": NOTHING,
        "hint": HINTS["extra2"],
    },
]


## What the row of *button* says, its `wayland_hint` when *wayland* holds and it
## has one, and its `hint` otherwise.
static func hint(button: Dictionary, wayland: bool = DisplayServer.get_name() == "Wayland") -> String:
    if wayland and button.has("wayland_hint"):
        return TranslationServer.translate(WAYLAND_HINTS[str(button["id"])])
    return TranslationServer.translate(HINTS[str(button["id"])])


## Every button bound to its default, what a pen does with nothing bound.
static func defaults() -> Dictionary[String, String]:
    var out: Dictionary[String, String] = {}
    for button: Dictionary[String, Variant] in BUTTONS:
        out[button["id"]] = button["default"]
    return out


## *stored* as exactly the four buttons, each bound to a listed action. A
## button the table does not name, or names with an action no row offers, keeps
## its default, so a hand-edited profile cannot leave a button acting on a word
## the machine does not know.
static func bound(stored: Variant) -> Dictionary[String, String]:
    var out := defaults()
    if not (stored is Dictionary):
        return out
    var table: Dictionary = stored
    for id: String in out:
        var action := str(table.get(id, ""))
        if _listed(action):
            out[id] = action
    return out


## The mouse's wheel press bound to *stored*, Pan when it is not a listed
## action, so a hand-edited profile cannot leave the wheel acting on a word the
## machine does not know.
static func mouse_middle_bound(stored: Variant) -> String:
    var action := str(stored)
    return action if _listed(action) else PAN


## What the button Godot reports as *index* is bound to in *table*, and null
## for a button that is not a pen's, the left one and the wheel above all.
static func action_for(table: Dictionary[String, String], index: int) -> Variant:
    for button: Dictionary[String, Variant] in BUTTONS:
        var button_index: int = button["index"]
        if button_index == index:
            return str(table.get(button["id"], button["default"]))
    return null


## The tool a held action swaps in on *machine*, and empty for an action that is
## no tool or a machine that holds no such tool. Eyedropper while held asks the
## machine for the tool whose descriptor sets `picks_colour`, and Eraser while
## held for the one that sets `erases`, so the settings name no module's tool id
## and a module registering its own picker or eraser under any id takes the
## button. The action's own string is only what the profile stores. The machine
## is an `Object` asked by method name, because `core` never names the tool
## machine's class, as with `SaPickHold`.
static func tool_for(action: String, machine: Object) -> StringName:
    var lookup: StringName = &""
    match action:
        EYEDROPPER:
            lookup = &"picker_tool_name"
        ERASER:
            lookup = &"eraser_tool_name"
    if lookup == &"" or not is_instance_valid(machine) or not machine.has_method(lookup):
        return &""
    var tool: StringName = machine.call(lookup)
    return tool


static func _listed(action: String) -> bool:
    for entry: Dictionary[String, Variant] in ACTIONS:
        if entry["id"] == action:
            return true
    return false
