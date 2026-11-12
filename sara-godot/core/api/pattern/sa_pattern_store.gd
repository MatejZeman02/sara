## The patterns on disk, by name: the shipped folder and the painter's, listed
## once and handed out as [SaPattern] objects.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Beside `core/presets/sa_preset_store.gd` in shape rather than inside it: a preset is
## a `.tres` the store writes, and a pattern is a file somebody else wrote, a
## kernel or a picture, which this only reads. Two folders, the way the tips
## have two: `res://patterns` for the ones Sara ships, and
## `patterns` under the data root for whatever a painter drops in, a `.gmacs` written with
## a language model at hand or a scanned paper as a `.png`. A painter's file
## with a shipped file's name wins, because the painter's folder is read
## second, and a shipped pattern can be replaced without touching Sara.
##
## **A name is a file's stem made readable**, `paper_grain.gmacs` is "Paper
## Grain", which is what a preset stores and what a chooser shows. The path
## is not stored anywhere outside this object, so a painter moving a file
## between the two folders breaks no preset.
##
## The shipped patterns are kernels rather than pictures, text files a reader
## can diff rather than PNGs nobody can, and a pattern is a file in the folder,
## so shipping one is adding one and needs no line here.
##
## **One per module, and it remembers a file it could not read**, because a
## store made by every chooser, capture window and brush lives a rebuild long
## and remembers nothing, so a refused file would be reported again on every
## listing. Each brush module makes its one store at registration and hands it
## out, the stamp's and
## the noise brush's, because the store lives in the door, so a
## refused file is said once by each engine that lists it. A pattern
## that fails to read tells the store through [method refused]. The store
## keeps the file's modification time beside the reason, reports the refusal
## once through `SaProblems`, and hands the reason back from
## [method known_failure] to every pattern object made for that path after a
## rescan, so the file is opened once until it changes on disk. Instance state
## and nothing static, because a static memory outlives the rendering device,
## and a test reads the private
## dictionary from outside rather than through a door built for it.
class_name SaPatternStore
extends RefCounted

## The five Sara ships, and the folder a painter's own go in.
const SHIPPED_DIR: String = "res://patterns"
## A folder name under the data root, which `--settings-dir` moves.
const SAVED_FOLDER: String = "patterns"

## The folders read, in order, the later winning a name both hold. A test
## points a store at a scratch folder through the constructor, which is the
## privates rule's door for a value set from outside.
var _dirs: Array[String] = []

## Name -> the pattern, filled by the first list and dropped by [method rescan].
var _patterns: Dictionary[String, SaPattern] = {}
var _scanned: bool = false

## Path -> the [Refusal] of every file a pattern refused, written here only. The size sits beside the time because
## `FileAccess.get_modified_time` is whole seconds, and a file rewritten within
## the second it was refused in would otherwise read as unchanged.
var _failed: Dictionary[String, Refusal] = {}


## The painter's folder, under the data root.
static func saved_dir() -> String:
    return SaDataRoot.path(SAVED_FOLDER)


func _init(folders: Array[String] = [SHIPPED_DIR, saved_dir()]) -> void:
    _dirs = folders.duplicate()


## Every pattern's name, sorted.
func names() -> PackedStringArray:
    _scan_if_needed()
    var out := PackedStringArray(_patterns.keys())
    out.sort()
    return out


func has(pattern_name: String) -> bool:
    _scan_if_needed()
    return _patterns.has(pattern_name)


## The pattern called *pattern_name*, or null when no file has that name.
func pattern(pattern_name: String) -> SaPattern:
    _scan_if_needed()
    return _patterns.get(pattern_name, null)


## Reads the folders again on the next ask, for a file added while Sara runs.
## A pattern already handed out keeps its texture, and the next [method pattern]
## for the same name answers a new object.
func rescan() -> void:
    _patterns.clear()
    _scanned = false


## A pattern's report that *path* could not be read, with the reader's own
## *reason*. Remembered against the file's modification time and size and said
## once through `SaProblems.report`: a second report for the same file as it
## stands on disk changes nothing and says nothing, and a report for the file
## after it was rewritten replaces the record and is said again.
func refused(path: String, reason: String) -> void:
    var stamp := _stamp(path)
    if _failed.has(path) and _failed[path].stamp == stamp:
        return
    _failed[path] = Refusal.new(stamp, reason)
    SaProblems.report("SaPatternStore", TranslationServer.translate("%s Skipped until the file changes on disk.") % reason)


## The reason *path* was refused, or empty when it was not, or when the file
## has changed or gone since. A record the file has outgrown is dropped here,
## so a mended file is read again on the next ask. Two stats and no open.
func known_failure(path: String) -> String:
    if not _failed.has(path):
        return ""
    var known: Refusal = _failed[path]
    if _stamp(path) != known.stamp:
        _failed.erase(path)
        return ""
    return known.reason


## The name a file is listed under: its stem, words capitalised.
static func name_for(file_name: String) -> String:
    return file_name.get_file().get_basename().capitalize()


## Whether *file_name* is a file a pattern can come from.
##
## A `.pat` is on the list, which is what lets the Krita import write one of
## Krita's bundled papers here instead of tagging the preset. It is listed
## under its file's stem like the rest: a `.pat` carries a name of its own in
## its header, and honouring that would give the store two naming rules and a
## pattern whose file a painter cannot find.
static func is_pattern_file(file_name: String) -> bool:
    var extension := file_name.get_extension().to_lower()
    if extension == SaPattern.PAT_EXTENSION:
        return true
    return extension == SaPattern.KERNEL_EXTENSION or SaPattern.IMAGE_EXTENSIONS.has(extension)


func _scan_if_needed() -> void:
    if _scanned:
        return
    _scanned = true
    for folder: String in _dirs:
        if not DirAccess.dir_exists_absolute(folder):
            continue
        var files := Array(DirAccess.get_files_at(folder))
        files.sort()
        for file: String in files:
            # An exported build ships `.import` beside a picture, and a
            # `.png.import` is not a pattern.
            var clean := file.trim_suffix(".import")
            if not is_pattern_file(clean):
                continue
            var pattern_name := name_for(clean)
            _patterns[pattern_name] = SaPattern.new(pattern_name, folder.path_join(clean), SaPattern.DEFAULT_TILE, {}, self)


## The file's modification time and size, which together say whether it is
## the file that was refused. Both are a stat, neither opens the file, and a
## file that is gone answers nought for both.
static func _stamp(path: String) -> Dictionary[String, int]:
    if not FileAccess.file_exists(path):
        return {"modified": 0, "size": 0}
    return {"modified": FileAccess.get_modified_time(path), "size": FileAccess.get_size(path)}


## A refused file as it stood on disk when it was refused, `_stamp`'s time and
## size, and the reader's reason.
class Refusal:
    extends RefCounted

    var stamp: Dictionary[String, int] = {}
    var reason: String = ""

    func _init(at: Dictionary[String, int], why: String) -> void:
        stamp = at
        reason = why
