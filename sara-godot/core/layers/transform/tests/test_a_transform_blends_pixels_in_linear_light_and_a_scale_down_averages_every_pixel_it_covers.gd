## A transform blends pixels in linear light, and a scale down averages every
## pixel it covers, through each of the three ways a picture is scaled: the
## transform tool's resample, a layer's live transform and Image > Scale.
##
## A one pixel black and white checker scaled to half on an sRGB document is
## half the light, linear 0.5, which the sRGB curve encodes as about 0.735. A
## blend of the stored values read 0.5, which is a fifth of the light. One
## pixel white lines every four pixels on black, scaled to a quarter, are a
## quarter of the white wherever a new pixel falls, where four taps of a
## bilinear read land between the lines and read black. A linear document holds
## the light itself and reads the same light. Nearest keeps to the source's own
## values. A soft edged opaque disc on transparency keeps its colour at its
## edge, the premultiplied blend that keeps a dark rim off it.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

## One step of eight bits, the tolerance the row asks for.
const STEP := 1.0 / 255.0
## Linear 0.5 through the sRGB curve.
const HALF_LIGHT_SRGB := 0.735357
## Linear 0.25 through the sRGB curve.
const QUARTER_LIGHT_SRGB := 0.537099
## Half the light of white as Oklab's lightness, the cube root of a half. An
## average of the stored values would read 0.5.
const HALF_LIGHT_OKLAB := 0.793701
const DISC_COLOUR := Color(0.8, 0.4, 0.2, 1.0)
## The transform tool's document and the square it lifts, the chunk at (1, 1).
const TOOL_CANVAS := Vector2i(1024, 1024)
const LIFTED := Rect2i(256, 256, 256, 256)
## The live transform's and Image > Scale's document, every chunk painted.
const CANVAS := Vector2i(512, 512)

var _easel: SaEasel = null


func after_each() -> void:
    if _easel != null:
        _easel.free()
    _easel = null


# --- The patterns --------------------------------------------------------------


static func _checker(x: int, y: int) -> Color:
    return Color.WHITE if (x + y) % 2 == 0 else Color.BLACK


## White and black as an Oklab document stores them, (1, 0, 0) and nought.
static func _oklab_checker(x: int, y: int) -> Color:
    return Color(1.0, 0.0, 0.0, 1.0) if (x + y) % 2 == 0 else Color(0.0, 0.0, 0.0, 1.0)


static func _lines(x: int, _y: int) -> Color:
    return Color.WHITE if x % 4 == 0 else Color.BLACK


## An opaque disc of DISC_COLOUR whose alpha falls to nothing over its last
## twenty pixels, centred in the chunk at (1, 1) and at the canvas's middle
## alike, since both are 384 or 256 from the origin in the cases below.
static func _disc_about(centre: Vector2) -> Callable:
    return func(x: int, y: int) -> Color:
        var r := Vector2(x + 0.5, y + 0.5).distance_to(centre)
        var alpha := clampf((110.0 - r) / 20.0, 0.0, 1.0)
        return Color(DISC_COLOUR.r, DISC_COLOUR.g, DISC_COLOUR.b, alpha) if alpha > 0.0 else Color(0, 0, 0, 0)


## Uploads *pattern*, a function of the document pixel, over *area* of
## *layer*'s chunks, whole chunks at a time since the brush is not what this
## suite is about.
static func _paint(layer: SaLayer, area: Rect2i, pattern: Callable) -> void:
    var side := SaLayer.CHUNK_SIZE
    var first := Vector2i(floori(float(area.position.x) / side), floori(float(area.position.y) / side))
    var last := Vector2i(ceili(float(area.end.x) / side), ceili(float(area.end.y) / side))
    for gy in range(first.y, last.y):
        for gx in range(first.x, last.x):
            var grid := Vector2i(gx, gy)
            var texture := layer.get_or_create_chunk(grid).albedo()
            var image := Image.create_empty(side, side, false, Image.FORMAT_RGBAF)
            for y in range(side):
                for x in range(side):
                    image.set_pixel(x, y, pattern.call(gx * side + x, gy * side + y))
            if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
                image.convert(Image.FORMAT_RGBAH)
            GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
            layer.mark_unresolved(grid)


## Every texel of *layer* over *area* of the document, row by row.
static func _texels(layer: SaLayer, area: Rect2i) -> Array[Color]:
    var side := SaLayer.CHUNK_SIZE
    var fields: Dictionary[Vector2i, SaTexture] = {}
    var bytes: Dictionary[Vector2i, PackedByteArray] = {}
    var found: Array[Color] = []
    for y in range(area.position.y, area.end.y):
        for x in range(area.position.x, area.end.x):
            var grid := Vector2i(floori(float(x) / side), floori(float(y) / side))
            if not fields.has(grid):
                fields[grid] = layer.get_field(grid)
                if fields[grid] != null:
                    bytes[grid] = GlobalShaderCompiler.get_rd().texture_get_data(fields[grid].rid, 0)
            var field := fields[grid]
            if field == null:
                found.append(Color(0, 0, 0, 0))
                continue
            var index := (y - grid.y * side) * side + (x - grid.x * side)
            found.append(SaFieldSpec.decode_texel(bytes[grid], field.format, index))
    return found


# --- The three ways of scaling -------------------------------------------------


## An easel of *size* in *space* with its background hidden, and its paint layer.
func _document(size: Vector2i, space: SaColorSpace) -> SaLayer:
    _easel = Bench.easel(size)
    _easel.document.color_space = space
    (_easel.document.get_node("Background") as SaLayer).visible = false
    return _easel.document.active_layer


## LIFTED of *pattern* scaled by *scale* about its centre with the transform
## tool, read where it lands, a square of LIFTED's size times *scale*.
func _through_the_tool(space: SaColorSpace, pattern: Callable, scale: float, nearest := false) -> Array[Color]:
    var layer := _document(TOOL_CANVAS, space)
    var doc := _easel.document
    _paint(layer, LIFTED, pattern)
    var pass_over := SaTransform.new(doc)
    if nearest:
        pass_over.filter = SaResampleKernel.Filter.NEAREST
    doc.selection.select_rect(LIFTED)
    pass_over.lift(layer, LIFTED)
    pass_over.preview_affine(Vector2i.ZERO, Vector2(scale, scale), 0.0)
    pass_over.tick()
    var side := int(LIFTED.size.x * scale)
    var half := int(side * 0.5)
    var corner := LIFTED.get_center() - Vector2i(half, half)
    var found := _texels(doc.stroke_layer, Rect2i(corner, Vector2i(side, side)))
    pass_over.cancel()
    return found


## The whole CANVAS of *pattern* drawn through a live transform that scales it
## by *scale* about the origin, read from the layer's cache.
func _through_the_live_transform(space: SaColorSpace, pattern: Callable, scale: float) -> Array[Color]:
    var layer := _document(CANVAS, space)
    _paint(layer, Rect2i(Vector2i.ZERO, CANVAS), pattern)
    Bench.composite(_easel)
    var map := SaLiveTransform.composed(Vector2.ZERO, 0.0, Vector2(scale, scale), Vector2.ZERO)
    assert_true(SaLiveTransform.put(_easel.document, layer, map), "The scale is put on the layer")
    Bench.composite(_easel)
    var side := int(CANVAS.x * scale)
    return _texels(SaLiveTransform.paint_of(layer), Rect2i(0, 0, side, side))


## The whole CANVAS of *pattern* through Image > Scale to *scale* of its size.
func _through_image_scale(space: SaColorSpace, pattern: Callable, scale: float, nearest := false) -> Array[Color]:
    var layer := _document(CANVAS, space)
    _paint(layer, Rect2i(Vector2i.ZERO, CANVAS), pattern)
    var pass_over := SaResample.new(_easel.document)
    if nearest:
        pass_over.filter = SaResampleKernel.Filter.NEAREST
    var side := int(CANVAS.x * scale)
    assert_true(pass_over.resample_to(Vector2i(side, side)), "Image > Scale ran")
    return _texels(layer, Rect2i(0, 0, side, side))


## The three ways, each as a function of the space, the pattern and the scale.
func _ways() -> Dictionary[String, Callable]:
    return {
        "the transform tool": _through_the_tool,
        "the live transform": _through_the_live_transform,
        "Image > Scale": _through_image_scale,
    }


## Asserts every one of *found* reads *expected* in its colour and is opaque,
## within STEP, naming the first that does not.
func _all_read(found: Array[Color], expected: float, what: String) -> void:
    var wrong := -1
    for i in range(found.size()):
        var c := found[i]
        var off := maxf(maxf(absf(c.r - expected), absf(c.g - expected)), maxf(absf(c.b - expected), absf(c.a - 1.0)))
        if off > STEP:
            wrong = i
            break
    assert_false(found.is_empty(), "%s reads something" % what)
    var seen := "" if wrong < 0 else ", not %s at %d" % [found[wrong], wrong]
    assert_eq(wrong, -1, "%s reads %.4f at every pixel%s" % [what, expected, seen])


static func _decode_srgb(c: float) -> float:
    return c / 12.92 if c < 0.04045 else pow((c + 0.055) / 1.055, 2.4)


# --- The suite -----------------------------------------------------------------


func test_a_checker_scaled_to_half_on_an_srgb_document_is_half_the_light() -> void:
    for way: String in _ways():
        var found: Array[Color] = _ways()[way].call(SaColorSpace.srgb(), _checker, 0.5)
        _all_read(found, HALF_LIGHT_SRGB, "The checker halved through %s" % way)
        after_each()


func test_lines_every_four_pixels_scaled_to_a_quarter_are_a_quarter_of_the_white_everywhere() -> void:
    for way: String in _ways():
        var found: Array[Color] = _ways()[way].call(SaColorSpace.srgb(), _lines, 0.25)
        _all_read(found, QUARTER_LIGHT_SRGB, "The lines quartered through %s" % way)
        var mean := 0.0
        for c: Color in found:
            mean += _decode_srgb(c.r)
        mean /= maxf(float(found.size()), 1.0)
        assert_almost_eq(mean, 0.25, STEP, "and their linear mean through %s is a quarter of the white" % way)
        after_each()


func test_a_checker_on_a_linear_document_reads_the_same_light() -> void:
    for way: String in _ways():
        var found: Array[Color] = _ways()[way].call(SaColorSpace.linear_srgb(), _checker, 0.5)
        _all_read(found, 0.5, "The checker halved on a linear document through %s" % way)
        after_each()


func test_a_checker_on_an_oklab_document_is_half_the_light_not_half_the_lightness() -> void:
    for way: String in _ways():
        var found: Array[Color] = _ways()[way].call(SaColorSpace.oklab(), _oklab_checker, 0.5)
        assert_false(found.is_empty(), "The Oklab checker halved through %s reads something" % way)
        var wrong := -1
        for i in range(found.size()):
            var c := found[i]
            var off := maxf(maxf(absf(c.r - HALF_LIGHT_OKLAB), absf(c.g)), maxf(absf(c.b), absf(c.a - 1.0)))
            if off > STEP:
                wrong = i
                break
        var seen := "" if wrong < 0 else ", not %s at %d" % [found[wrong], wrong]
        assert_eq(
            wrong, -1, "The Oklab checker halved through %s is a neutral grey of lightness %.4f%s" % [way, HALF_LIGHT_OKLAB, seen]
        )
        after_each()


func test_nearest_keeps_to_the_source_s_own_values() -> void:
    var ways: Dictionary[String, Callable] = {
        "the transform tool": _through_the_tool.bind(true),
        "Image > Scale": _through_image_scale.bind(true),
    }
    for way: String in ways:
        for scale: float in [0.5, 0.25]:
            var found: Array[Color] = ways[way].call(SaColorSpace.srgb(), _checker, scale)
            var foreign := -1
            for i in range(found.size()):
                var c := found[i]
                var grey := absf(c.r - c.g) < 1.0e-3 and absf(c.g - c.b) < 1.0e-3
                var own := grey and (absf(c.r) < 1.0e-3 or absf(c.r - 1.0) < 1.0e-3)
                if not own or absf(c.a - 1.0) > 1.0e-3:
                    foreign = i
                    break
            assert_false(found.is_empty(), "Nearest through %s at %s reads something" % [way, scale])
            assert_eq(foreign, -1, "and every pixel through %s at %s is black or white" % [way, scale])
            after_each()


func test_a_soft_disc_scaled_down_keeps_its_colour_at_its_edge() -> void:
    var centres: Dictionary[String, Vector2] = {
        "the transform tool": Vector2(LIFTED.get_center()),
        "the live transform": Vector2(CANVAS) * 0.5,
        "Image > Scale": Vector2(CANVAS) * 0.5,
    }
    for way: String in _ways():
        for scale: float in [0.5, 0.25]:
            var found: Array[Color] = _ways()[way].call(SaColorSpace.srgb(), _disc_about(centres[way]), scale)
            var edge := 0
            var darker := -1
            for i in range(found.size()):
                var c := found[i]
                if c.a <= 0.0:
                    continue
                if c.a < 1.0:
                    edge += 1
                if c.r < DISC_COLOUR.r - STEP or c.g < DISC_COLOUR.g - STEP or c.b < DISC_COLOUR.b - STEP:
                    darker = i
                    break
            assert_true(edge > 0, "The disc through %s at %s has a soft edge" % [way, scale])
            var seen := "" if darker < 0 else ", %s is" % found[darker]
            assert_eq(darker, -1, "and no pixel of it is darker than its colour%s" % seen)
            after_each()
