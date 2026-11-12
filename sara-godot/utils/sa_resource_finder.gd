## Where a file of a given name lives under `res://` today, and the repair of a
## `.tres` whose `[ext_resource]` lines point where a file was.
##
## A preset is named rather than pathed: a preset a painter wrote before the
## settings script moved still points at the old directory, and what is left of
## the old path when it moves is the file's name.
##
## **A walk rather than a table of old paths to new ones**, because a table is a
## list of the moves somebody remembered. The ask is rare, one preset load or one
## repair, and the answer cannot change while the process runs, so it is worked
## out once per name and kept.
##
## **In `utils` rather than beside the preset store**. The walk and the repair
## take a path to any `.tres` and know nothing about presets: a saved colour
## theme under `ui` needs them as much as a preset under `core`, and a library
## both may name is how neither names the other's package. It was cut out of
## `sa_preset_store.gd` once by length, and the repair followed it here by what
## it is about.
class_name SaResourceFinder
extends RefCounted

## Directories with no source in them, skipped so the walk stays short. `.godot`
## is the import cache and holds a copy of everything.
const SKIP: Array[String] = [".godot", ".git", "addons", "assets", "scratch", "build", "scenes", "layouts"]

## File name -> where it was found under `res://`, for the process. An empty
## answer is remembered too, so a name that is nowhere is not walked twice.
static var _found: Dictionary = {}


## Where a file called *file_name* lives under `res://`, or an empty string.
static func named(file_name: String) -> String:
    if _found.has(file_name):
        return _found[file_name]
    _found[file_name] = _search("res://", file_name)
    return _found[file_name]


## The first directory at or under *from* holding a resource called *file_name*.
##
## `ResourceLoader.list_directory` rather than `DirAccess`. Inside an exported
## pack a `DirAccess` walk finds no `sa_palette.gd` and no
## `sa_gradient_preset.gd` anywhere, as a debug export shows, so the repair
## would leave every old theme and preset broken in the build a painter runs
## while passing every suite in the editor. The loader lists a resource by the name
## it had in the editor, in both, and a directory with a slash after it.
static func _search(from: String, file_name: String) -> String:
    var subs: Array[String] = []
    for entry: String in ResourceLoader.list_directory(from):
        if entry.ends_with("/"):
            subs.append(entry.trim_suffix("/"))
        elif entry == file_name:
            return from.path_join(entry)
    for sub: String in subs:
        if sub.begins_with(".") or SKIP.has(sub):
            continue
        var found := _search(from.path_join(sub), file_name)
        if not found.is_empty():
            return found
    return ""


## Brings the `[ext_resource]` lines of the `.tres` at *path* up to date, and
## answers what it changed, one line per repair.
##
## A preset names the settings script by path, and a preset written while the
## script lived in `modules/sara-base-modules/tools/` still points there, where
## the script is now in `stamp-brush/tools/`. Godot does not read such a file
## partly: the parse fails on the missing `ext_resource`, the run log reads
## `Parse Error` on the preset's line, and the preset is gone.
##
## Two things are written, and the second is the one that matters. The dead path
## is replaced with wherever a file of that name now lives, which repairs what is
## already broken. And every `ext_resource` gains a `uid`, which is what stops the
## next move breaking anything at all: Godot resolves a `uid` before a path, and
## a script's `.uid` file stays the same when the script moves, so a preset
## carrying one survives the move untouched.
##
## Run before the load rather than after a failure, because a failed parse has
## already printed three `ERROR:` lines by the time it answers null, and because
## the check is a file read and a `ResourceLoader.exists` per line on a file with
## four of them.
##
## Static and taking a path, so a caller with a `.tres` and no store can use it,
## and so a test can point it at a file it wrote by hand.
static func repair_resource_paths(path: String) -> PackedStringArray:
    var changed := PackedStringArray()
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return changed
    var text := file.get_as_text()
    file = null
    var out: PackedStringArray = []
    for line: String in text.split("\n"):
        var fixed := _repaired_ext_resource(line)
        if fixed != line:
            changed.append(fixed.strip_edges())
        out.append(fixed)
    if changed.is_empty():
        return changed
    var writer := FileAccess.open(path, FileAccess.WRITE)
    if writer == null:
        # The repair is still worth reporting: the caller's load will fail and the
        # reason is a read-only profile rather than a preset that is beyond help.
        return changed
    writer.store_string("\n".join(out))
    return changed


## One `[ext_resource ...]` line with its path resolved and its uid filled in, or
## the line unchanged when it needs neither.
static func _repaired_ext_resource(line: String) -> String:
    if not line.begins_with("[ext_resource "):
        return line
    var quoted := line.split('path="')
    if quoted.size() < 2:
        return line
    var resource_path := String(quoted[1]).split('"')[0]
    var fixed := line
    if not ResourceLoader.exists(resource_path):
        # The file's name is what survives a move, and `named` is the walk that
        # takes that name back to a path.
        var found := named(resource_path.get_file())
        if found.is_empty():
            return line
        fixed = fixed.replace('path="%s"' % resource_path, 'path="%s"' % found)
        resource_path = found
    if not fixed.contains('uid="'):
        var uid := ResourceUID.id_to_text(ResourceLoader.get_resource_uid(resource_path))
        if uid.begins_with("uid://") and uid != "uid://<invalid>":
            fixed = fixed.replace('path="%s"' % resource_path, 'uid="%s" path="%s"' % [uid, resource_path])
    return fixed
