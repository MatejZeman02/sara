## Import from Krita reads every key name Krita writes.
##
## Importing Krita's stock chords must not leave Move layer
## up and down reading "Ctrl+(unset)" in the clash colour, Ctrl+PageUp moving
## nothing, and the ghost still on both rows back on Sara Default. Godot's
## `OS.find_keycode_from_string` answers "Ctrl+PgUp" with the Ctrl bit alone,
## `parse_chord` kept an event holding no key, and `action_erase_event` never
## matched it again. The suite imports the same fixture, a file holding what
## the stock fixture does not, and Krita's spellings one by one.
##
## It builds the app's own commands first, the way
## `core/registry/tests/test_the_numpad_chords_in_two_steps.gd` does and for the
## reason that suite gives: the layer and zoom actions reach the `InputMap`
## through the registry.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Krita 5.2.13's stock chords as the page is fed them.
const STOCK: String = "res://scenarios/fixtures/krita-stock.shortcuts"

static var scratch_dir: String = SaDataRoot.path("test_import_from_krita_reads_every_key_name_krita_writes")

## The base module as well, through the door the app uses, because now an
## import reads the Krita table, which names four of its filters. Without it
## the stock import wrote their chords into actions no command had made, and
## back on Sara Default they read as differences from the shipped map.
const BASE_MODULE := "res://modules/sara-base-modules/base/module.gd"
var _base: SaModule = null
var _context: SaContext = null

var _saved_events: Dictionary = {}
var _saved_actions: Array[StringName] = []
var _saved_profile: String = ""
var _commands_built: bool = false
var _notices: Array[String] = []


func _build_app_commands() -> void:
    if _commands_built:
        return
    _commands_built = true
    var registries := Fixtures.make_registries()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    var router := ShortcutRouter.new()
    router.bind_commands(registries.commands)
    router.free()


func before_each() -> void:
    _build_app_commands()
    var registries := Fixtures.make_registries()
    _base = load(BASE_MODULE).new()
    _base.register(registries.context.for_module(_base.get_id()))
    _context = registries.context
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    _saved_actions.assign(InputMap.get_actions())
    _saved_profile = SaSettings.shortcuts_profile
    SaShortcutStore.dir_override = scratch_dir
    SaShortcutStore.capture_defaults()
    SaSettings.shortcuts_profile = SaShortcutStore.DEFAULT_PROFILE
    _notices.clear()
    EventBus.corner_notice.connect(_on_notice)


func after_each() -> void:
    EventBus.corner_notice.disconnect(_on_notice)
    _base.unregister(_context)
    _base = null
    _context = null
    for action: StringName in _saved_events:
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)
    for action: StringName in InputMap.get_actions():
        if not _saved_actions.has(action):
            InputMap.erase_action(action)
    SaSettings.shortcuts_profile = _saved_profile
    SaShortcutStore.dir_override = ""
    var dir := DirAccess.open(scratch_dir)
    if dir != null:
        for file: String in dir.get_files():
            dir.remove(file)


func _on_notice(line: String) -> void:
    _notices.append(line)


## A `.shortcuts` file in the scratch folder holding *lines* under the section.
func _export(file_name: String, lines: Array[String]) -> String:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var path := scratch_dir.path_join(file_name)
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string("[Shortcuts]\n" + "\n".join(lines) + "\n")
    file.close()
    return path


## Every chord the InputMap holds that names no key, as "action: text".
func _ghosts() -> Array[String]:
    var out: Array[String] = []
    for action: StringName in InputMap.get_actions():
        for event: InputEvent in InputMap.action_get_events(action):
            var key := event as InputEventKey
            if key != null and key.keycode == KEY_NONE and key.physical_keycode == KEY_NONE:
                out.append("%s: %s" % [action, SaShortcutStore.chord_text(key)])
    return out


## The first half of the case: the stock fixture puts Krita's Ctrl+PageUp and
## Ctrl+PageDown on the two move rows, leaves out nothing, and writes no event
## without a key anywhere in the map.
func test_the_stock_fixture_moves_the_layer_on_ctrl_page_up_and_down() -> void:
    var reading := SaShortcutStore.import_krita(STOCK)

    assert_eq(reading.profile, "krita-stock", "the import is a profile named after the file")
    assert_eq(SaSettings.shortcuts_profile, "krita-stock", "and the active one")
    assert_eq(SaShortcutStore.chords_for(&"layer_move_up"), ["Ctrl+PageUp"] as Array[String], "Move layer up is Ctrl+PageUp")
    assert_eq(
        SaShortcutStore.chords_for(&"layer_move_down"), ["Ctrl+PageDown"] as Array[String], "Move layer down is Ctrl+PageDown"
    )
    assert_eq(reading.unread, {}, "every chord the stock file gives a Sara command reads")
    assert_eq(_ghosts(), [] as Array[String], "and no action holds a modifier with no key")
    var unset: Array[String] = []
    var map := SaShortcutStore.current_map()
    for action: String in map:
        for chord: Variant in map[action]:
            if str(chord).to_lower().contains("unset"):
                unset.append("%s: %s" % [action, chord])
    assert_eq(unset, [] as Array[String], "so no row reads (unset)")


## The second half of the case: back on Sara Default the move rows are the
## shipped ones and nothing differs from the shipped map, so the profile is not
## a fork. And back on the import they are Krita's again.
func test_sara_default_and_back_leave_no_ghost() -> void:
    SaShortcutStore.import_krita(STOCK)
    SaSettings.shortcuts_profile = SaShortcutStore.DEFAULT_PROFILE
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)

    var shipped := SaShortcutStore.defaults()
    assert_eq(SaShortcutStore.chords_for(&"layer_move_up"), shipped["layer_move_up"], "Sara Default moves up on its own chord")
    assert_eq(SaShortcutStore.overrides_now(), {} as Dictionary[String, Array], "and nothing differs from the shipped map")
    assert_eq(_ghosts(), [] as Array[String], "with no keyless event left behind")

    SaSettings.shortcuts_profile = "krita-stock"
    SaShortcutStore.apply_profile("krita-stock")
    assert_eq(
        SaShortcutStore.chords_for(&"layer_move_up"), ["Ctrl+PageUp"] as Array[String], "the import moves up on Ctrl+PageUp"
    )
    assert_eq(_ghosts(), [] as Array[String], "and still holds no ghost")


## An event that names no key is cleared by the next write of its action, the
## mouse binding beside it kept. The ghost an older import left in a launch's
## map goes on the next profile switch.
func test_a_ghost_goes_on_the_next_write_and_a_mouse_binding_stays() -> void:
    var ghost := InputEventKey.new()
    ghost.ctrl_pressed = true
    var wheel := InputEventMouseButton.new()
    wheel.button_index = MOUSE_BUTTON_WHEEL_UP
    InputMap.action_add_event(&"layer_move_up", ghost)
    InputMap.action_add_event(&"layer_move_up", wheel)

    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)

    assert_eq(_ghosts(), [] as Array[String], "the profile switch took the keyless event off")
    var mice := InputMap.action_get_events(&"layer_move_up").filter(
        func(event: InputEvent) -> bool: return event is InputEventMouseButton
    )
    assert_eq(mice.size(), 1, "and kept the wheel")


## Krita's own words for the keys Godot names otherwise, each read with and
## without a modifier.
func test_parse_chord_reads_kritas_key_words() -> void:
    for pair: Array in [
        ["PgUp", KEY_PAGEUP],
        ["PgDown", KEY_PAGEDOWN],
        ["Del", KEY_DELETE],
        ["Ins", KEY_INSERT],
        ["Esc", KEY_ESCAPE],
        ["Return", KEY_ENTER]
    ]:
        var bare := SaShortcutStore.parse_chord(String(pair[0]))
        assert_true(bare != null and bare.keycode == pair[1], "%s reads as its key" % pair[0])
        var held := SaShortcutStore.parse_chord("Ctrl+" + String(pair[0]))
        assert_true(held != null and held.keycode == pair[1] and held.ctrl_pressed, "and Ctrl+%s as Ctrl with it" % pair[0])


## A chord whose modifiers read and whose key does not is nothing, never a
## modifier alone.
func test_a_key_nothing_reads_is_null_whatever_its_modifiers() -> void:
    assert_null(SaShortcutStore.parse_chord("Ctrl+Nothing"), "Ctrl with no key Godot knows is nothing")
    assert_null(SaShortcutStore.parse_chord("Ctrl+Shift+"), "and so is Ctrl+Shift with no key at all")
    assert_null(SaShortcutStore.parse_chord("Ctrl+(unset)"), "and the ghost an older import saved")
    assert_null(SaShortcutStore.parse_chord("\\"), "while a bare backslash stays unread, as the Krita table's suite pins")


## A chord no key reads is left out and named, an action whose chords all fail
## keeps its own chord rather than being cleared, `none` and Krita's two empty
## chords clear, and both separators part alternatives.
func test_an_unread_chord_is_left_out_and_named() -> void:
    var path := _export(
        "mixed.shortcuts",
        (
            [
                "move_layer_up=Ctrl+Nothing",
                "move_layer_down=Ctrl+Nothing; Ctrl+PgDown",
                "remove_layer=none",
                "deselect=;\\s",
                "view_zoom_in=Ctrl+=; Ctrl++",
                "view_zoom_out=Ctrl+-,Ctrl+Num+-",
                "invert_selection=Hyper+I",
            ]
            as Array[String]
        )
    )
    var reading := SaShortcutKritaNames.parse(path)

    assert_false(reading.overrides.has("layer_move_up"), "a command whose one chord fails is left out")
    assert_eq(reading.unread.get("layer_move_up", []), ["Ctrl+Nothing"], "and the chord is named as Krita wrote it")
    assert_eq(reading.overrides.get("layer_move_down", []), ["Ctrl+PageDown"], "one that reads beside one that does not is kept")
    assert_eq(reading.unread.get("layer_move_down", []), ["Ctrl+Nothing"], "and the other named")
    assert_eq(reading.overrides.get("layer_delete", ["?"]), [], "none clears the command")
    assert_eq(reading.overrides.get("select_none", ["?"]), [], "and so do Krita's two empty chords")
    assert_eq(reading.overrides.get("view_zoom_in", []), ["Ctrl+=", "Ctrl++"], "a semicolon and a space part alternatives")
    assert_eq(
        reading.overrides.get("view_zoom_out", []), ["Ctrl+-", "Ctrl+Numpad -"], "and so does a comma, Num being the keypad"
    )
    assert_eq(reading.unread.get("select_invert", []), ["Hyper+I"], "a modifier Godot has no word for is not read as I alone")


## What `import_krita` leaves out the page names in the corner, by the row's
## label and the chord as Krita wrote it.
func test_the_page_names_what_the_import_left_out() -> void:
    var path := _export("left-out.shortcuts", ["move_layer_up=Ctrl+Nothing", "move_layer_down=Ctrl+PgDown"] as Array[String])
    var page := SaShortcutsPage.new()
    page.import_krita_file(path)

    assert_eq(_notices.size(), 1, "one notice: %s" % [_notices])
    if _notices.size() == 1:
        assert_true(_notices[0].contains("Ctrl+Nothing"), "it names the chord: %s" % _notices[0])
        assert_true(_notices[0].contains(SaShortcutsPage.label_for("layer_move_up")), "and the row it was for: %s" % _notices[0])
        assert_false(_notices[0].contains("PageDown"), "and nothing that read")
    assert_eq(SaSettings.shortcuts_profile, "left-out", "the rest is the active profile")
    page.free()


## Qt writes a glyph key as its character and Godot reads it by its word, so
## each one Krita's stock maps hold reads, and a separator is one only where a
## key cannot stand.
func test_kritas_glyph_keys_read_and_stay_one_chord() -> void:
    assert_eq(SaShortcutKritaNames.alternatives(","), [","] as Array[String], "the comma key alone is one chord")
    assert_eq(SaShortcutKritaNames.alternatives("Ctrl+,"), ["Ctrl+,"] as Array[String], "and after a modifier")
    assert_eq(
        SaShortcutKritaNames.alternatives("Ctrl+Shift+;; Ctrl+3"),
        ["Ctrl+Shift+;", "Ctrl+3"] as Array[String],
        "the semicolon key before Krita's separator"
    )
    assert_eq(SaShortcutKritaNames.alternatives("; "), [] as Array[String], "two empty chords are none")
    for pair: Array in [
        [";", "Semicolon"],
        ["\\", "Backslash"],
        [",", "Comma"],
        [".", "Period"],
        ["/", "Slash"],
        ["'", "Apostrophe"],
        ["Ctrl+Shift+;", "Ctrl+Shift+Semicolon"],
        ["Ctrl+<", "Ctrl+Less"],
        ["Num+5", "Numpad 5"],
        ["ctrl+alt+0", "Ctrl+Alt+0"],
        ["Media Play", "MediaPlay"],
    ]:
        var event := SaShortcutStore.parse_chord(SaShortcutKritaNames.sara_spelling(String(pair[0])))
        var wanted := SaShortcutStore.parse_chord(String(pair[1]))
        assert_true(
            event != null and SaShortcutStore.chord_text(event) == SaShortcutStore.chord_text(wanted),
            "%s reads as %s" % [pair[0], pair[1]]
        )
