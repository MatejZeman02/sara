## Layer > Rasterize Impasto bakes a layer's relief into its
## pixels with the light as it stands, and clears its height, as one step.
##
## The suite draws the easel's output through the canvas's own material into a
## viewport, the frame `test_the_canvas_shows_its_relief.gd` reads, once with
## Show Impasto on before the rasterise and once with it off after, and holds
## the two within two eight-bit steps everywhere: the light the view shone is
## in the pixels now. It holds the height gone and one undo bringing the height
## and the pixels back, a ground made a paint layer with its tooth lit in, a
## layer at double resolution lit at its own density, and the rows the menu
## dims.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Two cells wide, so one can hold height and the other none.
const SIZE := Vector2i(512, 256)

## How far the frame after may stand from the frame before, in steps of 255:
## two eight-bit steps.
const STEPS: float = 2.0

## Ridges a millimetre and a half high, 24 pixels apart, so every bearing of
## the light finds a face turned to it and one turned away.
const RIDGE_MM: float = 1.5
const RIDGE_PITCH: float = 24.0

const PAINT := Color(0.3, 0.55, 0.8, 1.0)

var _registries: SaRegistries = null
var _easel: SaEasel = null
var _canvas: SaCanvas = null
var _doc: SaDocument = null


func before_each() -> void:
    SaSettings.show_relief = true
    SaSettings.relief_light_angle = 315.0
    SaSettings.relief_strength = 4.0
    _registries = Fixtures.make_registries()
    _easel = SaEasel.create_default(SIZE)
    _easel.compositor.set_registry(_registries.blend_modes)
    _doc = _easel.document
    _doc.active_layer.fill(PAINT)
    _easel.process_pending_composite()
    _canvas = SaCanvas.new()
    _canvas.canvas_size = SIZE
    _canvas.easel = _easel
    _canvas.sync_tonemap()


func after_each() -> void:
    _canvas.free()
    _canvas = null
    _easel.free()
    _easel = null
    _doc = null
    _registries = null
    SaSettings.show_relief = true
    SaSettings.relief_light_angle = 315.0
    SaSettings.relief_strength = 4.0


## Ridges of height over the first cell of *layer*, at the density its chunk
## is stored at, so a ridge stands at the same canvas pixels at any scale.
func _raise_ridges(layer: SaLayer) -> void:
    var grid_pos := Vector2i.ZERO
    SaHeightOps.new(_doc).gain(layer)
    var texture := layer.get_or_create_field(grid_pos, SaFieldSpec.HEIGHT)
    var density := float(texture.size.x) / float(SaChunk.SIZE)
    var bytes := PackedByteArray()
    bytes.resize(texture.size.x * texture.size.y * 2)
    for y in texture.size.y:
        for x in texture.size.x:
            var height := RIDGE_MM * (0.5 + 0.5 * sin(TAU * (float(x) / density) / RIDGE_PITCH))
            bytes.encode_half((y * texture.size.x + x) * 2, height)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, bytes)
    _composite()


func _composite() -> void:
    _doc.invalidate_all_allocated_chunks()
    _easel.process_pending_composite()
    _canvas.view_changed()


## The easel's output drawn one texel a pixel through the canvas's material,
## which is the view's own picture.
func _frame() -> Image:
    var viewport := SubViewport.new()
    viewport.size = SIZE
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    EventBus.add_child(viewport)
    var output := Texture2DRD.new()
    output.texture_rd_rid = _easel.output.rid
    var item := RenderingServer.canvas_item_create()
    RenderingServer.canvas_item_set_parent(item, viewport.find_world_2d().canvas)
    RenderingServer.canvas_item_set_material(item, _canvas.material.get_rid())
    RenderingServer.canvas_item_set_default_texture_filter(item, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
    RenderingServer.canvas_item_add_texture_rect(item, Rect2(Vector2.ZERO, Vector2(SIZE)), output.get_rid())
    RenderingServer.force_draw(false, 0.0)
    var image := viewport.get_texture().get_image()
    RenderingServer.free_rid(item)
    viewport.free()
    return image


## The widest gap between two frames over every pixel, in steps of 255, and
## where it is.
static func _worst(a: Image, b: Image) -> Array:
    var worst := 0.0
    var at := Vector2i.ZERO
    for y in a.get_height():
        for x in a.get_width():
            var p := a.get_pixel(x, y)
            var q := b.get_pixel(x, y)
            var gap := maxf(absf(p.r - q.r), maxf(absf(p.g - q.g), absf(p.b - q.b))) * 255.0
            if gap > worst:
                worst = gap
                at = Vector2i(x, y)
    return [worst, at]


## How many pixels of two frames differ at all.
static func _differing(a: Image, b: Image) -> int:
    var count := 0
    for y in a.get_height():
        for x in a.get_width():
            if a.get_pixel(x, y) != b.get_pixel(x, y):
                count += 1
    return count


## The frame lit before, with Show Impasto on, held against the frame with it
## off after *layer* is rasterised, which is what the scenario's `texel` reads
## hold at three points.
func _rasterised_is_what_the_view_showed(layer: SaLayer, what: String) -> void:
    SaSettings.show_relief = false
    var flat_before := _frame()
    SaSettings.show_relief = true
    var lit_before := _frame()
    assert_true(_differing(flat_before, lit_before) > 100, "%s: the view lights the relief before" % what)
    assert_true(SaRasterizeImpasto.new(_easel).rasterize(layer), "%s: Rasterize Impasto runs" % what)
    _composite()
    SaSettings.show_relief = false
    var flat_after := _frame()
    var found: Array = _worst(lit_before, flat_after)
    assert_true(
        float(found[0]) <= STEPS,
        "%s: with the relief off the pixels are what the view lit, worst %.2f steps at %s" % [what, found[0], found[1]]
    )


func test_the_lit_relief_is_in_the_pixels_with_the_relief_off() -> void:
    var layer := _doc.active_layer
    _raise_ridges(layer)
    _rasterised_is_what_the_view_showed(layer, "A paint layer")
    assert_false(layer.carries_height(), "and the layer carries no height")
    for grid_pos: Vector2i in layer.chunks:
        assert_false(layer.chunks[grid_pos].has_field(SaFieldSpec.HEIGHT), "and no chunk of it holds one")
    SaSettings.show_relief = true
    assert_false(SaRelief.shows_height(_doc), "so the view has no paint height left to light")


func test_one_undo_brings_the_height_and_the_pixels_back() -> void:
    var layer := _doc.active_layer
    _raise_ridges(layer)
    var rd := GlobalShaderCompiler.get_rd()
    var height_before := rd.texture_get_data(layer.get_field(Vector2i.ZERO, SaFieldSpec.HEIGHT).rid, 0)
    var colour_before := rd.texture_get_data(layer.get_field(Vector2i.ZERO).rid, 0)
    var steps := _doc.undo_redo.get_history_count()
    assert_true(SaRasterizeImpasto.new(_easel).rasterize(layer), "Rasterize Impasto runs")
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "as one step")
    assert_eq(_doc.undo_redo.get_current_action_name(), SaRasterizeImpasto.ACTION_NAME, "named Rasterize Impasto")
    var colour_lit := rd.texture_get_data(layer.get_field(Vector2i.ZERO).rid, 0)
    assert_true(colour_lit != colour_before, "The pixels took the light")

    assert_true(_doc.undo(), "Ctrl+Z")
    assert_true(layer.carries_height(), "brings the height back")
    var height := layer.get_field(Vector2i.ZERO, SaFieldSpec.HEIGHT)
    assert_not_null(height, "into the chunk that held it")
    if height != null:
        assert_eq(rd.texture_get_data(height.rid, 0), height_before, "as it was to the texel")
    assert_eq(rd.texture_get_data(layer.get_field(Vector2i.ZERO).rid, 0), colour_before, "and the pixels as they were")
    _composite()
    assert_true(SaRelief.shows_height(_doc), "and the view lights it again")

    assert_true(_doc.redo(), "Ctrl+Shift+Z")
    assert_false(layer.carries_height(), "takes the height away again")
    assert_eq(rd.texture_get_data(layer.get_field(Vector2i.ZERO).rid, 0), colour_lit, "and lights the pixels again")


func test_a_ground_becomes_a_paint_layer_with_its_tooth_lit_in() -> void:
    var choice := {
        SaDocumentBackground.KIND: SaDocumentBackground.COLOUR,
        SaDocumentBackground.COLOR: Color.WHITE,
        SaDocumentBackground.GROUND: &"paper",
    }
    _doc.reset_to_default(SIZE, _doc.color_space, SaDocument.DEFAULT_DPI, choice, _registries.layer_types)
    _composite()
    var ops := SaLayerOps.new(_doc)
    var ground := ops.layers()[0]
    assert_true(ground.is_generated() and SaGeneratedLayer.tooth_of(ground) > 0.0, "The paper lies at the bottom with a tooth")
    assert_true(SaRasterizeImpasto.can_rasterize(_doc, ground), "and Rasterize Impasto is offered on it")
    var name := str(ground.name)
    _rasterised_is_what_the_view_showed(ground, "A paper")
    var paint := ops.layers()[0]
    assert_true(paint != ground, "A new layer stands in the paper's place")
    assert_false(paint.is_generated(), "which stores paint")
    assert_eq(str(paint.name), name, "under the paper's name")
    assert_false(paint.carries_height(), "and carries no height")
    assert_eq(paint.chunks.size(), SaLayer.grid_positions(SIZE).size(), "with a chunk at every grid position of the canvas")
    assert_null(ground.get_parent(), "The paper is out of the document")
    assert_eq(_doc.active_layer, paint, "and the new layer is the active one")

    assert_true(_doc.undo(), "Ctrl+Z")
    assert_eq(ops.layers()[0], ground, "puts the paper back in its place")
    assert_eq(str(ground.name), name, "under its name")
    assert_null(paint.get_parent(), "and takes the paint layer out")
    assert_true(_doc.redo(), "Ctrl+Shift+Z")
    assert_eq(ops.layers()[0], paint, "puts the paint layer back")


func test_a_layer_at_double_resolution_is_lit_at_its_own_density() -> void:
    var fine := SaLayerOps.new(_doc).add(&"", null, 2.0)
    fine.fill(Color(0.8, 0.35, 0.2, 1.0))
    _raise_ridges(fine)
    assert_eq(fine.get_field(Vector2i.ZERO).size.x, SaChunk.SIZE * 2, "The layer holds two texels a pixel")
    _rasterised_is_what_the_view_showed(fine, "A layer at double resolution")
    assert_eq(fine.get_field(Vector2i.ZERO).size.x, SaChunk.SIZE * 2, "and keeps them")


func test_at_a_strength_of_nought_the_height_goes_and_nothing_is_lit() -> void:
    var layer := _doc.active_layer
    _raise_ridges(layer)
    _doc.relief_light.strength = 0.0
    var rd := GlobalShaderCompiler.get_rd()
    var colour_before := rd.texture_get_data(layer.get_field(Vector2i.ZERO).rid, 0)
    assert_true(SaRasterizeImpasto.new(_easel).rasterize(layer), "Rasterize Impasto runs")
    assert_false(layer.carries_height(), "and the height goes")
    var colour_after := rd.texture_get_data(layer.get_field(Vector2i.ZERO).rid, 0)
    assert_eq(colour_after, colour_before, "with the pixels as the flat view showed them")


func test_the_row_is_offered_only_where_there_is_a_relief() -> void:
    var layer := _doc.active_layer
    assert_false(SaRasterizeImpasto.can_rasterize(_doc, layer), "A flat paint layer has no relief to rasterise")
    _raise_ridges(layer)
    assert_true(SaRasterizeImpasto.can_rasterize(_doc, layer), "A paint layer with height has")
    layer.visible = false
    assert_false(SaRasterizeImpasto.can_rasterize(_doc, layer), "not while it is hidden, with no surface in the view to light")
    layer.visible = true
    layer.is_locked = true
    assert_false(SaRasterizeImpasto.can_rasterize(_doc, layer), "nor while it is locked")
    layer.is_locked = false
    var group := SaLayerOps.new(_doc).group_active()
    assert_false(SaRasterizeImpasto.can_rasterize(_doc, group), "A group stores no pixels to light")
    assert_false(SaRasterizeImpasto.can_rasterize(_doc, null), "and nothing is nothing")
    assert_false(SaRasterizeImpasto.new(_easel).rasterize(group), "and pressing it on a group does nothing")

    var command := _registries.commands.get_descriptor(&"layer_rasterize_impasto")
    assert_not_null(command, "The command is registered")
    if command != null:
        assert_eq(command.menu_label(), "Rasterize Impasto", "under the menu's words")
