## F3 opens with the last three rows picked in it at the top.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## F3 search shows the last three
## searched things at the top when re-opened. A module's four commands are the
## rows picked, so the suite owns every row it reads, and the picks go into
## `SaSettings.search_recents`, which the suite puts back after each test. The
## running app's side, F3 opened again over a filter picked a moment before, is
## `tests/shots/f3-opens-with-the-last-three-rows-picked-in-it-at-the-top.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const MODULE := &"probe"
const TITLES := ["Probe Umber Wash", "Probe Sienna Wash", "Probe Ochre Wash", "Probe Indigo Wash"]

static var scratch_path: String = SaDataRoot.path("test_search_recents.cfg")

var _registries: SaRegistries = null
var _host: Node = null
var _window: SaSearchWindow = null
var _actions_before: Array[StringName] = []
var _kept: Array = []
var _ran: Array[String] = []
var _ochre_runs: bool = true


func before_each() -> void:
    _kept = SaSettings.search_recents
    SaSettings.search_recents = []
    _clear()
    _ran.clear()
    _ochre_runs = true
    _actions_before = InputMap.get_actions()
    _host = Node.new()
    _host.name = "U561SearchHost"
    EventBus.add_child(_host)
    _registries = Fixtures.make_menu_registries()
    var module := _registries.context.for_module(MODULE)
    for at in TITLES.size():
        var named: String = TITLES[at]
        var descriptor := SaCommandDescriptor.create(_command(at), named, func() -> bool: return _note(named))
        if at == 2:
            descriptor.enabled = func() -> bool: return _ochre_runs
        assert_true(module.register_command(descriptor), "The probe registers %s" % named)
    _window = SaSearchWindow.new(SaSearchIndex.new(_registries.context))
    _host.add_child(_window)


func after_each() -> void:
    _registries.context.for_module(MODULE).remove_all_registrations()
    _host.free()
    _host = null
    _window = null
    _registries = null
    for action: StringName in InputMap.get_actions():
        if not _actions_before.has(action):
            InputMap.erase_action(action)
    SaSettings.search_recents = _kept
    _clear()


func _clear() -> void:
    var path := ProjectSettings.globalize_path(scratch_path)
    for suffix: String in ["", ".bak", ".tmp", ".broken"]:
        DirAccess.remove_absolute(path + suffix)


static func _command(at: int) -> StringName:
    return StringName("probe_%d" % at)


func _note(named: String) -> bool:
    _ran.append(named)
    return true


## Opens the search, finds the row titled *named* by typing it, and picks it
## with Enter.
func _pick(named: String) -> void:
    _window.open()
    _window.filter(named)
    assert_eq(_window.shown[_window.marked_at].title, named, "%s is the row marked" % named)
    _window.pick_marked()


## The titles of the first *count* rows an opening with an empty field shows.
func _top(count: int) -> Array:
    _window.open()
    return (_window.report(count)["rows"] as Array).map(func(row: String) -> String: return row.get_slice(" (", 0))


func test_four_picks_leave_the_last_three_at_the_top_newest_first() -> void:
    for named: String in TITLES:
        _pick(named)
    assert_eq(_ran, TITLES, "Each pick ran its command")
    var top := _top(3)
    assert_eq(top, [TITLES[3], TITLES[2], TITLES[1]], "The last three picked open the list, newest first")
    var listed := _window.report(3)
    assert_eq(listed["recent"], 3, "under Recent, three rows")
    assert_eq(listed["shown"], listed["of"], "and every row is listed below them as before")
    assert_true(_window.find_child("SectionRecent", true, false) != null, "The heading Recent stands over them")
    assert_eq(SaSettings.search_recents.size(), SaSettingsSearchRecents.SEARCH_RECENTS_KEPT, "The settings keep three")


func test_picking_the_oldest_of_the_three_brings_it_first() -> void:
    for named: String in TITLES:
        _pick(named)
    _window.open()
    assert_eq(_window.shown[2].title, TITLES[1], "The oldest of the three is the third row")
    _window.pick(_window.shown[2])
    assert_eq(_ran.back(), TITLES[1], "A pick of a recent row runs it")
    assert_eq(_top(3), [TITLES[1], TITLES[3], TITLES[2]], "and it moves to the front, once")


## A click is the list's own `chosen`, which the door's press of a row is too.
func test_a_click_on_a_row_is_remembered_as_enter_is() -> void:
    _window.open()
    _window.filter(TITLES[0])
    _window.press_row(&"r0")
    assert_eq(_ran, [TITLES[0]], "The click ran the row")
    assert_eq(_top(1), [TITLES[0]], "and the row opens the list next time")


func test_typing_ranks_the_recent_rows_with_the_rest() -> void:
    _pick(TITLES[0])
    _window.open()
    _window.filter("probe")
    var listed := _window.report(8)
    assert_eq(listed["recent"], 0, "A typed query shows no Recent heading")
    assert_eq(listed["rows"].size(), TITLES.size(), "and lists each probe row once")


func test_a_recent_row_that_cannot_run_is_dimmed_and_unpickable() -> void:
    _pick(TITLES[2])
    _ochre_runs = false
    _window.open()
    assert_eq(_window.shown[0].title, TITLES[2], "The row is still first")
    assert_false(_window.shown[0].enabled, "and dimmed")
    assert_true(_window.row_report()[0]["disabled"], "drawn dimmed as it is anywhere else")
    _ran.clear()
    _window.pick(_window.shown[0])
    assert_eq(_ran, [], "and a pick does nothing")
    assert_true(_window.marked_at != 0, "The highlight lands on a row that can be picked")


func test_a_remembered_row_whose_command_is_gone_is_left_out() -> void:
    _pick(TITLES[0])
    _pick(TITLES[1])
    SaSettings.search_recents = ["command:never_registered"] + SaSettings.search_recents
    _registries.context.commands.unregister(_command(1))
    _window.open()
    var listed := _window.report(2)
    assert_eq(listed["recent"], 1, "Neither the unregistered nor the unloaded row is shown")
    assert_eq(_window.shown[0].title, TITLES[0], "and the one still registered stays")


func test_the_three_survive_a_save_and_a_read_into_fresh_settings() -> void:
    assert_eq(SaSettingsKeys.place_of(&"search_recents"), ["ui", "search_recents"], "Kept under ui beside the list's size")
    var file := SaSettingsFile.new()
    file.settings_path = ProjectSettings.globalize_path(scratch_path)
    var values := SaSettingsValues.new()
    file.load_from_disk(values)
    assert_eq(values.search_recents, [], "A fresh profile remembers no pick")
    values.changed.connect(func(property: StringName) -> void: file.write(property, values.stored(String(property))))
    for key: String in ["row:Tool:Brush", "command:a", "command:b", "command:a", "command:c"]:
        values.remember_search_pick(key)
    values.free()
    var again_file := SaSettingsFile.new()
    again_file.settings_path = ProjectSettings.globalize_path(scratch_path)
    var again := SaSettingsValues.new()
    again_file.load_from_disk(again)
    assert_eq(again.search_recents, ["command:c", "command:a", "command:b"], "The three read back, newest first, each once")
    again.free()
