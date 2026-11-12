## Repeat Last repeats every command a chord runs, Shift+F
## included. Blender's Repeat Last on Shift+R is the inspiration, and no code of
## Blender's is taken.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Some actions did not register for the Repeat action. The router answered
## Shift+B with `docker_toolbox`, which is an action of `project.godot` and no
## registered command, and Repeat Last kept only what the command registry
## holds. The same was true of the other older docker toggles, the colour pair,
## the brush size steps and every tool's key. Shift+B and Shift+C have since
## gone to the tools' family steps, so the Layers toggle and Info stand for the
## older toggles that still hold a chord.
##
## The app is built the way the profile suites build it, the two base modules through
## the door and the router's own chords on top, and every chord of Sara Default's
## map is pressed through the router, so a chord added tomorrow is read too.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A surface builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

## The chords that did not count before the fix, each pressed below and read
## back as the last command after it.
const DROPPED: Array[StringName] = [
    &"docker_layers",
    &"info_docker",
    &"color_swap",
    &"color_reset",
    &"brush_size_increase",
    &"brush_size_decrease",
    &"tool_brush",
    &"tool_crop",
    &"tool_eyedropper",
    &"tool_gradient",
    &"tool_lasso",
    &"tool_marquee",
    &"tool_pan",
    &"tool_patch",
    &"tool_transform",
    &"tool_wand",
]

const MODULES: Array[String] = [
    "res://modules/sara-base-modules/base/module.gd",
    "res://modules/sara-base-modules/stamp-brush/module.gd",
]

var _saved_events: Dictionary = {}
var _surface: SaSurface = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _machine: ToolMachine = null
var _router: ShortcutRouter = null
var _note_mode: SaNoteMode = null
## The docker ids the toggle doors were handed, in the order they were.
var _toggled: Array = []
## The dockers' table the router reads, in the shape `MainDockers` hands it.
var _table: Array[Dictionary] = []
## What the chords change outside the suite's own objects, put back after each
## case: Ctrl+Shift+= scales the interface, and X and D move the colour pair.
## Every plain preference as it stood, since the chords write some of them, the
## picker's shape among them, and the profile is the run's for every suite after.
var _saved_settings: Dictionary = {}
var _saved_scale: float = 1.0
var _saved_foreground: Color = Color.BLACK
var _saved_background: Color = Color.WHITE


func before_each() -> void:
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    _saved_scale = SaSettings.ui_scale
    _saved_settings.clear()
    for property: String in SaSettingsKeys.SETTINGS:
        if SaSettingsKeys.is_plain(StringName(property)):
            _saved_settings[property] = SaSettings.get(property)
    _saved_foreground = SaColors.foreground
    _saved_background = SaColors.background
    _toggled.clear()
    _surface = Fixtures.make_surface()
    _registries = Fixtures.make_registries(_surface)
    _modules.clear()
    for path: String in MODULES:
        var module: SaModule = load(path).new()
        module.register(_registries.context.for_module(module.get_id()))
        _modules.append(module)
    SaAppCommands.register_all(_registries, func(docker_id: StringName) -> void: _toggled.append(docker_id))
    _note_mode = SaNoteMode.new()
    SaNoteMode.register_command(_registries.commands, _note_mode)
    _machine = Fixtures.make_bound_machine(_surface)
    _router = ShortcutRouter.new()
    _router.canvas_provider = func() -> SaCanvas: return null
    _router.tool_machine_provider = func() -> ToolMachine: return _machine
    _router.request_quit = func() -> void: pass
    _router.file_command = func(_action: StringName) -> void: pass
    _table.clear()
    for row: Array in SaAppCommands.OLDER_DOCKERS + SaAppCommands.DOCKER_COMMANDS:
        _table.append({"id": String(row[1]), "shortcut": String(row[0])})
    _router.dockers_provider = func() -> Array[Dictionary]: return _table
    _router.toggle_docker = func(index: int) -> void: _toggled.append(StringName(_table[index]["id"]))
    _router.bind_commands(_registries.commands)


func after_each() -> void:
    # The brush editor's chord opens the editor on a deferred call, which would
    # otherwise run inside the next suite and bind a window to that suite's
    # document, freed under it by the time a tool switch rebinds the window.
    # A frame here runs it while this suite has no bar, so it opens nothing.
    await (Engine.get_main_loop() as SceneTree).process_frame
    SaSettings.ui_scale = _saved_scale
    for property: String in _saved_settings:
        if SaSettings.get(property) != _saved_settings[property]:
            SaSettings.set(property, _saved_settings[property])
    SaColors.foreground = _saved_foreground
    SaColors.background = _saved_background
    # Ctrl+R, the recent presets walk, puts its list under EventBus.
    var walk := EventBus.get_node_or_null(SaRecentPresetWalk.NODE_NAME)
    if walk != null:
        EventBus.remove_child(walk)
        walk.free()
    for module: SaModule in _modules:
        module.unregister(_registries.context)
    _modules.clear()
    Fixtures.teardown(_surface, _machine)
    _router.free()
    _note_mode.free()
    _router = null
    _note_mode = null
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


## The press a keyboard sends for *chord*, both spellings of the key, because
## `project.godot` binds the tools by physical key and the commands by the
## printed one.
func _press(chord: String) -> InputEventKey:
    var event := SaShortcutStore.parse_chord(chord)
    if event == null:
        return null
    event.physical_keycode = event.keycode
    event.pressed = true
    return event


## Every action of Sara Default's map with a chord and not in `NOT_REPEATED`,
## pressed through the router. Each press the router takes is read back as the
## last command: the action itself, the Apply Again a filter is kept as, or the
## command the router answered with, which is the eraser toggle for E.
func test_every_chord_the_router_takes_is_the_last_command() -> void:
    var map := SaShortcutStore.current_map()
    var actions: Array = map.keys()
    actions.sort()
    var taken: Array[StringName] = []
    var lost: Array[String] = []
    for action: String in actions:
        var chords: Array = map[action]
        if chords.is_empty() or SaQuickCommands.NOT_REPEATED.has(StringName(action)):
            continue
        # The note mode photographs the window, which a suite has no window
        # for, and its command was kept before the fix as every command was.
        if action == "ui_take_note":
            continue
        var event := _press(chords[0])
        if event == null:
            continue
        SaQuickCommands.last_run = &""
        if not _router.handle(event):
            continue
        taken.append(StringName(action))
        if SaQuickCommands.last_run.is_empty():
            lost.append("%s on %s" % [action, chords[0]])
    assert_eq(lost, [] as Array[String], "every chord the router took is the last command")
    for action: StringName in DROPPED:
        assert_true(taken.has(action), "%s was pressed and taken" % action)


## Each chord the registry does not hold is kept as itself, so the Edit menu's
## row and the search name the right thing.
func test_each_chord_that_was_dropped_is_kept_by_its_own_name() -> void:
    for action: StringName in DROPPED:
        SaQuickCommands.last_run = &""
        assert_true(_router.handle(_press(SaShortcutStore.chords_for(action)[0])), "%s is taken" % action)
        assert_eq(SaQuickCommands.last_run, action, "and is the last command")
        assert_true(SaQuickCommands.can_repeat(), "which there is a way to repeat")


## Shift+T toggles the Layers docker and Shift+R toggles it again.
func test_shift_r_after_shift_t_toggles_the_layers_again() -> void:
    _toggled.clear()
    assert_true(_router.handle(_press("Shift+T")), "Shift+T is taken")
    assert_true(_router.handle(_press("Shift+R")), "and Shift+R")
    assert_eq(_toggled, [SaDockerIds.LAYERS, SaDockerIds.LAYERS], "the Layers docker is toggled twice")
    assert_eq(SaQuickCommands.last_run, &"docker_layers", "and Repeat Last is not the last command")
    _toggled.clear()
    assert_true(_router.handle(_press("Shift+R")), "a second Shift+R")
    assert_eq(_toggled, [SaDockerIds.LAYERS], "toggles it once more")


## X swaps the pair and Shift+R swaps it back, which was nothing before.
func test_shift_r_after_x_swaps_the_colours_back() -> void:
    var foreground := SaColors.foreground
    var background := SaColors.background
    assert_true(_router.handle(_press("X")), "X is taken")
    assert_true(_router.handle(_press("Shift+R")), "and Shift+R")
    assert_eq(SaColors.foreground, foreground, "the foreground is back")
    assert_eq(SaColors.background, background, "and the background")


## A Window menu row toggles a docker without a command, and is kept the way its
## chord is. Repeat Last then presses the same row again.
func test_a_window_menu_docker_row_is_the_last_command() -> void:
    var toggled: Array = []
    var toggle := func(index: int) -> void: toggled.append(index)
    var all := func() -> void: toggled.append(&"all")
    SaQuickCommands.note_docker_row(&"docker_0", _table, toggle, all)
    assert_eq(SaQuickCommands.last_run, &"docker_toolbox", "the Toolbox's row is kept as its toggle")
    SaQuickCommands.repeat_last()
    assert_eq(toggled, [0], "and Repeat Last presses that row again")
    SaQuickCommands.note_docker_row(&"focus_mode", _table, toggle, all)
    assert_eq(SaQuickCommands.last_run, &"toggle_dockers", "Focus Mode's row is kept as Tab")
    SaQuickCommands.repeat_last()
    assert_eq(toggled, [0, &"all"], "and repeated as Tab")
