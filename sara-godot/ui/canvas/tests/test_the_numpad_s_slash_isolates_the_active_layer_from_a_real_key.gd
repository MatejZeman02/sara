## The numpad's slash isolates the active layer from a real key.
##
## A key built in GDScript is one no keyboard sends. These are the events Sara logged, through
## `SaKeyLog`, when `scripts/virtual_keyboard.py --play numpad-slash` pressed
## `KEY_KPSLASH` through `/dev/uinput` into an offscreen Sara: a label of 47 and
## a character of 47 on the press, none on the release, and the same with Num
## Lock on and off. Handed to the router as they came, under Sara Default and
## under Krita, whose table must keep the command.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const SIZE := Vector2i(256, 256)
## The logged keycode of each key, `KEY_KP_DIVIDE` and `KEY_NUMLOCK`.
const KP_DIVIDE := 4194434
const NUM_LOCK := 4194330
## The line `SaKeyLog` printed for the numpad's slash pressed, quoted from the
## proof's `run.txt`.
const HEARD := "key heard: Kp Divide, keycode 4194434, physical 4194434 (Kp Divide), label 47, unicode 47, pressed"

static var scratch_dir: String = SaDataRoot.path("test_the_numpad_s_slash")

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _router: ShortcutRouter = null
var _saved_events: Dictionary = {}
var _saved_actions: Array[StringName] = []
var _saved_profile: String = ""


func before_each() -> void:
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    _saved_actions.assign(InputMap.get_actions())
    _saved_profile = SaSettings.shortcuts_profile
    SaShortcutStore.dir_override = scratch_dir
    _surface = Fixtures.make_surface(SIZE)
    _registries = Fixtures.make_registries(_surface)
    SaAppCommands.register_all(_registries, func(_docker_id: StringName) -> void: pass)
    _router = ShortcutRouter.new()
    _router.bind_commands(_registries.commands)
    SaShortcutStore.capture_defaults()
    SaSettings.shortcuts_profile = SaShortcutStore.DEFAULT_PROFILE
    var doc: SaDocument = _surface.easel.document
    var ops := SaLayerOps.new(doc)
    doc.set_active_layer(ops.add())


func after_each() -> void:
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    SaLocalView.forget(_surface.easel.document)
    _router.free()
    _router = null
    _registries = null
    Fixtures.teardown(_surface)
    _surface = null
    for action: StringName in InputMap.get_actions():
        if not _saved_events.has(action) and not _saved_actions.has(action):
            InputMap.erase_action(action)
    for action: StringName in _saved_events:
        if not InputMap.has_action(action):
            continue
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)
    SaSettings.shortcuts_profile = _saved_profile
    SaShortcutStore.dir_override = ""
    var dir := DirAccess.open(scratch_dir)
    if dir != null:
        for file: String in dir.get_files():
            dir.remove(file)


## An event with the four readings Sara logged for it.
func _logged(keycode: int, physical: int, label: int, unicode: int, pressed: bool) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode as Key
    event.physical_keycode = physical as Key
    event.key_label = label as Key
    event.unicode = unicode
    event.pressed = pressed
    return event


## The numpad's slash pressed and let go, as the Linux run logged it with Num
## Lock on and off alike.
func _slash() -> Array[InputEventKey]:
    return [_logged(KP_DIVIDE, KP_DIVIDE, 47, 47, true), _logged(KP_DIVIDE, KP_DIVIDE, 47, 0, false)]


## Num Lock pressed and let go, as logged.
func _num_lock() -> Array[InputEventKey]:
    return [_logged(NUM_LOCK, NUM_LOCK, NUM_LOCK, 0, true), _logged(NUM_LOCK, NUM_LOCK, NUM_LOCK, 0, false)]


## The numpad's slash as the Windows driver reads `WM_KEYDOWN`, its label the
## keycode.
func _windows_slash() -> Array[InputEventKey]:
    return [_logged(KP_DIVIDE, KP_DIVIDE, KP_DIVIDE, 47, true), _logged(KP_DIVIDE, KP_DIVIDE, KP_DIVIDE, 0, false)]


func _hand(events: Array[InputEventKey]) -> void:
    for event: InputEventKey in events:
        _router.handle(event)


## The run's order: Num Lock, two slashes, Num Lock, two slashes, isolation read
## after each slash.
func _plays(profile: String) -> void:
    SaShortcutStore.apply_profile(profile)
    var doc: SaDocument = _surface.easel.document
    var seen: Array[bool] = []
    for lock: int in 2:
        _hand(_num_lock())
        for press: int in 2:
            _hand(_slash())
            seen.append(SaLocalView.is_on(doc))
    var told := "%s: each logged press of the numpad's slash toggles the isolation, Num Lock on and off" % profile
    assert_eq(seen, [true, false, true, false] as Array[bool], told)


func test_sara_default_isolates_on_the_logged_key() -> void:
    _plays(SaShortcutStore.DEFAULT_PROFILE)


func test_the_krita_profile_isolates_on_the_logged_key() -> void:
    _plays("Krita")


## Krita keeps `/` for the previous preset, so the profile gives the isolation
## the numpad's slash and not the main row's.
func test_the_krita_profile_leaves_slash_to_the_previous_preset() -> void:
    SaShortcutStore.apply_profile("Krita")
    var isolation: Array[String] = ["view_isolate_active_layer"]
    var swap: Array[String] = ["brush_preset_previous"]
    var numpad: Array[String] = ["Numpad /"]
    assert_eq(SaShortcutStore.chords_for(SaIsolateActiveLayer.COMMAND), numpad, "Krita: the isolation is on the numpad's slash")
    assert_eq(SaShortcutStore.holders("/"), swap, "Krita: and / is the swap's alone")
    assert_eq(SaShortcutStore.holders("Numpad /"), isolation, "Krita: the numpad's slash is the isolation's alone")


## What Godot's Windows driver makes of `VK_DIVIDE` on a `WM_KEYDOWN`: an
## extended key, so its label is the keycode rather than a character the
## layout gives. Read from `display_server_windows.cpp` of 4.7.
func test_the_windows_form_of_the_key_isolates_under_both_profiles() -> void:
    var doc: SaDocument = _surface.easel.document
    for profile: String in [SaShortcutStore.DEFAULT_PROFILE, "Krita"]:
        SaShortcutStore.apply_profile(profile)
        _hand(_windows_slash())
        assert_true(SaLocalView.is_on(doc), "%s: the Windows form isolates" % profile)
        _hand(_windows_slash())
        assert_false(SaLocalView.is_on(doc), "%s: and a second press ends it" % profile)


## The log's line for the press reads as the run quoted it.
func test_the_key_log_line_names_the_four_readings() -> void:
    assert_eq(SaKeyLog.line(_slash()[0]), HEARD, "The line reads as the run logged it")
