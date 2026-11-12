## The pin on a docker: the button on the docker's own bar that keeps it shown
## when Tab hides the rest, and the list of pinned dockers the profile keeps.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Tab is the most pressed chord of a painting, and without a pin a painter
## went out of focus mode and back for each colour. The dockers the painter pins
## stay when Tab hides the rest. [method pinned_ids] is what `SaFocusMode` is
## handed, and a docker on it is neither hidden nor outlined.
##
## **Unlike the lock, a pin is kept**. A lock is about one summon, and a pin is
## how the painter works, so the pinned ids go into the profile. They go through
## the door a module keeps its own preferences through, under the skeleton's own
## id, which is where `SaDockerBorrow` and `SaDockerMaximise` keep theirs and for
## their reason: `SaSettingsValues` is at the thousand lines
## `tests/test_file_length.gd` fails a run over. Nothing is pinned in a fresh
## profile, so focus mode behaves as it always did until the painter pins
## something, and a reset of the preferences forgets the pins with the rest of
## the section.
##
## A docker is filed under its registered id, which is the name `MainDockers`
## gives its window, so the pin reads the id off the window it is built for.
##
## Beside focus mode, which is the one thing a pin changes, rather than beside
## the docker window: `ui/dockers` stood some thirty lines under the budget
## `tests/test_structure_budget.gd` holds a folder to, and the file map's top
## page had no room for a folder of its own.
class_name SaDockerPin
extends RefCounted

## The id the skeleton keeps its own preferences under, and the key of the list.
const MODULE_ID := &"sara-skeleton"
const PINS_KEY := &"docker_pins"

## The switch that shows or hides the button on every docker's bar, kept beside
## the pins and for the reason they are kept there.
const SWITCH_KEY := &"docker_pin_button"

## The button in the docker's drag bar. Named, because a scenario presses it by
## name and a suite finds it the same way.
const BUTTON_NAME := &"PinButton"

## What the button says, which is the whole of what a painter is told about the
## pin. Each says what focus mode does with the docker now and what a press
## changes.
const PIN_TOOLTIP := "Pin this docker, so focus mode keeps it shown when Tab hides the rest"
const UNPIN_TOOLTIP := "Pinned: focus mode keeps this docker shown. Press to let Tab hide it"

## The switch as a property a Preferences row binds to, which is why this class
## is ever made. It holds nothing: it reads and writes the profile, so the row
## and every docker always agree.
var button_on: bool:
    get:
        return button_wanted()
    set(val):
        SaSettings.set_module_preference(MODULE_ID, SWITCH_KEY, val)


## Whether the button is wanted on a docker's bar, which is one switch for every
## docker, on Layouts and dockers under Every docker. On for a new profile, as
## the button always was. It hides the button and nothing else: the pins stay on
## [method pinned_ids], and focus mode keeps a pinned docker shown without it.
static func button_wanted() -> bool:
    var stored: Variant = SaSettings.module_preference(MODULE_ID, SWITCH_KEY, true)
    return stored if stored is bool else true


## Whether a name `SaSettings.changed` announced is this switch's, which a
## module's preference is announced under as its id, a slash and its key.
static func names_the_switch(property: StringName) -> bool:
    return property == StringName("%s/%s" % [MODULE_ID, SWITCH_KEY])


## Shows or hides *button* from the switch.
static func apply_button(button: Button) -> void:
    if button != null:
        button.visible = button_wanted()


## The ids of the pinned dockers, in the order they were pinned. A stored value
## that is not a list reads as nothing pinned, and anything in it that is not a
## name is passed over.
static func pinned_ids() -> Array:
    var stored: Variant = SaSettings.module_preference(MODULE_ID, PINS_KEY, [])
    var out: Array = []
    if not stored is Array:
        return out
    for id: Variant in stored:
        if (id is String or id is StringName) and not out.has(String(id)):
            out.append(String(id))
    return out


## Whether *window*'s docker is pinned.
static func is_pinned(window: Window) -> bool:
    return window != null and pinned_ids().has(String(window.name))


## Pins *window*'s docker or unpins it, keeps the list in the profile, and draws
## the button to match.
##
## The one writer, so the list and what a painter sees of it cannot drift apart.
## An empty list forgets the key rather than storing nothing, which leaves a
## profile that never pinned anything as it was.
static func set_pinned(window: Window, pinned: bool) -> void:
    if window == null:
        return
    var id := String(window.name)
    var pins := pinned_ids()
    if pinned and not pins.has(id):
        pins.append(id)
    elif not pinned:
        pins.erase(id)
    var stored: Variant = null
    if not pins.is_empty():
        stored = pins
    SaSettings.set_module_preference(MODULE_ID, PINS_KEY, stored)
    redraw(window)


## The button, built into the drag bar row the lock, the maximise and the hide
## buttons sit in.
##
## Straight after the title, where the lock is placed as well: the lock is built
## after this and takes the same place, so it reads beside the title while a
## summon offers it and the pin sits beside it. Shown on every docker, because
## any docker is one a painter may want to keep through a Tab, but the Toolbox,
## which hides it: it is one tool wide, sixty units in every shipped layout, and
## a third button in its bar floored it past the column beside it.
static func build_button(row: Container, window: Window) -> Button:
    var button := SaMake.button(row, BUTTON_NAME)
    row.move_child(button, 1)
    button.flat = true
    # Toggle mode, so the button holds its pressed look for as long as the pin is
    # in. Godot's `set_pressed_no_signal` does nothing without it.
    button.toggle_mode = true
    button.focus_mode = Control.FOCUS_NONE
    button.custom_minimum_size = Vector2(float(SaUI.px(24)), 0.0)
    button.pressed.connect(_toggle.bind(window))
    _draw_state(button, is_pinned(window))
    return button


## Draws *window*'s button from the profile, which a reset of the preferences
## calls through the docker once it has emptied the list.
static func redraw(window: Window) -> void:
    _draw_state(_button_of(window), is_pinned(window))


## The button this owns on *window*, or null where there is none.
static func _button_of(window: Window) -> Button:
    if window == null:
        return null
    return window.find_child(BUTTON_NAME, true, false) as Button


## Flips the pin, which is all a press of the button means.
static func _toggle(window: Window) -> void:
    set_pinned(window, not is_pinned(window))


## Draws *pinned* on *button*: the pressed look, the icon and the tooltip.
static func _draw_state(button: Button, pinned: bool) -> void:
    if button == null:
        return
    button.set_pressed_no_signal(pinned)
    button.tooltip_text = TranslationServer.translate(UNPIN_TOOLTIP if pinned else PIN_TOOLTIP)
    SaUI.set_button_icon(button, "pin" if pinned else "pin_outline", "P")
