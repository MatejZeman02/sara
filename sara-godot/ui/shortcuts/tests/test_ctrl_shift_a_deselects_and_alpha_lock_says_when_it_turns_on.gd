## Ctrl+Shift+A is Krita's Deselect, so it must not lock the layer's alpha, which
## would leave the next stroke laying no paint with nothing on screen to say
## why. Lock Alpha is on Ctrl+Alt+A, and the lock says so in the corner when it turns on.
##
## Pressed the way a keyboard sends a chord and answered by the router the main
## window hands every unhandled key to, so what is held is what a hand gets.
## The scenario of the same name shows the paint laid and the corner line.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The selection and the lock live on a document, which needs a RenderingDevice.
const REQUIRES_GPU := true

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _router: ShortcutRouter = null
var _notices: Array[String] = []
var _refusals: Array[String] = []
var _saved_events: Dictionary = {}


## The application's commands are registered as well as the skeleton's, and the
## map is saved after both, because applying a profile makes any action it names
## that does not exist yet. One made here and left behind keeps the chord the
## profile gave it, and the next suite to register the command finds the action
## already there and never writes its own: `edit_preferences` stayed on
## Photoshop's Ctrl+K for the rest of the run.
func before_each() -> void:
    _surface = Fixtures.make_surface()
    _registries = Fixtures.make_registries(_surface)
    SaAppCommands.register_all(_registries, func(_docker_id: StringName) -> void: pass)
    _router = ShortcutRouter.new()
    _router.bind_commands(_registries.commands)
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    _notices.clear()
    _refusals.clear()
    EventBus.corner_notice.connect(_hear_notice)
    EventBus.paint_refused.connect(_hear_refusal)


func after_each() -> void:
    EventBus.corner_notice.disconnect(_hear_notice)
    EventBus.paint_refused.disconnect(_hear_refusal)
    _router.free()
    _router = null
    _registries = null
    Fixtures.teardown(_surface)
    _surface = null
    for action: StringName in InputMap.get_actions():
        if not _saved_events.has(action):
            InputMap.erase_action(action)
    for action: StringName in _saved_events:
        if not InputMap.has_action(action):
            continue
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)


func _hear_notice(line: String) -> void:
    _notices.append(line)


func _hear_refusal(line: String) -> void:
    _refusals.append(line)


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


## A selection up, Ctrl+Shift+A: it drops the selection and leaves the lock alone.
func test_ctrl_shift_a_drops_the_selection_and_leaves_the_alpha_alone() -> void:
    var doc: SaDocument = _surface.easel.document
    doc.selection.select_rect(Rect2i(16, 16, 64, 32))
    assert_true(doc.selection.active, "A selection is up to begin with")

    assert_true(_router.handle(_press("Ctrl+Shift+A")), "The router takes the press")

    assert_false(doc.selection.active, "and the selection is dropped")
    assert_false(doc.active_layer.alpha_locked, "with the alpha left unlocked")
    assert_eq(_notices, [] as Array[String], "and nothing said in the corner")


## Ctrl+D is still Deselect, Photoshop's chord, beside it.
func test_ctrl_d_still_drops_the_selection() -> void:
    var doc: SaDocument = _surface.easel.document
    doc.selection.select_rect(Rect2i(16, 16, 64, 32))

    assert_true(_router.handle(_press("Ctrl+D")), "The router takes Ctrl+D")

    assert_false(doc.selection.active, "and the selection is dropped")


## The lock turning on says one line naming the layer and the way back, on the
## route that is not a refusal, because nothing was refused.
func test_ctrl_alt_a_locks_the_alpha_and_says_so_once() -> void:
    var layer: SaLayer = _surface.easel.document.active_layer

    assert_true(_router.handle(_press("Ctrl+Alt+A")), "The router takes Ctrl+Alt+A")

    assert_true(layer.alpha_locked, "and the alpha is locked")
    assert_eq(_notices.size(), 1, "with one line in the corner: %s" % [_notices])
    if _notices.size() == 1:
        assert_true(_notices[0].contains("'%s'" % layer.name), "naming the layer: %s" % _notices[0])
        assert_true(_notices[0].contains("Lock Alpha"), "and the lock: %s" % _notices[0])
        assert_true(_notices[0].contains("Ctrl+Alt+A turns it off"), "and how to turn it off: %s" % _notices[0])
    assert_eq(_refusals, [] as Array[String], "and nothing on the refusal route")


## Turning it off is what the painter went looking for, so it says nothing,
## from the chord and from the Layer menu's row alike.
func test_turning_it_off_says_nothing() -> void:
    var layer: SaLayer = _surface.easel.document.active_layer
    _router.handle(_press("Ctrl+Alt+A"))
    _notices.clear()

    assert_true(_router.handle(_press("Ctrl+Alt+A")), "The second press is taken")
    assert_false(layer.alpha_locked, "and unlocks the alpha")
    assert_eq(_notices, [] as Array[String], "without a word")

    assert_true(_registries.commands.execute(&"layer_alpha_lock"), "The menu row turns it on")
    assert_eq(_notices.size(), 1, "and says so")
    assert_true(_registries.commands.execute(&"layer_alpha_lock"), "and off again")
    assert_eq(_notices.size(), 1, "saying nothing more")


## The line reads the map as it stands. Under Krita the alpha lock has no
## chord, so it points at the menu row a painter on that map reaches it from.
func test_a_profile_with_no_chord_for_it_points_at_the_menu() -> void:
    SaShortcutStore.apply_profile("Krita")
    assert_eq(SaShortcutStore.chords_for(&"layer_alpha_lock"), [] as Array[String], "Krita clears the alpha lock")

    _registries.commands.execute(&"layer_alpha_lock")

    assert_eq(_notices.size(), 1, "The lock still says it turned on")
    if _notices.size() == 1:
        assert_true(_notices[0].contains("Layer menu"), "and points at the menu: %s" % _notices[0])
        assert_false(_notices[0].contains("Ctrl+"), "rather than a chord that does nothing: %s" % _notices[0])
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)


## What the builder checks on the Keyboard Shortcuts page, held here: in every
## shipped profile Ctrl+Alt+A is the alpha lock's or nobody's, and
## Ctrl+Shift+A is Deselect's or nobody's.
func test_no_shipped_profile_gives_either_chord_to_anything_else() -> void:
    for profile: String in [SaShortcutStore.DEFAULT_PROFILE, "Krita", "Photoshop"]:
        SaShortcutStore.apply_profile(profile)
        var alpha := SaShortcutStore.holders("Ctrl+Alt+A")
        alpha.erase("layer_alpha_lock")
        assert_eq(alpha, [] as Array[String], "%s gives Ctrl+Alt+A to nothing but Lock Alpha" % profile)
        var deselect := SaShortcutStore.holders("Ctrl+Shift+A")
        deselect.erase("select_none")
        assert_eq(deselect, [] as Array[String], "%s gives Ctrl+Shift+A to nothing but Deselect" % profile)
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    assert_true(SaShortcutStore.holders("Ctrl+Alt+A").has("layer_alpha_lock"), "and the default map is back")
