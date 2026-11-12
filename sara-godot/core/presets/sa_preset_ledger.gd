## What each shipped bundle has offered a profile, one marker file per bundle
## inside the presets directory.
##
## **A marker rather than the directory's absence.** "Write the shipped presets
## when the presets directory is not there" costs a `dir_exists` per refresh and
## can never add a set a later build ships: after the first run the directory is
## always there. A recipe whose
## name is in the marker has already been offered, a name in neither the marker
## nor the directory is new and is written, and a preset the painter deleted is
## in the marker and stays deleted.
##
## **The seed is the asker's.** A profile older than the marker has presets
## and no marker, and nothing on disk tells a preset the painter deleted from one
## that was never installed. For the recipes the directory is the only answer
## there is, so the store hands its own names in as the seed, and the first ask
## on such a profile takes them as the record and writes it. One deletion, the
## first, is therefore undone once on a profile that predates the marker.
## Reading the absent marker as an empty one instead is the same coin the other
## way up, and the worse half of it: that brings every deleted preset of every
## profile in the field back on the first launch after the upgrade. A module's
## bundles hand an empty seed, because no profile older than the marker was
## offered a module's bundle, so for them a missing marker is an empty one.
##
## **The store's, and nobody else's**. One record per presets directory, held
## by the store that owns the directory and offered through
## `SaPresetStore.offered` and `SaPresetStore.record_offered`, so a module asks
## the store it is handed rather than building a second record over the same
## folder. The seed is therefore an argument of the ask rather than of the
## record, since one record answers askers who want different ones.
##
## **One file per bundle, and inside the presets directory rather than in a
## folder of its own.** `list_names` takes `.tres` alone, so the chooser never
## sees a marker however it is named. What the name may not be is a *hidden* one:
## `DirAccess.get_files_at` does not return a dot-file, so a marker named `.x`
## is invisible both to a suite that clears that directory by removing the files
## in it and to this class looking for its own record. The suffix is the one
## thing that keeps a marker out of a painter's preset list, and it is a file
## rather than a folder for the same reason: a folder outlives the clearing, and
## the next install would read a record of presets that are no longer there.
##
## **What Sara wrote, beside what it offered.** A second file per bundle,
## `<bundle>.written`, holds for each shipped preset the fingerprint of the file
## Sara last wrote under that name and the build that wrote it, so a later build
## can tell a copy the painter never touched from one they edited, and replace
## only the first. The fingerprint is the file's text with the
## ids Godot draws at random on every save read as their order, because two saves
## of one preset never match byte for byte otherwise.
class_name SaPresetLedger
extends RefCounted

## What a marker file's name ends in, after the bundle's own.
const SUFFIX: String = ".bundle"

## What a bundle's record of written files ends in.
const WRITTEN_SUFFIX: String = ".written"

## The bundle an entry naming none of its own is filed under, so a table from a
## producer that predates the bundle line still installs once and holds its
## deletions.
const UNNAMED: String = "unnamed"

## The presets directory, which is where the markers live.
var dir: String = ""

## Bundle -> the names it has offered, read once and kept. The presets bar asks
## on every refresh, and this is what makes the second ask free.
var _offered: Dictionary[String, PackedStringArray] = {}

## Bundle -> name -> [fingerprint, build] of the file Sara last wrote, read on
## the first ask about the bundle.
var _written: Dictionary[String, Dictionary] = {}


## The record of *preset_dir*.
func _init(preset_dir: String) -> void:
    dir = preset_dir
    for bundle: String in _marked_bundles():
        _offered[bundle] = _read_marker(bundle)


## The names *bundle* has offered this profile, sorted.
##
## The first ask about a bundle with no marker on disk takes *seed_names* as
## its record and writes it, when there is anything to write. The note at the
## top of the file says why that is the answer for the recipes and what it
## costs. The seed is handed in rather than walked here: the store owns what
## counts as a preset in that directory, and a second walk that disagreed with
## it would be a second answer to the same question.
func offered(bundle: String, seed_names: PackedStringArray = PackedStringArray()) -> PackedStringArray:
    var key := stem_for(bundle)
    if not _offered.has(key):
        _offered[key] = seed_names.duplicate()
        if not seed_names.is_empty():
            _write_marker(key, _offered[key])
    return _offered[key]


## Whether *bundle* has an answer yet, a marker read or a first ask made, so a
## caller whose seed costs a directory walk can skip the walk when nothing new
## would take it.
func knows(bundle: String) -> bool:
    return _offered.has(stem_for(bundle))


## Adds *name* to *bundle*'s record and writes the marker, with *seed_names* the
## record's first answer when this is the first ask about *bundle*.
##
## One name at a time, because that is when the store knows one: a preset is
## written and then recorded, so a run that dies in the middle of the twenty-one
## leaves a record of the ones that landed rather than of the ones it meant to.
func record(bundle: String, name: String, seed_names: PackedStringArray = PackedStringArray()) -> void:
    var key := stem_for(bundle)
    var held: PackedStringArray = offered(key, seed_names)
    if held.has(name):
        return
    held.append(name)
    held.sort()
    _offered[key] = held
    _write_marker(key, held)


## The fingerprint and the build of *name*'s last write by Sara, two strings,
## both empty when there is no record.
func written(bundle: String, name: String) -> PackedStringArray:
    var held: Variant = _written_of(bundle).get(name, null)
    return held if held is PackedStringArray else PackedStringArray(["", ""])


## Records that *build* left *name* at *wrote*, an empty fingerprint
## meaning the file is no longer the one Sara wrote, and writes the record.
func record_written(bundle: String, name: String, wrote: String, build: String) -> void:
    var rows := _written_of(bundle)
    rows[name] = PackedStringArray([wrote, build])
    _write_written(stem_for(bundle), rows)


## Takes *former*'s record into *bundle*'s when a bundle was renamed or several
## were gathered into one: what it offered and what Sara wrote under it, so the
## rename brings back no preset the painter deleted and a copy they never
## touched is still known as Sara's, and is written again under the new name by
## the next build. Answers whether *bundle*'s record grew.
##
## **A union rather than a copy**, because seven old bundles became three and
## one of them was split, so Sara Advanced Paint takes the records of five
## and Sara Basic and Sara Advanced Paint both take Sara Essentials'. A name or
## a row *bundle* already holds is kept as it is, so a second ask adds nothing
## and writes nothing, and a profile that never knew *former* is left alone. The
## old files stay where they are, so a build from before the rename that opens
## the same profile finds its record as it left it.
func adopt(bundle: String, former: String) -> bool:
    var key := stem_for(bundle)
    var old := stem_for(former)
    if former.strip_edges().is_empty() or key == old or not _offered.has(old):
        return false
    var names: PackedStringArray = _offered[key].duplicate() if _offered.has(key) else PackedStringArray()
    var grew := not _offered.has(key)
    for name: String in _offered[old]:
        if not names.has(name):
            names.append(name)
            grew = true
    if grew:
        names.sort()
        _offered[key] = names
        _write_marker(key, names)
    var rows: Dictionary = _written_of(bundle).duplicate()
    var more := false
    for name: Variant in _written_of(former):
        if not rows.has(name):
            rows[name] = _written_of(former)[name]
            more = true
    if more:
        _written[key] = rows
        _write_written(key, rows)
    return grew or more


## Writes *rows*, name to fingerprint and build, as the record of written files
## filed under *key*.
func _write_written(key: String, rows: Dictionary) -> void:
    if not DirAccess.dir_exists_absolute(dir) and DirAccess.make_dir_recursive_absolute(dir) != OK:
        return
    var file := FileAccess.open(dir.path_join(key + WRITTEN_SUFFIX), FileAccess.WRITE)
    if file == null:
        return
    var names: Array = rows.keys()
    names.sort()
    var lines := PackedStringArray()
    for held: Variant in names:
        var row: PackedStringArray = rows[held]
        lines.append("%s\t%s\t%s" % [held, row[0], row[1]])
    file.store_string("\n".join(lines) + "\n")


## The fingerprint of the preset file at *path*, or an empty string when there
## is no such file.
##
## **Byte for byte, except for what Godot draws at random.** A save names each
## sub-resource and each external one with an id it makes up, and a file names
## itself with a uid of the same kind, so the same preset saved twice differs in
## those and nothing else. Each id is read as the order it first appears in and
## every uid is dropped, a script's too, since the saver may leave one out that
## the first load writes in, so a preset nobody touched read as edited.
## That leaves every value, curve and word of the preset as it is on disk.
static func fingerprint(path: String) -> String:
    if not FileAccess.file_exists(path):
        return ""
    var text := FileAccess.get_file_as_string(path).replace("\r\n", "\n")
    if text.is_empty():
        return ""
    text = RegEx.create_from_string(' uid="[^"]*"').sub(text, "", true)
    var order := 0
    for found: RegExMatch in RegEx.create_from_string('\\bid="([^"]+)"').search_all(text):
        text = text.replace('"%s"' % found.get_string(1), '"#%d"' % order)
        order += 1
    return text.sha256_text()


## Where *bundle*'s marker is written under *preset_dir*.
##
## The name a bundle is filed under is this file's business rather than
## `SaPresetStore.sanitize_name`'s, which is the rule for a *preset* name, and a
## class that named the store would be the store naming it back.
static func path_for(preset_dir: String, bundle: String) -> String:
    return preset_dir.path_join(stem_for(bundle) + SUFFIX)


## The name a bundle is filed under: its own, reduced to what a file name takes.
static func stem_for(bundle: String) -> String:
    var stem := bundle.strip_edges().validate_filename().strip_edges()
    while stem.begins_with("."):
        stem = stem.substr(1)
    return stem if not stem.is_empty() else UNNAMED


## *bundle*'s record of written files, read from its file on the first ask.
func _written_of(bundle: String) -> Dictionary:
    var key := stem_for(bundle)
    if _written.has(key):
        return _written[key]
    var rows := {}
    var file := FileAccess.open(dir.path_join(key + WRITTEN_SUFFIX), FileAccess.READ)
    while file != null and not file.eof_reached():
        var parts := file.get_line().split("\t")
        if parts.size() == 3 and not parts[0].is_empty():
            rows[parts[0]] = PackedStringArray([parts[1], parts[2]])
    _written[key] = rows
    return rows


## Every bundle this profile already has a marker for.
func _marked_bundles() -> PackedStringArray:
    var found := PackedStringArray()
    if not DirAccess.dir_exists_absolute(dir):
        return found
    for file_name: String in DirAccess.get_files_at(dir):
        if file_name.ends_with(SUFFIX):
            found.append(file_name.trim_suffix(SUFFIX))
    return found


## The names in *bundle*'s marker, one per line, or none when there is no file.
func _read_marker(bundle: String) -> PackedStringArray:
    var names := PackedStringArray()
    var file := FileAccess.open(path_for(dir, bundle), FileAccess.READ)
    if file == null:
        return names
    while not file.eof_reached():
        var line := file.get_line().strip_edges()
        if not line.is_empty() and not names.has(line):
            names.append(line)
    names.sort()
    return names


## Writes *names* as *bundle*'s marker, answering whether it landed.
##
## The directory is made first, because a bundle still to write its first preset
## has no directory yet and the record of what it was offered is worth keeping
## whether or not one of them landed.
func _write_marker(bundle: String, names: PackedStringArray) -> bool:
    if not DirAccess.dir_exists_absolute(dir) and DirAccess.make_dir_recursive_absolute(dir) != OK:
        return false
    var file := FileAccess.open(path_for(dir, bundle), FileAccess.WRITE)
    if file == null:
        return false
    var lines := names.duplicate()
    lines.sort()
    file.store_string("\n".join(lines) + "\n")
    return true
