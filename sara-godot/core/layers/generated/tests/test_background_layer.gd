## A background that stores nothing : a layer type whose kernel
## fills the dirty region instead of reading chunks, registered through the
## same door a module's type takes, walked by the stack without ever folding,
## filled by setting its colour, saved as its parameters, and drawn beyond
## the document rectangle by the canvas.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const THIRD_PARTY := &"background-test-module"
const PAPER := Color(0.9, 0.8, 0.2, 1.0)
static var scratch: String = SaDataRoot.path("test_background_layer.sad")


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


func _composite(easel: SaEasel) -> void:
    easel.request_full_composite()
    easel.process_pending_composite()


func _layer_named(doc: SaDocument, layer_name: String) -> SaLayer:
    return doc.get_node(layer_name) as SaLayer


## A background under everything: the default document's stored grey
## background is dropped and a generated one takes its place at the bottom,
## coloured *paper*, with Layer 1 active above it.
func _paper_document(easel: SaEasel, registries: SaRegistries, paper: Color = PAPER) -> SaLayer:
    var doc := easel.document
    SaLayerOps.new(doc).remove(_layer_named(doc, "Background"))
    var layer := SaLayerOps.new(doc).add(&"background", registries.layer_types)
    layer.name = "Paper"
    doc.fill_layer(paper, layer)
    SaLayerOps.new(doc).move(layer, -1)
    doc.set_active_layer(_layer_named(doc, "Layer 1"))
    doc.fold.debt.settle(doc)
    doc.update_caches()
    return layer


func _remove_scratch() -> void:
    var path := ProjectSettings.globalize_path(scratch)
    for suffix: String in ["", "1", ".saving"]:
        if FileAccess.file_exists(path + suffix):
            DirAccess.remove_absolute(path + suffix)


## The skeleton's background goes through the registry like the plain layer,
## and a layer of it has the kernel, the defaults in the document's space,
## and no chunks.
func test_the_background_type_is_registered_and_applies_to_a_layer() -> void:
    var registries := _registries()
    assert_true(registries.layer_types.has(&"background"), "The background is a registered type")
    var descriptor := registries.layer_types.get_descriptor(&"background")
    assert_eq(descriptor.owner_module, &"sara-skeleton", "registered by the skeleton")
    assert_true(descriptor.is_generated(), "and it evaluates a kernel")
    assert_true(registries.layer_types.validate().is_empty(), "with a schema the allocator can serve")

    var easel := _easel()
    var doc := easel.document
    var layer := SaLayerOps.new(doc).add(&"background", registries.layer_types)
    assert_true(layer.is_generated(), "A layer of it stores nothing")
    assert_eq(layer.generator, "background", "and names its kernel")
    assert_eq(layer.chunks.size(), 0, "and holds no chunk")
    assert_eq(
        layer.generator_params.get("color"), doc.background_fill(), "Its default is the grey a stored background is filled with"
    )
    easel.free()


## The kernel fills the document where no layer has a chunk, so the paper
## shows in the corner nobody painted, and Layer 1's paint sits over it.
func test_the_background_draws_everywhere_without_a_chunk() -> void:
    var registries := _registries()
    var easel := _easel()
    var doc := easel.document
    var paper := _paper_document(easel, registries)
    _layer_named(doc, "Layer 1").get_or_create_chunk(Vector2i(0, 0)).clear(Color(0, 0, 1, 1))
    doc.update_caches()

    assert_eq(doc.fold.bottom_stack.size(), 1, "The paper is one step below the active layer")
    assert_eq(doc.fold.bottom_stack[0][SaLayerStack.LAYER], paper, "walked as itself, never folded")
    assert_eq(doc.fold.bottom_cache.chunks.size(), 0, "so the bottom cache holds nothing")
    assert_eq(paper.chunks.size(), 0, "and the paper still holds no chunk")

    _composite(easel)
    var far := _texel(easel.output, 500, 200)
    assert_almost_eq(far.r, PAPER.r, 0.02, "Where nothing is painted the paper shows")
    assert_almost_eq(far.g, PAPER.g, 0.02, "in its colour")
    assert_almost_eq(far.a, 1.0, 0.01, "opaque")
    var painted := _texel(easel.output, 10, 10)
    assert_almost_eq(painted.b, 1.0, 0.02, "and Layer 1 paints over it")
    easel.free()


## Picking the paper in the Layers docker made it vanish from
## inside the document, because the active tier read it as a paint layer with no
## chunks. The same document as the case above, with the paper picked instead of
## Layer 1, has to draw the same two texels.
func test_the_background_still_draws_while_it_is_the_picked_layer() -> void:
    var registries := _registries()
    var easel := _easel()
    var doc := easel.document
    var paper := _paper_document(easel, registries)
    _layer_named(doc, "Layer 1").get_or_create_chunk(Vector2i(0, 0)).clear(Color(0, 0, 1, 1))
    doc.set_active_layer(paper)
    doc.fold.debt.settle(doc)
    doc.update_caches()

    assert_eq(doc.active_layer, paper, "The paper is the picked layer")
    _composite(easel)
    var far := _texel(easel.output, 500, 200)
    assert_almost_eq(far.r, PAPER.r, 0.02, "Where nothing is painted the paper still shows while it is picked")
    assert_almost_eq(far.g, PAPER.g, 0.02, "in its colour")
    assert_almost_eq(far.a, 1.0, 0.01, "opaque")
    var painted := _texel(easel.output, 10, 10)
    assert_almost_eq(painted.b, 1.0, 0.02, "and Layer 1, above it, still paints over it")
    easel.free()


## A stored layer between two runs: the layers below the active one fold into
## caches on either side of the paper, and the paper stays a step of its own.
func test_the_paper_splits_the_fold_below_the_active_layer() -> void:
    var registries := _registries()
    var easel := _easel()
    var doc := easel.document
    var paper := _paper_document(easel, registries)
    var a := SaLayerOps.new(doc).add()
    a.name = "A"
    a.get_or_create_chunk(Vector2i(0, 0)).clear(Color.RED)
    var b := SaLayerOps.new(doc).add()
    b.name = "B"
    b.get_or_create_chunk(Vector2i(1, 0)).clear(Color.GREEN)
    var above := SaLayerOps.new(doc).add()
    above.name = "Top"
    doc.set_active_layer(above)
    doc.fold.debt.settle(doc)

    assert_eq(doc.fold.bottom_stack.size(), 2, "Paper, then one cache for the three stored layers")
    assert_eq(doc.fold.bottom_stack[0][SaLayerStack.LAYER], paper, "the paper first")
    assert_eq(doc.fold.bottom_stack[1][SaLayerStack.LAYER], doc.fold.bottom_cache, "and the fold after it")
    assert_eq(doc.fold.bottom_cache.chunks.size(), 2, "holding a chunk only where A or B does")
    easel.free()


## Above the active layer the paper blends against what is under it, so a
## Multiply paper over a grey painting darkens it, and it breaks a run of
## Normal layers rather than joining a cache.
func test_a_multiply_paper_above_the_painting_darkens_it() -> void:
    var registries := _registries()
    var easel := _easel(Vector2i(256, 256))
    var doc := easel.document
    doc.fill_layer(Color(0.5, 0.5, 0.5, 1.0), _layer_named(doc, "Layer 1"))
    var paper := SaLayerOps.new(doc).add(&"background", registries.layer_types)
    # A ground goes in under the paint, so this one is
    # moved over the painting it is meant to darken.
    SaLayerOps.new(doc).move(paper, _layer_named(doc, "Layer 1").get_index() - paper.get_index())
    doc.fill_layer(Color(0.5, 0.5, 0.5, 1.0), paper)
    SaLayerOps.new(doc).set_blend_mode(paper, &"multiply")
    var normal := SaLayerOps.new(doc).add()
    normal.name = "Over"
    doc.set_active_layer(_layer_named(doc, "Layer 1"))
    doc.fold.debt.settle(doc)

    assert_eq(doc.fold.top_stack.size(), 2, "The paper and the Normal layer above it are two steps")
    assert_eq(doc.fold.top_stack[0][SaLayerStack.LAYER], paper, "the paper from its kernel")
    _composite(easel)
    var texel := _texel(easel.output, 10, 10)
    assert_almost_eq(texel.r, 0.25, 0.02, "Mid grey under a Multiply paper of mid grey is a quarter")
    easel.free()


## A fill on a paper is its colour, one history step, and undo brings the
## old colour back on the canvas.
func test_a_fill_sets_the_colour_and_undoes() -> void:
    var registries := _registries()
    var easel := _easel(Vector2i(256, 256))
    var doc := easel.document
    var paper := _paper_document(easel, registries)
    var steps := doc.undo_redo.get_history_count()
    doc.fill_layer(Color(0, 0, 1, 1), paper)
    assert_eq(paper.chunks.size(), 0, "A fill allocates nothing on a paper")
    assert_eq(paper.generator_params["color"], Color(0, 0, 1, 1), "and sets its colour")
    assert_eq(doc.undo_redo.get_history_count(), steps + 1, "as one history step")
    _composite(easel)
    assert_almost_eq(_texel(easel.output, 200, 200).b, 1.0, 0.02, "which the canvas shows")

    assert_true(doc.undo(), "Undo takes it back")
    assert_eq(paper.generator_params["color"], PAPER, "to the colour before")
    _composite(easel)
    assert_almost_eq(_texel(easel.output, 200, 200).r, PAPER.r, 0.02, "on the canvas too")
    easel.free()


## The parameters travel with the file and the kernel comes back from the
## registered type on load.
func test_a_paper_round_trips_through_a_sad() -> void:
    var registries := _registries()
    var easel := _easel(Vector2i(256, 256))
    var doc := easel.document
    _paper_document(easel, registries)
    _remove_scratch()
    assert_eq(SaExport.save_sad(doc, scratch), OK, "Saved")

    var loaded := _easel(Vector2i(256, 256))
    assert_eq(SaExport.load_sad(loaded.document, scratch), OK, "and loaded")
    var back := _layer_named(loaded.document, "Paper")
    assert_not_null(back, "The paper is there")
    assert_eq(back.layer_type, &"background", "with its type")
    assert_eq(back.generator_params.get("color"), PAPER, "and its colour")
    assert_eq(back.chunks.size(), 0, "and no chunk")
    assert_false(back.is_generated(), "The file records no kernel, the type does")
    registries.layer_types.rebind([back])
    assert_true(back.is_generated(), "which rebinding after a load puts back")
    _remove_scratch()
    easel.free()
    loaded.free()


## The canvas draws the bottom-most paper beyond the document, in display
## colour with the layer's opacity, and nothing when there is none.
func test_the_view_draws_the_bottom_paper_beyond_the_document() -> void:
    var registries := _registries()
    var easel := _easel(Vector2i(256, 256))
    var doc := easel.document
    assert_null(SaGeneratedLayer.view_source(doc), "A document with stored layers only has nothing to draw beyond")
    var paper := _paper_document(easel, registries)
    assert_eq(SaGeneratedLayer.view_source(doc), paper, "The paper is what the view draws beyond the rectangle")
    SaLayerOps.new(doc).set_visible(paper, false)
    assert_null(SaGeneratedLayer.view_source(doc), "unless it is hidden")
    SaLayerOps.new(doc).set_visible(paper, true)

    var rect := ColorRect.new()
    SaLayerOps.new(doc).set_opacity(paper, 0.5)
    SaGeneratedLayer.apply_view(rect, doc)
    assert_true(rect.visible, "The rect shows")
    var material := rect.material as ShaderMaterial
    assert_not_null(material, "through the generator's view shader")
    var shown: Color = material.get_shader_parameter("color_a")
    assert_almost_eq(shown.r, doc.color_space.to_display(PAPER).r, 0.001, "in display colour")
    assert_almost_eq(shown.a, 0.5, 0.001, "with the layer's opacity in its alpha")
    rect.free()
    easel.free()


## A module's generated type reaches the walk the same way the skeleton's
## does, which is the rule the type registry exists for.
func test_a_module_generated_type_reaches_the_walk() -> void:
    var registries := _registries()
    var ctx := registries.context.for_module(THIRD_PARTY)
    var descriptor := SaLayerTypeDescriptor.create(&"contract_paper", SaFieldSpec.default_schema())
    descriptor.generator = "background"
    descriptor.generator_defaults = {"color": Color(0, 1, 0, 1)}
    assert_true(ctx.register_layer_type(descriptor), "A module may register a generated type")

    var easel := _easel(Vector2i(256, 256))
    var doc := easel.document
    SaLayerOps.new(doc).remove(_layer_named(doc, "Background"))
    var layer := SaLayerOps.new(doc).add(&"contract_paper", registries.layer_types)
    SaLayerOps.new(doc).move(layer, -1)
    doc.set_active_layer(_layer_named(doc, "Layer 1"))
    doc.fold.debt.settle(doc)
    _composite(easel)
    assert_almost_eq(_texel(easel.output, 100, 100).g, 1.0, 0.02, "and its colour fills the document")
    easel.free()
