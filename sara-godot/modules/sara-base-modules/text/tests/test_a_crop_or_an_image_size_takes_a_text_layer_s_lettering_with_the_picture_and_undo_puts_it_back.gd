## A crop, a Canvas Size or an Image Size moves and scales a text layer's
## recipe with the picture, so its lettering is drawn again where the picture
## put it and a file saved after it opens there, and one undo puts the recipe
## back with the size. A quarter turn, which text cannot take, leaves the layer
## as paint of what it showed, and undo makes it text again.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const Recipe = preload("res://modules/sara-base-modules/text/sa_text_recipe.gd")
const Door = preload("res://modules/sara-base-modules/text/door/sa_text_door.gd")

const SIZE := Vector2i(800, 400)
const TITLE := "TITLE"
const AT := Vector2(300.0, 250.0)
const EM := 64.0
## The least alpha a display shows, half of an eight bit step.
const SHOWN := 0.5 / 255.0
static var scratch: String = SaDataRoot.path("test_a_crop_takes_a_text_layer_s_lettering.sad")

var _surface: SaSurface = null
var _doc: SaDocument = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []


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


func after_each() -> void:
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


## A text layer lettering the title at the baseline *at*.
func _letter() -> SaLayer:
    var said := Door.text_step(_doc, {"content": TITLE, "at": [AT.x, AT.y], "size": EM, "colour": [0.0, 0.0, 0.0, 1.0]})
    assert_true(said.begins_with("SaCapture: text {"), "The title is lettered, %s" % said)
    for child in _doc.get_children():
        var layer := child as SaLayer
        if layer != null and layer.layer_type == &"text":
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


func test_a_crop_moves_the_recipe_and_its_lettering_and_undo_puts_both_back() -> void:
    var layer := _letter()
    var recipe := layer.recipe as Recipe
    var inked := _inked(layer)
    assert_true(inked.has_area(), "The title is drawn, %s" % inked)
    var crop := Rect2i(200, 100, 500, 280)
    assert_true(SaCrop.new(_doc).crop_to(crop), "The crop happens")
    assert_eq(_doc.canvas_size, crop.size, "at the rectangle's size")
    assert_eq(layer.recipe, recipe, "The layer keeps its recipe")
    assert_eq(layer.layer_type, &"text", "and stays text")
    assert_eq(recipe.origin, AT - Vector2(crop.position), "whose baseline moved with the picture")
    var moved := _inked(layer)
    assert_eq(moved, Rect2i(inked.position - crop.position, inked.size), "and the lettering is drawn there, %s" % moved)

    _doc.undo()
    assert_eq(_doc.canvas_size, SIZE, "Undo puts the size back")
    assert_eq(recipe.origin, AT, "and the baseline")
    assert_eq(_inked(layer), inked, "and the lettering where it stood")
    _doc.redo()
    assert_eq(recipe.origin, AT - Vector2(crop.position), "Redo moves it again")
    assert_eq(_inked(layer), moved, "lettering and all")


func test_canvas_size_anchored_bottom_right_moves_the_recipe() -> void:
    var layer := _letter()
    var recipe := layer.recipe as Recipe
    var to := Vector2i(600, 300)
    assert_true(SaCrop.new(_doc).resize_to(to, Vector2i(2, 2)), "Canvas Size happens")
    var shift := SaCrop.offset_for(SIZE, to, Vector2i(2, 2))
    assert_eq(recipe.origin, AT + Vector2(shift), "and the baseline moves by the anchor's shift %s" % shift)
    _doc.undo()
    assert_eq(recipe.origin, AT, "Undo puts it back")


func test_image_size_at_half_scales_the_recipe_and_a_letter_typed_after_it_is_at_half_too() -> void:
    var layer := _letter()
    var recipe := layer.recipe as Recipe
    var inked := _inked(layer)
    assert_true(SaResample.new(_doc).resample_to(Vector2i(400, 200)), "Image Size happens")
    assert_eq(recipe.origin, AT / 2.0, "The baseline is halved")
    assert_eq(recipe.size, EM / 2.0, "and the size")
    var half := _inked(layer)
    assert_true(absf(half.size.x - inked.size.x / 2.0) <= 2.0, "The lettering is drawn at half, %s from %s" % [half, inked])
    assert_true(absf(half.position.x - inked.position.x / 2.0) <= 2.0, "where half the picture put it")

    var said := Door.text_step(_doc, {"layer": String(layer.name), "content": TITLE + "S"})
    assert_true(said.begins_with("SaCapture: text {"), "A letter is typed at the end, %s" % said)
    assert_eq(recipe.size, EM / 2.0, "in the half size")
    var typed := _inked(layer)
    assert_true(typed.size.y <= half.size.y + 2, "so nothing stands at the old size, %s" % typed)
    assert_true(typed.end.x > half.end.x and typed.position.x == half.position.x, "and the S comes after the title")

    _doc.undo()
    _doc.undo()
    assert_eq(_doc.canvas_size, SIZE, "Undo puts the size back")
    assert_eq([recipe.origin, recipe.size], [AT, EM], "with the baseline and the size")


func test_a_quarter_turn_leaves_the_text_layer_as_paint_and_undo_makes_it_text_again() -> void:
    var layer := _letter()
    var recipe := layer.recipe as Recipe
    SaProblems.announce = false
    assert_true(SaOrient.new(_doc).rotate_image(1), "The image turns")
    SaProblems.announce = true
    assert_null(layer.recipe, "Text cannot take a turn, so the layer has no recipe")
    assert_eq(layer.layer_type, &"", "and is paint")
    assert_true(_inked(layer).has_area(), "showing the turned lettering")
    _doc.undo()
    assert_eq(layer.recipe, recipe, "Undo gives the recipe back")
    assert_eq(layer.layer_type, &"text", "and the type")
    assert_eq(recipe.origin, AT, "at the baseline it had")
    _doc.redo()
    assert_null(layer.recipe, "Redo turns it to paint again")


func test_a_file_saved_after_a_crop_opens_with_the_lettering_where_the_crop_put_it() -> void:
    var layer := _letter()
    var crop := Rect2i(200, 100, 500, 280)
    assert_true(SaCrop.new(_doc).crop_to(crop), "The crop happens")
    var moved := _inked(layer)
    assert_eq(SaExport.save_sad(_doc, scratch), OK, "Saved")
    var opened := Fixtures.make_surface(SIZE)
    assert_eq(SaExport.load_sad(opened.get_document(), scratch), OK, "and opened")
    var back := opened.get_document().get_node(NodePath(String(layer.name))) as SaLayer
    _registries.layer_types.rebind([back])
    var kept := back.recipe as Recipe
    assert_not_null(kept, "with the text layer")
    assert_eq(kept.origin, AT - Vector2(crop.position), "whose baseline is where the crop put it")
    assert_eq(_inked(back), moved, "and whose lettering is drawn there")
    Fixtures.teardown(opened)
