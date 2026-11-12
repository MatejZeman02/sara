## The underlined letter of a
## menu row is chosen by a rule over the row's own words, and pressing it runs
## the row.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Each row's letter is picked programmatically by a
## heuristic, not hardcoded (like in Blender). What a screenshot cannot hold is
## here: that every row of the five menus named there carries one, that no two
## rows of a list share one, that "New" gives its letter last, that a row a
## module adds through the public door takes a letter nobody held without moving
## another, and that a letter runs its row and a dimmed row's letter runs nothing.
##
## Built detached and `_ready()`ed by hand, the way `test_menus.gd` builds its
## bar: a popup is a `Window`, and a bar in the tree hangs a headless run. The
## running app's capture is a scenario under
## `scenarios/`.
extends "res://tests/test_framework.gd"

## The menus the Done line names.
const MENUS: Array[String] = ["File", "Edit", "Layer", "Filter", "Window"]

## The module the added row belongs to, as a module's context names it.
const MODULE_ID := &"letter-fixture"

var _bar: TopMenuBar = null
var _registries: SaRegistries = null
var _ran: Array[StringName] = []


func before_each() -> void:
    _bar = TopMenuBar.new()
    _bar._ready()
    var note_mode := SaNoteMode.new()
    _bar.add_child(note_mode)
    _registries = SaTestFixtures.make_menu_registries(note_mode)
    _bar.bind_commands(_registries.commands)
    _ran.clear()


func after_each() -> void:
    if _bar != null:
        _bar.free()
        _bar = null
    _registries = null


## Row label -> its underlined letter, for one menu.
func _letters(menu_name: String) -> Dictionary:
    var out := {}
    for row: Dictionary in _bar.menu(menu_name).popup.row_report():
        out[row["label"]] = row["letter"]
    return out


## A menu with more rows than the alphabet
## has letters leaves its last rows bare, as Blender's do, so every row of a menu
## under 27 rows is lettered, and in every menu no letter is held twice. Every
## menu of the bar is short since the long ones went into submenus, so the
## bare rows are read off a list of thirty rows given to the rule itself.
func test_every_row_of_a_short_menu_has_a_letter_of_its_own_words_and_none_is_shared() -> void:
    for menu_name in MENUS:
        var popup := _bar.menu(menu_name).popup
        var rows := popup.row_report()
        assert_true(rows.size() > 0, "%s lists rows" % menu_name)
        var seen := {}
        for row: Dictionary in rows:
            var letter: String = row["letter"]
            if rows.size() < 27:
                assert_eq(letter.length(), 1, "%s › %s carries one underlined letter" % [menu_name, row["label"]])
            if letter.is_empty():
                continue
            var own := String(row["label"]).to_lower().contains(letter)
            assert_true(own, "%s › %s is underlined at a letter of its own words" % [menu_name, row["label"]])
            assert_false(seen.has(letter), "%s › %s shares %s with %s" % [menu_name, row["label"], letter, seen.get(letter, "")])
            seen[letter] = row["label"]
    var long_list: Array = []
    for i: int in 30:
        long_list.append([StringName("row_%d" % i), "Row %s" % char(65 + i % 26), true])
    var given := SaMenuLetters.pick(long_list)
    assert_true(given.size() <= 26, "a list of thirty rows letters no more than the alphabet holds: %d" % given.size())
    assert_true(given.size() < long_list.size(), "and leaves its last rows bare rather than share a letter")
    assert_eq(_letters("Layer").get("New Layer", ""), "l", "the Layer menu's first rows are lettered before its last")


func test_new_gives_its_letter_only_after_the_rows_other_words() -> void:
    var checked := 0
    for menu_name in MENUS:
        var popup := _bar.menu(menu_name).popup
        for id in popup.row_ids():
            var label := popup.label_button(id).text
            if not label.begins_with("New ") or SaChoiceLetters.letter_of(popup.row_of(id)).is_empty():
                continue
            checked += 1
            assert_true(
                SaChoiceLetters.letter_of(popup.row_of(id)) != "n", "%s › %s is lettered by a word after New" % [menu_name, label]
            )
    assert_true(checked > 0, "a row that begins with New was read")
    assert_eq(_letters("Layer").get("New Layer", ""), "l", "New Layer is underlined at the L of Layer")
    assert_eq(_letters("File").get("New...", ""), "n", "a row named New alone still has New's letter")


func test_the_rule_reads_words_before_letters_and_small_words_last() -> void:
    var given := (
        SaMenuLetters
        . pick(
            [
                [&"save", "Save", true],
                [&"save_as", "Save As...", true],
                [&"new_layer", "New Layer", true],
                [&"new", "New", true],
                [&"cut", "Cut (Ctrl+X)", true],
            ]
        )
    )
    assert_eq(given[&"save"], 0, "Save takes its S")
    assert_eq(given[&"save_as"], 5, "Save As takes the A of As, a word's initial, before a letter inside Save")
    assert_eq(given[&"new_layer"], 4, "New Layer takes the L of Layer before the N of New")
    assert_eq(given[&"new"], 0, "New alone takes its N")
    assert_eq(given[&"cut"], 0, "Cut takes its C")
    var crowded := SaMenuLetters.pick([[&"one", "Cut", true], [&"two", "Cut (Ctrl+X)", true]])
    assert_eq(crowded[&"two"], 1, "a second Cut takes a letter inside its word, never one of the chord")


func test_a_row_a_module_adds_takes_a_free_letter_and_moves_no_other() -> void:
    var before := _letters("Modules")
    var context := SaContext.new(Callable(), Callable(), MODULE_ID)
    context.commands = _registries.commands
    var ran := func() -> void: _ran.append(&"moon")
    var descriptor := SaCommandDescriptor.create(&"sharpen_the_moon", "Sharpen the Moon", ran)
    descriptor.show_in_modules_menu = true
    assert_true(context.register_command(descriptor), "the module's command is registered through its context")
    var after := _letters("Modules")
    assert_true(after.has("Sharpen the Moon"), "the module's row is in the Modules menu")
    var letter: String = after.get("Sharpen the Moon", "")
    assert_eq(letter.length(), 1, "the module's row is underlined though it gave no letter")
    for label: String in before:
        assert_eq(after.get(label, ""), before[label], "%s keeps its letter" % label)
        assert_true(before[label] != letter, "the module's row took a letter %s did not hold" % label)


func test_a_letter_runs_its_row_and_a_dimmed_rows_letter_runs_nothing() -> void:
    var context := SaContext.new(Callable(), Callable(), MODULE_ID)
    context.commands = _registries.commands
    var lit := SaCommandDescriptor.create(&"lit", "Lit Row", func() -> void: _ran.append(&"lit"))
    lit.show_in_modules_menu = true
    var dim := SaCommandDescriptor.create(&"dim", "Dim Row", func() -> void: _ran.append(&"dim"))
    dim.show_in_modules_menu = true
    dim.enabled = func() -> bool: return false
    context.register_command(lit)
    context.register_command(dim)
    var popup := _bar.menu("Modules").popup
    var lit_id := _row_named(popup, "Lit Row")
    var dim_id := _row_named(popup, "Dim Row")
    assert_true(popup.is_disabled(dim_id), "the dim row is dimmed")
    assert_false(SaChoiceLetters.letter_of(popup.row_of(dim_id)).is_empty(), "the dim row is underlined")
    assert_true(
        SaChoiceLetters.press(popup, SaChoiceLetters.letter_of(popup.row_of(dim_id)).to_upper()), "the dim row's letter is held"
    )
    assert_eq(_ran, [] as Array[StringName], "the dim row's letter ran nothing")
    assert_true(SaChoiceLetters.press(popup, SaChoiceLetters.letter_of(popup.row_of(lit_id))), "the lit row's letter is held")
    assert_eq(_ran, [&"lit"] as Array[StringName], "the lit row's letter ran the row once")
    var free := "abcdefghijklmnopqrstuvwxyz".split("") as Array
    for id in popup.row_ids():
        free.erase(SaChoiceLetters.letter_of(popup.row_of(id)))
    if not free.is_empty():
        assert_false(SaChoiceLetters.press(popup, free[0]), "a letter no row holds runs nothing and is left to the type-ahead")


## Every menu of the top bar has a search field that a bare letter types
## into, so there the letter runs its row with Alt
## held and a bare letter is left to the field. A list with no field, here a
## child list built as the filter menu builds one, takes the bare letter.
func test_alt_runs_a_letter_where_a_search_field_types_and_a_bare_letter_runs_it_elsewhere() -> void:
    var context := SaContext.new(Callable(), Callable(), MODULE_ID)
    context.commands = _registries.commands
    var lit := SaCommandDescriptor.create(&"alt", "Lit Row", func() -> void: _ran.append(&"lit"))
    lit.show_in_modules_menu = true
    context.register_command(lit)
    var popup := _bar.menu("Modules").popup
    assert_true(popup.search.visible, "a top-bar menu carries the search field")
    var letter := SaChoiceLetters.letter_of(popup.row_of(_row_named(popup, "Lit Row")))
    assert_eq(letter.length(), 1, "the row is lettered")
    popup.visible = true
    popup._input(_key(letter, false))
    assert_eq(_ran, [] as Array[StringName], "a bare letter in a menu with a search field runs no row")
    popup._input(_key(letter, true))
    assert_eq(_ran, [&"lit"] as Array[StringName], "Alt and the letter run the row")
    popup.visible = false

    var plain := SaChoicePopup.new(true, false)
    plain.add_row(&"one", "Sharpen")
    plain.add_row(&"two", "Blur")
    var picked := SaMenuLetters.pick([[&"one", "Sharpen", true], [&"two", "Blur", true]])
    for id: StringName in picked:
        SaChoiceLetters.underline(plain.row_of(id), picked[id])
    var chosen: Array[StringName] = []
    plain.chosen.connect(func(id: StringName) -> void: chosen.append(id))
    assert_false(plain.search.visible, "a short list of its own has no search field")
    plain.visible = true
    plain._input(_key("b", false))
    assert_eq(chosen, [&"two"] as Array[StringName], "a bare letter runs its row in a list with no field")
    plain.visible = false
    plain.free()


func _key(letter: String, alt: bool) -> InputEventKey:
    var key := InputEventKey.new()
    key.pressed = true
    key.keycode = OS.find_keycode_from_string(letter.to_upper())
    key.unicode = 0 if alt else letter.unicode_at(0)
    key.alt_pressed = alt
    return key


func _row_named(popup: SaChoicePopup, label: String) -> StringName:
    for id in popup.row_ids():
        if popup.label_button(id).text == label:
            return id
    return &""
