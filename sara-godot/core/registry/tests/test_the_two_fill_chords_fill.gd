## Alt and Backspace fill the active layer with the foreground colour and Alt
## and Delete with the background, pressed the way a keyboard sends them and
## answered by the router the main window hands every unhandled key to.
##
## A painter's note of 2026-09-21 was "ALT + BACKSPACE/DEL that should fill
## canvas with selected colours doesn't work". On the build's own map the press
## reaches the fill and the pixels change, which is the first half here. The
## step that stops it is the shortcut store: the shipped Krita profile, which
## a painter's settings named, gives both commands Krita's own chords and
## takes the Alt ones away, which is the second half. The third is the
## refusal, which is not silence and says why in the corner.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The proof is the pixels a fill wrote, which needs a RenderingDevice.
const REQUIRES_GPU := true

const CHORDS := {
    &"fill_foreground": "Alt+Backspace",
    &"fill_background": "Alt+Delete",
}

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _router: ShortcutRouter = null
var _pair: Array = []
var _heard: Array[String] = []
var _saved_events: Dictionary = {}


## The application's commands are registered and the map saved after them,
## because applying a profile makes any action it names that does not exist
## yet, and one left behind keeps the profile's chord, or none, for the rest of
## the run: `test_command_chords` then found `window_fullscreen` and the brush
## slots with no chord. Whatever the profiles still made is erased again.
func before_each() -> void:
    _surface = Fixtures.make_surface()
    _registries = Fixtures.make_registries(_surface)
    SaAppCommands.register_all(_registries, func(_docker_id: StringName) -> void: pass)
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    _router = ShortcutRouter.new()
    _router.bind_commands(_registries.commands)
    _pair = [SaColors.foreground, SaColors.background]
    SaColors.foreground = Color(1.0, 0.0, 0.0, 1.0)
    SaColors.background = Color(0.0, 0.0, 1.0, 1.0)
    _heard.clear()
    EventBus.paint_refused.connect(_hear)


func after_each() -> void:
    EventBus.paint_refused.disconnect(_hear)
    SaColors.foreground = _pair[0]
    SaColors.background = _pair[1]
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


func _hear(reason: String) -> void:
    _heard.append(reason)


## The press a keyboard sends: the character, its position and its label all
## set, with Alt held, rather than the one field a chord's text parses to.
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


## The first texel of the active layer's top left chunk, straight off the GPU.
func _first_texel() -> Color:
    var doc: SaDocument = _surface.easel.document
    var chunk: SaTexture = doc.active_layer.get_or_create_field(Vector2i.ZERO)
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(chunk.rid, 0)
    if data.size() < 16:
        return Color(0, 0, 0, 0)
    return Color(data.decode_float(0), data.decode_float(4), data.decode_float(8), data.decode_float(12))


func test_the_store_holds_both_chords_on_the_build_s_own_map() -> void:
    for action: StringName in CHORDS:
        assert_true(SaShortcutStore.chords_for(action).has(CHORDS[action]), "%s answers %s" % [action, CHORDS[action]])


func test_alt_backspace_through_the_router_lays_down_the_foreground() -> void:
    var doc: SaDocument = _surface.easel.document

    assert_true(_router.handle(_press(CHORDS[&"fill_foreground"])), "The router takes the press")

    var texel := _first_texel()
    assert_almost_eq(texel.r, 1.0, 0.01, "and the layer is the foreground red")
    assert_almost_eq(texel.a, 1.0, 0.01, "all the way through")
    assert_eq(doc.history.step_count(), 1, "in one history step")
    assert_true(_heard.is_empty(), "with nothing to explain")


func test_alt_delete_through_the_router_lays_down_the_background() -> void:
    assert_true(_router.handle(_press(CHORDS[&"fill_background"])), "The router takes the press")

    var texel := _first_texel()
    assert_almost_eq(texel.b, 1.0, 0.01, "and the layer is the background blue")
    assert_almost_eq(texel.r, 0.0, 0.01, "with none of the foreground in it")


func test_a_locked_layer_says_why_it_refused_both() -> void:
    var doc: SaDocument = _surface.easel.document
    doc.active_layer.is_locked = true

    for action: StringName in CHORDS:
        assert_false(_router.handle(_press(CHORDS[action])), "%s is declined on a locked layer" % action)
    doc.active_layer.is_locked = false

    assert_almost_eq(_first_texel().a, 0.0, 0.01, "Nothing landed")
    assert_eq(doc.history.step_count(), 0, "and nothing reached the history")
    assert_eq(_heard.size(), 2, "Each press said something")
    assert_true(_heard[0].contains("locked"), "and what it said is the lock: %s" % _heard[0])


func test_a_group_says_why_it_refused() -> void:
    var doc: SaDocument = _surface.easel.document
    doc.set_active_layer(SaLayerOps.new(doc).group_active())

    assert_false(_router.handle(_press(CHORDS[&"fill_foreground"])), "A group declines the press")

    assert_eq(_heard.size(), 1, "and says so")
    assert_true(_heard[0].contains("group"), "naming the group: %s" % _heard[0])


## The step the note stopped at. The Krita table names both fills, so the
## profile replaces the Alt chords rather than adding to them, and the press
## the note describes reaches no command at all.
func test_the_krita_profile_answers_its_own_chords_and_not_the_alt_ones() -> void:
    SaShortcutStore.apply_profile("Krita")

    for action: StringName in CHORDS:
        assert_false(
            SaShortcutStore.chords_for(action).has(CHORDS[action]),
            "Under Krita %s no longer answers %s" % [action, CHORDS[action]]
        )
    assert_false(_router.handle(_press(CHORDS[&"fill_foreground"])), "so Alt and Backspace reach nothing")
    assert_almost_eq(_first_texel().a, 0.0, 0.01, "and the layer stays empty, which is the report")

    var krita := String(SaShortcutStore.KRITA_DEFAULTS["fill_foreground"])
    assert_true(_router.handle(_press(krita)), "Krita's own %s is what fills there" % krita)
    assert_almost_eq(_first_texel().r, 1.0, 0.01, "with the foreground")

    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    for action: StringName in CHORDS:
        assert_true(
            SaShortcutStore.chords_for(action).has(CHORDS[action]),
            "Back on the default map %s answers %s again" % [action, CHORDS[action]]
        )


## Krita's bare Delete is its background fill and its bare
## Backspace its Clear, and the profile keeps both, where Sara's own map gives
## both bare keys to the clear. So under Krita Delete lays the background down
## and Backspace takes it away, and neither key answers two commands.
func test_under_krita_delete_fills_with_the_background_and_backspace_clears() -> void:
    var doc: SaDocument = _surface.easel.document
    SaShortcutStore.apply_profile("Krita")

    assert_eq(SaShortcutStore.chords_for(&"fill_background"), ["Delete"] as Array[String], "The background fill is Delete")
    assert_eq(SaShortcutStore.chords_for(&"layer_clear"), ["Backspace"] as Array[String], "and the clear Backspace alone")
    assert_true(_router.handle(_press("Delete")), "The router takes Delete")
    assert_almost_eq(_first_texel().b, 1.0, 0.01, "and the layer is the background blue")
    assert_true(_router.handle(_press("Backspace")), "The router takes Backspace")
    assert_almost_eq(_first_texel().a, 0.0, 0.01, "and the layer is clear again")
    assert_eq(doc.history.step_count(), 2, "one history step each")

    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    assert_eq(
        SaShortcutStore.chords_for(&"layer_clear"), ["Backspace", "Delete"] as Array[String], "Sara's own map clears on both"
    )


## The Keyboard Shortcuts page lists both rows with the chord each answers, so
## a painter who reads the page reads what the profile they are on gives.
func test_the_keyboard_shortcuts_page_shows_both_rows_with_their_chords() -> void:
    var page := SaShortcutsPage.new()

    for action: StringName in CHORDS:
        assert_true(SaShortcutRows.actions_for("fill_").has(action), "%s has a row" % action)
        assert_true(
            page.chord_shown(action).contains(CHORDS[action]),
            "%s shows %s: %s" % [action, CHORDS[action], page.chord_shown(action)]
        )
    page.free()
