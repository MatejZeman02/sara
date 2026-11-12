## The ten brush slots: the commands behind Ctrl+Alt+1 to Ctrl+Alt+0, and the
## rule for what a chord does when its slot is empty or its preset is gone.
##
## The slots live in the settings and on a Preferences page rather than on the
## tool options bar, they are one global list rather than one per shortcut
## profile, and a slot whose preset was deleted falls back to the default brush
## and says which slot it was.
##
## Its own file rather than a section of `ui/shortcuts/sa_app_commands.gd`, which
## is a list of the application's own singular commands. Ten
## commands generated from one table is a different shape, and the page beside
## it asks this file the same two questions a chord does: how many slots there
## are and which preset each holds.
##
## The chord is built here rather than through `SaAppCommands.chord`, because
## that file registers this one and a call back the other way would make the two
## classes a cycle.
class_name SaBrushSlotCommands
extends RefCounted

## How many slots there are. The number itself is `SaSettingsValues`, beside the
## key that stores them, because `core` does not read `ui`.
const COUNT: int = SaSettingsValues.BRUSH_SLOT_COUNT

## The key each slot answers to, in slot order: 1 to 9 and then 0, which is the
## row Krita's own Ten Brushes plugin uses and the order a painter reads off the
## keyboard.
const KEYS: Array = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0]

## The same ten keys on the numpad, which is where a painter reaches for them
## when the digit row is out of the way: on a Czech keyboard that row types
## letters without Shift, so Ctrl with a digit is out of reach and the numpad
## is the way left.
##
## A second chord on the same command rather than a second command, so the
## Keyboard Shortcuts page keeps ten rows and a painter who rebinds a slot
## rebinds one thing. `ui/shortcuts/shortcut_commands.gd` gives the zoom
## commands two events the same way.
const NUMPAD_KEYS: Array = [KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5, KEY_KP_6, KEY_KP_7, KEY_KP_8, KEY_KP_9, KEY_KP_0]

## What a slot holds when nobody has filled it. A stored list shorter or longer
## than `COUNT` is padded or cut to this shape, so a hand-edited profile cannot
## give the page nine rows.
const EMPTY: String = ""


## The command id for *slot*, 1 to `COUNT`.
##
## `brush_slot_1` rather than `select_brush_slot_1`: the Keyboard Shortcuts page groups its rows by action prefix
## (`SaShortcutRows.GROUPS`), so the second spelling would have filed the ten
## rows under Select beside Select All and Deselect. The title carries the verb
## instead.
static func command_id(slot: int) -> StringName:
    return StringName("brush_slot_%d" % slot)


## Registers all ten against whatever module *ctx* belongs to.
static func register_all(ctx: SaContext) -> void:
    for slot in range(1, COUNT + 1):
        var command := SaCommandDescriptor.create(command_id(slot), "Select brush slot %d" % slot, select.bind(slot))
        command.title_pattern = "Select brush slot %d"
        command.title_value = slot
        command.default_events = [_chord(KEYS[slot - 1]), _chord(NUMPAD_KEYS[slot - 1])]
        command.category = &"brush"
        command.sentence = (
            "Load the brush preset in slot %d. An empty slot does nothing, and a missing preset loads the default brush." % slot
        )
        ctx.register_command(command)


## Ctrl+Alt with the slot's key, which is the chord Krita's plugin offers and
## the one Krita users expect.
static func _chord(keycode: Key) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.ctrl_pressed = true
    event.alt_pressed = true
    return event


## The preset name in *slot*, or "" for a slot nobody has filled and for a slot
## number that is not one of the ten.
static func preset_for(slot: int) -> String:
    var slots: Array = SaSettings.brush_slots
    if slot < 1 or slot > slots.size():
        return EMPTY
    return String(slots[slot - 1])


## Puts *preset_name* in *slot* and writes the profile, or empties the slot when
## it is "".
##
## The whole list is assigned rather than one element written, because
## `SaSettingsValues.brush_slots` announces itself in its setter and an Array
## mutated in place announces nothing, so a slot filled that way would be on the
## page and not in the file.
static func fill(slot: int, preset_name: String) -> void:
    if slot < 1 or slot > COUNT:
        return
    var slots: Array = SaSettings.brush_slots.duplicate()
    slots[slot - 1] = preset_name
    SaSettings.brush_slots = slots


## What the chord for *slot* should do, given the store the presets are in:
## `action` is "none", "load" or "default", `preset` is the name the slot holds
## and `message` is what the corner says.
##
## Apart from `select` because this is the rule and that is the doing. The
## rule is answered here, in a few lines a test
## can ask without a tool options bar, a document or a window.
static func slot_action(slot: int, store: SaPresetStore) -> Dictionary:
    var preset := preset_for(slot)
    if preset.is_empty():
        return {"action": "none", "preset": EMPTY, "message": ""}
    if store != null and store.has_preset(preset):
        return {"action": "load", "preset": preset, "message": ""}
    return {
        "action": "default",
        "preset": preset,
        "message": 'Brush slot %d held "%s", which is gone, so the default brush is loaded.' % [slot, preset],
    }


## The chord's own handler. Always answers true: the key belongs to the slot
## whether or not anything is in it, and a slot that falls through would give
## Ctrl+Alt with a digit to whatever binds one later.
static func select(slot: int) -> bool:
    var presets := preset_box()
    if presets == null:
        return true
    var answer := slot_action(slot, presets.preset_store)
    match String(answer["action"]):
        "load":
            presets.load_preset(String(answer["preset"]))
        "default":
            presets.new_preset()
            SaMessage.notice(String(answer["message"]))
    return true


## The tool options bar's preset group, or null in a host that has no bar: a
## test, and the app before the bar is built.
##
## Public because the Brush Slots page fills its rows from the same store this
## reaches for, and a page offering names no chord could load would be a second
## library beside the real one.
static func preset_box() -> ToolOptionsPresets:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null:
        return null
    var bar := tree.root.find_child("ToolOptionsBar", true, false) as ToolOptionsBar
    return bar.preset_box if bar != null else null
