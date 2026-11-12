## The skeleton names no module, so it boots with `modules/`
## empty.
##
## Two halves. The launch half is `scripts/check_skeleton_boots.py`, which
## `run_tests.sh` runs after this suite: the loader finds nothing, the toolbox
## draws its empty state, the console carries no error. This is the parse
## half, which a launch in a tree that still holds the module scripts cannot
## see: a skeleton file that names a module's `class_name` parses here because
## the class resolves, and fails to parse in a checkout without the submodules,
## which is the checkout the README's claim is about. So this reads every file
## under `core/`, `ui/` and `render/` outside the loader, comment lines
## removed the way `test_hard_rules.gd` reads them, for a path under the
## modules directory and for every `class_name` the modules declare.
##
## The names are read off the modules rather than listed here, so a class a
## module adds tomorrow is watched the day it appears.
##
## **The allowlist is the list of files the claim is still false for.** It is
## empty, and a new file cannot join it without a reason written here.
extends "res://tests/test_framework.gd"

const LOADER := "core/loader/module_loader.gd"
const ROOTS: Array[String] = ["core", "ui", "render", "harness"]
const MODULES_DIR := "res://modules"
const SKIP_DIRS: Array[String] = [".godot", ".conda", ".git", "build", "node_modules", "scratch"]

## The files that still name a module class, and which class. A file
## here is one the skeleton cannot parse without the stamp brush, and the
## test fails when one of them stops naming a module class without leaving
## this list, so the list cannot rot into an exemption.
const STILL_NAMING: Dictionary = {}


func test_no_skeleton_file_carries_a_path_under_the_modules_directory() -> void:
    var offenders: Array[String] = []
    for path in _skeleton_sources():
        if _code(_read(path)).contains("res://modules/"):
            offenders.append(path)
    assert_true(offenders.is_empty(), "A path under the modules directory in the skeleton: %s" % ", ".join(offenders))


func test_no_skeleton_file_names_a_module_class_outside_the_list() -> void:
    var names := _module_class_names()
    assert_true(names.size() >= 10, "The modules declare classes to look for, found %d" % names.size())
    var offenders: Array[String] = []
    for path in _skeleton_sources():
        var named := _names_in(_code(_read(path)), names)
        if named.is_empty():
            continue
        var allowed: Array = STILL_NAMING.get(path, [])
        for name in named:
            if not allowed.has(name):
                offenders.append("%s names %s" % [path, name])
    assert_true(
        offenders.is_empty(), "A skeleton file names a module class the allowlist does not carry: %s" % ", ".join(offenders)
    )


## The other direction: a file on the list has to still deserve its place,
## and every class it is listed for has to still be named, or the list is
## stale and says the claim is falser than it is.
func test_the_list_of_files_still_naming_a_module_class_is_current() -> void:
    var names := _module_class_names()
    for path: String in STILL_NAMING:
        var named := _names_in(_code(_read(path)), names)
        for name: String in STILL_NAMING[path]:
            assert_true(named.has(name), "%s no longer names %s, so it leaves the allowlist" % [path, name])


func test_the_wand_step_asks_the_flood_role() -> void:
    var code := _code(_read("harness/drivers/sa_canvas_driver.gd"))
    assert_true(code.contains('_engine_for(tree, &"flood")'), "The capture's wand step asks the role registry")
    assert_false(code.contains("SaWand"), "and names no wand class")


## Every `class_name` declared under the modules directory, whichever module
## layout the folder uses.
func _module_class_names() -> Array[String]:
    var out: Array[String] = []
    var declared := RegEx.create_from_string("(?m)^class_name\\s+(\\w+)")
    var files: Array[String] = []
    _walk(MODULES_DIR, "modules/", files)
    for path in files:
        for found in declared.search_all(_read(path)):
            var name := found.get_string(1)
            if not out.has(name):
                out.append(name)
    out.sort()
    return out


## The module class names *code* mentions as a whole word.
func _names_in(code: String, names: Array[String]) -> Array[String]:
    var out: Array[String] = []
    for name in names:
        var whole := RegEx.create_from_string("\\b%s\\b" % name)
        if whole.search(code) != null:
            out.append(name)
    return out


## Every `.gd` under the three roots, as a path relative to the project, with
## the loader left out because the modules directory is its subject.
func _skeleton_sources() -> Array[String]:
    var out: Array[String] = []
    for root in ROOTS:
        _walk("res://" + root, root + "/", out)
    out.erase(LOADER)
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
            if not SKIP_DIRS.has(entry) and entry != "tests":
                _walk(dir_path.path_join(entry), prefix + entry + "/", out)
        elif entry.get_extension() == "gd":
            out.append(prefix + entry)
        entry = dir.get_next()
    dir.list_dir_end()


## The file with its comments removed, the way `test_hard_rules.gd` reads a
## file and one step further: a class named in a doc comment or after the
## code on a line is prose about it, and prose parses without the class. A
## `#` inside a string is kept, because only one preceded by whitespace or
## doubled is read as a comment.
func _code(text: String) -> String:
    var kept: Array[String] = []
    var doc := RegEx.create_from_string("##.*$")
    var trailing := RegEx.create_from_string("\\s#.*$")
    for line in text.split("\n"):
        if line.strip_edges().begins_with("#"):
            continue
        kept.append(trailing.sub(doc.sub(line, ""), ""))
    return "\n".join(kept)


func _read(relative: String) -> String:
    var file := FileAccess.open("res://" + relative, FileAccess.READ)
    if file == null:
        return ""
    return file.get_as_text()
