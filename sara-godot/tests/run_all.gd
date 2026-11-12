## Master test runner.
##
## Suites are discovered on disk rather than listed here: a hand-maintained list
## silently skips any suite someone forgets to register, which is exactly the
## failure mode this runner exists to catch. A suite is any `test_*.gd` in a
## `tests` folder anywhere under `res://`: `res://tests/` for the suites that
## test the whole tree, and a package's or a module's own `tests/` beside it.
##
## A suite that needs a RenderingDevice declares `const REQUIRES_GPU := true`,
## those are skipped, with a note, when no rendering device is available.
##
## A trailing argument filters which suites run:
##
##     ./run_tests.sh chunk          # any suite whose name contains "chunk"
##     ./run_tests.sh layer document # either one
##
## The filter is a substring match against the suite name, so `sa_` selects the
## core data suites and `state_` the tool ones. A filtered run prints what it
## left out and refuses to print ALL TESTS PASSED, because that line is
## run_tests.sh's success marker and a partial run must never look like a full
## one.
extends Node

## The name of a folder that holds suites, wherever it sits under `res://`.
const SUITES_DIR: String = "tests"
## Folders the walk for suites never enters. Hidden ones, `.godot` above all,
## are never listed by `DirAccess` in the first place.
const UNWALKED_DIRS: Array[String] = ["scratch", "build", "node_modules"]
## The shared base class matches the test_* pattern but is not itself a suite.
const FRAMEWORK_FILE: String = "test_framework.gd"
## The suites' base class, which the runner's script holds for as long as it
## lives itself, the guard `_held_to_exit` sets up.
const FRAMEWORK: Script = preload("res://tests/test_framework.gd")

## The runner's own script, which holds itself here from `_ready` on, and with
## it `FRAMEWORK`, so that no suite is ever the framework's last holder at exit
## A suite whose function reads a `static var` of its own
## holds its own script, because the compiler keeps the script as a constant of
## that function, so the script outlives the run. The engine lets go of it only
## in the walk `GDScriptLanguage::finish()` makes over every script at exit,
## newest first, and that walk steps to the next script before it lets go of
## the one it has just cleared. When the one let go of held the last reference
## to the framework, and the framework is the next script, the walk stands on a
## freed script and stops, and every script after it keeps its static state:
## 673 objects and 452 resources leaked in a named run, and the renderer's and
## the fonts' too once a suite that draws had run. The runner's script is older
## than the framework and every suite, so the walk reaches it after both, and
## only then lets the framework go.
static var _held_to_exit: Array[Script] = []

## The open documents a suite brings forward, read by `SaDocuments.front_in` as
## main's are in the app, so `SaCanvasView.front_canvas()` answers inside a
## suite. Null until a suite wants one.
##
## Every lookup for "the document a step acts on" goes through the
## front surface, which is the one the current scene's owner holds. The scene a
## test run is given is this runner, so a suite that drives a step at a canvas
## of its own puts that canvas here, through `SaTestFixtures.FrontDocuments`,
## which makes the owner when there is none and takes the canvas out again
## after each case. A suite cannot stand in as the current scene itself: the
## tree takes only a child of its root for that, and root refuses a child while
## it is setting its own up, which is the whole of a run.
var documents: SaDocuments = null

## The autosave a suite stands in for main's, read by the door's `load` as
## main's is in the app to name a newer recovery copy Null
## outside the suite that sets it.
var autosave: Node = null

## The registries a suite stands in for main's, which a generated layer's view
## finds a module's view shader through, a Paper's or a Canvas's included. Null
## outside the suite that sets it. Answered as `registries` by [method _get]
## only while it is set, because a declared `registries` would tell every
## `"registries" in main` check that there are registries when there are none.
var stand_in_registries: SaRegistries = null


## What a suite leaves for the suites after it, put back after each one and
## named as the suite's failure A suite that passes alone and
## fails in a batch is a fault of a suite before it, and this names that one.
##
## Two kinds are known. A node under `EventBus` the suite added and did not
## free, queued ones too, since `queue_free` waits for a frame the
## runner seldom passes, which once left six full-window controls over a search
## loupe. And a picture format registry installed and kept
## alive without PNG in it, which `SaImageFormatRegistry.shared()` answers
## instead of the skeleton's own, as when the loader held the last loaded
## registries with their formats put down and no picture could be read.
##
## The root is not watched. The app puts its own process-wide nodes there, the
## linked files' watch for one, with a deferred `add_child` that lands in the
## next frame any suite passes, so a node there names the wrong suite.
class Leftovers:
    extends RefCounted

    ## The ids of the nodes under `EventBus` before the suite ran.
    var _before: Dictionary[int, bool] = {}

    func _init() -> void:
        for node: Node in _watched():
            _before[node.get_instance_id()] = true

    ## Frees what the suite left and lets go of a registry with no PNG in it.
    ## Returns a line for each, empty when the suite left nothing.
    func put_back() -> Array[String]:
        var left: Array[String] = []
        for node: Node in _watched():
            if _before.has(node.get_instance_id()):
                continue
            var queued := ", queued to be freed" if node.is_queued_for_deletion() else ""
            var parent := node.get_parent()
            left.append("a %s named %s under %s%s" % [node.get_class(), node.name, parent.name, queued])
            parent.remove_child(node)
            node.free()
        if SaImageFormatRegistry.shared().flat_named("left.png") == null:
            left.append("an installed picture format registry that reads no PNG")
            SaImageFormatRegistry.install(null)
        return left

    static func _watched() -> Array[Node]:
        return EventBus.get_children()


## [member stand_in_registries] as `registries`, and nothing while it is null,
## which leaves `"registries" in` this node false as it is with no stand in.
func _get(property: StringName) -> Variant:
    if property == &"registries" and stand_in_registries != null:
        return stand_in_registries
    return null


## What the run holds in memory, read after each suite, so a suite that keeps
## what it made is named by the run itself rather than by the out of memory
## killer taking the run with the engine at about 10 GB resident. The resident set and its peak are Linux's
## `/proc/self/status`, where a painter's system monitor reads them too, and
## the rendering device's own count of video memory stands beside them, since
## a texture a suite keeps can be held on either side.
##
## `SARA_TEST_MEMORY_LIMIT_MB`, which run_tests.sh sets, is the most the run's
## resident set may reach. Passing it fails the run, naming the suite that
## crossed it, and stops the run there, because a run that went on would grow
## until the killer took it and printed nothing at all. `SARA_TEST_MEMORY_TABLE`
## names a file that takes every suite's growth, for when the ten in the
## report do not settle it.
class Memory:
    extends RefCounted

    ## How many suites the closing table names.
    const NAMED: int = 10

    ## The most the resident set may reach, in MiB, or 0 for no limit.
    var limit_mib: int = 0
    ## The suite that took the resident set past the limit, empty while none
    ## has.
    var crossed_by: String = ""
    ## Each suite's growth of the resident set and of video memory, in MiB,
    ## and of the engine's count of objects, of nodes outside any tree and of
    ## `EventBus`'s connections.
    var _grown: Array[Dictionary] = []
    var _rd: RenderingDevice = null
    var _start_mib: float = 0.0

    func _init(rd: RenderingDevice, limit: int) -> void:
        _rd = rd
        limit_mib = limit
        _start_mib = resident_mib()

    ## Notes what *suite_name* grew since *before*, a reading of `reading()`
    ## taken before it ran, and returns whether the run may go on.
    func note(suite_name: String, before: Dictionary) -> bool:
        var after := reading()
        var grown := {"suite": suite_name}
        for key: String in ["resident", "video"]:
            grown[key] = float(after[key]) - float(before[key])
        for key: String in ["objects", "orphans", "listeners"]:
            grown[key] = int(after[key]) - int(before[key])
        _grown.append(grown)
        if limit_mib > 0 and crossed_by.is_empty() and float(after["resident"]) > limit_mib:
            crossed_by = suite_name
        return crossed_by.is_empty()

    ## The resident set and the video memory now, in MiB, and the counts of
    ## objects, of nodes outside any tree and of `EventBus`'s connections.
    func reading() -> Dictionary:
        return {
            "resident": resident_mib(),
            "video": video_mib(),
            "objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
            "orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
            "listeners": listener_count(),
        }

    ## How many connections `EventBus`'s signals hold. A control a suite
    ## leaves connected to one answers every later suite's emit of it, so a
    ## theme switch rebuilt the rows of every Colour Themes page a suite had
    ## left behind, a thousand nodes a switch.
    static func listener_count() -> int:
        var count := 0
        for sig: Dictionary in EventBus.get_signal_list():
            count += EventBus.get_signal_connection_list(sig["name"]).size()
        return count

    func video_mib() -> float:
        if _rd == null:
            return 0.0
        return _rd.get_memory_usage(RenderingDevice.MEMORY_TOTAL) / 1048576.0

    ## Whether the run's peak stayed at or under the limit.
    func within_limit() -> bool:
        return crossed_by.is_empty() and (limit_mib <= 0 or peak_mib() <= limit_mib)

    ## Writes every suite's growth to *path*, a table to read whole,
    ## tab separated with a header, in the order the suites ran.
    func write_table(path: String) -> void:
        var file := FileAccess.open(path, FileAccess.WRITE)
        if file == null:
            printerr("ERROR: the memory table could not be written to %s" % path)
            return
        file.store_line("suite\tresident_mib\tvideo_mib\tobjects\torphans\tlisteners")
        for grown: Dictionary in _grown:
            var row := [grown["suite"], grown["resident"], grown["video"]]
            row.append_array([grown["objects"], grown["orphans"], grown["listeners"]])
            file.store_line("%s\t%.1f\t%.1f\t%d\t%d\t%d" % row)

    ## The lines the run closes with: the peak, and the suites that grew the
    ## resident set most, each with what it grew the video memory by.
    func report() -> Array[String]:
        var lines: Array[String] = []
        var limit_text := "no limit" if limit_mib <= 0 else "limit %d MiB" % limit_mib
        lines.append(
            (
                "Memory: peak resident %d MiB, %d MiB at the start and %d MiB at the end, %s. Video memory %d MiB at the end."
                % [roundi(peak_mib()), roundi(_start_mib), roundi(resident_mib()), limit_text, roundi(video_mib())]
            )
        )
        var by_growth := _grown.duplicate()
        by_growth.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["resident"] > b["resident"])
        lines.append("The %d suites that grew the resident set most:" % mini(NAMED, by_growth.size()))
        for grown: Dictionary in by_growth.slice(0, NAMED):
            lines.append(
                (
                    "  %+8.1f MiB resident  %+8.1f MiB video  %+7d objects  %+6d orphan nodes  %s"
                    % [grown["resident"], grown["video"], grown["objects"], grown["orphans"], grown["suite"]]
                )
            )
        if not crossed_by.is_empty():
            lines.append(
                "The resident set passed the limit of %d MiB after %s, and the run stopped there." % [limit_mib, crossed_by]
            )
        elif not within_limit():
            lines.append("The resident set peaked past the limit of %d MiB." % limit_mib)
        return lines

    ## The process's resident set in MiB, or 0 where no `/proc` says it.
    static func resident_mib() -> float:
        return _status_kib("VmRSS:") / 1024.0

    ## The most the process's resident set has been, in MiB, or 0 where no
    ## `/proc` says it.
    static func peak_mib() -> float:
        return _status_kib("VmHWM:") / 1024.0

    static func _status_kib(field: String) -> int:
        var status := FileAccess.open("/proc/self/status", FileAccess.READ)
        if status == null:
            return 0
        while not status.eof_reached():
            var line := status.get_line()
            if line.begins_with(field):
                return line.trim_prefix(field).strip_edges().split(" ")[0].to_int()
        return 0


func _ready() -> void:
    _held_to_exit.append(get_script() as Script)

    # The runner's own report is always the human shape, whatever SARA_CONSOLE
    # says. The machine mode is for the startup console, and run_tests.sh
    # parses these lines: a run under a script's environment would otherwise
    # print a shape the wrapper reads as a failed run.
    SaConsole.machine = 0

    var all_paths: Array[String] = _discover_suites()
    if all_paths.is_empty():
        printerr("ERROR: No test suites discovered in any %s folder" % SUITES_DIR)
        get_tree().quit(1)
        return

    var shared := shared_names(all_paths)
    if not shared.is_empty():
        for suite_name: String in shared:
            var carriers: Array = shared[suite_name]
            printerr("ERROR: %d suites are named %s: %s" % [carriers.size(), suite_name, ", ".join(carriers)])
        get_tree().quit(1)
        return

    var filters := _filters()
    var suite_paths := _apply_filters(all_paths, filters)
    if suite_paths.is_empty():
        printerr("ERROR: No suite matched %s. Discovered: %s" % [", ".join(filters), _names_of(all_paths)])
        get_tree().quit(1)
        return
    var filtered_out := all_paths.size() - suite_paths.size()

    # The kernels are a stage of the app's boot rather than the compiler's
    # constructor and the runner is a boot of its own, so
    # it compiles them all before the first suite, the way the autoload did.
    GlobalShaderCompiler.compile_kernels()

    var rd := RenderingServer.get_rendering_device()

    var total_passed: int = 0
    var total_failed: int = 0
    var failed_suites: Array[String] = []
    var skipped_suites: Array[String] = []
    # Suites that ran but left a part out on this machine, each saying why on
    # its own line: the socket half of the door on Windows, for one.
    var partly_skipped: Array[String] = []
    var run_started := Time.get_ticks_msec()

    ModuleLoader.verbose = false
    var memory := Memory.new(rd, OS.get_environment("SARA_TEST_MEMORY_LIMIT_MB").to_int())

    # Every SaSettings setter saves, and SaSettings is an autoload pointed at the
    # real ~/.config/sara/settings.cfg. So a suite that flips a preference to
    # assert something rewrites the user's file, and restoring "the default"
    # afterwards is not the same as restoring what they had chosen. Redirecting
    # the path here sandboxes every suite at once, including the ones that
    # already do this and the ones nobody has written yet.
    #
    # The values in memory are still the user's, because _ready() loaded them
    # before this line. Only the writes go elsewhere.
    SaSettings.settings_path = SaDataRoot.path("test_settings.cfg")

    SaConsole.blank()
    SaConsole.open_box("SARA TEST SUITE" if filters.is_empty() else "SARA TEST SUITE - FILTERED")
    SaConsole.blank()

    for path in suite_paths:
        var suite_name := path.get_file().get_basename()

        var suite_script: Script = load(path)
        if suite_script == null:
            # A suite that preloads a missing module fails to parse. Report it rather
            # than letting the run look clean.
            printerr("ERROR: Failed to load suite script: %s" % path)
            failed_suites.append(suite_name)
            continue

        if rd == null and _requires_gpu(suite_script):
            skipped_suites.append(suite_name)
            print_rich(
                (
                    "   %s  %s %s"
                    % [
                        SaConsole.tint("○", SaConsole.SKIP),
                        SaConsole.tint(suite_name.rpad(30), SaConsole.DIM),
                        SaConsole.tint("skipped · needs a GPU", SaConsole.SKIP),
                    ]
                )
            )
            continue

        if not suite_script.can_instantiate():
            # A script with a parse error still loads: `load()` hands back a
            # GDScript that never compiled. Calling new() on it raises a runtime
            # error that aborts _ready, so get_tree().quit() is never reached and
            # the whole run sat there until the shell timeout killed it. A parse
            # error is the most common failure there is. It must cost a second,
            # not the entire timeout window.
            printerr("ERROR: Suite %s failed to parse - see the SCRIPT ERROR above: %s" % [suite_name, path])
            failed_suites.append(suite_name)
            continue

        var suite: Object = suite_script.new()
        if not suite.has_method("run_all_tests"):
            printerr("ERROR: suite %s does not extend test_framework.gd (no run_all_tests)." % suite_name)
            failed_suites.append(suite_name)
            continue

        var memory_before := memory.reading()
        var leftovers := Leftovers.new()
        if not await suite.run_all_tests(suite_name):
            failed_suites.append(suite_name)
        var left := leftovers.put_back()
        if not left.is_empty():
            for what: String in left:
                printerr("        └ [LEFT] %s left %s" % [suite_name, what])
            if not failed_suites.has(suite_name):
                failed_suites.append(suite_name)
        if not suite.skip_reasons.is_empty():
            partly_skipped.append(suite_name)
        total_passed += suite.passed_count
        total_failed += suite.failed_count
        suite = null
        await _let_go_of_what_was_queued()
        if not memory.note(suite_name, memory_before):
            if not failed_suites.has(suite_name):
                failed_suites.append(suite_name)
            break

    var ok := total_failed == 0 and failed_suites.is_empty() and memory.within_limit()
    var ran := suite_paths.size() - skipped_suites.size()
    var elapsed := (Time.get_ticks_msec() - run_started) / 1000.0

    SaConsole.divider()
    print_rich(
        (
            "   %s %s   %s %s   %s %s"
            % [
                SaConsole.tint(str(ran), SaConsole.HEAD),
                SaConsole.tint("suites", SaConsole.DIM),
                SaConsole.tint(str(total_passed + total_failed), SaConsole.HEAD),
                SaConsole.tint("assertions", SaConsole.DIM),
                SaConsole.tint("%.2fs" % elapsed, SaConsole.HEAD),
                SaConsole.tint("total", SaConsole.DIM),
            ]
        )
    )
    print_rich(
        (
            "   %s %s     %s %s     %s %s"
            % [
                SaConsole.tint("✓ %d" % total_passed, SaConsole.OK),
                SaConsole.tint("passed", SaConsole.DIM),
                SaConsole.tint("✗ %d" % total_failed, SaConsole.ERR if total_failed else SaConsole.DIM),
                SaConsole.tint("failed", SaConsole.DIM),
                SaConsole.tint("○ %d" % skipped_suites.size(), SaConsole.SKIP if skipped_suites else SaConsole.DIM),
                SaConsole.tint("skipped", SaConsole.DIM),
            ]
        )
    )
    SaConsole.close_box()
    SaConsole.blank()
    for line: String in memory.report():
        print_rich("   " + line)
    if not OS.get_environment("SARA_TEST_MEMORY_TABLE").is_empty():
        memory.write_table(OS.get_environment("SARA_TEST_MEMORY_TABLE"))
    SaConsole.blank()

    if not skipped_suites.is_empty():
        # A headless run silently skipping the GPU suites would look identical
        # to a full one, which is how a broken shader can pass unnoticed.
        SaConsole.notice("Skipped (no RenderingDevice): %s" % ", ".join(skipped_suites))
        SaConsole.blank()
    if not partly_skipped.is_empty():
        SaConsole.notice("Skipped in part on this machine, each saying why on its line: %s" % ", ".join(partly_skipped))
        SaConsole.blank()

    # "ALL TESTS PASSED" is also run_tests.sh's authoritative success marker: a
    # clean suite can still exit non-zero because Godot's Vulkan teardown
    # sometimes signals after the run, so the script trusts this line over the
    # exit code. Keep the wording stable.
    if filtered_out > 0:
        # Never the full-run marker: run_tests.sh greps for "ALL TESTS PASSED" and
        # trusts it over the exit code, so a filtered run that printed it would
        # turn "I ran one suite" into "the gate is green".
        SaConsole.notice("Filtered run - %d suite(s) not run. The gate needs a full run." % filtered_out)
        SaConsole.blank()
        if ok:
            print_rich("  %s %s" % [SaConsole.tint("✓", SaConsole.OK), SaConsole.bold("FILTERED RUN PASSED", SaConsole.OK)])
            SaConsole.blank()
    elif ok:
        print_rich("  %s %s" % [SaConsole.tint("✓", SaConsole.OK), SaConsole.bold("ALL TESTS PASSED", SaConsole.OK)])
        SaConsole.blank()

    if not ok:
        print_rich(
            (
                "  %s %s"
                % [
                    SaConsole.tint("✗", SaConsole.ERR),
                    (
                        SaConsole.bold("%d suite(s) failed: " % failed_suites.size(), SaConsole.ERR)
                        + SaConsole.tint(", ".join(failed_suites), SaConsole.DIM)
                    ),
                ]
            )
        )
        SaConsole.blank()
        get_tree().quit(1)
    else:
        get_tree().quit(0)


## Passes a frame, which frees every node a suite queued for deletion.
##
## A suite runs in one frame, and a node it queued waits for the next. Without
## one between suites, every Preferences window and page a suite closed stayed
## alive, still connected to `EventBus.theme_changed`, until a later suite
## happened to wait for a frame: 120,000 nodes outside the tree by the time the
## theme suites ran, and each of their palette switches rebuilt the rows of every
## page among them, 1,500 objects a switch and 3.5 GB over the run.
func _let_go_of_what_was_queued() -> void:
    await get_tree().process_frame


## Substring filters from the command line, ignoring Godot's own arguments.
func _filters() -> PackedStringArray:
    var found := PackedStringArray()
    for arg in OS.get_cmdline_user_args():
        if not arg.begins_with("-"):
            found.append(arg)
    return found


func _apply_filters(paths: Array[String], filters: PackedStringArray) -> Array[String]:
    if filters.is_empty():
        return paths
    var kept: Array[String] = []
    for path in paths:
        var suite_name := path.get_file().get_basename()
        for filter_text in filters:
            if suite_name.contains(filter_text):
                kept.append(path)
                break
    return kept


func _names_of(paths: Array[String]) -> String:
    var names: Array[String] = []
    for path in paths:
        names.append(path.get_file().get_basename())
    return ", ".join(names)


## Every suite in the tree, sorted so runs are reproducible.
##
## A suite lives in a `tests` folder beside the feature it tests, so the walk
## takes every `tests` folder under `res://` rather than a list of places. A
## list, of `res://tests` and of each module's `tests` in the layouts
## `ModuleLoader` accepts, would leave a suite moved beside its package unrun
## while the run still printed ALL TESTS PASSED.
func _discover_suites() -> Array[String]:
    return discover_suites_under("res://")


## The suites under *root*: every `test_*.gd` directly inside a folder named
## `tests`, the framework aside. A folder inside a `tests` folder holds its
## fixtures, a module or a scene a suite loads, and is not walked, and neither
## is a hidden folder such as `.godot`, `scratch`, a build, or a folder Godot
## itself ignores through `.gdignore`.
static func discover_suites_under(root: String) -> Array[String]:
    var paths: Array[String] = []
    _walk_for_suites(root, paths)
    paths.sort()
    return paths


## The suite names more than one of *paths* carries, each with the paths that
## carry it. A count or a failure is read by the suite's name alone, so two
## suites under one name read as one, and the run refuses to start.
static func shared_names(paths: Array[String]) -> Dictionary[String, Array]:
    var by_name: Dictionary[String, Array] = {}
    for path: String in paths:
        var suite_name := path.get_file().get_basename()
        if not by_name.has(suite_name):
            by_name[suite_name] = []
        by_name[suite_name].append(path)
    var shared: Dictionary[String, Array] = {}
    for suite_name: String in by_name:
        if by_name[suite_name].size() > 1:
            shared[suite_name] = by_name[suite_name]
    return shared


static func _walk_for_suites(dir_path: String, into: Array[String]) -> void:
    for dir_name: String in DirAccess.get_directories_at(dir_path):
        if UNWALKED_DIRS.has(dir_name):
            continue
        var child := dir_path.path_join(dir_name)
        if FileAccess.file_exists(child.path_join(".gdignore")):
            continue
        if dir_name == SUITES_DIR:
            into.append_array(_collect_suites_in(child))
        else:
            _walk_for_suites(child, into)


static func _collect_suites_in(dir_path: String) -> Array[String]:
    var found: Array[String] = []
    for file_name: String in DirAccess.get_files_at(dir_path):
        # Exported builds serve scripts as .gd.remap pointing at compiled bytecode.
        var script_name := file_name.trim_suffix(".remap")
        if script_name == FRAMEWORK_FILE:
            continue
        if script_name.begins_with("test_") and script_name.ends_with(".gd"):
            found.append(dir_path.path_join(script_name))
    return found


func _requires_gpu(suite_script: Script) -> bool:
    return suite_script.get_script_constant_map().get("REQUIRES_GPU", false)
