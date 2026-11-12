## The Tools menu has a row that opens the brush editor.
##
## At 1920 by 1080 the top bar's overflow held one control, Edit Brush, and no
## menu named the brush editor, so a painter who hid the bar's button had the
## chord and nothing to find it by. The row is the `edit_brush` command's, drawn
## after the tool rows, and this suite holds that it is there, that it reads as
## a window opens, that it prints the chord the command carries and says what
## it does, and that a press runs the command.
##
## Built detached and `_ready()`ed by hand, the way `test_tools_menu.gd` builds
## its bar: a popup is a `Window`, and a bar in the tree hangs a headless run.
## The command's handler defers the open, `call_deferred`, which nothing here
## waits for: a test that awaits drops every assertion after the await
## (a Godot trap). So the press is read as the command running, with a probe where
## the handler was, and the window the handler opens is the scenario's, which
## presses the row on the running app and reads `SaBrushEditorWindow` back in
## the dump.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _registries: SaRegistries = null
var _bar: TopMenuBar = null
var _menu: SaToolsMenu = null


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    _registries = Fixtures.make_menu_registries()
    _bar = TopMenuBar.new()
    _bar._ready()
    _bar.bind_commands(_registries.commands)
    _menu = _bar.menu("Tools") as SaToolsMenu
    if _menu != null:
        _menu.machine = _machine
        _menu.populate()


func after_each() -> void:
    _menu = null
    if _bar != null:
        _bar.free()
        _bar = null
    _registries = null
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


## The row's own entry in the popup's report, or an empty one.
func _row() -> Dictionary:
    for row: Dictionary in _menu.popup.row_report():
        if String(row["id"]) == String(SaMenu.key(SaToolsMenu.EDIT_BRUSH_ROW)):
            return row
    return {}


func test_the_tools_menu_has_an_edit_brush_row_after_the_tools() -> void:
    assert_not_null(_menu, "The bar builds a Tools menu")
    var row := _row()
    assert_false(row.is_empty(), "The Tools menu has the Edit Brush row")
    assert_eq(String(row.get("label", "")), "Edit Brush...", "It reads as a window opens, which the other menus' dots say")
    assert_eq(_menu.command_at(SaToolsMenu.EDIT_BRUSH_ROW), &"edit_brush", "and it is the edit_brush command's row")
    var ids := _menu.popup.row_ids()
    var edit_at := ids.find(SaMenu.key(SaToolsMenu.EDIT_BRUSH_ROW))
    var last_tool := -1
    for index in ids.size():
        var id := SaMenu.id_of(ids[index])
        if id >= SaToolsMenu.TOOL_ROW_BASE and id < SaToolsMenu.STABILIZER_ROW_BASE:
            last_tool = index
    assert_true(last_tool >= 0 and edit_at > last_tool, "and it stands after the last tool row")


func test_the_row_prints_the_chord_the_command_carries() -> void:
    var row := _row()
    var chord := _menu.chord_of(&"edit_brush")
    assert_eq(chord, "F5", "The command answers to F5, Krita's own key for it")
    assert_eq(String(row.get("hint", "")), chord, "and the row prints it in its hint column")


func test_the_row_says_what_it_does() -> void:
    var button := _menu.popup.label_button(SaMenu.key(SaToolsMenu.EDIT_BRUSH_ROW))
    assert_not_null(button, "The row has a label button")
    if button != null:
        assert_eq(button.tooltip_text, "Opens the brush editor on the brush in hand.", "and its tooltip says what it does")


func test_the_row_is_not_dimmed_and_the_ids_do_not_collide() -> void:
    assert_false(bool(_row().get("disabled", true)), "The brush editor can be opened at any time, so the row is lit")
    var seen := {}
    for id: StringName in _menu.popup.row_ids():
        assert_false(seen.has(id), "%s is the row of one thing" % id)
        seen[id] = true
    var clear_of_modes := SaToolsMenu.EDIT_BRUSH_ROW >= SaToolsMenu.STABILIZER_ROW_BASE + 100
    assert_true(clear_of_modes, "and its id is clear of the stabilizer's run")


## The press, read as the command running. The handler is replaced by a probe,
## because the real one opens the window a frame later and a suite cannot wait.
func test_a_press_runs_the_edit_brush_command() -> void:
    var ran := [0]
    var command := _registries.commands.get_descriptor(&"edit_brush")
    assert_not_null(command, "The edit_brush command is registered")
    if command == null:
        return
    command.handler = func() -> bool:
        ran[0] += 1
        return true
    _menu.on_id_pressed(SaToolsMenu.EDIT_BRUSH_ROW)
    assert_eq(ran[0], 1, "Pressing the row runs the command once")
    ran[0] = 0
    _menu.popup.chosen.emit(SaMenu.key(SaToolsMenu.EDIT_BRUSH_ROW))
    assert_eq(ran[0], 1, "and so does a press the popup delivers")


## What the real handler opens, read off the source for the reason in the header.
func test_the_command_opens_the_brush_editor_through_its_door() -> void:
    var source := FileAccess.get_file_as_string("res://ui/shortcuts/sa_app_commands.gd")
    assert_false(source.is_empty(), "The file the command lives in is readable")
    assert_true(source.contains("SaBrushEditorDoor.toggle(tree)"), "The command opens the editor through the bar's own door")
    var door := FileAccess.get_file_as_string("res://ui/brush_editor/brush_editor_door.gd")
    assert_true(door.contains("SaBrushEditorWindow.new()"), "and the door builds an SaBrushEditorWindow on first use")


func test_a_bar_with_no_registry_draws_no_edit_brush_row() -> void:
    var bare := TopMenuBar.new()
    bare._ready()
    var menu := bare.menu("Tools") as SaToolsMenu
    menu.machine = _machine
    menu.populate()
    var has_row := menu.has_item(SaToolsMenu.EDIT_BRUSH_ROW)
    var has_modes := menu.has_item(SaToolsMenu.STABILIZER_ROW_BASE)
    menu = null
    bare.free()
    assert_false(has_row, "With no command to draw it from, a bar draws no row")
    assert_true(has_modes, "and the stabilizer's modes below it are still there")
