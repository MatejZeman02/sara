## A paper ground that stores nothing: the second generated
## layer type, registered through the same door the background takes, drawn by
## `paper.gmacs` from three octaves of value noise between two colours, over
## the region asked for and never over the document, allocating no chunk, with
## its two colours and its cell width travelling in the file.
##
## The suite that proves the mechanism is `test_background_layer.gd` beside
## this one, and it is not repeated here: this file asks only what a second
## generator answers differently from the first, which is a grain instead of a
## flat colour, a second colour and a scale, and a dispatch that has a region
## worth respecting.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

static var scratch: String = SaDataRoot.path("test_paper_layer.sad")


func _registries() -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    return registries


func _easel(size: Vector2i = Vector2i(512, 256)) -> SaEasel:
    var easel := SaEasel.create_default(size)
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    return easel


func _texel(texture: SaTexture, x: int, y: int) -> Color:
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var at := (y * texture.size.x + x) * 16
    return Color(data.decode_float(at), data.decode_float(at + 4), data.decode_float(at + 8), data.decode_float(at + 12))


func _layer_named(doc: SaDocument, layer_name: String) -> SaLayer:
    return doc.get_node(layer_name) as SaLayer


## A paper under everything: the default document's stored grey background is
## dropped and a generated paper takes its place at the bottom, with Layer 1
## active above it.
func _paper_document(easel: SaEasel, registries: SaRegistries) -> SaLayer:
    var doc := easel.document
    SaLayerOps.new(doc).remove(_layer_named(doc, "Background"))
    var layer := SaLayerOps.new(doc).add(&"paper", registries.layer_types)
    layer.name = "Paper"
    SaLayerOps.new(doc).move(layer, -1)
    doc.set_active_layer(_layer_named(doc, "Layer 1"))
    doc.update_caches()
    return layer


func _remove_scratch() -> void:
    var path := ProjectSettings.globalize_path(scratch)
    for suffix: String in ["", "1", ".saving"]:
        if FileAccess.file_exists(path + suffix):
            DirAccess.remove_absolute(path + suffix)


## The paper goes through the registry the way the background does, and a layer
## of it has the kernel, all three defaults in the document's space, and no
## chunk.
func test_the_paper_type_is_registered_beside_the_background() -> void:
    var registries := _registries()
    assert_true(registries.layer_types.has(&"paper"), "The paper is a registered type")
    var descriptor := registries.layer_types.get_descriptor(&"paper")
    assert_eq(descriptor.owner_module, &"sara-skeleton", "registered by the skeleton, through the public door")
    assert_true(descriptor.is_generated(), "and it evaluates a kernel")
    assert_eq(descriptor.generator, "paper", "its own, not the background's")
    assert_true(ResourceLoader.exists(descriptor.generator_view), "with a view shader on disk for beyond the rectangle")
    assert_true(registries.layer_types.validate().is_empty(), "and a schema the allocator can serve")

    var easel := _easel()
    var doc := easel.document
    var layer := SaLayerOps.new(doc).add(&"paper", registries.layer_types)
    assert_true(layer.is_generated(), "A layer of it stores nothing")
    assert_eq(layer.chunks.size(), 0, "and holds no chunk")
    var space := doc.color_space
    assert_eq(layer.generator_params.get("color"), space.from_display(Color(0.93, 0.91, 0.86, 1.0)), "the near colour")
    assert_eq(layer.generator_params.get("second"), space.from_display(Color(0.82, 0.79, 0.72, 1.0)), "the far one")
    assert_eq(layer.generator_params.get("scale"), 20.0, "and the cell width, which is no colour and is not converted")
    easel.free()


## The grain: the kernel writes a different value in different places, every
## one of them between the two colours, and it costs no chunk to do it.
func test_the_paper_grains_between_its_two_colours_without_a_chunk() -> void:
    var registries := _registries()
    var easel := _easel()
    var doc := easel.document
    var paper := _paper_document(easel, registries)
    paper.generator_params["color"] = Color(0.0, 0.0, 0.0, 1.0)
    paper.generator_params["second"] = Color(1.0, 1.0, 1.0, 1.0)
    paper.generator_params["scale"] = 16.0
    doc.update_caches()
    easel.request_full_composite()
    easel.process_pending_composite()

    var lowest := 2.0
    var highest := -1.0
    for x in range(4, 500, 7):
        var value := _texel(easel.output, x, 128).r
        lowest = min(lowest, value)
        highest = max(highest, value)
        assert_true(value >= -0.001 and value <= 1.001, "Every texel lies between the two colours at x=%d" % x)
    assert_true(highest - lowest > 0.15, "and the row is a grain rather than one value, spread %.3f" % (highest - lowest))
    assert_eq(paper.chunks.size(), 0, "with no chunk allocated for any of it")
    assert_eq(doc.fold.bottom_cache.chunks.size(), 0, "and nothing folded into the cache below")
    easel.free()


## Hard rule 2 on a layer that covers the whole document: the kernel is
## dispatched over the region the compositor asks for and writes nothing
## outside it, which is what lets a dab on a paper cost a dab.
func test_the_kernel_writes_the_region_and_not_the_chunk() -> void:
    var registries := _registries()
    var easel := _easel(Vector2i(256, 256))
    var paper := _paper_document(easel, registries)
    paper.generator_params["color"] = Color(1.0, 0.0, 0.0, 1.0)
    paper.generator_params["second"] = Color(1.0, 0.0, 0.0, 1.0)
    paper.generator_params["scale"] = 16.0

    var format := RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    var whole := easel.compositor.generate_chunk(paper, Vector2.ZERO, Rect2i(Vector2i.ZERO, Vector2i(256, 256)), format)
    assert_almost_eq(_texel(whole, 200, 200).r, 1.0, 0.01, "The whole chunk is red to start with")

    paper.generator_params["color"] = Color(0.0, 1.0, 0.0, 1.0)
    paper.generator_params["second"] = Color(0.0, 1.0, 0.0, 1.0)
    var region := Rect2i(Vector2i(0, 0), Vector2i(32, 32))
    var partial := easel.compositor.generate_chunk(paper, Vector2.ZERO, region, format)
    assert_almost_eq(_texel(partial, 8, 8).g, 1.0, 0.01, "The region asked for is written")
    assert_almost_eq(_texel(partial, 200, 200).r, 1.0, 0.01, "and the texel outside it still holds the first pass")
    assert_almost_eq(_texel(partial, 200, 200).g, 0.0, 0.01, "so the dispatch never ran over the whole chunk")
    easel.free()


## A coarser cell is a slower grain: neighbouring texels differ less at
## scale 64 than at scale 4, which is the one thing the number means.
func test_a_bigger_scale_is_a_coarser_grain() -> void:
    var registries := _registries()
    var easel := _easel(Vector2i(256, 256))
    var doc := easel.document
    var paper := _paper_document(easel, registries)
    paper.generator_params["color"] = Color(0.0, 0.0, 0.0, 1.0)
    paper.generator_params["second"] = Color(1.0, 1.0, 1.0, 1.0)

    var steps: Array[float] = []
    for scale: float in [4.0, 64.0]:
        paper.generator_params["scale"] = scale
        doc.update_caches()
        easel.request_full_composite()
        easel.process_pending_composite()
        var total := 0.0
        for x in range(8, 200):
            total += absf(_texel(easel.output, x + 1, 100).r - _texel(easel.output, x, 100).r)
        steps.append(total)
    assert_true(steps[0] > steps[1] * 2.0, "Four pixel cells step %.3f against sixty-four's %.3f" % [steps[0], steps[1]])
    easel.free()


## The two colours and the cell width travel with the file, and the kernel
## comes back from the registered type on load.
func test_the_paper_parameters_round_trip_through_a_sad() -> void:
    var registries := _registries()
    var easel := _easel(Vector2i(256, 256))
    var doc := easel.document
    var paper := _paper_document(easel, registries)
    paper.generator_params["color"] = Color(0.2, 0.3, 0.4, 1.0)
    paper.generator_params["second"] = Color(0.7, 0.6, 0.1, 1.0)
    paper.generator_params["scale"] = 41.0
    _remove_scratch()
    assert_eq(SaExport.save_sad(doc, scratch), OK, "Saved")

    var loaded := _easel(Vector2i(256, 256))
    assert_eq(SaExport.load_sad(loaded.document, scratch), OK, "and loaded")
    var back := _layer_named(loaded.document, "Paper")
    assert_not_null(back, "The paper is there")
    assert_eq(back.layer_type, &"paper", "with its type")
    assert_eq(back.generator_params.get("color"), Color(0.2, 0.3, 0.4, 1.0), "its near colour")
    assert_eq(back.generator_params.get("second"), Color(0.7, 0.6, 0.1, 1.0), "its far colour")
    assert_eq(back.generator_params.get("scale"), 41.0, "and its cell width")
    assert_eq(back.chunks.size(), 0, "and no chunk")
    registries.layer_types.rebind([back])
    assert_true(back.is_generated(), "and rebinding after a load puts the kernel back")
    _remove_scratch()
    easel.free()
    loaded.free()
