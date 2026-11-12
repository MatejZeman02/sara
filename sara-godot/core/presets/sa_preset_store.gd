## Named brush presets on disk: save, load, list, tag and delete.
##
## A preset is one `.tres` under `user://brush_presets`, holding a detached copy
## of whatever settings resource the active tool carries. This is the first thing
## in Sara to write a resource rather than a `ConfigFile`, so three findings are
## recorded here rather than left to be rediscovered.
##
## `brush_settings.gd` needs no `class_name` to round-trip. A `.tres` names the
## script in an `[ext_resource]` by path, so the instance comes back with its
## script attached and its `GammaFloat` sub-resources rebuilt. What that does
## cost is a hard dependency on the module: a preset saved from the base
## module's brush cannot load with that module absent, which is correct, because
## the settings it describes would have nowhere to go.
##
## The colour is deliberately excluded. `brush_settings.gd` bundles the palette
## in with the brush, and a preset that repainted the current colour every time
## it was loaded would be a worse tool than one that leaves it alone. `exposure`
## and `blend_mode` are kept, because they describe the brush rather than the
## palette.
##
## The store is one library rather than one per tool. Brush and fill already
## share a settings object and the eraser has its own, so keying presets by tool
## would give the same object two lists and split the eraser off from a brush it
## is otherwise identical to. A preset is applied to whichever settings resource
## is in front of the user.
class_name SaPresetStore
extends RefCounted

## Beside `docker_layout.cfg` rather than beside `settings.cfg`, because presets
## are the user's own content but they are not a preference, and the profile
## file has migrations that a directory of resources does not want. A folder
## under the data root, asked through [method default_dir].
const DEFAULT_FOLDER: String = "brush_presets"

## Where a saved gradient goes. Beside `brush_presets` rather than inside it:
## `list_names()` reads a directory, so one directory holding two kinds of
## resource would offer a painter a brush in the gradient list.
const GRADIENT_FOLDER: String = "gradient_presets"

const EXTENSION: String = ".tres"

## Settings a preset does not carry. See the note above on colour.
const EXCLUDED_KEYS: Array[String] = ["color"]

## Where a preset's description is kept, for a writer outside this package
## that names one, the brush editor's Save among them. [SaPresetMeta]'s key,
## spelled here because the store is the package's door.
const DESCRIPTION_META: StringName = SaPresetMeta.DESCRIPTION_META

## The six keys a preset carries about itself, its tags, its engine, its
## sentence, its bundle, its licence and its source, are declared once in
## [SaPresetMeta]. Metadata rather than fields, because the resource saved
## is the module's settings and none of the six is a brush setting, so
## `copy_settings()` never carries one onto the live brush.

## Where presets are read and written. A test points this somewhere disposable,
## which is the only reason it is a variable rather than the folder above.
var dir: String = default_dir()

## Whether a load leaves the target's blend mode alone. A preset carries its
## mode on purpose, since the mode describes the brush, and this is the
## painter saying the one they picked is theirs. On the store rather than read
## from the profile here, so the bar mirrors the setting onto it and a test
## can flip it without writing anyone's preferences.
var keep_blend_mode: bool = false

## Preset name -> what the tag row and the presets docker ask of it, so neither
## loads every resource each time it is rebuilt.
##
## **One load answers all of it.** Four caches stood here, the tags, the engine,
## the shipped sentence and the provenance, each filled by a load of its own, and
## the docker's mark of a cell asked all four and loaded the preset once more to
## learn whether it erases. A load is about 3 ms on a slower machine, so a cell cost five
## of them, and the docker's grid of fifty-two was the 0.4 s frame after Ready
## on every start, warm or cold.
var _facts: Dictionary[String, SaPresetMeta.Facts] = {}

## What each bundle has offered this profile, built on the first ask and kept:
## the bar asks on every refresh, and this is what makes the second ask cost
## no file read. Null until asked, because a test points `dir` elsewhere first
## and this is the record of the directory it was built on. One record for
## every asker, the recipes here and a module's bundles through
## [method offered], so no second record is ever built over this folder.
var _ledger: SaPresetLedger = null

## The build `_build` names, kept for the run.
static var _build_named: String = ""

## How many times this store has listed its folder. Read by the suite that
## switches tools twenty times and finds one listing, and written here only.
var listings: int = 0

## How many times this store has read a preset from disk. Read by the suite that
## finds a chooser cell costs one read, and written here only.
var loads: int = 0

## The folder's names as last listed, sorted, and what they were listed against:
## the folder, its modified time then, and the second the listing was taken.
## `_listed_dir` empty means nothing is kept.
var _listing := PackedStringArray()
var _listed_dir: String = ""
var _listed_mtime: int = 0
var _listed_at: int = 0

## The template scripts whose shipped recipes have been checked against this
## folder, keyed by the folder, the template's script and the recipes' script,
## so a second switch to a tool does not build and test every recipe again.
var _shipped_checked: Dictionary[String, bool] = {}


## A store pointed at the saved gradients rather than the brush presets.
##
## A factory rather than a second class. Everything a named library needs is
## already here, listing, saving, loading and deleting a resource by name, and
## the only thing a gradient does differently is which directory it reads. The
## brush-specific parts, `install_shipped` and `keep_blend_mode`, are simply not
## called: a gradient store that inherited them would have to explain why.
static func for_gradients() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = gradient_dir()
    return store


## Where the brush presets are, under the data root.
static func default_dir() -> String:
    return SaDataRoot.path(DEFAULT_FOLDER)


## Where the saved gradients are, under the data root.
static func gradient_dir() -> String:
    return SaDataRoot.path(GRADIENT_FOLDER)


## Every saved preset, sorted, without the file extension.
##
## The file name is the preset name. Reading the display name out of each file's
## `resource_name` instead would mean loading every preset, and its script and
## sub-resources with it, every time the dropdown is rebuilt.
##
## **Listed once and kept**. A tool switch asked for this list
## four or five times, from the bar's tags, its filter, the chooser's tags and
## its grid, and every ask was a listing of the folder. The listing is read
## again when this store saved or deleted a preset, when [method forget_tags]
## says something outside it touched the folder, and when the folder's modified
## time moved, which is how a preset deleted from a file manager is gone at the
## next switch. A copy is answered, so a caller sorting or trimming it edits
## nothing kept here.
func list_names() -> PackedStringArray:
    if not _listing_is_fresh():
        _listing = _read_listing()
    return _listing.duplicate()


func has_preset(preset_name: String) -> bool:
    var stored := sanitize_name(preset_name)
    return not stored.is_empty() and list_names().has(stored)


## The stored name *preset_name* means with case folded, see [SaPresetNames].
func taken_as(preset_name: String) -> String:
    return SaPresetNames.taken_as(list_names(), preset_name)


## Writes *settings* under *preset_name*, overwriting a preset of that name.
## Returns the name it was actually stored under, or an empty string on failure.
##
## The name comes back rather than a bool because sanitizing can change it, and
## the dropdown has to select the row that now exists rather than the row the
## user typed.
##
## *tags* are written into the file's metadata. Empty keeps whatever the preset
## of that name already had, so saving over a preset from the bar does not
## silently untag it. *metadata* is written into the file's metadata beside the
## tags, key by key: a Krita bundle's licence text and the file a preset was
## imported from, which a preset carries the way it carries its tags, in its
## own file, and `meta_for` reads back. Keys not named are kept as they were.
func save_preset(
    preset_name: String, settings: Resource, tags: PackedStringArray = PackedStringArray(), metadata: Dictionary = {}
) -> String:
    var stored := sanitize_name(preset_name)
    if stored.is_empty() or settings == null:
        return ""
    var kept_tags := tags if not tags.is_empty() else tags_for(stored)
    if not _ensure_dir():
        return ""

    # A detached copy, never the live resource. The base module hands one
    # settings instance to every surface, so saving that object directly would
    # tie the shared brush to a file on disk and leave the preset's sub-resources
    # aliased to the ones the sliders are still writing to.
    var copy := _detached_copy(settings)
    if copy == null:
        return ""
    copy.resource_name = stored
    if not kept_tags.is_empty():
        copy.set_meta(SaPresetMeta.TAGS_META, kept_tags)
    # The engine on every save and from the settings' own script, so the
    # importer and the shipped set carry one without a line of their own. Before
    # *metadata*, which may name another on purpose.
    var engine := SaPresetMeta.engine_of(settings)
    if not String(engine).is_empty():
        copy.set_meta(SaPresetMeta.ENGINE_META, engine)
    # The description too is the file's, kept like the tags when the writer names none.
    if not metadata.has(SaPresetMeta.DESCRIPTION_META) and not about_for(stored).is_empty():
        copy.set_meta(SaPresetMeta.DESCRIPTION_META, about_for(stored))
    for key: Variant in metadata:
        copy.set_meta(StringName(str(key)), metadata[key])
    var saved := ResourceSaver.save(copy, _path_for(stored))
    _forget_listing()
    if saved != OK:
        return ""
    _facts.erase(stored)
    return stored


## One metadata value off a preset's file, or *fallback* when the preset or
## the key is not there. A file read per ask, because the licence is read
## when a painter asks about one preset and not per row.
func meta_for(preset_name: String, key: StringName, fallback: Variant = null) -> Variant:
    var preset := load_preset(preset_name)
    if preset == null or not preset.has_meta(key):
        return fallback
    return preset.get_meta(key)


## The tags on one preset, sorted, empty when it has none or does not exist.
##
## Cached, because the tag row is rebuilt whenever the dropdown is and reading
## a tag means loading the resource, its script and its sub-resources. The
## cache is dropped by every write and by `forget_tags()`, which is what a
## caller uses when something outside this store has touched the directory.
func tags_for(preset_name: String) -> PackedStringArray:
    var stored := sanitize_name(preset_name)
    if stored.is_empty():
        return PackedStringArray()
    return _facts_of(stored).tags


## Reads what the tag row and the presets docker ask of *preset_name*, with one
## load, unless it is known already, and answers whether it loaded. The boot
## asks it of each preset a few a frame before the docker builds its grid, so
## the frame the grid is built in loads nothing.
func learn(preset_name: String) -> bool:
    var stored := sanitize_name(preset_name)
    if stored.is_empty() or _facts.has(stored):
        return false
    _facts_of(stored)
    return true


## Reads every listed preset this store has not read yet, the first of them
## whatever the time and the rest until `Time.get_ticks_usec()` passes
## *deadline_usec*, and answers whether every one is read. The boot's
## `prepare_scan` asks a frame's share at a time, so the scan after it finds
## each preset read.
func learn_listed(deadline_usec: int) -> bool:
    var first := true
    for stored: String in list_names():
        if _facts.has(stored):
            continue
        if not first and Time.get_ticks_usec() > deadline_usec:
            return false
        first = false
        _facts_of(stored)
    return true


## What *stored* says of itself, loaded the first time it is asked.
func _facts_of(stored: String) -> SaPresetMeta.Facts:
    if not _facts.has(stored):
        _facts[stored] = SaPresetMeta.Facts.new(load_preset(stored))
    return _facts[stored]


## Every tag any preset carries, sorted and without repeats.
func all_tags() -> PackedStringArray:
    var seen: Dictionary[String, bool] = {}
    for stored_name: String in list_names():
        for tag: String in tags_for(stored_name):
            seen[tag] = true
    var tags := PackedStringArray(seen.keys())
    tags.sort()
    return tags


## The presets carrying *tag*, or every preset when *tag* is empty.
func names_tagged(tag: String) -> PackedStringArray:
    if tag.is_empty():
        return list_names()
    var matching := PackedStringArray()
    for stored_name: String in list_names():
        if tags_for(stored_name).has(tag):
            matching.append(stored_name)
    return matching


## Drops what this remembers about which preset carries which tag, which engine
## each was written for, its shipped sentence and where each one came from, and
## the listing of the folder, since a caller says this when something outside
## the store has touched the folder.
func forget_tags() -> void:
    _forget_listing()
    _facts.clear()


## The engine *preset_name* was written for, empty when there is no such
## preset. A preset from before engines were named is stamped by the read
## itself.
func engine_for(preset_name: String) -> StringName:
    var stored := sanitize_name(preset_name)
    if stored.is_empty():
        return &""
    return _facts_of(stored).engine


## What *preset_name* says it lays and what it is for, [method
## SaPresetMeta.description_of] off the one load the store keeps, empty when its
## file says nothing. As the file holds it, so a caller showing it passes it
## through [method SaPresetMeta.description_said].
func about_for(preset_name: String) -> String:
    var stored := sanitize_name(preset_name)
    if stored.is_empty():
        return ""
    return _facts_of(stored).description


## *text*, a description as [method about_for] answers it, as the painter
## reads it, [method SaPresetMeta.description_said].
static func description_said(text: String) -> String:
    return SaPresetMeta.description_said(text)


## The line saying where *preset_name* came from and under what licence, or empty
## when its own file says nothing. The sentence is [SaPresetMeta]'s, so the
## cells' tooltips and the line under the grid cannot spell it two ways.
func provenance_for(preset_name: String) -> String:
    return SaPresetMeta.provenance_said(origin_for(preset_name))


## What *preset_name* says of where it came from, [method SaPresetMeta.origin]'s
## six strings off the one load the store keeps, all empty for no such preset.
func origin_for(preset_name: String) -> PackedStringArray:
    var stored := sanitize_name(preset_name)
    return _facts_of(stored).origin if not stored.is_empty() else SaPresetMeta.origin(null)


## Whether *preset_name* takes paint away rather than laying it: its blend mode
## is the layer's erase, which is what the eraser tool sets on a brush and what
## the shipped Eraser and Soft Eraser carry. Any engine's settings may carry
## one, so it is asked by name rather than of a class. False when there is no
## such preset.
func erases(preset_name: String) -> bool:
    var stored := sanitize_name(preset_name)
    return not stored.is_empty() and _facts_of(stored).erases


## The engine a tool takes presets of: the `PRESET_ENGINE` *settings*'s script
## declares, or empty when it declares one nowhere.
##
## **Not [method SaPresetMeta.engine_of]**, which answers the id a settings
## resource is told apart by and falls back to the script's global name so a
## third-party script that declares nothing still has one of its own. That name
## is a refusal's business and never an engine: the gradient's `SaGradientEnds`
## read as an engine called `Sa Gradient Ends`, every cell of the presets grid was
## dimmed under it, and a save wrote a preset of it that no tool could load. A
## tool that declares no engine takes no presets at all.
##
## On the store rather than in [SaPresetMeta], because both files that ask it sit
## outside `core/presets` and a facade is what they may name, and because the
## store is already the door that decides which engine a preset is written for.
static func preset_engine_of(settings: Resource) -> StringName:
    var script: Script = settings.get_script() if settings != null else null
    return SaPresetMeta.declared_engine(script)


## Why *preset_name* will not apply to *target*, as the sentence a painter reads,
## or empty when it will. Two named engines that differ are refused and nothing
## else is, because `copy_settings` across engines writes whatever names happen
## to match and drops the rest without a word.
func refusal(preset_name: String, target: Resource) -> String:
    var wrote := engine_for(preset_name)
    var takes := SaPresetMeta.engine_of(target)
    if String(wrote).is_empty() or String(takes).is_empty() or wrote == takes:
        return ""
    return (
        tr("'%s' is a %s preset, and this tool takes %s presets")
        % [sanitize_name(preset_name), SaPresetMeta.engine_name(wrote), SaPresetMeta.engine_name(takes)]
    )


## The engines *preset_name* can become, the store's question of the converter
## registry: every engine a module registered a converter to
## from the engine the preset was written for, in registration order. Empty
## for a preset that names no engine, one that is not there, and every preset
## while no module registers a converter, which is why a build without one
## adds nothing to the preset's menu.
##
## The registry is handed in rather than held, because the store is built in
## four places and under `core/presets`, and only the menu that asks knows
## where the registries are.
func conversions_for(preset_name: String, converters: SaConverterRegistry) -> Array[StringName]:
    if converters == null or not has_preset(preset_name):
        return []
    var engine := engine_for(preset_name)
    if String(engine).is_empty():
        return []
    return converters.targets_from(engine)


## Converts *preset_name* into a preset of *to_engine* with the registered
## converter, and saves it as a new preset beside the original, never over
## it. Answers the new preset's name, or empty when there is no converter,
## no such preset, or the converter answered nothing of the target engine.
##
## The converter is handed the preset as loaded, a fresh resource off disk,
## so whatever it does to that object the original file is untouched. The new
## preset is named after the original and the engine, "Soft round (Noise)",
## with a number after it when that name is taken, so a second conversion is a
## second preset rather than a save over the first.
##
## What the store carries itself, whatever the converter wrote: the original's
## tags, and where it came from, its bundle, licence and source, because a
## converted preset is still the bundle author's work and the provenance line
## has to say so. Any metadata the converter set on what it answered goes on
## the new file too, tags added to the original's rather than replacing them,
## which is where a converter says what it could not carry. The engine is the
## target's, written last, so a converter that forgot to set one still yields a
## preset the target's tools take.
func convert_preset(preset_name: String, to_engine: StringName, converters: SaConverterRegistry) -> String:
    if converters == null or not has_preset(preset_name):
        return ""
    var from_engine := engine_for(preset_name)
    var converter := converters.converter_for(from_engine, to_engine)
    if not converter.is_valid():
        return ""
    var source := load_preset(preset_name)
    var answered: Variant = converter.call(source)
    var converted: Resource = answered if answered is Resource else null
    if converted == null:
        push_warning(
            "SaPresetStore: the converter from '%s' to '%s' answered nothing for '%s'." % [from_engine, to_engine, preset_name]
        )
        return ""
    var converted_script: Script = converted.get_script()
    var declared := SaPresetMeta.declared_engine(converted_script)
    if not String(declared).is_empty() and declared != to_engine:
        push_warning(
            (
                "SaPresetStore: the converter from '%s' to '%s' answered a '%s' preset, and nothing was saved."
                % [from_engine, to_engine, declared]
            )
        )
        return ""
    var metadata: Dictionary[StringName, Variant] = {}
    for key: StringName in SaPresetMeta.CONVERTED_KEYS:
        if source.has_meta(key):
            metadata[key] = source.get_meta(key)
    for key: StringName in converted.get_meta_list():
        metadata[key] = converted.get_meta(key)
    var tags := tags_for(preset_name).duplicate()
    if converted.has_meta(SaPresetMeta.TAGS_META):
        var carried: PackedStringArray = converted.get_meta(SaPresetMeta.TAGS_META)
        for tag: String in carried:
            if not tags.has(tag):
                tags.append(tag)
    metadata.erase(SaPresetMeta.TAGS_META)
    metadata[SaPresetMeta.ENGINE_META] = to_engine
    return save_preset(_converted_name(preset_name, to_engine), converted, tags, metadata)


## An engine's id the way a painter reads it, for a Convert to row. Through the
## store, which is the package's door, rather than from [SaPresetMeta].
static func engine_label(engine: StringName) -> String:
    return SaPresetMeta.engine_name(engine)


## "<original> (<engine>)", numbered from 2 while the name is taken.
func _converted_name(preset_name: String, to_engine: StringName) -> String:
    var base := "%s (%s)" % [sanitize_name(preset_name), SaPresetMeta.engine_name(to_engine)]
    var wanted := base
    var number := 2
    while has_preset(wanted):
        wanted = "%s %d" % [base, number]
        number += 1
    return wanted


## Puts *tag* on *preset_name*, answering whether the file changed.
##
## False for a tag the preset already carries, for an empty tag, for a word an
## auto tag says and for a preset that is not there, so a caller can say "nothing to do" apart from "it failed".
func assign_tag(preset_name: String, tag: String) -> bool:
    var wanted := sanitize_tag(tag)
    var stored := sanitize_name(preset_name)
    if wanted.is_empty() or not has_preset(stored) or SaPresetTagMap.is_auto(self, wanted):
        return false
    var tags := tags_for(stored)
    if tags.has(wanted):
        return false
    tags.append(wanted)
    tags.sort()
    return _write_tags(stored, tags)


## Takes *tag* off *preset_name*, answering whether the file changed.
func unassign_tag(preset_name: String, tag: String) -> bool:
    var wanted := sanitize_tag(tag)
    var stored := sanitize_name(preset_name)
    if wanted.is_empty() or not has_preset(stored):
        return false
    var tags := tags_for(stored)
    var at := tags.find(wanted)
    if at < 0:
        return false
    tags.remove_at(at)
    return _write_tags(stored, tags)


## Renames *tag* to *wanted* across the library, answering how many presets it
## rewrote.
##
## **A rename onto a tag that already exists merges rather than duplicating.**
## Renaming Inks to Wet on a preset already tagged Wet leaves one Wet, because
## the tags on a preset are a set and a painter who typed an existing word meant
## the two to be one thing. A preset carrying both is rewritten all the same, so
## the count says what moved.
##
## The whole library is walked and only the presets carrying the tag are
## written, which is one file read per preset and one write per carrier, under a
## tenth of a second on a painter's library.
func rename_tag(tag: String, wanted: String) -> int:
    var was := sanitize_tag(tag)
    var now := sanitize_tag(wanted)
    if was.is_empty() or now.is_empty() or was == now or SaPresetTagMap.is_auto(self, now):
        return 0
    var rewritten := 0
    for stored_name: String in names_tagged(was):
        var tags := tags_for(stored_name)
        var at := tags.find(was)
        if at < 0:
            continue
        tags.remove_at(at)
        if not tags.has(now):
            tags.append(now)
        tags.sort()
        if _write_tags(stored_name, tags):
            rewritten += 1
    return rewritten


## Takes *tag* off every preset carrying it, answering how many it rewrote.
##
## The presets stay. A tag is a way of finding a brush and never the brush, so
## deleting one that thirty presets carry must not be a way of deleting thirty
## presets, and the chooser's question says as much.
func delete_tag(tag: String) -> int:
    var doomed := sanitize_tag(tag)
    if doomed.is_empty():
        return 0
    var rewritten := 0
    for stored_name: String in names_tagged(doomed):
        if unassign_tag(stored_name, doomed):
            rewritten += 1
    return rewritten


## A tag reduced to what may be written on a preset: the edges trimmed and the
## inner runs of blank collapsed to one space.
##
## Not `validate_filename`, which is what a preset name goes through, because a
## tag is metadata inside a file and never a file name of its own. So a tag may
## hold a slash or a colon and "Inks / wet" stays the words the painter typed.
static func sanitize_tag(tag: String) -> String:
    var cleaned := ""
    for part: String in tag.split(" ", false):
        cleaned += part if cleaned.is_empty() else " " + part
    return cleaned.strip_edges()


## Writes *tags* onto the stored preset's own file, answering whether it landed.
##
## The resource is loaded, its metadata moved and the file written back, rather
## than going through `save_preset`, which needs the live settings resource a
## caller changing a tag does not have. Everything else in the file, the licence
## a Krita import left and the file it came from, is carried across because the
## resource written back is the one that was read.
##
## An empty list erases the key rather than writing an empty array, so a preset
## that has been untagged reads the same as one that was never tagged.
func _write_tags(stored_name: String, tags: PackedStringArray) -> bool:
    var preset := load_preset(stored_name)
    if preset == null:
        return false
    if tags.is_empty():
        # Asked first: Godot's `remove_meta` on a key that is not there is an
        # error rather than a no-op, and an untagged preset reaching here is the
        # ordinary case of taking the last tag off one.
        if preset.has_meta(SaPresetMeta.TAGS_META):
            preset.remove_meta(SaPresetMeta.TAGS_META)
    else:
        preset.set_meta(SaPresetMeta.TAGS_META, tags)
    if ResourceSaver.save(preset, _path_for(stored_name)) != OK:
        return false
    _facts.erase(stored_name)
    return true


## Writes the shipped presets this profile has not been offered yet, and answers
## how many it wrote.
##
## **Per bundle and once each.** The store's ledger holds what each bundle has
## offered: a name in its marker has been offered and is not written again,
## whatever became of the file, so a preset the painter deleted stays deleted,
## and a name in neither the marker nor the directory is new, which is a build
## shipping a set this profile has never seen. Writing only into a directory
## that does not exist would cost a `dir_exists` per refresh and never add such a
## set: after the first run the directory is always there.
##
## *template* is the live settings resource, and each shipped preset is **that
## resource's script at its own defaults** plus the values its recipe names, so
## the shipped presets are never the brush that happened to be loaded, with the
## painter's curves baked into Sketch, and carry the pen settings a new brush
## carries. **A recipe the script cannot carry is skipped**, rather than shipped
## as a plain round wearing its name. Each written preset carries its recipe's
## sentence as `about`, the bundle as `bundle`, the licence `licence_for` gives
## it as `licence`, and the bundle's fields of `SaPresetMeta.BUNDLE_FIELDS` the
## entry names, so a painter reading a tooltip reads what the bundle says they
## may do with it.
##
## **The recipes are the caller's**. *recipes* is the script the caller got from
## the `shipped_presets` role, and it is a script rather than the bare table
## because how a module's recipes are built, its `build` over the shared
## `SaPresetRecipe` reader, travels with the table. Preloading a recipe
## file here would put the stamp brush's own field paths in the skeleton. A
## build with no stamp brush registers no role, so the caller hands this null
## and nothing is installed and nothing is said.
##
## **A *deadline_usec* stops it early**, after the first preset written once
## `Time.get_ticks_usec()` has passed it, and the table is then not marked
## checked, so the next ask writes on from there. The boot's `prepare_scan` asks
## a frame's share at a time, because a fresh profile's fifty-two shipped presets
## took 94 ms of one frame after Ready on a slower machine. The answer is how many
## were written, so an ask that writes none has nothing left.
func install_shipped(template: Resource, recipes: Script, deadline_usec: int = -1) -> int:
    if template == null or recipes == null or not SaPresetNames.writable_root(dir):
        return 0
    var script: Script = template.get_script()
    if script == null:
        return 0
    # **Once per template script**. Every tool switch asks, and a
    # recipe checked once answers the same until the folder is another one: it
    # was offered, it is on disk, or the script cannot carry it. The last is
    # the cost, since a template of another script would build and test every
    # recipe on each switch to its tool and write none.
    var checked := "%s|%s|%s" % [dir, script.resource_path, recipes.resource_path]
    if _shipped_checked.has(checked):
        return 0
    # Through `call` rather than `recipes.entries()`, because a `const` and a
    # static are not members of a `Script` value as the type checker sees it.
    var entries: Array = recipes.call("entries")
    # The directory's names as the seed, read before anything is written and
    # only while some bundle of the table has no answer yet, so a refresh after
    # the first costs no file read. A profile that predates the marker was once
    # offered the recipes, and what it holds is the only record it has. The
    # ledger's header says what that costs.
    # A bundle renamed since takes its old names' records first, `formerly`,
    # and the presets filed under them, which is `SaPresetBundleMap`'s.
    SaPresetBundleMap.carry_over(self, _record(), entries)
    # Then its stock presets' tags, once per bundle, `SaPresetTagMap`'s.
    SaPresetTagMap.carry_over(self, _record(), entries)
    var unknown := false
    for raw_entry: Variant in entries:
        unknown = unknown or not _record().knows(SaTyped.text_at(SaTyped.strings(raw_entry), "bundle", ""))
    var on_disk := list_names() if unknown else PackedStringArray()
    var written := 0
    var failed := false
    # A recipe table is a module's own untyped code, typed here where it enters.
    for raw_entry: Variant in entries:
        var entry := SaTyped.strings(raw_entry)
        var name := SaTyped.text_at(entry, "name", "")
        var bundle := SaTyped.text_at(entry, "bundle", "")
        # The whole of the "once": offered already, or on disk under that name,
        # which is a preset the painter saved or edited themselves, unless the
        # file is one a build before this one shipped and nobody touched since.
        if (offered(bundle, on_disk).has(name) or has_preset(name)) and not _stale_shipped(entry, bundle, name):
            continue
        var settings: Resource = recipes.call("build", script, entry)
        if settings == null:
            continue
        var about := {SaPresetMeta.DESCRIPTION_META: entry.get("description", entry.get("about", ""))}
        about[SaPresetMeta.BUNDLE_META] = bundle
        # The bundle's licence, written once from the table that names it rather
        # than repeated on the twenty-one recipes. A bundle the table does not
        # know writes no key, which is honest where an empty sentence is not.
        # A recipe naming its own licence wins, since a bundle may gather tables
        # of two licences.
        var licence := SaTyped.text_at(entry, "licence", SaTyped.text(recipes.call("licence_for", bundle)))
        if not licence.is_empty():
            about[SaPresetMeta.LICENCE_META] = licence
        for field: StringName in SaPresetMeta.BUNDLE_FIELDS:
            if not SaTyped.text_at(entry, String(field), "").is_empty():
                about[field] = SaTyped.text_at(entry, String(field), "")
        var tags: PackedStringArray = entry.get("tags", PackedStringArray())
        if save_preset(name, settings, tags, about).is_empty():
            failed = true
            continue
        record_offered(bundle, name, on_disk)
        _record().record_written(bundle, name, SaPresetLedger.fingerprint(_path_for(sanitize_name(name))), _build())
        written += 1
        if deadline_usec >= 0 and Time.get_ticks_usec() > deadline_usec:
            return written
    # A write that failed is tried again on the next ask, as it always was.
    if not failed:
        _shipped_checked[checked] = true
    return written


## Whether the preset *name* on disk is a copy an earlier build shipped and the
## painter never touched, so the current recipe may take its place.
##
## **Asked once per build and name.** A name this build has looked at answers
## no from the record without reading the file. Otherwise the file is read: it
## is stale when its fingerprint is the one Sara recorded at its last write, or
## one the recipe's `shipped_before` lists, a version shipped before Sara kept a
## record. A file that is neither is the painter's, and the record says so, so
## it is never read again until the next build. A copy the painter edited is
## therefore never written over, and a corrected recipe reaches every profile
## that kept the old one as it came.
func _stale_shipped(entry: Dictionary[String, Variant], bundle: String, name: String) -> bool:
    var held := _record().written(bundle, name)
    if held[1] == _build() or not has_preset(name):
        return false
    var found := SaPresetLedger.fingerprint(_path_for(sanitize_name(name)))
    var before := PackedStringArray()
    var raw_before: Variant = entry.get("shipped_before", [])
    if raw_before is PackedStringArray:
        before = raw_before
    elif raw_before is Array:
        var listed: Array = raw_before
        before = PackedStringArray(listed)
    if not found.is_empty() and (found == held[0] or before.has(found)):
        return true
    _record().record_written(bundle, name, "", _build())
    return false


## The build a shipped preset's record names: the version and the commit, so a
## build with a corrected recipe looks again and the same build never does.
## Read once a run, because the commit is a file read and every recipe asks.
static func _build() -> String:
    if _build_named.is_empty():
        var info := SaBuildInfo.read()
        _build_named = "%s %s" % [info.get("version", ""), info.get("commit_full", "")]
    return _build_named


## The names *bundle* has offered this profile, sorted.
##
## The record `install_shipped` keeps for the recipes, and the one a module
## keeps for what it installs, so a second door into this directory asks here
## rather than building a record of its own over the same folder.
## *seed_names* is what a bundle with no marker yet is taken to have offered:
## the recipes hand the directory's names, because a profile from before the
## marker was offered them, and a door no profile predates hands nothing,
## which reads a missing marker as an empty one.
func offered(bundle: String, seed_names: PackedStringArray = PackedStringArray()) -> PackedStringArray:
    return _record().offered(bundle, seed_names)


## Records that *bundle* has offered *name* to this profile and writes its
## marker, with *seed_names* as in [method offered].
func record_offered(bundle: String, name: String, seed_names: PackedStringArray = PackedStringArray()) -> void:
    _record().record(bundle, name, seed_names)


## The ledger of the directory the store points at now, built on the first ask.
## Rebuilt when `dir` moved since, so a store a test pointed elsewhere never
## answers from the record of the folder it left.
func _record() -> SaPresetLedger:
    if _ledger == null or _ledger.dir != dir:
        _ledger = SaPresetLedger.new(dir)
    return _ledger


## The stored preset as a fresh resource, or null when there is no such preset.
func load_preset(preset_name: String) -> Resource:
    var stored := sanitize_name(preset_name)
    if stored.is_empty():
        return null
    var path := _path_for(stored)
    if not FileAccess.file_exists(path):
        return null
    # Before the load, because a `.tres` naming a script that has moved does not
    # come back half read: it fails to parse and the preset is gone.
    SaResourceFinder.repair_resource_paths(path)
    # After the repair, which finds a file that only moved, and before the load,
    # because the engine prints an error for every resource a `.tres` names that
    # is gone. A preset written by a build that carried a module this one lacks
    # is left on disk, since the module may come back.
    if SaPresetMissingModule.skips(path, stored):
        return null
    # CACHE_MODE_IGNORE, because the resource cache would hand every caller the
    # same instance. Applying a preset and then moving a slider would otherwise
    # edit what the next load returns.
    var preset := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
    loads += 1
    # A preset from before engines were named names none, so it is given the one
    # its script declares and written back, once. Only a declared one, so a
    # gradient or a third-party preset is not rewritten on a read, and before the
    # migration, so the file gains that one key and nothing the migration would
    # change.
    if preset != null and not preset.has_meta(SaPresetMeta.ENGINE_META):
        var preset_script: Script = preset.get_script()
        var engine := SaPresetMeta.declared_engine(preset_script)
        if not String(engine).is_empty():
            preset.set_meta(SaPresetMeta.ENGINE_META, engine)
            # And repaired again, because the saver writes its own `ext_resource`
            # lines and the repair above is what promises they carry a uid.
            if ResourceSaver.save(preset, path) == OK:
                SaResourceFinder.repair_resource_paths(path)
    # A settings resource that knows how to bring itself up to date is asked to,
    # once, here. The store still treats a preset as an opaque resource: it asks
    # whether the object has a migration rather than what kind of object it is,
    # so a third-party tool's settings get the same offer and one that has no
    # migration is handed back untouched.
    if preset != null and preset.has_method("migrate"):
        preset.call("migrate")
    return preset


## Copies a stored preset onto *target*, in place. False when it does not exist.
##
## In place rather than by replacement, because the settings object is shared
## across surfaces and swapping it would leave the scratchpad's brush pointing at
## the old one.
func apply_preset(preset_name: String, target: Resource) -> bool:
    if target == null:
        return false
    var refused := refusal(preset_name, target)
    if not refused.is_empty():
        # In the canvas corner, the way a refused stroke is, so a painter who
        # pressed a dimmed cell learns why nothing happened. Here rather than in
        # the docker, because the bar's load, a chord and a scenario all come
        # through this door as well. On the bus a refused stroke speaks on,
        # because the store is under `core` and the notice is the interface's.
        EventBus.paint_refused.emit(refused)
        return false
    var started := Time.get_ticks_usec()
    var preset := load_preset(preset_name)
    if preset == null:
        return false
    # Keep Blend Mode keeps the painter's mode across presets that paint, a
    # blend mode being a look laid over the paint that the painter chose. Erase
    # is no look but what an eraser preset is for: kept away, the shipped Eraser
    # loaded as a hard round in Normal and painted the colour in hand. So an
    # erasing preset sets Erase whatever the switch says, and
    # `SaBrushPresetErase` gives the painter's mode back after it.
    var kept: Array[String] = []
    if keep_blend_mode and not erases(preset_name):
        kept.append("blend_mode")
    copy_settings(preset, target, kept)
    SaTrail.mark("the preset %s applied in %d ms" % [preset_name, int((Time.get_ticks_usec() - started) / 1000.0)])
    return true


func delete_preset(preset_name: String) -> bool:
    if not has_preset(preset_name):
        return false
    _facts.erase(sanitize_name(preset_name))
    # The one hook. A thumbnail is a rendered stroke and is disposable, so it is
    # removed rather than left for a rebuild to notice: an orphan PNG under
    # `.thumbs` outlives the preset it was drawn for and nothing else would ever
    # look at it again.
    SaPresetThumbs.forget(dir, preset_name)
    var removed := DirAccess.remove_absolute(_path_for(sanitize_name(preset_name))) == OK
    _forget_listing()
    return removed


## Copies every stored setting from *source* onto *target*, minus EXCLUDED_KEYS.
##
## Both directions of the preset path go through this, so what a preset carries
## is decided once. A property the target does not have is skipped rather than
## pushed, which is what lets a preset saved from one tool's settings be applied
## to another's.
## *kept* names settings of the target that the copy leaves as they are, on
## top of the ones a preset never carries.
static func copy_settings(source: Resource, target: Resource, kept: Array[String] = []) -> void:
    if source == null or target == null:
        return
    for raw_property: Variant in source.get_property_list():
        var property := SaTyped.strings(raw_property)
        var usage: int = property["usage"]
        if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or not (usage & PROPERTY_USAGE_STORAGE):
            continue
        var key: String = property["name"]
        if EXCLUDED_KEYS.has(key) or kept.has(key) or not (key in target):
            continue
        var value: Variant = source.get(key)
        # A GammaFloat handed straight across would be one object in two places,
        # so dragging the hardness slider would edit the preset that set it.
        if value is Resource:
            var shared: Resource = value
            value = shared.duplicate(true)
        target.set(key, value)


## The name reduced to something that can be a file name.
##
## Two names that differ only in characters a file system refuses collide here,
## and the second save wins. That is the same behaviour as saving over a preset
## by name, which is what the user asked for in every case anybody will hit.
static func sanitize_name(preset_name: String) -> String:
    var cleaned := preset_name.strip_edges().validate_filename()
    # A leading dot hides the file on every platform Sara targets, and a name of
    # only dots names the directory itself.
    while cleaned.begins_with("."):
        cleaned = cleaned.substr(1)
    return cleaned.strip_edges()


func _path_for(stored_name: String) -> String:
    return dir.path_join(stored_name + EXTENSION)


## Whether the kept listing still says what the folder holds, which costs one
## `stat` of the folder and no listing.
##
## **A listing taken in the second the folder last changed is never trusted.**
## A modified time counts whole seconds, so a file deleted later in that same
## second leaves it where it was and the listing would keep the name for good.
## Git calls this a racy entry and answers it the same way: such a listing is
## read again on the next ask, until one is taken in a later second than the
## change, and from then on any change moves the time past what was kept.
func _listing_is_fresh() -> bool:
    if _listed_dir != dir:
        return false
    return _listed_mtime < _listed_at and _folder_mtime() == _listed_mtime


## The folder's names, read from disk, sorted, and recorded as the kept listing.
## A folder that is not there lists nothing, and is kept as nothing with a time
## of zero, so its creation moves the time and is seen.
func _read_listing() -> PackedStringArray:
    var names := PackedStringArray()
    _listed_at = int(Time.get_unix_time_from_system())
    _listed_mtime = _folder_mtime()
    _listed_dir = dir
    listings += 1
    if not DirAccess.dir_exists_absolute(dir):
        return names
    for file_name: String in DirAccess.get_files_at(dir):
        if file_name.ends_with(EXTENSION):
            names.append(file_name.trim_suffix(EXTENSION))
    names.sort()
    return names


## The folder's modified time in seconds, zero when it is not there.
func _folder_mtime() -> int:
    return int(FileAccess.get_modified_time(dir))


## Drops the kept listing, so the next ask lists the folder. What every save and
## delete of this store calls, so the answer after its own write never rests on
## the folder's clock, which a filesystem with coarser times than a second would
## leave behind.
func _forget_listing() -> void:
    _listed_dir = ""


func _ensure_dir() -> bool:
    if not SaPresetNames.writable_root(dir):
        return false
    if DirAccess.dir_exists_absolute(dir):
        return true
    return DirAccess.make_dir_recursive_absolute(dir) == OK


## A new instance of the same script carrying only what a preset keeps.
##
## Built empty and filled rather than duplicated and stripped, so an excluded
## setting is left at its script default. A default is not written to a `.tres`
## at all, which is why the saved file has no `color` line rather than a
## misleading white one.
func _detached_copy(settings: Resource) -> Resource:
    var script: GDScript = settings.get_script()
    if script == null:
        return null
    var built: Variant = script.new()
    var copy: Resource = built if built is Resource else null
    if copy == null:
        return null
    copy_settings(settings, copy)
    return copy
