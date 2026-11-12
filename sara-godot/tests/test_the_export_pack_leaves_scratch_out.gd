## The export pack leaves the checkout's scratch profiles out.
##
## `scratch/` is gitignored and holds the profiles the offscreen gate and the
## captures write, but it sits under `res://` with no `.gdignore`, and the Linux
## preset exports every resource. So a pack made from a checkout that had run the
## gate stored 287 files from `res://scratch`, a settings file, a docker layout
## and every brush preset among them, and 544 files in all once the textures and
## resources the editor had converted from them are counted.
##
## The fix is the preset's `exclude_filter`, and these read it the way the
## exporter does: a filter excludes a file when it matches the path with its
## `res://` prefix or without it, through `matchn`. This is the check that fails when the line goes.
extends "res://tests/test_framework.gd"

const PRESETS := "res://export_presets.cfg"

## Paths a pack from a checkout that ran the gate actually stored, one per kind of file.
const SCRATCH_PATHS: Array[String] = [
    "res://scratch/xdg/config/sara/settings.cfg",
    "res://scratch/xdg-gate/config/sara/docker_layout.cfg",
    "res://scratch/xdg/data/godot/app_userdata/Sara/brush_presets/Sketch.tres",
    "res://scratch/xdg-gate/data/godot/app_userdata/Sara/patterns/sara-fixture-grain.png",
]

## Paths the pack must keep, so a filter that swallows the project fails too.
const KEPT_PATHS: Array[String] = [
    "res://project.godot",
    "res://core/export/sa_export.gd",
    "res://ui/scratchpad_docker.gd",
    "res://patterns/scratch.gmacs",
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


func test_there_is_a_preset_to_read() -> void:
    assert_true(_presets().size() > 0, "export_presets.cfg declares at least one preset")


func test_every_preset_leaves_the_scratch_profiles_out() -> void:
    for section: String in _presets():
        var filters := _excludes(section)
        for path: String in SCRATCH_PATHS:
            assert_true(_excluded(path, filters), "%s excludes %s, filters %s" % [section, path, filters])


func test_no_preset_excludes_the_project_itself() -> void:
    for section: String in _presets():
        var filters := _excludes(section)
        for path: String in KEPT_PATHS:
            assert_false(_excluded(path, filters), "%s keeps %s, filters %s" % [section, path, filters])
