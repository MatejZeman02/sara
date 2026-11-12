## The door the tool machine takes to the docker a right click with a brush
## opens under the pointer: Brush Presets or the pop-up palette, as the painter
## chose on Preferences > Brushes.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Both dockers are classes of the interface, which no tool may name. So each
## attaches its toggle here when it enters the tree and takes it away when it
## leaves, as the presets group attaches to `SaPresetsInHand`, and the tool
## machine asks here without knowing which of the two answers. An answer missing
## is a host with no such docker, and the press then goes on to the context
## menu.
##
## **The choice is read here rather than by the tool machine**, so the machine
## asks one question, and the Preferences row binds to [member opens] on an
## instance, because a row binds to an object and a property and never to a
## static. The property holds nothing: it reads and writes the profile, under the
## skeleton's own id through the door a module keeps its preferences through, as
## `SaDockerBorrow` keeps the summon's.
##
## Static otherwise, as `SaPresetsInHand` is: the tool machine is handed no
## registries.
class_name SaRightClickDocker
extends RefCounted

## The choice that opens Brush Presets, the default and what a new profile gets.
const PRESETS: String = "brush_presets"
## The choice that opens the pop-up palette.
const PALETTE: String = "palette"

## The section of the profile the choice is kept in, the skeleton's own.
const MODULE_ID := &"sara-skeleton"
const KEY := &"brush_right_click"

## Each docker's `toggle_at(point)`, by the choice it answers.
static var _toggles: Dictionary = {}

## Which docker a right click with a brush opens, [constant PRESETS] or
## [constant PALETTE]. Anything else stored reads as [constant PRESETS].
var opens: String:
    get:
        return chosen()
    set(val):
        SaSettings.set_module_preference(MODULE_ID, KEY, val if val == PALETTE else PRESETS)


## The choice as the profile holds it.
static func chosen() -> String:
    var stored: Variant = SaSettings.module_preference(MODULE_ID, KEY, PRESETS)
    return PALETTE if stored is String and stored == PALETTE else PRESETS


## Attaches the toggle of the docker that answers *choice*.
static func attach(choice: String, toggle_source: Callable) -> void:
    _toggles[choice] = toggle_source


## Takes the toggle answering *choice* away, when *docker* is still the one
## attached.
static func detach(choice: String, docker: Object) -> void:
    var toggle: Callable = _toggles.get(choice, Callable())
    if toggle.is_valid() and toggle.get_object() == docker:
        _toggles.erase(choice)


## Opens the chosen docker at *point* when it is closed and closes it when it is
## open, and answers whether it did either. False while that docker is not
## attached. *choice* names the docker instead of the painter's choice, which a
## finger's tap asks, since a tap opens the pop-up palette whatever the right
## click opens.
static func toggle_at(point: Vector2, choice: String = "") -> bool:
    var toggle: Callable = _toggles.get(choice if not choice.is_empty() else chosen(), Callable())
    if not toggle.is_valid():
        return false
    var toggled: bool = toggle.call(point)
    return toggled
