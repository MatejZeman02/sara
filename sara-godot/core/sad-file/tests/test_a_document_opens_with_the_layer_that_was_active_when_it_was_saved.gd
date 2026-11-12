## A document opens with the layer that was active when it was
## saved.
##
## The reader made the first layer it built active, the bottom of the stack,
## whatever the painter had selected, so every session had to activate a layer
## by name before a new one could go above the rest. The header now carries the
## active layer's name, additive to v4, and a file without the key opens as it
## always did.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: a save reads chunks back and a load writes them.
const REQUIRES_GPU := true

static var scratch_round_trip: String = SaDataRoot.path("test_r3_round_trip.sad")
static var scratch_no_key: String = SaDataRoot.path("test_r3_no_key.sad")
static var scratch_stale_key: String = SaDataRoot.path("test_r3_stale_key.sad")


func after_each() -> void:
    for path: String in [scratch_round_trip, scratch_no_key, scratch_stale_key]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The default document's two layers, Background and Layer 1, and two more
## above them, so there are four and the third is neither end of the stack.
func _document_of_four() -> SaDocument:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(64, 64), SaCompositor.new())
    for layer_name: String in ["Shadows", "Highlights"]:
        var layer := SaLayer.new()
        layer.name = layer_name
        layer.schema = SaFieldSpec.schema_for_space(doc.color_space)
        doc.add_child(layer)
    return doc


func _layer_names(doc: SaDocument) -> Array[String]:
    var found: Array[String] = []
    for child in doc.get_children():
        if child is SaLayer and child != doc.stroke_layer:
            found.append(str(child.name))
    return found


func _active_name(doc: SaDocument) -> String:
    return str(doc.active_layer.name) if doc.active_layer != null else ""


## A v4 file with four layers, as the writer laid them down before the key
## existed, and *extra* put into its header. Built here rather than kept as a
## fixture, because the file is the header alone and nothing about its chunks
## matters to the question.
func _write_four_layers(path: String, extra: Dictionary) -> void:
    var layers: Array = []
    for layer_name: String in ["Background", "Layer 1", "Shadows", "Highlights"]:
        layers.append({"name": layer_name, "visible": true, "opacity": 1.0, "chunks": []})
    var header := {
        "format": "sad",
        "version": SaSadFile.SAD_VERSION,
        "width": 32,
        "height": 32,
        "layers": layers,
    }
    header.merge(extra)
    var raw := JSON.stringify(header).to_utf8_buffer()
    var packed := raw.compress(SaSadFile.SAD_BLOB_COMPRESS)
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(SaSadFile.SAD_MAGIC_V4.to_ascii_buffer())
    file.store_32(SaSadFile.SAD_VERSION)
    file.store_32(packed.size())
    file.store_32(raw.size())
    file.store_buffer(packed)
    file.close()


func test_a_document_of_four_layers_opens_with_the_third_active() -> void:
    var source := _document_of_four()
    var saved := _layer_names(source)
    assert_eq(saved.size(), 4, "The fixture has four layers")
    source.active_layer = source.get_node(NodePath(saved[2])) as SaLayer
    assert_eq(SaExport.save_sad(source, scratch_round_trip), OK, "Saving succeeds")

    var reopened := SaDocument.new()
    reopened.setup_default_document(Vector2i(16, 16), SaCompositor.new())
    assert_eq(reopened.active_layer.name, &"Layer 1", "The document being opened over has another layer active")
    assert_eq(SaExport.load_sad(reopened, scratch_round_trip), OK, "Loading succeeds")
    assert_eq(_layer_names(reopened), saved, "All four layers are back, in order")
    assert_eq(_active_name(reopened), saved[2], "and the third is the active one")
    source.free()
    reopened.free()


func test_the_first_and_the_last_layer_come_back_active_too() -> void:
    for index: int in [0, 3]:
        var source := _document_of_four()
        var saved := _layer_names(source)
        source.active_layer = source.get_node(NodePath(saved[index])) as SaLayer
        assert_eq(SaExport.save_sad(source, scratch_round_trip), OK, "Saving succeeds")
        var reopened := SaDocument.new()
        reopened.setup_default_document(Vector2i(16, 16), SaCompositor.new())
        assert_eq(SaExport.load_sad(reopened, scratch_round_trip), OK, "Loading succeeds")
        assert_eq(_active_name(reopened), saved[index], "Layer %d of the file is the active one" % index)
        source.free()
        reopened.free()


func test_a_file_written_before_the_key_opens_with_its_first_layer_active() -> void:
    _write_four_layers(scratch_no_key, {})
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(16, 16), SaCompositor.new())
    doc.active_layer = doc.get_node(NodePath("Layer 1")) as SaLayer
    assert_eq(SaExport.load_sad(doc, scratch_no_key), OK, "An older file still opens")
    assert_eq(_layer_names(doc).size(), 4, "with its four layers")
    assert_eq(_active_name(doc), "Background", "and its first layer active, as it always did")
    doc.free()


## A hand-edited file, or one a later build wrote after the layer was renamed
## elsewhere, must not leave the document with nothing active.
func test_a_key_that_names_no_layer_falls_back_to_the_first() -> void:
    _write_four_layers(scratch_stale_key, {SaSadActiveLayer.KEY: "Gone"})
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(16, 16), SaCompositor.new())
    assert_eq(SaExport.load_sad(doc, scratch_stale_key), OK, "The file opens")
    assert_eq(_active_name(doc), "Background", "on its first layer, rather than on nothing")
    _write_four_layers(scratch_stale_key, {SaSadActiveLayer.KEY: 3})
    assert_eq(SaExport.load_sad(doc, scratch_stale_key), OK, "A key that is not a name opens too")
    assert_eq(_active_name(doc), "Background", "and is read as absent")
    doc.free()
