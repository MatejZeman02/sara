## A gradient the painter saved before the preset's script moved
## still loads.
##
## A gradient preset written before the script had a `.uid` names it by path
## alone, directly under `core`, where it stood until it moved
## into `core/api/color`. The preset store repairs such a line before every
## load, which is what freed the file to move, and this suite holds that:
## a preset written by hand the way an old build wrote it, opened through the
## store, with its stops read back.
extends "res://tests/test_framework.gd"

## Never the real `user://gradient_presets`, for the reason
## `test_gradient_presets.gd` gives.
var scratch_dir: String = SaDataRoot.path("test_p32_gradient")

## Where the preset's script stood, in two halves so that
## `scripts/move_packages.py`, which rewrites every whole old path in the tree,
## leaves the fixture as the old build wrote it.
const OLD_PATH := "res://core/" + "sa_gradient_preset.gd"


func before_each() -> void:
    _clear()


func after_each() -> void:
    _clear()


func _clear() -> void:
    if not DirAccess.dir_exists_absolute(scratch_dir):
        return
    for file_name: String in DirAccess.get_files_at(scratch_dir):
        DirAccess.remove_absolute(scratch_dir.path_join(file_name))
    DirAccess.remove_absolute(scratch_dir)


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store


func _write_old_preset(stem: String) -> String:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var path := scratch_dir.path_join(stem + ".tres")
    var file := FileAccess.open(path, FileAccess.WRITE)
    (
        file
        . store_string(
            (
                "\n"
                . join(
                    [
                        '[gd_resource type="Resource" script_class="SaGradientPreset" load_steps=2 format=3]',
                        "",
                        '[ext_resource type="Script" path="%s" id="1_preset"]' % OLD_PATH,
                        "",
                        "[resource]",
                        'script = ExtResource("1_preset")',
                        (
                            'stops = [{"position": 0.0, "color": [0.9, 0.7, 0.2, 1.0]}, '
                            + '{"position": 0.45, "color": [0.1, 0.75, 0.25, 1.0]}, '
                            + '{"position": 1.0, "color": [0.2, 0.3, 0.8, 0.0]}]'
                        ),
                        "",
                    ]
                )
            )
        )
    )
    file = null
    return path


func test_the_presets_former_path_is_dead() -> void:
    assert_false(ResourceLoader.exists(OLD_PATH), "the script no longer stands at the path an old file names")


func test_an_old_saved_gradient_loads_through_the_store_with_its_stops() -> void:
    var path := _write_old_preset("OldSunset")
    var preset := _store().load_preset("OldSunset") as SaGradientPreset
    assert_not_null(preset, "The old gradient loads as a gradient preset")
    if preset == null:
        return
    var ramp := preset.to_ramp()
    assert_eq(ramp.stops.size(), 3, "with its three stops, not the two a fallback ramp has")
    assert_almost_eq(float(ramp.stops[1]["position"]), 0.45, 0.0001, "the middle stop where it was put")
    assert_true((ramp.stops[1]["color"] as Color).is_equal_approx(Color(0.1, 0.75, 0.25, 1.0)), "in its own colour")
    assert_almost_eq((ramp.stops[2]["color"] as Color).a, 0.0, 0.0001, "and the last stop's alpha of zero survives")
    var text := FileAccess.get_file_as_string(path)
    assert_true(text.contains('path="res://core/api/color/sa_gradient_preset.gd"'), "The file now names where the script lives")
    assert_true(text.contains('uid="uid://'), "and carries its uid")
