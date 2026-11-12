## MIDI becomes a module of its own.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter on 2026-10-14: "Submodules and modules: MIDI should be a separate
## module, Others could stay in/moved to base-modules." The package `ui/midi`
## is this folder now, loaded as any module is, and Listen and the bindings left
## the skeleton's settings for the module's own preferences under
## `module.midi`.
##
## A profile in the shape a painter's had before the move, `[input]` holding
## `midi_listen` and a binding, is loaded by a settings object of the
## autoload's class and read through the module's preferences: both are there,
## a control change on the bound control moves the slider it names, and the
## profile saved again has both under `module.midi` and neither under `input`.
## Then the module through a scoped context, its page, its command and its
## source, and the skeleton without it, which offers neither. Last, the grep the
## row's last clause asks for.
extends "res://tests/test_framework.gd"

const Midi := preload("res://modules/sara-base-modules/midi/midi.gd")
const MidiModule := preload("res://modules/sara-base-modules/midi/module.gd")

## The settings autoload's script, a fresh object of which reads the scratch
## profile as the app reads the painter's.
const SETTINGS := "res://core/settings/sa_settings.gd"

## The device the old profile's binding is on, and the value its control 7 on
## channel 1 drives, which a slider of the suite's own carries.
const DEVICE := "Probe Mixer"
const VALUE_NAME := &"probe/probe"

## The words the row's grep looks for in the skeleton's GDScript.
const WORDS: Array[String] = ["SaMidi", "midi_listen", "midi_bindings", "InputEventMIDI", "ui/midi"]

## A profile written before the move, the shape `tests/data/every_key_moved.cfg`
## keeps, with only the two keys the module takes over.
const OLD_PROFILE := (
    '[meta]\n\nversion=%d\n\n[input]\n\nmidi_listen=true\nmidi_bindings={\n"Probe Mixer": {\n'
    + '"control/0/7": {\n"kind": "dial",\n"label": "Probe",\n"target": "probe/probe"\n}\n}\n}\n'
)

static var scratch_path: String = SaDataRoot.path("test_midi_profile.cfg")

var _made: Array[Node] = []


func before_each() -> void:
    _clear()


func after_each() -> void:
    for node: Node in _made:
        if is_instance_valid(node):
            if node.is_inside_tree():
                node.get_parent().remove_child(node)
            node.free()
    _made.clear()
    _clear()


func _clear() -> void:
    var path := ProjectSettings.globalize_path(scratch_path)
    for suffix: String in ["", ".bak", ".tmp", ".broken"]:
        DirAccess.remove_absolute(path + suffix)


## A settings object of the autoload's class over the scratch profile, written
## in the old shape first.
func _settings_over_old_profile() -> Node:
    var path := ProjectSettings.globalize_path(scratch_path)
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(OLD_PROFILE % SaSettingsFile.SETTINGS_VERSION)
    file.close()
    var settings: Node = load(SETTINGS).new()
    settings.settings_path = path
    settings.load_settings()
    _made.append(settings)
    return settings


## The module's preferences in *settings*, read and written as the context
## reads and writes them for the module whose id is `midi`.
static func _preferences(settings: Node) -> Midi.Preferences:
    return Midi.Preferences.new(
        func(key: StringName, default: Variant, formerly: Array) -> Variant:
            return settings.module_preference(Midi.MODULE_ID, key, default, formerly),
        func(key: StringName, value: Variant) -> void: settings.set_module_preference(Midi.MODULE_ID, key, value)
    )


func _profile_on_disk() -> ConfigFile:
    var written := ConfigFile.new()
    assert_eq(written.load(ProjectSettings.globalize_path(scratch_path)), OK, "the saved profile parses")
    return written


## The Done when's first clause, whole.
func test_an_old_profiles_listen_and_binding_become_the_modules_and_drive_a_slider() -> void:
    var settings := _settings_over_old_profile()
    var before := _profile_on_disk()
    assert_true(before.has_section_key("input", "midi_listen"), "The skeleton's load kept the key it no longer lists")
    assert_true(before.has_section_key("input", "midi_bindings"), "and the bindings beside it, for the module to read")

    var kept := _preferences(settings)
    kept.adopt()
    assert_true(kept.listen, "The module's Listen reads the old profile's")
    assert_eq(
        kept.bindings,
        {DEVICE: {"control/0/7": {"kind": "dial", "label": "Probe", "target": String(VALUE_NAME)}}},
        "and its bindings the old profile's binding"
    )

    var host := Node.new()
    host.name = "U125Host"
    _made.append(host)
    EventBus.add_child(host)
    var slider := FactorSlider.new()
    slider.value_name = VALUE_NAME
    slider.min_value = 0.0
    slider.max_value = 100.0
    slider.value = 0.0
    host.add_child(slider)
    var bindings := Midi.Bindings.new(kept, SaAppDrive.new(Callable()))
    assert_true(bindings.drive_control(DEVICE, 0, 7, 64), "A control change on the bound control is taken")
    bindings.flush()
    assert_almost_eq(
        slider.value,
        lerpf(slider.drag_min(), slider.drag_max(), 64.0 / 127.0),
        slider.step,
        "and moves the slider it names, to its step"
    )

    settings.save_settings()
    var after := _profile_on_disk()
    assert_true(bool(after.get_value("module.midi", "listen", false)), "Saved again, Listen is under module.midi")
    assert_eq(
        after.get_value("module.midi", "bindings", {}),
        {DEVICE: {"control/0/7": {"kind": "dial", "label": "Probe", "target": String(VALUE_NAME)}}},
        "and so is the binding"
    )
    assert_false(after.has_section_key("input", "midi_listen"), "and neither is under input any more")
    assert_false(after.has_section_key("input", "midi_bindings"), "the bindings included")


## A profile that already has the module's own value keeps it over an old key.
func test_the_modules_own_value_wins_over_an_old_key_left_beside_it() -> void:
    var settings := _settings_over_old_profile()
    settings.set_module_preference(Midi.MODULE_ID, Midi.Preferences.LISTEN, false)
    var kept := _preferences(settings)
    assert_false(kept.listen, "The module's own value is the one read")
    assert_false(_profile_on_disk().has_section_key("input", "midi_listen"), "and the old key is gone after the read")


func test_the_module_registers_its_page_command_and_source_and_takes_them_away() -> void:
    var values := SaSettingsValues.new()
    var registries := SaRegistries.new()
    registries.input_sources = SaInputSourceRegistry.new(values)
    registries.build_context(Callable(), Callable())
    var module: SaModule = MidiModule.new()
    assert_eq(module.get_id(), &"midi", "The module's id is midi")
    var scoped := registries.context.for_module(module.get_id())
    module.register(scoped)
    var source := registries.input_sources.source_of(Midi.SOURCE_ID)
    assert_not_null(source, "It registers the source the midi step asks")
    assert_eq(source.settings, [&"midi/listen"] as Array[StringName], "which follows its own Listen")
    assert_true(registries.ui.has_settings_page(Midi.PAGE_ID), "Preferences > MIDI comes in through the door")
    var page: Dictionary = {}
    for entry: Dictionary in registries.ui.list_settings_pages():
        if StringName(entry["id"]) == Midi.PAGE_ID:
            page = entry
    assert_eq(String(page.get("title", "")), "MIDI", "under the title the scenarios open it by")
    assert_eq(StringName(page.get("group", &"")), &"painting", "in Painting")
    assert_eq(StringName(page.get("module", &"")), &"midi", "held for the module")
    assert_true(registries.commands.has(Midi.MAP_COMMAND), "and Map to MIDI is a command")
    module.unregister(scoped)
    scoped.remove_all_registrations()
    assert_null(Midi.app, "Unloading lets the app's facade go")
    assert_null(registries.input_sources.source_of(Midi.SOURCE_ID), "and takes the source")
    assert_false(registries.ui.has_settings_page(Midi.PAGE_ID), "and the page")
    assert_false(registries.commands.has(Midi.MAP_COMMAND), "and the command")
    values.free()


## The Done when's third clause: with the module not loaded the skeleton
## registers no MIDI page and no Map to MIDI.
func test_the_skeleton_without_the_module_has_no_midi_page_and_no_map_to_midi() -> void:
    var registries := SaRegistries.new()
    registries.build_context(Callable(), Callable())
    registries.register_builtins()
    SaBuiltinPages.register_builtins(registries.ui)
    SaAppCommands.register_all(registries, Callable())
    assert_false(registries.ui.list_settings_pages().is_empty(), "The skeleton's own pages are registered")
    assert_false(registries.ui.has_settings_page(Midi.PAGE_ID), "and no MIDI page among them")
    assert_false(registries.commands.has(Midi.MAP_COMMAND), "and Map to MIDI is not one of them")
    assert_null(registries.input_sources.source_of(Midi.SOURCE_ID), "nor is there a midi source")


## The Done when's last clause: the GDScript of `core`, `ui` and `harness`
## names none of the five.
func test_the_skeleton_names_nothing_of_midi() -> void:
    var found: Array[String] = []
    for top: String in ["res://core", "res://ui", "res://harness"]:
        for path: String in _scripts_under(top):
            var text := FileAccess.get_file_as_string(path)
            for word: String in WORDS:
                if text.contains(word):
                    found.append("%s names %s" % [path, word])
    assert_eq(found, [] as Array[String], "The skeleton names nothing of MIDI's")
    assert_false(DirAccess.dir_exists_absolute("res://ui/midi"), "and ui/midi is gone")


func _scripts_under(dir_path: String) -> Array[String]:
    var found: Array[String] = []
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return found
    for file: String in dir.get_files():
        if file.ends_with(".gd"):
            found.append(dir_path.path_join(file))
    for sub: String in dir.get_directories():
        if not sub.begins_with("."):
            found.append_array(_scripts_under(dir_path.path_join(sub)))
    return found
