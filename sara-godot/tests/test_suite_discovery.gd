## Where the runner finds a suite, and that the pack leaves every one out.
##
## A suite lives in a `tests` folder beside the feature it tests, so
## `run_all.gd` walks every such folder under `res://`. These build a small tree
## of their own under the data root and ask the runner's walk what it finds
## there, and then ask the same of the real tree.
extends "res://tests/test_framework.gd"

const RunAll := preload("res://tests/run_all.gd")
const PRESETS := "res://export_presets.cfg"

## Suites the walk has to find, one per kind of home.
const FOUND: Array[String] = [
    "tests/test_the_whole_tree.gd",
    "core/layers/tests/test_a_layer_moves.gd",
    "modules/one-module/tests/test_its_filter.gd",
    "modules/a-collection/its-module/tests/test_its_tool.gd",
]

## Files the walk has to leave alone, each for its own reason.
const LEFT: Array[String] = [
    "tests/test_framework.gd",
    "tests/helper.gd",
    "tests/fixtures/modules/fixture/tests/test_a_fixture_module.gd",
    "core/layers/test_not_in_a_tests_folder.gd",
    "scratch/tests/test_a_probe.gd",
    "build/w/tests/test_a_copy.gd",
    "ignored/tests/test_behind_a_gdignore.gd",
]

var _root := SaDataRoot.path("suite_discovery")


func _write(relative: String) -> void:
    var path := _root.path_join(relative)
    DirAccess.make_dir_recursive_absolute(path.get_base_dir())
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string("extends RefCounted\n")
    file.close()


func _remove(path: String) -> void:
    if not DirAccess.dir_exists_absolute(path):
        return
    for name: String in DirAccess.get_directories_at(path):
        _remove(path.path_join(name))
    for name: String in DirAccess.get_files_at(path):
        DirAccess.remove_absolute(path.path_join(name))
    DirAccess.remove_absolute(path)


func _found_in_the_small_tree() -> Array[String]:
    _remove(_root)
    for relative: String in FOUND + LEFT:
        _write(relative)
    _write("ignored/.gdignore")
    var found: Array[String] = []
    for path: String in RunAll.discover_suites_under(_root):
        found.append(path.trim_prefix(_root + "/"))
    _remove(_root)
    return found


func test_every_tests_folder_is_walked() -> void:
    var found := _found_in_the_small_tree()
    for relative: String in FOUND:
        assert_true(found.has(relative), "the walk finds %s, found %s" % [relative, found])


func test_fixtures_probes_builds_and_helpers_are_left_alone() -> void:
    var found := _found_in_the_small_tree()
    for relative: String in LEFT:
        assert_false(found.has(relative), "the walk leaves %s alone" % relative)
    assert_eq(found.size(), FOUND.size(), "the walk finds the suites and nothing else")


func test_the_real_tree_finds_this_suite_and_the_modules() -> void:
    var found := RunAll.discover_suites_under("res://")
    assert_true(found.has("res://tests/test_suite_discovery.gd"), "the walk finds this suite")
    assert_true(
        found.has("res://modules/sara-base-modules/kaleidoscope/tests/test_kaleidoscope.gd"),
        "the walk finds a module's suite",
    )
    for path: String in found:
        assert_false(path.contains("/fixtures/"), "no fixture is taken for a suite: %s" % path)


## No two suites in the tree share a name, which is what the runner refuses to
## start on.
func test_no_two_suites_in_the_tree_share_a_name() -> void:
    var shared := RunAll.shared_names(RunAll.discover_suites_under("res://"))
    assert_true(shared.is_empty(), "every suite has a name of its own, shared: %s" % shared)


## A copy of a real suite in a second package's `tests` folder is named by the
## check, with both of its paths, and the suites around it are not.
func test_a_copied_suite_is_named_with_both_its_homes() -> void:
    _remove(_root)
    for relative: String in FOUND:
        _write(relative)
    _write("ui/themes/tests/test_a_layer_moves.gd")
    var shared := RunAll.shared_names(RunAll.discover_suites_under(_root))
    _remove(_root)
    assert_eq(shared.keys(), ["test_a_layer_moves"], "only the copied name is shared")
    var carriers: Array = shared.get("test_a_layer_moves", [])
    assert_eq(carriers.size(), 2, "and it names both suites that carry it")
    assert_true(
        _root.path_join("core/layers/tests/test_a_layer_moves.gd") in carriers,
        "the original is one, found %s" % [carriers],
    )
    assert_true(
        _root.path_join("ui/themes/tests/test_a_layer_moves.gd") in carriers,
        "and the copy the other, found %s" % [carriers],
    )


## The preset's exclude filters, split and trimmed as the exporter splits them.
func _excludes(section: String) -> Array[String]:
    var config := ConfigFile.new()
    assert_eq(config.load(PRESETS), OK, "the export presets file loads")
    var filters: Array[String] = []
    for part: String in str(config.get_value(section, "exclude_filter", "")).split(","):
        if not part.strip_edges().is_empty():
            filters.append(part.strip_edges())
    return filters


## A filter excludes a path when it matches it with its `res://` or without,
## through `matchn`, which is how a pack exported on 2026-09-26 behaved.
func _excluded(path: String, filters: Array[String]) -> bool:
    for filter: String in filters:
        if path.matchn(filter) or path.trim_prefix("res://").matchn(filter):
            return true
    return false


func test_the_pack_leaves_every_suite_out_wherever_it_lives() -> void:
    var config := ConfigFile.new()
    config.load(PRESETS)
    var suites := RunAll.discover_suites_under("res://")
    suites.append("res://core/layers/tests/test_a_layer_moves.gd")
    for section: String in config.get_sections():
        if not section.begins_with("preset.") or section.ends_with(".options"):
            continue
        var filters := _excludes(section)
        for path: String in suites:
            assert_true(_excluded(path, filters), "%s leaves %s out, filters %s" % [section, path, filters])
        # The pack leaves the whole `tests/` folder out, the runner with it,
        # so the guard against a filter that swallows the project is a
        # shipped script deep in a package instead.
        for kept: String in ["res://harness/sa_step_table.gd", "res://core/export/sa_export.gd", "res://project.godot"]:
            assert_false(_excluded(kept, filters), "%s keeps %s, filters %s" % [section, kept, filters])
