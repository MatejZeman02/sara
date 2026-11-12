## Cropping, growing the canvas and
## resampling the image all work on a document that holds a double resolution
## layer, and the layer stays at twice the resolution through them.
##
## Two layers carry the same picture. The plain one holds, at every document
## pixel, that pixel's own coordinates in red and green, and the double one
## holds the same value in each of the two by two texels over that pixel. After
## any of the three passes the double layer's texels at twice a pixel's
## position, and the three beside them, must read what the plain layer reads at
## that pixel, which is "its texels where the first one's are, scaled by two".
## The coordinates are small integers, which a half float holds exactly.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

var _easel: SaEasel = null
var _doc: SaDocument = null
var _plain: SaLayer = null
var _double: SaLayer = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(400, 300))
    _doc = _easel.document
    var ops := SaLayerOps.new(_doc)
    _plain = ops.add()
    _double = ops.add(&"", null, 2.0)


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _plain = null
    _double = null


## Writes the picture into both layers, every pixel coordinate divided by
## *block*, so a block of four survives a halving that nearest picks from.
func _paint(block: int = 1) -> void:
    for layer: SaLayer in [_plain, _double]:
        var scale := int(layer.resolution_scale)
        for grid_pos: Vector2i in SaLayer.grid_positions(_doc.canvas_size):
            var chunk := layer.get_or_create_chunk(grid_pos)
            var texture: SaTexture = chunk.fields[SaFieldSpec.ALBEDO]
            var edge := chunk.pixel_size()
            var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
            var image := Image.create_empty(edge, edge, false, Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF)
            var origin := grid_pos * SaLayer.CHUNK_SIZE
            for y in edge:
                for x in edge:
                    @warning_ignore("integer_division")
                    var pixel := origin + Vector2i(x / scale, y / scale)
                    image.set_pixel(x, y, _value(pixel, block))
            GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())


func _value(pixel: Vector2i, block: int) -> Color:
    return Color(floori(float(pixel.x) / block), floori(float(pixel.y) / block), 0.5, 1.0)


## One texel of *layer* at *texel*, in the layer's own texels, with the bytes of
## every chunk read once per *cache*.
func _read(layer: SaLayer, texel: Vector2i, cache: Dictionary) -> Color:
    var edge := roundi(SaLayer.CHUNK_SIZE * layer.resolution_scale)
    var grid := Vector2i(floori(float(texel.x) / edge), floori(float(texel.y) / edge))
    var key := [layer, grid]
    if not cache.has(key):
        var field := layer.get_field(grid)
        cache[key] = [] if field == null else [field, GlobalShaderCompiler.get_rd().texture_get_data(field.rid, 0)]
    var found: Array = cache[key]
    if found.is_empty():
        return Color.TRANSPARENT
    var texture: SaTexture = found[0]
    var local := texel - grid * edge
    return SaFieldSpec.decode_texel(found[1], texture.format, local.y * texture.size.x + local.x)


## Every chunk of the double layer is 512 across, and at pixels spread over the
## canvas, odd ones and those beside chunk seams among them, its four texels
## read what the plain layer reads. Answers how many pixels disagreed.
func _mismatches(label: String) -> int:
    assert_eq(_double.resolution_scale, 2.0, "%s: the layer is still at 2.0" % label)
    for grid_pos: Vector2i in _double.chunks:
        assert_eq(_double.chunks[grid_pos].pixel_size(), 512, "%s: chunk %s is 512 across" % [label, grid_pos])
    var cache := {}
    var wrong := 0
    var size := _doc.canvas_size
    var xs := [0, 1, 37, 127, 128, 255, 256, 257, size.x >> 1, size.x - 2, size.x - 1]
    var ys := [0, 1, 45, 199, 255, 256, 257, size.y >> 1, size.y - 2, size.y - 1]
    for y: int in ys:
        for x: int in xs:
            if x >= size.x or y >= size.y:
                continue
            var want := _read(_plain, Vector2i(x, y), cache)
            for step: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
                var got := _read(_double, Vector2i(x, y) * 2 + step, cache)
                if not got.is_equal_approx(want):
                    if wrong == 0:
                        print("  %s: first mismatch at pixel (%d, %d): plain %s, double %s" % [label, x, y, want, got])
                    wrong += 1
    return wrong


## The plain layer reads *pixel* at *at*, so a test says where the picture went
## as well as that the two layers agree.
func _plain_reads(at: Vector2i, pixel: Vector2i, label: String) -> void:
    var got := _read(_plain, at, {})
    assert_almost_eq(got.r, float(pixel.x), 1e-3, "%s: x" % label)
    assert_almost_eq(got.g, float(pixel.y), 1e-3, "%s: y" % label)


func _undo_takes_it_back(label: String) -> void:
    assert_true(_doc.undo(), "%s: one undo" % label)
    assert_eq(_doc.canvas_size, Vector2i(400, 300), "%s: puts the size back" % label)
    _plain_reads(Vector2i(301, 203), Vector2i(301, 203), "%s: and the picture" % label)
    assert_eq(_mismatches("%s undone" % label), 0, "%s: with the double layer's texels whole" % label)


func test_the_picture_is_the_same_on_both_layers_before_any_pass() -> void:
    _paint()
    _plain_reads(Vector2i(301, 203), Vector2i(301, 203), "The plain layer holds its coordinates")
    assert_eq(_mismatches("painted"), 0, "and the double layer the same, two by two")


func test_a_crop_at_an_odd_offset_moves_whole_texels() -> void:
    _paint()
    assert_true(SaCrop.new(_doc).crop_to(Rect2i(37, 45, 301, 203)), "The crop happens")
    assert_eq(_doc.canvas_size, Vector2i(301, 203), "and the document is the rectangle")
    _plain_reads(Vector2i(0, 0), Vector2i(37, 45), "The old (37, 45) is the new origin")
    _plain_reads(Vector2i(250, 200), Vector2i(287, 245), "and a pixel past the old seam moved with it")
    assert_eq(_mismatches("cropped"), 0, "The double layer's texels went where the plain layer's did, scaled by two")
    _undo_takes_it_back("The crop")


func test_crop_to_a_selection_takes_the_double_layer_along() -> void:
    _paint()
    _doc.selection.select_rect(Rect2i(129, 3, 261, 259))
    assert_true(SaCrop.new(_doc).crop_to_selection(), "Crop to Selection happens")
    assert_eq(_doc.canvas_size, Vector2i(261, 259), "at the selection's bounds")
    _plain_reads(Vector2i(0, 0), Vector2i(129, 3), "The selection's corner is the new origin")
    assert_eq(_mismatches("cropped to the selection"), 0, "and the double layer agrees")
    _undo_takes_it_back("Crop to Selection")


func test_growing_the_canvas_keeps_the_double_layer_in_place() -> void:
    _paint()
    # Centred, so the old picture lands at (57, 31), odd on both axes.
    assert_true(SaCrop.new(_doc).resize_to(Vector2i(515, 363), Vector2i(1, 1)), "Canvas Size happens")
    assert_eq(_doc.canvas_size, Vector2i(515, 363), "and the document grew")
    _plain_reads(Vector2i(57, 31), Vector2i(0, 0), "The old origin sits at the offset")
    assert_eq(_mismatches("grown"), 0, "and the double layer sits there too, empty where the plain one is")
    _undo_takes_it_back("Canvas Size")


func test_clear_outside_clears_the_double_layer_at_the_new_edge() -> void:
    _paint()
    assert_true(SaCrop.new(_doc).crop_to(Rect2i(0, 0, 301, 203), true), "The crop with Clear Outside happens")
    var cache := {}
    assert_almost_eq(_read(_double, Vector2i(601, 100), cache).a, 1.0, 1e-4, "The last texel inside keeps its paint")
    assert_almost_eq(_read(_double, Vector2i(602, 100), cache).a, 0.0, 1e-4, "and the first past the edge is cleared")
    assert_almost_eq(_read(_double, Vector2i(100, 406), cache).a, 0.0, 1e-4, "below it as well")
    assert_eq(_mismatches("cleared"), 0, "and inside the double layer agrees with the plain one")


func test_doubling_the_image_scales_the_double_layer_at_its_own_density() -> void:
    _paint()
    var resample := SaResample.new(_doc)
    resample.filter = SaResampleKernel.Filter.NEAREST
    assert_true(resample.resample_to(Vector2i(800, 600)), "Image Size happens")
    _plain_reads(Vector2i(603, 407), Vector2i(301, 203), "The plain layer's pixel doubled")
    assert_eq(_mismatches("doubled"), 0, "and the double layer's texels doubled with it")
    _undo_takes_it_back("Image Size")


func test_halving_the_image_keeps_the_double_layer_at_two() -> void:
    _paint(4)
    var resample := SaResample.new(_doc)
    resample.filter = SaResampleKernel.Filter.NEAREST
    assert_true(resample.resample_to(Vector2i(200, 150)), "Image Size happens")
    assert_eq(_mismatches("halved"), 0, "The double layer's texels land where the plain layer's do")
    assert_true(_doc.undo(), "One undo")
    assert_eq(_doc.canvas_size, Vector2i(400, 300), "puts the size back")


func test_a_bilinear_resample_keeps_the_double_layer_at_two() -> void:
    _paint()
    assert_true(SaResample.new(_doc).resample_to(Vector2i(600, 450)), "A bilinear Image Size happens")
    var cache := {}
    # A bilinear read of a picture that is linear in each coordinate is the
    # picture, so away from the edges both layers read the old coordinate the
    # new pixel came from, give or take the half texel their densities differ by.
    var plain := _read(_plain, Vector2i(300, 225), cache)
    var double := _read(_double, Vector2i(600, 450), cache)
    assert_almost_eq(plain.r, 200.0, 1.0, "The plain layer's centre came from the old centre")
    assert_almost_eq(double.r, 200.0, 1.0, "and so did the double layer's")
    assert_eq(_double.resolution_scale, 2.0, "which is still at 2.0")
    for grid_pos: Vector2i in _double.chunks:
        assert_eq(_double.chunks[grid_pos].pixel_size(), 512, "with every chunk 512 across")
