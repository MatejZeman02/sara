## The chords the menus draw, across all eleven of them: each row draws the
## chord of the key that works.
extends "res://tests/test_framework.gd"

## What the File menu binds, and the chord each row is supposed to draw.
const FILE_ROWS := {
    &"file_new": "Ctrl+N",
    &"file_open": "Ctrl+O",
    &"file_save": "Ctrl+S",
    &"file_save_as": "Ctrl+Shift+S",
    &"ui_quit": "Ctrl+Q",
}


func _source(path: String) -> String:
    var file := FileAccess.open(path, FileAccess.READ)
    return file.get_as_text() if file != null else ""


## The body of `func <name>`, up to the next declaration.
func _body_of(source: String, name: String) -> String:
    var at := source.find("func %s(" % name)
    if at == -1:
        return ""
    var end := source.find("\nfunc ", at + 1)
    return source.substr(at, (end - at) if end != -1 else -1)


## A `Shortcut` built from an action's raw events, which is what a menu row
## draws when nobody has thought about it.
func _raw_accel(action: StringName) -> String:
    var shortcut := Shortcut.new()
    shortcut.events = InputMap.action_get_events(action)
    return shortcut.get_as_text()


## A `Shortcut` built the way `SaMenu.action_chord` builds its list: a keycode
## twin in front of each physical binding, so the text reads the way Sara
## spells a chord everywhere else.
func _twinned_accel(action: StringName) -> String:
    var events: Array[InputEvent] = []
    for event: InputEvent in InputMap.action_get_events(action):
        var key := event as InputEventKey
        if key == null or key.keycode != KEY_NONE or key.physical_keycode == KEY_NONE:
            continue
        var twin := key.duplicate() as InputEventKey
        twin.keycode = key.physical_keycode
        twin.physical_keycode = KEY_NONE
        events.append(twin)
    events.append_array(InputMap.action_get_events(action))
    var shortcut := Shortcut.new()
    shortcut.events = events
    return shortcut.get_as_text()


func test_a_physical_binding_reads_as_physical_until_it_is_twinned() -> void:
    for action: StringName in FILE_ROWS:
        assert_true(InputMap.has_action(action), "%s is an action this build ships" % action)
        assert_true(
            _raw_accel(action).ends_with(" - Physical"),
            "%s is bound by physical keycode, so a raw Shortcut says so out loud" % action
        )


func test_the_twin_is_what_makes_the_text_read_like_a_chord() -> void:
    for action: StringName in FILE_ROWS:
        assert_eq(
            _twinned_accel(action),
            String(FILE_ROWS[action]),
            "%s reads as a plain chord once a keycode twin leads the list" % action
        )


## **The twinning is `SaMenu.action_chord` and there is one copy of it** (`MainDockers._menu_events` and
## `SaFileMenu._menu_events` were the
## same nine lines twice over, each building a `Shortcut` for a row that fired
## it, and a row of `SaChoicePopup` draws words and fires nothing. So both
## copies went and the two menus ask the one function for the words.
##
## Asserted as an answer rather than as source text, which the two tests this
## replaces could not do: a `Shortcut`'s text was only readable off a row, and a
## string is readable anywhere.
func test_the_menus_twin_their_events_through_one_function() -> void:
    for action: StringName in FILE_ROWS:
        assert_eq(
            SaMenu.action_chord(action),
            String(FILE_ROWS[action]),
            "%s reads as a plain chord rather than as a physical binding" % action
        )
    assert_eq(SaMenu.action_chord(&"nothing_is_bound_to_this"), "", "and an action nobody bound reads as nothing")


## f30, fixed. The File menu handed the raw events to a row, so New, Open File,
## Save, Save As and Quit each drew "Ctrl+N - Physical" and the rest. Every one
## of them is now the hint `action_chord` writes, read off the rows a bound bar
## draws, since each row is its command and asks `chord_of` for the chord.
func test_the_file_menu_rows_carry_the_plain_chord() -> void:
    var bar := _bound_bar()
    var ids := {
        &"file_new": SaFileMenu.ID_NEW,
        &"file_open": SaFileMenu.ID_OPEN,
        &"file_save": SaFileMenu.ID_SAVE,
        &"file_save_as": SaFileMenu.ID_SAVE_AS,
        &"ui_quit": SaFileMenu.ID_QUIT,
    }
    var hints := _hints(bar.menus["File"])
    for action: StringName in FILE_ROWS:
        var hint: String = hints.get(String(SaMenu.key(ids[action])), "")
        assert_eq(hint, String(FILE_ROWS[action]), "%s is the hint on its own row" % action)
    bar.free()


## Both rows draw their chord, as their siblings do, not as bare text.
func test_the_edit_menu_shows_the_undo_chord() -> void:
    var bar := _bound_bar()
    var hints := _hints(bar.menus["Edit"])
    assert_eq(hints.get(String(SaMenu.key(SaEditMenu.ID_UNDO)), ""), "Ctrl+Z", "The Undo row draws its chord")
    assert_eq(hints.get(String(SaMenu.key(SaEditMenu.ID_REDO)), ""), "Ctrl+Shift+Z", "and so does Redo")
    bar.free()


## A bar bound to every command the menus list, the way main binds it.
func _bound_bar() -> TopMenuBar:
    var bar := TopMenuBar.new()
    bar._ready()
    bar.bind_commands(SaTestFixtures.make_menu_registries().commands)
    return bar


## Row key -> the words at the row's right, where a chord goes.
func _hints(popup: SaChoicePopup) -> Dictionary:
    var out := {}
    for entry: Dictionary in popup.row_report():
        out[String(entry.get("id", ""))] = String(entry.get("hint", ""))
    return out


## The other half: the chord a row draws is the one the router answers
## on, because `chorded()` reads the same input map rather than a second copy.
func test_undo_and_redo_are_bound_and_their_rows_read_the_binding() -> void:
    for action: StringName in [&"edit_undo", &"edit_redo"]:
        assert_true(InputMap.has_action(action), "%s exists" % action)
        assert_false(InputMap.action_get_events(action).is_empty(), "and answers to a key")
    assert_eq(SaCommandRegistry.format_events(InputMap.action_get_events(&"edit_undo")), "Ctrl+Z", "Undo reads Ctrl+Z")
    assert_eq(
        SaCommandRegistry.format_events(InputMap.action_get_events(&"edit_redo")),
        "Ctrl+Shift+Z",
        "and Redo Ctrl+Shift+Z, with no ' - Physical' on either, both being bound by physical keycode"
    )


## The fallback is the registry's second choice, never its first, so a command
## that does have an entry keeps drawing what the entry says.
func test_a_registered_command_still_reads_from_the_registry() -> void:
    var registry := SaCommandRegistry.new()
    var descriptor := SaCommandDescriptor.new()
    descriptor.id = &"t4_probe_command"
    descriptor.title = "Probe"
    var event := InputEventKey.new()
    event.keycode = KEY_F9
    descriptor.default_events = [event]
    registry.register(descriptor)

    assert_eq(registry.chord_text(&"t4_probe_command"), "F9", "The registry answers from the descriptor")
    assert_false(InputMap.has_action(&"t4_probe_command"), "and the input map has never heard of it")


## Nothing else on the eleven menus loses the chord it had, which is the half of
## the Edit menu's chords that a fallback could quietly break: it only ever adds.
func test_the_fallback_only_adds() -> void:
    # `chord_of`, which `chorded` calls: a row draws the chord in
    # its own column, so the words and the joined string are two callers of one
    # answer rather than one function doing both.
    var source := _source("res://ui/menus/sa_menu.gd")
    var body := _body_of(source, "chord_of")
    assert_true(body.contains("commands.chord_text(command_id, 1)"), "The registry is asked first")
    assert_true(body.contains("InputMap.has_action(command_id)"), "and the input map only when it answered nothing")
    assert_true(_body_of(source, "chorded").contains("return text"), "and a command that answers to nothing keeps its bare text")
