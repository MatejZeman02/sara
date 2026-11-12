## Bare A makes the brush smaller and bare S larger, beside the brackets.
##
## A and S are a second option next to the square brackets, since nothing else
## uses the plain keys. The two keys are a second event on `brush_size_decrease` and
## `brush_size_increase` in `project.godot`, and `brush_size_direction` reads
## what the two actions hold before it reads the brackets by hand, so a chord
## added to either action, or bound on the Keyboard Shortcuts page, steps the
## size as well.
##
## Whether anything else of Sara Default answers the two keys is read off the
## booted app, skeleton, app, router, base modules and tools together, which
## needs the modules loaded and so a rendering device.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## The events themselves, put back after each case, for the reason
## `test_shortcut_editor.gd` gives: restoring from text would rewrite a
## physically bound key as a keycode one.
var _saved_events: Dictionary = {}


func before_each() -> void:
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()


func after_each() -> void:
    for action: StringName in _saved_events:
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)
    ModuleLoader.unload_all()


## One key down, in the shape a scenario's `key` step sends and a keyboard's
## letter carries: the position and the keycode both.
func _key(keycode: Key, shift: bool = false, ctrl: bool = false) -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = keycode
    key.physical_keycode = keycode
    key.shift_pressed = shift
    key.ctrl_pressed = ctrl
    key.pressed = true
    return key


func test_the_two_actions_hold_a_and_s_beside_the_brackets() -> void:
    var smaller := SaShortcutStore.chords_for(&"brush_size_decrease")
    var larger := SaShortcutStore.chords_for(&"brush_size_increase")
    assert_eq(smaller.size(), 2, "Smaller brush holds two chords: %s" % str(smaller))
    assert_true(smaller.has("A"), "and A is one of them: %s" % str(smaller))
    assert_eq(larger.size(), 2, "Larger brush holds two chords: %s" % str(larger))
    assert_true(larger.has("S"), "and S is one of them: %s" % str(larger))
    assert_eq(SaShortcutKeys.brush_size_direction(_key(KEY_BRACKETLEFT)), -1, "The left bracket still steps down")
    assert_eq(SaShortcutKeys.brush_size_direction(_key(KEY_BRACKETRIGHT)), 1, "and the right one up")


## The ask itself: A and S pressed over the canvas, through the router a
## keyboard reaches, step the brush a tenth down and a tenth up, and a held key
## repeats the way a held bracket does.
func test_a_and_s_over_the_canvas_step_the_size_down_and_up() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var router := ShortcutRouter.new()
    router.tool_machine_provider = func() -> ToolMachine: return machine
    router.bind_commands(SaCommandRegistry.new())
    var settings: Resource = machine.get_tool(&"brush").get("settings")
    var before: float = settings.radius

    assert_true(router.handle(_key(KEY_A)), "A is taken")
    var after_a: float = settings.radius
    assert_almost_eq(after_a, before + SaShortcutKeys.brush_size_step(before, -1), 1e-6, "by the brush, a tenth smaller")
    assert_true(router.handle(_key(KEY_S)), "S is taken")
    var after_s: float = settings.radius
    assert_almost_eq(after_s, after_a + SaShortcutKeys.brush_size_step(after_a, 1), 1e-6, "by the brush, a tenth larger")

    var held := _key(KEY_S)
    held.echo = true
    assert_true(ShortcutRouter.repeats_while_held(held), "A held S repeats, as a held bracket does")
    assert_true(router.handle(held), "and its echo is a step")
    assert_true(settings.radius > after_s, "a step up")

    router.free()
    Fixtures.teardown(surface, machine)


## Exactly, so the chords that hold A and S with a modifier keep them, Ctrl+A
## selecting all and Ctrl+S saving above all.
func test_a_modifier_on_either_key_is_not_the_size() -> void:
    for keycode: Key in [KEY_A, KEY_S]:
        var name := OS.get_keycode_string(keycode)
        assert_eq(SaShortcutKeys.brush_size_direction(_key(keycode, true)), 0, "Shift+%s is not the size" % name)
        assert_eq(SaShortcutKeys.brush_size_direction(_key(keycode, false, true)), 0, "nor Ctrl+%s" % name)
        var released := _key(keycode)
        released.pressed = false
        assert_eq(SaShortcutKeys.brush_size_direction(released), 0, "nor %s let go" % name)


## A chord a painter binds on the page steps the size too, which it never did
## while the brackets were read off a table of their own.
func test_a_chord_bound_on_the_page_steps_the_size() -> void:
    SaShortcutStore.set_chords(&"brush_size_increase", ["K"])
    assert_eq(SaShortcutKeys.brush_size_direction(_key(KEY_K)), 1, "K, bound to Larger brush, steps it up")
    assert_eq(SaShortcutKeys.brush_size_direction(_key(KEY_S)), 0, "and S, unbound from it, no longer does")


## Nothing else of Sara Default answers bare A or bare S. Every action of the
## booted app is asked, the engine's own included, so a module's tool or a
## command added later that takes either key fails here by name.
func test_no_other_action_of_sara_default_answers_a_or_s() -> void:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    SaAppCommands.register_all(
        registries,
        func(_docker_id: StringName) -> void: pass,
        func() -> Variant: return null,
        func(_docker_id: StringName) -> void: pass
    )
    ModuleLoader.load_and_register_modules(registries.context)
    var router := ShortcutRouter.new()
    router.bind_commands(registries.commands, registries.view_transforms)
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    assert_true(registries.commands.list_ids().size() > 100, "The boot registered the app's commands")
    assert_true(registries.tools.list_descriptors().size() > 10, "and the modules' tools")

    var holders: Array[String] = []
    for action: StringName in InputMap.get_actions():
        for keycode: Key in [KEY_A, KEY_S]:
            if InputMap.event_is_action(_key(keycode), action, true):
                holders.append("%s on %s" % [action, OS.get_keycode_string(keycode)])
    holders.sort()
    assert_eq(
        holders,
        ["brush_size_decrease on A", "brush_size_increase on S"] as Array[String],
        "Only the two size actions answer bare A and S in Sara Default"
    )
    router.free()


## A shipped Krita or Photoshop table that names the two actions replaces the
## build's chords, and keeps only the same key on another row: A and S are
## another key, so both profiles size the brush on the brackets alone.
func test_the_krita_and_photoshop_profiles_keep_the_brackets_alone() -> void:
    for profile: String in SaShortcutStore.SHIPPED_PROFILES:
        var map := SaShortcutStore.load_profile(profile)
        assert_eq(map.get("brush_size_decrease", []), ["["], "%s's smaller brush is [ alone" % profile)
        assert_eq(map.get("brush_size_increase", []), ["]"], "%s's larger brush is ] alone" % profile)
