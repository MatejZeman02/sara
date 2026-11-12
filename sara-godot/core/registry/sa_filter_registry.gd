## The seventh registry: the filters a module offers, and the one signal that
## asks for a filter's dialog.
##
## A filter registers the way a tool or a blend mode does, so the Filter
## menu, a command and a module all read one list. Hard rule 6 is the whole
## point of it: the box blur under `modules/` reaches the menu through this
## registry and no other door.
##
## **The key is the module id and the filter id joined by a full stop**, so two
## modules may each ship a "Box blur" and neither shadows the other. A filter
## registered with no module keeps its bare id, which is what a fixture built
## by hand looks like.
##
## **It knows nothing about dialogs.** [method invoke] emits [signal invoked]
## and the dialog host opens the window. That keeps the registry in `core/`
## with no reach into `ui/`, and it lets a headless test invoke a filter and
## count the signal rather than the window.
class_name SaFilterRegistry
extends RefCounted

## Registration and removal, which is what the Filter menu rebuilds from.
signal changed

## Somebody picked this filter: the menu row, the command, or a test. The host
## that owns the dialog answers.
signal invoked(filter_key: StringName)

## The prefix a filter's command id carries, so the shortcut editor and the
## command list group them without knowing this registry.
##
## An underscore and not a full stop, because `ui/settings/keyboard/shortcut_rows.gd`
## groups the shortcuts page by action prefix and `filter_` is a section it
## already draws. The full stop in the key is turned into one for the same
## reason, which is why [method command_id] is a substitution rather than a
## concatenation.
const COMMAND_PREFIX := "filter_"

## [constant SaFilter.OTHER_SECTION], under the name the menu and the browser
## read it by.
const OTHER := SaFilter.OTHER_SECTION


## One section of the Filter menu and the filter browser: its id, which a
## filter's `family()` names, the word its heading shows, where it sits among
## the others, and the module that registered it. Written by the constructor
## alone.
class Section:
    extends RefCounted
    var id: StringName
    var label: String
    var place: int
    var owner_module: StringName

    func _init(section_id: StringName, text: String, order: int, module_id: StringName) -> void:
        id = section_id
        label = text
        place = order
        owner_module = module_id


var _filters: Dictionary[StringName, SaFilter] = {}
## Key -> the module that registered it. Kept here rather than on the filter,
## because `SaFilter` is the class a student writes and it should carry
## nothing the student did not put there.
var _owners: Dictionary[StringName, StringName] = {}
var _order: Array[StringName] = []
## Section id -> `Section`, and the ids in the order they registered, which
## breaks a tie between two sections asking for one place.
var _sections: Dictionary[StringName, Section] = {}
var _section_order: Array[StringName] = []

## A key whose records another filter reads -> `[its key, a weak reference to
## that filter, the id it named]`, from [method SaFilter.reads_records_of].
## Static, because a record is made where no registry is in hand, on a load
## above all, and the filters it names are the installed modules' wherever the
## record is read.
static var _readers: Dictionary[StringName, Array] = {}


## The key *filter* answers to under *module_id*.
static func key_for(module_id: StringName, filter: SaFilter) -> StringName:
    return key_of(module_id, filter.id())


## The key a filter of the id *filter_id* registered by *module_id* takes.
static func key_of(module_id: StringName, filter_id: StringName) -> StringName:
    if String(module_id).is_empty():
        return filter_id
    return StringName("%s.%s" % [module_id, filter_id])


## The command a filter's key answers to, which is what the palette and a
## shortcut reach it by.
##
## Two keys that differ only in where their full stops fall would answer to one
## command after the substitution. `SaContext.register_filter` asks whether the
## command is taken before it registers anything, so the loser of that is
## refused whole rather than left as a filter no chord reaches.
static func command_id(filter_key: StringName) -> StringName:
    return StringName(COMMAND_PREFIX + String(filter_key).replace(".", "_"))


## The command *filter* answers to under *filter_key*: the name it declared, or
## the one its key spells.
##
## One function because two callers ask it. `SaContext.register_filter` decides
## what to register, and `SaFilterMenu` decides whose chord and whose sentence to
## draw beside the row. Each asking [method command_id] would let them disagree
## about a filter that declared its own name, which shows as a filter with no
## chord beside its menu row and a row that falls back to saying who registered
## it.
static func command_for(filter_key: StringName, filter: SaFilter) -> StringName:
    var named := filter.action_name()
    return named if not String(named).is_empty() else command_id(filter_key)


func register(filter: SaFilter, module_id: StringName = &"") -> bool:
    if filter == null:
        push_error("SaFilterRegistry: refusing to register a null filter.")
        return false
    var key := key_for(module_id, filter)
    if String(key).is_empty():
        push_error("SaFilterRegistry: a filter needs a title or an id.")
        return false
    if _filters.has(key):
        push_error("SaFilterRegistry: '%s' is already registered." % key)
        return false
    _filters[key] = filter
    _owners[key] = module_id
    _order.append(key)
    # A filter registered under a key reads its own records, so a student's copy
    # of the box blur under the module `box_blur` keeps what it saves, though the
    # base module's Box Blur reads `box_blur.box_blur` where nothing else does.
    _readers.erase(key)
    for former: StringName in filter.reads_records_of():
        var former_key := former if String(former).contains(".") else key_of(module_id, former)
        if former_key == key or not _filters.has(former_key):
            _readers[former_key] = [key, weakref(filter), former]
    changed.emit()
    return true


## The key and the values a record made under *filter_key* with *values* is to
## hold: those of the filter that reads such records, through its
## [method SaFilter.record_from], or the two as they came when none does.
static func record_for(filter_key: StringName, values: Dictionary) -> Array:
    var reader: Array = _readers.get(filter_key, [])
    if reader.is_empty():
        return [filter_key, values]
    var held: WeakRef = reader[1]
    var filter: Object = held.get_ref()
    if filter == null:
        return [filter_key, values]
    return [reader[0], filter.call("record_from", reader[2], values)]


## A section of the Filter menu under *section_id*, headed *label* and placed by
## *place*, lower first. Refused for an empty id and for an id already
## registered, by this module or another, with both claimants on the console,
## because a second registration would either rename a section other modules'
## filters already sit in or move it.
func register_section(section_id: StringName, label: String, place: int, module_id: StringName = &"") -> bool:
    if String(section_id).is_empty():
        push_error("SaFilterRegistry: a filter section needs an id.")
        return false
    if _sections.has(section_id):
        push_error(section_clash_line(module_id, section_id, (_sections[section_id] as Section).owner_module))
        return false
    _sections[section_id] = Section.new(section_id, label, place, module_id)
    _section_order.append(section_id)
    changed.emit()
    return true


## The console line for a section id two modules want, in the form
## `SaContext.command_clash_line` gives a command, and for the same reason: a
## test reads the words it asserts.
static func section_clash_line(asking: StringName, section_id: StringName, holder: StringName) -> String:
    return (
        "SaFilterRegistry.register_section: %s asked for the section '%s', which %s already registered."
        % [_named(asking, "an unnamed module"), section_id, _named(holder, "a section with no module")]
    )


static func _named(module_id: StringName, unnamed: String) -> String:
    return "'%s'" % module_id if not String(module_id).is_empty() else unnamed


## Every section in the order the menu lists them: by place, then by
## registration, and [constant OTHER] last. Other is made up here with its
## plain word when no module registered it, so the list always ends in it.
func list_sections() -> Array[Section]:
    var out: Array[Section] = []
    for section_id: StringName in _section_order:
        if section_id != OTHER:
            out.append(_sections[section_id])
    # A stable sort, so two sections at one place keep their registration order.
    var ranked: Array[Section] = []
    for section in out:
        var at := ranked.size()
        while at > 0 and ranked[at - 1].place > section.place:
            at -= 1
        ranked.insert(at, section)
    ranked.append(_sections[OTHER] if _sections.has(OTHER) else Section.new(OTHER, "Other", 0, &""))
    return ranked


## A row of the search for every filter, by section in the menu's order, under
## "Filter > " and its section, standing for the filter's command and listed in
## its place. A pick runs that command, as the Filter menu's row does, and a
## filter whose `problem` says it cannot run is listed dimmed.
func search_rows() -> Array[SaSearchRegistry.Row]:
    var out: Array[SaSearchRegistry.Row] = []
    for section: Section in list_sections():
        var place := "%s > %s" % [tr("Filter"), tr(section.label)]
        for key: StringName in _order:
            if section_of(key) != section.id:
                continue
            var filter := _filters[key]
            var command := command_for(key, filter)
            var live := filter.problem().is_empty()
            var row := SaSearchRegistry.Row.new(
                SaSearchRegistry.FILTER, filter.title(), place, Callable(), command, filter.sentence(), live, command, command
            )
            out.append(row)
    return out


## The section *filter_key*'s filter is listed in: the one its `family()` names
## when somebody registered it, and [constant OTHER] otherwise.
func section_of(filter_key: StringName) -> StringName:
    var filter := get_filter(filter_key)
    var named := filter.family() if filter != null else &""
    return named if _sections.has(named) else OTHER


## Removes every filter and every section *module_id* registered, which is what
## a reload does between unloading a module and loading it again. A filter of
## another module that sat in a dropped section falls to Other until a section
## of that id comes back.
func unregister_module(module_id: StringName) -> void:
    var doomed: Array[StringName] = []
    for key: StringName in _order:
        if _owners[key] == module_id:
            doomed.append(key)
    var doomed_sections: Array[StringName] = []
    for section_id: StringName in _section_order:
        if (_sections[section_id] as Section).owner_module == module_id:
            doomed_sections.append(section_id)
    if doomed.is_empty() and doomed_sections.is_empty():
        return
    for key in doomed:
        for former: StringName in _readers.keys():
            if _readers[former][0] == key:
                _readers.erase(former)
        _filters.erase(key)
        _owners.erase(key)
        _order.erase(key)
    for section_id in doomed_sections:
        _sections.erase(section_id)
        _section_order.erase(section_id)
    changed.emit()


func has(filter_key: StringName) -> bool:
    return _filters.has(filter_key)


func get_filter(filter_key: StringName) -> SaFilter:
    return _filters.get(filter_key)


## Who registered *filter_key*, or "" for one nobody attributed.
func owner_of(filter_key: StringName) -> StringName:
    return _owners.get(filter_key, &"")


## Every key, in registration order, which is the order each module wrote its
## filters in and therefore the order it meant.
func list_keys() -> Array[StringName]:
    return _order.duplicate()


## The keys grouped by the module that owns them, as
## `{ module_id -> Array[StringName] }`, in registration order within a module
## and in first-registration order between them.
##
## The Modules menu groups its rows the same way and for the same reason:
## "which module added this" is the first question anyone asks of an entry they
## did not expect, and a flat list cannot answer it.
func list_by_module() -> Dictionary[StringName, Array]:
    var grouped: Dictionary[StringName, Array] = {}
    for key: StringName in _order:
        var module_id: StringName = _owners[key]
        if not grouped.has(module_id):
            var keys: Array[StringName] = []
            grouped[module_id] = keys
        grouped[module_id].append(key)
    return grouped


## Asks for *filter_key*'s dialog. False for a key nobody registered, so a
## stale menu row or a command whose module has gone says so rather than
## opening nothing in silence.
func invoke(filter_key: StringName) -> bool:
    if not _filters.has(filter_key):
        push_error("SaFilterRegistry: no filter '%s' is registered." % filter_key)
        return false
    invoked.emit(filter_key)
    return true
