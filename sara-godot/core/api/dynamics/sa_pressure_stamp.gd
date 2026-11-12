## The painter's pressure table as a module sees it: the stamp a preset
## carries, the announcement when the painter changes it, and the walk that
## moves the stored presets made under the old one.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The door's face of `SaTablet` and the preset store**, so a brush engine
## that carries its maker's table names neither. The table itself, the maths
## that reads it and the announcement live in `core/pen/sa_tablet.gd`, and this
## hands them on.
##
## **A preset made under a table carries it in [constant FIELD]**, a
## `PackedFloat32Array` the stroke reads pressure through in place of the
## painter's own. The field is the whole contract, as `migrate` is the
## store's: [method restamp_stored] asks whether a stored preset has it rather
## than what kind of preset it is, so any engine's settings that carry the
## field are moved on the same way.
class_name SaPressureStamp
extends RefCounted

## The settings field a preset keeps its maker's table in.
const FIELD: StringName = &"maker_pressure_curve"


## The painter's table as a preset carries it, never empty.
static func current() -> PackedFloat32Array:
    return SaTablet.stamp()


## Whether two tables bend pressure the same way.
static func same(a: PackedFloat32Array, b: PackedFloat32Array) -> bool:
    return SaTablet.same_table(a, b)


## The object whose `changed(was, now)` signal announces a new painter's
## table.
static func changes() -> RefCounted:
    return SaTablet.curve_changes


## *settings* moved from *was* to *now* when it carries *was*. True when it did.
static func restamp(settings: Resource, was: PackedFloat32Array, now: PackedFloat32Array) -> bool:
    if settings == null or not (FIELD in settings):
        return false
    var carried: PackedFloat32Array = settings.get(FIELD)
    if carried.is_empty() or not same(carried, was):
        return false
    settings.set(FIELD, now.duplicate())
    return true


## Every stored brush preset stamped with *was* rewritten with *now*,
## answering how many. *dir* is the brush preset folder unless a suite names
## another.
##
## Written in place, with its tags and its licence, rather than through
## `save_preset`, which builds a detached copy and would drop the file's
## metadata. A file older than the field is stamped with the loading
## machine's table at every read, so it follows the painter already and is
## not written.
static func restamp_stored(was: PackedFloat32Array, now: PackedFloat32Array, dir: String = "") -> int:
    var store := SaPresetStore.new()
    if not dir.is_empty():
        store.dir = dir
    var rewritten := 0
    for preset_name in store.list_names():
        var preset := store.load_preset(preset_name)
        if preset == null or preset.has_meta(&"imported_from") or not restamp(preset, was, now):
            continue
        var path := store.dir.path_join(preset_name + SaPresetStore.EXTENSION)
        if ResourceSaver.save(preset, path) != OK:
            push_warning("SaPressureStamp: could not write the new pressure table into '%s'." % path)
            continue
        SaResourceFinder.repair_resource_paths(path)
        rewritten += 1
    return rewritten
