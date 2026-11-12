## The modules the painter switched off on Preferences > Modules, and what that
## leaves out of a start: each one switched off, every module that needs one of
## them, and the line a document gets when it names one.
##
## The loader asks [method reason] of each module in dependency order before it
## registers it, so a module that needs a switched-off one is kept out with the
## reason rather than refused as a fault. A refusal is a push_error and a red
## row, and a module the painter chose to leave out is neither.
##
## A document never fails to open over a module that is off. What it holds for
## one is kept as data, the way a file from a machine without the module is, and
## [method off_named_by] is what the loader says so of, rather than a canvas
## that silently shows less.
class_name SaSwitchedOff
extends RefCounted

## The module Sara does not run without, which no setting can leave out.
const SKELETON := &"sara-skeleton"

## The reason a module the painter switched off is not loaded.
const SWITCHED_OFF := "switched off in Preferences"

## What the painter switched off, by id, as the setting held it at the start.
var _asked: PackedStringArray = PackedStringArray()

## Each module left out at this start, with the reason: module_id -> String.
## The loader's `off_modules` is this dictionary.
var reasons: Dictionary[StringName, String] = {}


func _init(asked: Array) -> void:
    for module_id: Variant in asked:
        if StringName(str(module_id)) != SKELETON:
            _asked.append(str(module_id))


## Why *module_id* stays out of this start, or "" when it may register, kept in
## [member reasons] when it stays out. A module that needs one already left out
## stays out too, which the dependency order makes known by the time it is asked.
## *dependencies* are the ids the module's manifest names.
func reason(module_id: StringName, dependencies: PackedStringArray) -> String:
    var why := ""
    if _asked.has(String(module_id)):
        why = SWITCHED_OFF
    else:
        for dep: String in dependencies:
            if reasons.has(StringName(dep)):
                why = "needs %s, which is off" % dep
                break
    if not why.is_empty():
        reasons[module_id] = why
    return why


## Whether *module_id* was asked off by the painter, rather than left out for a
## dependency.
func asked_off(module_id: StringName) -> bool:
    return _asked.has(String(module_id))


## Whether the module of *manifest* is asked off by an id its manifest names,
## so the loader can file it without reading its script. A module whose id
## only its script knows has to be read to be known.
func unread(manifest: SaModuleManifest) -> bool:
    return manifest.from_file.has("id") and asked_off(manifest.id)


## The scripts of *paths* worth loading ahead of the start, leaving out each
## one whose folder's manifest names a module in *asked*.
static func wanted_scripts(paths: PackedStringArray, asked: Array) -> PackedStringArray:
    var off := SaSwitchedOff.new(asked)
    var wanted := PackedStringArray()
    for script_path: String in paths:
        if not off.unread(SaModuleManifest.read(script_path.get_base_dir())):
            wanted.append(script_path)
    return wanted


## Each module left out at this start that *document* names, in the order the
## document names them. The loader says each as a problem with its reason.
func off_named_by(document: SaDocument) -> Array[StringName]:
    var off: Array[StringName] = []
    for module_id: StringName in named_by(document):
        if reasons.has(module_id):
            off.append(module_id)
    return off


## Every module id *document* names, once each: the keys of its own and its
## layers' module data, the module before the first full stop of each attached
## filter's key, and the module of a layer's simulation rule. A layer type or a
## blend mode is named by its own id alone, so a file does not say whose it is.
static func named_by(document: SaDocument) -> Array[StringName]:
    var named: Array[StringName] = []
    _name_all(named, document.module_data.keys())
    _name_filters(named, document.root_filters)
    for child: Node in document.get_children():
        var layer := child as SaLayer
        if layer == null:
            continue
        _name_all(named, layer.module_data.keys())
        _name_filters(named, layer.filters)
        var record := SaSimulation.record_of(layer)
        if record != null:
            _name_all(named, [record.module])
    return named


static func _name_filters(named: Array[StringName], filters: Array[SaAttachedFilter]) -> void:
    for record: SaAttachedFilter in filters:
        var key := String(record.key)
        if key.contains("."):
            _name_all(named, [key.get_slice(".", 0)])


static func _name_all(named: Array[StringName], ids: Array) -> void:
    for raw: Variant in ids:
        var module_id := StringName(str(raw))
        if not String(module_id).is_empty() and not named.has(module_id):
            named.append(module_id)
