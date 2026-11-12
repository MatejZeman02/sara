## The repository carries a Windows build of its own.
##
## A Windows zip built from a preset derived by hand and thrown away could not be
## built again. What makes the build reproducible is the preset, the packaging
## script that drives it, and the icon the preset names, so this suite reads all
## three rather than the script's own output: a real export needs Godot's export
## templates, and `packaging/build.sh windows` is the run that leaves them under
## `build/w/`, the way `test_the_export_pack_leaves_scratch_out.gd` reads the
## Linux preset and leaves the export alone.
##
## A preset naming an icon that is not there exports a plain exe and says
## nothing about it, and a preset asking for no console wrapper exports one
## whose crash reports nobody can read, which is what the hand exports shipped.
## Both are silent in the export's own log, so both are graded here.
extends "res://tests/test_framework.gd"

const PRESETS := "res://export_presets.cfg"
const ICON := "res://ui/icon.ico"
const BUILD_SCRIPT := "packaging/build.sh"

## The platform name Godot's own preset carries, which is also the value of its
## `platform` key. A typo here is a preset the exporter never offers.
const WINDOWS_PLATFORM := "Windows Desktop"

## Where a Windows build lands, as a path from the project directory the way the
## preset writes it, and where the zipped build the alpha hands out is named.
const WINDOWS_OUTPUT := "../build/w/sara.exe"
const WINDOWS_ZIP_STEM := "sara-windows-x86_64"

## The sizes Windows picks from, 16 for the task bar up to 256 for the large
## icon view. 256 is stored as a PNG, which is what Vista onwards requires and
## what a `.ico` written by an older tool gets wrong.
const ICON_SIZES: Array[int] = [16, 24, 32, 48, 64, 128, 256]

## The permission bits that make a script runnable, 0o111.
const EXECUTE_BITS := 64 + 8 + 1

## The three files a stranger needs out of the zip: the exe, the console wrapper
## that makes its crash reports readable, and the stamp it was built with.
const ZIP_MEMBERS: Array[String] = ["sara.exe", "sara.console.exe", "build_info.json"]


func test_the_windows_preset_is_committed() -> void:
    var section := _windows_preset()
    assert_false(section.is_empty(), "export_presets.cfg carries a Windows Desktop preset")
    var options := "%s.options" % section
    var config := _presets()
    assert_eq(config.get_value(section, "name", ""), WINDOWS_PLATFORM, "The preset is named for its platform")
    assert_eq(config.get_value(section, "export_path", ""), WINDOWS_OUTPUT, "It exports the exe the script zips")
    assert_eq(
        config.get_value(options, "debug/export_console_wrapper", 0),
        2,
        "The console wrapper is written for a debug and a release export alike"
    )
    assert_true(
        config.get_value(options, "binary_format/embed_pck", false),
        "The pack is embedded, so a stranger downloads one file and runs it"
    )
    assert_eq(
        config.get_value(section, "exclude_filter", ""),
        config.get_value("preset.0", "exclude_filter", ""),
        "The Windows pack leaves res://scratch out the way the Linux pack does"
    )


func test_the_windows_preset_names_an_icon_that_is_there() -> void:
    var icon: String = _presets().get_value("%s.options" % _windows_preset(), "application/icon", "")
    assert_eq(icon, ICON, "The preset points at the project's own icon file")
    assert_true(FileAccess.file_exists(ICON), "%s is committed" % ICON)


func test_the_icon_carries_every_size_windows_asks_for() -> void:
    var entries := _icon_entries()
    var sizes: Array[int] = []
    for entry in entries:
        sizes.append(int(entry["size"]))
    for wanted in ICON_SIZES:
        assert_true(sizes.has(wanted), "The icon carries a %d by %d image" % [wanted, wanted])
    for entry in entries:
        if int(entry["size"]) == 256:
            assert_true(bool(entry["png"]), "The 256 by 256 image is a PNG, which is the only form Windows reads it in")


func test_the_linux_preset_still_exports_where_the_installer_looks() -> void:
    var config := _presets()
    assert_eq(config.get_value("preset.0", "name", ""), "Linux", "preset.0 is still the Linux preset")
    assert_eq(
        config.get_value("preset.0", "export_path", ""),
        "../build/l/sara.x86_64",
        "The installer reads build/l, so the Linux half keeps its output path"
    )
    assert_eq(
        config.get_value("preset.0.options", "debug/export_console_wrapper", 0),
        1,
        "The Linux preset is untouched by the Windows one"
    )


func test_the_build_script_takes_the_platform_and_zips_the_windows_build() -> void:
    var source := _read(_repo_path(BUILD_SCRIPT))
    assert_false(source.is_empty(), "%s is readable" % BUILD_SCRIPT)
    assert_true(source.contains(WINDOWS_PLATFORM), "%s names the Windows preset" % BUILD_SCRIPT)
    assert_true(source.contains(WINDOWS_ZIP_STEM), "%s names the zip it writes" % BUILD_SCRIPT)
    for member in ZIP_MEMBERS:
        assert_true(source.contains(member), "The zip carries %s" % member)
    var executable: Variant = _is_executable(_repo_path(BUILD_SCRIPT))
    if executable == null:
        skip("on Windows the mode of %s is git's to say, and no git knows this tree" % BUILD_SCRIPT)
        return
    assert_true(executable, "%s is executable" % BUILD_SCRIPT)


## The preset whose `platform` key is Windows Desktop, found by reading the file
## rather than by assuming it is `preset.1`: a preset added before it would move
## it, and the export path and the icon are read out of whichever carries the
## platform.
func _windows_preset() -> String:
    var config := _presets()
    for section: String in config.get_sections():
        if config.get_value(section, "platform", "") == WINDOWS_PLATFORM:
            return section
    return ""


func _presets() -> ConfigFile:
    var config := ConfigFile.new()
    assert_eq(config.load(PRESETS), OK, "%s loads" % PRESETS)
    return config


## The icon's own directory: one entry per image, each with a width and a height
## byte, a length and an offset into the file. A 256 pixel image has no room in
## a byte and is written as zero there, which is why the width is read back that
## way. Each image is a PNG when it starts with the PNG signature, which is what
## Windows requires of the 256 pixel one.
func _icon_entries() -> Array[Dictionary]:
    var file := FileAccess.open(ICON, FileAccess.READ)
    assert_not_null(file, "%s opens" % ICON)
    var bytes := file.get_buffer(file.get_length())
    assert_true(bytes.size() > 6, "%s is longer than its header" % ICON)
    var count := bytes[4] | (bytes[5] << 8)
    assert_eq(count, ICON_SIZES.size(), "The icon holds one image per size Windows asks for")
    var entries: Array[Dictionary] = []
    for i in count:
        var at := 6 + 16 * i
        var size := bytes[at] if bytes[at] != 0 else 256
        var length := bytes[at + 8] | (bytes[at + 9] << 8) | (bytes[at + 10] << 16) | (bytes[at + 11] << 24)
        var offset := bytes[at + 12] | (bytes[at + 13] << 8) | (bytes[at + 14] << 16) | (bytes[at + 15] << 24)
        assert_true(offset + length <= bytes.size(), "The %d by %d image fits inside the file" % [size, size])
        var signature := bytes.slice(offset, offset + 4).get_string_from_ascii()
        (
            entries
            . append(
                {
                    "size": size,
                    "length": length,
                    "png": signature == "\u0089PNG",
                }
            )
        )
    return entries


## Windows has no execute bit, so there the mode git records for the file is
## read instead, which is the mode a Linux checkout of the same commit gets.
## Null when git has no answer: a tree copied out by `git archive`, as a run
## on Windows may be, or a machine without git.
func _is_executable(absolute: String) -> Variant:
    if OS.get_name() == "Windows":
        var output: Array = []
        var code := OS.execute("git", ["-C", absolute.get_base_dir(), "ls-files", "-s", absolute.get_file()], output)
        var line := String(output[0]).strip_edges() if not output.is_empty() else ""
        if code != 0 or line.is_empty():
            return null
        return line.begins_with("100755")
    return (FileAccess.get_unix_permissions(absolute) & EXECUTE_BITS) == EXECUTE_BITS


func _repo_path(relative: String) -> String:
    return ProjectSettings.globalize_path("res://").path_join("..").path_join(relative).simplify_path()


func _read(absolute: String) -> String:
    var file := FileAccess.open(absolute, FileAccess.READ)
    return file.get_as_text() if file != null else ""
