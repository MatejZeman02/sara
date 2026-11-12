## Search Commands walks its rows once, and again only when a
## command arrives.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Edit > Search Commands held a frame of 74 to 100 ms at
## every opening, 17 ms of it the walk of every registry and 30 ms the drawing
## of the rows. The index now keeps its walk and the window its drawn rows, so
## here the list is opened twice and the walk counted, a command is registered
## as a module registers one and the next opening finds it, and a command that
## came to run since the rows were drawn is lit where a query draws it.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const ARRIVING := &"a_module_s_command"
const ARRIVING_TITLE := "Uxsixty Arriving Command"

var _registries: SaRegistries = null
var _host: Node = null
var _bar: TopMenuBar = null
var _window: SaSearchWindow = null
var _was_embedding := false
var _runs := false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "U660SearchHost"
    EventBus.add_child(_host)
    EventBus.move_child(_host, 0)
    _registries = Fixtures.make_menu_registries()
    _bar = TopMenuBar.new()
    _host.add_child(_bar)
    _bar.bind_commands(_registries.commands)
    _window = SaSearchWindow.new(SaSearchIndex.new(_registries.context), _bar)
    _host.add_child(_window)
    _runs = false


func after_each() -> void:
    _host.free()
    _host = null
    _window = null
    _bar = null
    _registries = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _was_embedding


## Two openings walk the rows once, and the second shows the rows the first
## drew rather than drawing them again.
func test_two_openings_walk_the_rows_once() -> void:
    _window.open()
    assert_true(_window.visible, "The first opening shows the list")
    assert_eq(_window.index.builds, 1, "and walks the rows once")
    var first_row := _window.row_of(_window.row_ids()[0])
    assert_true(first_row != null, "and draws them")
    _window.hide()
    await (Engine.get_main_loop() as SceneTree).process_frame

    _window.open()
    assert_true(_window.visible, "The second opening shows the list")
    assert_eq(_window.index.builds, 1, "with the rows of the first walk, walked once in all")
    assert_true(_window.row_of(_window.row_ids()[0]) == first_row, "and the rows the first opening drew, not drawn anew")
    assert_true(_window.entries.size() > 50, "a list of every command, %d rows" % _window.entries.size())


## A command registered between two openings, as a module registers one, is
## walked again once and found by the next opening.
func test_a_command_a_module_registers_is_walked_once_more() -> void:
    _window.open()
    _window.hide()
    assert_eq(_window.index.builds, 1, "The first opening walks the rows")
    _registries.commands.register(_command(), &"module")
    _window.open()
    assert_eq(_window.index.builds, 2, "A registered command walks them once more")
    assert_true(_titles().has(ARRIVING_TITLE), "and the opening lists the command")
    _window.hide()
    _window.open()
    assert_eq(_window.index.builds, 2, "and the opening after that walks nothing")


## A command that came to run since the rows were walked is lit where a query
## draws its row, though the walk was kept.
func test_a_command_that_came_to_run_is_lit_where_it_is_drawn() -> void:
    _registries.commands.register(_command(), &"module")
    _window.open()
    _window.filter(ARRIVING_TITLE)
    assert_false(_entry().enabled, "A command that does not run yet is dimmed")
    _window.hide()
    _runs = true
    _window.open()
    _window.filter(ARRIVING_TITLE)
    assert_eq(_window.index.builds, 1, "The rows were walked once")
    assert_true(_entry().enabled, "and the command that came to run is lit")
    assert_false(_window.is_disabled(_window.row_ids()[0]), "on its drawn row")


func _command() -> SaCommandDescriptor:
    var descriptor := SaCommandDescriptor.new()
    descriptor.id = ARRIVING
    descriptor.title = ARRIVING_TITLE
    descriptor.handler = func() -> bool: return true
    descriptor.enabled = func() -> bool: return _runs
    return descriptor


func _entry() -> SaSearchIndex.Entry:
    for entry: SaSearchIndex.Entry in _window.shown:
        if entry.command == ARRIVING:
            return entry
    return null


func _titles() -> Array[String]:
    var out: Array[String] = []
    for entry: SaSearchIndex.Entry in _window.entries:
        out.append(entry.title)
    return out
