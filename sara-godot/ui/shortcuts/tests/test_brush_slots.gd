## The ten brush slots: the page that fills them, the chords that read them
## and the rule for a slot pointing at a preset that is gone.
##
## Two rules are assertions here: the list is one and not one per shortcut
## profile, which is why it is a settings key and why the Photoshop map
## carries no chord for it, and a slot whose preset was deleted loads the
## default brush and names itself.
extends "res://tests/test_framework.gd"

const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")

## The registries the app is built on, so a test that wants the real commands
## does not preload this five times.
const Fixtures = preload("res://tests/fixtures.gd")

const SLOTS := SaSettingsValues.BRUSH_SLOT_COUNT

## Where the fixture library goes, so nothing here writes into the preset
## directory the rest of the suite reads.
static var scratch_fixture_dir: String = SaDataRoot.path("test_brush_slots")


func before_each() -> void:
    _clear_fixture()


func after_each() -> void:
    _clear_fixture()


func _clear_fixture() -> void:
    var dir := DirAccess.open(scratch_fixture_dir)
    if dir == null:
        return
    for file: String in dir.get_files():
        dir.remove(file)


func _fixture_store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_fixture_dir
    DirAccess.make_dir_recursive_absolute(scratch_fixture_dir)
    return store


func _write_preset(store: SaPresetStore, preset_name: String) -> void:
    store.save_preset(preset_name, BrushSettingsScript.new())


func _restore(before: Array) -> void:
    SaSettings.brush_slots = before


func test_preferences_offers_the_page() -> void:
    # The slots are the first part of Brushes.
    assert_true(SaSettingsWindow.FIXED_PAGES.has("Brushes"), "Preferences lists a Brushes category")
    var window := SaSettingsWindow.new()
    var page := window.build_page("Brushes") as SaSettingsWindow.PageParts
    assert_not_null(page, "and building that title gives the page rather than null")
    if page != null:
        assert_true(page.parts[0] is SaBrushSlotsPage, "whose first part is the slots")
        page.free()
    window.free()


## The width is asserted because the first run of the scenario shot ten dropdowns
## with no words on them: `SaChoiceButton` sets `clip_text`, so the label is not
## in the control's minimum size, and this row puts the dropdown in a box beside
## a Clear button rather than handing it to `SaSettingsRows.row` alone.
func test_the_page_is_ten_rows_of_a_dropdown_and_a_clear_button() -> void:
    var page := SaBrushSlotsPage.new(_fixture_store())
    assert_eq(page.pickers.size(), SLOTS, "One dropdown per slot")
    for slot in range(1, SLOTS + 1):
        assert_not_null(page.find_child("BrushSlot%d" % slot, true, false), "Slot %d has its dropdown" % slot)
        assert_not_null(page.find_child("BrushSlotClear%d" % slot, true, false), "and its Clear button")
        assert_true(page.pickers[slot - 1].custom_minimum_size.x > 0.0, "wide enough to read a preset name off")
    page.free()


func test_a_row_offers_the_store_and_picking_one_writes_the_setting() -> void:
    var before: Array = SaSettings.brush_slots.duplicate()
    # Empty slots, because a fresh profile's are filled and
    # a filled slot offers its own name beside the store's.
    SaSettings.brush_slots = SaSettingsBrushSlots.empty()
    var store := _fixture_store()
    _write_preset(store, "Inky")
    _write_preset(store, "Chalk")

    var page := SaBrushSlotsPage.new(store)
    var picker := page.pickers[2]
    assert_eq(picker.choice_values(), ["", "Chalk", "Inky"], "Nothing, and the two presets in the store")
    assert_eq(picker.choice_labels()[0], "Nothing", "with the empty row first")

    assert_true(page.choose(3, "Chalk"), "Slot three offers Chalk")
    assert_eq(SaBrushSlotCommands.preset_for(3), "Chalk", "and picking it writes the slot")
    assert_eq(SaSettings.brush_slots.size(), SLOTS, "The stored list stays ten long")
    assert_eq(String(SaSettings.brush_slots[2]), "Chalk", "with the name in the third place")

    page._on_clear_pressed(3)
    assert_eq(SaBrushSlotCommands.preset_for(3), "", "Clear empties the slot")
    assert_eq(String(picker.selected_value()), "", "and the dropdown goes back to Nothing")
    page.free()
    _restore(before)


## A page that quietly forgot a name it could not offer would be a second way to
## lose a slot, so the row keeps it and says what it is.
func test_a_slot_whose_preset_is_gone_still_reads_its_name_on_the_page() -> void:
    var before: Array = SaSettings.brush_slots.duplicate()
    SaBrushSlotCommands.fill(1, "Departed")
    var page := SaBrushSlotsPage.new(_fixture_store())
    var picker := page.pickers[0]
    assert_eq(picker.text, "Departed (missing)", "The row names it and says it is gone")
    assert_eq(String(picker.selected_value()), "Departed", "and still holds the name underneath")
    assert_eq(SaBrushSlotCommands.preset_for(1), "Departed", "Opening the page rewrites nothing")
    page.free()
    _restore(before)


func test_the_chord_rule_is_the_three_answers() -> void:
    var before: Array = SaSettings.brush_slots.duplicate()
    var store := _fixture_store()
    _write_preset(store, "Inky")
    SaSettings.brush_slots = []

    var empty := SaBrushSlotCommands.slot_action(4, store)
    assert_eq(String(empty["action"]), "none", "A chord whose slot is empty does nothing")
    assert_eq(String(empty["message"]), "", "and says nothing either")

    SaBrushSlotCommands.fill(4, "Inky")
    var loaded := SaBrushSlotCommands.slot_action(4, store)
    assert_eq(String(loaded["action"]), "load", "A slot whose preset is there loads it")
    assert_eq(String(loaded["preset"]), "Inky", "by name")

    store.delete_preset("Inky")
    var gone := SaBrushSlotCommands.slot_action(4, store)
    assert_eq(String(gone["action"]), "default", "A slot whose preset was deleted falls back to the default brush")
    assert_true(String(gone["message"]).contains("slot 4"), "and the corner message says which slot it was")
    _restore(before)


## The stored list is the page's shape whatever the file says, because ten rows
## are built from it and a shorter list would read past its own end.
func test_a_stored_list_of_the_wrong_length_is_made_ten() -> void:
    var before: Array = SaSettings.brush_slots.duplicate()
    SaSettings.brush_slots = ["One", "Two"]
    assert_eq(SaSettings.brush_slots.size(), SLOTS, "Two entries are padded to ten")
    assert_eq(String(SaSettings.brush_slots[0]), "One", "with what was there kept")
    assert_eq(String(SaSettings.brush_slots[9]), "", "and the rest empty")

    var long_list: Array = []
    long_list.resize(SLOTS + 4)
    long_list.fill("Over")
    SaSettings.brush_slots = long_list
    assert_eq(SaSettings.brush_slots.size(), SLOTS, "Fourteen are cut to ten")
    _restore(before)


## Each slot answers the digit row and the numpad, as one command
## with two chords rather than two commands, so the page keeps ten rows and a
## painter who rebinds a slot rebinds one thing.
func test_the_ten_commands_answer_to_ctrl_alt_and_a_digit() -> void:
    var registries := Fixtures.make_registries()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    var commands: SaCommandRegistry = registries.commands
    var row := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    for slot in range(1, SLOTS + 1):
        var command_id := SaBrushSlotCommands.command_id(slot)
        assert_true(commands.has(command_id), "%s is registered" % command_id)
        var wanted := "Ctrl+Alt+%s, Ctrl+Alt+Numpad %s" % [row[slot - 1], row[slot - 1]]
        assert_eq(commands.chord_text(command_id), wanted, "%s answers to both rows" % command_id)
        var descriptor := commands.get_descriptor(command_id)
        assert_eq(descriptor.title, "Select brush slot %d" % slot, "and the title is the one the page shows")
        assert_false(descriptor.sentence.is_empty(), "and it carries a sentence")


## Ten rows and not twenty. The numpad key is a second chord on the command the
## digit row already answers, so a painter who rebinds a slot rebinds one thing
## and the page gains no row for it.
func test_the_page_keeps_ten_rows_for_the_ten_slots() -> void:
    var registries := Fixtures.make_registries()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    var wanted: Array[String] = []
    for slot in range(1, SLOTS + 1):
        wanted.append(String(SaBrushSlotCommands.command_id(slot)))
    var in_the_map: Array[String] = []
    for action: StringName in InputMap.get_actions():
        if String(action).begins_with("brush_slot_"):
            in_the_map.append(String(action))
    wanted.sort()
    in_the_map.sort()
    assert_eq(in_the_map, wanted, "Every slot is one action in the map, so the page has ten rows")


## The two keys of a slot are the same chord on two rows of keys: a digit row key
## and its numpad twin, with the same modifiers on both. A numpad key without
## Ctrl would be a slot that fires on a bare keypress.
func test_a_slots_two_keys_are_one_chord_on_two_rows() -> void:
    var registries := Fixtures.make_registries()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    var commands: SaCommandRegistry = registries.commands
    for slot in range(1, SLOTS + 1):
        var events := commands.get_descriptor(SaBrushSlotCommands.command_id(slot)).default_events
        assert_eq(events.size(), 2, "Slot %d ships two chords" % slot)
        if events.size() != 2:
            continue
        var row := events[0] as InputEventKey
        var numpad := events[1] as InputEventKey
        assert_false(row == null or numpad == null, "Slot %d ships key events" % slot)
        assert_eq(row.keycode, SaBrushSlotCommands.KEYS[slot - 1], "the first is the digit row's key")
        assert_eq(numpad.keycode, SaBrushSlotCommands.NUMPAD_KEYS[slot - 1], "and the second its numpad twin")
        assert_eq(
            [numpad.ctrl_pressed, numpad.alt_pressed, numpad.shift_pressed, numpad.meta_pressed],
            [row.ctrl_pressed, row.alt_pressed, row.shift_pressed, row.meta_pressed],
            "with the same modifiers on both"
        )
        assert_true(row.ctrl_pressed and row.alt_pressed, "which are Ctrl and Alt, the chord Krita's plugin uses")


## The numpad's key: it sends KEY_KP_5,
## which no command held. The event here is what the numpad sends and nothing
## else in the map claims it, so a true answer is slot 5 and not a neighbour.
func test_a_numpad_key_with_ctrl_and_alt_reaches_its_slot() -> void:
    var registries := Fixtures.make_registries()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    var commands: SaCommandRegistry = registries.commands
    var event := _chord_event(KEY_KP_5)
    var slot_five := SaBrushSlotCommands.command_id(5)
    assert_true(InputMap.event_is_action(event, slot_five), "Ctrl+Alt+Kp 5 is slot 5's action")
    var others: Array[String] = []
    for action: StringName in InputMap.get_actions():
        if action != slot_five and InputMap.event_is_action(event, action, true):
            others.append(String(action))
    assert_eq(others, [] as Array[String], "and no other action in the map answers to it")
    assert_true(commands.try_handle_input(event), "so the key the numpad sends reaches the slot")


## Ctrl and Alt with a numpad key, which is the shape the keyboard sends and the
## shape `SaBrushSlotCommands._chord` builds.
func _chord_event(keycode: Key) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.ctrl_pressed = true
    event.alt_pressed = true
    event.pressed = true
    return event


## The page shows both chords of a slot, and the numpad one says it is the
## numpad's rather than the digit row's. A row printing only the first is what
## a painter reads as a zoom with no numpad chord at all.
func test_the_page_shows_a_slots_digit_and_numpad_chord() -> void:
    var registries := Fixtures.make_registries()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    var page := SaShortcutsPage.new()
    assert_eq(
        page.chords_shown(SaBrushSlotCommands.command_id(5)),
        ["Ctrl+Alt+5", "Ctrl+Alt+Numpad 5"] as Array[String],
        "Slot 5's row shows the digit row's key and the numpad's"
    )
    page.free()


## The prefix decides the section on the Keyboard Shortcuts page, so the ten sit
## under Brush rather than under Select, which is what `select_brush_slot_1`
## would have done.
func test_the_rows_land_in_the_brush_section() -> void:
    for slot in range(1, SLOTS + 1):
        assert_true(String(SaBrushSlotCommands.command_id(slot)).begins_with("brush_"), "Slot %d is a brush row" % slot)


## One list rather than one per profile. Photoshop has no brush slots, so its
## map takes the chords away rather than moving them.
func test_the_photoshop_map_carries_no_chord_for_a_slot() -> void:
    for slot in range(1, SLOTS + 1):
        var action := String(SaBrushSlotCommands.command_id(slot))
        assert_true(SaShortcutStore.PHOTOSHOP_DEFAULTS.has(action), "The Photoshop map names %s" % action)
        assert_eq(String(SaShortcutStore.PHOTOSHOP_DEFAULTS.get(action, "x")), "", "and clears it")


## Ctrl+Alt+1 loads slot 1 under Krita as under Sara Default. Krita 5.2.13 ships `activate_preset_1` to
## `activate_preset_0` on Ctrl+Alt digits, so the Krita map keeps the slots
## there with their numpad twins, and the key reaches the slot's command.
func test_under_krita_ctrl_alt_1_loads_slot_1() -> void:
    var registries := Fixtures.make_registries()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    var router := ShortcutRouter.new()
    router.bind_commands(registries.commands)
    var saved := {}
    for action: StringName in InputMap.get_actions():
        saved[action] = InputMap.action_get_events(action).duplicate()
    var row := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    for slot in range(1, SLOTS + 1):
        var action := String(SaBrushSlotCommands.command_id(slot))
        var chord := String(SaShortcutStore.KRITA_DEFAULTS.get(action, ""))
        assert_eq(chord, "Ctrl+Alt+%s" % row[slot - 1], "Krita keeps %s on its own chord" % action)
        var named := SaShortcutKritaTable.actions_of(action)
        assert_eq(named, ["activate_preset_%s" % row[slot - 1]] as Array[String], "and names Krita's action for it")

    SaShortcutStore.apply_profile("Krita")
    var slot_one := SaBrushSlotCommands.command_id(1)
    var digit := SaShortcutStore.chord_text(_chord_event(KEY_1))
    var numpad := SaShortcutStore.chord_text(_chord_event(KEY_KP_1))
    var held := SaShortcutStore.chords_for(slot_one)
    assert_eq(held, [digit, numpad] as Array[String], "Slot 1 answers both rows under Krita")
    assert_eq(SaShortcutStore.holders(digit, slot_one), [] as Array[String], "and nothing else answers Ctrl+Alt+1")
    var ten := SaShortcutStore.chord_text(_chord_event(KEY_0))
    var slot_ten := String(SaBrushSlotCommands.command_id(10))
    assert_eq(SaShortcutStore.holders(ten), [slot_ten] as Array[String], "Ctrl+Alt+0 is slot 10")
    registries.commands.last_command = &""
    assert_true(router.handle(_chord_event(KEY_1)), "Ctrl+Alt+1 is taken under Krita")
    assert_eq(registries.commands.last_command, slot_one, "by slot 1's command")

    SaShortcutStore.apply_profile("Photoshop")
    registries.commands.last_command = &""
    router.handle(_chord_event(KEY_1))
    assert_eq(registries.commands.last_command, &"", "while under Photoshop the key reaches no slot")

    router.free()
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    for action: StringName in InputMap.get_actions():
        if not saved.has(action):
            InputMap.erase_action(action)
    for action: StringName in saved:
        InputMap.action_erase_events(action)
        for event: InputEvent in saved[action]:
            InputMap.action_add_event(action, event)


## Each row's Clear is dimmed
## while its slot holds nothing, lit by a pick and dimmed by its own press.
func test_clear_is_dimmed_while_its_slot_is_empty() -> void:
    var before: Array = SaSettings.brush_slots.duplicate()
    for slot in range(1, SLOTS + 1):
        SaBrushSlotCommands.fill(slot, "")
    var store := _fixture_store()
    _write_preset(store, "Inky")

    var page := SaBrushSlotsPage.new(store)
    assert_eq(page.clear_buttons.size(), SLOTS, "One Clear per slot")
    for button: Button in page.clear_buttons:
        assert_true(button.disabled, "An empty slot offers no Clear")
    assert_true(page.choose(4, "Inky"), "Slot four offers Inky")
    assert_false(page.clear_buttons[3].disabled, "and filling it lights its Clear")
    assert_true(page.clear_buttons[2].disabled, "and no other")
    page._on_clear_pressed(4)
    assert_true(page.clear_buttons[3].disabled, "Its own press dims it again")
    page.free()
    _restore(before)


## Two slots holding one preset are marked. Both rows say where else the preset is, the corner says which
## slot had it first, and a clear takes both lines away.
func test_a_slot_that_takes_another_slots_preset_says_so() -> void:
    var before: Array = SaSettings.brush_slots.duplicate()
    SaSettings.brush_slots = SaSettingsBrushSlots.empty()
    var host := Node.new()
    host.name = "N67BrushSlotsHost"
    EventBus.add_child(host)
    SaMessage.install(host)
    var store := _fixture_store()
    _write_preset(store, "Inky")
    _write_preset(store, "Chalk")

    var page := SaBrushSlotsPage.new(store)
    assert_eq(page.twin_notes.size(), SLOTS, "One twin line per slot")
    assert_true(page.choose(1, "Inky"), "Slot one takes Inky")
    for note: Label in page.twin_notes:
        assert_false(note.visible, "and one slot holding a preset is no twin")
    assert_false(SaMessage.notice_widget().showing(), "and the corner says nothing")

    assert_true(page.choose(3, "Inky"), "Slot three takes Inky as well")
    assert_eq(SaBrushSlotCommands.preset_for(3), "Inky", "and the pick goes through, since a painter may want it twice")
    assert_true(page.twin_notes[2].visible, "Slot three's line is up")
    assert_eq(page.twin_notes[2].text, "Also on Slot 1.", "naming the slot that had it")
    assert_true(page.twin_notes[0].visible, "and so is slot one's")
    assert_eq(page.twin_notes[0].text, "Also on Slot 3.", "naming the other")
    var column := page.twin_notes[2].get_parent()
    assert_eq(String(column.name), "Labels", "in the row's title column")
    assert_not_null(column.get_node_or_null(^"Hint"), "under the row's own hint")
    assert_eq(page.twin_notes[2].get_theme_color("font_color"), SaTheme.palette.accent_primary, "in the accent")
    assert_false(page.twin_notes[1].visible, "and a row with no twin says nothing")
    assert_true(SaMessage.notice_widget().showing(), "The corner speaks")
    assert_eq(
        SaMessage.notice_widget().label.text,
        '"Inky" was already on Slot 1, and Slot 3 loads it too.',
        "and says which slot already had it"
    )

    assert_true(page.choose(5, "Inky"), "A third slot takes it")
    assert_eq(page.twin_notes[0].text, "Also on Slots 3 and 5.", "and the first names both others")
    assert_eq(page.twin_notes[4].text, "Also on Slots 1 and 3.", "as the third does")

    assert_true(page.choose(5, "Chalk"), "Picking another preset ends a twin")
    assert_false(page.twin_notes[4].visible, "so its line goes")
    assert_eq(page.twin_notes[0].text, "Also on Slot 3.", "and the others read it again")

    page._on_clear_pressed(3)
    for note: Label in page.twin_notes:
        assert_false(note.visible, "Clearing one of the pair clears both lines")
    assert_eq(page.twin_lines(), PackedStringArray(), "and a step reads none")

    page.free()
    host.free()
    _restore(before)


## A page opened on slots that already share a preset marks them before any
## pick, because a profile written before the mark existed can hold a twin.
func test_a_page_opened_on_a_twin_marks_it_at_once() -> void:
    var before: Array = SaSettings.brush_slots.duplicate()
    SaSettings.brush_slots = SaSettingsBrushSlots.empty()
    var store := _fixture_store()
    _write_preset(store, "Inky")
    SaBrushSlotCommands.fill(2, "Inky")
    SaBrushSlotCommands.fill(10, "Inky")

    var page := SaBrushSlotsPage.new(store)
    assert_eq(page.twin_notes[1].text, "Also on Slot 10.", "Slot two names slot ten")
    assert_eq(page.twin_notes[9].text, "Also on Slot 2.", "and slot ten names slot two")
    assert_eq(
        page.twin_lines(), PackedStringArray(["Slot 2: Also on Slot 10.", "Slot 10: Also on Slot 2."]), "and a step reads both"
    )
    page.free()
    _restore(before)
