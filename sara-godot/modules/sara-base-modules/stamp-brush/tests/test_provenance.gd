## The Krita copyright lines this module owes, checked against its own
## provenance file.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A port carries the original copyright lines verbatim beside Sara's own
## `SPDX-License-Identifier: GPL-3.0-or-later`. That is a licence obligation, and
## unchecked it is one refactor from being lost: a header comment is the first
## thing a rewrite drops and the last thing anybody notices.
##
## **The input moved and the questions did not.** This suite read the Provenance
## table of the brush engine spec, and its sibling in the skeleton read the
## other spec's. Every line the brush still owes is gathered into
## `../PROVENANCE.md`, one page at the top of this module. So this reads that
## page.
##
## **This suite sweeps the module and its sibling sweeps the skeleton.**
## `res://tests/test_dynamics_provenance.gd` is the other half, over
## `ui/brush_editor/`, `ui/widgets/` and `core/`. Two territories, and neither reads
## the other's files, because two gates asserting one thing is how the two drift.
##
## **What it cannot check.** This asserts that a file
## carries what it is granted and nothing it is not, and never that the grant is
## true: that the mechanism named is in the code, in that file, and taken rather
## than thought of. That is read by hand, against Krita 5.2.13.
extends "res://tests/test_framework.gd"

## The one page that grants a line, and the two the specs still keep as the
## record of what was read. All three are outside `res://`, so they are reached
## from the repository root.
const PROVENANCE: String = "sara-godot/modules/sara-base-modules/stamp-brush/PROVENANCE.md"

## The pages outside the module: `core/api/dynamics` holds the sensor and the
## stroke state with their two ports, `core/api/tip` the tip image with its one,
## and `ui/widgets/curve_option` the curve option control with its one. Read here
## only for their counts and their names, which the spec tables and
## `THIRDPARTY.txt` sum over every page. Their files are swept by the
## skeleton's suite, never by this one.
const DOOR_PAGES: Array[String] = [
    "sara-godot/core/api/dynamics/PROVENANCE.md",
    "sara-godot/core/api/tip/PROVENANCE.md",
    "sara-godot/ui/widgets/curve_option/PROVENANCE.md",
]
const SPEC: String = "docs/specs/brush-engine.md"
const DYNAMICS_SPEC: String = "docs/specs/brush-dynamics.md"

const THIRDPARTY: String = "THIRDPARTY.txt"

## The version of Krita every grant is read from. `THIRDPARTY.txt` and the
## provenance file have to name the same one, or the lines are quoted from a
## source nobody can find again.
const KRITA_VERSION: String = "5.2.13"

## Everything under the module that could carry a header, swept in both
## directions. Not the tests directory: this file quotes lines in prose and would
## fail its own sweep, which is the same trap from the other side.
const SWEPT: Array[String] = [
    "res://modules/sara-base-modules/stamp-brush",
    "res://modules/sara-base-modules/stamp-brush/tools",
    "res://modules/sara-base-modules/stamp-brush/krita",
    "res://modules/sara-base-modules/stamp-brush/presets",
    "res://modules/sara-base-modules/stamp-brush/pattern",
    "res://modules/sara-base-modules/stamp-brush/shaders",
    "res://modules/sara-base-modules/stamp-brush/ui",
]


func test_every_module_file_the_page_names_carries_the_lines_it_grants() -> void:
    var page := _read(_repo_path(PROVENANCE))
    assert_false(page.is_empty(), "%s is readable from a test" % PROVENANCE)
    assert_true(page.contains("Krita %s" % KRITA_VERSION), "%s names Krita %s" % [PROVENANCE, KRITA_VERSION])

    var granted := _granted(page)
    assert_eq(granted.size(), _stated_files(page), "the page names as many files as its own sentence says")

    var mine := 0
    for path: String in granted:
        if not path.begins_with("res://modules/"):
            continue
        mine += 1
        var absolute := ProjectSettings.globalize_path(path)
        assert_true(FileAccess.file_exists(absolute), "%s exists" % path)
        var text := _read(absolute)
        assert_true(text.contains("SPDX-License-Identifier: GPL-3.0-or-later"), "%s carries Sara's own licence" % path)
        assert_true(text.contains("PROVENANCE.md"), "%s points at the page that holds its lines" % path)
    assert_true(mine > 0, "the page grants lines to files of this module, %d of them" % mine)


## The reverse direction: a file carrying a line no section gives it.
## A wrong block is exactly this, because the line it carries belongs elsewhere.
func test_no_module_file_carries_a_line_the_page_does_not_grant() -> void:
    var page := _read(_repo_path(PROVENANCE))
    var granted := _granted(page)

    var swept := 0
    for directory: String in SWEPT:
        for path: String in _sources_under(directory):
            swept += 1
            var present := _copyright_lines(_read(ProjectSettings.globalize_path(path)))
            if present.is_empty():
                continue
            assert_true(granted.has(path), "%s carries a copyright line, so the provenance file has to name it" % path)
            var allowed: Dictionary = {}
            for line: String in granted.get(path, []):
                allowed[_fold(line)] = true
            for line: String in present:
                assert_true(allowed.has(line), "%s carries '%s', which the page does not grant it" % [path, line])
    assert_true(swept > 15, "the module was walked rather than silently empty, %d source files" % swept)


## Each page says how many rows it has, and this is what makes that sentence
## true.
##
## **The counts are read from the pages, never written here as literals.** A
## number frozen in a suite against a tree that keeps changing is not a check,
## it is a toll on every change.
##
## What the numbers were actually guarding is a parse that quietly returns
## nothing: rename a heading, break a regex, and a loop asserts nothing at all
## and the suite goes green over a licence obligation it never read. So the guard
## stays and the number is read from the sentence the page already states.
##
## **The counts are spelled in words, and that is deliberate rather than in the
## way.** The pages are prose and a digit in the middle of a sentence reads as a
## number the reader is meant to do something with.
func test_each_page_agrees_with_the_count_it_states() -> void:
    if not FileAccess.file_exists(_repo_path(SPEC)):
        skip("the brush engine spec is not in this copy of the source")
        return
    var spec := _read(_repo_path(SPEC))
    var table := _stated_table_counts(spec)
    assert_eq(table.size(), 3, "%s states its table's counts, as ports, ideas and rows" % SPEC)
    assert_eq(_rows_of_kind(spec, "port"), table[0], "%s counts its own port rows" % SPEC)
    assert_eq(_rows_of_kind(spec, "idea"), table[1], "and its idea rows")
    assert_eq(_rows_of_kind(spec, "port") + _rows_of_kind(spec, "idea"), table[2], "and the two together are its total")

    var page := _read(_repo_path(PROVENANCE))
    var ports := _stated_ports(page)
    assert_true(ports > 0, "%s says how many ports it grants" % PROVENANCE)
    assert_eq(_granted(page).size(), _stated_files(page), "%s counts its own sections" % PROVENANCE)
    var door_ports := 0
    for door_page: String in DOOR_PAGES:
        var stated := _stated_ports(_read(_repo_path(door_page)))
        assert_true(stated > 0, "%s says how many ports it grants" % door_page)
        door_ports += stated
    assert_eq(
        _rows_of_kind(spec, "port") + _dynamics_ports(_read(_repo_path(DYNAMICS_SPEC))),
        ports + door_ports,
        "and the two spec tables' port rows come to every page's ports together"
    )


## The provenance has to be findable from the root of the tree and not only from
## a page inside a module nobody outside this repository unpacks.
##
## **The list a packager reads is the one artefact of the four that is not a
## design document**, and it is the one nothing held until this suite did:
## `THIRDPARTY.txt` said "Six files carry them, and no others" for as long as the
## dynamics half existed, which was eight files it named nowhere.
func test_thirdparty_names_krita_the_page_and_every_ported_file() -> void:
    var text := _read(_repo_path(THIRDPARTY))
    assert_false(text.is_empty(), "%s is readable" % THIRDPARTY)
    assert_true(text.contains("Krita %s" % KRITA_VERSION), "%s names Krita %s" % [THIRDPARTY, KRITA_VERSION])
    for page_path: String in [PROVENANCE] + DOOR_PAGES:
        assert_true(text.contains(page_path.trim_prefix("sara-godot/")), "%s points at %s" % [THIRDPARTY, page_path])
    # The file rides in every build and reads whole there, and the specs are not
    # public, so it names them by what they are and never by their paths.
    for spec_path: String in [SPEC, DYNAMICS_SPEC]:
        assert_false(text.contains(spec_path), "%s names %s by what it is, not its path" % [THIRDPARTY, spec_path])
    assert_true(text.contains("two brush"), "%s names the two brush specs" % THIRDPARTY)

    var named := _granted(_read(_repo_path(PROVENANCE))).keys()
    for door_page: String in DOOR_PAGES:
        named.append_array(_granted(_read(_repo_path(door_page))).keys())
    assert_false(named.is_empty(), "the page names the files a packager has to find")
    for sara_path: String in named:
        var without_scheme := String(sara_path).trim_prefix("res://")
        assert_true(text.contains(without_scheme), "%s names %s" % [THIRDPARTY, without_scheme])


## `res://` path -> the copyright lines the page grants it.
##
## A section opens with a level-three heading whose whole text is a backticked
## `res://` path, and every fenced block under it up to the next heading holds
## that section's lines.
func _granted(page: String) -> Dictionary:
    var out: Dictionary = {}
    var heading := RegEx.create_from_string("^###\\s+`(res://[^`]+)`\\s*$")
    var path := ""
    var fenced := false
    for raw: String in page.split("\n"):
        var line := raw.strip_edges()
        if line.begins_with("#") and not fenced:
            var found := heading.search(line)
            path = found.get_string(1) if found != null else ""
            if found != null:
                out[path] = [] as Array[String]
            continue
        if line == "```":
            fenced = not fenced
            continue
        if not fenced or path.is_empty():
            continue
        var tag := line.find("SPDX-FileCopyrightText:")
        if tag >= 0:
            var lines: Array[String] = out[path]
            lines.append(_fold(line.substr(tag).strip_edges()))
    return out


## A `SPDX-FileCopyrightText:` that opens a sentence is not a copyright line, and
## both of the two that did were read as one by every reader until this suite
## ran.
func test_no_grant_uses_the_copyright_tag_for_prose() -> void:
    for path: String in _granted(_read(_repo_path(PROVENANCE))):
        for line: String in _granted(_read(_repo_path(PROVENANCE)))[path]:
            var body := line.substr("SPDX-FileCopyrightText:".length()).strip_edges()
            assert_true(
                body.length() > 0 and body[0].is_valid_int(),
                "%s: a copyright line starts with a year, not with '%s'" % [path, body.left(40)]
            )
            assert_true(body.contains("<") and body.contains(">"), "%s: %s names an address" % [path, body])


## How many rows of *spec*'s table read *kind*, port or idea.
func _rows_of_kind(spec: String, kind: String) -> int:
    var count := 0
    for row: String in spec.split("\n"):
        if not row.begins_with("|") or row.begins_with("|---"):
            continue
        var cells := row.trim_prefix("|").split("|")
        if cells.size() >= 4 and cells[2].strip_edges().begins_with(kind):
            count += 1
    return count


## The dynamics table writes its verdict in the same column and spells its
## reason after a comma, so a row reading `idea, then a code: ...` counts as an idea and
## `port, and a code left it one: ...` as a port.
func _dynamics_ports(spec: String) -> int:
    return _rows_of_kind(spec, "port")


## "One port and twenty-nine ideas, thirty rows", spelled in words.
func _stated_table_counts(spec: String) -> Array[int]:
    var found := RegEx.create_from_string("([\\w-]+) ports? and ([\\w-]+) ideas?, ([\\w-]+) rows").search(spec)
    if found == null:
        return [] as Array[int]
    var out: Array[int] = []
    for i: int in [1, 2, 3]:
        out.append(_spelled(found.get_string(i)))
    return out


func _stated_ports(page: String) -> int:
    var found := RegEx.create_from_string("(\\w+) ports? in (\\w+) files?, and no others").search(page)
    return -1 if found == null else _spelled(found.get_string(1))


func _stated_files(page: String) -> int:
    var found := RegEx.create_from_string("(\\w+) ports? in (\\w+) files?, and no others").search(page)
    return -1 if found == null else _spelled(found.get_string(2))


func _spelled(word: String) -> int:
    var words: Array[String] = [
        "zero",
        "one",
        "two",
        "three",
        "four",
        "five",
        "six",
        "seven",
        "eight",
        "nine",
        "ten",
        "eleven",
        "twelve",
        "thirteen",
        "fourteen",
        "fifteen",
        "sixteen",
        "seventeen",
        "eighteen",
        "nineteen",
        "twenty",
    ]
    var at := words.find(word.to_lower())
    if at >= 0:
        return at
    var tens := {"twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70}
    var parts := word.to_lower().split("-")
    if not tens.has(parts[0]):
        return -1
    if parts.size() == 1:
        return int(tens[parts[0]])
    var unit := words.find(parts[1])
    return int(tens[parts[0]]) + unit if parts.size() == 2 and unit >= 0 else -1


## Every source file directly under *directory* that could carry a header,
## sorted so two runs agree. Not recursive: the four swept directories are named
## one by one above, so a new one is a decision rather than a walk's accident.
func _sources_under(directory: String) -> Array[String]:
    var out: Array[String] = []
    if not DirAccess.dir_exists_absolute(directory):
        return out
    var names := DirAccess.get_files_at(directory)
    names.sort()
    for name: String in names:
        if name.ends_with(".gd") or name.ends_with(".gmacs"):
            out.append(directory.path_join(name))
    return out


func _copyright_lines(text: String) -> Dictionary:
    var out: Dictionary = {}
    var pattern := RegEx.create_from_string("SPDX-FileCopyrightText:[^\\n]*")
    for found in pattern.search_all(text):
        var line := found.get_string().strip_edges().trim_suffix("*/").strip_edges()
        out[_fold(line)] = true
    return out


## One line as it is compared, with the diacritics of the one name that has them
## folded away, so a page that has been through a tool that mangles them still
## matches. Three substitutions rather than a general transliteration, because a
## general one would quietly accept a different name folding to the same letters.
func _fold(line: String) -> String:
    return line.replace("á", "a").replace("š", "s").replace("ý", "y")


func _repo_path(relative: String) -> String:
    return ProjectSettings.globalize_path("res://").path_join("..").path_join(relative).simplify_path()


func _read(absolute: String) -> String:
    var file := FileAccess.open(absolute, FileAccess.READ)
    if file == null:
        return ""
    return file.get_as_text()
