## Layer > Rasterize Layer turns any layer into a plain paint
## layer that looks as it did, in one step.
##
## A paint layer is given a mask, a live move and a relief, rasterized, and
## read as a paint layer with none of the three whose picture is the one
## before, and one undo brings all three back. A paper ground, a generated
## layer, an effect layer and a paint layer under a filter are each read
## showing what they showed, and a layer at double resolution keeps its
## density. It is refused, with its reason, on a plain paint layer and on a
## group, and the Layers docker's suite of the same name reads the row dimmed.
##
## **The picture** is the easel's output drawn through the canvas's own
## material, the frame the Rasterize Impasto suite reads, so the relief the
## view lit before is in the picture compared. Held to BOUND in steps of 255,
## the largest difference found is printed for the Done paragraph.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## Two cells wide, so the move carries paint across the seam.
const SIZE := Vector2i(512, 256)
## How far the picture after may stand from the picture before, in steps of
## 255, which is the Rasterize Impasto suite's bound.
const BOUND: float = 2.0
const RIDGE_MM: float = 1.5
const RIDGE_PITCH: float = 24.0
const PAINT := Color(0.3, 0.55, 0.8, 1.0)
## A move by whole pixels, right and down.
const MOVE := Vector2(40.0, 24.0)
## The part of the first cell the mask hides.
const HIDDEN := Rect2i(32, 32, 128, 160)

var _registries: SaRegistries = null
var _easel: SaEasel = null
var _canvas: SaCanvas = null
var _doc: SaDocument = null


func before_each() -> void:
    SaSettings.show_relief = true
    SaSettings.relief_light_angle = 315.0
    SaSettings.relief_strength = 4.0
    SaProblems.pending_refusals = PackedStringArray()
    _registries = Fixtures.make_registries()
    _easel = SaEasel.create_default(SIZE)
    _easel.compositor.set_registry(_registries.blend_modes)
    var filters := SaFilterRegistry.new()
    filters.register(Bench.InvertFilter.new(), Bench.OWNER)
    _easel.compositor.filter_chain.registry = filters
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


## Ridges of height over the first cell of *layer*, at its density.
func _raise_ridges(layer: SaLayer) -> void:
    SaHeightOps.new(_doc).gain(layer)
    var texture := layer.get_or_create_field(Vector2i.ZERO, SaFieldSpec.HEIGHT)
    var density := float(texture.size.x) / float(SaChunk.SIZE)
    var bytes := PackedByteArray()
    bytes.resize(texture.size.x * texture.size.y * 2)
    for y in texture.size.y:
        for x in texture.size.x:
            var height := RIDGE_MM * (0.5 + 0.5 * sin(TAU * (float(x) / density) / RIDGE_PITCH))
            bytes.encode_half((y * texture.size.x + x) * 2, height)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, bytes)


## A mask on *layer* that hides HIDDEN to *coverage* and nothing elsewhere.
func _mask(layer: SaLayer, coverage: float) -> void:
    assert_true(SaMaskOps.new(_doc).add(layer), "The layer takes a mask")
    var field := SaMaskOps.mask_of(layer).get_or_create(Vector2i.ZERO)
    var density := float(field.size.x) / float(SaChunk.SIZE)
    var image := Image.create_empty(field.size.x, field.size.y, false, Image.FORMAT_RF)
    image.fill(Color(1, 0, 0, 0))
    image.fill_rect(Rect2i(Vector2(HIDDEN.position) * density, Vector2(HIDDEN.size) * density), Color(coverage, 0, 0, 0))
    if field.format == SaFieldSpec.HEIGHT_FORMAT:
        image.convert(Image.FORMAT_RH)
    GlobalShaderCompiler.get_rd().texture_update(field.rid, 0, image.get_data())
    layer.mark_all_unresolved()


func _composite() -> void:
    _doc.update_caches()
    _doc.invalidate_all_allocated_chunks()
    _easel.request_full_composite()
    _easel.process_pending_composite()
    _canvas.view_changed()


## The easel's output drawn one texel a pixel through the canvas's material.
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


## The widest gap between two frames, in steps of 255, and where it is, over
## every pixel *rim* does not answer true for, and then over the ones it does.
static func _worst(a: Image, b: Image, rim: Callable = Callable()) -> Array:
    var found: Array = [0.0, Vector2i.ZERO, 0.0, Vector2i.ZERO]
    for y in a.get_height():
        for x in a.get_width():
            var p := a.get_pixel(x, y)
            var q := b.get_pixel(x, y)
            var gap := maxf(absf(p.r - q.r), maxf(absf(p.g - q.g), absf(p.b - q.b))) * 255.0
            var slot := 2 if rim.is_valid() and rim.call(Vector2i(x, y)) else 0
            if gap > float(found[slot]):
                found[slot] = gap
                found[slot + 1] = Vector2i(x, y)
    return found


## Whether *at* is within a pixel of an edge of *shown*, the area a layer
## shows wholly, which is where the view's relief slopes off the layer and
## lights the paint under it, a light no pixel of the layer can hold.
static func _on_edge(at: Vector2i, shown: Callable) -> bool:
    var inside: bool = shown.call(at)
    for dy: int in [-1, 0, 1]:
        for dx: int in [-1, 0, 1]:
            if shown.call(at + Vector2i(dx, dy)) != inside:
                return true
    return false


## Rasterizes *layer* and holds the picture after to the picture before,
## answering the layer that stands in its place.
func _rasterized_shows_the_same(layer: SaLayer, what: String, rim: Callable = Callable()) -> SaLayer:
    _composite()
    var before := _frame()
    var at := layer.get_index()
    assert_true(SaRasterizeLayer.can_rasterize(_doc, layer), "%s: Rasterize Layer is offered" % what)
    assert_true(SaRasterizeLayer.new(_easel).rasterize(layer), "%s: Rasterize Layer runs" % what)
    _composite()
    var after_frame := _frame()
    var found: Array = _worst(before, after_frame, rim)
    print("%s: largest difference %.3f steps of 255 at %s" % [what, found[0], found[1]])
    if rim.is_valid():
        print("%s: on the rim, largest difference %.3f steps of 255 at %s" % [what, found[2], found[3]])
    var said := "%s: the picture is the one before, worst %.2f steps at %s" % [what, found[0], found[1]]
    assert_true(float(found[0]) <= BOUND, said)
    var paint := _doc.get_child(at) as SaLayer
    assert_true(paint != null and paint != layer, "%s: a new layer stands in its place" % what)
    if paint == null:
        return null
    assert_null(layer.get_parent(), "%s: the old layer is out of the document" % what)
    assert_eq(_doc.active_layer, paint, "%s: and the new one is active" % what)
    assert_true(SaRasterizeLayer.plain(paint), "%s: and it is plain paint" % what)
    assert_false(paint.is_generated() or paint.is_effect() or paint.is_scene(), "%s: storing pixels of its own" % what)
    assert_eq(str(paint.name), str(layer.name), "%s: under the old name" % what)
    assert_almost_eq(paint.opacity, layer.opacity, 1.0e-6, "%s: at the old opacity" % what)
    assert_eq(paint.get_blend_mode_name(), layer.get_blend_mode_name(), "%s: by the old blend mode" % what)
    return paint


func test_a_masked_moved_relief_layer_becomes_plain_paint_and_one_undo_brings_all_three_back() -> void:
    var layer := _doc.active_layer
    _raise_ridges(layer)
    _mask(layer, 0.0)
    var map := SaLiveTransform.composed(MOVE, 0.0, Vector2.ONE, Vector2(SIZE) * 0.5)
    assert_true(SaLiveTransform.put(_doc, layer, map), "The live move is put")
    assert_true(layer.mask != null and layer.live_transform != null and layer.carries_height(), "The layer carries all three")
    var steps := _doc.undo_redo.get_history_count()
    var moved := Vector2i(MOVE)
    var shown := func(at: Vector2i) -> bool:
        return Rect2i(moved, SIZE).has_point(at) and not Rect2i(HIDDEN.position + moved, HIDDEN.size).has_point(at)
    var paint := _rasterized_shows_the_same(layer, "A masked, moved relief layer", _on_edge.bind(shown))
    if paint == null:
        return
    assert_null(paint.mask, "The new layer has no mask")
    assert_null(paint.live_transform, "and no live transform")
    assert_false(paint.carries_height(), "and no relief")
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "as one step")
    assert_eq(_doc.undo_redo.get_current_action_name(), SaRasterizeLayer.ACTION_NAME, "named Rasterize Layer")

    assert_true(_doc.undo(), "Ctrl+Z")
    assert_eq(layer.get_parent(), _doc, "puts the layer back")
    assert_null(paint.get_parent(), "and takes the paint layer out")
    assert_not_null(layer.mask, "with its mask")
    assert_not_null(layer.live_transform, "its live move")
    assert_true(layer.carries_height(), "and its relief")
    assert_true(_doc.redo(), "Ctrl+Shift+Z")
    assert_eq(paint.get_parent(), _doc, "puts the paint layer back")


## The spec lights the relief "as Rasterize Impasto lights it". The two give
## one picture, the rim included, where the view lights the paint under a
## hidden edge and both depart from it alike, so the rim is the light's.
func test_the_relief_is_lit_as_rasterize_impasto_lights_it_on_the_rim_too() -> void:
    var layer := _doc.active_layer
    _raise_ridges(layer)
    _mask(layer, 0.0)
    _composite()
    var before := _frame()
    var shown := func(at: Vector2i) -> bool: return not HIDDEN.has_point(at)
    assert_true(SaRasterizeLayer.new(_easel).rasterize(layer), "Rasterize Layer runs")
    _composite()
    var layered := _frame()
    var by_layer: Array = _worst(before, layered, _on_edge.bind(shown))
    print("Rasterize Layer: %.3f off the rim, %.3f on it at %s" % [by_layer[0], by_layer[2], by_layer[3]])
    assert_true(_doc.undo(), "Ctrl+Z puts the layer back")
    _composite()
    var undone: Array = _worst(before, _frame())
    print("after the undo: largest difference %.3f steps of 255 at %s" % [undone[0], undone[1]])
    assert_true(SaRasterizeImpasto.new(_easel).rasterize(layer), "Rasterize Impasto runs")
    _composite()
    var impasto := _frame()
    var by_impasto: Array = _worst(before, impasto, _on_edge.bind(shown))
    print("Rasterize Impasto: %.3f off the rim, %.3f on it at %s" % [by_impasto[0], by_impasto[2], by_impasto[3]])
    var found: Array = _worst(impasto, layered, _on_edge.bind(shown))
    print("the two against each other: %.3f off the rim, %.3f on it at %s" % [found[0], found[2], found[3]])
    assert_true(float(found[0]) <= BOUND, "the two light the relief alike off the rim, worst %.2f steps" % found[0])
    assert_true(float(found[2]) <= BOUND, "and on it, worst %.2f steps" % found[2])


func test_a_half_mask_at_a_lower_opacity_with_no_relief_shows_the_same() -> void:
    var layer := _doc.active_layer
    layer.opacity = 0.6
    _mask(layer, 0.5)
    var map := SaLiveTransform.composed(MOVE, 0.0, Vector2.ONE, Vector2(SIZE) * 0.5)
    assert_true(SaLiveTransform.put(_doc, layer, map), "The live move is put")
    _rasterized_shows_the_same(layer, "A half masked, moved layer at 60 percent")


func test_a_layer_at_double_resolution_keeps_its_density() -> void:
    var fine := SaLayerOps.new(_doc).add(&"", null, 2.0)
    fine.fill(Color(0.8, 0.35, 0.2, 1.0))
    _mask(fine, 0.0)
    _raise_ridges(fine)
    assert_eq(fine.get_field(Vector2i.ZERO).size.x, SaChunk.SIZE * 2, "The layer holds two texels a pixel")
    var shown := func(at: Vector2i) -> bool: return not HIDDEN.has_point(at)
    var paint := _rasterized_shows_the_same(fine, "A masked relief layer at double resolution", _on_edge.bind(shown))
    if paint != null:
        assert_eq(paint.get_field(Vector2i.ZERO).size.x, SaChunk.SIZE * 2, "and the paint keeps them")


func test_a_paper_ground_becomes_paint_of_what_it_showed() -> void:
    var choice := {
        SaDocumentBackground.KIND: SaDocumentBackground.COLOUR,
        SaDocumentBackground.COLOR: Color.WHITE,
        SaDocumentBackground.GROUND: &"paper",
    }
    _doc.reset_to_default(SIZE, _doc.color_space, SaDocument.DEFAULT_DPI, choice, _registries.layer_types)
    var ground := SaLayerOps.new(_doc).layers()[0]
    assert_true(ground.is_generated(), "The paper is a generated layer")
    var paint := _rasterized_shows_the_same(ground, "A paper ground")
    if paint != null:
        assert_eq(paint.chunks.size(), SaLayer.grid_positions(SIZE).size(), "with a chunk at every grid position it covered")


func test_a_generated_layer_becomes_paint_of_what_it_showed() -> void:
    var background := SaLayerOps.new(_doc).add(&"background", _registries.layer_types)
    assert_true(background != null and background.is_generated(), "A generated background is added")
    if background == null:
        return
    _doc.active_layer.visible = false
    var paint := _rasterized_shows_the_same(background, "A generated background")
    if paint != null:
        assert_eq(paint.chunks.size(), SaLayer.grid_positions(SIZE).size(), "with a chunk at every grid position it covered")


func test_an_effect_layer_becomes_paint_of_what_it_showed() -> void:
    var source := _doc.active_layer
    source.get_or_create_chunk(Vector2i(1, 0)).clear(Color(0.9, 0.2, 0.1, 1.0))
    var effect := SaLayerOps.new(_doc).add(SaEffectLayer.TYPE_ID, _registries.layer_types)
    effect.name = "Effect"
    assert_true(SaEffectLayer.input_of(effect) == source, "The effect layer reads the paint below it")
    assert_not_null(SaFilterOps.new(_doc).attach(effect, Bench.INVERT, {}), "and inverts it")
    effect.opacity = 0.7
    _rasterized_shows_the_same(effect, "An effect layer")


func test_a_paint_layer_under_a_filter_becomes_paint_of_what_it_showed() -> void:
    var layer := _doc.active_layer
    assert_not_null(SaFilterOps.new(_doc).attach(layer, Bench.INVERT, {}), "The layer is inverted by a filter")
    var paint := _rasterized_shows_the_same(layer, "A paint layer under a filter")
    if paint != null:
        assert_true(paint.filters.is_empty(), "and the filter is in its pixels")


func test_it_refuses_plain_paint_and_a_group_and_says_why() -> void:
    var layer := _doc.active_layer
    assert_false(SaRasterizeLayer.can_rasterize(_doc, layer), "Plain paint has nothing to rasterize")
    assert_true(SaRasterizeLayer.refusal(_doc, layer).contains("plain paint"), "and the reason says so")
    var group := SaLayerOps.new(_doc).group_active()
    assert_false(SaRasterizeLayer.can_rasterize(_doc, group), "A group is not rasterized")
    assert_true(SaRasterizeLayer.refusal(_doc, group).contains("Merge"), "and is left to Merge")
    assert_false(SaRasterizeLayer.new(_easel).rasterize(group), "so pressed on a group it does nothing")
