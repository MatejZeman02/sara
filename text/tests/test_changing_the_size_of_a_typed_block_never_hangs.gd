## Changing the Size or the Font row while a block is typed settles the block
## once per frame however many times the row moved, so typing a size digit by
## digit or dragging the field does not relay and redraw the block for each
## step, and a large size comes back in seconds.
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


const BUDGET_MSEC := 20000


func _type_block() -> Recipe:
    _tool().press(AT)
    for letter: String in "Hello Sara, paint!".split():
        _press(KEY_A, letter)
    return _tool()._session.recipe as Recipe


func test_a_size_typed_digit_by_digit_is_set_in_the_block_once() -> void:
    var recipe := _type_block()
    var fired: Array[int] = [0]
    recipe.changed.connect(func(_rects: Array) -> void: fired[0] += 1)
    for size: float in [7.0, 72.0, 720.0]:
        _tool().font_size = size
    assert_eq(fired[0], 0, "Nothing is laid out while the field is still moving")
    _tool().tick(0.0)
    assert_eq(recipe.size, 720.0, "The last size stands")
    assert_eq(fired[0], 1, "The block changed once for the three steps")
    assert_eq(_tool()._text, "Hello Sara, paint!", "The words are intact")
    _press(KEY_ESCAPE)


func test_a_very_large_size_comes_back_in_seconds() -> void:
    var recipe := _type_block()
    var began := Time.get_ticks_msec()
    _tool().font_size = 2000.0
    _tool().tick(0.0)
    assert_true(Time.get_ticks_msec() - began < BUDGET_MSEC, "The size took %d ms" % (Time.get_ticks_msec() - began))
    assert_eq(recipe.size, 2000.0, "The size stands")
    _press(KEY_ESCAPE)
    assert_eq(_text_layers().size(), 1, "The block committed")


func test_a_font_change_and_a_commit_before_the_next_frame_both_land() -> void:
    var recipe := _type_block()
    _tool().font_choice = 1
    _tool().font_size = 40.0
    _press(KEY_ESCAPE)
    assert_eq(recipe.size, 40.0, "A commit settles a pending size")
    assert_eq(recipe.family, _tool().family(), "A commit settles a pending font")


func test_a_keystroke_after_a_row_moved_is_set_in_the_new_size() -> void:
    var recipe := _type_block()
    _tool().font_size = 90.0
    _press(KEY_A, "z")
    assert_eq(recipe.size, 90.0, "A key settles a pending size before it types")
    assert_eq(recipe.text, "Hello Sara, paint!z", "The letter was typed")
    _press(KEY_ESCAPE)
