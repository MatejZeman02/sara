## The export pack leaves every suite's fixture out.
##
## An `exclude_filter` that left out only `scratch/*` and `*/test_*.gd` would
## ship everything beside a suite under a `tests/` folder: the test pictures
## under `res://tests/data/`, the module fixtures under `res://tests/fixtures/`,
## the welcome window's test pictures, and in `sara-base-modules` a test bundle,
## two test tips and three suite helpers. A painter has no use for any. The scenarios' own
## fixtures and references and the two icon tracing references went the same
## way.
##
## The filters are read the way the exporter reads them, which
## `test_the_export_pack_leaves_scratch_out.gd` records: a filter excludes a
## file when the path matches it with the `res://` prefix or without, through
## `matchn`, whose `*` crosses a slash. This is the check that fails when a line goes.
extends "res://tests/test_framework.gd"

const PRESETS := "res://export_presets.cfg"

## One path per folder a fixture came out of, read off the 227 entries the
## export dropped. The last three are test-only files outside a
## `tests/` folder.
const FIXTURE_PATHS: Array[String] = [
    "res://tests/data/import_gradient.png",
    "res://tests/fixtures/modules/bundle-fixture/bundles/sara-fixtures.bundle",
    "res://tests/run_all.tscn",
    "res://modules/sara-base-modules/image-formats/radiance/tests/sky.hdr",
    "res://ui/files/tests/panorama.exr",
    "res://ui/welcome/tests/pictures/morning.png",
    "res://core/layers/scene/tests/two_tone_scene.tscn",
    "res://core/api/abr/tests/abr_writer.gd",
    "res://modules/sara-base-modules/stamp-brush/tests/fixtures/sara-fixtures.bundle",
    "res://modules/sara-base-modules/base/tests/map_bench.gd",
    "res://modules/sara-noise-brush-engine/tests/fixtures/paint.json",
    "res://scenarios/fixtures/h2-latitude-longitude-grid.png",
    "res://scenarios/references/a-photograph.jpg",
]

## Files the running app reads that stand next to one of those folders, so a
## filter that reaches too far fails here. The blue noise tile is the one
## submodule picture a build has to keep: `SaDitherFilter.thresholds()` decodes
## its bytes.
const KEPT_PATHS: Array[String] = [
    "res://project.godot",
    "res://tips/bush.png",
    "res://patterns/canvas_weave.gmacs",
    "res://ui/welcome/pictures/0.18.png",
    "res://assets/icons/bucket.svg",
    "res://modules/sara-base-modules/base/usual/dither_blue_noise.png",
    "res://modules/sara-noise-brush-engine/icons/noise_brush.svg",
    "res://scenarios/open-image-as-document.json",
    "res://harness/drivers/menu/sa_menu_driver.gd",
]


## Every preset section in the file, `preset.0` and any added after it.
func _presets() -> Array[String]:
    var config := ConfigFile.new()
    assert_eq(config.load(PRESETS), OK, "the export presets file loads")
    var found: Array[String] = []
    for section: String in config.get_sections():
        if section.begins_with("preset.") and not section.ends_with(".options"):
            found.append(section)
    return found


## The preset's exclude filters, split and trimmed as the exporter splits them.
func _excludes(section: String) -> Array[String]:
    var config := ConfigFile.new()
    config.load(PRESETS)
    var filters: Array[String] = []
    for part: String in str(config.get_value(section, "exclude_filter", "")).split(","):
        if not part.strip_edges().is_empty():
            filters.append(part.strip_edges())
    return filters


func _excluded(path: String, filters: Array[String]) -> bool:
    for filter: String in filters:
        if path.matchn(filter) or path.trim_prefix("res://").matchn(filter):
            return true
    return false


func test_every_preset_leaves_the_suites_fixtures_out() -> void:
    for section: String in _presets():
        var filters := _excludes(section)
        for path: String in FIXTURE_PATHS:
            assert_true(_excluded(path, filters), "%s excludes %s, filters %s" % [section, path, filters])


func test_no_preset_leaves_out_what_the_app_reads() -> void:
    for section: String in _presets():
        var filters := _excludes(section)
        for path: String in KEPT_PATHS:
            assert_false(_excluded(path, filters), "%s keeps %s, filters %s" % [section, path, filters])


## A path the suites name has to be a real one, or this suite would pass on a
## typo for ever.
func test_the_paths_read_are_the_trees_own() -> void:
    for path: String in FIXTURE_PATHS + KEPT_PATHS:
        assert_true(FileAccess.file_exists(path), "%s is a file in the tree" % path)
