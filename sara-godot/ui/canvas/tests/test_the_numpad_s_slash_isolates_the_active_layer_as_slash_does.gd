## The numpad's slash isolates the active layer as `/` does.
##
## The command needs both default events, `KEY_SLASH`, and `KEY_KP_DIVIDE`, which
## is the numpad's slash and another keycode. On a Czech keyboard the main
## row's `/` needs Shift, so the numpad is the key a painter reaches.
##
## Every press is a key as a keyboard sends it, through the router over the
## application's whole map. Two layers over a ground, a red square and a green
## blob, the blob's layer active, read off the easel's own output.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

## The proof is the canvas's pixels, which needs a RenderingDevice.
const REQUIRES_GPU := true

const SIZE := Vector2i(512, 512)
const GROUND := Color(0.5, 0.5, 0.5, 1.0)
const RED := Color(0.8, 0.1, 0.1, 1.0)
const GREEN := Color(0.1, 0.8, 0.2, 1.0)
const RED_AT := Rect2i(0, 0, 200, 200)
const BLOB := Rect2i(300, 310, 40, 20)
## Where the red square draws and where the blob does.
const RED_POINT := Vector2i(50, 50)
const BLOB_POINT := Vector2i(310, 315)
## A profile laid over Krita's with the command put on `/`, the way an import
## of a Krita `.shortcuts` file naming it lays one.
const PROFILE := "probe Krita with isolate on slash"

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
    _two()


func after_each() -> void:
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


## A key as a keyboard sends it, the numpad's slash or the main row's.
func _key(keycode: Key) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.key_label = keycode
    event.unicode = "/".unicode_at(0)
    event.pressed = true
    return event


## The ground grey, then a red square and the green blob, each a layer of its
## own, the blob's layer active.
func _two() -> void:
    var doc: SaDocument = _surface.easel.document
    var ops := SaLayerOps.new(doc)
    var stack := ops.layers()
    doc.fill_layer(GROUND, stack[0])
    _paint(stack[1], RED, RED_AT)
    var green := ops.add()
    _paint(green, GREEN, BLOB)
    doc.set_active_layer(green)


func _paint(layer: SaLayer, color: Color, rect: Rect2i) -> void:
    var doc: SaDocument = _surface.easel.document
    doc.selection.select_rect(rect)
    doc.fill_layer(color, layer)
    doc.selection.deselect()


func _at(point: Vector2i) -> Color:
    Bench.composite(_surface.easel)
    return Bench.texel(_surface.easel.output, point)


func _near(a: Color, b: Color, tolerance: float = 0.01) -> bool:
    return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a))) <= tolerance


## One key isolates the blob and the same key again gives the red square back.
func _toggles(keycode: Key, name: String) -> void:
    var doc: SaDocument = _surface.easel.document
    assert_true(_near(_at(RED_POINT), RED), "The red square is drawn before %s" % name)
    assert_true(_router.handle(_key(keycode)), "The router takes %s" % name)
    assert_true(SaLocalView.is_on(doc), "%s isolates the active layer" % name)
    assert_true(_near(_at(BLOB_POINT), GREEN), "The blob is drawn alone after %s" % name)
    assert_true(_at(RED_POINT).a < 0.001, "and the red square is not, after %s" % name)
    assert_true(_router.handle(_key(keycode)), "The router takes %s again" % name)
    assert_false(SaLocalView.is_on(doc), "A second %s ends the isolation" % name)
    assert_true(_near(_at(RED_POINT), RED), "and the red square is drawn again after %s" % name)


func test_the_numpad_s_slash_isolates_and_a_second_press_puts_everything_back() -> void:
    _toggles(KEY_KP_DIVIDE, "the numpad's slash")


func test_the_main_row_s_slash_still_does_the_same() -> void:
    _toggles(KEY_SLASH, "the main row's slash")


## The Shortcuts page lists the chords `chords_for` answers, so the command
## shows on both keys there.
func test_sara_s_own_map_puts_the_command_on_both_slashes() -> void:
    assert_eq(
        SaShortcutStore.chords_for(SaIsolateActiveLayer.COMMAND),
        ["/", "Numpad /"] as Array[String],
        "Isolate Active Layer answers / and the numpad's slash"
    )


## Krita ships the command unbound, and a profile laid over Krita's with the
## command put on `/` keeps the build's numpad twin beside it, the way the zoom
## keeps the numpad's plus.
func test_a_krita_profile_with_the_command_on_slash_keeps_the_numpad_s_slash() -> void:
    var overrides := SaShortcutStore._over_the_krita_profile({"view_isolate_active_layer": ["/"]})
    assert_eq(overrides["view_isolate_active_layer"], ["/", "Numpad /"], "The entry keeps the numpad's slash beside it")
    assert_true(SaShortcutStore.save_overrides(PROFILE, overrides), "The profile is saved")
    SaShortcutStore.apply_profile(PROFILE)
    assert_eq(
        SaShortcutStore.chords_for(SaIsolateActiveLayer.COMMAND),
        ["/", "Numpad /"] as Array[String],
        "Under the profile the command holds both slashes"
    )
    _toggles(KEY_KP_DIVIDE, "the numpad's slash under the profile")
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)


## The plain Krita profile keeps `/` for the previous preset and
## leaves the command the numpad's slash.
func test_the_plain_krita_profile_keeps_only_the_numpad_s_slash() -> void:
    SaShortcutStore.apply_profile("Krita")
    var numpad: Array[String] = ["Numpad /"]
    assert_eq(SaShortcutStore.chords_for(SaIsolateActiveLayer.COMMAND), numpad, "Krita keeps the numpad's slash alone")
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)


func test_same_keys_pairs_slash_asterisk_and_period_with_the_numpad() -> void:
    for pair: Array in [[KEY_SLASH, KEY_KP_DIVIDE], [KEY_ASTERISK, KEY_KP_MULTIPLY], [KEY_PERIOD, KEY_KP_PERIOD]]:
        for keycode: int in pair:
            var same := SaShortcutStore._same_keys(keycode)
            assert_true(same.has(pair[0]) and same.has(pair[1]), "%s is the same key as %s" % pair)
    assert_eq(SaShortcutStore._same_keys(KEY_COMMA), [KEY_COMMA], "and a key with no twin is itself alone")
