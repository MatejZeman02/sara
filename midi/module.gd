## Sara's MIDI module: knobs, faders and keys on a MIDI controller drive the
## sliders, the brush presets and the filters a painter maps them to.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A module of its own and shaped as a repository of its own, as the noise brush
## engine is, because nothing in the skeleton is about MIDI. It registers an
## input source, Preferences > MIDI and Map to MIDI through the context, keeps
## Listen and the bindings as its own preferences, and moves what a binding
## drives through `SaContext.drive`.
extends SaModule

const Midi := preload("res://modules/sara-base-modules/midi/midi.gd")


func get_id() -> StringName:
    return Midi.MODULE_ID


func get_name() -> String:
    return "MIDI"


func register(ctx: SaContext) -> void:
    Midi.register(ctx)


func unregister(_ctx: SaContext) -> void:
    Midi.unregister()
