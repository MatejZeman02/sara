## A tool's engine lives with the tool, held by a scan.
##
## A tool that calls an engine the skeleton keeps and implements nothing itself
## breaks the rule. `test_the_skeleton_without_modules.gd` looks the other way, at a skeleton
## file that names a module class. This one asks who uses each skeleton class,
## and fails a class only a module needs, because that class is the module's
## engine and belongs beside it.
##
## Every `.gd` outside `tests`, `scripts` and `scratch` is read with its comments
## removed. The skeleton is every top folder but `modules`, and a module is a
## folder holding a `module.gd`. A file uses a class when it names the class's
## `class_name`, its autoload name from `project.godot`, or a `res://` path to
## its file, as a `preload` or an `extends` does. Two discounts, without which
## the scan finds too few classes:
##
## - A line calling `register_role` is not a use. `ctx.register_role(&"transform",
##   SaTransform)` names the class so that somebody else can ask for it.
## - A name followed by a dot and a capital letter is not a use. `SaTransform.Filter`
##   is a constant, an enum or an inner class, and reaching one says the constant
##   lives in the wrong class rather than that the reader runs the engine.
##
## A skeleton class is held by a module when no skeleton file uses it and a
## module does, or when every skeleton file that uses it is itself held, closed
## until nothing changes. A kernel directly under `shaders/compute` is held the
## same way, by who opens it, and a kernel nothing opens fails too. A class
## under `core/api` is never held, because one customer through the door is the
## door working, so the scan skips that folder by name, which covers
## `SaPaintContext` under `core/api/paint`.
##
## What the scan cannot see: a function that serves one tool inside a shared
## class, a table of one module's names, and a settings key. Those are read by
## hand.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
## Paths the scan finds held today, each with the module that holds it.
## An entry that is no longer held fails the run, so the list cannot rot into
## an exemption.
##
## The two entries are the curve editor and the sensor list, which live in the
## widget toolkit ahead of their second user. The stamp is the one user until a
## second module binds a value to pressure through the curve editor, and that
## change removes both lines.
const HELD: Dictionary = {
    "ui/widgets/curve_option/sa_curve_option_control.gd": "the-texture-decides-where-paint-goes",
    "ui/widgets/curve_option/sa_sensor_list.gd": "the-texture-decides-where-paint-goes",
}

## Paths held today that stay in the skeleton on purpose, each with the sentence
## that keeps it. An entry here does not have to shrink. It fails only when the
## class stops being held, which is the day a second user arrives and the line
## can go.
##
## Empty. A shared class such as the colour ramp lives under `core/api/color`,
## and a class under the door is not asked, so it is held by where the files
## live rather than by a line here.
const DOORS: Dictionary = {}

## The folder the door lives in. One customer of a door is the door working.
const DOOR_DIR := "core/api"

## The folder every module lives under.
const MODULES_DIR := "modules"

## The kernels the scan asks about, the shipped ones directly under this folder.
## Its `libs` are imports and not kernels, and a module's kernels live with it.
const KERNELS_DIR := "shaders/compute"

## Never descend into these. Tests poke at what the rules forbid, `scripts` is
## the Python and the one tool script, and `scratch` is the gate's own profile.
const SKIP_DIRS: Array[String] = [".godot", ".conda", ".git", "build", "node_modules", "tests", "scripts", "scratch"]

## The tree is over four hundred app files. A walk that quietly returned fewer
## than this measured nothing.
const AT_LEAST_FILES := 300

## The file the scan has to have reached while one of the two lists names it.
## The guard is asked of a door: a walk that never opened a `core/api`
## file would leave every `DOORS` entry looking drained and fail the list above
## for the wrong reason.
const REACHED := "core/api/selection/sa_selection.gd"

## Where the planted pair is written and removed again, under `user://` so the
## editor never imports it and a run that dies between the write and the
## removal leaves no script in the tree.
static var scratch_dir: String = SaDataRoot.path("test_engine_lives_with_its_tool_scratch")

## The scan of the tree, read once for the three tests that ask it.
var _tree: Scan = null


func test_every_held_class_and_kernel_is_on_a_list() -> void:
    var scan := _tree_scan()
    var held := scan.held()
    _print_record(scan, held)
    var unlisted: Array[String] = []
    for path: String in held:
        if not HELD.has(path) and not DOORS.has(path):
            unlisted.append("%s (%s)" % [path, held[path]])
    assert_true(
        unlisted.is_empty(),
        (
            "A skeleton class or kernel only one module uses, so it is that module's engine and moves beside it, "
            + "or it joins HELD with the reason: %s" % ", ".join(unlisted)
        )
    )


func test_every_entry_of_held_is_still_held() -> void:
    var held := _tree_scan().held()
    for path: String in HELD:
        assert_true(
            held.has(path), "%s is no longer held by one module, so it leaves HELD (it was held for %s)" % [path, HELD[path]]
        )
    for path: String in DOORS:
        assert_true(held.has(path), "%s has a second user now, so it leaves DOORS and the sentence can go" % path)


## A walk that quietly returned nothing would pass both scans above.
func test_the_scan_reaches_the_code_it_claims_to_check() -> void:
    var scan := _tree_scan()
    assert_true(
        scan.sources.size() >= AT_LEAST_FILES,
        "The scan read %d files, under the %d the tree has, so it is measuring nothing" % [scan.sources.size(), AT_LEAST_FILES]
    )
    if HELD.has(REACHED) or DOORS.has(REACHED):
        assert_true(scan.sources.has(REACHED), "The scan never reached %s while a list names it" % REACHED)
    assert_true(scan.kernels.size() >= 10, "The scan found %d kernels under %s" % [scan.kernels.size(), KERNELS_DIR])


## The detector proved on files it wrote itself: a skeleton class only a planted
## module names is caught, one a planted skeleton file also names is not, one
## reached only through a constant is not, and a kernel only the held class opens
## follows it.
func test_a_planted_pair_is_caught() -> void:
    var planted := {
        "core/planted_engine.gd": "class_name PlantedEngine\nextends RefCounted\n\n\nfunc run() -> void:\n    pass\n",
        "core/planted_shared.gd": "class_name PlantedShared\nextends RefCounted\n\n\nfunc run() -> void:\n    pass\n",
        "core/planted_table.gd": "class_name PlantedTable\nextends RefCounted\n\nenum Kind { ONE }\n",
        "core/planted_kernels.gd":
        (
            "class_name PlantedKernels\nextends RefCounted\n\n\nfunc make() -> void:\n"
            + '    var c := SaCompute.new("planted")\n    var k := PlantedTable.Kind.ONE\n'
        ),
        "shaders/compute/planted.gmacs": "kernel planted\n",
        "shaders/compute/orphan.gmacs": "kernel orphan\n",
        "modules/planted/module.gd":
        (
            "extends RefCounted\n\n\nfunc register(ctx) -> void:\n    var engine := PlantedEngine.new()\n"
            + "    var shared := PlantedShared.new()\n    var kernels := PlantedKernels.new()\n"
            + '    ctx.register_role(&"planted", PlantedTable)\n'
        ),
        "ui/planted_user.gd": "extends Node\n\n\nfunc _ready() -> void:\n    var shared := PlantedShared.new()\n",
    }
    _write_scratch(planted)
    var scan := Scan.new(ProjectSettings.globalize_path(scratch_dir), {})
    var held := scan.held()
    ScratchFolder.clear(scratch_dir)

    assert_true(held.has("core/planted_engine.gd"), "The planted engine only the module names was not caught: %s" % [held.keys()])
    assert_true(held.has("core/planted_kernels.gd"), "The class the module names and nothing in the skeleton uses is held")
    assert_true(held.has("shaders/compute/planted.gmacs"), "The kernel only the held class opens follows it")
    assert_true(held.has("shaders/compute/orphan.gmacs"), "A kernel nothing opens fails too")
    assert_false(held.has("core/planted_shared.gd"), "A class a skeleton file uses as well is shared and stays")
    assert_false(held.has("core/planted_table.gd"), "A class reached only through a constant and a registration is not used")
    assert_eq(held.size(), 4, "The planted tree holds exactly four held paths, and the scan saw %s" % [held.keys()])


func _tree_scan() -> Scan:
    if _tree == null:
        _tree = Scan.new(ProjectSettings.globalize_path("res://"), _autoloads())
    return _tree


## The autoload names of `project.godot`, name to the path under `res://`.
func _autoloads() -> Dictionary:
    var out := {}
    var file := FileAccess.open("res://project.godot", FileAccess.READ)
    if file == null:
        return out
    var entry := RegEx.create_from_string('(?m)^(\\w+)="\\*?res://([^"]+)"')
    var section := RegEx.create_from_string("(?ms)^\\[autoload\\]\\n(.*?)(?=^\\[|\\z)")
    var found := section.search(file.get_as_text())
    if found == null:
        return out
    for line: RegExMatch in entry.search_all(found.get_string(1)):
        out[line.get_string(1)] = line.get_string(2)
    return out


## One line per held path, so the record can quote the list the scan printed.
func _print_record(scan: Scan, held: Dictionary) -> void:
    var counts := [scan.sources.size(), scan.classes.size(), scan.kernels.size(), held.size()]
    print("  scan: %d files, %d skeleton classes, %d kernels, %d held" % counts)
    var paths: Array = held.keys()
    paths.sort()
    for path: String in paths:
        var listed := "HELD, " + str(HELD[path]) if HELD.has(path) else ("DOORS" if DOORS.has(path) else "UNLISTED")
        print("    %s  %s  %s" % [path, held[path], listed])


func _write_scratch(planted: Dictionary) -> void:
    for name: String in planted:
        var path: String = scratch_dir.path_join(name)
        DirAccess.make_dir_recursive_absolute(path.get_base_dir())
        var file := FileAccess.open(path, FileAccess.WRITE)
        assert_not_null(file, "The planted file could not be written to %s" % path)
        if file != null:
            file.store_string(String(planted[name]))
            file.close()


## The scan over one tree: which files name which classes, which files open
## which kernels, and the closure that says what one module holds.
class Scan:
    extends RefCounted

    ## Every app `.gd` under the root, relative to it, skeleton and modules.
    var sources: Array[String] = []
    ## Skeleton class file to the names that reach it, `class_name` and autoload.
    var classes: Dictionary = {}
    ## Every kernel path under `shaders/compute`, relative to the root.
    var kernels: Array[String] = []
    ## Source file to the set of identifiers it names, discounts applied.
    var _names: Dictionary = {}
    ## Source file to the `res://` script paths it names.
    var _paths: Dictionary = {}
    ## Kernel path to the files and kernels that open it.
    var _openers: Dictionary = {}
    var _root: String

    func _init(root: String, autoloads: Dictionary) -> void:
        _root = root.rstrip("/")
        _walk(_root, "", sources, "gd")
        sources.sort()
        var declared := RegEx.create_from_string("(?m)^class_name\\s+(\\w+)")
        for path in sources:
            var code := _code(_read(path))
            _names[path] = _identifiers(code)
            _paths[path] = _script_paths(code)
            if _is_module(path) or path.begins_with(DOOR_DIR + "/"):
                continue
            var found := declared.search(code)
            var names: Array[String] = []
            if found != null:
                names.append(found.get_string(1))
            for autoload: String in autoloads:
                if autoloads[autoload] == path and not names.has(autoload):
                    names.append(autoload)
            if not names.is_empty():
                classes[path] = names
        _walk(_root.path_join(KERNELS_DIR), KERNELS_DIR + "/", kernels, "gmacs", false)
        kernels.sort()
        _read_openers()

    ## Held path to the sentence saying who holds it. Closed until nothing changes.
    func held() -> Dictionary:
        var out := {}
        var changed := true
        while changed:
            changed = false
            for path: String in classes:
                if out.has(path):
                    continue
                var why := _why_held(path, _users_of(path), out)
                if not why.is_empty():
                    out[path] = why
                    changed = true
            for kernel: String in kernels:
                if out.has(kernel):
                    continue
                var openers: Array = _openers.get(kernel, [])
                if openers.is_empty():
                    out[kernel] = "opened by nothing"
                    changed = true
                    continue
                var why := _why_held(kernel, openers, out)
                if not why.is_empty():
                    out[kernel] = why
                    changed = true
        return out

    ## Empty when a skeleton file that is not itself held uses the path.
    func _why_held(path: String, users: Array, held_so_far: Dictionary) -> String:
        if users.is_empty():
            return ""
        var modules: Array[String] = []
        var through: Array[String] = []
        for user: String in users:
            if user == path:
                continue
            if _is_module(user):
                var module := _module_of(user)
                if not modules.has(module):
                    modules.append(module)
            elif held_so_far.has(user):
                through.append(user)
            else:
                return ""
        if modules.is_empty() and through.is_empty():
            return ""
        if modules.is_empty():
            return "held through %s" % ", ".join(through)
        return "used by %s only" % ", ".join(modules)

    ## Every source file that names one of the class's names or its path.
    func _users_of(path: String) -> Array:
        var out: Array = []
        var names: Array = classes[path]
        for source in sources:
            if source == path:
                continue
            var used := false
            for name: String in names:
                if _names[source].has(name):
                    used = true
            if not used and _paths[source].has(path):
                used = true
            if used:
                out.append(source)
        return out

    ## The six ways a kernel is opened in the tree, read off every source file
    ## and every kernel, and a module's own kernels for their imports.
    func _read_openers() -> void:
        var by_new := RegEx.create_from_string('SaCompute\\.new\\("(\\w+)"\\)')
        var by_helper := RegEx.create_from_string('\\b\\w*compute\\("(\\w+)"\\)')
        var by_const := RegEx.create_from_string(
            '(?i)\\b\\w*(?:shader|shader_name|kernel)\\b(?:\\s*:\\s*\\w+)?\\s*:?=\\s*"(\\w+)"'
        )
        var by_generator := RegEx.create_from_string('\\bgenerator\\s*=\\s*"(\\w+)"')
        var by_blend := RegEx.create_from_string('SaBlendModeDescriptor\\.create\\([^,)]+,[^,)]+,\\s*"([\\w/-]+)"')
        for path in sources:
            var code := _code(_read(path))
            for pattern: RegEx in [by_new, by_helper, by_const, by_generator, by_blend]:
                for found: RegExMatch in pattern.search_all(code):
                    _open(found.get_string(1), path)
        # A line may name several libraries, `import a, b`, and each is opened.
        var by_import := RegEx.create_from_string("(?m)^\\s*import\\s+([\\w/, ]+)")
        var every_kernel: Array[String] = kernels.duplicate()
        _walk(_root.path_join(MODULES_DIR), MODULES_DIR + "/", every_kernel, "gmacs")
        for kernel in every_kernel:
            for found: RegExMatch in by_import.search_all(_read(kernel)):
                for name in found.get_string(1).split(","):
                    _open(name.strip_edges(), kernel)

    func _open(name: String, by: String) -> void:
        var kernel := KERNELS_DIR + "/" + name + ".gmacs"
        if not kernels.has(kernel) or kernel == by:
            return
        if not _openers.has(kernel):
            _openers[kernel] = []
        if not _openers[kernel].has(by):
            _openers[kernel].append(by)

    func _is_module(path: String) -> bool:
        return path.begins_with(MODULES_DIR + "/")

    ## The nearest folder above the file that holds a `module.gd`, or the file's
    ## own folder under `modules` when none does.
    func _module_of(path: String) -> String:
        var dir := path.get_base_dir()
        while dir != MODULES_DIR and not dir.is_empty():
            if FileAccess.file_exists(_root.path_join(dir).path_join("module.gd")):
                return dir
            dir = dir.get_base_dir()
        return path.get_base_dir()

    ## Every identifier the code names as a whole word, less the two discounts:
    ## a name followed by a dot and a capital letter, and any name on a line
    ## that calls `register_role`.
    func _identifiers(code: String) -> Dictionary:
        var out := {}
        var word := RegEx.create_from_string("\\b([A-Za-z_]\\w*)\\b(?!\\.[A-Z])")
        for line in code.split("\n"):
            if line.contains("register_role("):
                continue
            for found: RegExMatch in word.search_all(line):
                out[found.get_string(1)] = true
        return out

    ## Every `res://` path to a script the code names, relative to the root.
    func _script_paths(code: String) -> Dictionary:
        var out := {}
        var path := RegEx.create_from_string("res://([\\w./-]+\\.gd)")
        for found: RegExMatch in path.search_all(code):
            out[found.get_string(1)] = true
        return out

    func _walk(dir_path: String, prefix: String, out: Array[String], extension: String, recurse: bool = true) -> void:
        var dir := DirAccess.open(dir_path)
        if dir == null:
            return
        dir.list_dir_begin()
        var entry := dir.get_next()
        while not entry.is_empty():
            if dir.current_is_dir():
                if recurse and not SKIP_DIRS.has(entry):
                    _walk(dir_path.path_join(entry), prefix + entry + "/", out, extension)
            elif entry.get_extension() == extension:
                out.append(prefix + entry)
            entry = dir.get_next()
        dir.list_dir_end()

    ## The file with its comments removed, the way the suite above reads one: a class
    ## named in a doc comment is prose about it. A `#` inside a string is kept,
    ## because only one preceded by whitespace or doubled is read as a comment.
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
        var file := FileAccess.open(_root.path_join(relative), FileAccess.READ)
        if file == null:
            return ""
        return file.get_as_text()
