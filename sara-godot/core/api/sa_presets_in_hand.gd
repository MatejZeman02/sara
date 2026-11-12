## The door a module takes to the presets the painter has in hand: which engine
## they are for, a preset loaded by name, and an import run against their store.
## The Brush Presets docker a right click opens is asked through
## `SaRightClickDocker`, beside the pop-up palette.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The presets group is a class of the interface, which no module may name. So
## the group attaches its answers here when they enter the tree and take them away when they leave,
## rather than being found by a node name and called by a method name, which
## the structure scan cannot see and a rename breaks in silence. A caller asks
## here, where an answer missing is a host with no bar.
##
## Static, as `SaProblems` is: Liquify's preset hook and the import capture are
## static functions with no context to hand.
class_name SaPresetsInHand
extends RefCounted

## The group's `preset_engine()`, or empty while no group is attached.
static var _engine: Callable = Callable()
## The group's `import_presets_through(importer)`, or empty.
static var _import: Callable = Callable()
## The group's `load_preset(stored_name)`, or empty.
static var _load: Callable = Callable()


## Attaches the presets group's three answers. The last group to attach answers,
## so a suite's own group stands in for the app's while it is in the tree.
static func attach_group(engine_source: Callable, import_source: Callable, load_by_name: Callable) -> void:
    _engine = engine_source
    _import = import_source
    _load = load_by_name


## Takes the group's answers away, when *group* is still the one attached.
static func detach_group(group: Object) -> void:
    if _engine.is_valid() and _engine.get_object() == group:
        _engine = Callable()
        _import = Callable()
        _load = Callable()


## The engine of the presets in hand, or empty in a host with no bar.
static func engine() -> StringName:
    if not _engine.is_valid():
        return &""
    var answer: StringName = _engine.call()
    return answer


## Loads the preset stored as *stored_name* into the hand, the way a cell of
## the docker does, and answers whether it loaded. False with no group.
static func load_preset(stored_name: String) -> bool:
    if not _load.is_valid():
        return false
    var loaded: bool = _load.call(stored_name)
    return loaded


## Whether a presets group is attached to answer.
static func has_group() -> bool:
    return _import.is_valid()


## Runs *importer* against the group's store and settings and answers what
## arrived, each result carrying the `name` it was stored under. Empty when no
## group is attached, which [method has_group] tells apart beforehand.
static func import_through(importer: Callable) -> Array[Dictionary]:
    var results: Array[Dictionary] = []
    if _import.is_valid():
        var arrived: Array = _import.call(importer)
        results.assign(arrived)
    return results
