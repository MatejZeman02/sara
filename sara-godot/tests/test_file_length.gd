## No file grows past `LIMIT` lines unnoticed, and no file is cut by count into
## a sibling that is half of another class.
##
## Two rules live here. The first counts lines, the second reads what the answer
## to a long file was, and the second is the one that gives the first its teeth.
##
## **Length.** One band. Over `LIMIT` fails the run, because nobody meant it.
## Nothing is asked of a file under that: length on its own predicts how badly
## the next change to a file will go, but a file cut to duck a count is worse
## than the count it dodged, so there is no warning band on the way up.
##
## **The cut.** A file over the line is cut by
## responsibility into a class that owns something, never by count, because
## GDScript has no partial classes and a sibling cut by count is one class
## smeared over two files, a bag of statics with the parent's name and a suffix
## that takes the parent back as its first argument. So the second check reads
## every `.gd` in the project and fails a smear: a file whose name is another
## file's name in the same folder plus a suffix, with no `class_name` of its own
## and nothing but static functions. Three signals, all three needed, because
## each on its own is honest somewhere in this tree. `sa_capture_layers.gd` wears
## the parent's name and owns a class. The whole `.gmacs` compiler declines
## `class_name` on purpose, since a class name resolves only once the editor has
## rescanned and the test runner never asks it to. A page of pure helpers with a
## name of its own is fine. Together they are the shape the rule bans.
##
## Raising `LIMIT`, or adding an entry to `SMEARS`, is the wrong fix every time.
## Cut the file into a class that owns something and give it a name that says so.
##
## A limit on length alone treats the symptom: files split by count grow back,
## because every change that wants a number has a bag of statics to reach into
## and no class to ask. `SMEARS` names such files instead, and they leave the
## list by being cut rather than by being watched.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
## A file over this many lines fails the run, because nobody meant it. Nothing
## is asked of a file under it.
const LIMIT: int = 1000

## The sibling pairs cut by count that exist today.
##
## An entry leaves this list when its pair is cut. A path that is no longer a smear, because it was cut
## or because it went away, fails the run just as an unlisted smear does: a list
## that outlives what it excused is how the last band rotted.
const SMEARS: Dictionary = {}

## Text this suite is responsible for. Anything else in the tree is an asset, an
## import cache, or someone else's code.
const EXTENSIONS: Array[String] = ["gd", "gmacs", "gdshader", "py", "sh", "md"]

## Never descend into these. `.godot` is the engine's import cache, `.conda` the
## vendored gdtoolkit env, and `build/` and `scratch/` are output rather than
## source, the second holding the data root a gated run writes its generated
## kernels into, a module's dab kernel with a field written in.
const SKIP_DIRS: Array[String] = [".godot", ".conda", ".git", "build", "node_modules", "scratch"]

## `res://` is the Godot project. The docs live one level up, outside it, and
## they are the half of the repository that has actually hit the limit.
const EXTRA_ROOTS: Array[String] = ["../docs", "../packaging"]

## Where the planted pair is written and removed again.
static var scratch_dir: String = SaDataRoot.path("test_file_length_scratch")


func test_no_file_exceeds_the_limit() -> void:
    var lengths := _measure_all()
    assert_false(lengths.is_empty(), "The scan found no files at all, so it is measuring nothing")

    var over: Array[String] = []
    for path: String in lengths:
        var count: int = lengths[path]
        if count > LIMIT:
            over.append("%s (%d)" % [path, count])

    over.sort()
    assert_true(
        over.is_empty(),
        (
            "Over %d lines, split them by responsibility into a class that owns something, never by count: %s"
            % [LIMIT, ", ".join(over)]
        )
    )


## No file in the project is a sibling cut by count, except the entries of `SMEARS`,
## and every entry of `SMEARS` is still one.
##
## The second half is what makes the list drain. An entry whose file has been cut,
## renamed or removed measures nothing, and a list nobody measures is worse than
## no list.
func test_a_sibling_cut_by_count_fails_the_run() -> void:
    var found := _smears_under("res://", "")

    var unlisted: Array[String] = []
    for path: String in found:
        if not SMEARS.has(path):
            unlisted.append("%s, half of %s" % [path, found[path]])
    unlisted.sort()
    assert_true(
        unlisted.is_empty(),
        (
            (
                "Cut by count rather than by responsibility: %s. A sibling with the parent's name and a "
                + "suffix, no class name and nothing but statics is one class over two files. Give it a "
                + "class that owns something and a name that says what."
            )
            % ", ".join(unlisted)
        )
    )

    var stale: Array[String] = []
    for path: String in SMEARS:
        if not found.has(path):
            stale.append("%s, drained by %s" % [path, SMEARS[path]])
    stale.sort()
    assert_true(
        stale.is_empty(),
        "These are no longer smears, so remove their entries from SMEARS in the same commit: %s" % ", ".join(stale)
    )


## The check sees a pair planted beside it, and lets the three near misses past.
##
## The tree check above is guarded by its own allowlist only while the allowlist
## has entries. Once it is empty, a walk that quietly stopped early
## would report a clean tree, so the detector is proved on files it wrote itself.
func test_the_check_sees_a_planted_scratch_pair() -> void:
    var owner_source := "class_name SaScratch\nextends RefCounted\n\n\nfunc do_it() -> void:\n    pass\n"
    var planted := {
        "sa_scratch.gd": owner_source,
        # The smear: the parent's name, a suffix, no class name, statics only,
        # and the parent handed back as the first argument.
        "sa_scratch_helpers.gd": "extends RefCounted\n\n\nstatic func do_it(owner: SaScratch) -> void:\n    pass\n",
        # A sibling that owns a class is not a smear, whatever it is named.
        "sa_scratch_session.gd": "class_name SaScratchSession\nextends RefCounted\n\n\nstatic func do_it() -> void:\n    pass\n",
        # Nor is one that holds state and answers as an instance.
        "sa_scratch_state.gd": "extends RefCounted\n\n\nvar kept: int = 0\n\n\nfunc do_it() -> void:\n    pass\n",
        # Nor is a page of statics whose name is nobody else's plus a suffix.
        "sa_elsewhere.gd": "extends RefCounted\n\n\nstatic func do_it() -> void:\n    pass\n",
    }
    _write_scratch(planted)
    var found := _smears_under(scratch_dir, "")
    ScratchFolder.clear(scratch_dir)

    assert_eq(found.size(), 1, "The planted pair should be the one smear found, and the scan saw %s" % [found.keys()])
    assert_true(found.has("sa_scratch_helpers.gd"), "The planted smear was not seen, so the check measures nothing")
    assert_eq(found.get("sa_scratch_helpers.gd", ""), "sa_scratch.gd", "The smear should name the parent it is half of")


## A scan that quietly stopped early would report every file as short. The docs
## sit outside `res://` and are reached by an absolute path, which is the part
## most likely to break, so prove it arrived rather than trusting a green run.
func test_the_scan_reaches_outside_the_godot_project() -> void:
    var project_dir := ProjectSettings.globalize_path("res://")
    for relative in EXTRA_ROOTS:
        var absolute := project_dir.path_join(relative).simplify_path()
        if not DirAccess.dir_exists_absolute(absolute):
            continue
        var prefix := relative.trim_prefix("../") + "/"
        var reached := false
        for path: String in _measure_all():
            if path.begins_with(prefix):
                reached = true
                break
        assert_true(reached, "%s exists but the scan measured nothing under it" % absolute)


## The longest stem in *stems* that *stem* is the name of plus a suffix, or "".
##
## Longest, because a name can be a suffix on two stems at once, `sa_capture` and
## `sa_capture_dump` say, and the class the file is half of is the nearer one.
static func _parent_stem(stem: String, stems: Array[String]) -> String:
    var parent := ""
    for other in stems:
        if other != stem and stem.begins_with(other + "_") and other.length() > parent.length():
            parent = other
    return parent


## Whether *source* declares no class name of its own and nothing but statics.
##
## Column zero only, so a `func` inside an inner class is the inner class's and a
## file whose functions all live in one is not read as a bag.
static func _is_bag_of_statics(source: String) -> bool:
    var has_static := false
    for line in source.split("\n"):
        if line.begins_with("class_name ") or line.begins_with("func "):
            return false
        if line.begins_with("static func "):
            has_static = true
    return has_static


## Every sibling cut by count under *root_path*, as `{smear path: parent path}`,
## both displayed with *prefix* in front.
func _smears_under(root_path: String, prefix: String) -> Dictionary:
    var found: Dictionary = {}
    _walk_smears(root_path, prefix, found)
    return found


func _walk_smears(dir_path: String, prefix: String, found: Dictionary) -> void:
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return
    var stems: Array[String] = []
    var subdirs: Array[String] = []
    dir.list_dir_begin()
    var entry := dir.get_next()
    while not entry.is_empty():
        if dir.current_is_dir():
            if not SKIP_DIRS.has(entry):
                subdirs.append(entry)
        elif entry.get_extension() == "gd":
            stems.append(entry.get_basename())
        entry = dir.get_next()
    dir.list_dir_end()

    for stem in stems:
        var parent := _parent_stem(stem, stems)
        if parent.is_empty():
            continue
        var file := FileAccess.open(dir_path.path_join(stem + ".gd"), FileAccess.READ)
        if file == null:
            continue
        if _is_bag_of_statics(file.get_as_text()):
            found[prefix + stem + ".gd"] = prefix + parent + ".gd"

    for sub in subdirs:
        _walk_smears(dir_path.path_join(sub), prefix + sub + "/", found)


## Every countable file under every root, as `{display path: line count}`.
func _measure_all() -> Dictionary:
    var lengths: Dictionary = {}
    _walk("res://", "", lengths)

    var project_dir := ProjectSettings.globalize_path("res://")
    for relative in EXTRA_ROOTS:
        var absolute := project_dir.path_join(relative).simplify_path()
        # Absent in an exported build, and absent if the project is ever vendored
        # somewhere without the docs beside it. Neither is a failure.
        if DirAccess.dir_exists_absolute(absolute):
            _walk(absolute, relative.trim_prefix("../") + "/", lengths)
    return lengths


func _walk(dir_path: String, prefix: String, lengths: Dictionary) -> void:
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return
    dir.list_dir_begin()
    var entry := dir.get_next()
    while not entry.is_empty():
        if dir.current_is_dir():
            if not SKIP_DIRS.has(entry):
                _walk(dir_path.path_join(entry), prefix + entry + "/", lengths)
        elif EXTENSIONS.has(entry.get_extension()):
            lengths[prefix + entry] = _line_count(dir_path.path_join(entry))
        entry = dir.get_next()
    dir.list_dir_end()


## Lines as `wc -l` would count them: a trailing newline ends the last line, it
## does not start an empty one.
func _line_count(path: String) -> int:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return 0
    var lines := file.get_as_text().split("\n")
    var count := lines.size()
    if count > 0 and lines[count - 1].is_empty():
        count -= 1
    return count


## Writes *planted*, `{file name: source}`, into the scratch directory.
##
## Under `user://` rather than `res://`, so the editor never imports it and a run
## that dies between the write and the removal cannot leave a script in the tree.
func _write_scratch(planted: Dictionary) -> void:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    for name: String in planted:
        var file := FileAccess.open(scratch_dir.path_join(name), FileAccess.WRITE)
        assert_not_null(file, "The scratch pair could not be written to %s" % scratch_dir)
        if file != null:
            file.store_string(String(planted[name]))
            file.close()
