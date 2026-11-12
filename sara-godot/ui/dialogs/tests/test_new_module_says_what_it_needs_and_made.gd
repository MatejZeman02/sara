## New Module says what it needs and what it made.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Create with the name empty once seemed to do
## nothing, because "Type a name first." sat under the hint inside the scroll
## and below the fold at the dialog's floor. With a name the dialog closed with
## no word of what it made, and the folder in the hint ran under the right edge.
## The problem line now sits outside the scroll above the buttons, the hint
## wraps anywhere, and a Create puts a notice up naming the module and folder.
##
## The dialog is opened embedded and laid out by hand, for the reason
## `test_a_dialogs_buttons_sit_in_one_row` gives: no frame passes inside a test.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

## The screen the dialog opens on, in logical units.
const SCREEN := Vector2i(1280, 800)

## A modules folder under the run's data root, so a Create writes nothing into
## the painter's own. Removed after each test.
const SCRATCH := "test_s67_new_module/modules"

var _opened: Array[String] = []
var _kept_modules_root: String = ""
var _kept_embedding: bool = true
var _host: Node = null


func before_each() -> void:
    _opened.clear()
    NewModuleDialog.opener = func(path: String) -> void: _opened.append(path)
    _kept_modules_root = ModuleLoader.user_modules_root
    ModuleLoader.user_modules_root = SaDataRoot.path(SCRATCH)
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    # A Window added without embedding maps a real OS window and blocks the run.
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "S67NewModuleTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    NewModuleDialog.opener = OS.shell_open
    ModuleLoader.user_modules_root = _kept_modules_root
    _remove(ProjectSettings.globalize_path(SaDataRoot.path(SCRATCH.get_base_dir())))
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _kept_embedding


## An empty Create shows its line inside the window at the floor it opens at,
## outside the scroll, and puts the keyboard back in the name field.
func test_an_empty_create_says_so_inside_the_window() -> void:
    var dialog := _place(NewModuleDialog.new())
    dialog.fit_opening_size()
    _sort(dialog)
    var notes := dialog.find_child("NotesScroll", true, false) as ScrollContainer
    var status := dialog.find_child("StatusLabel", true, false) as Label
    assert_not_null(status, "The dialog has a problem line")
    if status == null or notes == null:
        return
    assert_false(notes.is_ancestor_of(status), "which is not inside the scroll")

    dialog._name_field.text = "   "
    dialog._on_confirmed()
    # The fit `_say_problem` asks for a frame later, which no frame here runs.
    _sort(dialog)
    dialog.fit_opening_size()
    _sort(dialog)
    assert_true(status.visible, "An empty Create shows it")
    assert_eq(status.text, "Type a name first.", "asking for a name")
    var frame := Rect2(Vector2.ZERO, Vector2(dialog.size))
    assert_true(frame.encloses(status.get_global_rect()), "inside the window, %s in %s" % [status.get_global_rect(), frame])
    var buttons := dialog.find_child("Buttons", true, false) as Control
    assert_true(status.get_global_rect().end.y <= buttons.get_global_rect().position.y + 0.5, "above the buttons")
    var create := dialog.find_child("CreateButton", true, false) as Button
    assert_true(frame.encloses(create.get_global_rect()), "which stay inside the window, %s" % create.get_global_rect())
    assert_true(dialog._name_field.has_focus(), "and the keyboard is back in the name field")
    assert_eq(_opened, [] as Array[String], "with nothing opened")


## The hint breaks a folder anywhere, since a path has no space to break at.
func test_the_hint_wraps_a_path_anywhere() -> void:
    var dialog := NewModuleDialog.new()
    var hint := dialog.find_child("HintLabel", true, false) as Label
    assert_eq(hint.autowrap_mode, TextServer.AUTOWRAP_ARBITRARY, "The hint wraps arbitrarily")
    assert_eq(hint.tooltip_text, ModuleLoader.user_modules_path(), "and the whole path stays on the tooltip")
    dialog.free()


## A Create opens the folder as before and says what it made in the notice.
func test_a_create_names_the_module_in_the_notice() -> void:
    SaMessage.install(_host)
    var dialog := _place(NewModuleDialog.new())
    dialog._name_field.text = "zz s67 module"
    dialog._on_confirmed()
    var dir_path := ModuleLoader.user_modules_path().path_join("zz-s67-module")
    assert_true(FileAccess.file_exists(dir_path.path_join("module.gd")), "Create writes the starter")
    assert_eq(_opened, [dir_path], "and still shows the painter its folder")
    assert_false(dialog.visible, "and closes")
    var notice := SaMessage.notice_widget()
    assert_not_null(notice, "The notice is installed")
    if notice == null:
        return
    assert_true(notice.showing(), "A line is up")
    assert_true(notice.label.text.contains("zz-s67-module"), "naming the module: %s" % notice.label.text)
    var shown := NewModuleDialog.from_home(ModuleLoader.user_modules_path(), OS.get_environment("HOME"))
    assert_true(notice.label.text.contains(shown), "and the folder it sits in")
    assert_true(notice.label.text.contains("Restart Sara"), "and what loads it")


func _place(dialog: SaDialogWindow, screen_size: Vector2i = SCREEN) -> SaDialogWindow:
    var screen := SubViewport.new()
    screen.size = screen_size
    screen.gui_embed_subwindows = true
    _host.add_child(screen)
    screen.add_child(dialog)
    dialog.popup_centered()
    _sort(dialog)
    return dialog


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


## *absolute* and everything under it.
func _remove(absolute: String) -> void:
    var dir := DirAccess.open(absolute)
    if dir == null:
        return
    for sub: String in dir.get_directories():
        _remove(absolute.path_join(sub))
    for file_name: String in dir.get_files():
        DirAccess.remove_absolute(absolute.path_join(file_name))
    DirAccess.remove_absolute(absolute)
