## The module's two preferences, whether Sara listens and what each control
## drives, kept in the painter's profile under `module.midi`.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Kept through the door every module keeps its values through,
## `SaContext.preference`. An older profile holds them as
## `midi_listen` and `midi_bindings` under `[input]`, the skeleton's own
## settings, so each read names that place and the door moves a value it finds
## there under the module's section, once, before it answers. The skeleton
## keeps every key it does not list when it saves, so nothing drops the old
## pair before the module has read it.
##
## Read and written through two callables rather than through a context, so a
## suite keeps them in a settings object of its own, or in this object alone
## when it hands none. [signal changed] is told each key this object writes,
## the bindings' list and the page hearing it.
extends RefCounted

## A key this object wrote, [constant LISTEN] or [constant BINDINGS].
signal changed(key: StringName)

## Whether the inputs are open, off in a fresh profile.
const LISTEN := &"listen"

## Device name to control key to what the control drives.
const BINDINGS := &"bindings"

## Where an older profile keeps each key, its section and its name there.
const FORMERLY: Dictionary = {LISTEN: ["input", "midi_listen"], BINDINGS: ["input", "midi_bindings"]}

## Whether Sara listens. Written through [method _store].
var listen: bool:
    get:
        return bool(_value(LISTEN, false))
    set(value):
        _store(LISTEN, value)

## What each control drives. Assigned whole, as a setter announces.
var bindings: Dictionary:
    get:
        var held: Variant = _value(BINDINGS, {})
        return held if held is Dictionary else {}
    set(value):
        _store(BINDINGS, value)

## `read(key, default, formerly)` and `write(key, value)`, the context's
## `preference` and `set_preference`, or nothing for [member _held].
var _read: Callable = Callable()
var _write: Callable = Callable()

## The values while no callables are given.
var _held: Dictionary = {}


func _init(read: Callable = Callable(), write: Callable = Callable()) -> void:
    _read = read
    _write = write


## Reads both keys, which moves an old profile's pair under the module's
## section at once rather than at the first message.
func adopt() -> void:
    _value(LISTEN, false)
    _value(BINDINGS, {})


func _value(key: StringName, default: Variant) -> Variant:
    if not _read.is_valid():
        return _held.get(key, default)
    return _read.call(key, default, FORMERLY[key])


func _store(key: StringName, value: Variant) -> void:
    if _write.is_valid():
        _write.call(key, value)
    else:
        _held[key] = value
    changed.emit(key)
