## The five docker toggles whose Shift chord asked for both
## hands sit under the left hand.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The Minimap was on Shift+M, Tool Options on Shift+O, the Graph on Shift+H,
## Recent Presets on Shift+P and Undo History on Shift+U. The left little finger
## holds Shift, so each was a chord for two hands and the pen went down to press
## it. Sara Default moves the five, and the Krita and Photoshop tables keep
## what they name.
##
## The map is built as the profile suites build it, the two base modules through
## the door and the router's own chords on top, so the clash check reads every
## action the app boots with. The scenario of the same name presses each new
## chord over the booted app and dumps the dockers shown after it.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A surface builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

const MODULES: Array[String] = [
    "res://modules/sara-base-modules/base/module.gd",
    "res://modules/sara-base-modules/stamp-brush/module.gd",
]

## The letters under the left hand on a US keyboard and on the Czech QWERTY
## one, the two layouts it is typed on. A QWERTZ layout swaps Z and Y,
## which would put Undo History's Z under the right hand there.
const LEFT_HAND: Array[Key] = [
    KEY_Q, KEY_W, KEY_E, KEY_R, KEY_T, KEY_A, KEY_S, KEY_D, KEY_F, KEY_G, KEY_Z, KEY_X, KEY_C, KEY_V, KEY_B
]

## The four that lost their toggle chord: the toolbox, colour picker, Recent
## Presets (the history toggle) and Pop-up Palette gave Shift+B, C, E and W to
## their tools' family steps, so each holds no toggle chord and is reached by
## its Window menu row and its Alt+Shift summon.
## Each row of it: the toggle, the docker, the letter its summon keeps.
const UNBOUND: Array = [
    [&"docker_history", SaDockerIds.HISTORY, KEY_E],
    [&"docker_toolbox", SaDockerIds.TOOLBOX, KEY_B],
    [&"docker_color_selector", SaDockerIds.COLOR, KEY_C],
    [&"docker_palette", SaDockerIds.PALETTE, KEY_W],
]

## The five that moved: the toggle, the docker it shows, the letter it holds and
## the one it left. The minimap's is V for view, which
## leaves its C to the colour picker, for colour.
const MOVED: Array = [
    [&"docker_minimap", SaDockerIds.MINIMAP, KEY_V, KEY_M],
    [&"docker_tool_options", SaDockerIds.TOOL_OPTIONS, KEY_D, KEY_O],
    [&"docker_graph", SaDockerIds.GRAPH, KEY_A, KEY_H],
    [&"docker_undo", SaDockerIds.UNDO, KEY_Z, KEY_U],
]

var _saved_events: Dictionary = {}
var _saved_profile: String = ""

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _machine: ToolMachine = null
var _router: ShortcutRouter = null
var _note_mode: SaNoteMode = null
## The docker ids the toggle door was handed, in the order it was.
var _toggled: Array = []
## The docker ids the summon door was handed.
var _summoned: Array = []


func before_each() -> void:
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    SaShortcutStore.dir_override = SaDataRoot.path("test_n33_shortcut_profiles")
    SaShortcutStore.capture_defaults()
    _saved_profile = SaSettings.shortcuts_profile
    SaSettings.shortcuts_profile = SaShortcutStore.DEFAULT_PROFILE

    _toggled.clear()
    _summoned.clear()
    _surface = Fixtures.make_surface()
    _registries = Fixtures.make_registries(_surface)
    _modules.clear()
    for path: String in MODULES:
        var module: SaModule = load(path).new()
        module.register(_registries.context.for_module(module.get_id()))
        _modules.append(module)
    SaAppCommands.register_all(
        _registries,
        func(docker_id: StringName) -> void: _toggled.append(docker_id),
        Callable(),
        func(docker_id: StringName) -> void: _summoned.append(docker_id)
    )
    _note_mode = SaNoteMode.new()
    SaNoteMode.register_command(_registries.commands, _note_mode)
    _machine = Fixtures.make_bound_machine(_surface)
    _router = ShortcutRouter.new()
    _router.canvas_provider = func() -> SaCanvas: return null
    _router.tool_machine_provider = func() -> ToolMachine: return _machine
    _router.bind_commands(_registries.commands)


func after_each() -> void:
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
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
    SaSettings.shortcuts_profile = _saved_profile
    SaShortcutStore.dir_override = ""
    var dir := DirAccess.open(SaDataRoot.path("test_n33_shortcut_profiles"))
    if dir != null:
        for file: String in dir.get_files():
            dir.remove(file)


## The one key event *action* answers to, or null when it holds none or more.
func _only_key(action: StringName) -> InputEventKey:
    if not InputMap.has_action(action):
        return null
    var events := InputMap.action_get_events(action)
    if events.size() != 1:
        return null
    return events[0] as InputEventKey


## Whether *event* is *keycode* with exactly the modifiers named.
func _is_chord(event: InputEventKey, keycode: Key, ctrl: bool, shift: bool, alt: bool) -> bool:
    if event == null:
        return false
    return (
        event.keycode == keycode
        and event.ctrl_pressed == ctrl
        and event.shift_pressed == shift
        and event.alt_pressed == alt
        and not event.meta_pressed
    )


## Both spellings of the key, the way a keyboard sends it: `project.godot` binds
## the tools by physical key and the commands by the printed one.
func _press(keycode: Key, shift: bool) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.shift_pressed = shift
    event.pressed = true
    return event


func test_each_of_the_five_toggles_is_shift_and_a_left_hand_letter() -> void:
    for row: Array in MOVED:
        var toggle: StringName = row[0]
        var letter: Key = row[2]
        assert_true(LEFT_HAND.has(letter), "%s's letter is under the left hand" % toggle)
        assert_true(_is_chord(_only_key(toggle), letter, false, true, false), "%s is Shift+%s alone" % [toggle, char(letter)])


## Every docker toggle with a letter, not only the five, so a docker given a row
## tomorrow on a right-hand letter fails here rather than in a painter's hand.
## Info's F9 is a function key and no letter.
func test_every_docker_toggle_with_a_letter_is_under_the_left_hand() -> void:
    var right: Array[String] = []
    for row: Array in SaAppCommands.DOCKER_COMMANDS + SaAppCommands.OLDER_DOCKERS:
        var key: Key = row[3]
        if key >= KEY_A and key <= KEY_Z and not LEFT_HAND.has(key):
            right.append("%s on Shift+%s" % [row[0], char(key)])
    assert_eq(right, [] as Array[String], "no docker toggle asks for both hands")


func test_each_moved_dockers_summon_and_locked_twin_follow_it() -> void:
    for row: Array in MOVED:
        var toggle: StringName = row[0]
        var letter: Key = row[2]
        var summon := SaAppCommands.summon_id(toggle)
        var locked := SaAppCommands.locked_summon_id(toggle)
        assert_true(_is_chord(_only_key(summon), letter, false, true, true), "%s is Alt+Shift+%s" % [summon, char(letter)])
        assert_true(_is_chord(_only_key(locked), letter, true, true, true), "%s is Ctrl+Alt+Shift+%s" % [locked, char(letter)])


## The letters the five left are nobody's now, under any of the three modifier
## sets the toggle, its summon and its twin use.
func test_the_right_hand_letters_they_left_hold_nothing() -> void:
    for row: Array in MOVED:
        var old := char(row[3])
        for chord: String in ["Shift+" + old, "Alt+Shift+" + old, "Ctrl+Alt+Shift+" + old]:
            var holders: Array[String] = []
            for holder: String in SaShortcutStore.holders(chord):
                # A letter a tool's family step took is nobody's toggle.
                if not holder.begins_with("tool_family_"):
                    holders.append(holder)
            assert_eq(holders, [] as Array[String], "%s holds no docker" % chord)


## The Done of the row: no two actions of any shipped profile on one chord. The
## five keep their letters under Krita, Photoshop and Procreate wherever a table
## does not name them, as Krita names its own backslash for Tool Options.
func test_no_two_actions_of_any_shipped_profile_share_a_chord() -> void:
    var profiles: Array[String] = [SaShortcutStore.DEFAULT_PROFILE]
    profiles.append_array(SaShortcutStore.SHIPPED_PROFILES.keys())
    assert_eq(profiles.size(), 5, "Sara Default, Krita, Photoshop, Procreate and Clip Studio Paint")
    for profile: String in profiles:
        SaShortcutStore.apply_profile(profile)
        var clashes := SaShortcutStore.all_conflicts()
        assert_eq(clashes.keys(), [], "%s gives no chord to two actions: %s" % [profile, str(clashes)])
        var table: Dictionary = SaShortcutStore.SHIPPED_PROFILES.get(profile, {})
        for row: Array in MOVED:
            var toggle: StringName = row[0]
            if table.has(String(toggle)):
                continue
            assert_eq(
                SaShortcutStore.chords_for(toggle), ["Shift+" + char(row[2])] as Array[String], "%s: %s" % [profile, toggle]
            )
    SaShortcutStore.apply_profile("Krita")
    assert_eq(SaShortcutStore.chords_for(&"docker_tool_options"), ["BackSlash"] as Array[String], "Krita keeps its backslash")
    assert_eq(SaShortcutStore.holders("Shift+D"), [] as Array[String], "and leaves Shift+D to nobody there")


## Pressed through the router, each new chord asks for its docker and nothing
## else, and the bare letter under it keeps what it did: C is still the crop
## tool, and Z is still the Brush Presets docker it has always been.
func test_a_press_of_each_chord_asks_for_its_docker() -> void:
    for row: Array in MOVED:
        _toggled.clear()
        assert_true(_router.handle(_press(row[2], true)), "Shift+%s is answered" % char(row[2]))
        assert_eq(_toggled, [row[1]], "by the %s and nothing else" % row[1])

    _toggled.clear()
    assert_eq(_router._answer(_press(KEY_C, false)), &"tool_crop", "Bare C is the crop tool")
    assert_eq(_toggled, [], "and asks for no docker")
    assert_eq(_router._answer(_press(KEY_Z, false)), &"docker_brush_presets", "Bare Z is the Brush Presets docker")
    assert_eq(_toggled, [SaDockerIds.BRUSH_PRESETS], "which it asks for by id")


## The four that lost their toggle chord hold none and still open by the door
## and by their summon, and V is still the minimap's.
func test_the_four_that_lost_a_toggle_chord_keep_their_summon() -> void:
    for row: Array in UNBOUND:
        var toggle: StringName = row[0]
        if not InputMap.has_action(toggle):
            continue
        assert_eq(InputMap.action_get_events(toggle).size(), 0, "%s holds no chord" % toggle)
        assert_eq(SaShortcutStore.chords_for(toggle), [] as Array[String], "the page lists none for %s" % toggle)
        var summon := SaAppCommands.summon_id(toggle)
        assert_true(_is_chord(_only_key(summon), row[2], false, true, true), "%s is Alt+Shift+%s" % [summon, char(row[2])])
        _summoned.clear()
        assert_true(_registries.commands.execute(summon), "%s runs" % summon)
        assert_eq(_summoned, [row[1]], "and summons its docker")
        if _registries.commands.has(toggle):
            _toggled.clear()
            assert_true(_registries.commands.execute(toggle), "%s still runs from its menu row" % toggle)
            assert_eq(_toggled, [row[1]], "and toggles its docker")
    assert_eq(SaShortcutStore.chords_for(&"docker_minimap"), ["Shift+V"] as Array[String], "the minimap is Shift+V")
    assert_eq(SaShortcutStore.holders("Shift+C"), ["tool_family_crop"] as Array[String], "Shift+C steps the crop's family")
    assert_eq(SaShortcutStore.holders("Shift+V"), ["docker_minimap"] as Array[String], "and Shift+V is nobody else's")


## A painter whose own profile put the minimap back on Shift+C keeps it there,
## and the colour picker gives the chord up rather than share it.
func test_a_saved_profile_that_binds_either_letter_keeps_its_own() -> void:
    var overrides: Dictionary[String, Array] = {"docker_minimap": ["Shift+C"]}
    assert_true(SaShortcutStore.save_overrides("u675-mine", overrides), "the profile is written")
    SaShortcutStore.apply_profile("u675-mine")
    assert_eq(SaShortcutStore.chords_for(&"docker_minimap"), ["Shift+C"] as Array[String], "the minimap keeps the painter's C")
    assert_eq(SaShortcutStore.holders("Shift+C"), ["docker_minimap"] as Array[String], "and nobody else holds it")
