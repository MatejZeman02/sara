## A brush stroke on a half precision document stores its
## colour twice, a dab into the stroke buffer and the commit into the layer, and
## some GPUs narrow a store into a half by truncating towards zero, so a glaze
## of low opacity stalled short of its colour. Each of those stores now rounds
## the float to a half itself, stochastically, drawn from the stroke's seed, the
## dab's and the texel, and stores a number the half holds exactly.
##
## The glaze is the research session's: a 512 by 512 Oklab document over Display
## P3, a disc of `#203048`, then strokes of `#f0d060` at opacity 0.02, read at
## the layer's texel at the disc's centre. One dab a stroke, so the opacity is
## the share each stroke moves the texel by and no stroke's dabs overlap.
extends "res://tests/test_framework.gd"

## The strokes dispatch real dabs and commits, and the suite reads the texels back.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

const SIZE := Vector2i(512, 512)
const CENTRE := Vector2(256.0, 256.0)
const DISC := Color("#203048")
const GLAZE := Color("#f0d060")
const GLAZE_OPACITY := 0.02
const STROKES := 400
## The disc's radius and the glaze's, in document pixels. The glaze is a little
## smaller so every stroke lands on the disc.
const DISC_RADIUS := 80.0
const GLAZE_RADIUS := 40.0
## How near the half precision glaze's lightness comes to the full one's.
const L_TOLERANCE := 0.001

## The SHA-256 of a full precision document's glaze, the layer's chunk under
## the centre after the disc and 400 strokes, taken at the tip
## changed a kernel. A full precision store is left as it was, so it holds.
const FULL_PRECISION_GLAZE_SHA256 := "ac4e9f5ed116204663f952cd7088a4bb9981eff5a09774ece96c9a4b114d1b70"

## Every stroke's seed is this plus its index, so the run is the same on every
## machine and no two strokes draw alike.
const SEED_BASE := 241000

## Every surface a test made, torn down after it.
var _surfaces: Array[SaSurface] = []


func after_each() -> void:
    for surface in _surfaces:
        Fixtures.teardown(surface)
    _surfaces.clear()


## A fresh document of *depth* on a surface of its own.
func _surface(depth: SaColorSpace.Depth) -> SaSurface:
    var easel := SaEasel.create_default(SIZE, null, SaColorSpace.oklab_p3().with_depth(depth))
    var surface := SaSurface.create(&"probe", easel, Fixtures.FakeView.new())
    _surfaces.append(surface)
    return surface


func _brush(surface: SaSurface, colour: Color, radius: float, opacity: float) -> Object:
    var brush: Object = StateBrushScript.new()
    brush.surface = surface
    brush.settings.color = colour
    brush.settings.radius = radius / float(mini(SIZE.x, SIZE.y))
    brush.settings.hardness = GammaFloat.new(1.0, 1.0)
    brush.settings.opacity = opacity
    brush.settings.opacity_by_pressure = false
    return brush


func _button(brush: Object, pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    brush.handle_input(event)
    if pressed:
        var motion := InputEventMouseMotion.new()
        motion.button_mask = MOUSE_BUTTON_MASK_LEFT
        motion.pressure = 1.0
        brush.handle_input(motion)


## One dab at the centre, pressed and released, under *seed*. *between* runs
## after the press and before the release, while the stroke buffer holds the dab.
func _dab(brush: Object, seed_value: int, between: Callable = Callable()) -> void:
    brush.stroke_seed = seed_value
    brush.surface.view.mouse_position = CENTRE
    _button(brush, true)
    if between.is_valid():
        between.call()
    _button(brush, false)


func _chunk_bytes(layer: SaLayer) -> PackedByteArray:
    var side := 256
    for grid: Vector2i in layer.chunks:
        side = (layer.chunks[grid] as SaChunk).pixel_size()
        break
    var here := Vector2i(floori(CENTRE.x / side), floori(CENTRE.y / side))
    if not layer.chunks.has(here):
        return PackedByteArray()
    return GlobalShaderCompiler.get_rd().texture_get_data(layer.get_field(here).rid, 0)


func _centre_texel(layer: SaLayer) -> Color:
    var side := 256
    for grid: Vector2i in layer.chunks:
        side = (layer.chunks[grid] as SaChunk).pixel_size()
        break
    var here := Vector2i(floori(CENTRE.x / side), floori(CENTRE.y / side))
    @warning_ignore("static_called_on_instance")
    var image: Image = SaExport.get_texture_image_float(layer.get_field(here))
    return image.get_pixelv(Vector2i(CENTRE) - here * side)


## The disc and *strokes* glaze strokes on a fresh document of *depth*.
func _glazed(depth: SaColorSpace.Depth, strokes: int) -> SaSurface:
    var surface := _surface(depth)
    _dab(_brush(surface, DISC, DISC_RADIUS, 1.0), SEED_BASE - 1)
    var glaze := _brush(surface, GLAZE, GLAZE_RADIUS, GLAZE_OPACITY)
    for i in strokes:
        _dab(glaze, SEED_BASE + i)
    return surface


func test_a_half_precision_glaze_reaches_the_full_precision_one() -> void:
    var full := _centre_texel(_glazed(SaColorSpace.Depth.F32, STROKES).easel.document.active_layer)
    var half := _centre_texel(_glazed(SaColorSpace.Depth.F16, STROKES).easel.document.active_layer)
    print("glaze L at %d strokes: full %.5f, half %.5f" % [STROKES, full.r, half.r])
    assert_true(full.a > 0.99, "The disc and the glaze cover the centre, alpha %.4f" % full.a)
    assert_almost_eq(half.r, full.r, L_TOLERANCE, "The half glaze reads L %.5f against the full one's %.5f" % [half.r, full.r])


func test_a_full_precision_glaze_paints_the_bytes_it_painted_before() -> void:
    var bytes := _chunk_bytes(_glazed(SaColorSpace.Depth.F32, STROKES).easel.document.active_layer)
    var context := HashingContext.new()
    context.start(HashingContext.HASH_SHA256)
    context.update(bytes)
    var digest := context.finish().hex_encode()
    print("full precision glaze sha256 %s" % digest)
    assert_eq(digest, FULL_PRECISION_GLAZE_SHA256, "A full precision glaze is the bytes it was before the rounding")


func test_one_stroke_painted_twice_from_one_state_is_the_same_bytes() -> void:
    var buffers: Array[PackedByteArray] = []
    var layers: Array[PackedByteArray] = []
    for run in 2:
        var surface := _glazed(SaColorSpace.Depth.F16, 3)
        var glaze := _brush(surface, GLAZE, GLAZE_RADIUS, GLAZE_OPACITY)
        var document := surface.easel.document
        _dab(glaze, SEED_BASE + 7, func() -> void: buffers.append(_chunk_bytes(document.stroke_layer)))
        layers.append(_chunk_bytes(document.active_layer))
    assert_false(buffers[0].is_empty(), "The stroke buffer holds the dab before the release")
    assert_true(buffers[0] == buffers[1], "The stroke buffer is the same bytes both times")
    assert_true(layers[0] == layers[1], "and so is the layer after the commit")
