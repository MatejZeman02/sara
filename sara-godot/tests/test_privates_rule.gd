## The privates rule read off the tree, from a walk of the whole tree.
##
## The rule is the maintainers' of 2026-09-09, in Sara's conventions for code: a
## private member is written by its own class only, something set from outside
## arrives as a constructor argument in `_init`, and there are no getters and
## no setters. Reading a private from outside is fine, so nothing here counts a
## read.
##
## The `test_` methods are a ratchet rather than a check of the rule. Each one
## holds a cap that the tree meets today and that a new violation would break,
## because the sites the walk found are work for follow-up units and a failing
## test on the integration branch turns the gate red for every other clone.
## Everything named `pending_` is the assertion a fixer turns back into a
## `test_`, in the same commit as the fix, and the framework does not run it
## because it does not begin with `test_`.
extends "res://tests/test_framework.gd"

## Where the rule applies, the walk's own list.
const ROOTS: Array[String] = [
    "res://core",
    "res://render",
    "res://tools",
    "res://ui",
    "res://utils",
    "res://harness",
    "res://tests",
    "res://modules/sara-base-modules",
    "res://modules/sara-noise-brush-engine",
    "res://modules/sara-pigment-mixing",
]

## This file quotes the shapes it looks for, so scanning it would count its own
## documentation as violations.
const SELF_PATH := "res://tests/test_privates_rule.gd"

## What the walk counted on 2026-09-09, the caps the tree may not exceed, each
## lowered by the fix that took its writes out. f12 took the thirty-seven a
## factory wrote into a second instance of its own class, f13 the two
## `settings.config` lines a sibling wrote, f14 the fifty-nine every suite line
## pointing `SaSettings` or `SaUI` at a scratch profile or a pretended screen
## scale, and f15 the twenty-nine six suites wrote into the widgets they were
## setting up. **That is all of them**, so the write caps are zero and the two
## tests below them are the rule itself rather than a ratchet.
## `GETTERS_CAP` is zero since f16 took the forty-three getter shapes.
const WRITES_CAP := 0
const WRITES_OUTSIDE_TESTS_CAP := 0
const GETTERS_CAP := 0
const EXPORTED_PRIVATES_CAP := 0

## The files each filed F unit owns, so a fixer sees its own cluster go to zero
## rather than having to read the whole ledger.
## What f12 fixed, kept as a list so the row cannot come back one file at a time.
const FACTORY_FILES: Array[String] = [
    "res://core/api/paint/sa_paint_context.gd",
    "res://ui/canvas/canvas_overlay.gd",
    "res://ui/canvas/cursor_overlay.gd",
    "res://ui/canvas/grid_overlay.gd",
    "res://ui/canvas/selection_overlay.gd",
    "res://harness/sa_capture.gd",
]
const SIBLING_FILES: Array[String] = [
    "res://core/sa_settings_persistence.gd",
    "res://ui/brush_editor/editor_pages.gd",
    "res://harness/sa_step_table.gd",
    "res://harness/drivers/sa_input_driver.gd",
    "res://harness/scenario/sa_scenario_stroke.gd",
    "res://harness/drivers/sa_canvas_driver.gd",
    "res://harness/scenario/sa_scenario_document.gd",
    "res://harness/report/sa_cursor_probe.gd",
]

## The calls that change an `Array` or a `Dictionary` in place, as a regex
## alternation. A call on a private that is not one of these is a read.
const MUTATORS := (
    "clear|append|append_array|push_back|push_front|pop_back|pop_front|pop_at"
    + "|erase|remove_at|insert|fill|resize|sort|sort_custom|reverse|shuffle|assign|merge"
)

var _write_re := RegEx.new()
var _call_re := RegEx.new()
var _func_re := RegEx.new()
var _export_re := RegEx.new()
var _return_re := RegEx.new()


func _init() -> void:
    var receiver := "[A-Za-z_][A-Za-z0-9_]*(?:\\s*\\([^()]*\\))?(?:\\s*\\[[^\\]]*\\])?"
    var chain := "(?:\\s*\\.\\s*%s)*" % receiver
    var ops := "(?:\\+=|-=|\\*=|/=|%=|\\|=|&=|\\^=|<<=|>>=|=)"
    # Any number of subscripts may stand between the name and the operator
    # `obj._table[key] = value` writes `_table` as surely as
    # `obj._table = value` does, and nineteen lines of that shape sat under a cap
    # of zero because the pattern ended the member at the operator.
    _write_re.compile("^\\s*(%s%s)\\.(_[A-Za-z0-9_]*)(?:\\s*\\[[^\\]]*\\])*\\s*%s(?!=)" % [receiver, chain, ops])
    # A call that changes the member in place writes it too:
    # `list._selection.clear()` empties another object's private as surely as
    # `list._selection = []` would. Only the calls that change an `Array` or a
    # `Dictionary` are named, so a `has` or a `duplicate` stays a read.
    _call_re.compile("^\\s*(%s%s)\\.(_[A-Za-z0-9_]*)(?:\\s*\\[[^\\]]*\\])*\\s*\\.\\s*(?:%s)\\s*\\(" % [receiver, chain, MUTATORS])
    _func_re.compile("^(\\s*)(?:static\\s+)?func\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*\\(([^)]*)\\)")
    _export_re.compile("^\\s*@export[a-z_]*(?:\\([^)]*\\))?\\s+var\\s+(_[A-Za-z0-9_]*)")
    _return_re.compile("^return\\s+(_[A-Za-z0-9_]*)\\s*$")


## Every `.gd` under the walk's roots, this file aside. A missing root is not an
## error: two of the three modules are empty stubs with no code in them yet.
func _sources() -> Array[String]:
    var found: Array[String] = []
    for root: String in ROOTS:
        _walk(root, found)
    found.sort()
    return found


func _walk(dir_path: String, into: Array[String]) -> void:
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return
    for name: String in dir.get_files():
        if name.ends_with(".gd") and "%s/%s" % [dir_path, name] != SELF_PATH:
            into.append("%s/%s" % [dir_path, name])
    for name: String in dir.get_directories():
        if name.begins_with("."):
            continue
        _walk("%s/%s" % [dir_path, name], into)


func _lines_of(path: String) -> PackedStringArray:
    var file := FileAccess.open(path, FileAccess.READ)
    return file.get_as_text().split("\n") if file != null else PackedStringArray()


## The line with its trailing comment dropped and its string literals blanked,
## so a regex sees code. Blanked rather than removed, because a column that
## moves would make every line number in the walk's ledger wrong.
func _code(line: String) -> String:
    var out := ""
    var quote := ""
    var i := 0
    while i < line.length():
        var c := line[i]
        if quote != "":
            if c == "\\":
                out += "  "
                i += 2
                continue
            out += c if c == quote else " "
            if c == quote:
                quote = ""
            i += 1
            continue
        if c == '"' or c == "'":
            quote = c
            out += c
            i += 1
            continue
        if c == "#":
            break
        out += c
        i += 1
    return out


## Every write to a `_name` member of an object that is not `self`, as
## "path:line" strings. The prefilter is what keeps this cheap: only a line
## that already carries a dotted underscore is parsed.
func _writes_into_other_objects() -> Array[String]:
    var hits: Array[String] = []
    for path: String in _sources():
        var lines := _lines_of(path)
        for i: int in lines.size():
            if lines[i].contains("._") and _writes_another(_code(lines[i])):
                hits.append("%s:%d" % [path, i + 1])
    return hits


## Whether *code*, a line with its comment dropped and its strings blanked,
## writes a private of an object that is not `self`, by an assignment or by a
## call that changes the member in place.
func _writes_another(code: String) -> bool:
    for pattern: RegEx in [_write_re, _call_re]:
        var found := pattern.search(code)
        if found != null and found.get_string(1).strip_edges() != "self":
            return true
    return false


## Every method whose whole body is `return _member`, which the rule wants as a
## plain member instead. A body that computes, delegates or copies is not one.
func _getter_shapes() -> Array[String]:
    var hits: Array[String] = []
    for path: String in _sources():
        var lines := _lines_of(path)
        for i: int in lines.size():
            var head := _func_re.search(lines[i])
            if head == null or head.get_string(3).strip_edges() != "":
                continue
            if head.get_string(2) == "_init":
                continue
            var body := _body_of(lines, i, head.get_string(1).length())
            if body.size() == 1 and _return_re.search(body[0]) != null:
                hits.append("%s:%d" % [path, i + 1])
    return hits


## The statements under the `func` at *at*, stripped, blank lines dropped.
func _body_of(lines: PackedStringArray, at: int, indent: int) -> PackedStringArray:
    var body := PackedStringArray()
    var i := at + 1
    while i < lines.size():
        var line := lines[i]
        if line.strip_edges() != "":
            if line.length() - line.lstrip("\t ").length() <= indent:
                break
            body.append(_code(line).strip_edges())
        i += 1
    return body


func _exported_privates() -> Array[String]:
    var hits: Array[String] = []
    for path: String in _sources():
        var lines := _lines_of(path)
        for i: int in lines.size():
            if lines[i].contains("@export") and _export_re.search(_code(lines[i])) != null:
                hits.append("%s:%d" % [path, i + 1])
    return hits


func _in_files(hits: Array[String], files: Array[String]) -> Array[String]:
    var kept: Array[String] = []
    for hit: String in hits:
        if files.has(hit.substr(0, hit.rfind(":"))):
            kept.append(hit)
    return kept


func _outside_tests(hits: Array[String]) -> Array[String]:
    var kept: Array[String] = []
    for hit: String in hits:
        if not hit.begins_with("res://tests/"):
            kept.append(hit)
    return kept


func test_the_scan_reads_the_tree_it_is_pointed_at() -> void:
    var sources := _sources()
    assert_true(sources.size() > 500, "the walk finds the tree, %d files" % sources.size())
    assert_true(sources.has("res://core/api/document/sa_document.gd"), "core is walked")
    assert_true(sources.has("res://modules/sara-base-modules/base/module.gd"), "and a module with it")
    assert_false(sources.has(SELF_PATH), "and this file is left out of its own count")


## The pattern counts a write through a subscript, one or two
## deep, and still counts neither the class's own nor a read or a comparison
## that happens to index the same member.
func test_a_write_through_a_subscript_is_counted() -> void:
    assert_true(_counts("    SaSettings._table[key] = {}"), "an autoload's dictionary written through a key")
    assert_true(_counts("    tm._held[KEY_SPACE] = true"), "an instance's dictionary written through a key")
    assert_true(_counts("    grid._cells[x][y] += 1"), "and two subscripts deep")
    assert_true(_counts("    SaSettings._table = {}"), "with the plain write still counted")
    assert_false(_counts("    self._table[key] = {}"), "not the class's own")
    assert_false(_counts("    if SaSettings._table[key] == {}:"), "not a comparison")
    assert_false(_counts("    var kept = SaSettings._table[key]"), "and not a read")


## A call that changes another object's private in place is
## counted, through a subscript as well, and neither the class's own call nor a
## call that only reads the member is.
func test_a_call_that_changes_the_member_is_counted() -> void:
    assert_true(_counts("    list._selection.clear()"), "a clear on another object's array")
    assert_true(_counts("    list._selection.append(i)"), "an append")
    assert_true(_counts("    SaSettings._table[key].erase(y)"), "and an erase through a key")
    assert_true(_counts("    SaSettings._table.merge({}, true)"), "with a merge into a dictionary")
    assert_false(_counts("    self._selection.clear()"), "not the class's own through self")
    assert_false(_counts("    _selection.append(i)"), "nor its own bare")
    assert_false(_counts("    if not list._selection.has(i):"), "not a call that only reads")
    assert_false(_counts("    var wanted := list._selection.duplicate()"), "nor a copy")
    assert_false(_counts("    list._selection_changed.connect(_on_changed)"), "nor a signal connected")


## Whether one line is a write `_writes_into_other_objects` would count.
func _counts(line: String) -> bool:
    return _writes_another(_code(line))


func test_no_new_write_into_another_objects_private() -> void:
    var hits := _writes_into_other_objects()
    assert_true(
        hits.size() <= WRITES_CAP, "writes into another object's private, %d against the walk's %d" % [hits.size(), WRITES_CAP]
    )


func test_no_new_write_into_a_private_outside_the_suites() -> void:
    var hits := _outside_tests(_writes_into_other_objects())
    assert_true(
        hits.size() <= WRITES_OUTSIDE_TESTS_CAP,
        "writes outside tests/, %d against the walk's %d" % [hits.size(), WRITES_OUTSIDE_TESTS_CAP]
    )


func test_no_new_getter_shape() -> void:
    var hits := _getter_shapes()
    assert_true(hits.size() <= GETTERS_CAP, "getter shapes, %d against the walk's %d" % [hits.size(), GETTERS_CAP])


func test_no_private_is_exported() -> void:
    var hits := _exported_privates()
    assert_eq(hits.size(), EXPORTED_PRIVATES_CAP, "exported privates: %s" % ", ".join(hits))


## f12, fixed. A class writes no private of a second instance of itself: the
## factories take the field in `_init`, and the two in `cursor_overlay.gd` reach
## a built overlay through `force_samples` instead.
func test_a_factory_does_not_fill_its_own_class_privates() -> void:
    var hits := _in_files(_writes_into_other_objects(), FACTORY_FILES)
    assert_eq(hits.size(), 0, "factory writes left: %s" % ", ".join(hits))


## f13. The siblings write nothing private of the host they were split out of,
## because the member they reach is a plain member now, with a docstring naming
## the sibling that writes it.
func test_a_sibling_does_not_write_its_hosts_private() -> void:
    var hits := _in_files(_writes_into_other_objects(), SIBLING_FILES)
    assert_eq(hits.size(), 0, "sibling writes left: %s" % ", ".join(hits))


## f14 and f15, both done. No suite reaches into a private to set a state up.
##
## **A `test_` since f15 merged**, which is the shape the filing gave it: the two
## halves ended here together, f14's fifty-nine and f15's twenty-nine, and f15
## was the second to land. It counts the same set as
## `test_no_new_write_into_another_objects_private` above now that both caps are
## zero, and it is kept beside it rather than folded in because the two are
## different claims: one says no write is left, the other says none is left in a
## suite, and a suite is where they came back last time.
func test_no_suite_writes_a_private() -> void:
    var all_hits := _writes_into_other_objects()
    var hits := all_hits.size() - _outside_tests(all_hits).size()
    assert_eq(hits, 0, "suite writes left: %d" % hits)


## f16. Every read-only getter is a plain member, and the ratchet above is at
## zero, so the next `return _member` body is a failing test.
func test_no_getter_shape_is_left() -> void:
    var hits := _getter_shapes()
    assert_eq(hits.size(), 0, "getter shapes left: %d" % hits.size())
