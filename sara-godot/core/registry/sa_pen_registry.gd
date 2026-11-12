## The tenth registry: where the pen's state comes from when something outside
## Godot reads it. A module registers an [SaPenSource] through
## [method SaContext.register_pen_source], and the tool machine and any brush
## engine ask the newest, neither naming the module. Why there is one at all is
## the source's note.
class_name SaPenRegistry
extends RefCounted

## Registration and removal.
signal changed

## `{"source": SaPenSource, "module": StringName}` apiece, oldest first. The last
## is the one asked.
var _sources: Array[Dictionary] = []


## Registers *pen_source* for *module_id*, on top of any registered before it.
## Refused for no source or one already registered.
func register(pen_source: SaPenSource, module_id: StringName = &"") -> bool:
    if pen_source == null:
        push_error("SaPenRegistry: a pen source cannot be null.")
        return false
    for held: Dictionary in _sources:
        if held["source"] == pen_source:
            push_error("SaPenRegistry: that pen source is already registered.")
            return false
    _sources.append({"source": pen_source, "module": module_id})
    changed.emit()
    return true


## Removes every source *module_id* registered.
func unregister_module(module_id: StringName) -> void:
    var kept: Array[Dictionary] = []
    for held: Dictionary in _sources:
        if held["module"] != module_id:
            kept.append(held)
    if kept.size() == _sources.size():
        return
    _sources = kept
    changed.emit()


## The source the tools ask, the newest registered, or null when none is.
func source() -> SaPenSource:
    return _sources.back()["source"] if not _sources.is_empty() else null


## The pen as the newest source knows it, or null when no source is registered
## or the one registered knows nothing.
func now() -> SaPenSource.State:
    var asked := source()
    return asked.now() if asked != null else null
