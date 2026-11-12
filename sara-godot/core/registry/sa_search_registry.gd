## The context's registry of the registries a module brings of its own, which the
## search walks beside the built-in ones. Its file also holds the contract every
## registry the search lists answers, [SaSearchRegistry.Row].
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A thing registered through the door is found by the search with no call to
## the search, as Blender's operators are.
##
## **The contract** is one method, `search_rows() -> Array`, holding
## [SaSearchRegistry.Row] apiece. A registry that answers it is walked: the
## built-in ones because [method sources_of] finds them among the context's own
## members, and a module's own because it announced it with
## `context.searches.register(it)`, the door's call. A registry with nothing a painter
## would look for, the blend modes for now, answers nothing and is not walked.
##
## **A pick that needs the app** is a call the app binds where it wires the
## registry, held in the registry's `search_pick`, so no registry here names a
## class of `ui`. While nobody bound it the rows are listed dimmed.
class_name SaSearchRegistry
extends RefCounted

## What each built-in kind says it is on its row.
const TOOL := "Tool"
const DOCKER := "Docker"
const FILTER := "Filter"
const COMMAND := "Command"
const LAYER := "Layer"

## `{"source": Object, "module": StringName}` apiece, in the order announced,
## one array shared by every module's view of the registry.
var _sources: Array = []
## The module a view files what it is handed under, empty for the app's own.
var _module_id: StringName = &""


## One thing the search lists, as its owner describes it. Written by its
## constructor alone.
class Row:
    extends RefCounted
    ## What the row says it is, "Tool", "Filter" or a module's own word.
    var kind: String
    var title: String
    ## Where the thing lives, "Tools" or "Filter > Blur". Empty for a command,
    ## which the search places on the menu that draws it or on the Keyboard
    ## Shortcuts page.
    var place: String
    ## More words the row is found by and shows as its hover.
    var sentence: String
    var enabled: bool
    ## What a pick does. Empty means running [member command] as its menu row
    ## would, and a row with neither is listed dimmed.
    var pick: Callable
    ## The command the row stands for, which the search's right press offers to
    ## keep and to bind, or `&""`.
    var command: StringName
    ## The command or action this row is listed in place of, so a filter's
    ## command is the filter's row and a tool's chord is the tool's row, never
    ## a second row under another name.
    var covers: StringName
    ## The command or action whose chord the row shows.
    var chord: StringName
    ## Listed only when no row before it has its title, which a menu's own row
    ## does, since the Tools menu's Brush is the Brush found twice.
    var gives_way: bool

    func _init(
        what: String,
        named: String,
        found_in: String,
        act: Callable,
        stands_for: StringName = &"",
        said: String = "",
        live: bool = true,
        listed_for: StringName = &"",
        keys: StringName = &"",
        yields: bool = false
    ) -> void:
        kind = what
        title = named
        place = found_in
        pick = act
        command = stands_for
        sentence = said
        enabled = live
        covers = listed_for
        chord = keys
        gives_way = yields


## *shared* is the list of another view, so a module's view and the app's
## hold one list. A new registry starts its own.
func _init(module_id: StringName = &"", shared: Variant = null) -> void:
    _module_id = module_id
    _sources = shared if shared is Array else []


## A view of this registry that files what it announces under *module_id*,
## which `SaContext.for_module` hands a module.
func for_module(module_id: StringName) -> SaSearchRegistry:
    return SaSearchRegistry.new(module_id, _sources)


## Announces *source*, a registry of a module's own, to the search, filed under
## *module_id* or else the view's module. Refused for one that does not answer
## `search_rows` and for one announced already.
func register(source: Object, module_id: StringName = &"") -> bool:
    if module_id.is_empty():
        module_id = _module_id
    if source == null or not source.has_method("search_rows"):
        push_error("SaSearchRegistry: a search source answers search_rows().")
        return false
    for held: Dictionary in _sources:
        if held["source"] == source:
            push_error("SaSearchRegistry: that source is already announced.")
            return false
    _sources.append({"source": source, "module": module_id})
    return true


## Removes every source *module_id* announced.
func unregister_module(module_id: StringName) -> void:
    for at in range(_sources.size() - 1, -1, -1):
        if _sources[at]["module"] == module_id:
            _sources.remove_at(at)


## The announced sources, oldest first.
func list_sources() -> Array:
    return _sources.map(func(held: Dictionary) -> Object: return held["source"])


## Every registry *context* holds that answers `search_rows`, in the order the
## context declares them, then the ones modules announced through it. The list
## is read off the context's own members, so a registry added to the context
## is walked with no line written here.
static func sources_of(context: Object) -> Array:
    var out: Array = []
    if context == null:
        return out
    var announced: SaSearchRegistry = null
    for property: Dictionary in context.get_property_list():
        var usage: int = property["usage"]
        if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
            continue
        var member: StringName = property["name"]
        var held: Variant = context.get(member)
        if not (held is Object):
            continue
        var found: Object = held
        if found is SaSearchRegistry:
            announced = found
        elif found.has_method("search_rows") and not out.has(found):
            out.append(found)
    if announced != null:
        for source: Object in announced.list_sources():
            if not out.has(source):
                out.append(source)
    return out
