## A rectangle and an ellipse drawn with the Shape tool on a vector layer lay
## the fill and the stroke the vector kernel lays when it draws the same paths
## directly, a move redraws only the tiles under the object's old and new
## bounds, a resize by a handle is one step that undoes and redoes, and a save
## keeps both objects, which the open draws again.
##
## Every shape is drawn as a painter draws it: a press, motions and a release
## handed to the tool machine with the module registered through `SaRegistries`
## as a stranger's module would be (hard rule 6).
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const Module = preload("res://modules/sara-base-modules/vector/module.gd")
const VectorRecipe = preload("res://modules/sara-base-modules/vector/sa_vector_recipe.gd")
const VectorObject = preload("res://modules/sara-base-modules/vector/sa_vector_object.gd")
const VectorSettings = preload("res://modules/sara-base-modules/vector/tools/sa_vector_settings.gd")
const VectorHandles = preload("res://modules/sara-base-modules/vector/tools/sa_vector_handles.gd")

## Four chunks across and two down.
const SIZE := Vector2i(1024, 512)
## The rectangle's drag, across the first two chunks of both rows.
const RECT_FROM := Vector2(100, 60)
const RECT_TO := Vector2(420, 300)
## The ellipse's drag, its box, in the third and fourth chunks.
const ELLIPSE_FROM := Vector2(560, 150)
const ELLIPSE_TO := Vector2(860, 350)
## Where the rectangle is dragged by.
const MOVE_BY := Vector2(40, 120)
## Where the ellipse's lower right handle is pulled to.
const PULLED_TO := Vector2(940, 420)
const WIDTH := 6.0
const STROKE := Color(0.05, 0.1, 0.6, 1.0)
const FILL := Color(1.6, 0.9, 0.2, 1.0)
## Half precision and the stochastic rounding of the kernel's store.
const CLOSE := 0.002
static var scratch: String = SaDataRoot.path("test_rectangles_and_ellipses_on_a_vector_layer.sad")

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _registries: SaRegistries = null
var _doc: SaDocument = null
## Kept as the loader keeps a module, with the context it registered through,
## which the Shape tool's settings hold only weakly.
var _module: SaModule = null
var _foreground := Color.BLACK
var _background := Color.WHITE


func before_each() -> void:
    _foreground = SaColors.foreground
    _background = SaColors.background
    SaColors.foreground = STROKE
    SaColors.background = FILL
    _surface = Fixtures.make_surface(SIZE)
    _doc = _surface.get_document()
    _registries = Fixtures.make_registries(_surface)
    _surface.easel.compositor.set_registry(_registries.blend_modes)
    _module = Module.new()
    _module.context = _registries.context.for_module(&"vector")
    _module.register(_module.context)
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _machine._ready()
    _machine.bind(_surface, _registries.tools, _registries.roles)
    _doc.set_active_layer(_doc.get_node("Layer 1") as SaLayer)


func after_each() -> void:
    SaColors.foreground = _foreground
    SaColors.background = _background
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _doc = null
    _registries = null
    _module = null
    var path := ProjectSettings.globalize_path(scratch)
    for suffix: String in ["", "1", ".saving"]:
        if FileAccess.file_exists(path + suffix):
            DirAccess.remove_absolute(path + suffix)


func _settings() -> VectorSettings:
    return _machine.get_descriptor(&"vector_shape").shared_settings as VectorSettings


func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    if pressed:
        event.button_mask = MOUSE_BUTTON_MASK_LEFT
    return event


## A press at *from*, motions to *to* in one frame, the frame's tick, and the
## release, each through the machine as the canvas hands it a painter's input.
func _drag(from: Vector2, to: Vector2) -> void:
    var view := _surface.view as Fixtures.FakeView
    view.mouse_position = from
    _machine.handle_input(_button(true))
    for step in range(1, 9):
        view.mouse_position = from.lerp(to, step / 8.0)
        var motion := InputEventMouseMotion.new()
        motion.button_mask = MOUSE_BUTTON_MASK_LEFT
        motion.pressure = 1.0
        _machine.handle_input(motion)
    _machine._process(1.0 / 60.0)
    _machine.handle_input(_button(false))


## Draws one shape of *kind* with the Shape tool, filled and stroked.
func _draw_shape(kind: VectorObject.Kind, from: Vector2, to: Vector2) -> void:
    _machine.set_active_tool(&"vector_shape")
    var settings := _settings()
    settings.kind = kind
    settings.corner_radius = 0.0
    settings.fill_on = true
    settings.stroke_on = true
    settings.stroke_width = WIDTH
    _drag(from, to)


## The two shapes, drawn on the vector layer the first one makes, and that layer.
func _two_shapes() -> SaLayer:
    _draw_shape(VectorObject.Kind.RECT, RECT_FROM, RECT_TO)
    _draw_shape(VectorObject.Kind.ELLIPSE, ELLIPSE_FROM, ELLIPSE_TO)
    return _doc.active_layer


func _texel(texture: SaTexture, at: Vector2i) -> Color:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


## The colour *layer* holds at the document pixel *at*.
func _at(layer: SaLayer, at: Vector2i) -> Color:
    var grid_pos := Vector2i(floori(at.x / float(SaChunk.SIZE)), floori(at.y / float(SaChunk.SIZE)))
    var field := layer.get_field(grid_pos)
    return _texel(field, at - grid_pos * SaChunk.SIZE) if field != null else SaFieldSpec.NO_PAINT


func _assert_paint(actual: Color, expected: Color, message: String) -> void:
    assert_almost_eq(actual.r, expected.r, CLOSE, message + ", red")
    assert_almost_eq(actual.g, expected.g, CLOSE, message + ", green")
    assert_almost_eq(actual.b, expected.b, CLOSE, message + ", blue")
    assert_almost_eq(actual.a, expected.a, CLOSE, message + ", alpha")


## The largest difference of any channel of any texel between *layer* and
## *other*, chunk by chunk, a chunk one of them lacks read as no paint.
func _largest_difference(layer: SaLayer, other: SaLayer) -> float:
    var places := {}
    for grid_pos: Vector2i in layer.chunks:
        places[grid_pos] = true
    for grid_pos: Vector2i in other.chunks:
        places[grid_pos] = true
    var largest := 0.0
    for grid_pos: Vector2i in places:
        var a := _texels(layer, grid_pos)
        var b := _texels(other, grid_pos)
        for i in maxi(a.size(), b.size()):
            var x: Color = a[i] if i < a.size() else SaFieldSpec.NO_PAINT
            var y: Color = b[i] if i < b.size() else SaFieldSpec.NO_PAINT
            largest = maxf(largest, maxf(maxf(absf(x.r - y.r), absf(x.g - y.g)), maxf(absf(x.b - y.b), absf(x.a - y.a))))
    return largest


func _texels(layer: SaLayer, grid_pos: Vector2i) -> Array[Color]:
    var out: Array[Color] = []
    var field := layer.get_field(grid_pos)
    if field == null:
        return out
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(field.rid, 0)
    for i in field.size.x * field.size.y:
        out.append(SaFieldSpec.decode_texel(bytes, field.format, i))
    return out


## A fresh document's paint layer with every part of *objects* drawn on it in
## order by the vector kernel directly, the reference a vector layer is held to.
func _drawn_directly(objects: Array[VectorObject]) -> Dictionary:
    var direct_run := Fixtures.make_surface(SIZE)
    var layer := direct_run.get_document().get_node("Layer 1") as SaLayer
    var kernels: Array[SaVectorFill] = []
    for object in objects:
        for part: Array in object.parts():
            var kernel := SaVectorFill.new()
            kernel.draw(layer, part[0] as SaVectorPath, part[1] as Color, object.origin())
            kernels.append(kernel)
    return {"surface": direct_run, "layer": layer, "kernels": kernels}


func test_a_drawn_rectangle_and_ellipse_lay_the_kernel_s_fill_and_stroke_and_a_move_redraws_only_its_bounds() -> void:
    var steps := _doc.history.step_count()
    var layer := _two_shapes()
    var recipe := VectorSettings.recipe_of(layer)
    assert_not_null(recipe, "The first shape made a vector layer, and it is active")
    if recipe == null:
        return
    assert_eq(recipe.objects.size(), 2, "holding both shapes")
    assert_eq(_doc.history.step_count(), steps + 2, "each shape one step, the layer the first made inside its step")
    var rect := recipe.objects[0]
    var ellipse := recipe.objects[1]
    assert_eq(rect.kind, VectorObject.Kind.RECT, "The first is the rectangle")
    assert_eq(rect.box, Rect2(RECT_FROM, RECT_TO - RECT_FROM), "on the box the drag drew")
    assert_eq(ellipse.kind, VectorObject.Kind.ELLIPSE, "the second the ellipse")
    assert_eq(ellipse.box, Rect2(ELLIPSE_FROM, ELLIPSE_TO - ELLIPSE_FROM), "on its own box")
    assert_eq(rect.fill, FILL, "The fill is the background colour, past 1 as it was given")
    assert_eq(rect.stroke, STROKE, "and the stroke the foreground")
    assert_eq(rect.stroke_width, WIDTH, "as wide as the row says")

    var direct_run := _drawn_directly(recipe.objects)
    var direct: SaLayer = direct_run["layer"]
    var largest := _largest_difference(layer, direct)
    assert_true(largest <= CLOSE, "Every texel is the kernel's own drawing the same paths, %s apart at most" % largest)
    _assert_paint(_at(layer, Vector2i(260, 180)), FILL, "Inside the rectangle is its fill")
    _assert_paint(_at(layer, Vector2i(99, 180)), STROKE, "and on its left side its stroke")
    _assert_paint(_at(layer, Vector2i(260, 61)), STROKE, "and on its top")
    assert_almost_eq(_at(layer, Vector2i(90, 180)).a, 0.0, CLOSE, "Beyond its stroke is nothing")
    _assert_paint(_at(layer, Vector2i(710, 250)), FILL, "The ellipse's middle is its fill")
    _assert_paint(_at(layer, Vector2i(559, 250)), STROKE, "and its leftmost edge its stroke")
    _assert_paint(_at(layer, Vector2i(710, 151)), STROKE, "and its top")
    assert_almost_eq(_at(layer, Vector2i(575, 165)).a, 0.0, CLOSE, "Its box's corner, outside the ellipse, is empty")
    direct_run["layer"] = null
    (direct_run["surface"] as SaSurface).get_document().free()
    Fixtures.teardown(direct_run["surface"])

    var old_bounds := rect.bounds()
    var held := _doc.history.step_count()
    _machine.set_active_tool(&"vector_object")
    recipe.drawn_tiles.clear()
    _drag(Vector2(260, 180), Vector2(260, 180) + MOVE_BY)
    assert_eq(rect.box.position, RECT_FROM + MOVE_BY, "The Object tool's drag moved the rectangle")
    assert_eq(ellipse.box.position, ELLIPSE_FROM, "and only it")
    assert_eq(_doc.history.step_count(), held + 1, "as one step")
    var reach := SaDrawnLayer.regions_of([old_bounds, rect.bounds()])
    assert_false(recipe.drawn_tiles.is_empty(), "The move redrew tiles")
    var stray := 0
    for tile in recipe.drawn_tiles:
        var grid_pos := Vector2i(floori(tile.position.x / 256.0), floori(tile.position.y / 256.0))
        if not (reach.has(grid_pos) and reach[grid_pos].encloses(tile)):
            stray += 1
    assert_eq(stray, 0, "and every tile it drew lies under the rectangle's old or new bounds")
    var ellipse_only := Rect2i(Vector2i(ELLIPSE_FROM) + Vector2i(150, 0), Vector2i(16, 16))
    for tile in recipe.drawn_tiles:
        assert_false(tile.intersects(ellipse_only), "No tile of the ellipse's own was drawn again")
    _assert_paint(_at(layer, Vector2i(260, 180) + Vector2i(MOVE_BY)), FILL, "The rectangle's fill stands where it went")
    assert_almost_eq(_at(layer, Vector2i(110, 70)).a, 0.0, CLOSE, "and its old corner is empty")
    _assert_paint(_at(layer, Vector2i(710, 250)), FILL, "The ellipse is untouched")


func test_a_resize_by_a_handle_undoes_redoes_and_both_objects_survive_a_save_and_an_open() -> void:
    var layer := _two_shapes()
    var recipe := VectorSettings.recipe_of(layer)
    assert_not_null(recipe, "The shapes are on a vector layer")
    if recipe == null:
        return
    var ellipse := recipe.objects[1]
    var first := ellipse.box
    _machine.set_active_tool(&"vector_object")
    var steps := _doc.history.step_count()
    _drag(ellipse.box.get_center(), ellipse.box.get_center())
    assert_eq(_settings().picked, PackedStringArray([ellipse.id]), "A click on the ellipse picks it")
    assert_eq(_doc.history.step_count(), steps, "and a click that moved nothing is no step")
    assert_eq(VectorHandles.under(ellipse.box, ELLIPSE_TO, VectorHandles.REACH), 2, "Its lower right corner is a handle")

    _drag(ELLIPSE_TO, PULLED_TO)
    var resized := Rect2(ELLIPSE_FROM, PULLED_TO - ELLIPSE_FROM)
    assert_eq(ellipse.box, resized, "The handle's pull resized the ellipse")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step")
    _assert_paint(_at(layer, Vector2i(PULLED_TO) - Vector2i(70, 40)), FILL, "and its fill reaches the new corner's side")

    assert_true(_doc.undo(), "Undo")
    ellipse = VectorSettings.recipe_of(layer).find(ellipse.id)
    assert_eq(ellipse.box, first, "puts the ellipse's box back")
    assert_almost_eq(_at(layer, Vector2i(PULLED_TO) - Vector2i(70, 40)).a, 0.0, CLOSE, "and its paint with it")
    assert_true(_doc.redo(), "Redo")
    ellipse = VectorSettings.recipe_of(layer).find(ellipse.id)
    assert_eq(ellipse.box, resized, "resizes it again")

    layer.name = "Panels"
    assert_eq(SaExport.save_sad(_doc, scratch), OK, "Saved")
    var opened := Fixtures.make_surface(SIZE)
    assert_eq(SaExport.load_sad(opened.get_document(), scratch), OK, "and opened")
    var back := opened.get_document().get_node("Panels") as SaLayer
    assert_not_null(back, "The vector layer is there")
    if back != null:
        assert_eq(back.layer_type, VectorSettings.TYPE, "with its type")
        assert_true(back.chunks.is_empty(), "and no chunk, since the file keeps the objects")
        _registries.layer_types.rebind([back])
        var kept := VectorSettings.recipe_of(back)
        assert_not_null(kept, "The rebind gives it the vector recipe")
        if kept != null:
            assert_eq(kept.objects.size(), 2, "with both objects")
            assert_eq(kept.objects[0].kind, VectorObject.Kind.RECT, "the rectangle first")
            assert_eq(kept.objects[0].box, Rect2(RECT_FROM, RECT_TO - RECT_FROM), "on its box")
            assert_eq(kept.objects[1].box, resized, "and the ellipse as it was resized")
            assert_eq(kept.objects[1].fill, FILL, "its fill kept past 1")
            assert_eq(kept.objects[1].stroke_width, WIDTH, "and its stroke's width")
            _assert_paint(_at(back, Vector2i(260, 180)), FILL, "The opened layer draws the rectangle")
            _assert_paint(_at(back, Vector2i(559, 280)), STROKE, "and the ellipse's stroke")
    opened.get_document().free()
    Fixtures.teardown(opened)


func test_a_click_with_the_shape_tool_draws_nothing_and_a_locked_layer_takes_no_shape() -> void:
    var layer := _two_shapes()
    var count := VectorSettings.recipe_of(layer).objects.size()
    _draw_shape(VectorObject.Kind.RECT, Vector2(30, 30), Vector2(30.4, 30.2))
    assert_eq(VectorSettings.recipe_of(layer).objects.size(), count, "A click draws nothing")
    layer.is_locked = true
    _draw_shape(VectorObject.Kind.RECT, Vector2(30, 400), Vector2(200, 480))
    assert_eq(VectorSettings.recipe_of(layer).objects.size(), count, "and a drag over a locked vector layer adds nothing to it")
    var other := VectorSettings.recipe_of(_doc.active_layer)
    assert_true(other != null and _doc.active_layer != layer, "but makes a vector layer of its own above it")


func test_new_layer_for_each_shape_puts_every_shape_on_a_vector_layer_of_its_own() -> void:
    var layer := _two_shapes()
    var count := VectorSettings.recipe_of(layer).objects.size()
    var layers := _vector_layers()
    _settings().new_layer_each = true
    _draw_shape(VectorObject.Kind.RECT, Vector2(30, 400), Vector2(200, 480))
    _settings().new_layer_each = false
    assert_eq(
        VectorSettings.recipe_of(layer).objects.size(),
        count,
        "A shape drawn with the option on leaves the active vector layer alone"
    )
    var own := VectorSettings.recipe_of(_doc.active_layer)
    assert_true(own != null and _doc.active_layer != layer, "and goes on a vector layer made for it")
    assert_eq(own.objects.size() if own != null else 0, 1, "which holds that one shape")
    assert_eq(_vector_layers(), layers + 1, "one vector layer more than before")


func _vector_layers() -> int:
    return _doc.get_children().filter(func(child: Node) -> bool: return VectorSettings.recipe_of(child as SaLayer) != null).size()
