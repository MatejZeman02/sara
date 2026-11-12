## A text layer deleted or merged while a block is in hand ends the block with
## no history step of its own, keys typed after the layer left do nothing, and
## undo restores the layer where it stood rather than under the background.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const Recipe = preload("res://modules/sara-base-modules/text/sa_text_recipe.gd")
const StateText = preload("res://modules/sara-base-modules/text/edit/state_text.gd")

const SIZE := Vector2i(800, 400)
const AT := Vector2(60.0, 300.0)

var _surface: SaSurface = null
var _doc: SaDocument = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _machine: ToolMachine = null
var _router: ShortcutRouter = null


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


func after_each() -> void:
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


func _type(said: String) -> void:
    for character in said:
        if character == " ":
            _press(KEY_SPACE, " ")
        elif character == "\n":
            _press(KEY_ENTER)
        else:
            var code := OS.find_keycode_from_string(character.to_upper())
            _press(code, character, false, character != character.to_lower())


func _add_paint_layer(named: String) -> SaLayer:
    var layer := SaLayerOps.new(_doc).add()
    layer.name = named
    return layer


func test_a_fresh_block_deleted_while_typed_ends_with_no_step_and_undo_restores_it() -> void:
    var paint := _add_paint_layer("Paint")
    assert_eq(_doc.active_layer, paint, "Paint layer is active")
    var base_count := _doc.get_child_count()

    _tool().press(AT)
    assert_true(_tool().editing(), "Text tool is editing")
    _type("ab")
    assert_eq(_tool()._text, "ab", "Letters typed into the block")
    var text_layer := _doc.active_layer
    assert_true(text_layer != null and text_layer != paint, "Text layer is in the document")
    assert_eq(text_layer.get_index(), base_count, "Text layer stands above Paint")

    var ops := SaLayerOps.new(_doc)
    assert_true(ops.remove(text_layer), "Layer was deleted from document")
    assert_eq(_doc.get_child_count(), base_count, "Child count returned to base")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Delete Layer", "History ends on Delete Layer")

    _press(KEY_C, "c")
    _press(KEY_ESCAPE)

    assert_false(_tool().editing(), "Escape committed and closed the session")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Delete Layer", "History still ends on Delete Layer, no Add Text")
    assert_eq(_doc.get_child_count(), base_count, "No ghost layer was added")

    assert_true(_doc.undo_redo.undo(), "One undo ran")
    assert_eq(_doc.get_child_count(), base_count + 1, "One undo restored the layer")
    var restored := _doc.active_layer
    assert_eq(restored, text_layer, "The deleted text layer is back")
    assert_eq(restored.get_index(), base_count, "Restored above Paint, not under Background")
    assert_eq((_doc.get_child(0) as SaLayer).name, "Background", "Background is still at index 0")
    var recipe := restored.recipe as Recipe
    assert_true(recipe != null, "Restored layer is a text layer")
    assert_eq(recipe.text, "ab", "Keys typed after delete did not land in the recipe")


func test_a_fresh_block_merged_down_while_typed_ends_with_no_step() -> void:
    var paint := _add_paint_layer("Paint")
    _tool().press(AT)
    _type("Title")
    var text_layer := _doc.active_layer
    assert_true(text_layer != null and text_layer != paint, "Text layer is above Paint")

    var ops := SaLayerOps.new(_doc)
    assert_true(ops.merge_down(text_layer), "The text layer merges down onto Paint")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Merge Down", "History ends on Merge Down")

    _press(KEY_X, "x")
    _press(KEY_ESCAPE)

    assert_false(_tool().editing(), "Escape closed the session")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Merge Down", "History still ends on Merge Down, no Add Text")


func test_an_existing_text_layer_deleted_while_typed_ends_with_no_step() -> void:
    _add_paint_layer("Paint")
    _tool().press(AT)
    _type("Keep")
    _press(KEY_ENTER, "", true)
    var text_layer := _doc.active_layer
    assert_eq(_doc.undo_redo.get_current_action_name(), "Add Text", "Text layer committed")
    var recipe := text_layer.recipe as Recipe
    assert_eq(recipe.text, "Keep", "Recipe holds original text")

    assert_true(_tool().edit(text_layer), "Opened existing text layer for editing")
    _type("More")
    var ops := SaLayerOps.new(_doc)
    assert_true(ops.remove(text_layer), "Layer deleted")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Delete Layer", "History ends on Delete Layer")

    _press(KEY_Z, "z")
    _press(KEY_ESCAPE)

    assert_false(_tool().editing(), "Escape closed the session")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Delete Layer", "History still ends on Delete Layer, no Edit Text")

    assert_true(_doc.undo_redo.undo(), "One undo ran")
    var restored := _doc.active_layer
    assert_eq(restored, text_layer, "One undo restored the text layer")
    var restored_recipe := restored.recipe as Recipe
    assert_eq(restored_recipe.text, "Keep", "Text before the edit session is kept")


func test_an_existing_text_layer_merged_down_while_typed_ends_with_no_step() -> void:
    _add_paint_layer("Paint")
    _tool().press(AT)
    _type("Header")
    _press(KEY_ENTER, "", true)
    var text_layer := _doc.active_layer

    assert_true(_tool().edit(text_layer), "Opened text layer for editing")
    _type("Extra")
    var ops := SaLayerOps.new(_doc)
    assert_true(ops.merge_down(text_layer), "Text layer merges down onto Paint")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Merge Down", "History ends on Merge Down")

    _press(KEY_Y, "y")
    _press(KEY_ESCAPE)

    assert_false(_tool().editing(), "Escape closed the session")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Merge Down", "History still ends on Merge Down, no Edit Text")
