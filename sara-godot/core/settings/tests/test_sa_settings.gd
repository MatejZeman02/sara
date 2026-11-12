## SaSettings: persistence, the settings directory, and the layout overrides.
##
## The class is an autoload every setter of which writes to disk, so the runner
## points it at a scratch file before any suite runs (see run_all.gd). Without
## that, asserting anything here would edit the user's real preferences.
extends "res://tests/test_framework.gd"

static var scratch_path: String = SaDataRoot.path("test_sa_settings_scratch.cfg")

var _saved_knee: float
var _saved_desaturation: float
var _saved_tonemap: bool
var _saved_path: String


func before_each() -> void:
    _saved_knee = SaSettings.tonemap_knee
    _saved_desaturation = SaSettings.tonemap_desaturation
    _saved_tonemap = SaSettings.tonemap_highlights
    _saved_path = SaSettings.settings_path


## Restores what this suite found, not what the defaults happen to be. Restoring
## a default is how a suite could reset a preference the user had
## deliberately changed.
func after_each() -> void:
    SaSettings.settings_path = _saved_path
    SaSettings.tonemap_knee = _saved_knee
    SaSettings.tonemap_desaturation = _saved_desaturation
    SaSettings.tonemap_highlights = _saved_tonemap
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_path))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(SaDataRoot.path("test_sa_settings_other.cfg")))


# --- Persistence -----------------------------------------------------------------


## The whole promise of the class, and nothing asserted it. A setting that
## records itself in memory but does not survive a restart is worse than a
## missing one, because the user believes they have set it.
func test_a_setting_survives_a_save_and_a_load() -> void:
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_path)
    SaSettings.tonemap_knee = 0.42
    SaSettings.tonemap_desaturation = 0.7
    SaSettings.tonemap_highlights = true

    # Every setter saves, so moving away from the values has to happen against a
    # different file or it would overwrite the one under test.
    SaSettings.settings_path = ProjectSettings.globalize_path(SaDataRoot.path("test_sa_settings_other.cfg"))
    SaSettings.tonemap_knee = 0.11
    SaSettings.tonemap_highlights = false

    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_path)
    SaSettings.load_settings()

    assert_almost_eq(SaSettings.tonemap_knee, 0.42, 0.0001, "The stored knee comes back")
    assert_almost_eq(SaSettings.tonemap_desaturation, 0.7, 0.0001, "and so does the stored desaturation")
    assert_true(SaSettings.tonemap_highlights, "and the toggle")


## A file that does not exist is a first run, not a failure. It has to leave
## every value at its default rather than at whatever was in memory.
func test_a_missing_file_loads_defaults_rather_than_failing() -> void:
    # Set the value first: assigning it after repointing would save, and the
    # file under test would exist by the time it is loaded.
    SaSettings.tonemap_knee = 0.9
    var absent := ProjectSettings.globalize_path(SaDataRoot.path("test_sa_settings_absent.cfg"))
    DirAccess.remove_absolute(absent)
    SaSettings.settings_path = absent

    SaSettings.load_settings()

    assert_almost_eq(SaSettings.tonemap_knee, 1.0, 0.0001, "A first run starts from the defaults")
    DirAccess.remove_absolute(absent)


## Clamping happens in the setter, so it also applies to a value read off disk.
## A hand-edited config must not be able to push the shader outside its range.
func test_a_value_from_disk_is_clamped_like_one_from_a_slider() -> void:
    var config := ConfigFile.new()
    config.set_value("meta", "version", SaSettings.SETTINGS_VERSION)
    config.set_value("ui", "tonemap_knee", 9.0)
    config.set_value("ui", "tonemap_desaturation", -3.0)
    config.save(ProjectSettings.globalize_path(scratch_path))

    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_path)
    SaSettings.load_settings()

    assert_almost_eq(
        SaSettings.tonemap_knee, SaSettings.TONEMAP_KNEE_TOP, 0.0001, "A hand-edited knee is clamped to the top of the range"
    )
    assert_almost_eq(SaSettings.tonemap_desaturation, 0.0, 0.0001, "and a negative desaturation to the bottom")


## A first launch, modelled: the scratch path holds no profile and `config` is
## the empty one the autoload is constructed with.
##
## Replacing `config` is the whole of what makes this a first launch. A missing
## file leaves in place whatever the load before it read, so a test that only
## deletes the file writes a profile carrying every key the last one had,
## `meta/version` included, and passes whether or not the stamp exists. That is
## how the first version of these three tests was green against the defect.
func _first_launch(path: String) -> ConfigFile:
    var previous: ConfigFile = SaSettings.config
    DirAccess.remove_absolute(path)
    SaSettings.config = ConfigFile.new()
    SaSettings.settings_path = path
    return previous


## A profile a first launch writes carries no `meta` section unless
## something puts one there, so the launch after it reads `stored_version` 1 and
## runs every migration on a file written by this build.
func test_a_profile_written_from_the_defaults_is_stamped_with_this_version() -> void:
    var absent := ProjectSettings.globalize_path(scratch_path)
    var was_scale := SaSettings.ui_scale
    var previous := _first_launch(absent)

    SaSettings.load_settings()

    var written := ConfigFile.new()
    var loaded := written.load(absent)
    var stamped: int = int(written.get_value("meta", "version", 0))
    SaSettings.config = previous
    SaSettings.ui_scale = was_scale

    assert_eq(loaded, OK, "The first launch wrote a profile")
    assert_eq(stamped, SaSettings.SETTINGS_VERSION, "and stamped it with this build's version, not left it unversioned")


## The defect itself, end to end, in the two loads that showed it: a scale set on
## a fresh profile survives the next load. Without the stamp the version-2
## migration read it as a pre-multiplier scale and reset it to 1.0, and only on
## that one load, because the migration stamped the file on its way out.
func test_a_scale_set_on_a_fresh_profile_survives_the_next_load() -> void:
    var scratch := ProjectSettings.globalize_path(scratch_path)
    var was_scale := SaSettings.ui_scale
    var previous := _first_launch(scratch)

    SaSettings.load_settings()
    SaSettings.ui_scale = 1.25
    # The second launch, against the file the first one left.
    SaSettings.config = ConfigFile.new()
    SaSettings.load_settings()

    var survived := SaSettings.ui_scale
    SaSettings.config = previous
    SaSettings.ui_scale = was_scale
    assert_almost_eq(survived, 1.25, 0.0001, "The second load reads the scale the first one saved")


## A reset writes current defaults, so it is stamped for the same reason. A
## profile reset while an old version was stored would otherwise be migrated on
## the next launch, and the version-2 step would reset a scale nobody had
## carried over from the old meaning.
func test_a_reset_profile_is_stamped_too() -> void:
    var scratch := ProjectSettings.globalize_path(scratch_path)
    var was_scale := SaSettings.ui_scale
    var previous := _first_launch(scratch)
    SaSettings.config.set_value("meta", "version", 1)

    SaSettings.reset_to_defaults()

    var written := ConfigFile.new()
    var loaded := written.load(scratch)
    var stamped: int = int(written.get_value("meta", "version", 0))
    SaSettings.config = previous
    SaSettings.ui_scale = was_scale

    assert_eq(loaded, OK, "The reset wrote the profile")
    assert_eq(stamped, SaSettings.SETTINGS_VERSION, "and stamped it with this version")


## "Reset all settings to defaults" walked a hand-written list
## that had fallen nine keys behind, so a painter who reset kept the grid, the
## second row, the pinned blend modes, the interface font and both proof modes.
## These are the nine, each set away from its default, and the reset has to put
## every one back.
func test_a_reset_puts_back_the_nine_keys_it_used_to_walk_past() -> void:
    var scratch := ProjectSettings.globalize_path(scratch_path)
    var was_scale := SaSettings.ui_scale
    var previous := _first_launch(scratch)
    var fresh := SaSettingsValues.new()
    var kept := {
        &"second_row": false,
        &"docker_hide_button": false,
        &"show_grid": true,
        &"keep_blend_mode": true,
        &"import_fit": "inside",
        &"blend_favorites": ["screen"],
        &"canvas_proof_mode": "d12_proof",
        &"minimap_proof_mode": "d12_proof",
        &"ui_font": "noto-sans",
    }
    # Read what is stored rather than the property, because the property
    # resolves a proof mode through the registry and answers the default for
    # an id nothing registered, which would hide a reset that did nothing.
    var moved := 0
    for property: StringName in kept:
        SaSettings.set(String(property), kept[property])
        if SaSettings.stored(String(property)) != fresh.stored(String(property)):
            moved += 1

    SaSettings.reset_to_defaults()

    var back := {}
    for property: StringName in kept:
        back[property] = SaSettings.stored(String(property)) == fresh.stored(String(property))
    fresh.free()
    SaSettings.config = previous
    SaSettings.ui_scale = was_scale

    assert_eq(moved, 9, "all nine took a value away from their default first")
    for property: StringName in back:
        assert_true(back[property], "the reset put %s back to its default" % property)


## The other hand-written list, three keys short: a fresh profile has to say
## what it holds, so `ui/import_fit`, `ui/blend_favorites` and `theme/font` are
## in the file a first launch writes.
func test_a_first_launch_writes_the_three_keys_it_used_to_skip() -> void:
    var scratch := ProjectSettings.globalize_path(scratch_path)
    var was_scale := SaSettings.ui_scale
    var previous := _first_launch(scratch)

    SaSettings.load_settings()

    var written := ConfigFile.new()
    var loaded := written.load(scratch)
    SaSettings.config = previous
    SaSettings.ui_scale = was_scale

    assert_eq(loaded, OK, "The first launch wrote a profile")
    for place: Array in [["ui", "import_fit"], ["ui", "blend_favorites"], ["theme", "font"]]:
        assert_true(written.has_section_key(place[0], place[1]), "and it carries %s/%s" % [place[0], place[1]])


## a build that shipped with six top-bar menus empty hid them by default
## and saved the default as if it were a choice, so a profile from before the
## migration cannot tell "hidden by default" from "hidden on purpose".
func test_a_pre_v8_profile_shows_the_six_menus_the_default_used_to_hide() -> void:
    var config := ConfigFile.new()
    config.set_value("meta", "version", 7)
    for menu: String in ["View", "Dockers", "Image", "Layer", "Select", "Filter"]:
        config.set_value("profile_visibility", "TopMenuBar_%s" % menu, false)
    config.set_value("profile_visibility", "TopMenuBar_File", true)
    config.save(ProjectSettings.globalize_path(scratch_path))

    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_path)
    SaSettings.load_settings()

    for menu: String in ["View", "Dockers", "Image", "Layer", "Select", "Filter"]:
        assert_true(SaSettings.get_element_visible("TopMenuBar", menu), "%s comes back shown once" % menu)
    assert_true(SaSettings.get_element_visible("TopMenuBar", "File"), "a saved true is untouched")


## Godot's own picker left the colour docker, so a stored order that
## still lists it would offer a Preferences row for a control that is not
## there, and one written before the dropdown would never show it, since a
## stored order is handed back verbatim.
##
## The migration is driven with a `ConfigFile` of this suite's own rather than
## through the autoload and the disk, for the reason the pitfall beside
## `ConfigFile.load()` gives: a load merges into what the object already holds,
## so a profile written here would leak its sections into the next test.
func test_a_pre_v10_profile_loses_the_godot_picker_and_gains_the_shape_row() -> void:
    var config := ConfigFile.new()
    config.set_value("meta", "version", 9)
    config.set_value(
        "profile_order",
        "ColorPicker",
        ["Drag Handle", "Resizer", "HSV Wheel", "Selected Colour Preview", "Hex Input", "Godot HSL Picker"]
    )
    config.set_value("profile_visibility", "ColorPicker_Godot HSL Picker", false)

    SaSettingsMigrations.apply(config, 9)

    var order: Array = config.get_value("profile_order", "ColorPicker", [])
    assert_false(order.has("Godot HSL Picker"), "The picker that left is out of the stored order")
    # Version 10 put the choice of shape in its place and version 13 took the
    # row out again, because the dropdown moved to the Preferences page as a
    # per-docker option. A pre-v10 profile runs through both, so what it
    # ends with is neither row rather than one of them.
    assert_false(order.has("Picker Type"), "and so is the row that replaced it, which version 13 moved")
    assert_false(
        config.has_section_key("profile_visibility", "ColorPicker_Godot HSL Picker"),
        "and the key that hid it is not left behind to hide the row that replaced it"
    )


## A file already at the current version is not the migration's business,
## even if it holds the same shape a pre-v8 file would.
func test_a_current_version_file_keeps_a_hidden_menu_hidden() -> void:
    var config := ConfigFile.new()
    config.set_value("meta", "version", SaSettings.SETTINGS_VERSION)
    config.set_value("profile_visibility", "TopMenuBar_View", false)
    config.save(ProjectSettings.globalize_path(scratch_path))

    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_path)
    SaSettings.load_settings()

    assert_false(SaSettings.get_element_visible("TopMenuBar", "View"), "A file at the new version is not touched")
    SaSettings.set_element_visible("TopMenuBar", "View", true)


# --- The settings directory ------------------------------------------------------


## Where preferences live is the one thing that must not quietly change, because
## being wrong means every setting silently fails to persist. On Linux XDG wins.
##
## Against `SaSettingsFile.platform_default()` rather than
## `SaSettings.get_settings_dir()`: the latter also reads a real
## `--settings-dir` off this very process's command line, which an
## offscreen gate run under that flag always wins, and these two tests are
## about XDG, not about flag priority.
func test_the_settings_directory_follows_xdg_config_home() -> void:
    if OS.get_name() not in ["Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD"]:
        return

    var previous := OS.get_environment("XDG_CONFIG_HOME")
    OS.set_environment("XDG_CONFIG_HOME", "/tmp/sara-xdg-probe")
    var directory := SaSettingsFile.platform_default()
    if previous.is_empty():
        OS.unset_environment("XDG_CONFIG_HOME")
    else:
        OS.set_environment("XDG_CONFIG_HOME", previous)

    assert_eq(directory, "/tmp/sara-xdg-probe/sara", "XDG_CONFIG_HOME decides, and the app appends its own name")


func test_the_settings_directory_falls_back_to_dot_config() -> void:
    if OS.get_name() not in ["Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD"]:
        return

    var previous_xdg := OS.get_environment("XDG_CONFIG_HOME")
    var previous_home := OS.get_environment("HOME")
    OS.unset_environment("XDG_CONFIG_HOME")
    OS.set_environment("HOME", "/tmp/sara-home-probe")
    var directory := SaSettingsFile.platform_default()
    OS.set_environment("HOME", previous_home)
    if not previous_xdg.is_empty():
        OS.set_environment("XDG_CONFIG_HOME", previous_xdg)

    assert_eq(directory, "/tmp/sara-home-probe/.config/sara", "Without XDG the spec says ~/.config")


## --settings-dir wins outright, ahead of any pointer or platform default.
func test_settings_dir_flag_is_read_with_a_space() -> void:
    var found := SaDataRoot.flag_in(PackedStringArray(["godot", "--settings-dir", "/tmp/sara-flag-probe"]))
    assert_eq(found, "/tmp/sara-flag-probe", "the value after the flag is the path")


func test_settings_dir_flag_is_read_with_an_equals_sign() -> void:
    var found := SaDataRoot.flag_in(PackedStringArray(["godot", "--settings-dir=/tmp/sara-flag-probe"]))
    assert_eq(found, "/tmp/sara-flag-probe", "the flag also takes the Godot-style single argument")


func test_settings_dir_flag_absent_is_empty() -> void:
    var found := SaDataRoot.flag_in(PackedStringArray(["godot", "--path", "."]))
    assert_eq(found, "", "no flag means no override, so the pointer or the default decides")


## A folder chosen through Preferences is a pointer file in the default
## folder, in a run without the flag. This process carries the runner's own
## `--settings-dir`, so the no-flag path is reached by handing the call an
## empty flag, and the pointer is read back through `read_pointer()` rather than
## `SaSettings.get_settings_dir()`, for the same reason as the two tests above.
func test_a_chosen_folder_survives_as_a_pointer_in_the_default_folder() -> void:
    var previous := OS.get_environment(_default_root_variable())
    var default_root := OS.get_temp_dir().path_join("sara-pointer-probe")
    OS.set_environment(_default_root_variable(), default_root)

    SaSettingsFile.set_pointer("/tmp/sara-chosen-folder", "")
    var default_dir := SaSettingsFile.platform_default()
    var pointed_at := SaSettingsFile.read_pointer("")

    DirAccess.remove_absolute(default_dir.path_join(SaSettingsFile.LOCATION_FILE))
    if previous.is_empty():
        OS.unset_environment(_default_root_variable())
    else:
        OS.set_environment(_default_root_variable(), previous)

    assert_eq(default_dir, default_root.path_join("sara"), "the pointer lives in the platform default folder")
    assert_eq(pointed_at, "/tmp/sara-chosen-folder", "and it names the folder Preferences chose")


## "Use Default" clears the pointer rather than leaving an empty one behind.
func test_clearing_the_pointer_leaves_nothing_to_read() -> void:
    var previous := OS.get_environment(_default_root_variable())
    var default_root := OS.get_temp_dir().path_join("sara-pointer-probe-2")
    OS.set_environment(_default_root_variable(), default_root)

    SaSettingsFile.set_pointer("/tmp/sara-chosen-folder-2", "")
    SaSettingsFile.set_pointer("", "")
    var pointed_at := SaSettingsFile.read_pointer("")

    if previous.is_empty():
        OS.unset_environment(_default_root_variable())
    else:
        OS.set_environment(_default_root_variable(), previous)

    assert_eq(pointed_at, "", "no pointer left behind means the platform default answers again")


## the pointer a scenario writes belongs to the scenario. A run with
## `--settings-dir` once wrote the painter's own `location.cfg`, and the
## installed Sara then read its settings from a test folder at their defaults.
## The default root is pointed at one scratch folder and the flag at another,
## and only the flag's may end up holding a pointer.
func test_a_run_with_the_flag_writes_its_pointer_under_the_flags_folder() -> void:
    var previous := OS.get_environment(_default_root_variable())
    var default_root := OS.get_temp_dir().path_join("sara-pointer-probe-3")
    var flag_dir := OS.get_temp_dir().path_join("sara-pointer-flag-probe")
    OS.set_environment(_default_root_variable(), default_root)
    var default_pointer := SaSettingsFile.platform_default().path_join(SaSettingsFile.LOCATION_FILE)
    # A probe left by an earlier run, or by a build that wrote the wrong file,
    # would otherwise fail this case for good.
    DirAccess.remove_absolute(default_pointer)

    SaSettingsFile.set_pointer("/tmp/sara-another-settings-folder", flag_dir)
    var flag_pointer := flag_dir.path_join(SaSettingsFile.LOCATION_FILE)
    var landed_in_flag := FileAccess.file_exists(flag_pointer)
    var landed_in_default := FileAccess.file_exists(default_pointer)
    var pointed_at := SaSettingsFile.read_pointer(flag_dir)
    var default_answers := SaSettingsFile.read_pointer("")

    SaSettingsFile.set_pointer("", flag_dir)
    var cleared := not FileAccess.file_exists(flag_pointer)
    DirAccess.remove_absolute(flag_dir)
    if previous.is_empty():
        OS.unset_environment(_default_root_variable())
    else:
        OS.set_environment(_default_root_variable(), previous)

    assert_true(landed_in_flag, "the pointer is a file in the flag's folder")
    assert_false(landed_in_default, "and the default root has no location.cfg")
    assert_eq(pointed_at, "/tmp/sara-another-settings-folder", "and a read with the flag finds the row's value there")
    assert_eq(default_answers, "", "while a read without the flag finds no pointer")
    assert_true(cleared, "and Use Default clears the flag's pointer")


## The same, through the flag this process really carries, which is what the
## Files page's folder row passes in on every scenario: no argument at all. A
## pointer already in the flag's folder is put back after, in case a run was
## started with a folder worth keeping.
func test_the_files_page_row_writes_the_flags_pointer_when_no_flag_is_handed() -> void:
    var flag_dir := SaDataRoot.flag()
    if flag_dir.is_empty():
        return
    var previous := OS.get_environment(_default_root_variable())
    var default_root := OS.get_temp_dir().path_join("sara-pointer-probe-4")
    OS.set_environment(_default_root_variable(), default_root)
    var flag_pointer := flag_dir.path_join(SaSettingsFile.LOCATION_FILE)
    var kept := SaSettingsFile.read_pointer()

    SaSettingsFile.set_pointer("/tmp/sara-another-settings-folder")
    var default_pointer := SaSettingsFile.platform_default().path_join(SaSettingsFile.LOCATION_FILE)
    var landed_in_default := FileAccess.file_exists(default_pointer)
    var pointed_at := SaSettingsFile.read_pointer()

    SaSettingsFile.set_pointer(kept)
    if previous.is_empty():
        OS.unset_environment(_default_root_variable())
    else:
        OS.set_environment(_default_root_variable(), previous)

    assert_eq(SaSettingsFile.pointer_path(), flag_pointer, "the pointer is in the flag's folder")
    assert_false(landed_in_default, "and the default root has no location.cfg")
    assert_eq(pointed_at, "/tmp/sara-another-settings-folder", "and the row's value reads back from there")


## The variable `SaSettingsFile.platform_default()` builds the default folder
## from. Setting the one this platform ignores would leave the probe in the
## painter's own settings folder.
func _default_root_variable() -> String:
    return "APPDATA" if OS.get_name() == "Windows" else "XDG_CONFIG_HOME"


# --- Layout overrides -------------------------------------------------------------


## The default order is a const shared by the whole process. Handing a caller
## the const itself would let one docker's reordering rewrite the defaults for
## every other, permanently, with nothing written to disk to explain it.
func test_the_default_order_cannot_be_mutated_through_the_getter() -> void:
    var before: int = SaSettings.DEFAULT_ORDERS["LayersDocker"].size()

    var order := SaSettings.get_layout_order("LayersDocker")
    order.append("Injected")

    assert_eq(SaSettings.DEFAULT_ORDERS["LayersDocker"].size(), before, "The const is not the thing handed out")
    assert_false("Injected" in SaSettings.get_layout_order("LayersDocker"), "and the next caller sees the real order")


## Edit holds undo and redo. Hiding it would take them out of the UI with no
## menu left to turn them back on, so both sides of the pair refuse.
func test_the_edit_menu_cannot_be_hidden() -> void:
    SaSettings.set_element_visible("TopMenuBar", "Edit", false)

    assert_true(SaSettings.get_element_visible("TopMenuBar", "Edit"), "Edit is visible whatever was asked for")


func test_an_element_nobody_configured_is_visible() -> void:
    assert_true(SaSettings.get_element_visible("LayersDocker", "Never Mentioned"), "Visible is the default")


## A module contributing a Preferences page has to be able to take it back,
## because the autoload outlives both the module and the test run.
func test_a_runtime_category_can_be_registered_and_taken_back() -> void:
    assert_true(SaSettings.register_layout_category("ProbeDocker", "Probe", ["Handle"]), "A fresh id is accepted")
    assert_false(SaSettings.get_layout_order("ProbeDocker").is_empty(), "Its elements are reachable")

    SaSettings.unregister_layout_category("ProbeDocker")

    assert_true(SaSettings.get_layout_order("ProbeDocker").is_empty(), "and gone again afterwards")


## A page registered for a holder goes when the holder is freed,
## which is how a `Main` a suite boots and frees takes its dockers' pages with
## it. The F1 search suite read Brush Presets twice after the boot cover suite,
## once as the docker and once as the page that suite's `Main` had left behind.
func test_a_runtime_category_goes_with_the_object_it_was_registered_for() -> void:
    var holder := Node.new()
    assert_true(SaSettings.register_layout_category("HeldProbeDocker", "Held Probe", ["Handle"], holder), "Accepted for a holder")
    assert_true(_has_category("HeldProbeDocker"), "and listed while the holder lives")
    assert_false(SaSettings.register_layout_category("HeldProbeDocker", "Again", ["Handle"]), "and its id is still taken")

    holder.free()

    assert_false(_has_category("HeldProbeDocker"), "Gone once the holder is freed")
    assert_true(SaSettings.register_layout_category("HeldProbeDocker", "Held Probe", ["Handle"]), "so the id is free again")
    SaSettings.unregister_layout_category("HeldProbeDocker")


func _has_category(category_id: String) -> bool:
    for category: Dictionary in SaSettings.reorderable_categories():
        if category["id"] == category_id:
            return true
    return false


func test_a_category_with_no_elements_is_refused() -> void:
    assert_false(SaSettings.register_layout_category("EmptyDocker", "Empty", []), "A page with nothing on it is not a page")
    assert_false(SaSettings.register_layout_category("", "Nameless", ["Handle"]), "and a category needs an id")


## F1: the empty menus were hidden until the phase that filled each arrived,
## Layer with F3, Filter with F7 and Select with F6, and a profile's own
## choice is not overruled either way.
func test_every_menu_is_shown_by_default_and_a_choice_wins() -> void:
    for menu: String in ["Select", "Filter", "Layer"]:
        assert_true(SaSettings.get_element_visible("TopMenuBar", menu), "%s is shown since the phase that filled it" % menu)
    assert_true(SaSettings.get_element_visible("TopMenuBar", "View"), "A populated menu is shown")
    SaSettings.set_element_visible("TopMenuBar", "Select", false)
    assert_false(SaSettings.get_element_visible("TopMenuBar", "Select"), "A profile that hides it keeps that")
    SaSettings.set_element_visible("TopMenuBar", "Select", true)
    SaSettings.config.erase_section_key("profile_visibility", "TopMenuBar_Select")
    SaSettings.save_settings()


## Newest first, no duplicates, capped, and it survives a reload.
func test_the_recent_list_keeps_the_newest_ten_once_each() -> void:
    var path := SaDataRoot.path("test_settings_recent.cfg")
    var previous_path: String = SaSettings.settings_path
    SaSettings.settings_path = path
    SaSettings.reset_to_defaults()
    assert_eq(SaSettings.recent_files(), [], "Empty to begin with")

    var announced: Array = []
    var listener := func() -> void: announced.append(true)
    SaSettings.recent_files_changed.connect(listener)
    for i in 12:
        SaSettings.add_recent_file("/paintings/%d.sad" % i)
    SaSettings.add_recent_file("/paintings/5.sad")
    SaSettings.recent_files_changed.disconnect(listener)

    var recent := SaSettings.recent_files()
    assert_eq(recent.size(), SaSettings.MAX_RECENT_FILES, "Capped")
    assert_eq(recent[0], "/paintings/5.sad", "The one opened again is first")
    assert_eq(recent[1], "/paintings/11.sad", "and the rest keep their order")
    assert_eq(recent.count("/paintings/5.sad"), 1, "once")
    assert_false(recent.has("/paintings/0.sad"), "The oldest fell off")
    assert_eq(announced.size(), 13, "Every change announced")

    SaSettings.remove_recent_file("/paintings/5.sad")
    assert_false(SaSettings.recent_files().has("/paintings/5.sad"), "A file that stopped opening is dropped")

    SaSettings.load_settings()
    assert_eq(SaSettings.recent_files()[0], "/paintings/11.sad", "The list is in the file")

    SaSettings.settings_path = previous_path
    SaSettings.load_settings()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## How many previous versions a save keeps, clamped and persisted.
func test_the_versions_count_is_clamped_and_reloads() -> void:
    var path := SaDataRoot.path("test_settings_versions.cfg")
    var previous_path: String = SaSettings.settings_path
    SaSettings.settings_path = path
    SaSettings.reset_to_defaults()
    assert_eq(SaSettings.sad_versions, 1, "One previous version by default")
    SaSettings.sad_versions = 40
    assert_eq(SaSettings.sad_versions, SaSettings.MAX_SAD_VERSIONS, "Clamped at the top")
    SaSettings.sad_versions = -3
    assert_eq(SaSettings.sad_versions, 0, "and at zero, which keeps none")
    SaSettings.sad_versions = 3
    SaSettings.load_settings()
    assert_eq(SaSettings.sad_versions, 3, "The count is in the file")

    SaSettings.settings_path = previous_path
    SaSettings.load_settings()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
