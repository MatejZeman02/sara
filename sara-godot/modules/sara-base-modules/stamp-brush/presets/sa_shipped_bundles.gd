## The Krita bundles a module ships as files, installed at first run the way the
## recipes are.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Why a second door.** [SaShippedPresets] is a table of recipes written as
## this module's own field paths, which is the right shape for a brush Sara can
## describe in numbers. An animated tip is not that: such tips are `.gih` pipes
## and `.pat` papers inside a Krita `.bundle`, and the only thing that reads one
## is the importer. So a module may hold a `bundles/` folder beside its
## `module.gd`, and every `.bundle` in it goes through the same import a
## painter's Import button runs, with the same not-carried tags.
##
## **Once per bundle, by its title.** The title is what the bundle's own
## `meta.xml` calls it and what the importer writes on every preset as `bundle`,
## so it is the name a painter reads and the name the record is kept under. The
## record is a marker of its own in the presets directory, beside the recipes'
## ones and kept by the same store, through [method SaPresetStore.offered] and
## [method SaPresetStore.record_offered], so a bundle a later build adds is
## imported and one already offered is not read past its title again. A preset
## already in the directory under the name a bundle would write is left alone,
## which is the rule for a recipe: a preset of that name is the painter's.
##
## **Here rather than in `core/`**, because the importer is this module's, and a
## skeleton with no stamp brush has nothing to import a bundle with. The module
## registers this script under [constant ROLE], and the presets bar asks for it
## once a session after the recipes.
class_name SaShippedBundles
extends RefCounted

## The role this script is registered under, named once here for the module and
## for the bar that asks for it.
const ROLE: StringName = &"shipped_bundles"

## The folder beside a module's `module.gd` its bundle files live in.
const FOLDER: String = "bundles"

## What a bundle file's name ends in.
const EXTENSION: String = ".bundle"

## The name the record of offered bundle titles is filed under in the store.
##
## One marker for every module's bundles rather than one per module, because a
## title is the bundle's own identity wherever it was found: the same bundle
## moved from one module to another is still the bundle this profile was offered.
const RECORD: String = "Module bundles"


## Every bundle file under a loaded module's `bundles/` folder, sorted by path.
##
## Loaded modules only, the rule `ModuleLoader.module_layouts` keeps for a
## layout: a module that was refused has a folder on disk and no business
## changing a painter's presets.
static func module_paths() -> PackedStringArray:
    var found := PackedStringArray()
    for module_id: StringName in ModuleLoader.loaded_modules:
        var dir_path := String(ModuleLoader.module_dirs.get(module_id, ""))
        if dir_path.is_empty():
            continue
        var folder := dir_path.path_join(FOLDER)
        if DirAccess.open(folder) == null:
            continue
        for file_name: String in DirAccess.get_files_at(folder):
            if file_name.to_lower().ends_with(EXTENSION):
                found.append(folder.path_join(file_name))
    found.sort()
    return found


## Imports every bundle the loaded modules ship that this profile has not been
## offered, and answers how many presets it wrote.
static func install_from_modules(store: SaPresetStore, template: Resource) -> int:
    return install(store, template, module_paths())


## Imports each bundle in *paths* whose title is not in *store*'s record, into
## *store* and from *template*'s script, and answers how many presets it wrote.
##
## The reader and then the importer one preset at a time, which is
## `SaKppImport.import_path` with the title read in between: the title is only
## known once the bundle is read, and reading it twice to learn it would open
## the zip twice per bundle.
##
## A bundle is recorded once it was read, whatever each of its presets came to.
## A preset the importer refused is refused on the next launch as well, and a
## bundle that tried again every start would put the same refusal in the
## console every start. A bundle that could not be read at all is not recorded,
## so a build that fixes the file offers it.
static func install(store: SaPresetStore, template: Resource, paths: PackedStringArray) -> int:
    if store == null or template == null or paths.is_empty():
        return 0
    # No seed rather than the directory's names. The recipes take the directory
    # as the record on a profile carrying no marker, because such a profile may
    # have been offered recipes. No profile was offered a module's bundle that
    # way, so for bundles a missing marker is an empty one.
    var written := 0
    for path: String in paths:
        var presets := SaKppReader.read_path(path)
        var title := title_of(presets, path)
        if title.is_empty() or store.offered(RECORD).has(title):
            continue
        for preset: Dictionary in presets:
            var name := String(preset.get("name", ""))
            if not name.is_empty() and store.has_preset(name):
                continue
            var result := SaKppImport.import_preset(preset, store, template)
            if String(result.get("error", "")).is_empty() and not String(result.get("name", "")).is_empty():
                written += 1
        store.record_offered(RECORD, title)
    return written


## The title *presets*, read from the bundle at *path*, carry, or the file's own
## name when its `meta.xml` gives none, or empty when nothing in it could be read.
static func title_of(presets: Array[Dictionary], path: String) -> String:
    var readable := false
    for preset: Dictionary in presets:
        if not String(preset.get("error", "")).is_empty():
            continue
        readable = true
        var bundle: Variant = preset.get("bundle", null)
        if bundle is Dictionary:
            var title := String((bundle as Dictionary).get("title", "")).strip_edges()
            if not title.is_empty():
                return title
    return path.get_file().get_basename() if readable else ""
