## The Keyboard Shortcuts page and the store behind it.
##
## Every test here puts the InputMap back the way it found it, because the map
## is global and a suite that rebinds Ctrl+Z and walks away breaks whatever runs
## next.
extends "res://tests/test_framework.gd"

static var scratch_dir: String = SaDataRoot.path("test_shortcut_profiles")

## Built first, the way `core/registry/tests/test_rebind_survives.gd` builds it and for the
## same reason: `project.godot` carries `edit_undo` and the tool keys, and
## `view_zoom_in` is the router's own command and reaches the `InputMap` through
## the registry. The row this suite asserts about is the zoom's, which answers
## three chords.
const Fixtures = preload("res://tests/fixtures.gd")

## Whether the app's commands are in the `InputMap` already. Once per run: the
## actions outlive the registry, and a second registration of an id is refused.
var _commands_built: bool = false

## The events themselves, not their text. Restoring from text would rewrite a
## physically bound key as a keycode one, and the tool machine's Alt and Space
## quick-switches read the physical key: putting the map back the wrong way made
## every tool test fail with 'pan'.
var _saved_events: Dictionary = {}


## `main.gd`'s startup as far as the `InputMap` is concerned. The router is what
## registers the view commands, so a registry built without one has the
## application's commands and none of those.
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
    # Before the events are saved, or the restore puts back an InputMap that
    # never had these actions in it.
    _build_app_commands()
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    SaShortcutStore.dir_override = scratch_dir


func after_each() -> void:
    ShortcutRouter.capture_in_progress = false
    for action: StringName in _saved_events:
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)
    SaShortcutStore.dir_override = ""
    var dir := DirAccess.open(scratch_dir)
    if dir != null:
        for file: String in dir.get_files():
            dir.remove(file)


## The chord text a painter reads has to come back as the event it stands for,
## or a profile file is a one-way trip.
func test_a_chord_reads_back_as_the_event_it_names() -> void:
    for text: String in ["Ctrl+Z", "Ctrl+Shift+Z", "Ctrl+[", "]", "F5", "Shift+B"]:
        var event := SaShortcutStore.parse_chord(text)
        assert_not_null(event, "'%s' reads as an event" % text)
        assert_eq(SaShortcutStore.chord_text(event), text, "and writes back as itself")
    assert_null(SaShortcutStore.parse_chord("not a key"), "and nonsense reads as nothing")
    assert_null(SaShortcutStore.parse_chord(""), "as does an empty chord")

    # A profile saved before the square brackets were bound by glyph holds Godot's word for the bracket, and has to
    # keep opening. It comes back as the glyph, which is the one spelling the
    # file is written in from now on.
    var old_spelling := SaShortcutStore.parse_chord("Ctrl+BracketLeft")
    assert_not_null(old_spelling, "the word a saved profile holds still reads")
    assert_eq(SaShortcutStore.chord_text(old_spelling), "Ctrl+[", "and writes back as the glyph")


func test_a_rebind_moves_what_the_app_answers_to() -> void:
    var before := SaShortcutStore.chords_for(&"edit_undo")
    assert_eq(before, ["Ctrl+Z"] as Array[String], "Undo starts on Ctrl+Z")

    SaShortcutStore.set_chords(&"edit_undo", ["Ctrl+Y"])
    assert_eq(SaShortcutStore.chords_for(&"edit_undo"), ["Ctrl+Y"] as Array[String], "and moves to Ctrl+Y")
    assert_true(
        InputMap.action_has_event(&"edit_undo", SaShortcutStore.parse_chord("Ctrl+Y")),
        "The InputMap itself answers to the new key, which is what makes it real"
    )
    assert_false(InputMap.action_has_event(&"edit_undo", SaShortcutStore.parse_chord("Ctrl+Z")), "and not to the old one")


## The menu entry and the toolbox tooltip both read the InputMap, so a rebind
## has to show in both without either being told about it.
func test_a_rebind_moves_the_menu_text() -> void:
    var registry := SaCommandRegistry.new()
    var descriptor := SaCommandDescriptor.new()
    descriptor.id = &"test_rebind_command"
    descriptor.title = "Rebind me"
    descriptor.action = &"edit_undo"
    registry.register(descriptor)

    assert_eq(registry.chord_text(&"test_rebind_command"), "Ctrl+Z", "The command reads its chord off the InputMap")
    SaShortcutStore.set_chords(&"edit_undo", ["Ctrl+Y"])
    assert_eq(registry.chord_text(&"test_rebind_command"), "Ctrl+Y", "and reads the new one with nothing rebuilt")

    var menu := SaMenu.new(SaChoicePopup.new())
    menu.commands = registry
    assert_eq(menu.chorded("Undo", &"test_rebind_command"), "Undo (Ctrl+Y)", "so the menu entry says the new chord")
    menu.popup.free()


func test_a_conflict_is_named_rather_than_refused() -> void:
    SaShortcutStore.set_chords(&"edit_redo", ["Ctrl+Z"])
    var clashing := SaShortcutStore.conflicts("Ctrl+Z", &"edit_redo")
    assert_true(clashing.has("edit_undo"), "Redo on Undo's chord names Undo as the collision")
    var all := SaShortcutStore.all_conflicts()
    assert_true(all.has("edit_undo") and all.has("edit_redo"), "and both rows are marked, not only the one that moved")

    SaShortcutStore.set_chords(&"edit_redo", ["Ctrl+Shift+Z"])
    var cleared := SaShortcutStore.all_conflicts()
    assert_false(cleared.has("edit_undo"), "Moving it off again clears the mark on Undo")
    assert_false(cleared.has("edit_redo"), "and on Redo")
    assert_true(
        SaShortcutStore.conflicts("Ctrl+Z", &"edit_redo").has("edit_undo"),
        "though asking who holds Ctrl+Z still names Undo, which is what holds it"
    )


## A profile stores only what differs from the shipped map, so a build that
## adds a command gives the painter its chord rather than leaving it unbound.
##
## On a chord nothing else holds. Ctrl+Y is the proof's, and a chord
## shared with another command is saved beside that command, so the profile
## gives the clash back as it was rather than taking the key off the proof.
func test_a_profile_stores_only_the_differences() -> void:
    SaShortcutStore.capture_defaults()
    SaShortcutStore.set_chords(&"edit_undo", ["Ctrl+Alt+F9"])
    assert_eq(SaShortcutStore.save_profile("Mine"), 1, "One action differs, so one is written")

    var stored := SaShortcutStore.load_profile("Mine")
    assert_eq(stored.keys(), ["edit_undo"], "and it is the one that moved")
    assert_eq(stored["edit_undo"], ["Ctrl+Alt+F9"] as Array[String], "with the chord it moved to")

    SaShortcutStore.set_chords(&"edit_undo", ["Ctrl+Z"])
    SaShortcutStore.apply_profile("Mine")
    assert_eq(SaShortcutStore.chords_for(&"edit_undo"), ["Ctrl+Alt+F9"] as Array[String], "Applying it puts the chord back")

    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    assert_eq(SaShortcutStore.chords_for(&"edit_undo"), ["Ctrl+Z"] as Array[String], "and the shipped profile undoes it")

    assert_true(SaShortcutStore.list_profiles().has("Mine"), "The saved profile is offered")
    assert_eq(SaShortcutStore.list_profiles()[0], SaShortcutStore.DEFAULT_PROFILE, "with the shipped one first")
    assert_false(SaShortcutStore.delete_profile(SaShortcutStore.DEFAULT_PROFILE), "A shipped profile cannot be deleted")
    assert_true(SaShortcutStore.delete_profile("Mine"), "and a saved one can")


## What a restart does: the settings name a profile, the InputMap is rebuilt
## from `project.godot`, and `apply_active` lays the profile back over it. The
## suite cannot restart, so it does what a restart does.
func test_a_changed_chord_survives_a_restart() -> void:
    SaShortcutStore.capture_defaults()
    var page := SaShortcutsPage.new()
    page.rebind(&"edit_undo", "Ctrl+Y")
    SaShortcutStore.save_profile("Restarted")
    SaSettings.shortcuts_profile = "Restarted"
    page.free()

    # What the next launch starts from.
    SaShortcutStore.set_chords(&"edit_undo", ["Ctrl+Z"])
    SaShortcutStore.apply_active()
    assert_eq(SaShortcutStore.chords_for(&"edit_undo"), ["Ctrl+Y"] as Array[String], "The chord is back after the restart")

    SaSettings.shortcuts_profile = "default"
    SaShortcutStore.delete_profile("Restarted")


## The shipped map collides with nothing, which it did not always: E activated
## the eraser tool and also toggled the brush's eraser, and this case pinned
## that pair as the map's one collision. The two are now declared one gesture, since
## `ui/shortcuts/shortcut_router.gd` answers them in a single branch and a painter has
## nothing to act on. Kept as the opposite claim rather than deleted, so the day
## a chord really does land on two commands, this says so.
func test_the_shipped_map_has_no_collision_left() -> void:
    var clashes := SaShortcutStore.all_conflicts()
    assert_eq(clashes.keys().size(), 0, "Nothing in the shipped map clashes: %s" % str(clashes.keys()))


## The page itself: what a click on a row ends in, and what the search hides.
func test_the_page_rebinds_marks_and_resets() -> void:
    SaShortcutStore.capture_defaults()
    var page := SaShortcutsPage.new()

    assert_eq(page.chord_shown(&"edit_undo"), "Ctrl+Z", "The row shows the chord the action answers to")
    page.rebind(&"edit_undo", "Ctrl+Y")
    assert_eq(page.chord_shown(&"edit_undo"), "Ctrl+Y", "A rebind moves the row's button")
    assert_eq(SaShortcutStore.chords_for(&"edit_undo"), ["Ctrl+Y"] as Array[String], "and the InputMap under it")

    page.rebind(&"edit_redo", "Ctrl+Y")
    var marked := page.conflicting_actions()
    assert_true(marked.has(&"edit_undo"), "Two commands on one chord marks the first row")
    assert_true(marked.has(&"edit_redo"), "and the second")

    page.reset_action(&"edit_undo")
    assert_eq(page.chord_shown(&"edit_undo"), "Ctrl+Z", "Reset puts the shipped chord back")
    assert_false(page.conflicting_actions().has(&"edit_undo"), "and the mark goes with it")

    page.free()


## A row shows every chord its command answers, the numpad ones
## named as the numpad's, and a rebind replaces the chord clicked and keeps the
## others. Zoom in is the row that could read as a chord and a half: it prints
## Ctrl+Equal and leaves Ctrl+Plus and the numpad's plus invisible.
func test_a_row_shows_every_chord_and_a_rebind_keeps_the_others() -> void:
    SaShortcutStore.capture_defaults()
    var page := SaShortcutsPage.new()
    var shipped := ["Ctrl+=", "Ctrl++", "Ctrl+Numpad +"] as Array[String]
    assert_eq(page.chords_shown(&"view_zoom_in"), shipped, "The zoom row shows all three chords, the numpad's among them")

    page.rebind(&"view_zoom_in", "Ctrl+Alt+I", 1)
    assert_eq(
        page.chords_shown(&"view_zoom_in"),
        ["Ctrl+=", "Ctrl+Alt+I", "Ctrl+Numpad +"] as Array[String],
        "A rebind of the Plus button replaces that chord and leaves the numpad's"
    )
    assert_eq(SaShortcutStore.chords_for(&"view_zoom_in").size(), 3, "and the InputMap holds all three")

    page.reset_action(&"view_zoom_in")
    assert_eq(page.chords_shown(&"view_zoom_in"), shipped, "Reset brings back every shipped chord, not only the first")
    page.free()
    SaSettings.shortcuts_profile = SaShortcutStore.DEFAULT_PROFILE


func test_the_search_hides_the_rows_that_do_not_match() -> void:
    var page := SaShortcutsPage.new()
    page.search.text = "undo"
    page.search.text_changed.emit("undo")
    var host: VBoxContainer = page.find_child("ShortcutRows", true, false)
    assert_not_null(host, "The rows have a host")
    assert_true(page.chord_shown(&"edit_undo") != "", "Undo's row is still there")

    var shown := 0
    for section in host.get_children():
        if (section as Control).visible:
            shown += 1
    assert_true(shown >= 1, "and at least the section holding it is shown")
    assert_true(shown < host.get_child_count(), "while the sections with no match are hidden")

    page.search.text = ""
    page.search.text_changed.emit("")
    for section in host.get_children():
        assert_true((section as Control).visible, "Clearing the search brings every section back")

    page.free()


## The square brackets change the brush size by increments, and a painter
## searches for them by those words. The rows are labelled "Larger brush" and
## "Smaller brush", so the search has to reach a row by what the action does.
func test_the_search_reaches_a_row_by_what_the_action_is_called() -> void:
    var page := SaShortcutsPage.new()
    for needle: String in ["size", "brush size"]:
        page.filter(needle)
        assert_true(page.row_shown(&"brush_size_increase"), "'%s' finds the larger brush row" % needle)
        assert_true(page.row_shown(&"brush_size_decrease"), "'%s' finds the smaller brush row" % needle)
    page.filter("larger")
    assert_true(page.row_shown(&"brush_size_increase"), "and the label still finds its own row")
    assert_false(page.row_shown(&"brush_size_decrease"), "without dragging the other one in")
    page.free()


func _key(keycode: Key, ctrl: bool = false) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.ctrl_pressed = ctrl
    event.pressed = true
    return event


## Setting a shortcut to Ctrl+N, which is already in use, must not execute the
## action of opening a new document instead of just setting the shortcut.
##
## A window emits `window_input` before it pushes the event into its own tree,
## so the router had already answered Ctrl+N by the time the row saw it. The
## page stands the router down for exactly as long as a row is waiting, and the
## capture in scenarios/shortcut-capture.json is what shows it in the app.
func test_a_listening_row_stands_the_router_down() -> void:
    SaShortcutStore.capture_defaults()
    var page := SaShortcutsPage.new()
    var router := ShortcutRouter.new()
    var opened: Array = []
    router.file_command = func(action: StringName) -> void: opened.append(action)

    assert_false(ShortcutRouter.capture_in_progress, "Nothing is listening to start with")
    assert_true(router.handle(_key(KEY_N, true)), "so Ctrl+N is the router's")

    page.begin_capture(&"edit_copy")
    assert_eq(page.listening, &"edit_copy", "A row asked for a key is waiting for one")
    assert_true(ShortcutRouter.capture_in_progress, "and the router stands down")
    router.handle_viewport_input(_key(KEY_N, true), null)
    router.handle_docker_input(_key(KEY_N, true), null)
    assert_eq(opened, [&"file_new"], "so the second Ctrl+N opens nothing, only the first one did")

    page._input(_key(KEY_N, true))
    assert_eq(page.listening, &"", "the row stopped waiting")
    assert_false(ShortcutRouter.capture_in_progress, "and the router answers again")
    # New holds Ctrl+N, so the page asks before it moves the key.
    assert_not_null(page.question, "The key that landed asks first, since New holds it")
    page.question.buttons[SaShortcutsPage.ANSWER_MOVE].pressed.emit()
    assert_eq(page.chord_shown(&"edit_copy"), "Ctrl+N", "and moved, it became the row's chord")

    router.free()
    page.free()


## A modifier on its own is the painter still reaching for the key, so the row
## keeps waiting and the router keeps standing down.
func test_a_modifier_alone_does_not_end_the_capture() -> void:
    var page := SaShortcutsPage.new()
    page.begin_capture(&"edit_copy")
    page._input(_key(KEY_CTRL))
    assert_eq(page.listening, &"edit_copy", "Ctrl alone leaves the row waiting")
    assert_true(ShortcutRouter.capture_in_progress, "so the router is still standing down")
    page._input(_key(KEY_ESCAPE))
    assert_eq(page.listening, &"", "Escape ends it")
    assert_false(ShortcutRouter.capture_in_progress, "and hands the keys back")
    page.free()


## A capture the painter walks away from must not leave the app deaf: switching
## Preferences page frees the row that was waiting.
func test_leaving_the_page_hands_the_keys_back() -> void:
    # `_exit_tree` is called rather than reached, because the suite runs from
    # `_ready` and a parent setting up its children refuses an `add_child`.
    var page := SaShortcutsPage.new()
    page.begin_capture(&"edit_copy")
    assert_true(ShortcutRouter.capture_in_progress, "The row is waiting")
    page._exit_tree()
    assert_false(ShortcutRouter.capture_in_progress, "and leaving the tree ends it")
    page.free()


## Rows are sorted by importance and into sections.
##
## The order inside a section is not `InputMap.get_actions()`, which is
## registration order, so the Dockers section opened on Info: the
## action is named the other way round and is declared first. The ORDER table
## is the order now, and an action not in it follows by its identifier.
func test_the_rows_follow_the_labels_table_rather_than_the_input_map() -> void:
    var ranks: Array = SaShortcutRows.ORDER
    for group: Array in SaShortcutsPage.GROUPS:
        var actions := SaShortcutsPage.actions_for(String(group[0]))
        var last := -1
        for action: StringName in actions:
            var rank: int = ranks.find(action)
            if rank < 0:
                continue
            assert_true(rank > last, "%s: %s comes after what the table puts before it" % [group[1], action])
            last = rank
    var dockers := SaShortcutsPage.actions_for("docker_")
    assert_eq(dockers[0], &"docker_toolbox", "so the Dockers section opens on the Toolbox: %s" % str(dockers))


## Reset on a row already at its default chord, and Delete on the
## shipped profile, did nothing when pressed. Each is dimmed on the check its
## handler makes, and a changed chord lights both: the row's Reset, and Delete
## because the change forked a profile of the painter's own.
func test_reset_and_delete_are_dimmed_until_there_is_something_to_undo() -> void:
    SaShortcutStore.capture_defaults()
    var was_profile := SaSettings.shortcuts_profile
    SaSettings.shortcuts_profile = SaShortcutStore.DEFAULT_PROFILE
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    var page := SaShortcutsPage.new()

    var reset := page.find_child("Reset_edit_undo", true, false) as Button
    assert_true(reset.disabled, "A row at its shipped chord offers no Reset")
    assert_true(page.delete_button.disabled, "and the shipped profile offers no Delete")

    page.rebind(&"edit_undo", "Ctrl+Y")
    reset = page.find_child("Reset_edit_undo", true, false) as Button
    assert_false(reset.disabled, "A changed chord lights its Reset")
    assert_false(SaShortcutStore.is_shipped(page.active_profile()), "the change forked a profile of the painter's")
    assert_false(page.delete_button.disabled, "which Delete can remove")

    page.reset_action(&"edit_undo")
    reset = page.find_child("Reset_edit_undo", true, false) as Button
    assert_true(reset.disabled, "A reset row dims its Reset again")

    page.free()
    SaSettings.shortcuts_profile = was_profile


## The row a gesture of `SaShortcutRows.GESTURES` is filed under on the page.
func _gesture_row(gesture: Array) -> StringName:
    return StringName(SaShortcutsPage.FIXED_KEY + String(gesture[1]).to_snake_case())


## A search for "ctrl+j" must not leave a blank page because the
## search read a row's name and never the keys it shows. Layer via Copy holds
## Ctrl+J, so the search finds it however the chord is
## typed, and Undo, on Ctrl+Z, stays out.
func test_a_search_for_a_chord_finds_the_command_on_it() -> void:
    SaShortcutStore.capture_defaults()
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    var page := SaShortcutsPage.new()
    assert_true(page.chords_shown(&"layer_via_copy").has("Ctrl+J"), "Layer via Copy is on Ctrl+J")
    for needle: String in ["ctrl+j", "Ctrl+J", "ctrl + j"]:
        page.filter(needle)
        assert_true(page.row_shown(&"layer_via_copy"), "'%s' finds Layer via Copy" % needle)
        assert_false(page.row_shown(&"edit_undo"), "'%s' leaves Undo out" % needle)
        assert_false(page.nothing_matches.visible, "'%s' says nothing about no match" % needle)
    for needle: String in ["ctrl", "ctrl+"]:
        page.filter(needle)
        assert_true(
            page.row_shown(&"edit_undo") and page.row_shown(&"layer_via_copy"), "'%s' finds the rows held with Ctrl" % needle
        )
        assert_false(page.row_shown(&"tool_marquee"), "'%s' leaves out the Marquee, on a bare M" % needle)
    page.free()


## A search for "m" must not list every row whose name has an m in it. One character
## is a key, so it shows exactly the rows with a chord on M, and Zoom In, whose
## name holds the letter, is not one.
func test_a_lone_letter_finds_the_rows_on_that_key() -> void:
    SaShortcutStore.capture_defaults()
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    var page := SaShortcutsPage.new()
    page.filter("m")
    var on_m := 0
    for action: StringName in page._chord_buttons:
        var on_key := false
        for chord: String in page.chords_shown(action):
            on_key = on_key or chord.substr(SaCommandRegistry.key_name_at(chord)) == "M"
        assert_eq(page.row_shown(action), on_key, "'m' shows %s exactly when one of its keys is M" % action)
        on_m += 1 if on_key else 0
    assert_true(on_m > 0, "and some row is on M")
    assert_false(page.row_shown(&"view_zoom_in"), "Zoom In is left out")
    for gesture: Array in SaShortcutRows.GESTURES:
        assert_false(page.row_shown(_gesture_row(gesture)), "'m' is not the m of %s" % gesture[0])
    page.free()


## A search for "drag" must find the four Gestures rows that show a drag,
## so a fixed row is searched by the keys it shows as well as its words. "shift" finds the Shift drag, and
## "fixed", the start of the key the page files it under, finds none.
func test_a_search_for_drag_finds_the_gestures_that_are_drags() -> void:
    var page := SaShortcutsPage.new()
    page.filter("drag")
    for gesture: Array in SaShortcutRows.GESTURES:
        var is_drag := String(gesture[0]).contains("drag")
        assert_eq(page.row_shown(_gesture_row(gesture)), is_drag, "'drag' and %s" % gesture[0])
    assert_false(page.nothing_matches.visible, "'drag' says nothing about no match")
    page.filter("shift")
    assert_true(page.row_shown(_gesture_row(SaShortcutRows.GESTURES[2])), "'shift' finds the Shift drag")
    page.filter("tab")
    assert_true(page.row_shown(StringName(SaShortcutsPage.FIXED_KEY + "hide_or_show_every_docker")), "'tab' finds Tab's row")
    page.filter("fixed")
    for gesture: Array in SaShortcutRows.GESTURES:
        assert_false(page.row_shown(_gesture_row(gesture)), "'fixed' does not find %s" % gesture[0])
    page.free()


## A search that matches nothing says so rather than leaving a blank page. The line says it, and goes when the search is cleared.
func test_a_search_with_no_match_says_nothing_matches() -> void:
    var page := SaShortcutsPage.new()
    page.filter("")
    assert_false(page.nothing_matches.visible, "Nothing typed says nothing")
    page.filter("qzxwv")
    assert_true(page.nothing_matches.visible, "A word no row holds says so")
    assert_eq(page.nothing_matches.text, "Nothing matches", "in those words")
    for title: String in page._section_boxes:
        assert_false((page._section_boxes[title] as Control).visible, "with the %s section hidden" % title)
    page.filter("")
    assert_false(page.nothing_matches.visible, "and clearing the search takes the line away")
    page.free()


## Keys are spelt one way on the page, not two like "Ctrl+Comma"
## against "Ctrl+=". No chord on the page names a key by Godot's word for one
## `KEY_GLYPHS` spells, and the five that joined the table at this row read as
## their glyphs. The backslash keeps its word, because a bare "\" reads as no
## key at all.
func test_every_chord_on_the_page_is_spelt_one_way() -> void:
    SaShortcutStore.capture_defaults()
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    var page := SaShortcutsPage.new()
    var words := {}
    for code: int in SaCommandRegistry.KEY_GLYPHS:
        words[OS.get_keycode_string(code as Key)] = true
    var read := 0
    for action: StringName in page._chord_buttons:
        for chord: String in page.chords_shown(action):
            read += 1
            var key_name := chord.substr(SaCommandRegistry.key_name_at(chord))
            assert_false(words.has(key_name), "%s reads %s and not Godot's word for the key" % [action, chord])
    assert_true(read > 50, "every chord on the page was read, %d of them" % read)
    assert_true(page.chords_shown(&"edit_preferences").has("Ctrl+,"), "Preferences reads Ctrl+,")
    assert_true(page.chords_shown(&"view_zoom_in").has("Ctrl+="), "beside the zoom's Ctrl+=")
    var glyphs := {KEY_COMMA: ",", KEY_PERIOD: ".", KEY_SLASH: "/", KEY_SEMICOLON: ";", KEY_APOSTROPHE: "'"}
    for code: int in glyphs:
        assert_eq(
            SaCommandRegistry.key_text(_key(code as Key, true)), "Ctrl+" + String(glyphs[code]), "%s is its glyph" % glyphs[code]
        )
    assert_eq(
        SaCommandRegistry.key_text(_key(KEY_BACKSLASH, true)),
        "Ctrl+" + OS.get_keycode_string(KEY_BACKSLASH),
        "and the backslash its word"
    )
    page.free()
