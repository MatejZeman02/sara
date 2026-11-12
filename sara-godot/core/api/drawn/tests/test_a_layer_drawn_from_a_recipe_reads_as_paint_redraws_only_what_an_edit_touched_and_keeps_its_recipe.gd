## A drawn layer, a layer whose pixels are drawn from a recipe, is read by
## every reader of a layer's chunks as paint, redraws only the chunks an edit
## touched, keeps its recipe in the history and the `.sad` instead of its
## pixels, gives its chunks up to residency with nothing read back, refuses a
## brush with a sentence that names the way out, and becomes paint through
## Rasterize Layer.
##
## The recipe is one rectangle drawn through `SaVectorFill`,
## `one_rectangle_recipe.gd`, registered by a test module through
## `SaRegistries` as a stranger's module would register it (hard rule 6).
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const Recipe = preload("res://core/api/drawn/tests/one_rectangle_recipe.gd")
const Eyedropper = preload("res://modules/sara-base-modules/base/tools/state_eyedropper.gd")

const THIRD_PARTY := &"drawn-layer-test-module"
const TYPE := &"one-rectangle"
## Four chunks across and two down, so a move can leave chunks behind.
const SIZE := Vector2i(1024, 512)
## Inside the rectangle in its first chunk and in its second, on its left
## edge, where a half pixel is covered, and beside it.
const INSIDE := Vector2i(250, 70)
const INSIDE_SECOND := Vector2i(290, 70)
const EDGE := Vector2i(200, 70)
const OUTSIDE := Vector2i(150, 70)
## Where a move takes the rectangle's corner: the third chunk of the second row.
const MOVED := Vector2(600.5, 300.5)
## The chunks the rectangle covers where it starts, and where it is moved.
const FIRST_CHUNKS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
const MOVED_CHUNKS: Array[Vector2i] = [Vector2i(2, 1)]
## Half precision and the stochastic rounding of the kernel's store.
const CLOSE := 0.002
static var scratch: String = SaDataRoot.path("test_a_layer_drawn_from_a_recipe.sad")

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _registries: SaRegistries = null
var _doc: SaDocument = null
var _heard: Array[String] = []


func before_each() -> void:
    _surface = Fixtures.make_surface(SIZE)
    _surface.easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _doc = _surface.get_document()
    _registries = SaRegistries.new()
    _registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    _registries.register_builtins()
    var descriptor := SaLayerTypeDescriptor.drawn_layer(TYPE, Recipe)
    descriptor.display_name = "One Rectangle"
    _registries.layer_types.register(descriptor, THIRD_PARTY)
    _heard.clear()
    EventBus.paint_refused.connect(_hear)


func after_each() -> void:
    EventBus.paint_refused.disconnect(_hear)
    SaStrokeNote.say("")
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _doc = null
    _registries = null
    var path := ProjectSettings.globalize_path(scratch)
    for suffix: String in ["", "1", ".saving"]:
        if FileAccess.file_exists(path + suffix):
            DirAccess.remove_absolute(path + suffix)


func _hear(line: String) -> void:
    _heard.append(line)


## A drawn layer of the test type above Layer 1, and active.
func _drawn() -> SaLayer:
    _doc.set_active_layer(_doc.get_node("Layer 1") as SaLayer)
    var layer := SaLayerOps.new(_doc).add(TYPE, _registries.layer_types)
    layer.name = "Shape"
    return layer


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


## Finds the rectangle in *layer*: opaque paint inside it in both its chunks,
## half coverage on its edge and nothing beside it.
func _assert_rectangle(layer: SaLayer, paint: Color, how: String) -> void:
    _assert_paint(_at(layer, INSIDE), paint, how + " holds the rectangle's paint inside it")
    _assert_paint(_at(layer, INSIDE_SECOND), paint, how + " and in its second chunk")
    assert_almost_eq(_at(layer, EDGE).a, 0.5, CLOSE, how + " half covers the pixel its edge halves")
    assert_almost_eq(_at(layer, OUTSIDE).a, 0.0, CLOSE, how + " and holds nothing beside it")


## Every chunk of *layer*, read back, by place.
static func _bytes(layer: SaLayer) -> Dictionary:
    var out := {}
    for grid_pos: Vector2i in layer.chunks:
        out[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data(layer.chunks[grid_pos].albedo().rid, 0)
    return out


static func _sorted(positions: Array) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    out.assign(positions)
    out.sort()
    return out


func test_the_type_comes_through_the_door_and_draws_where_the_recipe_covers() -> void:
    var descriptor := _registries.layer_types.get_descriptor(TYPE)
    assert_eq(descriptor.owner_module, THIRD_PARTY, "A drawn type comes in through the public door")
    assert_true(descriptor.is_drawn() and not descriptor.is_generated() and not descriptor.is_scene(), "and is drawn")
    var layer := _drawn()
    assert_true(layer.is_drawn(), "The layer carries a recipe of its own")
    assert_true(layer.recipe.get_script() == Recipe, "of the type's script")
    assert_eq(_sorted(layer.chunks.keys()), FIRST_CHUNKS, "Chunks are allocated only where the recipe covers")
    _assert_rectangle(layer, layer.recipe.paint, "The layer")


func test_the_compositor_merge_down_select_opaque_the_eyedropper_and_copy_read_it() -> void:
    var layer := _drawn()
    var paint: Color = layer.recipe.paint

    _doc.update_caches()
    _surface.easel.request_full_composite()
    _surface.easel.process_pending_composite()
    _assert_paint(_texel(_surface.easel.output, INSIDE), paint, "The composite shows the rectangle")
    _assert_paint(_texel(_surface.easel.output, INSIDE_SECOND), paint, "in both its chunks")
    assert_true(_texel(_surface.easel.output, OUTSIDE).r < paint.r - 0.1, "and the ground beside it")

    var opaque := SaSelectOpaque.new(_doc)
    assert_true(opaque.select(layer, SaSelection.Mode.REPLACE), "Select Opaque takes the drawn layer")
    var mask: SaChunk = _doc.selection.chunks[Vector2i(0, 0)]
    assert_almost_eq(_texel(mask.field(SaSelection.FIELD), INSIDE).r, 1.0, CLOSE, "and selects inside the rectangle")
    assert_almost_eq(_texel(mask.field(SaSelection.FIELD), EDGE).r, 0.5, CLOSE, "half its edge")
    assert_almost_eq(_texel(mask.field(SaSelection.FIELD), OUTSIDE).r, 0.0, CLOSE, "and nothing beside it")
    _doc.selection.deselect()

    var eyedropper := Eyedropper.new()
    eyedropper.surface = _surface
    eyedropper.sample_from = Eyedropper.SampleFrom.LAYER
    eyedropper.sample_size = 1
    _doc.set_active_layer(layer)
    _assert_paint(eyedropper.pick_color_at_pos(Vector2(INSIDE) + Vector2(0.5, 0.5)), paint, "The eyedropper picks its paint")

    var held := SaClipboard.new()
    assert_eq(held.copy(_doc, layer), FIRST_CHUNKS.size(), "Copy takes both its chunks")
    _assert_paint(_texel((held.chunks[Vector2i(0, 0)] as SaChunk).albedo(), INSIDE), paint, "with the rectangle in them")

    var below := _doc.get_node("Layer 1") as SaLayer
    assert_true(SaLayerOps.new(_doc).merge_down(layer), "Merge Down takes the drawn layer onto the paint below")
    assert_false(is_instance_valid(layer) and layer.get_parent() == _doc, "and the drawn layer goes")
    _assert_rectangle(below, paint, "The paint layer it merged into")


func test_an_edit_redraws_only_the_chunks_under_the_old_and_new_bounds_and_undo_keeps_no_chunk() -> void:
    var layer := _drawn()
    var recipe: Recipe = layer.recipe
    var first := _bytes(layer)
    var steps := _doc.history.step_count()
    recipe.drawn.clear()
    recipe.tiles.clear()

    assert_true(SaDrawnLayer.edit(layer, "Move Shape", func(r: Recipe) -> void: r.move_to(MOVED)), "The move is an edit")
    assert_eq(_sorted(layer.chunks.keys()), MOVED_CHUNKS, "The chunks it left are let go and one is drawn where it went")
    var reach := SaDrawnLayer.regions_of([recipe.bounds()])
    for region in recipe.drawn:
        var grid_pos := Vector2i(floori(region.position.x / 256.0), floori(region.position.y / 256.0))
        assert_true(reach.has(grid_pos) and reach[grid_pos].encloses(region), "Each region drawn lies under the new bounds")
    for tile in recipe.tiles:
        assert_true(recipe.bounds().intersects(tile), "and each tile dispatched lies under the rectangle")
    assert_eq(recipe.drawn.size(), MOVED_CHUNKS.size(), "One draw a chunk, and none for a chunk nothing covers")
    assert_almost_eq(_at(layer, Vector2i(650, 330)).a, 1.0, CLOSE, "The rectangle stands where it was moved")

    assert_eq(_doc.history.step_count(), steps + 1, "The move is one step")
    assert_true(_doc.history.holdings().back().is_empty(), "which holds no chunk")
    assert_true(SaResidency.history_entries(_doc).is_empty(), "nor anything residency could move")

    recipe.drawn.clear()
    assert_true(_doc.undo(), "Undo")
    assert_eq(_sorted(layer.chunks.keys()), FIRST_CHUNKS, "puts the rectangle's chunks back and lets the moved one go")
    assert_eq(recipe.drawn.size(), FIRST_CHUNKS.size(), "drawing only the chunks under its bounds")
    assert_eq(_bytes(layer), first, "bit for bit as they were drawn first")
    assert_true(_doc.redo(), "Redo")
    assert_eq(_sorted(layer.chunks.keys()), MOVED_CHUNKS, "moves it again")


func test_a_brush_stroke_on_it_is_refused_with_a_sentence_that_names_the_way_out() -> void:
    var layer := _drawn()
    _doc.set_active_layer(layer)
    var before := _bytes(layer)
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    var state := _machine.active_tool
    var view := _surface.view as Fixtures.FakeView
    view.mouse_position = Vector2(100, 60)
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    state.handle_input(press)
    for step in range(1, 9):
        view.mouse_position = Vector2(100, 60).lerp(Vector2(400, 80), step / 8.0)
        var motion := InputEventMouseMotion.new()
        motion.pressure = 1.0
        state.handle_input(motion)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    state.handle_input(release)

    assert_true(layer.refuses_paint(), "A drawn layer turns a brush away")
    assert_eq(_bytes(layer), before, "and the stroke laid nothing on it")
    assert_false(_heard.is_empty(), "The refusal is said")
    var line := _heard[0] if not _heard.is_empty() else ""
    assert_true(line.contains("drawn from its shapes"), "saying why: '%s'" % line)
    assert_true(line.contains("paint layer above"), "naming a paint layer above")
    assert_true(line.contains("Rasterize Layer"), "and Rasterize Layer")
    assert_eq(line, SaContext.paint_refusal_line(layer, TranslationServer.translate("stroke")), "the refusals' own line")


func test_a_save_keeps_the_recipe_and_no_chunk_and_the_open_draws_it_again() -> void:
    var layer := _drawn()
    layer.recipe.paint = Color(0.1, 0.7, 0.3, 1.0)
    SaDrawnLayer.redraw(layer, [layer.recipe.bounds()])
    assert_eq(SaExport.save_sad(_doc, scratch), OK, "Saved")
    assert_eq(SaSadFile.version_at(scratch), SaSadDrawn.VERSION, "under the drawn layer's version")

    var opened := Fixtures.make_surface(SIZE)
    assert_eq(SaExport.load_sad(opened.get_document(), scratch), OK, "and opened")
    var back := opened.get_document().get_node("Shape") as SaLayer
    assert_not_null(back, "The drawn layer is there")
    assert_eq(back.layer_type, TYPE, "with its type")
    assert_true(back.chunks.is_empty(), "and no chunk, because the file holds none")
    assert_true(back.has_meta(SaDrawnLayer.KEPT), "but its recipe")

    _registries.layer_types.rebind([back])
    assert_true(back.is_drawn(), "The rebind gives it the type's recipe")
    assert_eq(_sorted(back.chunks.keys()), FIRST_CHUNKS, "which owes the chunks it covers")
    var recipe := back.recipe as Recipe
    for grid_pos: Vector2i in back.chunks:
        assert_true(back.chunks[grid_pos].is_stored(), "Each opened chunk %s waits to be read" % grid_pos)
    assert_eq(recipe.drawn.size(), 0, "so the rebind drew nothing at once")
    _assert_rectangle(back, Color(0.1, 0.7, 0.3, 1.0), "The opened layer")
    assert_eq(recipe.drawn.size(), FIRST_CHUNKS.size(), "and the reads drew each chunk once")
    opened.get_document().free()
    Fixtures.teardown(opened)


func test_residency_lets_its_chunks_go_unread_and_they_are_drawn_again() -> void:
    var ground := _doc.get_node("Background") as SaLayer
    _doc.remove_child(ground)
    ground.free()
    var layer := _drawn()
    var first := _bytes(layer)
    _doc.set_active_layer(_doc.get_node("Layer 1") as SaLayer)
    var readbacks := SaResidency.readbacks
    assert_true(SaResidency.settle(_doc, 1) >= FIRST_CHUNKS.size(), "A budget of a byte lets the drawn chunks go")
    for grid_pos: Vector2i in FIRST_CHUNKS:
        assert_true((layer.chunks[grid_pos] as SaChunk).is_stored(), "Chunk %s is off the card" % grid_pos)
    assert_eq(SaResidency.readbacks, readbacks, "with nothing read back")
    assert_eq(_bytes(layer), first, "Read again, each is drawn afresh as it was")
    assert_eq(SaResidency.readbacks, readbacks, "and still nothing was read back")


func test_rasterize_layer_leaves_a_paint_layer_with_the_same_pixels() -> void:
    var layer := _drawn()
    var first := _bytes(layer)
    assert_true(SaRasterizeLayer.can_rasterize(_doc, layer), "Rasterize Layer is lit on a drawn layer")
    assert_true(SaRasterizeLayer.new(_surface.easel).rasterize(layer), "and turns it into paint")
    var paint := _doc.get_node("Shape") as SaLayer
    assert_not_null(paint, "under its name")
    assert_false(paint.is_drawn(), "a paint layer with no recipe")
    assert_false(paint.refuses_paint(), "which takes a brush")
    assert_eq(_bytes(paint), first, "holding the same pixels")


func test_a_drawn_layer_with_a_mask_keeps_the_mask_across_a_save() -> void:
    var layer := _drawn()
    layer.add_mask(0.25)
    assert_eq(SaExport.save_sad(_doc, scratch), OK, "Saved with its mask")

    var opened := Fixtures.make_surface(SIZE)
    assert_eq(SaExport.load_sad(opened.get_document(), scratch), OK, "and opened")
    var back := opened.get_document().get_node("Shape") as SaLayer
    assert_false(back.chunks.is_empty(), "The chunks are kept, since the mask is a field of them")
    _registries.layer_types.rebind([back])
    var mask := back.get_field(Vector2i(0, 0), SaFieldSpec.MASK)
    assert_not_null(mask, "The mask is there after the redraw")
    if mask != null:
        assert_almost_eq(_texel(mask, INSIDE).r, 0.25, CLOSE, "at the value it was given")
    _assert_paint(_at(back, INSIDE), layer.recipe.paint, "and the colour is drawn again over it")
    opened.get_document().free()
    Fixtures.teardown(opened)
