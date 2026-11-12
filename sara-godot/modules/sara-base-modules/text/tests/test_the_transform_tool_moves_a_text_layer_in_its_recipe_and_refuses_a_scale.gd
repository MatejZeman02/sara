## The Transform tool's move of a text layer lands in its recipe, so the
## lettering is drawn again sharp where the box went, a letter typed after it
## and a file saved after it stand there too, and one undo puts the recipe
## back. A scale, a turn or a selection leaves the layer as it was, with a
## line in the corner that names text and Rasterize Layer.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const Recipe = preload("res://modules/sara-base-modules/text/sa_text_recipe.gd")
const Door = preload("res://modules/sara-base-modules/text/door/sa_text_door.gd")
const Pass = preload("res://modules/sara-base-modules/base/transform/sa_transform.gd")

const SIZE := Vector2i(800, 400)
const TITLE := "MOVE ME"
const AT := Vector2(150.0, 100.0)
const BY := Vector2(300.0, 200.0)
const EM := 48.0
## The least alpha a display shows, half of an eight bit step.
const SHOWN := 0.5 / 255.0
static var scratch: String = SaDataRoot.path("test_the_transform_tool_moves_a_text_layer.sad")

var _surface: SaSurface = null
var _doc: SaDocument = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _lines: Array[String] = []


func before_each() -> void:
    _surface = Fixtures.make_surface(SIZE)
    _surface.easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _doc = _surface.get_document()
    _registries = SaRegistries.new()
    _registries.build_context(func() -> SaEasel: return _surface.easel, func() -> Array: return [_surface])
    _registries.register_builtins()
    _modules.clear()
    for path: String in ["base", "text"]:
        var module: SaModule = load("res://modules/sara-base-modules/%s/module.gd" % path).new()
        module.register(_registries.context.for_module(module.get_id()))
        _modules.append(module)
    _lines.clear()
    EventBus.corner_notice.connect(_heard)
    EventBus.paint_refused.connect(_heard)


func after_each() -> void:
    EventBus.corner_notice.disconnect(_heard)
    EventBus.paint_refused.disconnect(_heard)
    for i in range(_modules.size() - 1, -1, -1):
        _modules[i].unregister(_registries.context)
    _modules.clear()
    Fixtures.teardown(_surface)
    _surface = null
    _doc = null
    _registries = null
    for path: String in [scratch, scratch + "1", scratch + ".saving"]:
        var real := ProjectSettings.globalize_path(path)
        if FileAccess.file_exists(real):
            DirAccess.remove_absolute(real)


func _heard(line: String) -> void:
    _lines.append(line)


## A text layer lettering the title at the baseline *at*, made active.
func _letter() -> SaLayer:
    var said := Door.text_step(_doc, {"content": TITLE, "at": [AT.x, AT.y], "size": EM, "colour": [0.0, 0.0, 0.0, 1.0]})
    assert_true(said.begins_with("SaCapture: text {"), "The title is lettered, %s" % said)
    for child in _doc.get_children():
        var layer := child as SaLayer
        if layer != null and layer.layer_type == &"text":
            _doc.active_layer = layer
            return layer
    return null


## The box of every texel of *layer* a display could show, in document pixels.
static func _inked(layer: SaLayer) -> Rect2i:
    var box := Rect2i()
    for grid_pos: Vector2i in layer.chunks:
        var texture := layer.get_field(grid_pos)
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        for y in texture.size.y:
            for x in texture.size.x:
                if SaFieldSpec.decode_texel(bytes, texture.format, y * texture.size.x + x).a > SHOWN:
                    var at := Rect2i(grid_pos * SaChunk.SIZE + Vector2i(x, y), Vector2i.ONE)
                    box = at if box.size == Vector2i.ZERO else box.merge(at)
    return box


## Lifts *layer*'s box, puts it under *map* and presses Enter, answering
## whether a step was written.
func _transform(layer: SaLayer, map: Transform2D) -> bool:
    var engine := Pass.new(_doc)
    assert_true(engine.lift(layer, _inked(layer).grow(2)), "The Transform tool lifts the text layer")
    engine.tick()
    engine.preview_matrix(map)
    engine.tick()
    return engine.commit()


func test_a_drag_and_enter_move_the_recipe_and_its_lettering_and_undo_puts_both_back() -> void:
    var layer := _letter()
    var recipe := layer.recipe as Recipe
    var inked := _inked(layer)
    assert_true(inked.has_area(), "The title is drawn, %s" % inked)
    var steps := _doc.history.step_count()
    assert_true(_transform(layer, Transform2D(0.0, BY)), "Enter writes a step")
    assert_eq(_doc.history.step_count(), steps + 1, "one step")
    assert_eq(_doc.history._undo_redo.get_current_action_name(), "Transform Layer", "named Transform Layer")
    assert_eq(layer.recipe, recipe, "The layer keeps its recipe")
    assert_eq(layer.layer_type, &"text", "and stays text")
    assert_eq(recipe.origin, AT + BY, "whose baseline moved with the box")
    var moved := _inked(layer)
    assert_eq(moved, Rect2i(inked.position + Vector2i(BY), inked.size), "and the lettering is drawn there, %s" % moved)
    assert_true(_lines.is_empty(), "with nothing said in the corner, %s" % [_lines])

    _doc.undo()
    assert_eq(recipe.origin, AT, "Undo puts the baseline back")
    assert_eq(_inked(layer), inked, "and the lettering where it was typed")
    _doc.redo()
    assert_eq(recipe.origin, AT + BY, "Redo moves it again")
    assert_eq(_inked(layer), moved, "lettering and all")


func test_a_letter_typed_after_the_move_lands_at_the_new_place() -> void:
    var layer := _letter()
    var recipe := layer.recipe as Recipe
    assert_true(_transform(layer, Transform2D(0.0, BY)), "The title moves")
    var moved := _inked(layer)
    var said := Door.text_step(_doc, {"layer": String(layer.name), "content": TITLE + "S"})
    assert_true(said.begins_with("SaCapture: text {"), "A letter is typed at the end, %s" % said)
    assert_eq(recipe.origin, AT + BY, "at the moved baseline")
    var typed := _inked(layer)
    assert_eq(typed.position.x, moved.position.x, "so the title starts where the move put it, %s" % typed)
    assert_true(typed.end.x > moved.end.x, "and the S comes after it")


func test_a_file_saved_after_the_move_opens_with_the_lettering_where_it_was_moved() -> void:
    var layer := _letter()
    assert_true(_transform(layer, Transform2D(0.0, BY)), "The title moves")
    var moved := _inked(layer)
    assert_eq(SaExport.save_sad(_doc, scratch), OK, "Saved")
    var opened := Fixtures.make_surface(SIZE)
    assert_eq(SaExport.load_sad(opened.get_document(), scratch), OK, "and opened")
    var back := opened.get_document().get_node(NodePath(String(layer.name))) as SaLayer
    _registries.layer_types.rebind([back])
    var kept := back.recipe as Recipe
    assert_not_null(kept, "with the text layer")
    assert_eq(kept.origin, AT + BY, "whose baseline is where the move put it")
    assert_eq(_inked(back), moved, "and whose lettering is drawn there")
    Fixtures.teardown(opened)


func test_a_scale_or_a_turn_leaves_the_layer_as_it_was_and_the_corner_names_text() -> void:
    var layer := _letter()
    var recipe := layer.recipe as Recipe
    var inked := _inked(layer)
    var steps := _doc.history.step_count()
    var centre := Vector2(inked.get_center())
    var doubled := Transform2D(0.0, centre) * Transform2D(0.0, Vector2(2.0, 2.0), 0.0, Vector2.ZERO) * Transform2D(0.0, -centre)
    assert_false(_transform(layer, doubled), "A scale writes no step")
    assert_eq(_lines.size(), 1, "and says one line, %s" % [_lines])
    var line: String = _lines[0] if not _lines.is_empty() else ""
    assert_true(line.contains("text") and line.contains("Rasterize Layer"), "which names text and Rasterize Layer, %s" % line)
    assert_false(line.contains("shapes") or line.contains("draw over"), "and not the paint refusal's words")
    assert_false(_transform(layer, Transform2D(0.3, Vector2.ZERO)), "A turn writes no step either")
    assert_eq(_doc.history.step_count(), steps, "so the history is as it was")
    assert_eq(recipe.origin, AT, "and the baseline")
    assert_eq(_inked(layer), inked, "and the lettering")


func test_a_move_after_a_refused_scale_still_lands() -> void:
    var layer := _letter()
    var recipe := layer.recipe as Recipe
    var engine := Pass.new(_doc)
    assert_true(engine.lift(layer, _inked(layer).grow(2)), "Lifted")
    engine.preview_matrix(Transform2D(0.0, Vector2(2.0, 1.0), 0.0, Vector2.ZERO))
    assert_eq(engine.matrix, Transform2D.IDENTITY, "The scale is refused and the box stays")
    engine.preview_matrix(Transform2D(0.0, BY))
    assert_eq(engine.matrix, Transform2D(0.0, BY), "and the move after it is taken")
    engine.tick()
    assert_true(engine.commit(), "Enter lands it")
    assert_eq(recipe.origin, AT + BY, "in the recipe")


func test_a_selection_on_a_text_layer_lifts_nothing_and_says_why() -> void:
    var layer := _letter()
    _doc.selection.select_rect(Rect2i(0, 0, 200, 200))
    var engine := Pass.new(_doc)
    assert_false(engine.lift(layer, Rect2i(0, 0, 200, 200)), "A selection's lift is refused")
    assert_eq(_lines.size(), 1, "with one line, %s" % [_lines])
    assert_true(not _lines.is_empty() and _lines[0].contains("text"), "that names text")


func test_a_locked_text_layer_is_refused_as_before() -> void:
    var layer := _letter()
    layer.is_locked = true
    var engine := Pass.new(_doc)
    assert_false(engine.lift(layer, _inked(layer).grow(2)), "A locked text layer lifts nothing")
    assert_true(not _lines.is_empty() and _lines[0].contains("locked"), "and the line says it is locked, %s" % [_lines])
