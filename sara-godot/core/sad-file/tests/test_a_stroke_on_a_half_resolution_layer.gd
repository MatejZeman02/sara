## A `.sad` whose layer asks for
## half the document's resolution. Nothing paints or draws a chunk below 1.0,
## so the reader opens the layer at 1.0 and says so, each texel the file stored
## repeated over the document pixels it covered, so a stroke on it is a
## stroke on a plain layer and lands by document pixels.
extends "res://tests/test_framework.gd"

## Chunks are real textures, so this needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

static var scratch_saved: String = SaDataRoot.path("test_d19_half_resolution.sad")
const HALF_SIDE := 128


func _layers(doc: SaDocument) -> Array:
    return doc.get_children().filter(func(c: Node) -> bool: return c is SaLayer)


## The colour the test stores in the half resolution texel (*x*, *y*), one no
## two texels share.
func _texel_colour(x: int, y: int) -> Color:
    return Color(float(x) / HALF_SIDE, float(y) / HALF_SIDE, float(x ^ y) / HALF_SIDE, 1.0)


## *chunk*'s albedo read back as an image in its own format.
func _image(chunk: SaChunk) -> Image:
    var texture: SaTexture = chunk.fields[SaFieldSpec.ALBEDO]
    var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var edge := chunk.pixel_size()
    return Image.create_from_data(edge, edge, false, Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF, bytes)


## Saves a document whose layer "Half" is at 0.5 with one chunk at 0.5 holding
## `_texel_colour` in every texel, the file a hand or an old build could write.
func _save_half_file() -> void:
    var surface := Fixtures.make_surface(Vector2i(512, 256))
    var doc := surface.easel.document
    var layer := SaLayerOps.new(doc).add(&"", null, 0.5)
    layer.name = "Half"
    var chunk := layer.get_or_create_chunk(Vector2i(1, 0))
    assert_eq(chunk.pixel_size(), HALF_SIDE, "The file's chunk is stored 128 across")
    var texture: SaTexture = chunk.fields[SaFieldSpec.ALBEDO]
    var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    var image := Image.create_empty(HALF_SIDE, HALF_SIDE, false, Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF)
    for y in HALF_SIDE:
        for x in HALF_SIDE:
            image.set_pixel(x, y, _texel_colour(x, y))
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
    assert_eq(SaExport.save_sad(doc, scratch_saved), OK, "The file saves")
    Fixtures.teardown(surface)


func _opened_half(loaded: SaDocument) -> SaLayer:
    for layer: SaLayer in _layers(loaded):
        if str(layer.name) == "Half":
            return layer
    return null


func test_a_half_resolution_layer_opens_at_one_and_says_so() -> void:
    _save_half_file()
    var warnings := SaErrorCatcher.new()
    var loaded := SaDocument.new()
    OS.add_logger(warnings)
    var opened := SaExport.load_sad(loaded, scratch_saved, SaCompositor.new())
    OS.remove_logger(warnings)
    assert_eq(opened, OK, "The file opens")
    var layer := _opened_half(loaded)
    assert_not_null(layer, "with its half resolution layer")
    assert_eq(layer.resolution_scale, 1.0, "opened at the document's resolution")
    var said := SaSadCoarseLayer.refusal("Half", 0.5)
    var caught := warnings.texts([SaErrorCatcher.WARNING])
    assert_true(caught.has(said), "and the refusal is said, naming the layer and the scale: %s" % said)

    var chunk: SaChunk = layer.chunks[Vector2i(1, 0)]
    assert_eq(chunk.resolution_scale, 1.0, "Its chunk is at 1.0")
    assert_eq(chunk.pixel_size(), SaChunk.SIZE, "and 256 across")
    var image := _image(chunk)
    for pixel: Vector2i in [Vector2i(0, 0), Vector2i(1, 1), Vector2i(2, 3), Vector2i(100, 37), Vector2i(255, 254)]:
        var expected := _texel_colour(floori(pixel.x / 2.0), floori(pixel.y / 2.0))
        var found := image.get_pixelv(pixel)
        var words := "Document pixel %s holds the texel that covered it, %s, not %s" % [pixel, expected, found]
        assert_true(found.is_equal_approx(expected), words)
    assert_eq(layer.get_or_create_chunk(Vector2i(0, 0)).pixel_size(), SaChunk.SIZE, "A chunk made later is 256 across too")

    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_saved))
    loaded.free()


func test_a_plain_or_double_scale_opens_as_asked_and_quietly() -> void:
    var warnings := SaErrorCatcher.new()
    OS.add_logger(warnings)
    assert_eq(SaSadCoarseLayer.opened_scale("Plain", 1.0), 1.0, "A layer at 1.0 opens at 1.0")
    assert_eq(SaSadCoarseLayer.opened_scale("Double", 2.0), 2.0, "one at 2.0 at 2.0")
    assert_eq(SaSadCoarseLayer.opened_scale("Huge", 8.0), 2.0, "one above 2.0 at 2.0, as before")
    OS.remove_logger(warnings)
    assert_true(warnings.texts([SaErrorCatcher.WARNING]).is_empty(), "and none of them says a word")
    var bytes := PackedByteArray([1, 2, 3, 4])
    assert_true(SaSadCoarseLayer.widened(bytes, 1.0) == bytes, "Bytes at 1.0 go through as they are")
    assert_true(SaSadCoarseLayer.widened(bytes, 2.0) == bytes, "and at 2.0")
