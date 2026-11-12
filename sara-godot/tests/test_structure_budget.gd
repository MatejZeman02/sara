## No package grows past its line budget unnoticed, the sixth rule of structure in CONTRIBUTING.md:
## "A folder read whole stays under about 2500 lines." The
## manifest at `packages.json` names every package of the skeleton, and the
## folders of the modules are the ones `AREAS` of `scripts/gen_file_map.py`
## gives a page of the file map, read out of that list rather than kept twice. This suite sums the `.gd` files
## sitting directly in each
## folder, never the files of a child folder nested inside it, since `core/api`
## and `core/api/color` are measured apart.
extends "res://tests/test_framework.gd"

## Where the manifest lives.
const MANIFEST_PATH: String = "res://packages.json"

## The file map's generator, whose `AREAS` list names every module folder.
const FILE_MAP_PATH: String = "res://scripts/gen_file_map.py"

## A package over this many lines is a folder that can no longer be read
## whole in one pass.
const BUDGET: int = 2500

## Where the ledger lives: `budget_over` there lists the folders already over
## the budget, each with the lines it was last measured at and the reason, one line an entry. A folder over the budget and not
## listed fails, a listed folder that grows past its recorded lines fails, and
## a listed folder that has dropped to the budget or under fails as stale: a
## band nobody measures is worse than no band. Growing a folder edits its line
## there and no suite. Why each number is what it is, is the file's history in
## git, `git log -p structure_ledgers.json`, never a paragraph here.
const LEDGERS_PATH: String = "res://structure_ledgers.json"

## One module folder the file map is known to list, so a reshaped `AREAS` that
## this suite can no longer read fails instead of measuring nothing.
const KNOWN_MODULE_DIR: String = "modules/sara-base-modules/stamp-brush/walk"

## Where the planted package is written and removed again. A plain `var`, never
## a `static var`: `_planted_lines` reading a static of this script made the
## script hold itself past the run, and at exit that took `test_framework.gd`
## down under the engine's own walk and left 673 objects leaked.
var scratch_dir: String = SaDataRoot.path("test_structure_budget_scratch")


## Every package of the manifest and every module folder of the file map,
## over budget and not on `budget_over`, fails the run. A listed folder is entitled to
## grow no further than the lines `budget_over` recorded for it: past that, the folder has outgrown its entry,
## and the number needs raising in the
## same commit as whatever grew it.
func test_no_package_grows_past_its_budget_unlisted() -> void:
    var ledger: Variant = JSON.parse_string(FileAccess.get_file_as_string(LEDGERS_PATH))
    var read := ledger is Dictionary and (ledger as Dictionary).get("budget_over") is Dictionary
    assert_true(read, "%s has no budget_over" % LEDGERS_PATH)
    var measured := _measure_packages()
    assert_false(measured.is_empty(), "The manifest named no packages, so nothing was measured")
    _assert_no_breach(_breaches(measured))


## The module folders are read out of the file map's own list, and the base
## module's are among them, so a module folder is measured the day it gets a
## page rather than the day somebody remembers a second list.
func test_the_module_folders_come_from_the_file_map() -> void:
    var dirs := _module_dirs()
    assert_true(
        dirs.has(KNOWN_MODULE_DIR),
        "%s did not list %s among its module folders, read %s" % [FILE_MAP_PATH, KNOWN_MODULE_DIR, ", ".join(dirs)]
    )
    var measured := _measure_packages()
    for dir: String in dirs:
        assert_true(measured.has(dir), "The module folder %s was listed and not measured" % dir)


## The second half of the same allowlist. An entry on `budget_over` whose folder has
## come back under the budget is no longer earning its place, and the reason
## it was listed is named so it can be dropped without measuring again.
func test_a_listed_package_under_budget_is_stale() -> void:
    var measured := _measure_packages()
    var stale: Array[String] = []
    var over := _over()
    for dir: String in over:
        # A source copy leaves some module folders out, so an entry for one has
        # nothing there to have come back under the budget.
        if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://" + dir)):
            continue
        var lines: int = measured.get(dir, 0)
        if lines <= BUDGET:
            stale.append("%s, listed for %s" % [dir, over[dir][1]])
    stale.sort()
    assert_true(
        stale.is_empty(),
        "No longer over budget, remove its line from budget_over in %s in the same commit: %s" % [LEDGERS_PATH, ", ".join(stale)]
    )


## The check sees a package planted beside it, and proves the scan actually
## measures rather than trusting the manifest alone.
func test_a_planted_package_over_budget_is_caught() -> void:
    var lines := _planted_lines()
    assert_eq(lines, BUDGET + 1, "The planted package should read as %d lines and read %d" % [BUDGET + 1, lines])
    assert_true(lines > BUDGET, "A %d line package should read as over the %d budget" % [lines, BUDGET])


## A module folder the file map listed, measured past the budget and not on
## `budget_over`, is a breach the run fails on.
func test_a_planted_module_folder_over_budget_is_caught() -> void:
    var planted := "modules/sara-base-modules/planted"
    var breaches := _breaches({planted: _planted_lines()})
    assert_eq(breaches[0], ["%s (%d)" % [planted, BUDGET + 1]], "A planted module folder past the budget was not caught")


## A folder `budget_over` lists, grown one line past what it recorded, fails the
## run, and at exactly the recorded lines it passes. The first listed folder
## stands in, and the stamp brush's tools grown past the budget fail as
## unlisted. With nothing listed there is no record to grow past.
func test_a_listed_folder_grown_past_its_record_fails() -> void:
    var unlisted := _breaches({KNOWN_MODULE_DIR: BUDGET + 1})
    assert_eq(unlisted[0], ["%s (%d)" % [KNOWN_MODULE_DIR, BUDGET + 1]], "The stamp brush's walk past the budget should fail")
    var over := _over()
    if over.is_empty():
        return
    var dir: String = over.keys()[0]
    var recorded: int = over[dir][0]
    var held := _breaches({dir: recorded})
    assert_true(held[0].is_empty() and held[1].is_empty(), "At its recorded %d lines %s should pass" % [recorded, dir])
    var grown := _breaches({dir: recorded + 1})
    assert_eq(grown[1], ["%s grew from %d to %d" % [dir, recorded, recorded + 1]], "One line past its record should fail")


## `[unlisted, grown]` for *measured*, `{dir: lines}`: the folders over budget
## and not on `budget_over`, and the listed ones past the lines `budget_over` recorded, each
## a sorted list of the lines the failure prints.
func _breaches(measured: Dictionary) -> Array:
    var unlisted: Array[String] = []
    var grown: Array[String] = []
    var over := _over()
    for dir: String in measured:
        var lines: int = measured[dir]
        if lines <= BUDGET:
            continue
        if not over.has(dir):
            unlisted.append("%s (%d)" % [dir, lines])
            continue
        var recorded: int = over[dir][0]
        if lines > recorded:
            grown.append("%s grew from %d to %d" % [dir, recorded, lines])
    unlisted.sort()
    grown.sort()
    return [unlisted, grown]


## Fails the run on either half of *breaches*, as `_breaches` returns them.
func _assert_no_breach(breaches: Array) -> void:
    assert_true(
        breaches[0].is_empty(),
        (
            "Over %d lines and not in budget_over: %s. Read whole, that is a piece of the tree the rule was written for."
            % [BUDGET, ", ".join(breaches[0])]
        )
    )
    assert_true(
        breaches[1].is_empty(),
        (
            "Grew past the lines budget_over recorded, raise its number in %s in the same commit: %s"
            % [LEDGERS_PATH, ", ".join(breaches[1])]
        )
    )


## The lines of a folder planted under `user://` with one file of the budget
## and a line more, measured by the same scan the tree is, then removed.
func _planted_lines() -> int:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var name := "sa_scratch_budget.gd"
    var file := FileAccess.open(scratch_dir.path_join(name), FileAccess.WRITE)
    assert_not_null(file, "The scratch package could not be written to %s" % scratch_dir)
    if file == null:
        return 0
    var body := "extends RefCounted\n"
    for i in range(BUDGET):
        body += "# line\n"
    file.store_string(body)
    file.close()
    var lines := _lines_directly_in(scratch_dir)
    DirAccess.remove_absolute(scratch_dir.path_join(name))
    return lines


## `{dir: lines}` for every package the manifest names and every module folder
## the file map lists, `dir` spelled as its list spells it and measured under
## `res://`.
func _measure_packages() -> Dictionary:
    var measured: Dictionary = {}
    for entry: Dictionary in _load_manifest():
        var dir: String = entry["dir"]
        measured[dir] = _lines_directly_in("res://" + dir)
    for dir: String in _module_dirs():
        measured[dir] = _lines_directly_in("res://" + dir)
    return measured


## Every folder under `modules/` that `AREAS` of the file map's generator
## names, in its order. The list is Python, read here as text: each entry opens
## with the folder as a quoted string, and nothing else in the list is a string
## starting `modules/`.
func _module_dirs() -> Array[String]:
    var dirs: Array[String] = []
    var file := FileAccess.open(FILE_MAP_PATH, FileAccess.READ)
    assert_not_null(file, "The file map's generator could not be opened at %s" % FILE_MAP_PATH)
    if file == null:
        return dirs
    var text := file.get_as_text()
    var start := text.find("\nAREAS = [")
    var end := text.find("\n]\n", start)
    assert_true(start >= 0 and end > start, "No AREAS list was found in %s" % FILE_MAP_PATH)
    if start < 0 or end < start:
        return dirs
    var row := RegEx.create_from_string('"(modules/[^"]+)"')
    for found: RegExMatch in row.search_all(text.substr(start, end - start)):
        dirs.append(found.get_string(1))
    return dirs


## The `.gd` files sitting directly in *dir_path*, summed by line count.
## A subfolder is never descended into: it is either another package, measured
## on its own entry, or a shelf's own concern, and either way this package does
## not answer for what is not directly its own.
func _lines_directly_in(dir_path: String) -> int:
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return 0
    var total := 0
    dir.list_dir_begin()
    var entry := dir.get_next()
    while not entry.is_empty():
        if not dir.current_is_dir() and entry.get_extension() == "gd":
            total += _line_count(dir_path.path_join(entry))
        entry = dir.get_next()
    dir.list_dir_end()
    return total


## Lines as `wc -l` would count them: a trailing newline ends the last line,
## it does not start an empty one.
func _line_count(path: String) -> int:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return 0
    var lines := file.get_as_text().split("\n")
    var count := lines.size()
    if count > 0 and lines[count - 1].is_empty():
        count -= 1
    return count


## The manifest's `packages` array, each entry a `Dictionary` with a `dir` key.
func _load_manifest() -> Array:
    var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
    assert_not_null(file, "The manifest could not be opened at %s" % MANIFEST_PATH)
    if file == null:
        return []
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    assert_true(
        parsed is Dictionary and (parsed as Dictionary).has("packages"), "The manifest did not parse as a packages object"
    )
    if not (parsed is Dictionary and (parsed as Dictionary).has("packages")):
        return []
    return (parsed as Dictionary)["packages"]


## `budget_over` of the ledger, `{dir: [lines, reason]}` with each number an
## `int`, since JSON hands every number back as a float.
func _over() -> Dictionary:
    var over: Dictionary = {}
    var file := FileAccess.open(LEDGERS_PATH, FileAccess.READ)
    if file == null:
        return over
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if not (parsed is Dictionary and (parsed as Dictionary).get("budget_over") is Dictionary):
        return over
    var listed: Dictionary = (parsed as Dictionary)["budget_over"]
    for dir: String in listed:
        var entry: Array = listed[dir]
        over[dir] = [int(entry[0]), String(entry[1])]
    return over
