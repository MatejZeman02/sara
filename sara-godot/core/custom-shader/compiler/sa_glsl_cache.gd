## The dialect's translations kept on disk between starts, keyed on the text
## they came from and on the dialect that made them.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Translating a kernel file's text into GLSL is script work, and a start
## translated every file again although the SPIR-V cache already held what each
## one compiled to: on the RTX 3090 it was 1.6 of the 2.2 seconds the kernels
## stage took with every SPIR-V entry a hit, against 0.17 for the driver. Kept
## here, a start that changed no kernel reads one file instead.
##
## One file rather than a file an entry, because a start reads every entry and
## a hundred and fifty small reads cost more than one. Written once a start, at
## the end of the kernels stage, and only when a translation was made that the
## file did not hold, so a warm start writes nothing. What a write keeps is what
## this process read or made, which drops a text no kernel has any more.
##
## A translation is kept only when the dialect refused nothing while it made
## it, so a file that says why it is wrong says so at every start, not only the
## first.
class_name SaGlslCache
extends RefCounted

## The folder under the data root, beside the SPIR-V cache, so a cold start
## that empties one empties both.
const CACHE_FOLDER: String = "glsl_cache"

## The one file the entries are kept in.
const CACHE_FILE: String = "translations.bin"

## Where the dialect's scripts are, every file of which is read for the
## fingerprint, so an edit to the dialect drops every translation it made.
const DIALECT_FOLDER: String = "res://core/custom-shader/dialect"

## The names table the dialect reads, part of the fingerprint for the same
## reason.
const NAMES_FILE: String = "res://core/custom-shader/gmacs_names.json"

## The format of the file, so a change to its layout reads as no file at all.
const FORMAT: int = 1

## The one cache a start reads, built on first use.
static var _shared: SaGlslCache = null

## The file this cache reads and writes.
var _path: String = ""
## What the dialect's files hash to, the file's key as a whole.
var _fingerprint: String = ""
## key -> GLSL, read from the file on first use.
var _kept: Dictionary[String, String] = {}
## key -> GLSL, every entry this process read or made, which a write keeps.
var _used: Dictionary[String, String] = {}
var _read: bool = false
## Whether this process made a translation the file did not hold.
var _fresh: bool = false


## A cache kept in *folder*, for a dialect whose files hash to *fingerprint*.
func _init(folder: String, fingerprint: String) -> void:
    _path = folder.path_join(CACHE_FILE)
    _fingerprint = fingerprint


## The cache a start uses, under the data root, for the dialect this build
## carries.
static func shared() -> SaGlslCache:
    if _shared == null:
        _shared = SaGlslCache.new(SaDataRoot.path(CACHE_FOLDER), dialect_fingerprint())
    return _shared


## A hash of every file of the dialect and of its names table, as bytes, so an
## exported build whose scripts are tokens fingerprints those.
static func dialect_fingerprint() -> String:
    var hashing := HashingContext.new()
    hashing.start(HashingContext.HASH_SHA256)
    var names := Array(DirAccess.get_files_at(DIALECT_FOLDER))
    names.sort()
    for file_name: String in names:
        if file_name.get_extension() == "uid":
            continue
        hashing.update(file_name.to_utf8_buffer())
        hashing.update(FileAccess.get_file_as_bytes(DIALECT_FOLDER.path_join(file_name)))
    hashing.update(FileAccess.get_file_as_bytes(NAMES_FILE))
    return hashing.finish().hex_encode()


## The translation kept for *text*, or "" when none is.
func read(text: String) -> String:
    _read_once()
    var key := text.sha256_text()
    var glsl: String = _kept.get(key, "")
    if not glsl.is_empty():
        _used[key] = glsl
    return glsl


## Keeps *glsl* as the translation of *text*, for the next write.
func keep(text: String, glsl: String) -> void:
    _read_once()
    var key := text.sha256_text()
    _used[key] = glsl
    if _kept.get(key, "") != glsl:
        _kept[key] = glsl
        _fresh = true


## The file read into [member _kept] the first time either side asks, so a
## keep before the first read is not then read over.
func _read_once() -> void:
    if not _read:
        _read = true
        _kept = _from_disk()


## Writes what this process read or made, when it made something the file did
## not hold. Through a file beside it and a rename, so a second Sara reading at
## the same moment reads the old file or the new one and never half of one.
func write() -> void:
    if not _fresh:
        return
    _fresh = false
    DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
    var partial := _path + ".partial"
    var file := FileAccess.open(partial, FileAccess.WRITE)
    if file == null:
        return
    file.store_var({"format": FORMAT, "fingerprint": _fingerprint, "entries": _used})
    file.close()
    DirAccess.rename_absolute(partial, _path)


## The entries the file holds, or none when it is missing, of another format or
## of another dialect.
func _from_disk() -> Dictionary[String, String]:
    var out: Dictionary[String, String] = {}
    var file := FileAccess.open(_path, FileAccess.READ)
    if file == null:
        return out
    var held: Variant = file.get_var()
    if not held is Dictionary:
        return out
    var table: Dictionary = held
    if table.get("format") != FORMAT or table.get("fingerprint") != _fingerprint:
        return out
    var entries: Variant = table.get("entries")
    if entries is Dictionary:
        var kept_entries: Dictionary = entries
        out.assign(kept_entries)
    return out
