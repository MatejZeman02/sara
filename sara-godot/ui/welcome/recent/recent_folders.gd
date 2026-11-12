## The recent documents put under their folders, as `welcome-window.md` asks: one
## group per folder, the folders in the order of the newest document in each,
## and the ten newest documents the limit across all of them.
##
## **What newest means.** An entry is a path and a time, and the larger time is
## the newer. The recent list keeps no time of its own, only an order, newest
## first, so the grid hands each path its place on the list counted from the end
## as its time. A suite hands real seconds and reads the same rule. Two entries
## with one time keep the order they were handed in.
##
## Pure and static, so a suite asks it of a list alone without building a card.
@tool
class_name WelcomeRecentFolders
extends RefCounted

## How many documents the groups hold between them, the recent list's own cap.
const LIMIT := SaSettingsValues.MAX_RECENT_FILES


## The groups for *entries*, each a dictionary with `path` and `time`.
##
## Returns one dictionary per folder, `folder` and `paths`, the paths newest
## first. A folder comes before another when its newest document is newer, which
## is the same as the order its first path appears in the ten newest.
static func group(entries: Array) -> Array:
    var ranked: Array = []
    for index in entries.size():
        var entry: Dictionary = entries[index]
        ranked.append({"path": str(entry["path"]), "time": float(entry["time"]), "index": index})
    ranked.sort_custom(_newer)
    if ranked.size() > LIMIT:
        ranked.resize(LIMIT)

    var groups: Array = []
    var by_folder := {}
    for entry: Dictionary in ranked:
        var path: String = entry["path"]
        var folder := path.get_base_dir()
        if not by_folder.has(folder):
            by_folder[folder] = {"folder": folder, "paths": []}
            groups.append(by_folder[folder])
        (by_folder[folder]["paths"] as Array).append(path)
    return groups


## The entries the grid hands in for the recent list *paths*, newest first, each
## timed by its place so the first is the newest.
static func of_recent_list(paths: Array) -> Array:
    var entries: Array = []
    for index in paths.size():
        entries.append({"path": str(paths[index]), "time": float(paths.size() - index)})
    return entries


## Newer first, and on one time the order the entries came in.
static func _newer(a: Dictionary, b: Dictionary) -> bool:
    if a["time"] != b["time"]:
        return a["time"] > b["time"]
    return a["index"] < b["index"]
