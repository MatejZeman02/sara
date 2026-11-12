## Layer types through the public API.
##
## The field work built the whole field mechanism and gave it no module-facing door, so
## these assertions are all one question asked from different sides: can a module
## declare a layer type without doing what `skeleton_module.gd` is forbidden to
## do, and does the skeleton's own plain layer come through the same door.
##
## The two schemas exercised here are the real cases the generalisation was
## justified by rather than invented ones: impasto's `[albedo, height]` and
## a mixing layer's `[concentrations, thickness, albedo*]` with a derived albedo.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const LayersDockerScript = preload("res://ui/dockers/layers/layers_docker.gd")

const THIRD_PARTY := &"layer-type-test-module"


func _registries() -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    return registries


## The impasto schema: colour plus a single-channel height that is not colour.
func _impasto_schema() -> Array[SaFieldSpec]:
    var schema: Array[SaFieldSpec] = [
        SaFieldSpec.albedo(),
        SaFieldSpec.create(&"height", RenderingDevice.DATA_FORMAT_R32_SFLOAT, false),
    ]
    return schema


## The Kubelka-Munk schema: concentrations and thickness are authoritative, and
## the albedo the compositor reads is derived from them.
func _mixing_schema() -> Array[SaFieldSpec]:
    var sources: Array[StringName] = [&"concentrations", &"thickness"]
    var schema: Array[SaFieldSpec] = [
        SaFieldSpec.create(&"concentrations", RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, false),
        SaFieldSpec.create(&"thickness", RenderingDevice.DATA_FORMAT_R32_SFLOAT, false),
        SaFieldSpec.create(SaFieldSpec.ALBEDO, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, true, sources),
    ]
    return schema


## The executable half of the guiding rule for layer types.
func test_the_skeleton_registers_its_own_layer_type_through_the_api() -> void:
    var registries := _registries()

    assert_true(registries.layer_types.has(SaLayerTypeDescriptor.PLAIN), "The plain layer is a registered type")
    var descriptor := registries.layer_types.get_descriptor(SaLayerTypeDescriptor.PLAIN)
    assert_eq(descriptor.owner_module, &"sara-skeleton", "registered by the skeleton, like its blend modes")
    assert_eq(descriptor.schema.size(), 1, "and it is one authoritative colour field")
    assert_eq(descriptor.schema[0].id, SaFieldSpec.ALBEDO, "called albedo")


func test_a_module_registers_a_layer_type_the_same_way() -> void:
    var registries := _registries()
    var ctx := registries.context.for_module(THIRD_PARTY)

    var descriptor := SaLayerTypeDescriptor.create(&"impasto", _impasto_schema())
    descriptor.display_name = "Impasto"
    assert_true(ctx.register_layer_type(descriptor), "A module may register a layer type")
    assert_true(registries.layer_types.has(&"impasto"), "and it reaches the registry")
    assert_eq(registries.layer_types.get_descriptor(&"impasto").owner_module, THIRD_PARTY, "attributed to the module")

    ctx.remove_all_registrations()
    assert_false(registries.layer_types.has(&"impasto"), "Unloading the module takes its layer types with it")


func test_a_type_with_no_schema_is_refused() -> void:
    var registries := _registries()
    var empty: Array[SaFieldSpec] = []

    assert_false(registries.layer_types.register(SaLayerTypeDescriptor.create(&"hollow", empty)), "An empty schema is not a type")
    assert_false(registries.layer_types.has(&"hollow"), "so nothing is registered")


func test_registering_the_same_id_twice_is_refused() -> void:
    var registries := _registries()

    assert_false(
        registries.layer_types.register(SaLayerTypeDescriptor.plain()),
        "The skeleton already registered 'plain', and a second one would shadow it"
    )


## The F16 lesson, in the one place a layer type could reintroduce it.
##
## A colour field's depth is the document's declared choice. A height or
## concentration field is not colour and its precision is the layer type's own
## business, so the document has no opinion about it. Getting this backwards is
## what let a document record `"depth": "F16"` while allocating F32 chunks.
func test_colour_fields_take_the_document_depth_and_others_keep_their_own() -> void:
    var descriptor := SaLayerTypeDescriptor.create(&"impasto", _impasto_schema())

    var f32 := descriptor.schema_for(SaColorSpace.srgb())
    assert_eq(f32[0].format, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, "An F32 document stores colour as RGBA32F")
    assert_eq(f32[1].format, RenderingDevice.DATA_FORMAT_R32_SFLOAT, "and height keeps the format the type asked for")

    var space := SaColorSpace.srgb()
    space.depth = SaColorSpace.Depth.F16
    var f16 := descriptor.schema_for(space)
    assert_eq(f16[0].format, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, "An F16 document stores colour as RGBA16F")
    assert_eq(f16[1].format, RenderingDevice.DATA_FORMAT_R32_SFLOAT, "and height is unaffected, because height is not colour")


## Two layers of one type must not share a spec object one of them could edit.
func test_each_layer_gets_its_own_field_specs() -> void:
    var descriptor := SaLayerTypeDescriptor.plain()

    var first := descriptor.schema_for(SaColorSpace.srgb())
    var second := descriptor.schema_for(SaColorSpace.srgb())
    assert_false(first[0] == second[0], "Two resolutions of one schema are separate objects")
    assert_false(first[0] == descriptor.schema[0], "and neither is the template the descriptor holds")


func test_applying_a_type_sets_everything_a_layer_needs() -> void:
    var registries := _registries()
    var ctx := registries.context.for_module(THIRD_PARTY)
    var descriptor := SaLayerTypeDescriptor.create(&"impasto", _impasto_schema())
    descriptor.default_blend_mode = &"multiply"
    ctx.register_layer_type(descriptor)

    var layer := SaLayer.new()
    assert_true(registries.layer_types.apply_to(layer, &"impasto", SaColorSpace.srgb()), "The type applies")
    assert_eq(layer.layer_type, &"impasto", "The layer reports what it is")
    assert_eq(layer.schema.size(), 2, "and carries the type's fields")
    assert_eq(layer.blend_mode, &"multiply", "and starts on the type's default blend mode")

    layer.free()


## An unknown type leaves the layer exactly as it was, rather than half applied.
func test_applying_an_unknown_type_changes_nothing() -> void:
    var registries := _registries()
    var layer := SaLayer.new()
    var before := layer.schema

    assert_false(registries.layer_types.apply_to(layer, &"not_a_type", SaColorSpace.srgb()), "An unknown type is refused")
    assert_eq(layer.layer_type, &"", "The layer is not marked as anything")
    assert_true(layer.schema == before, "and its schema is untouched")

    layer.free()


## `create_layer` is the door a module uses instead of constructing an SaLayer
## and poking its schema.
func test_create_layer_builds_a_typed_layer_in_the_document() -> void:
    var registries := _registries()
    var ctx := registries.context.for_module(THIRD_PARTY)
    var descriptor := SaLayerTypeDescriptor.create(&"impasto", _impasto_schema())
    ctx.register_layer_type(descriptor)

    var surface := Fixtures.make_surface()
    var doc := surface.easel.document

    var layer := ctx.create_layer(&"impasto", doc)
    assert_not_null(layer, "The module gets a layer back")
    assert_eq(layer.layer_type, &"impasto", "of the type it asked for")
    assert_eq(layer.schema.size(), 2, "with the type's fields")
    assert_true(layer.get_parent() == doc, "already in the document")

    Fixtures.teardown(surface)


## A caller that silently gets the wrong kind of layer finds out at the first
## dab, in the compositor, with nothing to say why.
func test_create_layer_refuses_a_type_nobody_registered() -> void:
    var registries := _registries()
    var ctx := registries.context.for_module(THIRD_PARTY)
    var surface := Fixtures.make_surface()
    var doc := surface.easel.document

    var before := doc.get_children().size()
    assert_null(ctx.create_layer(&"not_a_type", doc), "An unregistered type gets null")
    assert_eq(doc.get_children().size(), before, "and no layer is added")

    Fixtures.teardown(surface)


## The end of the chain, and the reason any of this exists: a layer type whose
## albedo is derived actually gets recomputed before the compositor reads it.
##
## Two facts, because the first one is the surprise. A chunk the layer gains
## is resolved by the document's own cache rebuild, since
## `SaDocument.update_caches` resolves every layer before reading it. So the
## hook is on the real composite path and not only on the one this test calls
## by hand, which is the half that would otherwise be untested. Then the
## explicit pass, which runs it exactly once per chunk that needs it. A new
## layer holds no chunks until paint lands, so one is made here.
func test_a_derived_field_resolves_through_the_hook_the_type_supplied() -> void:
    var registries := _registries()
    var ctx := registries.context.for_module(THIRD_PARTY)

    var resolved: Array[Vector2i] = []
    var descriptor := SaLayerTypeDescriptor.create(&"mixing", _mixing_schema())
    descriptor.resolve = func(_layer: SaLayer, grid_pos: Vector2i, _chunk: SaChunk) -> void: resolved.append(grid_pos)
    ctx.register_layer_type(descriptor)

    var surface := Fixtures.make_surface()
    var layer := ctx.create_layer(&"mixing", surface.easel.document)
    assert_not_null(layer, "The mixing layer is created")
    assert_true(resolved.is_empty(), "and holds nothing to resolve yet")
    layer.get_or_create_chunk(Vector2i(0, 0))
    surface.easel.document.update_caches()
    assert_false(resolved.is_empty(), "A chunk it gains is resolved by the document's own cache rebuild")

    resolved.clear()
    layer.get_or_create_chunk(Vector2i(0, 0))
    layer.mark_all_unresolved()
    layer.resolve_pending()

    assert_eq(resolved, [Vector2i(0, 0)], "and an explicit pass runs it once, for the chunk that needed it")

    resolved.clear()
    layer.resolve_pending()
    assert_true(resolved.is_empty(), "A chunk that has not moved since is not resolved again")

    Fixtures.teardown(surface)


## A `.sad` records the type id, not the Callable. A loaded layer has its fields
## and nothing to recompute the derived ones with until this runs.
func test_rebind_reattaches_the_hook_to_a_layer_that_only_knows_its_type_id() -> void:
    var registries := _registries()
    var ctx := registries.context.for_module(THIRD_PARTY)
    var descriptor := SaLayerTypeDescriptor.create(&"mixing", _mixing_schema())
    descriptor.resolve = func(_layer: SaLayer, _grid_pos: Vector2i, _chunk: SaChunk) -> void: pass
    ctx.register_layer_type(descriptor)

    # What a freshly loaded layer looks like: fields from the file, type id from
    # the file, and no hook.
    var layer := SaLayer.new()
    layer.layer_type = &"mixing"
    layer.schema = descriptor.schema_for(SaColorSpace.srgb())
    assert_false(layer.resolve_hook.is_valid(), "A loaded layer starts with no hook")

    registries.layer_types.rebind([layer])
    assert_true(layer.resolve_hook.is_valid(), "and rebind gives it the one its type declares")

    layer.free()


## Losing a layer because a collaborator's module is not installed would be worse
## than opening it inert.
func test_rebind_leaves_a_layer_whose_module_is_missing_alone() -> void:
    var registries := _registries()

    var layer := SaLayer.new()
    layer.layer_type = &"a_module_you_do_not_have"
    var schema := layer.schema

    registries.layer_types.rebind([layer])
    assert_eq(layer.layer_type, &"a_module_you_do_not_have", "The layer keeps the type it claims")
    assert_true(layer.schema == schema, "and its fields, so a save writes them back")
    assert_false(layer.resolve_hook.is_valid(), "It simply does not resolve")

    layer.free()


## A type naming a format nothing can allocate is caught at startup rather than
## at the first dab.
func test_validate_catches_a_format_nothing_can_allocate() -> void:
    var registries := _registries()
    assert_true(registries.validate().is_empty(), "The skeleton's own types are healthy")

    var bogus: Array[SaFieldSpec] = [SaFieldSpec.create(&"nonsense", RenderingDevice.DATA_FORMAT_R8_UNORM)]
    registries.layer_types.register(SaLayerTypeDescriptor.create(&"bogus", bogus))

    var problems := registries.validate()
    assert_eq(problems.size(), 1, "The unallocatable format is reported")
    assert_true(problems[0].contains("nonsense"), "by field name: %s" % problems[0])


## The add button is built from the registry rather than from a hardcoded call
## One click always adds the plain type, whatever else is registered.
func test_the_add_button_adds_the_one_registered_type() -> void:
    var registries := _registries()
    # The skeleton registers the background as well, and the
    # paper beside it, the canvas, and
    # several types is the list case below. One type is the plain layer alone.
    registries.layer_types.unregister(&"background")
    registries.layer_types.unregister(&"paper")
    registries.layer_types.unregister(&"canvas")
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)

    var docker := LayersDockerScript.new()
    docker.name = "LayersDocker"
    canvas.add_child(docker)
    docker.target_canvas = canvas
    docker._ready()
    docker.bind_registries(registries.blend_modes, registries.layer_types)

    var before := _layer_count(canvas.document)
    docker.actions.add_layer()
    assert_eq(_layer_count(canvas.document), before + 1, "One click adds one layer")
    assert_eq(canvas.document.active_layer.layer_type, SaLayerTypeDescriptor.PLAIN, "of the type the skeleton registered")

    canvas.free()


## The definition of done for this phase: removing the skeleton's registration
## has to break the docker rather than leave it silently working. A registry that
## is bound and empty is a broken application, not a minimal one, because a door
## only the built-ins can walk through is not a door.
func test_the_add_button_refuses_when_nothing_is_registered() -> void:
    var registries := _registries()
    registries.layer_types.unregister(SaLayerTypeDescriptor.PLAIN)
    registries.layer_types.unregister(&"background")
    registries.layer_types.unregister(&"paper")
    registries.layer_types.unregister(&"canvas")
    registries.layer_types.unregister(SaBackdropLayer.TYPE_ID)
    registries.layer_types.unregister(SaEffectLayer.TYPE_ID)
    registries.layer_types.unregister(SaFrameLayer.TYPE_ID)

    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)

    var docker := LayersDockerScript.new()
    docker.name = "LayersDocker"
    canvas.add_child(docker)
    docker.target_canvas = canvas
    docker._ready()
    docker.bind_registries(registries.blend_modes, registries.layer_types)

    var before := _layer_count(canvas.document)
    docker.actions.add_layer()
    assert_eq(_layer_count(canvas.document), before, "No type registered, so no layer and a loud error")

    canvas.free()


## A second registered type shows up in the arrow's list beside the plus
## No edit in the docker: that is the whole point of the type living in
## a descriptor.
func test_a_second_registered_type_turns_the_button_into_a_list() -> void:
    var registries := _registries()
    var ctx := registries.context.for_module(THIRD_PARTY)
    var descriptor := SaLayerTypeDescriptor.create(&"impasto", _impasto_schema())
    descriptor.display_name = "Impasto"
    ctx.register_layer_type(descriptor)

    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)

    var docker := LayersDockerScript.new()
    docker.name = "LayersDocker"
    canvas.add_child(docker)
    docker.target_canvas = canvas
    docker._ready()
    docker.bind_registries(registries.blend_modes, registries.layer_types)

    # The background is excluded from the arrow's list: a document
    # already has one, made at New.
    docker.actions.fill_add_type_menu()
    var list: SaChoicePopup = docker.actions._add_type_menu
    assert_true(list.row_ids().has(&"impasto"), "The module's type is a row of the arrow's list")

    # What pressing that row does. The list is filled and not popped here, because
    # opening a Window in a test maps a real OS window unless the root viewport
    # embeds subwindows. A row is keyed on the type's own id.
    var before := _layer_count(canvas.document)
    list.press_row(&"impasto")
    assert_eq(_layer_count(canvas.document), before + 1, "Choosing the module's type adds a layer")
    assert_eq(canvas.document.active_layer.layer_type, &"impasto", "of that type")
    assert_eq(canvas.document.active_layer.schema.size(), 2, "with the fields the module declared")

    canvas.free()


## A type that stores nothing is not what keeps a kind off the
## arrow. The paper is in the arrow's Ground list, and a
## press adds one, and the background is still left out, because a document is
## born with one.
func test_the_arrow_offers_the_paper_and_not_the_background() -> void:
    var registries := _registries()
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)

    var docker := LayersDockerScript.new()
    docker.name = "LayersDocker"
    canvas.add_child(docker)
    docker.target_canvas = canvas
    docker._ready()
    docker.bind_registries(registries.blend_modes, registries.layer_types)

    docker.actions.fill_add_type_menu()
    var list: SaChoicePopup = docker.actions._add_type_menu
    var ids := list.row_ids()
    var labels := list.row_labels()
    assert_eq(ids.size(), 5, "Five rows: %s" % str(ids))
    if ids.size() == 5:
        assert_eq(ids[0], SaLayerTypeDescriptor.PLAIN, "Paint Layer first")
        assert_eq(ids[1], SaBackdropLayer.TYPE_ID, "the adjustment layer after it")
        assert_eq(ids[2], SaEffectLayer.TYPE_ID, "the effect layer after it")
        assert_eq(ids[3], SaFrameLayer.TYPE_ID, "the frame layer after it, which holds a frame another program sent")
        assert_eq(ids[4], SaGroundChoice.ROW, "and the grounds one Ground row last")
        assert_eq(labels[4], "Ground", "under its own name")
    assert_true(registries.layer_types.has(&"background"), "The background is registered")
    assert_false(ids.has(&"background"), "and is not a row")
    var grounds := docker.actions.open_grounds()
    var ground_ids := grounds.row_ids().slice(0, 3)
    var expected: Array[StringName] = [&"background", &"paper", &"canvas"]
    assert_eq(ground_ids, expected, "The Ground list holds the solid colour, the paper and the canvas")
    assert_eq(grounds.row_labels()[1], "Paper", "the paper under its own name")

    var before := _layer_count(canvas.document)
    assert_true(grounds.press_row(&"paper"), "The paper row takes a press")
    assert_eq(_layer_count(canvas.document), before + 1, "and adds a layer")
    var paper := canvas.document.active_layer
    assert_eq(paper.layer_type, &"paper", "of the paper type")
    assert_true(paper.is_generated(), "which stores nothing")
    assert_eq(paper.chunks.size(), 0, "so it holds no chunk")

    canvas.free()


func _layer_count(document: SaDocument) -> int:
    return document.get_children().filter(func(child: Node) -> bool: return child is SaLayer).size()


## A `.sad` records which type a layer is, so a typed layer survives a save.
##
## Without this the type is a runtime-only fact: an impasto layer saved and
## reopened keeps its fields, because the schema already round-trips, and becomes
## a layer nobody can resolve or identify.
func test_a_layer_type_survives_a_save_and_a_load() -> void:
    var registries := _registries()
    var ctx := registries.context.for_module(THIRD_PARTY)
    ctx.register_layer_type(SaLayerTypeDescriptor.create(&"impasto", _impasto_schema()))

    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(64, 64), SaCompositor.new())

    var layer := ctx.create_layer(&"impasto", doc)
    assert_not_null(layer, "The impasto layer is created")

    var path := SaDataRoot.path("test_layer_type_roundtrip.sad")
    assert_eq(SaExport.save_sad(doc, path), OK, "Saving a document with a typed layer succeeds")

    var loaded := SaDocument.new()
    assert_eq(SaExport.load_sad(loaded, path, SaCompositor.new()), OK, "and loading it back succeeds")

    var restored: SaLayer = null
    for child in loaded.get_children():
        if child is SaLayer and (child as SaLayer).layer_type == &"impasto":
            restored = child
    assert_not_null(restored, "The layer comes back knowing what type it is")
    assert_eq(restored.schema.size(), 2, "with the fields that type declared")

    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    loaded.free()
    doc.free()


## Losing a collaborator's layer because you had not installed their module would
## be worse than opening it inert, so the id is kept even when nothing can
## resolve it, and written back out on the next save.
func test_an_unknown_layer_type_is_preserved_rather_than_dropped() -> void:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(64, 64), SaCompositor.new())

    # What a document written by a build that had the module looks like to a
    # build that does not: a type id nothing in this registry knows.
    var layer := _first_layer(doc)
    layer.layer_type = &"a_module_you_do_not_have"

    var path := SaDataRoot.path("test_layer_type_missing_module.sad")
    assert_eq(SaExport.save_sad(doc, path), OK, "It saves")

    var loaded := SaDocument.new()
    assert_eq(SaExport.load_sad(loaded, path, SaCompositor.new()), OK, "and opens rather than refusing")
    assert_eq(_first_layer(loaded).layer_type, &"a_module_you_do_not_have", "with the type id it did not understand intact")

    # Written back out unchanged, which is the half that matters: opening and
    # saving on a build without the module must not silently strip the layer's
    # identity from the collaborator's file.
    var again := SaDataRoot.path("test_layer_type_missing_module_2.sad")
    assert_eq(SaExport.save_sad(loaded, again), OK, "and saves again")
    var reloaded := SaDocument.new()
    assert_eq(SaExport.load_sad(reloaded, again, SaCompositor.new()), OK, "and reopens")
    assert_eq(_first_layer(reloaded).layer_type, &"a_module_you_do_not_have", "still carrying the type it never understood")

    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(again))
    reloaded.free()
    loaded.free()
    doc.free()


## Empty means a plain colour layer, and it stays empty rather than being
## upgraded to `plain` on the way through a file. A default document's own
## Background and Layer 1 are built by SaDocument with no registry in reach, so
## the two spellings coexist on purpose and nothing may branch on the difference.
func test_a_layer_that_was_never_typed_stays_untyped() -> void:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(64, 64), SaCompositor.new())

    var path := SaDataRoot.path("test_layer_type_absent.sad")
    assert_eq(SaExport.save_sad(doc, path), OK, "It saves")

    var loaded := SaDocument.new()
    assert_eq(SaExport.load_sad(loaded, path, SaCompositor.new()), OK, "and loads")
    assert_eq(_first_layer(loaded).layer_type, &"", "An untyped layer stays untyped rather than becoming 'plain'")

    # The two spellings must be interchangeable, or something will eventually
    # branch on which one it got.
    var plain := SaLayerTypeDescriptor.plain()
    var untyped := _first_layer(loaded)
    assert_eq(untyped.schema.size(), plain.schema.size(), "An untyped layer has a plain layer's schema")
    assert_eq(untyped.schema[0].id, plain.schema[0].id, "the same field")
    assert_false(untyped.resolve_hook.is_valid(), "and no resolve hook, exactly as a plain layer has none")

    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    loaded.free()
    doc.free()


func _first_layer(document: SaDocument) -> SaLayer:
    for child in document.get_children():
        if child is SaLayer:
            return child as SaLayer
    return null
