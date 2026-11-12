## Every tool the application knows about, described rather than hardcoded.
##
## The registry holds descriptors, not instances: a tool is instantiated once per
## surface (the main canvas and the info docker's scratchpad are two surfaces), so
## each gets its own state while a module describes the tool a single time.
class_name SaToolRegistry
extends RefCounted

## Emitted when a tool is added or removed, so UI built before modules load
## still updates. This is what allows the loader to run before the toolbox exists.
signal changed

var _descriptors: Dictionary[StringName, SaToolDescriptor] = {}
var _order: Array[StringName] = []
## The Brush -> the engine it last painted with, when that is not the Brush's
## own. Written by [method note_in] alone.
var _in_use: Dictionary[StringName, StringName] = {}

## (tool_id) -> void, what picking a tool's row in the search does, which only
## the app can, since the tool in hand is its tool machine's. Bound where the
## app wires the search, and while it is not the rows are listed dimmed.
var search_pick: Callable = Callable()


func register(descriptor: SaToolDescriptor, module_id: StringName = &"") -> bool:
    if descriptor == null or not descriptor.is_valid():
        push_error("SaToolRegistry: refusing an invalid tool descriptor.")
        return false
    if _descriptors.has(descriptor.id):
        push_error("SaToolRegistry: tool '%s' is already registered." % descriptor.id)
        return false
    descriptor.owner_module = module_id
    _descriptors[descriptor.id] = descriptor
    _order.append(descriptor.id)
    changed.emit()
    return true


## Registers *descriptor* as an engine of the Brush rather than a tool.
##
## A brush engine, the noise brush among them, counts as the Brush rather than a
## tool of its own. So an engine is described the way a tool is, because the
## tool machine builds and drives it as one, and lands in the same table with
## [member SaToolDescriptor.is_brush_engine] set. [method list_tools] leaves it
## out, which takes it off the toolbox and the Tools menu, and [method tool_of]
## names the Brush in its place, which is what the machine announces and the
## usage tally counts. A painter reaches it by choosing one of its presets while
## the Brush is in hand.
##
## An engine is known by its presets, so one whose descriptor names no
## `preset_engine` is refused: nothing could ever choose it.
func register_brush_engine(descriptor: SaToolDescriptor, module_id: StringName = &"") -> bool:
    if descriptor != null and String(descriptor.preset_engine).is_empty():
        push_error("SaToolRegistry: refusing brush engine '%s', which names no preset engine." % descriptor.id)
        return false
    if descriptor != null:
        descriptor.is_brush_engine = true
    return register(descriptor, module_id)


## Removes one tool. Used by SaModule.unregister so a module can be unloaded.
func unregister(tool_id: StringName) -> void:
    if not _descriptors.has(tool_id):
        return
    _descriptors.erase(tool_id)
    _order.erase(tool_id)
    changed.emit()


## Removes everything a module registered, so unloading is not the module's
## bookkeeping problem.
func unregister_module(module_id: StringName) -> void:
    var doomed: Array[StringName] = []
    for tool_id: StringName in _order:
        if _descriptors[tool_id].owner_module == module_id:
            doomed.append(tool_id)
    for tool_id in doomed:
        _descriptors.erase(tool_id)
        _order.erase(tool_id)
    if not doomed.is_empty():
        changed.emit()


func has(tool_id: StringName) -> bool:
    return _descriptors.has(tool_id)


func get_descriptor(tool_id: StringName) -> SaToolDescriptor:
    return _descriptors.get(tool_id, null)


## Registration order, brush engines among the tools.
func list_ids() -> Array[StringName]:
    return _order.duplicate()


## Every descriptor, brush engines among the tools, in registration order: what
## the tool machine builds an instance of and the options bar builds rows for.
func list_descriptors() -> Array:
    var out: Array = []
    for tool_id in _order:
        out.append(_descriptors[tool_id])
    return out


## The tools a painter picks from, in toolbox order: every descriptor but a brush
## engine, which paints under the Brush's button. An engine with no Brush
## registered to paint under is listed as a tool, so a build without the stamp
## brush still reaches it.
func list_tools() -> Array:
    var brush := _brush()
    var out: Array = []
    for tool_id in _order:
        var descriptor: SaToolDescriptor = _descriptors[tool_id]
        if descriptor.offered() and (not descriptor.is_brush_engine or String(brush).is_empty()):
            out.append(descriptor)
    return out


## A row of the search for every tool [method list_tools] gives, in its order,
## listed in place of the tool's chord and showing it.
func search_rows() -> Array[SaSearchRegistry.Row]:
    var out: Array[SaSearchRegistry.Row] = []
    for descriptor: SaToolDescriptor in list_tools():
        var named := descriptor.display_name if not descriptor.display_name.is_empty() else String(descriptor.id)
        var action := descriptor.activate_action
        var act := _search_picked.bind(descriptor.id)
        var kind := SaSearchRegistry.TOOL
        out.append(SaSearchRegistry.Row.new(kind, named, "Tools", act, &"", "", search_pick.is_valid(), action, action))
    return out


func _search_picked(tool_id: StringName) -> void:
    if search_pick.is_valid():
        search_pick.call(tool_id)


## The tool a painter knows *tool_id* as: the Brush for one of its engines, and
## *tool_id* itself for anything else, an engine with no Brush to paint under
## among them.
func tool_of(tool_id: StringName) -> StringName:
    var descriptor: SaToolDescriptor = _descriptors.get(tool_id, null)
    if descriptor == null or not descriptor.is_brush_engine:
        return tool_id
    var brush := _brush()
    return brush if not String(brush).is_empty() else tool_id


## [method tool_of] asked of *registry*, or *tool_id* itself when there is none,
## which is a machine a suite built without one.
static func tool_in(registry: SaToolRegistry, tool_id: StringName) -> StringName:
    return registry.tool_of(tool_id) if registry != null else tool_id


## Every id that paints as the tool *tool_id* is known as: the Brush first and
## each of its engines after it in registration order, and *tool_id* alone for
## any other tool.
func engines_of(tool_id: StringName) -> Array[StringName]:
    var shown := tool_of(tool_id)
    var out: Array[StringName] = [shown]
    if shown != _brush():
        return out
    for engine_id: StringName in _order:
        if _descriptors[engine_id].is_brush_engine:
            out.append(engine_id)
    return out


## The id among [method engines_of] *tool_id* whose descriptor takes presets of
## *engine*, or empty when none does, which is a preset the tool cannot paint.
func engine_for(tool_id: StringName, engine: StringName) -> StringName:
    for candidate: StringName in engines_of(tool_id):
        if _descriptors.has(candidate) and _descriptors[candidate].preset_engine == engine:
            return candidate
    return &""


## Notes that a machine made *tool_id* its tool, so a pick of the Brush comes
## back to the engine it last painted with. The machine's
## `set_active_tool` is the one caller, through [method note_in], which makes a
## preset's switch, a scenario's `tool` step and a module reload's restore all
## count.
func note(tool_id: StringName) -> void:
    var shown := tool_of(tool_id)
    if shown != tool_id:
        _in_use[shown] = tool_id
    else:
        _in_use.erase(tool_id)


## [method note] on *registry*, and nothing for a machine bound to none. Static
## so the machine's caller stays one line.
static func note_in(registry: SaToolRegistry, tool_id: StringName) -> void:
    if registry != null:
        registry.note(tool_id)


## What a painter's pick of *tool_id*, on the toolbox, a key or the Tools menu,
## switches to: the engine the Brush last painted with for the Brush, and
## *tool_id* itself for anything else.
func picked(tool_id: StringName) -> StringName:
    var engine: StringName = _in_use.get(tool_id, tool_id)
    return engine if has(engine) else tool_id


## The first tool that takes brush engines, or empty when none is registered.
func _brush() -> StringName:
    for tool_id: StringName in _order:
        if _descriptors[tool_id].takes_brush_engines:
            return tool_id
    return &""


## Tools offered on an embedded surface (the scratchpad), replacing a duplicated
## hardcoded six-tool list.
func list_for_embedded() -> Array:
    var out: Array = []
    for tool_id in _order:
        var descriptor: SaToolDescriptor = _descriptors[tool_id]
        if descriptor.available_in_embedded:
            out.append(descriptor)
    return out


## Quick-hold tools, highest priority first. Replaces ToolMachine._QUICK_TOOLS.
func list_quick_tools() -> Array:
    var out: Array = []
    for tool_id in _order:
        var descriptor: SaToolDescriptor = _descriptors[tool_id]
        if not String(descriptor.quick_action).is_empty():
            out.append(descriptor)
    out.sort_custom(func(a: SaToolDescriptor, b: SaToolDescriptor) -> bool: return a.quick_priority > b.quick_priority)
    return out
