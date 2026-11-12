## One saved set of a filter's values, the file a filter dialog's presets row
## writes through [SaPresetStore] and reads back.
##
## A file of its own rather than an inner class of the row, because
## `ResourceSaver` takes the `script` line of a `.tres` from the script's
## `resource_path`, and an inner class has none: a preset nested in the row
## would save a file holding no field and come back as a bare `Resource`.
##
## The values are the filter's record, the dictionary `parameters()` answers,
## so any filter's presets are this one script and none writes a format of its
## own. Every filter keeps its presets in a directory named after its id, so
## two filters never list each other's.
##
## SPDX-License-Identifier: GPL-3.0-or-later
class_name SaFilterPreset
extends Resource

## Where every filter's presets go, one directory each under it. Beside
## `brush_presets` and `gradient_presets` under the data root, for the
## reason those two are apart.
const ROOT_FOLDER := "filter_presets"

## The directory [method store_for] points a store under. A test points this
## somewhere disposable and puts it back, which is the only reason it is a
## variable rather than the folder above.
static var root: String = default_root()


## The folder every filter's presets sit under when no test moved it.
static func default_root() -> String:
    return SaDataRoot.path(ROOT_FOLDER)


## The filter's record, what `set_parameters()` is handed when the preset is
## picked.
@export var values: Dictionary[String, Variant] = {}


## A preset holding a copy of *record*.
static func of(record: Dictionary) -> SaFilterPreset:
    var preset := SaFilterPreset.new()
    preset.values = SaTyped.strings(record).duplicate(true)
    return preset


## The store of the filter *filter_id*'s presets.
static func store_for(filter_id: StringName) -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = root.path_join(SaPresetStore.sanitize_name(String(filter_id)))
    return store


## The record the preset *preset_name* of *store* holds, or empty when there is
## no such preset or the file is not one of these.
static func values_in(store: SaPresetStore, preset_name: String) -> Dictionary[String, Variant]:
    var preset := store.load_preset(preset_name) as SaFilterPreset
    return preset.values.duplicate(true) if preset != null else {}
