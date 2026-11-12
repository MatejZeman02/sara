## View > Show Status Line hides the line along the bottom edge, the canvas gets
## its rows back, and the profile remembers it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The line takes space the canvas can use, so it can be hidden. The row
## is pressed the way a click presses it, through the View menu of a bar bound to
## the application's commands, so the row, the command and the line are the ones
## the app has. A restart is the profile read again from its file and a line
## built anew, which is what a launch does. The running app is
## `scenarios/the-status-line-can-be-hidden-from-the-view-menu.json`.
extends "res://tests/test_framework.gd"

## A real SaCanvas builds an easel, and the bar's View menu reaches for the
## registries, so both need a RenderingDevice.
const REQUIRES_GPU := true

const WINDOW := Vector2i(800, 600)
const BAR := 50.0
const DOCUMENT := Vector2i(256, 256)

var _host: Node = null
var _viewport: SubViewport = null
var _canvas: SaCanvas = null
var _bar: TopMenuBar = null


## Parented to an autoload rather than to the root, for the reason
## `test_canvas_view.gd` gives: the runner calls a suite from its own `_ready`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "D26TestHost"
    EventBus.add_child(_host)
    _viewport = SubViewport.new()
    _viewport.size = WINDOW
    _host.add_child(_viewport)
    _canvas = SaCanvas.new()
    _canvas.canvas_size = DOCUMENT
    _viewport.add_child(_canvas)
    var top := Control.new()
    top.position = Vector2.ZERO
    top.size = Vector2(float(WINDOW.x), BAR)
    top.add_to_group(SaCanvasView.COVER_GROUP)
    _viewport.add_child(top)
    _bar = TopMenuBar.new()
    _bar._ready()
    _bar.bind_commands(SaTestFixtures.make_menu_registries().commands)


func after_each() -> void:
    if _bar != null:
        _bar.free()
        _bar = null
    if _host != null:
        _host.free()
        _host = null
    if SaSettings.config.has_section_key("profile_visibility", _stored_key()):
        SaSettings.config.erase_section_key("profile_visibility", _stored_key())
    SaSettings.save_settings()
    SaSettings.load_settings()


func test_the_row_hides_the_line_the_fit_takes_its_rows_and_a_restart_keeps_it() -> void:
    var line := _new_line()
    var view := SaCanvasView.for_canvas(_canvas)
    var menu := _bar.menu("View") as SaViewMenu
    assert_true(menu.has_item(SaViewMenu.ID_STATUS_LINE), "View has a Show Status Line row")
    assert_true(menu.is_item_checked(SaViewMenu.ID_STATUS_LINE), "ticked on a fresh profile")
    assert_true(line.visible, "and the line is shown")
    assert_true(line.size.y >= float(SaUI.px(SaStatusLine.HEIGHT)), "at least the line's height: %d" % int(line.size.y))
    assert_almost_eq(view.get_visible_rect().end.y, _line_top(line), 1e-3, "The canvas stops at the line's top")

    menu.on_id_pressed(SaViewMenu.ID_STATUS_LINE)
    assert_false(line.visible, "One press hides the line")
    assert_false(line.is_visible_in_tree(), "which is what the view asks of a cover")
    assert_false(menu.is_item_checked(SaViewMenu.ID_STATUS_LINE), "and takes the row's tick")
    assert_almost_eq(view.get_visible_rect().end.y, float(WINDOW.y), 1e-3, "The canvas reaches the window's bottom edge")
    view.fit(DOCUMENT)
    assert_almost_eq(
        view.document_to_screen(Vector2(DOCUMENT)).y, float(WINDOW.y), 1e-3, "and Fit puts the document's last row on it"
    )

    line.free()
    SaSettings.load_settings()
    var after := _new_line()
    assert_false(after.visible, "A line built after the profile is read again stays hidden")
    menu.populate()
    assert_false(menu.is_item_checked(SaViewMenu.ID_STATUS_LINE), "and the row says so")

    menu.on_id_pressed(SaViewMenu.ID_STATUS_LINE)
    assert_true(after.visible, "The second press shows it again")
    assert_true(menu.is_item_checked(SaViewMenu.ID_STATUS_LINE), "ticked again")
    assert_almost_eq(view.get_visible_rect().end.y, _line_top(after), 1e-3, "and the canvas stops at the line's top again")
    view.fit(DOCUMENT)
    assert_almost_eq(view.document_to_screen(Vector2(DOCUMENT)).y, _line_top(after), 1e-3, "so Fit ends above the words")


## The command is in the shortcut list with no chord, so a painter can bind one,
## and it is the row's command rather than a second way to the same switch.
func test_the_command_can_be_bound_and_is_the_rows() -> void:
    var commands := SaTestFixtures.make_menu_registries().commands
    var descriptor := commands.get_descriptor(SaStatusLine.COMMAND)
    assert_true(descriptor != null, "Show Status Line is a registered command")
    assert_eq(descriptor.category, &"view", "filed under View on the shortcuts page")
    assert_true(descriptor.has_tick(), "with a tick")
    assert_true(InputMap.has_action(SaStatusLine.COMMAND), "and an action a chord binds to")
    var menu := _bar.menu("View") as SaViewMenu
    assert_eq(menu.command_at(SaViewMenu.ID_STATUS_LINE), SaStatusLine.COMMAND, "The row runs that command")

    var line := _new_line()
    commands.execute(SaStatusLine.COMMAND)
    assert_false(line.visible, "A chord's press hides the line the way the row does")


func _new_line() -> SaStatusLine:
    var line := SaStatusLine.new(Callable())
    _viewport.add_child(line)
    return line


## Where *line* starts, read off it the way the view reads a cover, rather than
## the window less `HEIGHT`. The two differ in a whole run: an earlier suite,
## `test_dialog_font_scale.gd`, builds the shared theme the app builds at boot
## and leaves it, so a line enters the tree at that theme's full font size, is
## 26 tall in that frame and settles at 24 on the next, when the engine's
## deferred minimum size catches up. A suite cannot await that frame. The
## running app measures 24.
func _line_top(line: SaStatusLine) -> float:
    return line.get_global_rect().position.y


func _stored_key() -> String:
    return "%s_%s" % [SaStatusLine.SETTING_CATEGORY, SaStatusLine.SETTING_ELEMENT]
