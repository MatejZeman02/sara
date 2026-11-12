## The Krita copyright lines the skeleton's half of the brush owes, checked
## against the door's provenance file.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The suite asks two questions of the provenance pages:
##
## 1. Every line the provenance file grants a Sara file is in that file's own
##    section, verbatim, so a packager reading one page finds them all.
## 2. No source file in the three skeleton directories the brush reaches into
##    carries a copyright line the provenance file does not grant it.
##
## The second keeps a line owed elsewhere out of a file. A copyright line in a
## file that is owed nothing credits the wrong person and leaves the person owed
## the attribution uncredited.
##
## **This suite sweeps the skeleton and the module's own suite sweeps the
## module.** Two territories, and the skeleton's half has the pages
## `core/api/dynamics/PROVENANCE.md`, `core/api/tip/PROVENANCE.md` and
## `ui/widgets/curve_option/PROVENANCE.md`, and neither half reads the other's
## files:
## `modules/sara-base-modules/stamp-brush/tests/test_provenance.gd` is the other
## half. Two gates asserting one thing is how the two drift.
extends "res://tests/test_framework.gd"

## The page that grants the skeleton's lines, read from the repository root.
## Each page sits beside the files it grants.
const PAGES: Array[String] = [
    "sara-godot/core/api/dynamics/PROVENANCE.md",
    "sara-godot/core/api/tip/PROVENANCE.md",
    "sara-godot/ui/widgets/curve_option/PROVENANCE.md",
]

## The skeleton directories the brush reaches into, which is what the provenance
## file's "no others" claim is about on this side.
const SWEPT: Array[String] = [
    "res://ui/brush_editor",
    "res://ui/widgets",
    "res://core",
]


## Every section of the page is a Sara file with lines under it, and the page
## says how many there are in a sentence a reader can check.
func test_the_provenance_file_grants_lines_to_the_files_it_names() -> void:
    for page_path: String in PAGES:
        _check_page_grants(page_path)


func _check_page_grants(page_path: String) -> void:
    var page := _read(_repo_path(page_path))
    assert_false(page.is_empty(), "%s is readable from a test" % page_path)

    var granted := _granted(page)
    assert_eq(granted.size(), _stated_files(page), "%s names as many files as its own sentence says" % page_path)
    assert_true(granted.size() > 0, "and the parse found them rather than returning nothing")

    for path: String in granted:
        assert_true(FileAccess.file_exists(ProjectSettings.globalize_path(path)), "%s exists" % path)
        var lines: Array = granted[path]
        assert_false(lines.is_empty(), "%s is granted at least one line, or it would not be a section" % path)
        for line: String in lines:
            assert_true(line.begins_with("SPDX-FileCopyrightText:"), "%s: '%s' is a copyright line" % [path, line])
            var body := line.substr("SPDX-FileCopyrightText:".length()).strip_edges()
            assert_true(
                body.length() > 0 and body[0].is_valid_int(),
                "%s: a copyright line starts with a year, not with '%s'" % [path, body.left(40)]
            )
            assert_true(body.contains("<") and body.contains(">"), "%s: %s names an address" % [path, body])


## A file carrying a line no section gives it.
func test_no_skeleton_file_carries_a_line_the_page_does_not_grant() -> void:
    var granted: Dictionary = {}
    for page_path: String in PAGES:
        granted.merge(_granted(_read(_repo_path(page_path))))

    var swept := 0
    for directory: String in SWEPT:
        for path: String in _scripts_under(directory):
            swept += 1
            var present := _copyright_lines(_read(ProjectSettings.globalize_path(path)))
            if present.is_empty():
                continue
            assert_true(granted.has(path), "%s carries a copyright line, so the provenance file has to name it" % path)
            var allowed: Dictionary = {}
            for line: String in granted.get(path, []):
                allowed[_fold(line)] = true
            for line: String in present:
                assert_true(allowed.has(line), "%s carries '%s', which the provenance file does not grant it" % [path, line])
    assert_true(swept > 15, "the three directories were walked rather than silently empty, %d scripts" % swept)


## `res://` path -> the copyright lines the page grants it.
##
## A section opens with a level-three heading whose whole text is a backticked
## `res://` path, and every fenced block under it up to the next heading holds
## that section's lines. Two shapes of line are read, the bare one and the one
## with Krita's own leading `*`, because the page reproduces both verbatim.
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


## The count the page states about itself, spelled in words, so the parse above
## cannot go quietly empty and no test holds a literal a merge has to move.
func _stated_files(page: String) -> int:
    var found := RegEx.create_from_string("(\\w+) ports? in (\\w+) files?, and no others").search(page)
    if found == null:
        return -1
    return _spelled(found.get_string(2))


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
    ]
    return words.find(word.to_lower())


## Every `.gd` under *directory* at any depth, sorted, so two runs agree. The
## walk descends because the skeleton is in packages: `core` holds
## two pinned scripts directly and every other one is a folder down, so a flat
## listing saw eight scripts where the guard below wants more than fifteen.
func _scripts_under(directory: String) -> Array[String]:
    var out: Array[String] = []
    var names := DirAccess.get_files_at(directory)
    names.sort()
    for name: String in names:
        if name.ends_with(".gd"):
            out.append(directory.path_join(name))
    var folders := DirAccess.get_directories_at(directory)
    folders.sort()
    for folder: String in folders:
        out.append_array(_scripts_under(directory.path_join(folder)))
    return out


func _copyright_lines(text: String) -> Dictionary:
    var out: Dictionary = {}
    var pattern := RegEx.create_from_string("SPDX-FileCopyrightText:[^\\n]*")
    for found in pattern.search_all(text):
        var line := found.get_string().strip_edges().trim_suffix("*/").strip_edges()
        out[_fold(line)] = true
    return out


## One line as it is compared, with the diacritics of the one name that has them
## folded away.
##
## The provenance file reproduces the lines as the Krita files carry them, so
## `Lukáš Tvrdý` is spelled with its diacritics on both sides now and the folding
## is no longer load-bearing. It stays because the page is also read by tools
## that mangle those characters, and a line that survives a round trip through
## one of them should still match rather than fail on an accent.
##
## Three substitutions rather than a general transliteration, because a general
## one would quietly accept a different name that folded to the same letters.
func _fold(line: String) -> String:
    return line.replace("á", "a").replace("š", "s").replace("ý", "y")


func _repo_path(relative: String) -> String:
    return ProjectSettings.globalize_path("res://").path_join("..").path_join(relative).simplify_path()


func _read(absolute: String) -> String:
    var file := FileAccess.open(absolute, FileAccess.READ)
    if file == null:
        return ""
    return file.get_as_text()
