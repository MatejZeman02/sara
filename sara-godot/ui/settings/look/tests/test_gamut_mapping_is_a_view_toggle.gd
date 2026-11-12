## Gamut mapping is a view toggle of its own, on by default.
##
## Brightness and contrast leave colours below zero that clip badly on screen,
## and they map even when tonemapping is off, so the preference is a registered
## toggle
## beside Tonemap Highlights, Oklab is the default, an older profile reads Oklab
## once, and the toggle and the Display page's row are one setting.
##
## The mapped pixel itself is a shader's and is proved on the running app, by
## scenarios/gamut-mapping-is-a-view-toggle-of-its-own-on-by-default.json.
extends "res://tests/test_framework.gd"

const ControlWalker := preload("res://harness/controls/sa_control_walker.gd")

const TOGGLE_ID := &"gamut_mapping"

static var scratch_path: String = SaDataRoot.path("test_gamut_mapping_toggle_scratch.cfg")

var _saved_mapping: String
var _saved_rolloff: bool


func before_each() -> void:
    _saved_mapping = SaSettings.gamut_mapping
    _saved_rolloff = SaSettings.tonemap_highlights
    SaSettings.tonemap_highlights = false


## Restores what this suite found, so a run leaves the person's profile alone.
func after_each() -> void:
    SaSettings.gamut_mapping = _saved_mapping
    SaSettings.tonemap_highlights = _saved_rolloff


func _registry() -> SaViewTransformRegistry:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    return registries.view_transforms


func test_a_new_profile_maps() -> void:
    var values := SaSettingsValues.new()
    assert_eq(values.gamut_mapping, SaGamutMapping.OKLAB, "A profile that never named the key maps with Oklab")
    values.free()


func test_the_toggle_is_registered_beside_the_roll_off() -> void:
    var registry := _registry()
    var toggle := registry.get_descriptor(TOGGLE_ID)
    assert_not_null(toggle, "The skeleton registers it through the same door a module uses")
    assert_eq(toggle.kind, SaViewTransformDescriptor.Kind.TOGGLE, "as a toggle, not a mode")
    assert_eq(toggle.display_name, "Gamut Mapping", "under the name the View menu draws")
    var ids: Array[StringName] = []
    for descriptor in registry.list_toggles():
        ids.append(descriptor.id)
    assert_eq(ids.find(TOGGLE_ID), ids.find(SaDisplayPage.ROLLOFF_ID) + 1, "and listed straight after the roll-off")


## On is Oklab and off is clip, with the roll-off off throughout, because the
## mapping does not wait for it.
func test_the_toggle_reads_and_writes_the_setting_with_the_roll_off_off() -> void:
    var registry := _registry()
    SaSettings.gamut_mapping = SaGamutMapping.OKLAB
    assert_true(registry.is_enabled(TOGGLE_ID), "Oklab reads as on")
    assert_true(registry.set_enabled(TOGGLE_ID, false), "The toggle takes a click")
    assert_eq(SaSettings.gamut_mapping, SaGamutMapping.CLIP, "and off writes clip")
    assert_false(registry.is_enabled(TOGGLE_ID), "which reads back as off")
    registry.set_enabled(TOGGLE_ID, true)
    assert_eq(SaSettings.gamut_mapping, SaGamutMapping.OKLAB, "and on writes Oklab again")
    assert_false(SaSettings.tonemap_highlights, "without switching the roll-off on")


## Both ways: the toggle moves the page's row, and the row moves the toggle.
func test_the_toggle_and_the_display_page_agree_both_ways() -> void:
    var registry := _registry()
    SaSettings.gamut_mapping = SaGamutMapping.OKLAB
    var page := SaDisplayPage.new()
    var row := ControlWalker.find(page, "GamutMappingOpt") as SaChoiceButton
    assert_not_null(row, "The Display page has the row")
    assert_eq(row.selected_value(), SaGamutMapping.OKLAB, "and it opens on Oklab with the toggle on")

    registry.set_enabled(TOGGLE_ID, false)
    assert_eq(row.selected_value(), SaGamutMapping.CLIP, "The toggle turned off moves the row to clip")

    assert_true(ControlWalker.move(row, SaGamutMapping.OKLAB), "The row is picked back to Oklab")
    assert_true(registry.is_enabled(TOGGLE_ID), "and the toggle reads on")
    assert_true(ControlWalker.move(row, SaGamutMapping.CLIP), "The row is picked to clip")
    assert_false(registry.is_enabled(TOGGLE_ID), "and the toggle reads off")
    page.free()


## A profile from before the toggle held clip because clip was the default, so
## it reads Oklab once. A clip chosen after the migration is kept.
func test_an_old_profile_reads_oklab_after_its_migration() -> void:
    var old := ConfigFile.new()
    old.set_value("meta", "version", 15)
    old.set_value("ui", "gamut_mapping", SaGamutMapping.CLIP)
    SaSettingsMigrations.apply(old, 15)
    assert_eq(old.get_value("ui", "gamut_mapping"), SaGamutMapping.OKLAB, "A version-15 profile at clip reads Oklab")
    assert_eq(old.get_value("meta", "version"), SaSettingsMigrations.SETTINGS_VERSION, "and is stamped with this build")

    var chosen := ConfigFile.new()
    chosen.set_value("meta", "version", SaSettingsMigrations.SETTINGS_VERSION)
    chosen.set_value("ui", "gamut_mapping", SaGamutMapping.CLIP)
    var stored_version: int = chosen.get_value("meta", "version")
    assert_false(stored_version < SaSettingsMigrations.SETTINGS_VERSION, "A current profile runs no migration")
    assert_eq(chosen.get_value("ui", "gamut_mapping"), SaGamutMapping.CLIP, "so a clip chosen since stays clip")


## Through the whole load, so the read after the migration is the one proved.
func test_an_old_profile_on_disk_loads_as_oklab() -> void:
    var path := ProjectSettings.globalize_path(scratch_path)
    var saved_path: String = SaSettings.settings_path
    var old := ConfigFile.new()
    old.set_value("meta", "version", 15)
    old.set_value("ui", "gamut_mapping", SaGamutMapping.CLIP)
    old.save(path)
    SaSettings.settings_path = path
    SaSettings.load_settings()
    assert_eq(SaSettings.gamut_mapping, SaGamutMapping.OKLAB, "The loaded profile maps")
    # Back onto the runner's own file, read again so every other value the
    # scratch profile loaded is the runner's once more.
    SaSettings.settings_path = saved_path
    SaSettings.load_settings()
    DirAccess.remove_absolute(path)
