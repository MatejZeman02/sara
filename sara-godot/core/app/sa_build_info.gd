## The version and the commit a running Sara can name for itself.
##
## `project.godot` holds the version and is the only place it is written. The
## commit comes from `build_info.json`, which `packaging/build.sh` writes into the
## project for exactly as long as the export takes to pack it, then moves beside
## the binary, so an editor run never reads a stamp left over from last week's
## build. Without a stamp the commit is read from the checkout's own `.git`, and
## the reader says which of the two it did, because a commit named by an exported
## binary and one named by a working tree with uncommitted edits are different
## claims.
class_name SaBuildInfo
extends RefCounted

## Where the export stamp lands. Gitignored, and gone again after the export.
const STAMP_PATH: String = "res://build_info.json"

## What `read()` reports when there is no stamp and no `.git` to ask.
const UNKNOWN_COMMIT: String = "unknown"

## The stamped build was exported by `packaging/build.sh`.
const SOURCE_EXPORT: String = "export"
## No stamp, so the commit is whatever `.git/HEAD` pointed at, edits and all.
const SOURCE_WORKING_TREE: String = "working tree"
## Neither a stamp nor a `.git`, which is a build made some other way.
const SOURCE_UNKNOWN: String = "unknown"
## The keys a stamp may carry that the build's information takes over.
const STAMP_KEYS: PackedStringArray = ["version", "commit", "commit_full", "dirty", "built", "modules"]


## The version from `project.godot`, bare: "0.1.0".
static func version() -> String:
    return str(ProjectSettings.get_setting("application/config/version", ""))


## Everything known about the running build.
##
## Keys: `version`, `commit` (seven characters), `commit_full`, `dirty` (true when
## the export ran on a tree with uncommitted changes to tracked files), `built`
## (ISO 8601, UTC, empty unless stamped), `source`, one of the three SOURCE
## constants, and `modules`, the commit of each module repository the export
## packed by its folder under `res://`, empty unless stamped.
## A stamp that is not a JSON object is treated as absent.
static func read(stamp_path: String = STAMP_PATH) -> Dictionary[String, Variant]:
    var info: Dictionary[String, Variant] = {
        "version": version(),
        "commit": UNKNOWN_COMMIT,
        "commit_full": "",
        "dirty": false,
        "built": "",
        "source": SOURCE_UNKNOWN,
        "modules": {},
    }
    var stamp := _read_stamp(stamp_path)
    if not stamp.is_empty():
        for key: String in STAMP_KEYS:
            if stamp.has(key):
                info[key] = stamp[key]
        info["source"] = SOURCE_EXPORT
        return info

    var head := _working_tree_commit()
    if head != "":
        info["commit_full"] = head
        info["commit"] = head.substr(0, 7)
        info["source"] = SOURCE_WORKING_TREE
    return info


## One line for the boot header and, later, the About dialog.
##
## "v0.1.0  ·  ae1b0fa  ·  exported 2026-09-02 01:12 UTC", with "uncommitted
## changes" appended when the tree was dirty, or "working tree, not exported" for
## an editor run. Provenance is part of the line on purpose: a bug report that
## names a commit is only worth the commit if the binary was actually built from
## it.
static func describe(info: Dictionary[String, Variant]) -> String:
    var parts: Array[String] = ["v" + str(info.get("version", ""))]
    var commit := str(info.get("commit", UNKNOWN_COMMIT))
    match str(info.get("source", SOURCE_UNKNOWN)):
        SOURCE_EXPORT:
            parts.append(commit)
            var built := built_for_humans(str(info.get("built", "")))
            parts.append("exported " + built if built != "" else "exported")
            var dirty: bool = info.get("dirty", false)
            if dirty:
                parts.append("development build")
        SOURCE_WORKING_TREE:
            parts.append(commit)
            parts.append("development build")
        _:
            parts.append("commit " + UNKNOWN_COMMIT)
    return "  ·  ".join(parts)


## The one line `sara --version` prints: "Sara 0.17.3 (5cd5c8c)", with " dirty"
## before the bracket closes when the export ran on a tree with uncommitted
## changes. The same version and seven-character commit the boot header's Build
## line shows, without the provenance words, so a script can split it on spaces.
static func version_line(info: Dictionary[String, Variant]) -> String:
    var inside := str(info.get("commit", UNKNOWN_COMMIT))
    var dirty: bool = info.get("dirty", false)
    if dirty:
        inside += " dirty"
    return "Sara %s (%s)" % [info.get("version", ""), inside]


static func _read_stamp(path: String) -> Dictionary[String, Variant]:
    if not FileAccess.file_exists(path):
        return {}
    # A JSON instance rather than JSON.parse_string, which prints an engine error
    # for a malformed file. A bad stamp is a build script bug worth ignoring
    # quietly here, not a startup error.
    var json := JSON.new()
    if json.parse(FileAccess.get_file_as_string(path)) != OK:
        return {}
    # The parsed object is untyped, so it is typed here rather than failing
    # where a caller first assigns it.
    return SaTyped.strings(json.data)


## "2026-09-02T01:12:40Z" becomes "2026-09-02 01:12 UTC". Anything else is
## returned as it came, because a stamp written by hand is still worth showing.
static func built_for_humans(built: String) -> String:
    if built.length() == 20 and built[10] == "T" and built.ends_with("Z"):
        return built.substr(0, 10) + " " + built.substr(11, 5) + " UTC"
    return built


## The commit `.git/HEAD` names, read from the checkout the project lives in.
##
## Empty in an exported build, where `res://` globalizes to the binary's own
## directory and there is no `.git` above it. Handles a `.git` that is a file
## pointing elsewhere, which is what a worktree has, and a ref that has been
## packed away by `git gc`. Refs are read from the worktree's `commondir`.
static func _working_tree_commit() -> String:
    return checkout_commit(ProjectSettings.globalize_path("res://").path_join(".."))


## The commit the `.git` in the folder *root* names, a submodule's `.git` file
## pointing elsewhere included, or empty when the folder holds none.
static func checkout_commit(root: String) -> String:
    var git_dir := _git_dir(root.path_join(".git"))
    if git_dir == "":
        return ""
    var head := FileAccess.get_file_as_string(git_dir.path_join("HEAD")).strip_edges()
    if head == "":
        return ""
    if not head.begins_with("ref: "):
        return head
    var ref := head.trim_prefix("ref: ")
    var refs_dir := _common_dir(git_dir)
    var loose := FileAccess.get_file_as_string(refs_dir.path_join(ref)).strip_edges()
    if loose != "":
        return loose
    for line in FileAccess.get_file_as_string(refs_dir.path_join("packed-refs")).split("\n"):
        if line.ends_with(" " + ref):
            return line.get_slice(" ", 0)
    return ""


## A worktree's git dir holds only HEAD and the index. Its refs and packed-refs
## live in the repository it was added from, which `commondir` names, relative
## to the worktree's own git dir. A plain checkout has no such file.
static func _common_dir(git_dir: String) -> String:
    var pointer := FileAccess.get_file_as_string(git_dir.path_join("commondir")).strip_edges()
    if pointer == "":
        return git_dir
    if pointer.is_relative_path():
        pointer = git_dir.path_join(pointer)
    return pointer if DirAccess.dir_exists_absolute(pointer) else git_dir


static func _git_dir(candidate: String) -> String:
    if DirAccess.dir_exists_absolute(candidate):
        return candidate
    if not FileAccess.file_exists(candidate):
        return ""
    var pointer := FileAccess.get_file_as_string(candidate).strip_edges()
    if not pointer.begins_with("gitdir: "):
        return ""
    var target := pointer.trim_prefix("gitdir: ")
    if target.is_relative_path():
        target = candidate.get_base_dir().path_join(target)
    return target if DirAccess.dir_exists_absolute(target) else ""
