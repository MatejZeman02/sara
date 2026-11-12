## A colour theme the painter saved before the palette's script moved still
## loads.
##
## `SaTheme.fork` writes a `.tres` through `ResourceSaver`, and every palette
## written before the script had a `.uid` beside it names the script by path
## alone, directly under `ui`, where the script once stood. Godot
## fails the whole parse on that one dead line, so the theme would leave the
## dropdown without a word. This
## suite writes one by hand, the way an old build did, and asks the theme for
## it the way the Colour Themes page does.
extends "res://tests/test_framework.gd"

## Where the palette's script stood in the old layout, built from two halves because
## `scripts/move_packages.py` rewrites every whole old path it finds in the
## tree, and this one is the fixture, not a reference to follow the move.
const OLD_PATH := "res://ui/" + "sa_palette.gd"

const STEM := "test-p32-old-path"

var _saved_theme: String = "default"
var _saved_path: String = ""


func before_each() -> void:
    _saved_theme = SaTheme.palette_id
    _saved_path = SaSettings.settings_path
    SaSettings.settings_path = ProjectSettings.globalize_path(SaDataRoot.path("test_p32_theme.cfg"))
    _remove()


func after_each() -> void:
    _remove()
    SaSettings.settings_path = _saved_path
    SaTheme.use_named(_saved_theme)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(SaDataRoot.path("test_p32_theme.cfg")))


func _remove() -> void:
    DirAccess.remove_absolute(SaTheme.custom_path(SaTheme.CUSTOM_PREFIX + STEM))


## What an old build wrote: the script by its former path and no `uid`.
func _write_old_palette() -> String:
    var path := SaTheme.custom_path(SaTheme.CUSTOM_PREFIX + STEM)
    DirAccess.make_dir_recursive_absolute(SaTheme.custom_dir())
    var file := FileAccess.open(path, FileAccess.WRITE)
    (
        file
        . store_string(
            (
                "\n"
                . join(
                    [
                        '[gd_resource type="Resource" script_class="SaPalette" format=3]',
                        "",
                        '[ext_resource type="Script" path="%s" id="1"]' % OLD_PATH,
                        "",
                        "[resource]",
                        'script = ExtResource("1")',
                        'display_name = "Old Path"',
                        "accent_primary = Color(0.1, 0.2, 0.9, 1)",
                        "",
                    ]
                )
            )
        )
    )
    file = null
    return path


func test_the_palettes_former_path_is_dead() -> void:
    assert_false(ResourceLoader.exists(OLD_PATH), "the script no longer stands at the path an old file names")


func test_an_old_saved_theme_loads_and_reads_its_colour_back() -> void:
    var path := _write_old_palette()
    var id := SaTheme.CUSTOM_PREFIX + STEM
    SaTheme.use_named(id)
    assert_eq(SaTheme.palette_id, id, "The old theme is the one in use, not the default it would fall back to")
    assert_true(SaTheme.palette.accent_primary.is_equal_approx(Color(0.1, 0.2, 0.9, 1.0)), "and its own colour is read back")
    assert_eq(SaTheme.palette.display_name, "Old Path", "with its own name")
    var names: Array = []
    for entry: Dictionary in SaTheme.available():
        names.append(entry["id"])
    assert_true(names.has(id), "The dropdown offers it again")
    var text := FileAccess.get_file_as_string(path)
    assert_true(text.contains('path="res://ui/themes/sa_palette.gd"'), "The file now names where the script lives")
    assert_true(text.contains('uid="uid://'), "and carries the uid that makes the next move harmless")


func test_every_shipped_palette_names_its_script_by_uid() -> void:
    for id: String in SaTheme.PALETTES:
        var text := FileAccess.get_file_as_string(SaTheme.PALETTES[id])
        assert_true(text.contains('uid="uid://'), "%s carries the script's uid" % id)
        assert_not_null(load(SaTheme.PALETTES[id]) as SaPalette, "and loads as a palette")
