## The painter makes a layer at
## twice the document's resolution from the Layer menu, sees in the Layers
## docker which layer it is, and gets it back the same from a `.sad` file.
extends "res://tests/test_framework.gd"

## Chunks are real textures, so this needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## A file written before the layer had a scale, with plain layers only.
const OLD_FILE := "res://tests/data/plain_v4.sad"
static var scratch_saved: String = SaDataRoot.path("test_x1_double_resolution.sad")


func _layers(doc: SaDocument) -> Array:
    return doc.get_children().filter(func(c: Node) -> bool: return c is SaLayer)


## Fills one chunk's albedo with a gradient no two texels share, in the
## texture's own format, and answers the bytes written.
func _paint_pattern(chunk: SaChunk) -> PackedByteArray:
    var texture: SaTexture = chunk.fields[SaFieldSpec.ALBEDO]
    var edge := chunk.pixel_size()
    var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    var image := Image.create_empty(edge, edge, false, Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF)
    for y in edge:
        for x in edge:
            image.set_pixel(x, y, Color(float(x) / edge, float(y) / edge, float(x ^ y) / edge, 1.0))
    var rd := GlobalShaderCompiler.get_rd()
    rd.texture_update(texture.rid, 0, image.get_data())
    return rd.texture_get_data(texture.rid, 0)


func _bytes(chunk: SaChunk) -> PackedByteArray:
    var texture: SaTexture = chunk.fields[SaFieldSpec.ALBEDO]
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)


func test_the_command_makes_a_double_resolution_layer_as_one_step() -> void:
    var surface := Fixtures.make_surface()
    var registries := Fixtures.make_registries(surface)
    var doc := surface.easel.document
    var before := _layers(doc).size()

    assert_true(registries.commands.has(&"layer_new_double"), "The command is registered")
    var words := registries.commands.get_descriptor(&"layer_new_double").label
    assert_eq(words, "New Layer at Double Resolution", "with the menu's words")
    assert_true(registries.commands.execute(&"layer_new_double"), "and runs")
    var layer := doc.active_layer
    assert_eq(_layers(doc).size(), before + 1, "One more layer exists")
    assert_eq(layer.resolution_scale, 2.0, "at twice the document's resolution")
    assert_eq(layer.get_or_create_chunk(Vector2i.ZERO).pixel_size(), 512, "and its first chunk is 512 across")

    assert_true(doc.undo(), "Undo takes it back")
    assert_eq(_layers(doc).size(), before, "and the stack is what it was")
    assert_true(doc.redo(), "Redo makes it again")
    assert_eq(doc.active_layer, layer, "the same layer")
    assert_eq(doc.active_layer.resolution_scale, 2.0, "still at 2.0")
    Fixtures.teardown(surface)


func test_the_layers_row_says_2x_and_a_plain_row_says_nothing() -> void:
    var surface := Fixtures.make_surface()
    var doc := surface.easel.document
    var plain := doc.active_layer
    var double := SaLayerOps.new(doc).add(&"", null, 2.0)

    var marked := SaLayerRowView.new("Boat", 0, false, 0, double)
    marked.refresh(doc)
    assert_true(marked.scale_mark.visible, "The double resolution layer's row shows its mark")
    assert_eq(marked.scale_mark.text, "2x", "and it reads 2x")

    var unmarked := SaLayerRowView.new("Lake", 0, false, 1, plain)
    unmarked.refresh(doc)
    assert_false(unmarked.scale_mark.visible, "A layer at the document's resolution shows none")
    marked.free()
    unmarked.free()
    Fixtures.teardown(surface)


func test_a_duplicate_keeps_the_scale() -> void:
    var surface := Fixtures.make_surface()
    var doc := surface.easel.document
    var double := SaLayerOps.new(doc).add(&"", null, 2.0)
    var pattern := _paint_pattern(double.get_or_create_chunk(Vector2i.ZERO))

    var copy := SaLayerOps.new(doc).duplicate(double)
    assert_eq(copy.resolution_scale, 2.0, "The copy is at 2.0")
    assert_eq(copy.chunks[Vector2i.ZERO].pixel_size(), 512, "its copied chunk is 512 across")
    assert_true(_bytes(copy.chunks[Vector2i.ZERO]) == pattern, "and holds the source's texels")
    assert_eq(copy.get_or_create_chunk(Vector2i(0, 1)).pixel_size(), 512, "and a chunk made on it later is too")
    Fixtures.teardown(surface)


func test_a_saved_double_resolution_layer_opens_the_same() -> void:
    var surface := Fixtures.make_surface(Vector2i(512, 256))
    var doc := surface.easel.document
    var double := SaLayerOps.new(doc).add(&"", null, 2.0)
    double.name = "Boat"
    var patterns := {}
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0)]:
        patterns[grid_pos] = _paint_pattern(double.get_or_create_chunk(grid_pos))
    assert_eq(SaExport.save_sad(doc, scratch_saved), OK, "The document saves")

    var loaded := SaDocument.new()
    assert_eq(SaExport.load_sad(loaded, scratch_saved, SaCompositor.new()), OK, "and opens")
    var found: SaLayer = null
    for layer: SaLayer in _layers(loaded):
        if str(layer.name) == "Boat":
            found = layer
        else:
            assert_eq(layer.resolution_scale, 1.0, "%s stays at 1.0" % layer.name)
    assert_not_null(found, "The double resolution layer is there")
    assert_eq(found.resolution_scale, 2.0, "at 2.0")
    assert_eq(found.chunks.size(), 2, "with both its chunks")
    for grid_pos: Vector2i in patterns:
        var chunk: SaChunk = found.chunks[grid_pos]
        assert_eq(chunk.resolution_scale, 2.0, "chunk %s at 2.0" % grid_pos)
        assert_eq(chunk.pixel_size(), 512, "and 512 across")
        assert_true(_bytes(chunk) == patterns[grid_pos], "chunk %s holds exactly the texels saved" % grid_pos)
    var later := found.get_or_create_chunk(Vector2i(0, 5))
    assert_eq(later.pixel_size(), 512, "A chunk made after the load is at 2.0 too")

    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_saved))
    loaded.free()
    Fixtures.teardown(surface)


func test_a_file_from_before_the_scale_opens_at_one() -> void:
    var loaded := SaDocument.new()
    assert_eq(SaExport.load_sad(loaded, ProjectSettings.globalize_path(OLD_FILE), SaCompositor.new()), OK, "The old file opens")
    var layers := _layers(loaded)
    assert_false(layers.is_empty(), "with its layers")
    for layer: SaLayer in layers:
        assert_eq(layer.resolution_scale, 1.0, "%s is at 1.0" % layer.name)
        for grid_pos: Vector2i in layer.chunks:
            var edge := layer.chunks[grid_pos].pixel_size()
            assert_eq(edge, SaChunk.SIZE, "and its chunk %s is %d across" % [grid_pos, SaChunk.SIZE])
    loaded.free()
