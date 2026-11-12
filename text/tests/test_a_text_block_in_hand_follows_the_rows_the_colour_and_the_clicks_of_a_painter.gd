## A text block in hand answers the painter's rows and clicks the way a
## painter expects: a reopened layer shows its own font and size in the rows, a
## colour picked recolours the whole block and not only what is typed next, and
## a click anywhere on the block's lines, the gap under a line with no
## descenders included, enters it and does not make a new layer.
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
var _saved_colour: Color = Color.BLACK


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
    _saved_colour = SaColors.foreground
    SaColors.foreground = Color.BLACK


func after_each() -> void:
    SaColors.foreground = _saved_colour
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


func _tool_press_type(at: Vector2, letters: String) -> Recipe:
    _tool().press(at)
    for letter: String in letters.split():
        _press(KEY_A, letter)
    return _tool()._session.recipe as Recipe


func test_a_reopened_layer_puts_its_own_font_and_size_in_the_rows_and_tells_the_panel() -> void:
    var recipe := _tool_press_type(AT, "Hi")
    _tool().font_choice = 1
    _tool().font_size = 90.0
    _press(KEY_ESCAPE)
    _tool().font_choice = 0
    _tool().font_size = 72.0
    var told: Array[int] = [0]
    EventBus.tool_options_moved.connect(func() -> void: told[0] += 1)
    _tool().press(AT + Vector2(2.0, -5.0))
    assert_true(_tool().editing(), "The click entered the block")
    assert_eq(_tool().family(), recipe.family, "The Font row shows the layer's own family")
    assert_eq(_tool().font_size, 90.0, "The Size row shows the layer's own size")
    assert_true(told[0] > 0, "The panel and the bar were told the tool moved its rows")
    _press(KEY_ESCAPE)
    assert_eq(recipe.size, 90.0, "and the edit kept them")


func test_a_colour_picked_while_a_block_is_in_hand_colours_the_whole_block() -> void:
    var recipe := _tool_press_type(AT, "Hello")
    var red := Color(1.0, 0.0, 0.0, 1.0)
    SaColors.foreground = red
    _tool().tick(0.0)
    assert_eq(
        recipe.paint,
        _doc.color_space.from_display(red) if _doc.color_space != null else red,
        "The block's colour followed the pick"
    )
    assert_eq(recipe.text, "Hello", "and its words are intact")
    _press(KEY_ESCAPE)


func test_a_block_opened_keeps_its_own_colour_until_one_is_picked() -> void:
    var recipe := _tool_press_type(AT, "Hello")
    var kept := recipe.paint
    _press(KEY_ESCAPE)
    SaColors.foreground = Color(0.0, 0.0, 1.0, 1.0)
    _tool().press(AT + Vector2(2.0, -5.0))
    _tool().tick(0.0)
    assert_eq(recipe.paint, kept, "Entering a block does not recolour it")
    _press(KEY_ESCAPE)


func test_a_click_under_the_letters_or_a_little_outside_enters_the_block() -> void:
    var recipe := _tool_press_type(AT, "Hello")
    _press(KEY_ESCAPE)
    var layout := recipe.laid_out()
    var foot := recipe.origin.y - layout.ascent + layout.line_height
    for at: Vector2 in [Vector2(AT.x + 5.0, foot - 1.0), Vector2(AT.x + 5.0, foot + 4.0), Vector2(AT.x - 4.0, AT.y)]:
        _tool().press(at)
        assert_true(_tool().editing(), "A click at %s entered the block" % at)
        _press(KEY_ESCAPE)
    assert_eq(_text_layers().size(), 1, "No click made a second layer")
    _tool().press(Vector2(AT.x + 5.0, foot + 40.0))
    _press(KEY_ESCAPE)
    assert_eq(_text_layers().size(), 1, "A click well below starts a block that stays empty and leaves none")
