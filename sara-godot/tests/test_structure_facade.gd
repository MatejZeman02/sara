## The first rule of structure: a feature is a folder with one facade, and
## nothing outside the folder names any other file of it.
##
## `packages.json` is the map of the tree. Each package there says
## its kind and its public files: a feature lists the facade and whatever the
## tree already treated as a type of its own, a library is public through and
## through, and a shelf is a folder of features that are one file each. What
## this suite holds is the rest: a file of a feature that is not on the list is
## private to the folder, and a file outside the folder naming it is a debt.
##
## A file names another when it uses its `class_name`, its autoload name, or
## its `res://` path in a `preload`, a `load` or an `extends`. Comments and
## strings are not references, so a rule quoted in a doc comment and a class
## named in a `has_method` call stay out. Suites and `scripts/` are not read as
## referrers, because naming an inner class is how an inner class is tested.
## Module files are read: a module naming a skeleton's inner file is exactly
## the shape that makes a module hard to move.
##
## Every pair found is on `inner_named` of the ledgers, so the check is red
## for the first file that widens the debt. A pair the tree no longer has fails as stale, so
## the list cannot outlive what it excused. `public_files_max` is the other
## half: a face is widened by an argument in a merge that raises the number,
## never by an edit to the manifest alone.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
## The map of the tree, read by the mover and the file map.
const MANIFEST: String = "res://packages.json"

## The six layer folders every package lives under.
const LAYERS: Array[String] = ["core", "render", "tools", "ui", "utils", "harness"]

## Read as referrers beside the layers. A module that names an inner file of
## the skeleton is a debt like any other,.
const MODULES: String = "modules"

## Never descend into these, and never into a `tests` folder: a suite names
## the inner file it tests, which is not a reference across an edge.
const SKIP_DIRS: Array[String] = [".godot", ".conda", ".git", "build", "node_modules", "scratch", "tests"]

## The two layer folders that hold no script directly. No file is pinned directly in them.
const PINNED_ONLY: Array[String] = ["core", "ui"]
## The ledgers this suite reads, one line an entry: `public_files_max` is the
## width of the tree's faces, and
## `inner_named` every reference across a package's edge to a file that is not
## public, `"referrer -> inner file"`. Making an inner file public raises the number by
## one and says why in its commit, and why each entry is what it is lives in
## `git log -p structure_ledgers.json` rather than here.
const LEDGERS: String = "res://structure_ledgers.json"

## Where the planted case is written and removed again. Under `user://` so
## the editor never imports it and a run that dies mid-test leaves nothing in
## the tree.
static var scratch_dir: String = SaDataRoot.path("test_structure_facade_scratch")

## Matches an identifier, for the words a referrer uses once its comments and
## strings are gone.
var _word := RegEx.create_from_string("[A-Za-z_]\\w*")

## Matches a script path handed to `preload`, `load` or `extends`.
var _path := RegEx.create_from_string('(?:\\b(?:preload|load)\\(\\s*|\\bextends\\s+)"res://([^"]+)"')

## Matches the file's own `class_name` line.
var _class_name := RegEx.create_from_string("(?m)^class_name\\s+(\\w+)")

## Matches a double-quoted or a single-quoted string, escapes included.
var _string := RegEx.create_from_string("\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'")


## Every folder that holds a script is a package of the manifest, or holds
## only pinned files. Every public file exists, every feature lists one, and
## nothing sits directly in `core` or `ui`. The pinned list is empty.
func test_the_manifest_matches_the_tree() -> void:
    var manifest := _manifest()
    assert_false(manifest.is_empty(), "The manifest at %s could not be read" % MANIFEST)
    var packages: Dictionary = manifest.get("packages", {})
    var pinned: Array = manifest.get("pinned", [])
    assert_true(pinned.is_empty(), "Nothing is pinned, and the manifest pins %s" % ", ".join(pinned))

    var problems: Array[String] = []
    var folders := _folders_with_scripts(_root(), LAYERS)
    for folder: String in folders:
        if packages.has(folder):
            continue
        var stray: Array[String] = []
        for file: String in folders[folder]:
            if not pinned.has(folder.path_join(file)):
                stray.append(file)
        if not stray.is_empty():
            problems.append("%s is not in packages.json and holds %s" % [folder, ", ".join(stray)])
    for folder: String in PINNED_ONLY:
        for file: String in folders.get(folder, []):
            if not pinned.has(folder.path_join(file)):
                problems.append("%s sits directly in %s, and only a pinned file may" % [file, folder])
    for folder: String in packages:
        var package: Dictionary = packages[folder]
        if package["kind"] != "feature":
            if not DirAccess.dir_exists_absolute(_root().path_join(folder)):
                problems.append("%s is in packages.json and not in the tree" % folder)
            continue
        var public: Array = package["public"]
        if public.is_empty():
            problems.append("%s lists no public file" % folder)
        for file: String in public:
            if not FileAccess.file_exists(_root().path_join(folder).path_join(file)):
                problems.append("%s names a public file that does not exist, %s" % [folder, file])
    problems.sort()
    assert_true(problems.is_empty(), "The manifest and the tree disagree: %s" % "; ".join(problems))


## The debt is exactly the list. An unlisted pair names both paths, and a
## listed pair the tree no longer has is stale and fails the same way.
func test_every_inner_file_named_across_an_edge_is_listed() -> void:
    var found := _inner_named(_root(), _manifest(), _autoloads())
    assert_true(found.size() > 20, "The scan found %d pairs, so it is measuring nothing" % found.size())

    var inner_named: Dictionary = _ledgers().get("inner_named", {})
    var unlisted: Array[String] = []
    for pair: String in found:
        if not inner_named.has(pair):
            unlisted.append(pair)
    unlisted.sort()
    assert_true(
        unlisted.is_empty(),
        "A file names an inner file of another package, which the first rule of structure forbids: %s" % ", ".join(unlisted)
    )

    var stale: Array[String] = []
    for pair: String in inner_named:
        if not found.has(pair):
            stale.append("%s (%s)" % [pair, inner_named[pair]])
    stale.sort()
    assert_true(stale.is_empty(), "inner_named lists a pair the tree no longer has, so its entry is done: %s" % ", ".join(stale))


## The faces do not widen without an argument.
func test_the_public_face_is_no_wider_than_argued() -> void:
    var count := 0
    var packages: Dictionary = _manifest().get("packages", {})
    for folder: String in packages:
        if packages[folder]["kind"] == "feature":
            count += packages[folder]["public"].size()
    assert_true(count > 0, "No feature lists a public file, so the manifest was not read")
    var entry: Array = _ledgers().get("public_files_max", [])
    assert_eq(entry.size(), 2, "%s has no public_files_max, a number" % LEDGERS)
    var most: int = int(entry[0]) if entry.size() == 2 else 0
    assert_true(
        count <= most,
        (
            "%d public files over the features, and public_files_max in %s is %d: widen it in the same merge, with the reason"
            % [count, LEDGERS, most]
        )
    )


## The scan sees a case it wrote itself. Two packages, one inner file, and
## four referrers: by class name, by preload, in a comment and in a string.
## The first two are references and the other two are not.
func test_the_scan_sees_a_planted_case() -> void:
    var manifest := {
        "pinned": [],
        "packages":
        {
            "one": {"kind": "feature", "public": ["one.gd"]},
            "two": {"kind": "feature", "public": ["two.gd"]},
        },
    }
    var planted := {
        "one/one.gd": "class_name SaScratchOne\nextends RefCounted\n",
        "one/by_name.gd": "extends RefCounted\n\nvar helper := SaScratchTwoInner.new()\n",
        "one/by_preload.gd": 'extends RefCounted\n\nconst Inner := preload("res://two/two_inner.gd")\n',
        "one/in_comment.gd": "extends RefCounted\n\n# SaScratchTwoInner is named here and nowhere else.\nvar kept := 0\n",
        "one/in_string.gd": "extends RefCounted\n\nvar kept := 'SaScratchTwoInner'\n",
        "two/two.gd": "class_name SaScratchTwo\nextends RefCounted\n",
        "two/two_inner.gd": "class_name SaScratchTwoInner\nextends RefCounted\n",
    }
    _write_scratch(planted)
    var found := _inner_named(scratch_dir, manifest, {}, ["one", "two"], "")
    ScratchFolder.clear(scratch_dir)

    var pairs := found.keys()
    pairs.sort()
    assert_eq(pairs.size(), 2, "The planted case should be two references, and the scan saw %s" % [pairs])
    assert_true(found.has("one/by_name.gd -> two/two_inner.gd"), "The class name was not seen, so the check measures nothing")
    assert_true(found.has("one/by_preload.gd -> two/two_inner.gd"), "The preload was not seen, so the check measures nothing")


## The scan reaches the trees the rule is about, and the reference kinds it
## claims to read.
func test_the_scan_reaches_the_code_it_claims_to_check() -> void:
    var referrers := _referrers(_root(), LAYERS, MODULES)
    assert_true(referrers.size() > 300, "The scan found only %d referrers, so it is measuring nothing" % referrers.size())
    assert_true(referrers.has("ui/main/main.gd"), "The scan never reached the interface")
    assert_true(referrers.has("modules/sara-base-modules/base/module.gd"), "The scan never reached the modules")
    var suites := 0
    for path: String in referrers:
        if path.contains("/tests/") or path.begins_with("tests/"):
            suites += 1
    assert_eq(suites, 0, "A suite was read as a referrer")
    assert_true(_autoloads().size() >= 6, "project.godot lists %d autoloads, and Sara has six" % _autoloads().size())


## Every `"referrer -> inner file"` pair under *root* by the manifest, the
## reference kinds above, with *roots* as the folders read as referrers and
## *modules* read beside them when it is not empty.
func _inner_named(
    root: String, manifest: Dictionary, autoloads: Dictionary, roots: Array[String] = LAYERS, modules: String = MODULES
) -> Dictionary:
    var inner := _inner_files(root, manifest)
    var names := {}
    var known_paths := {}
    for file: String in inner:
        known_paths[file] = true
        var found := _class_name.search(_read(root.path_join(file)))
        if found != null:
            names[found.get_string(1)] = file
        if autoloads.has(file):
            names[autoloads[file]] = file

    var pairs := {}
    for referrer: String in _referrers(root, roots, modules):
        var own_folder := referrer.get_base_dir()
        var code := _code(_read(root.path_join(referrer)))
        var named := {}
        for found: RegExMatch in _path.search_all(code):
            var path := found.get_string(1)
            if known_paths.has(path):
                named[path] = true
        for found: RegExMatch in _word.search_all(_string.sub(code, "", true)):
            var word := found.get_string()
            if names.has(word):
                named[names[word]] = true
        for file: String in named:
            if file.get_base_dir() != own_folder:
                pairs["%s -> %s" % [referrer, file]] = true
    return pairs


## Every non-public script of a feature, relative to *root*.
func _inner_files(root: String, manifest: Dictionary) -> Array[String]:
    var out: Array[String] = []
    var packages: Dictionary = manifest.get("packages", {})
    for folder: String in packages:
        var package: Dictionary = packages[folder]
        if package["kind"] != "feature":
            continue
        var public: Array = package["public"]
        for file: String in _scripts_in(root.path_join(folder)):
            if not public.has(file):
                out.append(folder.path_join(file))
    out.sort()
    return out


## Every script read as a referrer, relative to *root*.
func _referrers(root: String, roots: Array[String], modules: String) -> Array[String]:
    var out: Array[String] = []
    var folders := roots.duplicate()
    if not modules.is_empty():
        folders.append(modules)
    for folder: String in folders:
        _walk(root.path_join(folder), folder + "/", out)
    out.sort()
    return out


func _walk(dir_path: String, prefix: String, out: Array[String]) -> void:
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return
    dir.list_dir_begin()
    var entry := dir.get_next()
    while not entry.is_empty():
        if dir.current_is_dir():
            if not SKIP_DIRS.has(entry):
                _walk(dir_path.path_join(entry), prefix + entry + "/", out)
        elif entry.get_extension() == "gd":
            out.append(prefix + entry)
        entry = dir.get_next()
    dir.list_dir_end()


## `{folder: [script names]}` for every folder under *roots* that holds a
## script directly, folders relative to *root*.
func _folders_with_scripts(root: String, roots: Array[String]) -> Dictionary:
    var out := {}
    var scripts: Array[String] = []
    for folder: String in roots:
        _walk(root.path_join(folder), folder + "/", scripts)
    for path: String in scripts:
        var folder := path.get_base_dir()
        if not out.has(folder):
            out[folder] = []
        out[folder].append(path.get_file())
    return out


## The scripts directly in *dir_path*, names only.
func _scripts_in(dir_path: String) -> Array[String]:
    var out: Array[String] = []
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return out
    dir.list_dir_begin()
    var entry := dir.get_next()
    while not entry.is_empty():
        if not dir.current_is_dir() and entry.get_extension() == "gd":
            out.append(entry)
        entry = dir.get_next()
    dir.list_dir_end()
    out.sort()
    return out


## The manifest as `{"pinned": [paths], "packages": {dir: entry}}`, empty when
## it cannot be read.
func _manifest() -> Dictionary:
    var parsed: Variant = JSON.parse_string(_read(MANIFEST))
    if not parsed is Dictionary:
        return {}
    var packages := {}
    for entry: Dictionary in parsed.get("packages", []):
        packages[entry["dir"]] = entry
    var pinned: Array[String] = []
    for entry: Dictionary in parsed.get("pinned", []):
        pinned.append(entry["file"])
    return {"pinned": pinned, "packages": packages}


## `{script path: autoload name}` from `project.godot`.
func _autoloads() -> Dictionary:
    var out := {}
    var line := RegEx.create_from_string('(?m)^(\\w+)="\\*?res://([^"]+)"')
    for found: RegExMatch in line.search_all(_read("res://project.godot")):
        out[found.get_string(2)] = found.get_string(1)
    return out


## The file with its comment lines removed.
func _code(text: String) -> String:
    var kept: Array[String] = []
    for line in text.split("\n"):
        if not line.strip_edges().begins_with("#"):
            kept.append(line)
    return "\n".join(kept)


func _root() -> String:
    return ProjectSettings.globalize_path("res://").rstrip("/")


func _read(path: String) -> String:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return ""
    return file.get_as_text()


func _write_scratch(planted: Dictionary) -> void:
    for name: String in planted:
        var path := scratch_dir.path_join(name)
        DirAccess.make_dir_recursive_absolute(path.get_base_dir())
        var file := FileAccess.open(path, FileAccess.WRITE)
        assert_not_null(file, "The planted case could not be written to %s" % path)
        if file != null:
            file.store_string(String(planted[name]))
            file.close()


## The ledger file parsed, an empty `Dictionary` when it is missing or broken,
## which the two tests that read it then fail on.
func _ledgers() -> Dictionary:
    var parsed: Variant = JSON.parse_string(_read(LEDGERS))
    return parsed if parsed is Dictionary else {}
