## Where input comes from when Godot does not hand it to a control by itself:
## a MIDI controller the first. A module extends this and registers it through
## [method SaContext.register_input_source], and it lands on
## `SaRegistries.input_sources`, which the settings, the door's `midi` step and
## the state dump ask, none of them naming the module.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## It is in the pen source's shape. The settings, the door and the dump ask the
## source registered under an id rather than opening MIDI inputs by name or
## asking a MIDI facade, so MIDI lives in a module of its own, and what a
## source does is its own.
##
## **What a source brings beside this** goes through the doors that exist: a
## Preferences page through `register_settings_page` and a command through
## `register_command`, so the descriptor carries neither. What a bound control
## drives, a value, a preset or a filter, is [SaControlDrive] on the context.
##
## Each method is called on the main thread, at registration, at a setting
## moved, at a dump and at a door step, never per frame.
class_name SaInputSource
extends RefCounted

## The source's own name, which the registry keys it by and the dump writes its
## block under. The door's `midi` step asks the source whose id is `midi`.
var id: StringName = &""

## The settings [method apply] follows, by the property name `SaSettings`
## announces, so the registry calls it again when one of them moves.
var settings: Array[StringName] = []


## *source_id* names the source and *setting_names* are the settings its
## [method apply] reads.
func _init(source_id: StringName = &"", setting_names: Array[StringName] = []) -> void:
    id = source_id
    settings = setting_names.duplicate()


## Opens the inputs or closes them, as the painter's settings say. Called when
## the source registers, which is at start for one a module brings, and again
## whenever a setting in [member settings] moves.
func apply() -> void:
    pass


## Closes whatever [method apply] opened, because the module that registered the
## source is unloading. Called once, as the registry lets the source go.
func release() -> void:
    pass


## The dump's block for the source, written under [member id].
func capture_state() -> Dictionary:
    return {}


## Feeds *spec* in the way a device would, for the door's step a scenario names
## the source by, and answers the line the step prints.
func simulate(spec: Dictionary) -> String:
    return "SaCapture: the input source %s simulates nothing, not %s" % [id, JSON.stringify(spec)]
