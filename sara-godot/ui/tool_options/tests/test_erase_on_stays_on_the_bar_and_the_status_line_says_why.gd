## Erase on shows on the bar, and the status line says why a stroke changed
## nothing.
##
## An Erase toggle that goes to the overflow at the bar's width leaves nothing
## on screen saying it is on. Lit, it stays on the row whatever
## else leaves it, and off it leaves among the first as it did.
##
## Built detached and `_ready()`ed by hand, the way `test_top_bar_rows.gd` does.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The bar's controls come from the tools' descriptors, and a machine with the
## built-in tools needs a surface, which needs a device.
const REQUIRES_GPU := true

## About the narrowest bar the menus and the window buttons leave any room on,
## so every control that can leave has left. At 640 they overrun the row on
## their own and nothing of the tool's stays. The Erase toggle is 44 wide, which a row
## of 800 has no room for.
const NARROW := 820.0

var _saved_path: String = ""
var _saved_row: bool = false
var _surface: SaSurface = null
var _machine: ToolMachine = null


func before_each() -> void:
    _saved_row = SaSettings.second_row
    _saved_path = SaSettings.settings_path
    SaSettings.settings_path = ProjectSettings.globalize_path(SaDataRoot.path("test_erase_on_stays_on_the_bar.cfg"))
    _remove_profile()
    SaSettings.load_settings()
    SaSettings.second_row = false
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")


func after_each() -> void:
    _remove_profile()
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()
    SaSettings.second_row = _saved_row
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


func _remove_profile() -> void:
    for suffix: String in ["", ".bak", ".broken"]:
        var path := ProjectSettings.globalize_path(SaDataRoot.path("test_erase_on_stays_on_the_bar.cfg")) + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


func _bar() -> TopMenuBar:
    var bar := TopMenuBar.new()
    var options := ToolOptionsBar.new()
    options.target_tool_machine = _machine
    options._ready()
    bar.add_tool_options(options)
    bar._ready()
    # Pinned together for the reason `test_top_bar_rows.gd` gives: the width
    # written below is the width that stays on a detached bar.
    bar.set_anchor(SIDE_RIGHT, 0.0)
    return bar


func test_erase_on_stays_lit_on_a_narrow_bar_and_off_it_leaves() -> void:
    var bar := _bar()
    bar.size.x = NARROW
    bar.apply_layout_settings()
    var rows := bar.rows
    var options: ToolOptionsBar = rows._options
    var erase := options.control_for(ToolOptionsBar.ERASE_KEY) as Button
    assert_not_null(erase, "The brush's Erase is a control on the bar")
    assert_eq(erase.get_parent(), rows.overflow.box, "Off, it leaves a narrow row among the first")

    _machine.active_tool.set(&"eraser_toggled", true)
    assert_eq(rows.kept_on_row(), [String(ToolOptionsBar.ERASE_KEY)] as Array[String], "On, the row holds it")
    assert_eq(erase.get_parent(), rows.row_container(1), "and it is back on the row")
    assert_true(erase.button_pressed, "lit")
    assert_true(erase.visible, "and shown")
    var radius := options.control_for(&"radius")
    assert_eq(radius.get_parent(), rows.overflow.box, "while Size, the last of the rest to leave, has gone")

    erase.button_pressed = false
    assert_false(bool(_machine.active_tool.get(&"eraser_toggled")), "Pressing it turns Erase off")
    assert_eq(erase.get_parent(), rows.overflow.box, "and it leaves the row again")
    bar.free()


func test_the_status_line_shows_why_and_hides_when_there_is_nothing() -> void:
    var line := SaStatusLine.new(func() -> SaSurface: return null)
    line._ready()
    assert_false(line.note_label.visible, "With nothing to say the note is hidden")
    EventBus.stroke_explained.emit(SaStrokeNote.ERASING_NOTHING)
    assert_eq(line.note_label.text, SaStrokeNote.ERASING_NOTHING, "A stroke's reason is on the line")
    assert_true(line.note_label.visible, "and shown")
    EventBus.stroke_explained.emit("")
    assert_false(line.note_label.visible, "and an empty one hides it again")
    line.free()
