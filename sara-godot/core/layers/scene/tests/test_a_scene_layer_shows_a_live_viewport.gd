## a scene layer at the bottom of a document is a live paper. Its type
## names a scene rather than a generator, registered by a third party through
## the same door, the scene draws into an offscreen viewport at the document's
## size, and a frame copies it into the layer's chunks over what the scene
## declares changed. Paint above it composites as over any layer, and a `.sad`
## keeps the scene's path and parameters, never its pixels.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const THIRD_PARTY := &"scene-layer-test-module"
const TYPE := &"two-tone-scene"
const SCENE := "res://core/layers/scene/tests/two_tone_scene.tscn"
const SIZE := Vector2i(512, 256)
const GROUND := Color(0.2, 0.4, 0.8, 1.0)
const BAND := Color(1.0, 0.25, 0.0, 1.0)
const PAINT := Color(0.1, 0.9, 0.3, 1.0)
## Half float in linear light and back into sRGB loses a little, and nothing
## more than that.
const CLOSE := 0.01
static var scratch: String = SaDataRoot.path("test_a_scene_layer_shows_a_live_viewport.sad")

var _host: Node = null


## A viewport draws only inside the tree, so the easel lives under a host.
func before_each() -> void:
    _host = Node.new()
    _host.name = "K7SceneLayerTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    var path := ProjectSettings.globalize_path(scratch)
    for suffix: String in ["", "1", ".saving"]:
        if FileAccess.file_exists(path + suffix):
            DirAccess.remove_absolute(path + suffix)


func _registries() -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    var descriptor := SaLayerTypeDescriptor.scene_layer(TYPE, SCENE, {"color": GROUND})
    descriptor.display_name = "Two Tone Scene"
    registries.layer_types.register(descriptor, THIRD_PARTY)
    return registries


func _easel() -> SaEasel:
    var easel := SaEasel.create_default(SIZE, null, SaColorSpace.srgb())
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _host.add_child(easel)
    return easel


## The document's stored background goes and a scene layer takes the bottom,
## with Layer 1 active above it.
func _scene_document(easel: SaEasel, registries: SaRegistries) -> SaLayer:
    var doc := easel.document
    SaLayerOps.new(doc).remove(doc.get_node("Background") as SaLayer)
    var layer := SaLayerOps.new(doc).add(TYPE, registries.layer_types)
    layer.name = "Sky"
    SaLayerOps.new(doc).move(layer, -1)
    doc.set_active_layer(doc.get_node("Layer 1") as SaLayer)
    doc.update_caches()
    return layer


## One frame: the renderer draws the viewport, then the layer copies it.
static func _frame(stage: SaSceneLayer) -> Dictionary[Vector2i, Rect2i]:
    RenderingServer.force_draw(false)
    return stage.step()


static func _texel(texture: SaTexture, x: int, y: int) -> Color:
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var at := (y * texture.size.x + x) * 16
    return Color(data.decode_float(at), data.decode_float(at + 4), data.decode_float(at + 8), data.decode_float(at + 12))


func _assert_color(actual: Color, expected: Color, message: String) -> void:
    assert_almost_eq(actual.r, expected.r, CLOSE, message + ", red")
    assert_almost_eq(actual.g, expected.g, CLOSE, message + ", green")
    assert_almost_eq(actual.b, expected.b, CLOSE, message + ", blue")
    assert_almost_eq(actual.a, expected.a, CLOSE, message + ", alpha")


func test_the_type_names_a_scene_and_the_layer_gets_a_viewport() -> void:
    var registries := _registries()
    var descriptor := registries.layer_types.get_descriptor(TYPE)
    assert_eq(descriptor.owner_module, THIRD_PARTY, "A scene type comes in through the public door")
    assert_true(descriptor.is_scene() and not descriptor.is_generated(), "and names a scene, not a kernel")
    assert_true(registries.layer_types.validate().is_empty(), "with a schema the allocator serves")

    var easel := _easel()
    var layer := _scene_document(easel, registries)
    var stage := SaSceneLayer.attach(layer)
    assert_not_null(stage, "The layer carries its viewport")
    assert_eq(layer.get_node_or_null(SaSceneLayer.NODE_NAME), stage, "one, found again by a second attach")
    assert_eq(stage.viewport.size, SIZE, "The viewport is the document's size")
    assert_true(layer.refuses_paint(), "A brush leaves the scene's pixels alone")
    assert_eq(stage.root.get("color"), GROUND, "and the type's defaults reach the scene's root")


func test_a_frame_copies_the_viewport_into_the_chunks() -> void:
    var registries := _registries()
    var easel := _easel()
    var layer := _scene_document(easel, registries)
    var stage := SaSceneLayer.attach(layer)
    assert_true(layer.chunks.is_empty(), "Nothing is stored before the scene has drawn")

    var copied := _frame(stage)
    assert_eq(copied.size(), 2, "The first frame copies the whole viewport, both chunks of it")
    _assert_color(_texel(layer.get_field(Vector2i(0, 0)), 10, 10), GROUND, "The first chunk holds the viewport's pixels")
    _assert_color(_texel(layer.get_field(Vector2i(1, 0)), 200, 250), GROUND, "and so does the second")

    assert_true(_frame(stage).is_empty(), "A frame where the scene says nothing changed copies nothing")

    stage.root.call(&"paint_band", Rect2i(300, 10, 20, 20), BAND)
    copied = _frame(stage)
    assert_eq(copied, {Vector2i(1, 0): Rect2i(44, 10, 20, 20)}, "A change copies only the rectangle the scene declared")
    _assert_color(_texel(layer.get_field(Vector2i(1, 0)), 50, 20), BAND, "which now holds the band")
    _assert_color(_texel(layer.get_field(Vector2i(1, 0)), 10, 20), GROUND, "and around it the ground")


func test_paint_above_the_scene_composites_unchanged() -> void:
    var registries := _registries()
    var easel := _easel()
    var doc := easel.document
    var layer := _scene_document(easel, registries)
    _frame(SaSceneLayer.attach(layer))

    var above := doc.get_node("Layer 1") as SaLayer
    GlobalShaderCompiler.get_rd().texture_clear(above.get_or_create_field(Vector2i(0, 0)).rid, PAINT, 0, 1, 0, 1)
    doc.invalidate_chunk_regions({Vector2i(0, 0): SaDocument.WHOLE_CHUNK, Vector2i(1, 0): SaDocument.WHOLE_CHUNK})
    easel.request_full_composite()
    easel.process_pending_composite()
    _assert_color(_texel(easel.output, 10, 10), PAINT, "Opaque paint above the scene is the paint")
    _assert_color(_texel(easel.output, 400, 100), GROUND, "and where nothing is painted the scene shows")


func test_a_sad_keeps_the_path_and_parameters_not_the_pixels() -> void:
    var registries := _registries()
    var easel := _easel()
    var layer := _scene_document(easel, registries)
    layer.scene_params["color"] = BAND
    _frame(SaSceneLayer.attach(layer))
    assert_false(layer.chunks.is_empty(), "The scene holds chunks in memory")
    assert_eq(SaExport.save_sad(easel.document, scratch), OK, "Saved")

    var loaded := _easel()
    assert_eq(SaExport.load_sad(loaded.document, scratch), OK, "and loaded")
    var back := loaded.document.get_node("Sky") as SaLayer
    assert_not_null(back, "The scene layer is there")
    assert_eq(back.layer_type, TYPE, "with its type")
    assert_eq(back.scene, SCENE, "and its scene's path")
    assert_eq(back.scene_params.get("color"), BAND, "and its parameters, a colour still a colour")
    assert_true(back.chunks.is_empty(), "and none of its pixels")

    registries.layer_types.rebind([back])
    var stage := SaSceneLayer.attach(back)
    _frame(stage)
    _assert_color(_texel(back.get_field(Vector2i(0, 0)), 10, 10), BAND, "A frame after the load draws it again")
