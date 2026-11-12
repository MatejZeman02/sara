## What a module says about itself in its `manifest.cfg`, read before any of
## its code runs.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A module's folder may hold a `manifest.cfg` beside its scripts, with its id,
## name, version, the oldest API version it runs on, its dependencies by id with
## the version each needs, a sentence saying what it does, its authors, licence,
## website and tags. The loader reads it before it loads a script of the module,
## as Blender's add-on list reads a `blender_manifest.toml` without running the
## add-on, so the Modules window can describe a module that never loaded.
##
## A `ConfigFile` rather than JSON, because Godot reads both with no add-on and
## only the first takes a comment. A manifest is written by hand, often by a
## student, and a line that says why a dependency is there belongs beside it.
## Its sections and `key=value` lines read like the TOML Blender chose.
##
## A key the file leaves out is answered by the module's function of the same
## meaning, `get_version()` for `version` and so on, so a module with no
## manifest keeps working as it did, and a key the file writes wins over the
## function. A module with neither has its folder's name as its id and "0.0.0"
## as its version.
##
## Versions follow semantic versioning, `MAJOR.MINOR.PATCH` with an optional
## `-pre.release` part, and a manifest whose version does not is refused.
class_name SaModuleManifest extends RefCounted

## The file a module's folder may hold.
const FILE := "manifest.cfg"
## The section of the module's own keys, and the one of its dependencies, each
## line `<id>="<the oldest version it needs>"`, an empty version meaning any.
const MODULE_SECTION := "module"
const DEPENDENCIES_SECTION := "dependencies"
## The version a module that says none has.
const NO_VERSION := "0.0.0"
## What the commit reads when neither a build's stamp nor a checkout names one.
const NO_COMMIT := ""

## The keys of the module section and the type each is read as.
const KEYS: Dictionary[String, int] = {
    "id": TYPE_STRING,
    "name": TYPE_STRING,
    "version": TYPE_STRING,
    "sara_api": TYPE_INT,
    "description": TYPE_STRING,
    "authors": TYPE_ARRAY,
    "license": TYPE_STRING,
    "website": TYPE_STRING,
    "tags": TYPE_ARRAY,
}

## The folder the manifest was looked for in.
var folder: String = ""
## Whether the folder holds a manifest at all.
var has_file: bool = false
## Why the manifest could not be taken, empty when it could or there is none.
var problem: String = ""
## The keys the file wrote, which win over the module's functions.
var from_file: PackedStringArray = []

var id: StringName = &""
var name: String = ""
var version: String = NO_VERSION
## The API version the module needs at the least, `SaContext.API_VERSION` of
## the build it was written for.
var sara_api: int = SaContext.API_VERSION
var description: String = ""
var authors: PackedStringArray = []
var license: String = ""
var website: String = ""
var tags: PackedStringArray = []
## Each module this one needs, by id, with the oldest version of it that will
## do, or "" when any version will.
var dependencies: Dictionary[String, String] = {}
## The seven characters of the commit the module was built from, or empty.
var commit: String = NO_COMMIT


## The manifest of the module in *dir_path*, read from its file when it has one.
## Nothing of the module's code runs, so a module that fails to load is still
## described. [method complete] fills what the file leaves out.
static func read(dir_path: String) -> SaModuleManifest:
    var manifest := SaModuleManifest.new()
    manifest.folder = dir_path
    if dir_path.is_empty():
        return manifest
    manifest._read_file(dir_path.path_join(FILE))
    manifest.commit = Commits.of_folder(dir_path)
    return manifest


## The manifest of a module the loader did not read from a folder, the
## skeleton's own, whose folder is `res://`, or one filed by hand, read from its
## folder where it has one and completed by its functions.
static func of_module(module: SaModule) -> SaModuleManifest:
    var manifest := read(module.own_folder)
    manifest.complete(module, "")
    if module.own_folder.is_empty():
        manifest.commit = Commits.of_build()
    return manifest


## Fills each key the file left out from *module*'s function for it, and the id,
## when neither says one, from *fallback_id*, a folder's name with its hyphens
## read as underscores, as `SaModule.get_id()` does.
func complete(module: SaModule, fallback_id: String) -> void:
    if not from_file.has("id"):
        id = module.get_id()
    if String(id).is_empty():
        id = StringName(fallback_id.replace("-", "_"))
    if not from_file.has("name"):
        name = module.get_name()
    if name.is_empty() or name == "Unnamed Module":
        name = String(id).replace("-", " ").capitalize()
    if not from_file.has("version"):
        version = module.get_version()
        if not is_semver(version):
            problem = "its get_version() answers %s, which is not a semantic version" % version
    if not from_file.has("sara_api"):
        sara_api = module.get_api_version()
    if not from_file.has(DEPENDENCIES_SECTION):
        for dep: String in module.get_dependencies():
            dependencies[dep] = ""


## The ids of the modules this one needs.
func dependency_ids() -> PackedStringArray:
    return PackedStringArray(dependencies.keys())


## The version and the commit as one word pair, "1.0.0-alpha.1 3f2a9c1", or the
## version alone when no commit is known.
func version_and_commit() -> String:
    return version if commit.is_empty() else "%s %s" % [version, commit]


## Why *have*, the version of *dep_id* that loaded, is too old for this module,
## or "" when it will do.
func too_old(dep_id: String, have: String) -> String:
    var needed: String = dependencies.get(dep_id, "")
    if needed.is_empty() or compare(have, needed) >= 0:
        return ""
    return "%s %s is older than the %s it needs" % [dep_id, have, needed]


## Whether *text* is a semantic version: three numbers with no leading zero and
## an optional pre-release part after a hyphen.
static func is_semver(text: String) -> bool:
    return Semver.parse(text).size() == 4


## -1, 0 or 1 as *a* is older than, the same as or newer than *b*, by semantic
## versioning's precedence, which reads a pre-release as older than its release.
## A version that does not parse is older than any that does.
static func compare(a: String, b: String) -> int:
    var left := Semver.parse(a)
    var right := Semver.parse(b)
    if left.is_empty() or right.is_empty():
        return signi(right.size() - left.size())
    for i in 3:
        if left[i] != right[i]:
            var have: int = left[i]
            var need: int = right[i]
            return signi(have - need)
    return Semver.compare_pre(str(left[3]), str(right[3]))


func _read_file(path: String) -> void:
    if not FileAccess.file_exists(path):
        return
    has_file = true
    var config := ConfigFile.new()
    if config.load(path) != OK:
        problem = "its %s does not parse" % FILE
        return
    for key: String in KEYS:
        if not config.has_section_key(MODULE_SECTION, key):
            continue
        var value: Variant = config.get_value(MODULE_SECTION, key)
        if typeof(value) != KEYS[key]:
            problem = "the %s in its %s is not a %s" % [key, FILE, type_string(KEYS[key])]
            return
        from_file.append(key)
        _take(key, value)
    if config.has_section(DEPENDENCIES_SECTION):
        from_file.append(DEPENDENCIES_SECTION)
        for dep: String in config.get_section_keys(DEPENDENCIES_SECTION):
            var needed := str(config.get_value(DEPENDENCIES_SECTION, dep))
            if not needed.is_empty() and not is_semver(needed):
                problem = "the version its %s needs of %s, %s, is not a semantic version" % [FILE, dep, needed]
                return
            dependencies[dep] = needed
    if from_file.has("version") and not is_semver(version):
        problem = "the version in its %s, %s, is not a semantic version" % [FILE, version]


func _take(key: String, value: Variant) -> void:
    var list: Array = value if value is Array else []
    match key:
        "id":
            id = StringName(str(value))
        "name":
            name = str(value)
        "version":
            version = str(value)
        "sara_api":
            sara_api = value
        "description":
            description = str(value)
        "authors":
            authors = PackedStringArray(list)
        "license":
            license = str(value)
        "website":
            website = str(value)
        "tags":
            tags = PackedStringArray(list)


## Semantic versions taken apart and compared.
class Semver:
    ## [major, minor, patch, pre-release] of *text*, or empty when it is not a
    ## semantic version. Build metadata after a plus is read and dropped, as
    ## the precedence rule says.
    static func parse(text: String) -> Array:
        var core := text.get_slice("+", 0)
        var pre := ""
        var hyphen := core.find("-")
        if hyphen >= 0:
            pre = core.substr(hyphen + 1)
            core = core.substr(0, hyphen)
            if pre.is_empty():
                return []
        var parts := core.split(".")
        if parts.size() != 3:
            return []
        var numbers: Array = []
        for part in parts:
            if part.is_empty() or not part.is_valid_int() or part.begins_with("-") or part.begins_with("+"):
                return []
            if part.length() > 1 and part.begins_with("0"):
                return []
            numbers.append(int(part))
        numbers.append(pre)
        return numbers

    ## The order of two pre-release parts, an empty one, the release, last.
    static func compare_pre(a: String, b: String) -> int:
        if a == b:
            return 0
        if a.is_empty() or b.is_empty():
            return 1 if a.is_empty() else -1
        var left := a.split(".")
        var right := b.split(".")
        for i in mini(left.size(), right.size()):
            if left[i] == right[i]:
                continue
            var both_numbers := left[i].is_valid_int() and right[i].is_valid_int()
            if both_numbers:
                return signi(left[i].to_int() - right[i].to_int())
            if left[i].is_valid_int() != right[i].is_valid_int():
                return -1 if left[i].is_valid_int() else 1
            return -1 if left[i] < right[i] else 1
        return signi(left.size() - right.size())


## The commit a module was built from: the one an exported build's stamp names
## for the module's repository, or the one its checkout's `HEAD` names.
class Commits:
    ## The commit of the repository holding *dir_path*. A packaged module of
    ## the tree sits in a repository of its own under `res://modules/`, whose
    ## commit the build's stamp records by that folder.
    static func of_folder(dir_path: String) -> String:
        var stamped: Dictionary = {}
        var read: Variant = SaBuildInfo.read().get("modules", {})
        if read is Dictionary:
            stamped = read
        var root := dir_path
        while not root.is_empty():
            if stamped.has(root.trim_prefix("res://")):
                return str(stamped[root.trim_prefix("res://")])
            var head := SaBuildInfo.checkout_commit(ProjectSettings.globalize_path(root))
            if not head.is_empty():
                return head.substr(0, 7)
            var parent := root.get_base_dir()
            if parent == root or parent.ends_with(":/") or parent == "res://" or parent.length() < 2:
                break
            root = parent
        # A folder of Sara's own tree with no checkout and no stamp of its own,
        # the skeleton's or a fixture's, was built with Sara.
        return of_build() if dir_path.begins_with("res://") else NO_COMMIT

    ## The commit of Sara's own build, for the skeleton's module.
    static func of_build() -> String:
        var commit := str(SaBuildInfo.read().get("commit", SaBuildInfo.UNKNOWN_COMMIT))
        return NO_COMMIT if commit == SaBuildInfo.UNKNOWN_COMMIT else commit
