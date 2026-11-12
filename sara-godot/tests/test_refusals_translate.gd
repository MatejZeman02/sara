## Every refusal a painter reads in the corner goes through a translation
## lookup, and the sweep that says how many faults still do not.
##
## `SaProblems.refuse` is the corner notice, which is a line a painter
## reads and acts on, so a string a painter sees goes through `tr` or, from a
## static function where there is no `self` to reach `tr` through,
## `TranslationServer.translate`.
##
## **A source sweep rather than a behaviour test.** Nothing observable changes
## when a string is wrapped: with no translation loaded, `tr` answers the string
## it was given, so a test that drove the app would pass either way. What is
## actually being held is a property of the call sites, and the only honest way
## to hold it is to read them.
##
## The second case is a count that does not fail the run:
## `SaProblems.report` is the growing window, 31 of its call sites still pass a
## bare string, and most of them are module-API errors a script author reads
## rather than lines a painter acts on. The number is printed so a reader
## sees how far the sweep still has to go.
extends "res://tests/test_framework.gd"

const SKIP_DIRS: Array[String] = [".godot", ".conda", ".git", "build", "node_modules", "tests"]

## How many bare `SaProblems.report` call sites there were when this was
## written. It may fall, and a rise means a new fault line skipped the rule.
const BARE_REPORTS_WHEN_WRITTEN: int = 32


## Every refusal in the tree carries a lookup rather than a bare string.
func test_no_refusal_passes_a_bare_string() -> void:
    var bare := _bare_call_sites("SaProblems.refuse(")
    assert_eq(bare, [] as Array[String], "every SaProblems.refuse call site translates its text")


## The count is a ceiling that may only fall.
func test_the_faults_that_still_pass_a_bare_string_are_counted() -> void:
    var bare := _bare_call_sites("SaProblems.report(")
    print("    SaProblems.report call sites still passing a bare string: %d" % bare.size())
    assert_true(
        bare.size() <= BARE_REPORTS_WHEN_WRITTEN,
        "no new bare fault line: %d against the %d counted" % [bare.size(), BARE_REPORTS_WHEN_WRITTEN]
    )


## The sweep reaches the module sources as well as the skeleton's own, or a
## refusal inside a module would never be read.
func test_the_sweep_reaches_the_modules() -> void:
    var seen := _call_sites("SaProblems.refuse(")
    var in_modules := 0
    for site: String in seen:
        if site.begins_with("modules/"):
            in_modules += 1
    assert_true(seen.size() >= 8, "the tree declares refusals to check: %d" % seen.size())
    assert_true(in_modules >= 1, "and at least one of them is a module's: %d" % in_modules)


## `path:line` for every call site of *call*, tests excluded.
func _call_sites(needle: String) -> Array[String]:
    var out: Array[String] = []
    _walk("res://", "", needle, out, false)
    return out


## The call sites of *call* whose text argument is a bare string.
func _bare_call_sites(needle: String) -> Array[String]:
    var out: Array[String] = []
    _walk("res://", "", needle, out, true)
    return out


func _walk(dir_path: String, prefix: String, needle: String, out: Array[String], bare_only: bool) -> void:
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return
    dir.list_dir_begin()
    var entry := dir.get_next()
    while not entry.is_empty():
        if dir.current_is_dir():
            if not SKIP_DIRS.has(entry):
                _walk(dir_path.path_join(entry), prefix + entry + "/", needle, out, bare_only)
        elif entry.get_extension() == "gd" and not entry.begins_with("test_"):
            _read(dir_path.path_join(entry), prefix + entry, needle, out, bare_only)
        entry = dir.get_next()
    dir.list_dir_end()


## One file's call sites. A call is followed to its closing bracket, because
## four of them wrap onto three lines and the text is nowhere near the name.
func _read(path: String, display: String, needle: String, out: Array[String], bare_only: bool) -> void:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return
    var lines := file.get_as_text().split("\n")
    for index in lines.size():
        var line := String(lines[index])
        if not line.contains(needle) or line.strip_edges().begins_with("#"):
            continue
        var whole := _through_the_brackets(lines, index)
        if not bare_only or not _translates(whole):
            out.append("%s:%d" % [display, index + 1])


## The call from its opening bracket to the line that closes it, at most eight
## lines, which is longer than any of them.
func _through_the_brackets(lines: PackedStringArray, index: int) -> String:
    var whole := ""
    var depth := 0
    for step in mini(8, lines.size() - index):
        var line := String(lines[index + step])
        whole += line
        depth += line.count("(") - line.count(")")
        if step > 0 or line.contains(")"):
            if depth <= 0:
                break
    return whole


## Whether the call carries a lookup at all. The name is enough: a call that
## says `tr(` or `TranslationServer.translate(` anywhere between its brackets
## has its text through one, since the only other argument is the source, which
## is a class's own name and never translated. A `.refusal(` is a sentence its
## class has translated already, the way `SaLayerOps.MergePick` gives its own
## and `SaRasterizeLayer.refusal` gives the layer's.
func _translates(whole: String) -> bool:
    for lookup: String in ["tr(", "tr_n(", "TranslationServer.translate", ".refusal("]:
        if whole.contains(lookup):
            return true
    return false
