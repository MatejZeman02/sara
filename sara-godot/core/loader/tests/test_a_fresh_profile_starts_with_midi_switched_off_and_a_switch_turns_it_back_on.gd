## A fresh profile leaves out the modules the build ships switched off, and the
## painter's switch brings one back at the next start.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter, on 2026-11-03: "some of the modules should not be on by default,
## like the MIDI one." A settings object of the autoload's class is read over a
## scratch profile that does not exist yet, the way a first launch reads one,
## and the loader is started on what it holds, as a start is. MIDI's switch is
## then written the way the modules page writes it, the profile is read again
## by a second settings object, the next start, and the loader started on that.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const SETTINGS := "res://core/settings/sa_settings.gd"

static var scratch_path: String = SaDataRoot.path("test_off_by_default/settings.cfg")

var _made: Array[Node] = []
var _registries: SaRegistries


func before_each() -> void:
    _clear()
    _registries = SaRegistries.new()
    _registries.build_context(func() -> Variant: return null, func() -> Array: return [])


func after_each() -> void:
    ModuleLoader.unload_all()
    for node: Node in _made:
        if is_instance_valid(node):
            node.free()
    _made.clear()
    _registries = null
    _clear()


func _clear() -> void:
    var path := ProjectSettings.globalize_path(scratch_path)
    for suffix: String in ["", ".bak", ".tmp", ".broken"]:
        DirAccess.remove_absolute(path + suffix)


## A start's settings: an object of the autoload's class reading the scratch
## profile, whatever it holds by now.
func _start_settings() -> Node:
    var path := ProjectSettings.globalize_path(scratch_path)
    DirAccess.make_dir_recursive_absolute(path.get_base_dir())
    var settings: Node = load(SETTINGS).new()
    settings.settings_path = path
    settings.load_settings()
    _made.append(settings)
    return settings


## The loader started on what *settings* holds, the way a start passes it.
func _start_modules(settings: Node) -> void:
    ModuleLoader.unload_all()
    ModuleLoader.verbose = false
    ModuleLoader.load_and_register_modules(_registries.context, settings.modules_off)
    ModuleLoader.verbose = true


func test_the_list_names_midi_and_never_the_skeleton() -> void:
    assert_true(SaOffByDefault.IDS.has("midi"), "MIDI is on the build's list")
    assert_false(SaOffByDefault.IDS.has(String(SaSwitchedOff.SKELETON)), "and the skeleton is not")
    var copy := SaOffByDefault.ids()
    copy.append("probe")
    assert_false(SaOffByDefault.IDS.has("probe"), "A caller's copy is not the build's list")


func test_a_fresh_profile_loads_every_listed_module_as_switched_off() -> void:
    var settings := _start_settings()
    assert_eq(settings.modules_off, SaOffByDefault.ids(), "A first launch holds the build's list")
    _start_modules(settings)
    for module_id: String in SaOffByDefault.IDS:
        assert_eq(
            ModuleLoader.off_modules.get(StringName(module_id), ""),
            SaSwitchedOff.SWITCHED_OFF,
            "%s is loaded as switched off on a fresh profile" % module_id
        )
        assert_false(ModuleLoader.loaded_modules.has(StringName(module_id)), "and %s registered nothing" % module_id)
        assert_eq(
            ModuleLoader.module_names.get(StringName(module_id), ""),
            ModuleLoader.manifest_of(StringName(module_id)).name,
            "and the modules page still has its name to show beside the switch"
        )


func test_a_module_whose_manifest_names_it_off_has_its_script_left_unread() -> void:
    var settings := _start_settings()
    var paths := ModuleLoader.packaged_script_paths()
    var midi_script := ""
    for script_path: String in paths:
        if SaModuleManifest.read(script_path.get_base_dir()).id == &"midi":
            midi_script = script_path
    assert_false(midi_script.is_empty(), "MIDI ships a module script")
    var wanted := SaSwitchedOff.wanted_scripts(paths, settings.modules_off)
    assert_false(wanted.has(midi_script), "The start does not compile the script of a module it leaves out")
    assert_eq(wanted.size(), paths.size() - SaOffByDefault.IDS.size(), "and compiles every other packaged module's")


func test_switching_midi_on_loads_it_at_the_next_start() -> void:
    var first := _start_settings()
    # What the modules page's switch writes when it is turned on.
    var off: Array = first.modules_off.duplicate()
    off.erase("midi")
    first.modules_off = off

    var second := _start_settings()
    assert_false(second.modules_off.has("midi"), "The next start's profile holds MIDI switched on")
    _start_modules(second)
    assert_true(ModuleLoader.loaded_modules.has(&"midi"), "and MIDI loads")
    assert_false(ModuleLoader.off_modules.has(&"midi"), "and is not among the modules left out")
