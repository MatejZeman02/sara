## A module keeps its own preferences: two calls on
## `SaContext`, a section of `settings.cfg` named for the module, and the one
## migration that moved the gradient's two endpoint alphas into the base
## module's section.
##
## Every test here points `SaSettings` at a scratch file and puts the run's
## own profile back afterwards, by path and by a fresh load, because the
## autoload's values are what the suites after this one read.
extends "res://tests/test_framework.gd"

const FIXTURE_MODULE = preload("res://tests/fixtures/modules/preference-fixture/module.gd")
static var scratch_path: String = SaDataRoot.path("test_x5_module_preferences.cfg")
const BASE_MODULE_ID := &"sara-base-modules"

var _saved_path: String
var _heard: Array[StringName] = []


func before_each() -> void:
    _saved_path = SaSettings.settings_path
    _heard.clear()
    DirAccess.remove_absolute(_scratch())


func after_each() -> void:
    if SaSettings.changed.is_connected(_on_changed):
        SaSettings.changed.disconnect(_on_changed)
    SaSettings.settings_path = _saved_path
    SaSettings.config = ConfigFile.new()
    SaSettings.load_settings()
    DirAccess.remove_absolute(_scratch())
    DirAccess.remove_absolute(_scratch() + SaSettings.BACKUP_SUFFIX)


func _scratch() -> String:
    return ProjectSettings.globalize_path(scratch_path)


func _on_changed(property: StringName) -> void:
    _heard.append(property)


## The profile *text* describes, loaded as a launch would load it.
func _launch_on(text: String) -> void:
    var file := FileAccess.open(_scratch(), FileAccess.WRITE)
    file.store_string(text)
    file.close()
    SaSettings.config = ConfigFile.new()
    SaSettings.settings_path = _scratch()
    SaSettings.load_settings()


## A second launch against the file the first one left.
func _relaunch() -> void:
    SaSettings.config = ConfigFile.new()
    SaSettings.load_settings()


func _registries() -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    return registries


## The requirement, over a hand-written file: a profile an older build
## wrote with a start alpha of 0.25 opens after the merge with the near end of a
## fresh gradient at the same alpha.
func test_a_profile_from_before_the_move_keeps_its_gradient_alphas() -> void:
    _launch_on("[meta]\nversion=14\n\n[tools]\ngradient_start_alpha=0.25\ngradient_end_alpha=0.5\nselection_feather=0.02\n")

    var context := SaContext.new(Callable(), Callable(), BASE_MODULE_ID)
    var ends := SaGradientEnds.new(context)
    var ramp := ends.fresh_ramp(Color.RED, Color.BLUE)
    assert_almost_eq(ramp.color_of(0).a, 0.25, 1e-6, "The near end of a fresh gradient opens at the remembered alpha")
    assert_almost_eq(ramp.color_of(1).a, 0.5, 1e-6, "and the far end at its own")

    var section := SaSettingsFile.module_section(BASE_MODULE_ID)
    assert_eq(section, "module.sara-base-modules", "The base module's section is named for it")
    var written := ConfigFile.new()
    assert_eq(written.load(_scratch()), OK, "The migrated profile was saved")
    assert_almost_eq(float(written.get_value(section, "gradient_start_alpha", -1.0)), 0.25, 1e-6, "The value moved on disk")
    assert_false(written.has_section_key("tools", "gradient_start_alpha"), "and the old start key is gone")
    assert_false(written.has_section_key("tools", "gradient_end_alpha"), "and so is the old end key")
    assert_almost_eq(
        float(written.get_value("tools", "selection_feather", -1.0)), 0.02, 1e-6, "while the skeleton's own keys stay"
    )
    assert_eq(int(written.get_value("meta", "version", 0)), SaSettings.SETTINGS_VERSION, "and the file is stamped current")


## A profile that never faded an end has nothing to move, and the migration
## makes no section out of nothing.
func test_a_profile_with_no_gradient_alphas_gains_no_module_section() -> void:
    _launch_on("[meta]\nversion=14\n\n[tools]\nselection_feather=0.02\n")

    assert_false(SaSettings.config.has_section(SaSettingsFile.module_section(BASE_MODULE_ID)), "No section is invented")
    var ends := SaGradientEnds.new(SaContext.new(Callable(), Callable(), BASE_MODULE_ID))
    assert_almost_eq(ends.start_alpha(), 1.0, 1e-6, "and a fresh gradient opens opaque, as before")


## The fixture clause: a module writes a value and reads it back across a reload
## of the settings, through the two calls and nothing of the skeleton's.
func test_a_fixture_module_remembers_a_value_across_a_reload() -> void:
    _launch_on("[meta]\nversion=%d\n" % SaSettings.SETTINGS_VERSION)
    var module: SaModule = FIXTURE_MODULE.new()
    var registries := _registries()
    module.register(registries.context.for_module(module.get_id()))

    assert_eq(module.recalled("none"), "none", "Nothing is remembered before the module writes")
    module.remember("wombat")
    _relaunch()

    assert_eq(module.recalled("none"), "wombat", "The value comes back after the settings are read from disk again")
    var written := ConfigFile.new()
    written.load(_scratch())
    assert_eq(
        written.get_value("module.preference-fixture", "favourite_marsupial", ""), "wombat", "under the module's own section"
    )


## Any Variant a `ConfigFile` holds, not only a number.
func test_a_preference_can_be_any_value_a_config_file_holds() -> void:
    _launch_on("[meta]\nversion=%d\n" % SaSettings.SETTINGS_VERSION)
    var context := SaContext.new(Callable(), Callable(), &"preference-fixture")
    context.set_preference(&"list", [1, "two", 3.0])
    context.set_preference(&"colour", Color(0.1, 0.2, 0.3, 0.4))
    context.set_preference(&"sizes", {"small": Vector2i(8, 8)})
    _relaunch()

    assert_eq(context.preference(&"list"), [1, "two", 3.0], "An array comes back")
    assert_eq(context.preference(&"colour"), Color(0.1, 0.2, 0.3, 0.4), "and a colour")
    assert_eq(context.preference(&"sizes"), {"small": Vector2i(8, 8)}, "and a dictionary")


## Two modules may use one key and never read each other's value.
func test_two_modules_keep_one_key_apart() -> void:
    _launch_on("[meta]\nversion=%d\n" % SaSettings.SETTINGS_VERSION)
    var first := SaContext.new(Callable(), Callable(), &"first-module")
    var second := SaContext.new(Callable(), Callable(), &"second-module")
    first.set_preference(&"size", 1)
    second.set_preference(&"size", 2)

    assert_eq(first.preference(&"size"), 1, "The first module reads its own")
    assert_eq(second.preference(&"size"), 2, "and the second its own")


## The write announces itself as the module id, a slash and the key, once, and
## a write of the value already stored announces nothing.
func test_a_write_is_announced_by_module_and_key() -> void:
    _launch_on("[meta]\nversion=%d\n" % SaSettings.SETTINGS_VERSION)
    SaSettings.changed.connect(_on_changed)
    var context := SaContext.new(Callable(), Callable(), &"preference-fixture")
    context.set_preference(&"size", 3)
    context.set_preference(&"size", 3)

    assert_eq(_heard, [&"preference-fixture/size"] as Array[StringName], "One announcement, named module/key")


## A null forgets the key, and forgetting one that was never written is a no-op
## rather than the error `erase_section_key` gives.
func test_a_null_forgets_a_preference() -> void:
    _launch_on("[meta]\nversion=%d\n" % SaSettings.SETTINGS_VERSION)
    var context := SaContext.new(Callable(), Callable(), &"preference-fixture")
    context.set_preference(&"never", null)
    context.set_preference(&"size", 3)
    context.set_preference(&"size", null)
    _relaunch()

    assert_eq(context.preference(&"size", "gone"), "gone", "The key is forgotten on disk")


## A reset of the profile forgets every module's preferences with the rest.
func test_a_reset_clears_every_module_section() -> void:
    _launch_on("[meta]\nversion=%d\n" % SaSettings.SETTINGS_VERSION)
    SaContext.new(Callable(), Callable(), &"first-module").set_preference(&"size", 1)
    SaContext.new(Callable(), Callable(), BASE_MODULE_ID).set_preference(SaGradientEnds.END_ALPHA_KEY, 0.0)

    SaSettings.reset_to_defaults()

    for section: String in SaSettings.config.get_sections():
        assert_false(section.begins_with(SaSettingsFile.MODULE_SECTION_PREFIX), "'%s' survived the reset" % section)
    var ends := SaGradientEnds.new(SaContext.new(Callable(), Callable(), BASE_MODULE_ID))
    assert_almost_eq(ends.end_alpha(), 1.0, 1e-6, "and a fresh gradient opens opaque again")
