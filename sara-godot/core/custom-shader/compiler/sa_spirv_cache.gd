## Compiled SPIR-V kept on disk between runs, keyed on the source it came from.
##
## glslang is the real startup cost and it grows with every shader a module ships,
## and whichever kernel compiles first pays for glslang and driver warm-up on
## everyone else's behalf. Read from this cache, the same work is a tenth of it.
##
## Nothing here touches a RenderingDevice. It is bytes on disk and the key that
## finds them, which is why it lives beside the compiler rather than inside it.
class_name SaSpirvCache
extends RefCounted

## Where compiled SPIR-V is kept between runs.
##
## Under the data root rather than `res://`: an exported build's resources are
## read-only and packed, and the cache has to be writable wherever Sara runs. A
## folder name rather than a path, because a `--settings-dir` run keeps its
## cache under its own root, and [method cache_dir] asks the root.
const CACHE_FOLDER: String = "spirv_cache"

## How many entries to keep. Every edit to a shader leaves the previous entry
## behind, so without a cap this grows for as long as anyone develops. An entry is
## tens of kilobytes, so the cap is about disk tidiness rather than pressure.
## Sized to hold every kernel a start compiles, 282 on a clean boot, with room
## for third-party modules.
const CACHE_MAX: int = 512

## The keys this process read or wrote, which [method prune] drops last.
##
## A hit reads a file and never writes it, so its modification time is the
## day it was compiled. By age alone the kernels every boot loads would be the
## oldest in a full directory, and each edit's fresh entry would evict one of
## them and make the next boot compile it again.
static var _used: Dictionary[String, bool] = {}


## What identifies compiled SPIR-V: the exact GLSL it came from, and the engine
## that compiled it.
##
## The source is already fully preprocessed by the time it gets here, with includes
## pasted, comments gone and the storage format substituted, so two kernels that
## differ in any of those hash differently and a hit is exact. The engine version
## is in the key because a Godot upgrade can bring a different glslang, and SPIR-V
## from one is not promised to load into another.
static func key_for(final_source: String) -> String:
    var version: String = str(Engine.get_version_info().get("string", "unknown"))
    return (version + "\n" + final_source).sha256_text()


## The folder the compiled SPIR-V is kept in, under the data root.
static func cache_dir() -> String:
    return SaDataRoot.path(CACHE_FOLDER)


static func path_for(key: String) -> String:
    return cache_dir().path_join(key + ".spv")


## The cached bytes as an RDShaderSPIRV, or null when there are none.
static func load_spirv(key: String) -> RDShaderSPIRV:
    var file := FileAccess.open(path_for(key), FileAccess.READ)
    if file == null:
        return null
    var bytes := file.get_buffer(file.get_length())
    if bytes.is_empty():
        return null
    var spirv := RDShaderSPIRV.new()
    spirv.bytecode_compute = bytes
    _used[key] = true
    return spirv


## Writes *spirv* under *key*, and keeps the directory at the cap while doing it.
##
## The cap is checked here rather than kept in a counter, and the counter was
## written first and thrown away. Anything writing to the directory behind this
## function desynchronises a counter, and two Godot processes sharing one
## checkout's `user://` is the ordinary case on this board rather than a corner:
## a counter seeded at 254 does not notice a sibling's three entries and the cap
## quietly stops holding.
##
## The cost the counter was avoiding is smaller than it reads. `get_files()`
## returns names and stats nothing, so a listing of the cap is a few hundred
## microseconds, and only [method prune] stats for modification times, only when
## the directory is actually over. A cold start writes an entry per kernel and
## pays glslang for each of them, which is milliseconds apiece.
##
## A write over an existing key replaces it and cannot take the count up, so the
## listing is skipped there.
static func store(key: String, spirv: RDShaderSPIRV) -> void:
    var bytes := spirv.bytecode_compute
    if bytes.is_empty():
        return
    DirAccess.make_dir_recursive_absolute(cache_dir())
    var path := path_for(key)
    var fresh := not FileAccess.file_exists(path)
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        # Not worth an error. A cache that cannot be written costs the compile it
        # would have saved and nothing else, as though there were no cache.
        push_warning("SaSpirvCache: could not write the SPIR-V cache, compiling every run.")
        return
    file.store_buffer(bytes)
    _used[key] = true
    if fresh and count() > CACHE_MAX:
        prune()


## Removes one entry, for bytes a driver read and then refused.
static func discard(key: String) -> void:
    DirAccess.remove_absolute(path_for(key))


## How many entries the directory holds right now, by asking it.
static func count() -> int:
    var dir := DirAccess.open(cache_dir())
    if dir == null:
        return 0
    var held := 0
    for entry_name in dir.get_files():
        if entry_name.ends_with(".spv"):
            held += 1
    return held


## Drops the oldest entries until at most CACHE_MAX remain, and answers how many
## it dropped. An entry this process used goes after every one it did not.
##
## Called from [method store] when a write takes the directory over, and once from the compiler's
## startup pass so a session that writes nothing still tidies a directory an older build, or a sibling
## process, left over the cap. The startup pass rather than the boot header, which a headless run
## never builds, because the gate is what writes most of the entries.
##
## The count is the caller's to read rather than a report made here. The
## startup pass is the only disk work between the kernel compile and
## `Main._init`, and the boot marks table carries the number beside the mark on
## either side of it, so the prune's share of that gap is read rather than
## guessed.
static func prune() -> int:
    var dir := DirAccess.open(cache_dir())
    if dir == null:
        return 0
    var entries: Array = []
    for entry_name in dir.get_files():
        if entry_name.ends_with(".spv"):
            var used := 1 if _used.has(entry_name.get_basename()) else 0
            entries.append([used, FileAccess.get_modified_time(cache_dir().path_join(entry_name)), entry_name])
    if entries.size() <= CACHE_MAX:
        return 0
    entries.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
    var dropped := entries.size() - CACHE_MAX
    for i in dropped:
        var entry_name: String = entries[i][2]
        dir.remove(entry_name)
    return dropped
