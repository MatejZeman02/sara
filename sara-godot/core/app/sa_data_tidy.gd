## Keeps the data folder from growing for as long as Sara is used: the copies
## and caches a run makes by itself are dropped once nobody can want them.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **What it tidies, and what it never does.** Only what Sara made without being
## asked: the kernels it generated, the engine's compiled shaders of a version
## that is gone, the crash copies of documents that were never saved, the pasted
## references and the half-poured saves. A preset, a pattern, a saved look, a
## template, a note or a timelapse is the painter's, and no folder of those is
## named here.
##
## **By age, or by the newest few.** A file is dropped when it was last written
## more than a number of days ago. Every generated kernel is written again at
## each start, so its age is its time since a build last used it, and a kernel an
## older version made and no newer one names ages out on its own. The engine's
## shader cache keeps one folder for each version of a shader, so it keeps the
## newest few of those rather than going by age, since a version a painter still
## runs is not written again.
##
## **Once a start, at the end of the kernels stage**, beside the SPIR-V and
## translation caches, which keep a count of their own. Every rule takes the
## folder and the clock, so a suite plays a year in a moment.
class_name SaDataTidy
extends RefCounted

## The days a generated kernel may go unwritten. Each start writes every kernel
## the build names, so only one no build names any more reaches this.
const KERNEL_DAYS: int = 30

## The days a crash copy of an untitled document is kept. A painter who has not
## looked at it in a month is not going to, and the folder is the one place a
## crash leaves a whole document behind.
const RECOVERY_DAYS: int = 30

## The days a pasted reference is kept. The document that holds it keeps its
## own bytes, so this is a copy for a board that was never saved.
const PASTE_DAYS: int = 60

## The days a side file of a save onto a content address may wait. A save that
## lands removes its own, so one this old is the leftover of a save that failed.
const POURED_DAYS: int = 7

## The folders of the engine's shader cache kept for each shader, the newest.
## One is the build running, one the build before it for a painter who goes
## back.
const SHADER_VERSIONS: int = 2

## The engine's own shader cache, as the engine names it. It sits under the
## engine's `user://` whatever `--settings-dir` says.
const SHADER_CACHE_FOLDER: String = "shader_cache"

## The folders the rules name, spelled here because the compiler, an autoload
## that calls this, cannot name the classes that own them. A suite reads each
## owner's constant and fails when one differs.
const KERNEL_FOLDER: String = "generated-kernels"
const RECOVERY_FOLDER: String = "autosave"
const PASTE_FOLDER: String = "reference-pastes"
const POURED_FOLDER: String = "saving"

const _DAY_SECONDS: int = 86400


## Every rule, against the data root of this run, the clock being now.
static func run(now: int = int(Time.get_unix_time_from_system())) -> int:
    var dropped := 0
    dropped += files_older_than(SaDataRoot.path(KERNEL_FOLDER), KERNEL_DAYS, now, true)
    dropped += files_older_than(SaDataRoot.path(RECOVERY_FOLDER), RECOVERY_DAYS, now, false)
    dropped += files_older_than(SaDataRoot.path(PASTE_FOLDER), PASTE_DAYS, now, false)
    dropped += files_older_than(SaDataRoot.path(POURED_FOLDER), POURED_DAYS, now, false)
    dropped += newest_folders(SaDataRoot.DEFAULT.path_join(SHADER_CACHE_FOLDER), SHADER_VERSIONS)
    return dropped


## Removes every file of *folder* last written more than *days* before *now*,
## and answers how many went. With *below*, the folders under it are walked as
## well and a folder left empty goes, the folder itself never. A missing folder
## has nothing to drop.
static func files_older_than(folder: String, days: int, now: int, below: bool) -> int:
    var dir := DirAccess.open(folder)
    if dir == null:
        return 0
    var dropped := 0
    var cut := now - days * _DAY_SECONDS
    for file_name: String in dir.get_files():
        if FileAccess.get_modified_time(folder.path_join(file_name)) < cut and dir.remove(file_name) == OK:
            dropped += 1
    if below:
        for sub: String in dir.get_directories():
            var inner := folder.path_join(sub)
            dropped += files_older_than(inner, days, now, true)
            if DirAccess.get_files_at(inner).is_empty() and DirAccess.get_directories_at(inner).is_empty():
                dir.remove(sub)
    return dropped


## Removes all but the newest *keep* folders of each folder under *folder*, by
## the time each was last written, and answers how many went. The shader cache
## has a folder a shader and a folder a version of it below that.
static func newest_folders(folder: String, keep: int) -> int:
    var dropped := 0
    for shader: String in DirAccess.get_directories_at(folder):
        var versions: Array = []
        var inner := folder.path_join(shader)
        for version: String in DirAccess.get_directories_at(inner):
            versions.append([FileAccess.get_modified_time(inner.path_join(version)), version])
        if versions.size() <= keep:
            continue
        versions.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
        for at in range(keep, versions.size()):
            dropped += 1 if _remove_tree(inner.path_join(str(versions[at][1]))) else 0
    return dropped


## Removes *folder* and all it holds, and answers whether it is gone.
static func _remove_tree(folder: String) -> bool:
    for file_name: String in DirAccess.get_files_at(folder):
        DirAccess.remove_absolute(folder.path_join(file_name))
    for sub: String in DirAccess.get_directories_at(folder):
        _remove_tree(folder.path_join(sub))
    return DirAccess.remove_absolute(folder) == OK
