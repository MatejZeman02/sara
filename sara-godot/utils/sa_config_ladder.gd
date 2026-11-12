## How a `ConfigFile` the painter keeps is read and written so that a crash or a
## hand edit never costs them the file.
##
## `ConfigFile.load` fails identically for a missing file and a truncated one,
## and a store that keeps its defaults on either and saves them on the next
## change writes over a file a repair could have saved. So a file that exists
## but does not parse is first moved aside as a `.broken` sibling, then the
## backup the last save kept is tried. A save goes to a `.tmp` sibling and is
## renamed over the file, the previous one kept as the `.bak`, so a write that
## dies part way leaves the file that was there rather than half of a new one.
##
## The ladder says what happened and the caller says it to the painter, in its
## own words, because the preferences and the colours are different losses.
## Building one reads the file.
class_name SaConfigLadder
extends RefCounted

## What a read came to.
enum Outcome {
    READ,  ## The file parsed.
    MISSING,  ## There is no file, which a first run is and no fault.
    RESTORED,  ## The file did not parse and the backup did.
    DEFAULTS,  ## Neither parsed, so [member config] is empty.
}

## The file as it was before the last save. Written on every save, so a file
## that fails to parse has a previous version to fall back to.
const BACKUP_SUFFIX := ".bak"
## Where a file that failed to parse is kept. Never read back, only kept,
## because a file that broke once is still the painter's, and what broke it
## may be one line they can repair by hand.
const BROKEN_SUFFIX := ".broken"
## The sibling a save writes before it is renamed over the file.
const TEMP_SUFFIX := ".tmp"

## What was read: the file, the backup, or an empty one. A fresh object either
## way, because `ConfigFile.load` merges into what it holds.
var config: ConfigFile = ConfigFile.new()
var outcome: Outcome = Outcome.MISSING
## Why the file did not parse, `OK` when it did or was missing.
var error: Error = OK
## Where the unreadable file now is, empty unless it was moved there.
var broken_path: String = ""


func _init(path: String) -> void:
    if not FileAccess.file_exists(path):
        return
    error = config.load(path)
    if error == OK:
        outcome = Outcome.READ
        return
    broken_path = path + BROKEN_SUFFIX
    DirAccess.rename_absolute(path, broken_path)
    config = ConfigFile.new()
    var backup_path := path + BACKUP_SUFFIX
    if FileAccess.file_exists(backup_path) and config.load(backup_path) == OK:
        outcome = Outcome.RESTORED
        return
    config = ConfigFile.new()
    outcome = Outcome.DEFAULTS


## Writes `values` to `path` by way of a sibling, keeping the previous file as
## the backup. Answers the first error, which the caller reports.
static func write(values: ConfigFile, path: String) -> Error:
    var temp_path := path + TEMP_SUFFIX
    var err: Error = values.save(temp_path)
    if err != OK:
        return err
    if FileAccess.file_exists(path):
        DirAccess.rename_absolute(path, path + BACKUP_SUFFIX)
    return DirAccess.rename_absolute(temp_path, path)
