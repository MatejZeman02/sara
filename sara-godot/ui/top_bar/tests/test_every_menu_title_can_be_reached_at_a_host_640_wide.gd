## Every menu title can be reached at a host 640 wide.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## At scale 2 a 1280 by 1024 or 1280 by 800 panel is a host of 640 logical
## pixels, and the first row laid out unchecked would be 818 wide in it, with
## Modules cut at the window's edge and Help, the tool options' overflow
## button and the window buttons past it. The titles that do not fit
## leave the row from its end and wait behind its last title,
## `SaTopBarMenuOverflow`, whose list opens their menus.
##
## **The host is 640 wide in logical pixels, which is what scale 2 makes a 1280
## panel.** The scale is the window's `content_scale_factor` alone and every
## size on the bar is logical, `SaUI.px` being the identity, so the bar laid out
## in a host 640 wide is the bar a 1280 panel at scale 2 draws, and the running
## app's proof at both panels is
## `scenarios/every-menu-title-can-be-reached-at-a-host-640-wide.json`.
##
## **The bar hangs from a `Node` in a viewport 640 wide, the way it hangs from
## `Main` in the window.** `Main` is a `Node`, so the bar's anchors measure the
## window's own rect, and a bar under a control would have taken its width from
## a path the app never takes. A bar under a control would read the room for
## the titles off its own width, 802 where the window is 640. The viewport embeds its own lists, so they are real windows
## that open and close inside it. Everything is asked in one frame, since a test
## that awaits drops every assertion after the await, so the rows are
## sorted by hand where the engine would sort them a frame later.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The bar's controls come from the tools' descriptors, which need a device, and
## its lists are windows.
const REQUIRES_GPU := true

## The host a 1280 by 1024 panel at scale 2 makes, in logical pixels.
const HOST := Vector2i(640, 512)

## A host at 1920 by 1080 at scale 1, where all eleven fit.
const WIDE := Vector2i(1920, 1080)

## The scratch profile, absent before each test, so the bar is a fresh one.
static var scratch_profile: String = SaDataRoot.path("test_d99_menu_overflow_profile.cfg")

var _saved_path: String
var _saved_row: bool
var _surface: SaSurface
var _machine: ToolMachine
## The window the bar is drawn in, and the node it hangs from there, `Main`'s
## place.
var _window: SubViewport
var _main: Node


func before_each() -> void:
    _saved_path = SaSettings.settings_path
    _saved_row = SaSettings.second_row
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_profile)
    _remove_profile()
    SaSettings.load_settings()
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    # Parented to an autoload rather than to the root, because the runner calls
    # a suite from its own `_ready`.
    _window = SubViewport.new()
    _window.name = "D99Window"
    _window.gui_embed_subwindows = true
    _window.render_target_update_mode = SubViewport.UPDATE_DISABLED
    EventBus.add_child(_window)
    _main = Node.new()
    _main.name = "D99Main"
    _window.add_child(_main)


## The run's own profile is put back as it was, the switch with it, since a
## later suite reads the bar it leaves.
func after_each() -> void:
    _window.free()
    Fixtures.teardown(_surface, _machine)
    _remove_profile()
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()
    SaSettings.second_row = _saved_row


func _remove_profile() -> void:
    for suffix: String in ["", ".bak", ".broken"]:
        var path := ProjectSettings.globalize_path(scratch_profile) + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


## A bar with its tool options and its commands, the way main builds it,
## anchored across the top of a window *host* large, and laid out.
func _bar(host: Vector2i) -> TopMenuBar:
    _window.size = host
    var options := ToolOptionsBar.new()
    options.target_tool_machine = _machine
    options._ready()
    var bar := TopMenuBar.new()
    bar.add_tool_options(options)
    _main.add_child(bar)
    var note_mode := SaNoteMode.new()
    bar.add_child(note_mode)
    bar.bind_commands(Fixtures.make_menu_registries(note_mode).commands)
    _lay_out(bar)
    return bar


## The bar measured against its window again, and its rows sorted inside it.
## The engine measures the bar again once its minimum has moved, a frame after
## the fit that moved it, so an offset is written here, which measures it there
## and then. A size written over anchors that differ would do the same with a
## warning.
func _lay_out(bar: TopMenuBar) -> void:
    bar.offset_bottom = bar.get_combined_minimum_size().y
    for box: Container in [
        bar,
        bar.rows,
        bar.rows.main_row,
        bar.rows.second_row,
        bar.menu_bar.get_parent() as Container,
        bar.menu_bar,
        bar.window_buttons,
    ]:
        box.notification(Container.NOTIFICATION_SORT_CHILDREN)


## Whether *control* is on screen and inside the window's width.
func _inside(control: Control) -> bool:
    var rect := control.get_global_rect()
    return control.is_visible_in_tree() and rect.position.x >= 0.0 and rect.end.x <= float(_window.size.x) + 0.5


## Where *control* runs from and to, for a message.
func _span(control: Control) -> String:
    var rect := control.get_global_rect()
    return "%s from %.0f to %.0f in %d" % [control.name, rect.position.x, rect.end.x, _window.size.x]


## The ask's first half for one setting of the second row: every menu on the
## row inside the window or behind a last title that is, and the window
## buttons and the overflow button inside it as well.
func _every_menu_is_reachable(bar: TopMenuBar) -> void:
    var fold := bar.menu_overflow
    assert_true(
        bar.get_combined_minimum_size().x <= float(_window.size.x),
        "The bar asks for %.0f of the %d it has" % [bar.get_combined_minimum_size().x, _window.size.x]
    )
    for menu_name: String in TopMenuBar.MENU_NAMES:
        var title: Button = bar.menu_buttons[menu_name]
        if fold.folded.has(menu_name):
            assert_false(title.visible, "%s waits behind the last title, off the row" % menu_name)
            assert_true(_inside(fold), "%s is behind a title inside the window, %s" % [menu_name, _span(fold)])
        else:
            assert_true(_inside(title), "%s is on the row inside the window, %s" % [menu_name, _span(title)])
    assert_true(fold.folded.has("Help"), "Help, the last title, is one that waits: %s" % [fold.folded])
    assert_true(_inside(bar.window_buttons), "The window buttons are inside the window, %s" % _span(bar.window_buttons))
    var overflow := bar.rows.overflow
    assert_true(_inside(overflow), "The overflow button shows inside the window, %s" % _span(overflow))
    assert_true(overflow.held().size() > 0, "and holds the tool options the bar has no room for")


func test_with_the_second_row_on_every_menu_is_on_the_row_or_behind_its_last_title() -> void:
    assert_true(SaSettings.second_row, "A fresh profile has the second row on")
    var bar := _bar(HOST)
    assert_true(bar.rows.second_row.visible, "so the bar shows it")
    assert_true(bar.rows.second_row.is_ancestor_of(bar.rows.overflow), "with the overflow button at its end")
    _every_menu_is_reachable(bar)


func test_with_the_first_row_on_its_own_every_menu_is_on_the_row_or_behind_its_last_title() -> void:
    SaSettings.second_row = false
    var bar := _bar(HOST)
    assert_false(bar.rows.second_row.visible, "The second row is off")
    assert_true(bar.rows.main_row.is_ancestor_of(bar.rows.overflow), "so the overflow button is on the first row")
    _every_menu_is_reachable(bar)


## The titles on the row are the profile's first
## ones and the folded are the rest, in the same order.
func test_the_titles_leave_from_the_rows_end_in_the_profiles_order() -> void:
    var bar := _bar(HOST)
    var on_row: Array = bar.menu_overflow.report()["on_row"]
    assert_eq(
        on_row + bar.menu_overflow.folded,
        TopMenuBar.MENU_NAMES,
        "The row and the list behind its last title read the eleven in order"
    )
    assert_true(on_row.size() > 0 and on_row[0] == "File", "File is still the first title, %s" % [on_row])


## The ask's "a press reaching Help": a press on the last title opens the list
## of the titles that wait, and a press on Help there opens Help's own menu
## under that title.
func test_a_press_reaches_help() -> void:
    var bar := _bar(HOST)
    var fold := bar.menu_overflow
    fold.pressed.emit()
    assert_true(fold.list.visible, "A press on the last title opens its list")
    assert_true(Array(fold.list.row_labels()).has("Help"), "which holds Help, %s" % [fold.list.row_labels()])
    assert_true(fold.list.press_row(&"Help"), "Help's row takes a press")
    assert_false(fold.list.visible, "the list closes on it")
    var help: SaChoicePopup = bar.menus["Help"]
    assert_true(help.visible, "and Help's own menu opens")
    assert_true(help.row_ids().size() > 0, "with its rows in it, %s" % [help.row_labels()])
    _opens_under(help, fold)


## Whether *popup* stands under *title* and inside the window: its top at the
## title's foot, and across the title, moved left from the title's own left edge
## only as far as the window's right edge asks.
func _opens_under(popup: SaChoicePopup, title: Control) -> void:
    var under := SaPopupRect.of_anchor(title)
    var rect := Rect2(Vector2(popup.position), Vector2(popup.size))
    assert_true(absf(rect.position.y - under.end.y) <= 1.0, "under the last title: %s against %s" % [rect, under])
    assert_true(
        rect.position.x <= under.position.x + 1.0 and rect.end.x >= under.end.x - 1.0, "across it: %s against %s" % [rect, under]
    )
    assert_true(
        rect.position.x >= 0.0 and rect.end.x <= float(_window.size.x) + 0.5,
        "and inside the window, %s in %d" % [rect, _window.size.x]
    )


## A second press on the last title is the close, and a press on a title still
## on the row closes the list the way a press on another menu does.
func test_a_second_press_closes_the_list() -> void:
    var bar := _bar(HOST)
    var fold := bar.menu_overflow
    fold.pressed.emit()
    fold.pressed.emit()
    assert_false(fold.list.visible, "The second press closes the list")
    fold.pressed.emit()
    bar._on_menu_button_pressed("File")
    assert_false(fold.list.visible, "and File's title closes it as it opens File")
    assert_true((bar.menus["File"] as SaChoicePopup).visible, "File's menu is open")


## The door's `menu` step and every other caller of the bar's handler open a
## waiting menu under the last title rather than under a title that is not on
## screen.
func test_a_waiting_menu_opened_by_name_opens_under_the_last_title() -> void:
    var bar := _bar(HOST)
    var fold := bar.menu_overflow
    var waiting: String = fold.folded[0]
    bar._on_menu_button_pressed(waiting)
    var popup: SaChoicePopup = bar.menus[waiting]
    assert_true(popup.visible, "%s opens" % waiting)
    _opens_under(popup, fold)


## The row stays as it was wherever all eleven fit: at 1920 every title is on
## it and the last title is not drawn.
func test_at_1920_the_row_is_as_it_was() -> void:
    var bar := _bar(WIDE)
    assert_false(bar.menu_overflow.visible, "The last title is not drawn")
    assert_eq(bar.menu_overflow.folded, [] as Array[String], "and holds nothing")
    for menu_name: String in TopMenuBar.MENU_NAMES:
        var title: Button = bar.menu_buttons[menu_name]
        assert_true(_inside(title), "%s is on the row, %s" % [menu_name, _span(title)])


## A window made wider changes no setting, and the titles come back to the row
## all the same, by the resize the bar already answers.
func test_widening_the_host_brings_every_title_back() -> void:
    var bar := _bar(HOST)
    assert_true(bar.menu_overflow.visible, "At 640 the last title shows")
    _window.size = WIDE
    _lay_out(bar)
    assert_false(bar.menu_overflow.visible, "At 1920 it is gone")
    assert_eq(bar.menu_overflow.report()["on_row"], TopMenuBar.MENU_NAMES, "and all eleven are on the row")


## A title the painter hid in Preferences stays hidden, on the row and in the
## list, since the list holds what did not fit and not what was put away.
func test_a_hidden_title_is_in_neither_place() -> void:
    SaSettings.set_element_visible("TopMenuBar", "Modules", false)
    var bar := _bar(HOST)
    var title: Button = bar.menu_buttons["Modules"]
    assert_false(title.visible, "Modules is off the row")
    assert_false(bar.menu_overflow.folded.has("Modules"), "and not behind the last title, %s" % [bar.menu_overflow.folded])
