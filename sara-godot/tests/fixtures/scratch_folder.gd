## A suite's scratch folder taken away, for every suite that writes files of
## its own under the data root and has to leave nothing behind.
##
## Eighty-three suites each wrote a `_clear_scratch` by hand, and the copies
## had drifted: one left a thumbnails folder behind, one listed the folders it
## knew of, one emptied the folder and kept it. A suite now calls one of the
## three below, and `rg "ScratchFolder\."` lists them.
extends RefCounted

## The files a safe save leaves beside the file it writes.
const SAVED_SUFFIXES: Array[String] = ["", ".bak", ".tmp", ".broken"]


## Removes *path* and everything under it, its folders included. A path that is
## empty, missing or not inside the data root is left alone, so a suite whose
## folder was never made, or a mistyped name, removes nothing of the painter's.
static func clear(path: String) -> void:
    var folder := _inside_data_root(path)
    if folder.is_empty() or not DirAccess.dir_exists_absolute(folder):
        return
    _remove_tree(folder)


## Removes the files directly inside *path*, hidden ones as well, and keeps the
## folder and any folder in it, for a suite whose store expects the folder to
## stand between its tests.
static func empty(path: String) -> void:
    var folder := _inside_data_root(path)
    if folder.is_empty():
        return
    var dir := DirAccess.open(folder)
    if dir == null:
        return
    dir.include_hidden = true
    for file_name: String in dir.get_files():
        dir.remove(file_name)


## Removes the file at *path* and the backup, temporary and broken copies a
## safe save writes beside it.
static func remove_saved(path: String) -> void:
    var file := _inside_data_root(path)
    if file.is_empty():
        return
    for suffix: String in SAVED_SUFFIXES:
        DirAccess.remove_absolute(file + suffix)


## *path* as an absolute path when it lies strictly inside the data root, and
## empty otherwise.
static func _inside_data_root(path: String) -> String:
    if path.is_empty():
        return ""
    var root := ProjectSettings.globalize_path(SaDataRoot.folder()).simplify_path()
    var absolute := ProjectSettings.globalize_path(path).simplify_path()
    var prefix := root if root.ends_with("/") else root + "/"
    if not absolute.begins_with(prefix):
        push_error("ScratchFolder: %s is not inside the data root %s, left alone" % [absolute, root])
        return ""
    return absolute


## Removes *folder* with every file and folder under it. A link is removed as
## a link and never followed, so nothing outside the folder goes with it.
static func _remove_tree(folder: String) -> void:
    var dir := DirAccess.open(folder)
    if dir == null:
        return
    dir.include_hidden = true
    for file_name: String in dir.get_files():
        dir.remove(file_name)
    for child: String in dir.get_directories():
        if dir.is_link(child):
            dir.remove(child)
        else:
            _remove_tree(folder.path_join(child))
    DirAccess.remove_absolute(folder)
