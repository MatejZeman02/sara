## With a text block in hand, Ctrl+A selects the block's letters and not the
## canvas, typing or deleting then replaces them, and an arrow key puts the
## caret at the selection's edge. With no block in hand, Ctrl+A still selects
## the canvas.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const Recipe = preload("res://modules/sara-base-modules/text/sa_text_recipe.gd")
const StateText = preload("res://modules/sara-base-modules/text/edit/state_text.gd")

const SIZE := Vector2i(512, 256)
const AT := Vector2(100.0, 140.0)

var _surface: SaSurface = null
var _doc: SaDocument = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _machine: ToolMachine = null
var _router: ShortcutRouter = null
var _clipboard_mock: String = ""


func before_each() -> void:
    _surface = Fixtures.make_surface(SIZE)
    _surface.easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _doc = _surface.get_document()
    _registries = SaRegistries.new()
    _registries.build_context(func() -> SaEasel: return _surface.easel, func() -> Array: return [_surface])
    _registries.register_builtins()
    _modules.clear()
    for path: String in ["stamp-brush", "base", "text"]:
        var module: SaModule = load("res://modules/sara-base-modules/%s/module.gd" % path).new()
        module.register(_registries.context.for_module(module.get_id()))
        _modules.append(module)
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _machine._ready()
    _machine.bind(_surface, _registries.tools)
    _surface.tool_machine = _machine
    _machine.set_active_tool(&"text")
    _router = ShortcutRouter.new()
    _router.canvas_provider = func() -> SaCanvas: return null
    _router.tool_machine_provider = func() -> ToolMachine: return _machine
    _router.bind_commands(_registries.commands)
    _clipboard_mock = ""
    StateText.clipboard_reader = func() -> String: return _clipboard_mock


func after_each() -> void:
    StateText.clipboard_reader = DisplayServer.clipboard_get
    _router.free()
    for i in range(_modules.size() - 1, -1, -1):
        _modules[i].unregister(_registries.context)
    _modules.clear()
    _surface.tool_machine = null
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _doc = null
    _registries = null


func _tool() -> StateText:
    return _machine.active_tool as StateText


func _press(keycode: Key, character: String = "", ctrl: bool = false, shift: bool = false) -> void:
    for pressed: bool in [true, false]:
        var event := InputEventKey.new()
        event.keycode = keycode
        event.physical_keycode = keycode
        event.unicode = character.unicode_at(0) if not character.is_empty() else 0
        event.ctrl_pressed = ctrl
        event.shift_pressed = shift
        event.pressed = pressed
        _router.handle_viewport_input(event, null)


func _text_layers() -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for child in _doc.get_children():
        var layer := child as SaLayer
        if layer != null and StateText.Session.is_text(layer):
            found.append(layer)
    return found


func test_ctrl_a_in_a_block_selects_its_text_and_leaves_the_canvas_alone() -> void:
    _tool().press(AT)
    for letter: String in ["a", "b", "c"]:
        _press(KEY_A, letter)
    _press(KEY_A, "", true)
    assert_false(_doc.selection.active, "The canvas is not selected")
    assert_eq(_tool()._anchor, 0, "The selection starts at the first letter")
    assert_eq(_tool()._caret, 3, "The selection reaches the last letter")
    var fills: Array = _tool().preview_shape()["fills"]
    assert_eq(fills.size(), 1, "The selected letters are drawn as one box")
    _press(KEY_ESCAPE)


func test_typing_over_a_selection_replaces_it() -> void:
    _tool().press(AT)
    for letter: String in ["a", "b", "c"]:
        _press(KEY_A, letter)
    _press(KEY_A, "", true)
    _press(KEY_X, "x")
    assert_eq(_tool()._text, "x", "The letters were replaced by the typed one")
    assert_eq(_tool().preview_shape()["fills"].size(), 0, "Nothing is selected afterwards")
    _press(KEY_ESCAPE)


func test_delete_and_the_arrows_act_on_the_selection() -> void:
    _tool().press(AT)
    for letter: String in ["a", "b", "c"]:
        _press(KEY_A, letter)
    _press(KEY_A, "", true)
    _press(KEY_LEFT)
    assert_eq(_tool()._caret, 0, "Left goes to the start of the selection")
    _press(KEY_A, "", true)
    _press(KEY_BACKSPACE)
    assert_eq(_tool()._text, "", "Backspace removes the whole selection")
    _press(KEY_ESCAPE)


func test_ctrl_a_with_no_block_in_hand_still_selects_the_canvas() -> void:
    _press(KEY_A, "", true)
    assert_true(_doc.selection.active, "The canvas is selected")
