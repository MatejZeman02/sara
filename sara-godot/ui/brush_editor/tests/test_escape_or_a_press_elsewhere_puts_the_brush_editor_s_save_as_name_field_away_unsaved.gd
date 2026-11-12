## Escape or a press elsewhere puts the Brush Editor's Save As name field away
## unsaved.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The field Save As and Rename swap in for the preset's name must not have only
## Return as its way out. It follows the Brush Presets panel's rule: Return writes, and Escape or a press anywhere
## else puts the field away, writes nothing and brings the name back, with the
## editor still open.
##
## Built as the F5 suite builds it: the stamp brush registered through the
## door, the real tool options bar, the app's commands and a router watching
## every window, so Escape reaches the editor the way the engine hands it to a
## window, its `window_input` first and then its own tree.
extends "res://tests/test_framework.gd"

## The editor builds curve controls and a pad with a canvas in it.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StampModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")

static var scratch_dir: String = SaDataRoot.path("test_name_field")

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _module: SaModule = null
var _machine: ToolMachine = null
var _host: Node = null
var _bar: ToolOptionsBar = null
var _router: ShortcutRouter = null
var _was_embedding: bool = true


func before_each() -> void:
    _clear(scratch_dir)
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    # A window added unembedded maps a real OS window and blocks the run.
    tree.root.gui_embed_subwindows = true
    _surface = Fixtures.make_surface()
    _registries = Fixtures.make_registries(_surface)
    _module = StampModuleScript.new()
    _module.register(_registries.context.for_module(_module.get_id()))
    SaAppCommands.register_all(_registries, func(_docker_id: StringName) -> void: pass)
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _machine._ready()
    _machine.bind(_surface, _registries.tools)
    _machine.set_active_tool(&"brush")

    _host = Node.new()
    _host.name = "U587TestHost"
    EventBus.add_child(_host)
    _bar = ToolOptionsBar.new()
    _bar.name = "ToolOptionsBar"
    _host.add_child(_bar)
    _bar.target_tool_machine = _machine
    _bar.preset_store.dir = scratch_dir
    _bar._ready()
    # Under the host rather than the busy root, where the door's lookup by
    # name finds it and reuses it, as the F5 suite does.
    _host.add_child(SaBrushEditorWindow.new())

    _router = ShortcutRouter.new()
    _router.name = "U587Router"
    _router.canvas_provider = func() -> SaCanvas: return null
    _router.tool_machine_provider = func() -> ToolMachine: return _machine
    _router.commands = _registries.commands
    _host.add_child(_router)
    _router.watch_windows(tree)
    SaAppCommands._open_brush_editor_deferred()


func after_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if _host != null:
        EventBus.remove_child(_host)
        _host.free()
        _host = null
        _bar = null
        _router = null
    Fixtures.teardown(_surface, _machine)
    _machine = null
    _surface = null
    _module.unregister(_registries.context)
    _registries.context.for_module(_module.get_id()).remove_all_registrations()
    _module = null
    _registries = null
    tree.root.gui_embed_subwindows = _was_embedding
    _clear(scratch_dir)


## Empties the suite's own folder and nothing else.
func _clear(path: String) -> void:
    if not path.ends_with("test_name_field") or not DirAccess.dir_exists_absolute(path):
        return
    for file_name: String in DirAccess.get_files_at(path):
        DirAccess.remove_absolute(path.path_join(file_name))
    DirAccess.remove_absolute(path)


func _editor() -> SaBrushEditorWindow:
    return SaBrushEditorDoor.live_window(Engine.get_main_loop() as SceneTree) as SaBrushEditorWindow


func _names() -> PackedStringArray:
    return _editor().preset_bar.session.preset_store.list_names()


static func _escape() -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = KEY_ESCAPE
    key.physical_keycode = KEY_ESCAPE
    key.pressed = true
    return key


static func _press_into(window: Window, event: InputEvent) -> void:
    window.window_input.emit(event)
    window.push_input(event)


## A left press and its release in the middle of the editor's pages, given to
## the window as the engine gives a click.
func _click_the_pages() -> void:
    var window := _editor()
    var at := window.pages.page_body.get_global_rect().get_center()
    for down: bool in [true, false]:
        var click := InputEventMouseButton.new()
        click.button_index = MOUSE_BUTTON_LEFT
        click.pressed = down
        click.position = at
        click.global_position = at
        _press_into(window, click)


## The editor with a preset stored and loaded, so Rename has a name to change.
func _on_a_stored_preset(stored: String) -> SaBrushEditorPresetBar:
    var bar := _editor().preset_bar
    bar.begin_save_as()
    bar.write_named(stored)
    return bar


## What the field's being put away reads as, said under *how*.
func _assert_put_away(bar: SaBrushEditorPresetBar, label: String, how: String) -> void:
    assert_false(bar.preset_name_edit.visible, "%s hides the name field" % how)
    assert_true(bar.preset_label.visible, "and shows the preset's name again")
    assert_eq(bar.preset_label.text, label, "which reads as it did before")
    assert_true(_editor().visible, "and the Brush Editor is still open")


func test_the_editor_is_open_on_the_brush() -> void:
    assert_not_null(_editor(), "The Brush Editor is built")
    assert_true(_editor().visible, "and open")


func test_escape_puts_save_as_away_and_writes_nothing() -> void:
    var bar := _editor().preset_bar
    var label := bar.preset_label.text
    bar.save_as_button.pressed.emit()
    assert_true(bar.preset_name_edit.visible, "Save As swaps the name field in")
    assert_true(bar.preset_name_edit.has_focus(), "with the keyboard")
    bar.preset_name_edit.text = "Typed but never saved"
    _press_into(_editor(), _escape())
    _assert_put_away(bar, label, "Escape")
    assert_eq(_names().size(), 0, "and no preset was written")


func test_a_press_on_the_pages_puts_save_as_away_and_writes_nothing() -> void:
    var bar := _editor().preset_bar
    var label := bar.preset_label.text
    bar.save_as_button.pressed.emit()
    bar.preset_name_edit.text = "Typed but never saved"
    _click_the_pages()
    _assert_put_away(bar, label, "A press on the pages")
    assert_eq(_names().size(), 0, "and no preset was written")


func test_escape_puts_rename_away_and_the_old_file_stays() -> void:
    var bar := _on_a_stored_preset("Inker")
    assert_eq(_names(), PackedStringArray(["Inker"]), "The editor is on a stored preset")
    bar.rename_button.pressed.emit()
    assert_true(bar.preset_name_edit.visible, "Rename swaps the name field in")
    bar.preset_name_edit.text = "Liner"
    _press_into(_editor(), _escape())
    _assert_put_away(bar, "Inker", "Escape")
    assert_eq(_names(), PackedStringArray(["Inker"]), "and the old file stays, with no new one")
    assert_eq(bar.session.preset_name, "Inker", "the editor still on it")


func test_a_press_on_the_pages_puts_rename_away_and_the_old_file_stays() -> void:
    var bar := _on_a_stored_preset("Inker")
    bar.rename_button.pressed.emit()
    bar.preset_name_edit.text = "Liner"
    _click_the_pages()
    _assert_put_away(bar, "Inker", "A press on the pages")
    assert_eq(_names(), PackedStringArray(["Inker"]), "and the old file stays, with no new one")


func test_escape_after_rename_leaves_the_next_save_as_a_copy() -> void:
    var bar := _on_a_stored_preset("Inker")
    bar.rename_button.pressed.emit()
    _press_into(_editor(), _escape())
    bar.save_as_button.pressed.emit()
    bar.preset_name_edit.text_submitted.emit("Liner")
    var names := _names()
    names.sort()
    assert_eq(names, PackedStringArray(["Inker", "Liner"]), "Save As after a put-away Rename copies and keeps the old file")


func test_return_with_a_typed_name_still_writes_the_copy() -> void:
    var bar := _on_a_stored_preset("Inker")
    bar.save_as_button.pressed.emit()
    bar.preset_name_edit.text_submitted.emit("Inker copy")
    var names := _names()
    names.sort()
    assert_eq(names, PackedStringArray(["Inker", "Inker copy"]), "Return writes the copy beside the original")
    assert_false(bar.preset_name_edit.visible, "and puts the field away")
    assert_eq(bar.preset_label.text, "Inker copy", "the editor on the copy")


func test_return_with_an_empty_name_writes_nothing_and_keeps_the_field() -> void:
    var bar := _editor().preset_bar
    bar.save_as_button.pressed.emit()
    bar.preset_name_edit.text_submitted.emit("   ")
    assert_eq(_names().size(), 0, "An empty name writes nothing")
    assert_true(bar.preset_name_edit.visible, "and the field stays open for one")


func test_the_fields_own_menu_leaves_the_field_open() -> void:
    var bar := _editor().preset_bar
    bar.save_as_button.pressed.emit()
    var field := bar.preset_name_edit
    var menu := field.get_menu()
    menu.popup(Rect2i(Vector2i(field.get_global_rect().get_center()), Vector2i.ZERO))
    assert_true(field.is_menu_visible(), "The field's right-click menu is up")
    assert_true(field.visible, "over a field still open under it")
    field.focus_exited.emit()
    assert_true(field.visible, "The field stays open when its own menu takes the keyboard")
    menu.hide()
    assert_false(field.is_menu_visible(), "The menu shut")
    assert_true(field.visible, "leaves the field open")
    assert_true(_editor().visible, "in an editor still open")
