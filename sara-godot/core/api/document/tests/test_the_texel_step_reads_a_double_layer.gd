## The `texel` step reads a layer at 2.0 a texel for a pixel.
##
## The probe found the texel under a document point with the layer's 256 as
## though every chunk held 256 texels, so on a double layer it read the texel
## of the point halfway to the chunk's corner. These cases put a dot on a layer
## at a scale, texel for texel, and hold the `layer` column to the dot, to the
## composite's colour at the same point, and to nothing a chunk's width away.
##
## The dot is written into the chunk's texels rather than stamped, because the
## question is where the probe reads and not what the brush writes, which is
## the stamp brush module's suite.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const TexelProbe = preload("res://harness/report/sa_texel_probe.gd")

## Needs a RenderingDevice, because the answer is a texel read back.
const REQUIRES_GPU := true

## Two chunks wide, so a chunk's width to the right is still on the canvas.
const CANVAS := Vector2i(512, 256)

## The dot, in document pixels, inside chunk 0, 0.
const DOT := Rect2i(100, 100, 2, 2)

const RED := Color(0.9, 0.1, 0.1, 1.0)

var _surface: SaSurface = null
var _canvas: SaCanvas = null


func after_each() -> void:
    if _canvas != null:
        _canvas.free()
    _canvas = null
    if _surface != null:
        Fixtures.teardown(_surface)
    _surface = null


## A fresh document whose active layer is a new one at *scale*, both of its
## chunks allocated and clear, with the dot written into the first.
func _open(scale: float) -> SaLayer:
    _surface = Fixtures.make_surface(CANVAS)
    _canvas = SaCanvas.new()
    _canvas.easel = _surface.easel
    var layer := SaLayerOps.new(_surface.get_document()).add(&"", null, scale)
    layer.get_or_create_chunk(Vector2i(1, 0)).clear(Color(0, 0, 0, 0))
    var chunk := layer.get_or_create_chunk(Vector2i.ZERO)
    chunk.clear(Color(0, 0, 0, 0))
    var texture := chunk.albedo()
    var edge := chunk.pixel_size()
    var rd := GlobalShaderCompiler.get_rd()
    var image := Image.create_from_data(edge, edge, false, _image_format(texture), rd.texture_get_data(texture.rid, 0))
    var per_pixel := float(edge) / float(SaChunk.SIZE)
    var from := (Vector2(DOT.position) * per_pixel).floor()
    var span := (Vector2(DOT.size) * per_pixel).ceil()
    image.fill_rect(Rect2i(Vector2i(from), Vector2i(span)), RED)
    rd.texture_update(texture.rid, 0, image.get_data())
    _surface.get_document().invalidate_chunks([Vector2i.ZERO])
    # The picture the `composited` column reads, the way the compositing suite asks for
    # it, since no frame runs here to composite it.
    _surface.get_document().update_caches()
    _surface.easel.request_full_composite()
    _surface.easel.process_pending_composite()
    return layer


static func _image_format(texture: SaTexture) -> Image.Format:
    return Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF


func _read(at: Vector2i) -> Dictionary:
    return TexelProbe._read_point(_surface.get_document(), _canvas, at)


static func _rgba(answer: Variant) -> Color:
    if answer == null:
        return Color(-1, -1, -1, -1)
    return Color(answer["r"], answer["g"], answer["b"], answer["a"])


## The case that matters: the dot on a layer at 2.0 reads its own colour, which is
## the composite's there, and a chunk's width away reads nothing.
func test_on_a_double_layer_the_column_under_the_dot_is_the_composite() -> void:
    var layer := _open(2.0)
    assert_eq(layer.chunks[Vector2i.ZERO].pixel_size(), 512, "The layer is at 2.0, 512 texels to a chunk")
    for at: Vector2i in [DOT.position, DOT.end - Vector2i.ONE]:
        var out := _read(at)
        var own := _rgba(out["layer"])
        assert_true(own.is_equal_approx(RED), "The layer column at %s is the dot, %s" % [at, own])
        var shown := _rgba(out["composited"])
        assert_true(own.is_equal_approx(shown), "and the composite's colour there, %s against %s" % [own, shown])
    var away := _read(DOT.position + Vector2i(SaChunk.SIZE, 0))
    assert_almost_eq(_rgba(away["layer"]).a, 0.0, 0.001, "A chunk's width away the layer holds nothing")


## The point the probe used to read for the dot: at 2.0 the texel at 200, 200
## lies under the document pixel at 100, 100, so the pixel at 200, 200 read the
## dot once and reads nothing now.
func test_the_point_twice_as_far_out_no_longer_reads_the_dot() -> void:
    _open(2.0)
    var out := _read(DOT.position * 2)
    assert_almost_eq(_rgba(out["layer"]).a, 0.0, 0.001, "The pixel at twice the dot's offset is clear")
    var edge := _read(DOT.end)
    assert_almost_eq(_rgba(edge["layer"]).a, 0.0, 0.001, "and so is the pixel just past the dot")


## At 1.0 the arithmetic is the old one, a texel for a pixel.
func test_on_a_plain_layer_the_dot_reads_the_same() -> void:
    _open(1.0)
    var own := _rgba(_read(DOT.position)["layer"])
    assert_true(own.is_equal_approx(RED), "The dot at 1.0, %s" % own)
    assert_almost_eq(_rgba(_read(DOT.end)["layer"]).a, 0.0, 0.001, "and nothing past it")


## A layer at 0.5 holds a texel for four pixels, and the dot's texel is under
## each of them.
func test_on_a_half_layer_every_pixel_of_the_texel_reads_it() -> void:
    _open(0.5)
    for at: Vector2i in [DOT.position, DOT.position + Vector2i.ONE]:
        var own := _rgba(_read(at)["layer"])
        assert_true(own.is_equal_approx(RED), "The pixel at %s reads the dot's texel, %s" % [at, own])
    assert_almost_eq(_rgba(_read(DOT.end)["layer"]).a, 0.0, 0.001, "and the next texel is clear")


## A chunk whose texture is not the size its scale names cannot be placed,
## and the probe says so and names the scale rather than reading a guess.
func test_a_chunk_it_cannot_place_is_refused_by_its_scale() -> void:
    var layer := _open(2.0)
    var chunk: SaChunk = layer.chunks[Vector2i.ZERO]
    chunk.fields[SaFieldSpec.ALBEDO] = SaTexture.new(Vector2i(SaChunk.SIZE, SaChunk.SIZE), chunk.albedo().format)
    var out := _read(DOT.position)
    assert_eq(out["layer"], null, "No colour is answered")
    assert_true(String(out.get("unplaced", "")).contains("2.0"), "and the refusal names the scale, %s" % out.get("unplaced"))
