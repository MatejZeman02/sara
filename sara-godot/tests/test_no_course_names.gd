## Nothing in the tree names the course the box blur module was called after.
##
## The code and its names read as a general painting program and not as a
## student's project, and this suite is that rule as a red run.
##
## It asks git two questions, about every tracked line and every tracked path
## outside the plans folder of the maintainer's documentation.
## `ALLOWED` is exact in both directions: a file over its count, a file not on
## it and a listed file that no longer holds the word all fail, the last so the
## list cannot outlive what it excused.
extends "res://tests/test_framework.gd"

## The word as a whole token, whatever its case. A letter or a digit on either
## side is another word, which is what keeps a generated uid and "stopgap" out.
const PATTERN: String = "(^|[^A-Za-z0-9])pga([^A-Za-z0-9]|$)"

## What to call the things instead, printed by every failure.
const INSTEAD: String = "the box blur module is `box-blur`, id `box_blur`, and Hard Mix is the skeleton's blend mode `hard_mix`"

## This suite spells the word in its own assertions.
const SELF: String = "sara-godot/tests/test_no_course_names.gd"

## The files that keep the word, each with the exact number of lines that hold
## it and why it is there.
const ALLOWED: Dictionary = {
    # The former blend id, so a picture saved with the old Hard Mix still
    # opens as it was. The alias is the whole point of the line.
    # It moved with the mode into the skeleton's table.
    "sara-godot/core/loader/skeleton_blend_modes.gd": 1,
    # The suite that reads Hard Mix off the skeleton's table, its former id
    # among what it reads.
    "sara-godot/core/composite/tests/test_hard_mix_composites_as_the_module_that_once_shipped_it_did.gd": 1,
    # The suite that loads a document under the former id and names it.
    "sara-godot/core/api/tests/test_former_blend_ids.gd": 2,
    # The scenario whose saved layer carries the former id it proves loads.
    "sara-godot/scenarios/a-renamed-blend-mode-keeps-loading-under-its-former-id.json": 1,
    # The scenario that saves a layer under the former id on the cut build.
    "sara-godot/scenarios/a-document-saved-with-hard-mix-under-its-former-id.json": 1,
    # The `REMOVED` keys that tell a stale doc reference where the
    # six module files went.
    "sara-godot/scripts/check_docs.py": 6,
    # The committed baseline and the two runs it was read from, recorded
    # before the module was renamed. A key is the module id that boot loaded,
    # and relabelling it would record a run that never happened. The runner
    # reads a key found only in the baseline as nothing and the new one as
    # new, so the lines leave when the baseline is next recorded.
    "docs/architecture/PERFORMANCE-2026-09-17.json": 1,
    "sara-godot/tests/fixtures/perf/baseline.json": 1,
    "sara-godot/tests/fixtures/perf/baseline-before-d5.json": 1,
    "sara-godot/tests/fixtures/perf/run-1/boot.json": 1,
    "sara-godot/tests/fixtures/perf/run-1/large.json": 1,
    "sara-godot/tests/fixtures/perf/run-1/small.json": 1,
    "sara-godot/tests/fixtures/perf/run-2/boot.json": 1,
    "sara-godot/tests/fixtures/perf/run-2/large.json": 1,
    "sara-godot/tests/fixtures/perf/run-2/small.json": 1,
}


## Whether a line or a path names the course.
static func hits(text: String) -> bool:
    var regex := RegEx.create_from_string("(?i)" + PATTERN)
    return regex.search(text) != null


## The complaints about one run of the two questions, empty when the tree is
## clean. `lines` is `git grep -n` output and `paths` is `git ls-files` output.
static func complaints(lines: String, paths: String, allowed: Dictionary) -> Array[String]:
    var found: Array[String] = []
    var counts: Dictionary = {}
    for line in lines.split("\n", false):
        var path := line.get_slice(":", 0)
        if path != SELF:
            counts[path] = int(counts.get(path, 0)) + 1
    for path: String in counts:
        if not allowed.has(path):
            found.append("%s names the course on %d lines, and %s" % [path, counts[path], INSTEAD])
        elif int(counts[path]) > int(allowed[path]):
            var said := "%s names the course on %d lines where %d are allowed, and %s"
            found.append(said % [path, counts[path], allowed[path], INSTEAD])
    for path: String in allowed:
        if not counts.has(path):
            found.append("%s no longer names the course, so its row leaves ALLOWED" % path)
        elif int(counts[path]) < int(allowed[path]):
            var fewer := "%s names the course on %d lines where ALLOWED says %d, so lower its row"
            found.append(fewer % [path, counts[path], allowed[path]])
    for path in paths.split("\n", false):
        if hits(path) and path != SELF:
            found.append("%s has the course in its path, and %s" % [path, INSTEAD])
    return found


func test_the_pattern_finds_the_word_and_nothing_inside_another() -> void:
    assert_true(hits("pga_box_blur"), "The old module id")
    assert_true(hits("res://modules/pga-hard-mix/hard_mix.gd"), "The old folder in a path")
    assert_true(hits('"Pga Hard Mix"'), "The label the id capitalized into")
    assert_true(hits("the PGA course"), "The course in prose")
    assert_false(hits("uid://v4cltpgad34t"), "Three letters inside a generated uid")
    assert_false(hits("a stopgap"), "Three letters inside a word")
    assert_false(hits("box_blur"), "The new id")


func test_the_counts_fail_in_every_direction() -> void:
    var allowed := {"a.gd": 1}
    assert_eq(complaints("a.gd:3:pga_x\n", "", allowed), [] as Array[String], "A file at its count passes")
    assert_eq(complaints("a.gd:3:pga_x\n" + SELF + ":9:pga\n", "", allowed).size(), 0, "The suite's own lines are dropped")
    var over := complaints("a.gd:3:pga_x\na.gd:4:pga_y\n", "", allowed)
    assert_eq(over.size(), 1, "A file over its count fails")
    assert_true(over[0].contains("a.gd") and over[0].contains("box_blur"), "and names the file and the new id: %s" % [over])
    var unlisted := complaints("a.gd:3:pga_x\nb.gd:1:pga\n", "", allowed)
    assert_eq(unlisted.size(), 1, "A file not listed fails")
    assert_true(unlisted[0].begins_with("b.gd"), "and names it: %s" % [unlisted])
    var gone := complaints("", "", allowed)
    assert_eq(gone.size(), 1, "A listed file that lost the word fails")
    assert_true(gone[0].contains("leaves ALLOWED"), "and says the row goes: %s" % [gone])
    var path := complaints("a.gd:3:pga_x\n", "modules/pga-box-blur/module.gd\nmodules/box-blur/module.gd\n", allowed)
    assert_eq(path.size(), 1, "A path with the word fails, a path without it does not")
    assert_true(path[0].contains("box-blur"), "and says what the folder is called: %s" % [path])


func test_nothing_in_the_tree_names_the_course() -> void:
    var root := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
    var probe: Array = []
    if OS.execute("git", ["-C", root, "rev-parse", "--is-inside-work-tree"], probe, true) != 0:
        print("  test_no_course_names: %s is not a git work tree, so nothing was looked at" % root)
        return
    var grep_out: Array = []
    var grep_args := ["-C", root, "grep", "-nIiE", "--recurse-submodules", PATTERN, "--", ".", ":!docs/plans"]
    var code := OS.execute("git", grep_args, grep_out, true)
    var lines: String = "" if grep_out.is_empty() else grep_out[0]
    # One with nothing printed is git's "nothing found", and a pass.
    assert_true(code == 0 or (code == 1 and lines.strip_edges().is_empty()), "git grep failed with %d: %s" % [code, lines])
    var list_out: Array = []
    assert_eq(OS.execute("git", ["-C", root, "ls-files", "--recurse-submodules"], list_out, true), 0, "git ls-files runs")
    var paths: Array[String] = []
    for path in ("" if list_out.is_empty() else String(list_out[0])).split("\n", false):
        if not path.begins_with("docs/plans/"):
            paths.append(path)
    # A row for a file this tree does not track is not a stale row, it is a
    # copy that leaves the file out (a public copy has no check_docs.py or
    # performance record). The file cannot hold the word if it is not there.
    var tracked: Dictionary = {}
    for path in paths:
        tracked[path] = true
    var allowed_here: Dictionary = {}
    for path: String in ALLOWED:
        if tracked.has(path):
            allowed_here[path] = ALLOWED[path]
    for complaint in complaints(lines, "\n".join(PackedStringArray(paths)), allowed_here):
        assert_true(false, complaint)
