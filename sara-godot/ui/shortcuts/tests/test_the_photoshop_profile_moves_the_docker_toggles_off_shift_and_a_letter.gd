## The Photoshop profile moves the docker toggles off Shift and
## a letter, which Photoshop gives to stepping through a letter's tool group.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The profile is applied as Quick settings applies it, by a press of
## `SaComingFromRow` over a layout store of the suite's own on a scratch file,
## the way the other profile suites build one. The map is theirs, the two base modules
## through the door and the router's own chords on top, and the router is handed
## the four dockers whose toggle is an action of `project.godot` the way `Main`
## hands it the registered ones, so a press of F7 reaches the Layers docker by
## the road a painter's does.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A surface builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

const MODULES: Array[String] = [
    "res://modules/sara-base-modules/base/module.gd",
    "res://modules/sara-base-modules/stamp-brush/module.gd",
]

const SCRATCH := "test_u507_shortcut_profiles"
static var scratch_layout_path: String = SaDataRoot.path("test_u507_layout.cfg")

## The three dockers that take Photoshop's own panel keys.
const PANEL_KEYS: Dictionary[StringName, String] = {
    &"docker_layers": "F7",
    &"docker_color_selector": "F6",
    &"info_docker": "F8",
}

var _saved_events: Dictionary = {}
var _saved := {}

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _machine: ToolMachine = null
var _router: ShortcutRouter = null
var _root: Node = null
var _store: DockerLayoutStore = null
var _row: SaComingFromRow = null
var _saved_layout_state := ConfigFile.new()
## What the two docker doors were handed, an id or a row's shortcut action.
var _toggled: Array = []


func before_each() -> void:
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    for key: String in ["shortcuts_profile", "theme_name", "color_picker_shape", "reset_zoom"]:
        _saved[key] = SaSettings.get(key)
    SaShortcutStore.dir_override = SaDataRoot.path(SCRATCH)
    SaShortcutStore.capture_defaults()
    SaSettings.shortcuts_profile = SaShortcutStore.DEFAULT_PROFILE

    _toggled.clear()
    _surface = Fixtures.make_surface()
    _registries = Fixtures.make_registries(_surface)
    _modules.clear()
    for path: String in MODULES:
        var module: SaModule = load(path).new()
        module.register(_registries.context.for_module(module.get_id()))
        _modules.append(module)
    SaAppCommands.register_all(_registries, func(docker_id: StringName) -> void: _toggled.append(docker_id))
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    _machine = Fixtures.make_bound_machine(_surface)
    _router = ShortcutRouter.new()
    _router.canvas_provider = func() -> SaCanvas: return null
    _router.tool_machine_provider = func() -> ToolMachine: return _machine
    _router.bind_commands(_registries.commands)
    var rows: Array = []
    for entry: Array in SaAppCommands.OLDER_DOCKERS:
        rows.append({"id": String(entry[1]), "shortcut": String(entry[0])})
    _router.dockers_provider = func() -> Array: return rows
    _router.toggle_docker = func(index: int) -> void: _toggled.append(StringName(rows[index]["shortcut"]))

    _root = Node.new()
    _root.name = "U507Host"
    EventBus.add_child(_root)
    var docker := Window.new()
    docker.size = Vector2i(200, 150)
    _root.add_child(docker)
    docker.visible = false
    _store = DockerLayoutStore.new()
    _store.path = scratch_layout_path
    _store.dockers_provider = func() -> Array: return [{"id": "ProbeDocker", "name": "Probe", "node": docker}]
    _store.save_allowed = func() -> bool: return true
    _saved_layout_state = ConfigFile.new()
    _store.presets().capture(_saved_layout_state)
    _row = SaComingFromRow.new(_store)


func after_each() -> void:
    _row.free()
    _store.presets().apply(_saved_layout_state)
    _store.free()
    _root.free()
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    for module: SaModule in _modules:
        module.unregister(_registries.context)
    _modules.clear()
    Fixtures.teardown(_surface, _machine)
    _router.free()
    _router = null
    _machine = null
    _registries = null
    _surface = null

    for action: StringName in InputMap.get_actions():
        if not _saved_events.has(action):
            InputMap.erase_action(action)
    for action: StringName in _saved_events:
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)
    for key: String in _saved:
        SaSettings.set(key, _saved[key])
    EventBus.shortcuts_changed.emit()
    SaShortcutStore.dir_override = ""
    DirAccess.remove_absolute(scratch_layout_path)


## Every docker toggle, the rows registered here and the four of `project.godot`.
func _toggles() -> Array[StringName]:
    var out: Array[StringName] = []
    for entry: Array in SaAppCommands.DOCKER_COMMANDS + SaAppCommands.OLDER_DOCKERS:
        out.append(entry[0])
    return out


## The docker toggles holding a chord of Shift and one letter, "action on chord".
func _on_shift_and_a_letter() -> Array[String]:
    var out: Array[String] = []
    for action: StringName in _toggles():
        for event: InputEvent in InputMap.action_get_events(action):
            var key := event as InputEventKey
            if key == null or not key.shift_pressed or key.ctrl_pressed or key.alt_pressed or key.meta_pressed:
                continue
            var code := key.keycode if key.keycode != KEY_NONE else key.physical_keycode
            if code >= KEY_A and code <= KEY_Z:
                out.append("%s on %s" % [action, SaShortcutStore.chord_text(key)])
    return out


func _press(keycode: Key, shift: bool) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.shift_pressed = shift
    event.pressed = true
    return event


## The chords every toggle holds now, toggle -> its chord texts.
func _chords_now() -> Dictionary:
    var out := {}
    for action: StringName in _toggles():
        out[action] = SaShortcutStore.chords_for(action)
    return out


func test_photoshop_leaves_no_toggle_on_shift_and_a_letter_and_gives_three_their_f_keys() -> void:
    var repeat := SaShortcutStore.holders("Shift+R")
    var fill := SaShortcutStore.holders("Shift+G")
    assert_true(fill.has("tool_family_gradient"), "Sara's own map has the fill family step on Shift+G (%s)" % [fill])
    _row.press("photoshop")
    assert_eq(SaSettings.shortcuts_profile, "Photoshop", "Quick settings put the Photoshop profile in force")
    assert_eq(_on_shift_and_a_letter(), [] as Array[String], "no docker toggle holds Shift and one letter")
    for action: StringName in PANEL_KEYS:
        assert_eq(SaShortcutStore.chords_for(action), [PANEL_KEYS[action]] as Array[String], "%s is on its F key" % action)
        assert_eq(SaShortcutStore.holders(PANEL_KEYS[action]), [String(action)] as Array[String], "and alone there")
    assert_eq(SaShortcutStore.holders("Shift+R"), repeat, "Shift+R is held as it was, Repeat Last's where it is registered")
    assert_eq(SaShortcutStore.holders("Shift+G"), fill, "Shift+G is still the fill family step")
    assert_eq(SaShortcutStore.holders("F5"), ["edit_brush"] as Array[String], "F5 stays Edit Brush Settings")


func test_sara_and_krita_keep_the_dockers_where_they_were() -> void:
    var sara := _chords_now()
    assert_eq(sara[&"docker_layers"], ["Shift+T"] as Array[String], "Sara's own map has the layers on Shift+T")
    assert_eq(sara[&"info_docker"], ["F9"] as Array[String], "and Info on F9")
    _row.press("krita")
    var krita := _chords_now()
    for action: StringName in _toggles():
        var want: Array = sara[action]
        if action == &"docker_tool_options":
            want = ["BackSlash"]
        elif action == &"docker_color_selector":
            want = ["Shift+I"]
        elif action == &"docker_palette":
            want = []  # Shift+W is Krita's Wrap Around Mode
        assert_eq(krita[action], want, "Krita keeps %s where it was" % action)
    _row.press("photoshop")
    _row.press("photoshop")
    assert_eq(_chords_now(), sara, "Sara's own map gives every toggle back after Photoshop is pressed again")


func test_f7_toggles_the_layers_under_photoshop_and_shift_t_does_nothing() -> void:
    _row.press("photoshop")
    _toggled.clear()
    assert_eq(_router._answer(_press(KEY_SHIFT, false)), &"", "a bare Shift is nobody's")
    assert_eq(_router._answer(_press(KEY_T, true)), &"", "Shift+T answers nothing under Photoshop")
    assert_eq(_toggled, [], "and toggles no docker")
    assert_eq(_router._answer(_press(KEY_F7, false)), &"docker_layers", "F7 is the Layers toggle")
    assert_eq(_toggled, [&"docker_layers"], "which asks for the Layers docker alone")
    _toggled.clear()
    assert_eq(_router._answer(_press(KEY_F6, false)), &"docker_color_selector", "F6 is the Colour Picker's")
    assert_eq(_router._answer(_press(KEY_F8, false)), &"info_docker", "F8 is the Info docker's")
    assert_eq(_toggled, [&"docker_color_selector", &"info_docker"], "each asking for its own docker")
    _row.press("photoshop")
    _toggled.clear()
    assert_eq(_router._answer(_press(KEY_T, true)), &"docker_layers", "back in Sara's own map Shift+T is the layers again")
    assert_eq(_router._answer(_press(KEY_F7, false)), &"", "and F7 nobody's")
