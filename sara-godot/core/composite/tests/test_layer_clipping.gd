## Clipping masks: a layer shows only where the layer below it has paint.
##
## One flag on the layer. The base is the nearest layer below that is not
## itself clipped, so a stack of clipped layers share one, and a hidden base
## hides them all. A base and the layers clipped to it
## composite as one group, the way Photoshop's clipping masks do: one step of
## the walk, and around the active layer a scope of its own, walked from the
## clipped layers' chunks rather than cached, because the plate they are laid
## on is the layer being painted.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const RED := Color(1, 0, 0, 1)
const BLUE := Color(0, 0, 1, 1)
const GREEN := Color(0, 1, 0, 1)


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


## Background, Layer 1, then a base with one red chunk at (0, 0) and a clipped
## layer filled blue over both chunks. Layer 1 is made active afterwards so the
## pair sits above the active layer, unless the caller says otherwise.
func _base_and_clipped(doc: SaDocument, base_color: Color = RED) -> Array[SaLayer]:
    var base := SaLayerOps.new(doc).add()
    base.name = "Base"
    base.get_or_create_chunk(Vector2i(0, 0)).clear(base_color)
    var clipped := SaLayerOps.new(doc).add()
    clipped.name = "Clipped"
    doc.fill_layer(BLUE, clipped)
    SaLayerStack.set_clip_to_below(doc, clipped, true)
    return [base, clipped]


func test_a_clipped_layer_shows_only_where_the_layer_below_has_paint() -> void:
    var easel := _easel()
    var doc := easel.document
    var pair := _base_and_clipped(doc)
    doc.set_active_layer(_layer_named(doc, "Layer 1"))
    doc.fold.debt.settle(doc)

    assert_eq(SaLayerStack.clip_base(doc, pair[1]), pair[0], "The base is the layer below")
    assert_eq(doc.fold.top_stack.size(), 1, "Base and clipped are one step")
    assert_eq(doc.fold.top_stack[0][SaLayerStack.LAYER], pair[0], "the base's")
    var clipped := SaLayerStack.clipped_of(doc.fold.top_stack[0])
    assert_eq(clipped.size(), 1, "with the clipped layer's step inside it")
    assert_eq(SaLayerStack.layer_of(clipped[0]), pair[1], "which is the clipped layer")

    _composite(easel)
    assert_almost_eq(_texel(easel.output, 10, 10).b, 1.0, 0.02, "Over the base, the clipped layer shows")
    var outside := _texel(easel.output, 300, 10)
    assert_almost_eq(outside.b, 0.5, 0.02, "Beside it, the background shows through")
    assert_almost_eq(outside.r, 0.5, 0.02, "unchanged")

    SaLayerStack.set_clip_to_below(doc, pair[1], false)
    doc.update_caches()
    _composite(easel)
    assert_almost_eq(_texel(easel.output, 300, 10).b, 1.0, 0.02, "Unclipped, it covers the canvas again")

    easel.free()


## The mask is the base's alpha, not a yes or no: half a base is half a layer.
func test_a_half_transparent_base_halves_the_clipped_layer() -> void:
    var easel := _easel()
    var doc := easel.document
    _base_and_clipped(doc, Color(1, 0, 0, 0.5))
    doc.set_active_layer(_layer_named(doc, "Layer 1"))
    doc.fold.debt.settle(doc)
    _composite(easel)

    # The blue covers the base whole, so the group is blue at the base's half
    # alpha over grey 0.5, and none of the red shows through it.
    var texel := _texel(easel.output, 10, 10)
    assert_almost_eq(texel.r, 0.25, 0.02, "The grey halved under the group, and no red")
    assert_almost_eq(texel.b, 0.75, 0.02, "Blue at the base's half alpha over the grey")

    easel.free()


## Painting on a clipped layer: the layer and the live stroke are both masked,
## through the same scratch the stroke path already uses.
func test_the_active_layer_clipped_to_the_one_below_is_masked_stroke_included() -> void:
    var easel := _easel()
    var doc := easel.document
    var pair := _base_and_clipped(doc)
    doc.set_active_layer(pair[1])
    doc.fold.debt.settle(doc)
    doc.stroke_layer.get_or_create_chunk(Vector2i(0, 0)).clear(GREEN)
    doc.stroke_layer.get_or_create_chunk(Vector2i(1, 0)).clear(GREEN)
    _composite(easel)

    assert_almost_eq(_texel(easel.output, 10, 10).g, 1.0, 0.02, "Over the base, the stroke shows")
    assert_almost_eq(_texel(easel.output, 300, 10).g, 0.5, 0.02, "Beside it, neither the layer nor the stroke does")

    doc.stroke_layer.chunks.clear()
    easel.free()


## A layer clipped to the active one is laid on a plate that changes every
## dab, so it is not cached, and it follows the base without a rebuild.
func test_a_layer_clipped_to_the_active_layer_follows_it_and_is_not_cached() -> void:
    var easel := _easel()
    var doc := easel.document
    var base := _layer_named(doc, "Layer 1")
    base.get_or_create_chunk(Vector2i(0, 0)).clear(RED)
    var clipped := SaLayerOps.new(doc).add()
    doc.fill_layer(BLUE, clipped)
    SaLayerStack.set_clip_to_below(doc, clipped, true)
    doc.set_active_layer(base)
    doc.fold.debt.settle(doc)

    assert_true(doc.fold.top_stack.is_empty(), "Nothing above the group")
    assert_eq(doc.fold.active_scopes.size(), 1, "which is a scope around the active layer")
    var scope := doc.fold.active_scopes[0]
    assert_true(SaLayerStack.is_clip_scope(scope), "a clip scope")
    assert_eq(SaLayerStack.group_of(scope), base, "on the active layer as the base")
    var top: Array = scope[SaLayerStack.TOP]
    assert_eq(top.size(), 1, "with one step above it")
    assert_eq(SaLayerStack.layer_of(top[0]), clipped, "walked from the clipped layer's own chunks")
    assert_true(doc.fold.top_cache.chunks.is_empty(), "and never cached")

    _composite(easel)
    assert_almost_eq(_texel(easel.output, 300, 10).b, 0.5, 0.02, "Nothing where the base has no chunk")

    base.get_or_create_chunk(Vector2i(1, 0)).clear(RED)
    doc.invalidate_chunks([Vector2i(1, 0)])
    easel.process_pending_composite()
    assert_almost_eq(_texel(easel.output, 300, 10).b, 1.0, 0.02, "and blue the moment the base gains one, no rebuild needed")

    easel.free()


func test_a_clipped_layer_under_a_hidden_base_is_hidden() -> void:
    var easel := _easel()
    var doc := easel.document
    var pair := _base_and_clipped(doc)
    SaLayerOps.new(doc).set_visible(pair[0], false)
    doc.set_active_layer(_layer_named(doc, "Layer 1"))
    doc.fold.debt.settle(doc)
    assert_true(doc.fold.top_stack.is_empty(), "Neither the base nor what clips to it is walked")
    _composite(easel)
    assert_almost_eq(_texel(easel.output, 10, 10).b, 0.5, 0.02, "and the background shows")
    easel.free()


## Two clipped layers in a row clip to the same base, the way Krita's do.
func test_clipped_layers_stack_on_one_base() -> void:
    var easel := _easel()
    var doc := easel.document
    var pair := _base_and_clipped(doc)
    var second := SaLayerOps.new(doc).add()
    second.get_or_create_chunk(Vector2i(1, 0)).clear(GREEN)
    SaLayerStack.set_clip_to_below(doc, second, true)
    doc.set_active_layer(_layer_named(doc, "Layer 1"))
    doc.fold.debt.settle(doc)

    assert_eq(SaLayerStack.clip_base(doc, second), pair[0], "The second clipped layer skips the first to reach the base")
    _composite(easel)
    assert_almost_eq(_texel(easel.output, 300, 10).g, 0.5, 0.02, "so its chunk beyond the base shows nothing")
    assert_almost_eq(_texel(easel.output, 10, 10).b, 1.0, 0.02, "and the first clipped layer still shows over the base")

    easel.free()


## An additive key in the header. An older build ignores it and a file from one
## reads as unclipped.
func test_the_flag_round_trips_through_the_file() -> void:
    var easel := _easel(Vector2i(256, 256))
    var doc := easel.document
    var pair := _base_and_clipped(doc)
    var path := SaDataRoot.path("test_clipping_round_trip.sad")
    assert_eq(SaExport.save_sad(doc, path), OK, "Saved")

    var loaded := SaDocument.new()
    assert_eq(SaExport.load_sad(loaded, path, SaCompositor.new()), OK, "and loaded")
    assert_true(_layer_named(loaded, pair[1].name).clip_to_below, "The clipped layer comes back clipped")
    assert_false(_layer_named(loaded, pair[0].name).clip_to_below, "and the base does not")

    loaded.free()
    easel.free()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The chord Krita uses, registered through the public door like a module's
## shortcut, so the action exists without a line in project.godot.
func test_the_command_toggles_the_active_layer_and_has_its_chord() -> void:
    var surface := Fixtures.make_surface()
    var registries := Fixtures.make_registries(surface)
    var doc := surface.easel.document

    assert_true(registries.commands.has(&"layer_clip_to_below"), "The command is registered")
    assert_true(InputMap.has_action(&"layer_clip_to_below"), "and its action exists")
    assert_true(registries.commands.execute(&"layer_clip_to_below"), "It runs")
    assert_true(doc.active_layer.clip_to_below, "and clips the active layer")
    registries.commands.execute(&"layer_clip_to_below")
    assert_false(doc.active_layer.clip_to_below, "and the next press unclips it")

    Fixtures.teardown(surface)
