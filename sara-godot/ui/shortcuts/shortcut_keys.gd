## Which key is which chord, and the one action whose rule cannot be written
## anywhere else. Kept apart from `ui/shortcuts/shortcut_router.gd`, which
## decides what a chord does.
##
## The router decides what a chord *does*. This decides whether the event in
## hand is that chord at all, which is a question with no state behind it: the
## matching functions here read nothing but the event and the InputMap.
##
## The brush size step is the exception and it is here on purpose. Its matching
## rule and its effect are one answer to one question, "what does a bracket mean
## on a keyboard that is not American", and splitting them would put half the
## reasoning in each file.
##
## **Why the split fell here.** The alternative seam was the block of methods the
## router registers with `SaCommandRegistry`, which is bigger, but each of those
## is bound to the router's own providers and would have had to carry a reference
## back. Matching carries nothing. The commands were cut out later, as a class
## built with the providers themselves rather than with the router.
class_name SaShortcutKeys
extends RefCounted

## The two brackets, and the direction each means. Named here as well as read
## out of the InputMap, because `brush_size_direction` answers a bracket on the
## character as well as on the key's position, and a position is all the
## InputMap holds.
const BRUSH_SIZE_KEYS: Dictionary = {
    KEY_BRACKETLEFT: -1,
    KEY_BRACKETRIGHT: 1,
}

## What one bracket does to the size: a tenth of it, up or down.
##
## The Size row is geometric, so this is the same proportion at every size and
## the keys and the drag stay one scale. See [method brush_size_step] for what
## the fixed amount it replaced cost at each end.
const BRUSH_SIZE_RATIO: float = 0.1

## Undo is bound twice, by Godot's own `ui_undo` and by the shipped `edit_undo`,
## and the router answers either. Both are named here, once, so the rule that
## lets a held chord repeat and the lookup that acts on it cannot drift apart.
const UNDO_ACTIONS: Array[String] = ["ui_undo", "edit_undo"]

## Redo is `edit_redo` alone. `ui_redo` is deliberately off the list, because it
## answers Ctrl+Y and that chord is the canvas proof. A repeat must not be the
## door that puts redo back on it.
const REDO_ACTIONS: Array[String] = ["edit_redo"]

## The engine's actions a `LineEdit` and a `TextEdit` answer themselves.
const TEXT_EDITING_ACTIONS: Array[String] = ["ui_text_select_all", "ui_copy", "ui_cut", "ui_paste", "ui_undo", "ui_redo"]


## Whether *event* is a history chord whose repeats mean the same thing it does,
## so the router's gate lets its echoes past.
##
## A held chord asks for the repeats of any chord that steps one place per
## press, the size bracket and history both, so holding Ctrl+Z keeps undoing.
## The rate is the platform's repeat rate, the same rate the bracket repeats
## at, and not a second timer of Sara's.
##
## Nothing else joins them, and the gate is not an echo exemption in general:
## Ctrl+Q's echo still reaches nobody, which the twin test asserts beside the
## bracket's.
static func history_chord(event: InputEvent) -> bool:
    var key := event as InputEventKey
    if key == null or not key.is_pressed() or not key.echo:
        return false
    return pressed(key, UNDO_ACTIONS, true, true) or pressed(key, REDO_ACTIONS, true, true)


static func is_key_like(event: InputEvent) -> bool:
    return event is InputEventKey or event is InputEventShortcut


## True when any of `actions` exists in the InputMap and matches `event`.
static func pressed(event: InputEvent, actions: Array, allow_echo: bool = false, exact: bool = false) -> bool:
    for action: String in actions:
        if InputMap.has_action(action) and event.is_action_pressed(action, allow_echo, exact):
            return true
    return false


## Escape with no modifier on it. Either spelling of the key, because a
## scenario's `key` step sets both fields and a keyboard sets one. The router
## decides what the key means, and a widget that wants the key for itself asks
## here whether this is it.
static func is_escape(event: InputEvent) -> bool:
    var key := event as InputEventKey
    if key == null:
        return false
    if key.keycode != KEY_ESCAPE and key.physical_keycode != KEY_ESCAPE:
        return false
    return not key.ctrl_pressed and not key.shift_pressed and not key.alt_pressed and not key.meta_pressed


## A key with Ctrl, ALT or Meta held. Shift alone is not a chord, it is how a
## capital letter is typed.
static func is_chord(event: InputEvent) -> bool:
    var key := event as InputEventKey
    if key == null:
        return false
    return key.ctrl_pressed or key.alt_pressed or key.meta_pressed


## Whether *event* is a chord a focused text box answers itself: select all,
## copy, cut, paste, undo and redo, in every form the engine binds them.
##
## The engine's actions are the list and Sara's `select_all` and `edit_*` are not,
## because the box acts on the engine's chords whatever Sara binds, so those are
## the ones that would act twice. Sara's shipped profiles bind the same Ctrl+A,
## C, X, V, Z and Ctrl+Shift+Z, and `SaShortcutStore.ALIASES` moves `ui_undo` and
## `ui_redo` with a rebound Undo and Redo. Ctrl+Y is in, since `ui_redo` carries
## it and Sara binds it to the canvas proof.
##
## Matched exactly, as the box matches, so Krita's Ctrl+Shift+A is still Deselect.
## The release counts as well as the press, so the tool machine is not handed the
## key up of a chord the box took the key down of.
static func text_editing_chord(event: InputEvent) -> bool:
    if not is_key_like(event):
        return false
    for action: String in TEXT_EDITING_ACTIONS:
        if InputMap.has_action(action) and InputMap.event_is_action(event, action, true):
            return true
    return false


## True when an item of the open menu carries this chord itself.
static func menu_claims(popup: Window, event: InputEvent) -> bool:
    var menu := popup as PopupMenu
    if menu == null:
        return false
    for i in menu.item_count:
        var shortcut := menu.get_item_shortcut(i)
        if shortcut != null and shortcut.matches_event(event):
            return true
    return false


## Tab alone toggles every docker. Modified Tab is left alone so it can keep
## meaning focus traversal.
static func is_bare_tab(event: InputEvent) -> bool:
    var key := event as InputEventKey
    if key == null or not key.is_pressed() or key.is_echo():
        return false
    return key.keycode == KEY_TAB and not key.ctrl_pressed and not key.alt_pressed


## Which way the brush size should step for *event*, or 0 for no step.
##
## **What the two actions hold answers first, and exactly**: the brackets, bare
## A and S beside them on the build's own map, and whatever a painter binds on
## the Keyboard Shortcuts page, which no rule below then refuses. Exactly, so
## Shift+A and Ctrl+A stay whatever else they are.
##
## That alone answers one keyboard, since `project.godot` binds by physical
## keycode: a US layout, with no modifier held. Three shapes the running app
## can be handed would reach nothing, and `scenarios/brush-size-brackets-2.json`
## plays each. A bracket arriving as a keycode with no position
## behind it, a bracket arriving as a character with AltGr held, and a bracket
## arriving with Ctrl and ALT together, which is how a compositor may report
## AltGr. On a Czech layout the two US bracket positions type `ú` and `)` and a
## bracket needs AltGr, so a painter on that layout could not resize the brush
## at all with a chord that matched exactly.
##
## **A bracket is a bracket wherever it comes from**, so all four fields of the
## event are read: the physical position, the keycode, the key label and the
## unicode the key produced. Any one of them naming a bracket is enough.
##
## **What the widening costs.** Two things, and they are the reason this is a
## function of its own rather than `exact = false` on the two `pressed` calls.
##
## Shift is let through, so `Shift+]`, which is `}` on a US layout, steps the
## size as well. That is the price of the layouts where a bracket needs Shift,
## and nothing else in Sara wants `}`.
##
## Ctrl alone is refused, because `Ctrl+[` and `Ctrl+]` rotate the view and
## `_handle_brush` runs before the command registry does. ALT with Ctrl is let
## through, being AltGr rather than a chord anybody bound.
##
## **A chord another action holds is that action's**, whatever the widening
## lets through. Photoshop's `Alt+]` selects the layer above and leaves the
## size, and AltGr with a bracket sizes the brush wherever nothing holds it.
##
## Meta is refused for the same reason as Ctrl, without a chord behind it: a key
## with the Super key held belongs to the desktop.
##
## The widening reaches these two actions and no others. Every other chord in
## the router still matches exactly, which is what keeps `Ctrl+Z` from firing on
## `Ctrl+Alt+Z`.
##
## **An echo is a step too**, at the rate the platform repeats a held key, so
## `is_echo()` is not read and `ShortcutRouter.handle_viewport_input`
## lets a bracket's echoes through its gate by name.
static func brush_size_direction(event: InputEvent) -> int:
    var key := event as InputEventKey
    if key == null or not key.is_pressed():
        return 0
    var bound := int(pressed(key, ["brush_size_increase"], true, true)) - int(pressed(key, ["brush_size_decrease"], true, true))
    # Ctrl on its own is the view rotation. Ctrl with ALT is AltGr.
    if bound != 0 or key.meta_pressed or (key.ctrl_pressed and not key.alt_pressed):
        return bound
    for code: int in [key.physical_keycode, key.keycode, key.key_label, key.unicode]:
        if BRUSH_SIZE_KEYS.has(code):
            var own := &"brush_size_increase" if BRUSH_SIZE_KEYS[code] > 0 else &"brush_size_decrease"
            return 0 if SaShortcutStore.holders(SaShortcutStore.chord_of_event(key), own) else int(BRUSH_SIZE_KEYS[code])
    return 0


## The brush size the active tool holds, or the permanent tool's when the active
## one has none, the same resolution [method nudge_brush_radius] uses. Nought
## when neither holds one, which is a tool asking for a size it does not have.
static func current_brush_radius(tool_machine: ToolMachine) -> float:
    if tool_machine == null:
        return 0.0
    var sized := _sized_tool(tool_machine)
    if sized == null:
        return 0.0
    var settings := _radius_of(sized)
    return float(settings.radius) if settings != null else sized.own_size()


## The radius change one bracket makes from *current*.
##
## **A proportion of the size itself rather than a fixed amount.** The Size row
## is geometric, so a constant distance along its scale is a constant *ratio* of
## the size, and the two must agree or the keys and the drag would be two
## scales. A fixed amount was wrong at both ends: at fifty pixels it was a step
## of nought point two per cent, which a painter cannot see, and at half a pixel
## it was a jump of more than four times the size. A tenth of the current size
## is the same proportion of a pixel as of a thousand.
##
## Never nought, so a size at the floor still moves by the smallest step the
## clamp will accept.
static func brush_size_step(current: float, direction: int) -> float:
    return maxf(current, ToolMachine.BRUSH_RADIUS_MIN) * BRUSH_SIZE_RATIO * float(signi(direction))


static func nudge_brush_radius(tool_machine: ToolMachine, delta: float) -> void:
    if tool_machine == null:
        return
    var sized := _sized_tool(tool_machine)
    if sized == null:
        return
    var settings := _radius_of(sized)
    if settings != null:
        settings.radius = clampf(settings.radius + delta, ToolMachine.BRUSH_RADIUS_MIN, ToolMachine.BRUSH_RADIUS_MAX)
    else:
        sized.resize_own(sized.own_size() + delta)
    # Nothing observes brush settings directly, so this is what makes the
    # options bar read the size again. Values only, for the reason the shift
    # drag gives in ToolMachine. The ring polls on its own.
    EventBus.tool_options_moved.emit()


## The tool the brackets resize: the active one, or the permanent one when the
## active one has no size. A size is a brush's settings `radius` or a size of
## the tool's own, [method ToolState.own_size], which is the patch tool's
## circle.
##
## The fallback is what makes AltGr work at all, and it is not about matching.
## `tool_eyedropper_quick` is bound to ALT alone, so `ToolMachine._evaluate_tool`
## has already swapped the brush for the eyedropper by the time this runs, and
## the eyedropper has no size. The painter has not chosen the eyedropper: they
## are holding the modifier their layout needs to type a bracket, and the tool
## they mean is the one they will be holding again a keystroke later, which is
## `default_tool_name`.
##
## Returning null rather than reaching further is deliberate. A permanent tool
## with no size, the transform for instance, is a painter asking to resize
## something that has no size, and silence is the honest answer.
static func _sized_tool(tool_machine: ToolMachine) -> ToolState:
    var candidates: Array[ToolState] = []
    if tool_machine.active_tool != null:
        candidates.append(tool_machine.active_tool)
    var permanent := tool_machine.get_tool(tool_machine.default_tool_name)
    if permanent != null:
        candidates.append(permanent)
    for candidate: ToolState in candidates:
        if _radius_of(candidate) != null or candidate.own_size() >= 0.0:
            return candidate
    return null


## *tool*'s brush settings when they carry a `radius`, null for a tool whose
## size, if it has one, is its own.
static func _radius_of(tool: ToolState) -> Resource:
    var settings: Resource = tool.get("settings")
    if settings != null and "radius" in settings:
        return settings
    return null
