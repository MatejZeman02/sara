## Under the Krita profile Alt+Shift and plus or minus step the
## brush's blending mode, and Alt+Shift and a free letter picks one, as Krita's
## own chords do. The twelve letters a docker summon holds stay the summons'.
##
## Pressed the way a keyboard sends them and answered by the router the main
## window hands every unhandled key to, with the brush and its settings the
## stamp-brush module registers, so the mode read back is the one the bar shows.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const BlendModeCommands = preload("res://core/loader/skeleton_blend_mode_commands.gd")

## Krita's fourteen free letters and the command each is the chord of.
const FREE := {
    "Q": &"blend_mode_behind",
    "R": &"blend_mode_clear",
    "K": &"blend_mode_darken",
    "I": &"blend_mode_dissolve",
    "H": &"blend_mode_hard_light",
    "L": &"blend_mode_hard_mix",
    "P": &"blend_mode_hard_overlay",
    "U": &"blend_mode_hue",
    "G": &"blend_mode_lighten",
    "J": &"blend_mode_linear_light",
    "Y": &"blend_mode_luminosity",
    "M": &"blend_mode_multiply",
    "N": &"blend_mode_normal",
    "O": &"blend_mode_overlay",
}

## The twelve letters of Krita's blending modes a docker summon holds.
const HELD := ["X", "C", "D", "A", "E", "Z", "F", "S", "W", "B", "T", "V"]

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _modules: Array = []
var _machine: ToolMachine = null
var _router: ShortcutRouter = null
var _summoned: Array[StringName] = []
var _saved_events: Dictionary = {}
## The profile the run had, put back after each case, because applying one
## writes the setting another suite reads as a fresh folder's.
var _saved_profile: String = ""


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _registries = Fixtures.make_registries(_surface)
    _modules.clear()
    for script: GDScript in [
        load("res://modules/sara-base-modules/stamp-brush/module.gd"),
        load("res://modules/sara-base-modules/base/module.gd"),
    ]:
        var module: SaModule = script.new()
        module.register(_registries.context.for_module(module.get_id()))
        _modules.append(module)
    _summoned.clear()
    SaAppCommands.register_all(
        _registries,
        func(_docker_id: StringName) -> void: pass,
        func() -> ToolMachine: return _machine,
        func(docker_id: StringName) -> void: _summoned.append(docker_id)
    )
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _machine._ready()
    _machine.bind(_surface, _registries.tools)
    _router = ShortcutRouter.new()
    _router.tool_machine_provider = func() -> ToolMachine: return _machine
    _router.bind_commands(_registries.commands)
    _saved_profile = SaSettings.shortcuts_profile
    SaShortcutStore.apply_profile("Krita")


func after_each() -> void:
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    SaSettings.shortcuts_profile = _saved_profile
    _brush_settings().set(&"blend_mode", &"normal")
    for module: SaModule in _modules:
        module.unregister(_registries.context)
    _modules.clear()
    _router.free()
    _router = null
    Fixtures.teardown(_surface, _machine)
    _machine = null
    _surface = null
    _registries = null
    for action: StringName in InputMap.get_actions():
        if not _saved_events.has(action):
            InputMap.erase_action(action)
    for action: StringName in _saved_events:
        if not InputMap.has_action(action):
            continue
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)


## The press a keyboard sends: the character, its position and its label all
## set, rather than the one field a chord's text parses to.
func _press(chord: String) -> InputEventKey:
    var parsed := SaShortcutStore.parse_chord(chord)
    var event := InputEventKey.new()
    event.keycode = parsed.keycode
    event.physical_keycode = parsed.keycode
    event.key_label = parsed.keycode
    event.ctrl_pressed = parsed.ctrl_pressed
    event.shift_pressed = parsed.shift_pressed
    event.alt_pressed = parsed.alt_pressed
    event.pressed = true
    return event


func _brush_settings() -> Resource:
    return _machine.get_tool(&"brush").get("settings") as Resource


func _mode() -> StringName:
    return StringName(_brush_settings().get(&"blend_mode"))


func test_the_machine_paints_with_the_brush_and_the_commands_move_its_settings() -> void:
    assert_eq(_machine.active_tool_name, &"brush", "The machine starts on the brush")
    assert_eq(BlendModeCommands.target_settings(_registries.context), _brush_settings(), "and a press moves the brush's settings")


## The first half of the Done-when: plus steps the brush's mode forward along
## the list the bar's menu draws, and minus steps it back.
func test_alt_shift_plus_and_minus_step_the_brush_s_mode_forward_and_back() -> void:
    var order := BlendModeCommands.walk_order(_registries.blend_modes)
    _brush_settings().set(&"blend_mode", &"multiply")
    var at := order.find(&"multiply")
    assert_true(at > 0 and at < order.size() - 1, "Multiply has a mode on either side: %s" % [order])

    assert_true(_router.handle(_press("Alt+Shift+Plus")), "The router takes Alt+Shift+plus")
    assert_eq(_mode(), order[at + 1], "and the brush is on the mode after Multiply")

    assert_true(_router.handle(_press("Alt+Shift+Minus")), "The router takes Alt+Shift+minus")
    assert_eq(_mode(), &"multiply", "and the brush is back on Multiply")
    assert_true(_router.handle(_press("Alt+Shift+Minus")), "and again")
    assert_eq(_mode(), order[at - 1], "on the mode before it")


## Krita's step moves only while the new index is inside the box, so the ends
## hold, and Sara's does the same.
func test_a_step_past_either_end_of_the_list_stops_there() -> void:
    var order := BlendModeCommands.walk_order(_registries.blend_modes)
    _brush_settings().set(&"blend_mode", order[0])
    assert_true(_router.handle(_press("Alt+Shift+Minus")), "Minus on the first mode is taken")
    assert_eq(_mode(), order[0], "and the brush stays on it")
    _brush_settings().set(&"blend_mode", order[-1])
    assert_true(_router.handle(_press("Alt+Shift+Plus")), "Plus on the last mode is taken")
    assert_eq(_mode(), order[-1], "and the brush stays on it")


## The internal Alpha Lock is in no menu, so no step lands on it.
func test_the_walk_is_the_menu_s_list_and_skips_what_it_hides() -> void:
    var order := BlendModeCommands.walk_order(_registries.blend_modes)
    assert_false(order.has(&"alpha_lock"), "Alpha Lock, which no menu offers, is not walked")
    assert_true(order.has(&"erase"), "Erase, which the brush's menu offers, is")
    assert_eq(order[0], &"normal", "and the walk starts where the menu does")


## The second clause of the first Done-when: Alt+Shift+M picks Multiply.
func test_alt_shift_m_picks_multiply() -> void:
    assert_eq(_mode(), &"normal", "The brush starts on Normal")
    assert_true(_router.handle(_press("Alt+Shift+M")), "The router takes Alt+Shift+M")
    assert_eq(_mode(), &"multiply", "and the brush is on Multiply")
    assert_true(_router.handle(_press("Alt+Shift+N")), "Alt+Shift+N is taken")
    assert_eq(_mode(), &"normal", "and the brush is on Normal again")


## A letter whose mode Sara has no kernel for keeps the brush as it was.
func test_a_letter_whose_mode_is_not_installed_leaves_the_brush_alone() -> void:
    _brush_settings().set(&"blend_mode", &"overlay")
    assert_false(_registries.blend_modes.has(&"dissolve"), "Sara has no Dissolve")
    _router.handle(_press("Alt+Shift+I"))
    assert_eq(_mode(), &"overlay", "so Alt+Shift+I leaves the brush on Overlay")


## The second Done-when, its first half: the store keeps every one of the
## fourteen free chords on its command under Krita and drops none.
func test_none_of_the_fourteen_free_chords_is_dropped_by_the_store() -> void:
    var dropped: Array[String] = []
    for letter: String in FREE:
        var chord := SaShortcutStore.chord_text(SaShortcutStore.parse_chord("Alt+Shift+" + letter))
        var holds := SaShortcutStore.chords_for(FREE[letter])
        if not holds.has(chord):
            dropped.append("%s holds %s and not %s" % [FREE[letter], holds, chord])
    for pair: Array in [[&"blend_mode_next", "Alt+Shift+Plus"], [&"blend_mode_previous", "Alt+Shift+Minus"]]:
        var chord := SaShortcutStore.chord_text(SaShortcutStore.parse_chord(String(pair[1])))
        if not SaShortcutStore.chords_for(pair[0]).has(chord):
            dropped.append("%s lost %s" % [pair[0], chord])
    assert_eq(dropped, [] as Array[String], "every free chord is its command's")


## The second Done-when, its second half. The twelve letters are the docker
## summons' on Sara's own map, and each summon there still answers its press.
## The Krita profile leaves every summon unbound, by `SUMMON_PREFIX` in the
## store, because Krita has no summon, but for the palette's, which stays on
## Alt+Shift+W. So under Krita eleven of the twelve reach no
## command at all, and the twelfth summons the palette, never a blending mode.
func test_the_summons_on_the_twelve_held_letters_still_answer() -> void:
    var letters: Array[String] = []
    var under_krita: Array[String] = []
    for entry: Array in SaAppCommands.DOCKER_COMMANDS + SaAppCommands.OLDER_DOCKERS:
        var letter := OS.get_keycode_string(entry[3])
        if not HELD.has(letter):
            continue
        letters.append(letter)
        var chord := SaShortcutStore.chord_text(SaShortcutStore.parse_chord("Alt+Shift+" + letter))
        _summoned.clear()
        if _router.handle(_press(chord)) or not _summoned.is_empty():
            under_krita.append(chord)
            assert_eq(_summoned, [entry[1]] as Array[StringName], "and %s summons its own docker" % chord)
    assert_eq(under_krita, ["Alt+Shift+W"] as Array[String], "Under Krita only the palette's summon answers")
    assert_eq(_mode(), &"normal", "and none of them moved the brush")

    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    _router.bind_commands(_registries.commands)
    for entry: Array in SaAppCommands.DOCKER_COMMANDS + SaAppCommands.OLDER_DOCKERS:
        var letter := OS.get_keycode_string(entry[3])
        if not HELD.has(letter):
            continue
        var chord := SaShortcutStore.chord_text(SaShortcutStore.parse_chord("Alt+Shift+" + letter))
        var summon := SaAppCommands.summon_id(entry[0])
        assert_true(SaShortcutStore.chords_for(summon).has(chord), "On Sara's own map %s holds %s" % [summon, chord])
        _summoned.clear()
        assert_true(_router.handle(_press(chord)), "The router takes %s" % chord)
        assert_eq(_summoned, [entry[1]] as Array[StringName], "and %s summons its docker" % chord)
    letters.sort()
    var held := HELD.duplicate()
    held.sort()
    assert_eq(letters, held, "the twelve letters are the summons' own")
    assert_eq(_mode(), &"normal", "and none of the summons moved the brush")


## Sara's own map gives the sixteen commands no chord, so no letter of Sara
## Default moves the brush's mode.
func test_sara_default_gives_the_blending_mode_commands_no_chord() -> void:
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    var bound: Array[String] = []
    for command: StringName in FREE.values() + [&"blend_mode_next", &"blend_mode_previous"]:
        if not SaShortcutStore.chords_for(command).filter(func(c: String) -> bool: return not c.is_empty()).is_empty():
            bound.append(String(command))
    assert_eq(bound, [] as Array[String], "none of them holds a chord on Sara's own map")
