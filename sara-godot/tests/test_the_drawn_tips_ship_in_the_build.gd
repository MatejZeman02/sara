## The build carries the tips in `res://tips`.
##
## The folder had a `.gdignore`, so Godot would not import its PNGs into
## textures and drop their bytes, and the preset's `include_filter` was meant to
## pack the raw files anyway. Godot 4.7's exporter packs nothing from a folder
## its file system ignores, so all 23 drawn tips and the three older ones were
## missing from the build. Every drawn-tip preset painted nothing, said
## "torn-block.png could not be read." and drew a blank thumbnail, while the
## editor and the gate read the files straight off the disk and passed.
##
## The folder is visible now and each PNG has an import file with the `keep`
## importer, Godot's "Keep File (exported as is)", which packs the bytes
## untouched. These hold both halves, so a tip added without its import file,
## which Godot would turn into a texture, fails here rather than in a build.
## The pack itself was listed after the fix: all 28 files are in it.
extends "res://tests/test_framework.gd"

const TIPS := "res://tips"
const PRESETS := "res://export_presets.cfg"


func _files(extension: String) -> Array[String]:
    var found: Array[String] = []
    for file: String in DirAccess.get_files_at(TIPS):
        if file.get_extension().to_lower() == extension:
            found.append(file)
    return found


func test_the_tips_folder_is_not_ignored() -> void:
    var ignored := FileAccess.file_exists(TIPS.path_join(".gdignore"))
    assert_false(ignored, "res://tips has no .gdignore, or the exporter leaves every tip out")


func test_there_are_tips_to_check() -> void:
    assert_true(_files("png").size() >= 23, "res://tips holds the drawn tips, found %d" % _files("png").size())


func test_every_png_tip_is_kept_as_it_is() -> void:
    for file: String in _files("png"):
        var config := ConfigFile.new()
        var path := TIPS.path_join(file + ".import")
        assert_eq(config.load(path), OK, "%s has an import file" % file)
        assert_eq(str(config.get_value("remap", "importer", "")), "keep", "%s is imported with keep, so its bytes ship" % file)


func test_every_preset_packs_the_raw_tip_files() -> void:
    var config := ConfigFile.new()
    assert_eq(config.load(PRESETS), OK, "the export presets file loads")
    for section: String in config.get_sections():
        if not section.begins_with("preset.") or section.ends_with(".options"):
            continue
        var filters := str(config.get_value(section, "include_filter", ""))
        for wanted: String in ["*.png", "*.gbr", "*.gih"]:
            assert_true(filters.contains(wanted), "%s includes %s, filters %s" % [section, wanted, filters])
