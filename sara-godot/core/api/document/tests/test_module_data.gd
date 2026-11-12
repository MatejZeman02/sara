## Module data in `.sad`: the interpretation, not the pixels.
##
## Field blobs, the schema and the layer type id already round-tripped. What did
## not was everything only a module understands: which colour set a document was
## painted with, and what a layer's concentration channels mean. Without it a
## `.sad` carrying module state is readable only by the exact build that wrote it,
## and such a document reopened with a different colour set silently changes
## every colour.
##
## The load-bearing assertion here is the byte-identity one. A file written by a
## build that had the module, opened by a build that does not, and saved again
## must be unchanged in that module's data, because the alternative is that
## opening a collaborator's file quietly destroys what they painted it with.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: saving and loading a document touches chunk textures.
const REQUIRES_GPU := true

const MIXING := &"sara-mixing-module"
const IMPASTO := &"sara-impasto"


func _registries() -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    return registries


func _document() -> SaDocument:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(64, 64), SaCompositor.new())
    return doc


func _first_layer(document: SaDocument) -> SaLayer:
    for child in document.get_children():
        if child is SaLayer:
            return child as SaLayer
    return null


## The header as it was actually written, so "byte-identical" means the bytes.
func _header_text(path: String) -> String:
    var file := FileAccess.open(path, FileAccess.READ)
    file.get_buffer(4)  # magic
    file.get_32()  # version
    var packed_size := file.get_32()
    var raw_size := file.get_32()
    var packed := file.get_buffer(packed_size)
    file.close()
    return packed.decompress(raw_size, SaSadFile.SAD_BLOB_COMPRESS).get_string_from_utf8()


func _cleanup(paths: Array) -> void:
    for path: String in paths:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_a_module_writes_document_state_and_reads_it_back() -> void:
    var registries := _registries()
    var ctx := registries.context.for_module(MIXING)
    var doc := _document()

    ctx.document_data(doc)["colour_set"] = "quinacridone-6"
    ctx.document_data(doc)["substrate"] = "linen"

    var path := SaDataRoot.path("test_module_data_document.sad")
    assert_eq(SaExport.save_sad(doc, path), OK, "The document saves")

    var loaded := SaDocument.new()
    assert_eq(SaExport.load_sad(loaded, path, SaCompositor.new()), OK, "and loads")

    var restored := ctx.document_data(loaded)
    assert_eq(restored.get("colour_set", ""), "quinacridone-6", "The module reads back what it wrote")
    assert_eq(restored.get("substrate", ""), "linen", "all of it")

    _cleanup([path])
    loaded.free()
    doc.free()


## Per layer as well as per document, because Kubelka-Munk is a layer type rather
## than a document mode.
func test_a_module_writes_layer_state_and_reads_it_back() -> void:
    var registries := _registries()
    var ctx := registries.context.for_module(MIXING)
    var doc := _document()

    ctx.layer_data(_first_layer(doc))["channels"] = ["cyan", "magenta", "yellow"]

    var path := SaDataRoot.path("test_module_data_layer.sad")
    assert_eq(SaExport.save_sad(doc, path), OK, "The document saves")

    var loaded := SaDocument.new()
    assert_eq(SaExport.load_sad(loaded, path, SaCompositor.new()), OK, "and loads")

    var restored := ctx.layer_data(_first_layer(loaded))
    assert_eq(restored.get("channels", []), ["cyan", "magenta", "yellow"], "The layer's own slice round-trips")

    _cleanup([path])
    loaded.free()
    doc.free()


## The definition of done for this phase.
##
## Save with the module, open on a build that has no idea what any of it means,
## save again. The header must be identical, because the alternative is that
## opening a collaborator's file quietly destroys what they painted it with.
func test_a_file_saved_without_the_module_is_byte_identical() -> void:
    var registries := _registries()
    var ctx := registries.context.for_module(MIXING)
    var doc := _document()

    # Deliberately mixed types, including an integer, which is the one that used
    # to make the second save differ from the first.
    var data := ctx.document_data(doc)
    data["colour_set"] = "quinacridone-6"
    data["layers_deep"] = 3
    data["opacity"] = 0.75
    data["mixed"] = true
    data["nested"] = {"z_last": [1, 2, 3], "a_first": null}
    ctx.layer_data(_first_layer(doc))["concentration_count"] = 8

    var written := SaDataRoot.path("test_module_data_written.sad")
    assert_eq(SaExport.save_sad(doc, written), OK, "A build with the module saves it")
    var original_header := _header_text(written)

    # A build without the module: nothing here registers it, nothing reads its
    # slice, and nothing knows the keys exist.
    var innocent := SaDocument.new()
    assert_eq(SaExport.load_sad(innocent, written, SaCompositor.new()), OK, "A build without it opens the file")

    var resaved := SaDataRoot.path("test_module_data_resaved.sad")
    assert_eq(SaExport.save_sad(innocent, resaved), OK, "and saves it again")

    assert_eq(_header_text(resaved), original_header, "The header must come back byte for byte")

    _cleanup([written, resaved])
    innocent.free()
    doc.free()


## JSON has one number type, and no amount of care invents an integer for it.
## Pinned because a module author will hit it, and because it is the reason
## SaExport writes the canonical form: the file is stable from its first save
## rather than from its second.
func test_an_integer_comes_back_as_a_float_and_then_stays_put() -> void:
    var registries := _registries()
    var ctx := registries.context.for_module(MIXING)
    var doc := _document()
    ctx.document_data(doc)["count"] = 3

    var path := SaDataRoot.path("test_module_data_int.sad")
    assert_eq(SaExport.save_sad(doc, path), OK, "It saves")

    var loaded := SaDocument.new()
    assert_eq(SaExport.load_sad(loaded, path, SaCompositor.new()), OK, "and loads")

    var count: Variant = ctx.document_data(loaded)["count"]
    assert_eq(typeof(count), TYPE_FLOAT, "The integer comes back as a float, because JSON has no other number")
    assert_almost_eq(float(count), 3.0, 0.0, "with the value intact")

    _cleanup([path])
    loaded.free()
    doc.free()


## Keyed by module id, which is what makes "a module's data" a boundary rather
## than a convention.
func test_a_module_cannot_reach_another_modules_slice() -> void:
    var registries := _registries()
    var mixing := registries.context.for_module(MIXING)
    var impasto := registries.context.for_module(IMPASTO)
    var doc := _document()

    mixing.document_data(doc)["secret"] = "mixing"
    impasto.document_data(doc)["secret"] = "impasto"

    assert_eq(mixing.document_data(doc)["secret"], "mixing", "Each module sees its own value")
    assert_eq(impasto.document_data(doc)["secret"], "impasto", "and not the other's")
    assert_eq(doc.module_data.size(), 2, "The document holds one slice per module")

    doc.free()


## The slice is returned by reference, so a module writes to the document simply
## by writing to the dictionary. Anything else would need a save-back call that
## somebody will forget.
func test_the_slice_is_live_rather_than_a_copy() -> void:
    var registries := _registries()
    var ctx := registries.context.for_module(MIXING)
    var doc := _document()

    var slice := ctx.document_data(doc)
    slice["written_later"] = 1.0

    assert_true(doc.module_data[String(MIXING)].has("written_later"), "Writing to the slice writes to the document")

    doc.free()


## Two layers must not share one dictionary, or a module writing to one layer's
## data would write to every layer's.
func test_each_layer_gets_its_own_slice() -> void:
    var registries := _registries()
    var ctx := registries.context.for_module(MIXING)
    var doc := _document()

    var layers: Array = doc.get_children().filter(func(child: Node) -> bool: return child is SaLayer)
    assert_true(layers.size() >= 2, "A default document has a background and a paint layer")

    ctx.layer_data(layers[0])["mine"] = "first"
    assert_false(ctx.layer_data(layers[1]).has("mine"), "The second layer's slice is its own")

    doc.free()


## Same, after a load, where the empty default is handed out per layer.
func test_each_loaded_layer_gets_its_own_slice() -> void:
    var registries := _registries()
    var ctx := registries.context.for_module(MIXING)
    var doc := _document()

    var path := SaDataRoot.path("test_module_data_independent.sad")
    assert_eq(SaExport.save_sad(doc, path), OK, "A document with no module data saves")

    var loaded := SaDocument.new()
    assert_eq(SaExport.load_sad(loaded, path, SaCompositor.new()), OK, "and loads")

    var layers: Array = loaded.get_children().filter(func(child: Node) -> bool: return child is SaLayer)
    ctx.layer_data(layers[0])["mine"] = "first"
    assert_false(ctx.layer_data(layers[1]).has("mine"), "Layers loaded from a file with no module data are still independent")

    _cleanup([path])
    loaded.free()
    doc.free()


## A plain document's header does not grow a key that says nothing, which is the
## same rule the colour space and the blend reference white already follow.
func test_a_document_with_no_module_data_writes_no_key() -> void:
    var doc := _document()

    var path := SaDataRoot.path("test_module_data_absent.sad")
    assert_eq(SaExport.save_sad(doc, path), OK, "It saves")

    var text := _header_text(path)
    assert_false(text.contains('"modules"'), "and writes no modules key at all")

    _cleanup([path])
    doc.free()


## Sara never inspects this data, so a module that is not installed costs the
## file nothing.
func test_data_from_a_module_nobody_has_survives_untouched() -> void:
    var doc := _document()
    doc.module_data["a-module-you-do-not-have"] = {"anything": "at all", "depth": 2.0}

    var path := SaDataRoot.path("test_module_data_stranger.sad")
    assert_eq(SaExport.save_sad(doc, path), OK, "It saves")

    var loaded := SaDocument.new()
    assert_eq(SaExport.load_sad(loaded, path, SaCompositor.new()), OK, "and opens rather than refusing")

    var stranger: Dictionary = loaded.module_data.get("a-module-you-do-not-have", {})
    assert_eq(stranger.get("anything", ""), "at all", "with a stranger's data intact")
    assert_almost_eq(float(stranger.get("depth", 0.0)), 2.0, 0.0, "all of it")

    _cleanup([path])
    loaded.free()
    doc.free()


func test_a_context_with_no_document_hands_back_something_writable() -> void:
    var registries := _registries()
    var ctx := registries.context.for_module(MIXING)

    var slice := ctx.document_data()
    assert_eq(slice.size(), 0, "No easel and no document means an empty slice")
    assert_eq(ctx.layer_data(null).size(), 0, "and a null layer likewise")


## A layer whose module is missing falls back to reading its `albedo` field.
##
## The final half of "a missing module is not a failed load". A Kubelka-Munk
## layer's albedo is derived, and without the module there is no hook to derive
## it, so the resolve pass has to leave the stored albedo exactly where it is
## rather than clearing it or refusing. What the compositor then draws is the
## last albedo the owning build resolved, which is the picture the file was saved
## looking like.
func test_a_layer_with_no_hook_keeps_the_albedo_it_was_saved_with() -> void:
    var doc := _document()
    var layer := _first_layer(doc)

    var sources: Array[StringName] = [&"concentrations"]
    var km_schema: Array[SaFieldSpec] = [
        SaFieldSpec.create(&"concentrations", RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, false),
        SaFieldSpec.create(SaFieldSpec.ALBEDO, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, true, sources),
    ]
    layer.schema = km_schema
    layer.layer_type = &"kubelka-munk"
    layer.chunks.clear()

    var chunk := layer.get_or_create_chunk(Vector2i.ZERO)
    chunk.albedo().clear(Color(0.25, 0.5, 0.75, 1.0))

    # No resolve hook, because the module that owns this type is not installed.
    assert_false(layer.resolve_hook.is_valid(), "There is nothing to derive the albedo with")
    layer.mark_all_unresolved()
    layer.resolve_pending()

    var rd := GlobalShaderCompiler.get_rd()
    var data: PackedByteArray = rd.texture_get_data(layer.get_field(Vector2i.ZERO, SaFieldSpec.ALBEDO).rid, 0)
    var texel := SaFieldSpec.decode_texel(data, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
    assert_almost_eq(texel.r, 0.25, 0.001, "The stored albedo is left exactly as it was")
    assert_almost_eq(texel.g, 0.5, 0.001, "on every channel")
    assert_almost_eq(texel.b, 0.75, 0.001, "so the file still shows the picture it was saved as")

    doc.free()
