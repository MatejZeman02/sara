## With a text block in hand, Ctrl+V pastes plain text from the clipboard at
## the caret, keeping newlines and dropping other control characters. With no
## block in hand, Ctrl+V leaves the layer stack alone.
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


func test_clean_clipboard_text_preserves_newlines_and_drops_other_controls() -> void:
    assert_eq(StateText.clean_clipboard_text("Hello\nWorld"), "Hello\nWorld", "LF is kept")
    assert_eq(StateText.clean_clipboard_text("Line 1\r\nLine 2"), "Line 1\nLine 2", "CRLF becomes LF")
    assert_eq(StateText.clean_clipboard_text("Line 1\rLine 2"), "Line 1\nLine 2", "Lone CR becomes LF")
    assert_eq(StateText.clean_clipboard_text("A\tB\u0007C\u001b"), "ABC", "Tabs and control codes are dropped")
    assert_eq(StateText.clean_clipboard_text("Příliš žluťoučký kůň"), "Příliš žluťoučký kůň", "Accents stay")
    assert_eq(StateText.clean_clipboard_text(""), "", "Empty string stays empty")


func test_ctrl_v_with_no_block_in_hand_leaves_layer_stack_alone() -> void:
    _clipboard_mock = "Some plain text\nSecond line"
    var layers_before := _doc.get_child_count()
    _press(KEY_V, "", true)
    assert_eq(_doc.get_child_count(), layers_before, "Layer count remains unchanged")
    assert_eq(_text_layers().size(), 0, "No text layer created")


func test_ctrl_v_pastes_two_lines_at_caret_in_new_block() -> void:
    _clipboard_mock = "First line\nSecond line"
    _tool().press(AT)
    assert_true(_tool().editing(), "Editing a new text block")
    _press(KEY_A, "A", false, true)
    _press(KEY_V, "", true)
    assert_eq(_tool()._text, "AFirst line\nSecond line", "Text has letter and pasted lines")
    assert_eq(_tool()._caret, "AFirst line\nSecond line".length(), "Caret sits at the end of pasted text")
    _press(KEY_ESCAPE)
    assert_false(_tool().editing(), "Escape committed the block")
    var layers := _text_layers()
    assert_eq(layers.size(), 1, "One text layer created")
    var recipe := layers[0].recipe as Recipe
    assert_eq(recipe.text, "AFirst line\nSecond line", "Recipe text matches")


func test_ctrl_v_with_empty_clipboard_leaves_typed_letter_alone() -> void:
    _clipboard_mock = ""
    _tool().press(AT)
    _press(KEY_A, "A", false, true)
    _press(KEY_V, "", true)
    assert_eq(_tool()._text, "A", "Text still has only the typed letter")
    assert_eq(_tool()._caret, 1, "Caret stays at 1")
    _press(KEY_ESCAPE)
    var layers := _text_layers()
    assert_eq(layers.size(), 1, "One text layer created")
    var recipe := layers[0].recipe as Recipe
    assert_eq(recipe.text, "A", "Recipe text is A")


func test_ctrl_v_pastes_at_caret_in_middle_of_text() -> void:
    _clipboard_mock = "mid"
    _tool().press(AT)
    _press(KEY_A, "a")
    _press(KEY_B, "b")
    _press(KEY_LEFT)
    assert_eq(_tool()._caret, 1, "Caret is between a and b")
    _press(KEY_V, "", true)
    assert_eq(_tool()._text, "amidb", "Pasted text landed at caret")
    assert_eq(_tool()._caret, 4, "Caret moved past pasted text")
    _press(KEY_ESCAPE)
    var recipe := _text_layers()[0].recipe as Recipe
    assert_eq(recipe.text, "amidb", "Recipe text has pasted text in the middle")


func test_ctrl_shift_v_is_not_consumed_by_block_in_hand() -> void:
    _clipboard_mock = "Pasted"
    _tool().press(AT)
    _press(KEY_A, "A", false, true)
    var event := InputEventKey.new()
    event.keycode = KEY_V
    event.ctrl_pressed = true
    event.shift_pressed = true
    event.pressed = true
    assert_false(_tool().takes_typing(event), "Ctrl+Shift+V is not taken by takes_typing")
    _press(KEY_ESCAPE)
