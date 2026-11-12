## F5 closes the brush editor it opened.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## F5 is a toggle, as in Krita, whose chord Sara took: F5 opens the brush editor and F5 again puts it
## away, and the top bar's Edit Brush button is the same toggle.
##
## Built as the app builds it: the stamp brush registered through the door, a
## machine on it, the real tool options bar in the tree, the app's commands
## registered by `SaAppCommands.register_all` and a router watching every
## window. A key over the canvas goes in as `Main._unhandled_input` hands it
## on, and a key into the editor as the engine hands it to a window, its
## `window_input` first and then its own tree, the shape the other window suites use.
##
## **The command's handler defers its body**, because a chord pressed over an
## open menu arrives while the popup is mid-hide, and a suite has no frame to
## wait for. So the edit_brush handler is put on `_open_brush_editor_deferred`,
## the very body it defers, and the deferral is the scenario's, which presses
## F5 on the running app:
## `scenarios/f5-closes-the-brush-editor-it-opened.json`.
extends "res://tests/test_framework.gd"

## The editor builds curve controls and a pad with a canvas in it.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StampModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")

const COMMAND := &"edit_brush"

static var scratch_dir: String = SaDataRoot.path("test_f5_toggle")

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _module: SaModule = null
var _machine: ToolMachine = null
var _host: Node = null
var _bar: ToolOptionsBar = null
var _router: ShortcutRouter = null
var _was_embedding: bool = true
var _kept_curve_editor: Callable = Callable()


func before_each() -> void:
    _clear(scratch_dir)
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    # A window added unembedded maps a real OS window and blocks the run.
    tree.root.gui_embed_subwindows = true
    _kept_curve_editor = ToolOptionControls.open_curve_editor
    _surface = Fixtures.make_surface()
    _registries = Fixtures.make_registries(_surface)
    _module = StampModuleScript.new()
    _module.register(_registries.context.for_module(_module.get_id()))
    SaAppCommands.register_all(_registries, func(_docker_id: StringName) -> void: pass)
    var command := _registries.commands.get_descriptor(COMMAND)
    if command != null:
        command.handler = func() -> bool:
            SaAppCommands._open_brush_editor_deferred()
            return true
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _machine._ready()
    _machine.bind(_surface, _registries.tools)
    _machine.set_active_tool(&"brush")

    _host = Node.new()
    _host.name = "U456TestHost"
    EventBus.add_child(_host)
    _bar = ToolOptionsBar.new()
    _bar.name = "ToolOptionsBar"
    _host.add_child(_bar)
    _bar.target_tool_machine = _machine
    _bar.preset_store.dir = scratch_dir
    _bar._ready()
    # The door adds a window it builds to the root, which is busy while the
    # suites run, so the window is built here under the host, where the door's
    # lookup by name finds it and reuses it as it reuses a live one.
    var window := SaBrushEditorWindow.new()
    _host.add_child(window)

    _router = ShortcutRouter.new()
    _router.name = "U456Router"
    _router.canvas_provider = func() -> SaCanvas: return null
    _router.tool_machine_provider = func() -> ToolMachine: return _machine
    _router.commands = _registries.commands
    _host.add_child(_router)
    _router.watch_windows(tree)


func after_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    ToolOptionControls.open_curve_editor = _kept_curve_editor
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
    if not path.ends_with("test_f5_toggle") or not DirAccess.dir_exists_absolute(path):
        return
    for file_name: String in DirAccess.get_files_at(path):
        DirAccess.remove_absolute(path.path_join(file_name))
    DirAccess.remove_absolute(path)


## A press of F5 as a keyboard sends it, through whatever the InputMap holds.
static func _f5() -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = KEY_F5
    key.physical_keycode = KEY_F5
    key.pressed = true
    return key


func _press_over_the_canvas(event: InputEvent) -> void:
    _router.handle_viewport_input(event, (Engine.get_main_loop() as SceneTree).root)


static func _press_into(window: Window, event: InputEvent) -> void:
    window.window_input.emit(event)
    window.push_input(event)


func _editor() -> SaBrushEditorWindow:
    return SaBrushEditorDoor.live_window(Engine.get_main_loop() as SceneTree) as SaBrushEditorWindow


func _is_open() -> bool:
    var window := _editor()
    return window != null and window.visible


func test_f5_is_edit_brush_in_the_input_map() -> void:
    assert_true(InputMap.has_action(String(COMMAND)), "edit_brush is an InputMap action")
    assert_true(_f5().is_action_pressed(String(COMMAND), false, true), "and F5 is its chord")


func test_f5_twice_over_the_main_window_opens_then_closes() -> void:
    assert_false(_is_open(), "No editor is open to begin with")
    _press_over_the_canvas(_f5())
    assert_true(_is_open(), "F5 over the main window opens the brush editor")
    assert_eq(_editor().tool_state, _bar.shown_tool(), "on the brush in hand")
    _press_over_the_canvas(_f5())
    assert_false(_is_open(), "F5 again closes it")
    assert_not_null(_editor(), "and the window is kept, as its own Close keeps it")
    _press_over_the_canvas(_f5())
    assert_eq(_editor().tool_state, _bar.shown_tool(), "Opened again it is bound to the brush in hand")


func test_f5_into_the_editor_closes_it() -> void:
    _press_over_the_canvas(_f5())
    assert_true(_is_open(), "F5 over the main window opens the brush editor")
    _press_into(_editor(), _f5())
    assert_false(_is_open(), "F5 pressed with the editor focused closes it")
    _press_over_the_canvas(_f5())
    assert_true(_is_open(), "and F5 over the main window opens it again")


func test_f5_with_a_text_field_focused_still_closes_the_editor() -> void:
    _press_over_the_canvas(_f5())
    var window := _editor()
    var fields := window.find_children("*", "LineEdit", true, false)
    assert_false(fields.is_empty(), "The editor holds a text field")
    if fields.is_empty():
        return
    var field := fields[0] as LineEdit
    field.grab_focus()
    assert_true(field.has_focus(), "the text field holds the keyboard")
    _press_into(window, _f5())
    assert_false(_is_open(), "F5 types nothing, so the field does not keep it and the editor closes")


func test_the_bars_edit_brush_button_twice_opens_then_closes() -> void:
    assert_not_null(_bar.edit_brush_btn, "The bar has its Edit Brush button")
    _bar.edit_brush_btn.pressed.emit()
    assert_true(_is_open(), "The first press opens the brush editor")
    _bar.edit_brush_btn.pressed.emit()
    assert_false(_is_open(), "the second closes it")


func test_the_editor_window_stands_under_a_thousand_lines() -> void:
    var source := FileAccess.get_file_as_string("res://ui/brush_editor/brush_editor_window.gd")
    assert_false(source.is_empty(), "The window's file is readable")
    assert_true(source.split("\n").size() < 1000, "and stands under a thousand lines")
