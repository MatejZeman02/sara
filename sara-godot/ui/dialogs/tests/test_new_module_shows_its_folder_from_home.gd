## New Module shows its folder from the home folder and keeps its buttons at the
## bottom edge.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## New Module once printed a long absolute path and left blank under its
## buttons. The hint now writes the home folder
## as "~" and holds the whole path in its tooltip, and the row goes through
## `SaDialogWindow.pinned_buttons` with the window opening at its floor.
##
## The dialog is opened embedded and laid out by hand, for the reason
## `test_a_dialogs_buttons_sit_in_one_row` gives: no frame passes inside a test.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

## The screen the dialog opens on, in logical units.
const SCREEN := Vector2i(1280, 800)

## The height New Module's constructor declares as its floor and opens at.
const FLOOR_HEIGHT := 240

## The room a 1280 by 800 screen leaves at a scale of 2 below a one-row bar, in
## logical units, the shortest host the dialogs are held to.
const SHORT_HOST := Vector2i(640, 335)

## A modules folder under the run's data root whose path wraps the hint over
## more lines than `SHORT_HOST` holds, the way a checkout under a
## scratch folder outside `HOME` does. The first part is the one removed after.
const LONG_TOP := "test_new_module_long_folder"
const LONG_FOLDER := (
    LONG_TOP
    + "/a-folder-whose-name-runs-on-the-way-a-scratch-folder-does"
    + "/and-another-one-under-it-just-as-long-as-the-first-one-was"
    + "/and-a-third-so-the-hint-wraps-over-more-lines-than-the-room/modules"
)

var _kept_home: String = ""
var _kept_modules_root: String = ""
var _kept_font_scale: float = 1.0
var _kept_theme: Theme = null
var _kept_embedding: bool = true
var _host: Node = null


func before_each() -> void:
    _kept_home = OS.get_environment("HOME")
    _kept_modules_root = ModuleLoader.user_modules_root
    _kept_font_scale = SaUI.user_font_scale
    _kept_theme = SaUI.shared_theme
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    # A Window added without embedding maps a real OS window and blocks the run.
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "N113NewModuleTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    OS.set_environment("HOME", _kept_home)
    ModuleLoader.user_modules_root = _kept_modules_root
    SaUI.user_font_scale = _kept_font_scale
    SaUI.shared_theme = _kept_theme
    _remove(ProjectSettings.globalize_path(SaDataRoot.path(LONG_TOP)))
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _kept_embedding


## With `HOME` set to a folder the modules folder sits in, the hint starts from
## "~/" and the tooltip carries the path whole.
func test_the_hint_starts_from_home_and_the_tooltip_holds_the_whole_path() -> void:
    var folder := ModuleLoader.user_modules_path()
    OS.set_environment("HOME", folder.get_base_dir())
    var dialog := NewModuleDialog.new()
    var hint := dialog.find_child("HintLabel", true, false) as Label
    assert_true(hint.text.begins_with("Creates a starter module in ~/"), "The hint starts from the home folder: %s" % hint.text)
    assert_false(hint.text.contains(folder), "and does not print the absolute path")
    assert_eq(hint.tooltip_text, folder, "The tooltip holds the full path")
    assert_true(hint.mouse_filter != Control.MOUSE_FILTER_IGNORE, "and the label hears the pointer, so it shows")
    dialog.free()


## Only a path that starts at the home folder is shortened, and a folder whose
## name merely begins with the home folder's is not.
func test_only_a_path_under_home_is_shortened() -> void:
    var under := NewModuleDialog.from_home("/home/ann/.local/share/sara/modules", "/home/ann")
    assert_eq(under, "~/.local/share/sara/modules", "Under home")
    assert_eq(NewModuleDialog.from_home("/home/ann/modules", "/home/ann/"), "~/modules", "A home with a trailing slash")
    assert_eq(NewModuleDialog.from_home("/home/ann", "/home/ann"), "~", "Home itself")
    var sibling := NewModuleDialog.from_home("/home/anna/modules", "/home/ann")
    assert_eq(sibling, "/home/anna/modules", "A sibling that shares the prefix")
    assert_eq(NewModuleDialog.from_home("/opt/sara/modules", "/home/ann"), "/opt/sara/modules", "Outside home")
    assert_eq(NewModuleDialog.from_home("C:/Users/ann/modules", ""), "C:/Users/ann/modules", "No home at all")


## The row is the pinned one, and it ends at the bottom margin as the dialog
## opens and again dragged taller, with no blank band under it.
func test_the_buttons_end_at_the_bottom_margin() -> void:
    var dialog := _place(NewModuleDialog.new())
    dialog.fit_opening_size()
    _sort(dialog)
    # Pinned by the scrolling body, which expands, so the helper adds no spacer
    # beside it.
    assert_eq(dialog.find_child("ButtonsSpacer", true, false), null, "The row is pinned by the expanding notes")
    assert_eq(dialog.scrolling_body, dialog.find_child("NotesScroll", true, false), "which are the scrolling body")
    assert_almost_eq(_row_bottom(dialog), _bottom_margin(dialog), 1.0, "The row ends at the bottom margin")
    # A pixel of slack, because `_sort` nudges the window a pixel and back.
    var fits := _column_height(dialog) + 1
    assert_true(dialog.size.y <= fits, "and the dialog opens no taller than its column, %d of %d" % [dialog.size.y, fits])
    dialog.size = dialog.size + Vector2i(0, 160)
    _sort(dialog)
    assert_almost_eq(_row_bottom(dialog), _bottom_margin(dialog), 1.0, "and still does dragged taller")
    var row := dialog.find_child("Buttons", true, false) as HBoxContainer
    assert_eq(row.get_children().back(), dialog.default_button, "with Create last")


## However long the folder, the dialog opens at its column and no taller.
##
## The hint was wrapped at two widths: under the scroll bar the notes show while
## the dialog is still at its floor, and at the whole width once the fit has
## made room and the bar has gone. A folder whose last word broke between the
## two opened the dialog a line taller than its column, and which folder that
## is depends on where the checkout sits, so a run could pass in one checkout and
## fail in another. Every length up
## to ninety more characters passes both kinds of break on this font.
func test_no_folder_length_opens_the_dialog_taller_than_its_column() -> void:
    for extra in range(1, 91):
        ModuleLoader.user_modules_root = SaDataRoot.path(LONG_TOP + "/" + "x".repeat(extra))
        var dialog := _place(NewModuleDialog.new())
        dialog.fit_opening_size()
        _sort(dialog)
        var fits := _column_height(dialog) + 1
        if dialog.size.y > fits:
            var opened := "A folder %d characters longer opens the dialog %d high" % [extra, dialog.size.y]
            assert_true(false, "%s, its column %d" % [opened, fits])
            return
        dialog.get_parent().free()
    assert_true(true, "No folder length opens the dialog taller than its column")


## A folder whose path wraps the hint past a short host scrolls the hint and
## keeps Cancel and Create inside the window, wherever the folder is.
##
## The run once failed here when its checkout sat under a long scratch folder
## outside `HOME`: the hint printed the path whole, wrapped it over line after
## line at the dialog's width, and the row ended under the 335 the host had.
func test_a_long_folder_scrolls_the_hint_and_keeps_the_buttons() -> void:
    ModuleLoader.user_modules_root = SaDataRoot.path(LONG_FOLDER)
    # No home, so the path is printed whole, as it is on Windows.
    OS.set_environment("HOME", "")
    # The app's own theme at the default Font size, for the reason the suite of
    # every dialog at every size gives: Godot's smaller default font wrapped
    # the same hint into a window it fitted.
    SaUI.user_font_scale = 1.0
    SaUI.init_global_theme(null)
    var dialog := _place(NewModuleDialog.new(), SHORT_HOST)
    dialog.fit_opening_size()
    _sort(dialog)

    assert_true(dialog.size.y <= SHORT_HOST.y, "The window is no taller than its host, %d of %d" % [dialog.size.y, SHORT_HOST.y])
    var frame := Rect2(Vector2.ZERO, Vector2(dialog.size))
    for button_name: String in ["CancelButton", "CreateButton"]:
        var button := dialog.find_child(button_name, true, false) as Button
        assert_true(
            frame.encloses(button.get_global_rect()),
            "%s at %s lies inside the window %s" % [button_name, button.get_global_rect(), frame]
        )

    var notes := dialog.find_child("NotesScroll", true, false) as ScrollContainer
    assert_not_null(notes, "The hint is in a scroll")
    if notes == null:
        return
    assert_eq(dialog.scrolling_body, notes, "which is the scrolling body")
    var wanted := (notes.get_child(0) as Control).get_combined_minimum_size().y
    assert_true(
        wanted > notes.size.y,
        "and wants more than the host leaves it, %d against %d, so it scrolls" % [int(wanted), int(notes.size.y)]
    )


func _place(dialog: SaDialogWindow, screen_size: Vector2i = SCREEN) -> SaDialogWindow:
    var screen := SubViewport.new()
    screen.size = screen_size
    screen.gui_embed_subwindows = true
    _host.add_child(screen)
    screen.add_child(dialog)
    dialog.popup_centered()
    _sort(dialog)
    return dialog


## The height *dialog*'s column asks for with its notes whole, or the floor when
## that is more. The notes ask the column for no more than the scrolling body's
## floor and the dialog opens with them whole, so the column is counted with them
## whole: counted at the floor, a folder long enough to wrap past it read as a
## blank band that was the hint.
func _column_height(dialog: SaDialogWindow) -> int:
    var notes := dialog.scrolling_body
    var whole := ceili((notes.get_child(0) as Control).get_combined_minimum_size().y)
    var column := dialog.content_minimum_size().y - ceili(notes.custom_minimum_size.y) + whole
    return maxi(FLOOR_HEIGHT, column)


func _row_bottom(dialog: SaDialogWindow) -> float:
    var row := dialog.find_child("Buttons", true, false) as Control
    return row.get_global_rect().end.y


func _bottom_margin(dialog: SaDialogWindow) -> float:
    var margin := dialog.content.get_child(0) as MarginContainer
    return float(dialog.size.y - margin.get_theme_constant("margin_bottom"))


## Lays *window* out the way a drawn frame would, for the reason
## `test_a_dialogs_buttons_sit_in_one_row` gives for its own `_sort`.
func _sort(window: Window) -> void:
    for _pass in range(2):
        _sort_under(window)
        _ask_again(window)
    var kept := window.size
    window.size = kept + Vector2i.ONE
    window.size = kept
    _sort_under(window)


func _sort_under(node: Node) -> void:
    for child: Node in node.get_children():
        if child is Container:
            (child as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
        _sort_under(child)


func _ask_again(node: Node) -> void:
    for child: Node in node.get_children():
        _ask_again(child)
        if child is Control:
            (child as Control).update_minimum_size()


## *absolute* and everything under it, the folders `user_modules_path` made.
func _remove(absolute: String) -> void:
    var dir := DirAccess.open(absolute)
    if dir == null:
        return
    for sub: String in dir.get_directories():
        _remove(absolute.path_join(sub))
    for file_name: String in dir.get_files():
        DirAccess.remove_absolute(absolute.path_join(file_name))
    DirAccess.remove_absolute(absolute)
