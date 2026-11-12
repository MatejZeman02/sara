## A brush's commit into a half precision layer rounds
## stochastically in Normal, Erase and Alpha Lock, and every other blend mode
## must too rather than committing through `composite.gmacs` and truncating. Every mode of
## `composite.gmacs` now has a twin in `stroke_commit.gmacs` that runs the same
## formula, kept once in `libs/composite_blend_modes.gmacs`, and rounds its store.
##
## The glaze is: a 512 by 512 Oklab document over Display P3, a disc of
## `#203048` in Normal, then strokes of `#f0d060` at opacity 0.02, here in
## Multiply and in Overlay, read at the layer's texel at the disc's centre. The
## noise brush's glaze is the same in Normal.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

## The strokes dispatch real dabs and commits, and the suite reads the texels back.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")

const SIZE := Vector2i(512, 512)
const CENTRE := Vector2(256.0, 256.0)
const DISC := Color("#203048")
const GLAZE := Color("#f0d060")
const GLAZE_OPACITY := 0.02
const STROKES := 400
const DISC_RADIUS := 80.0
const GLAZE_RADIUS := 40.0
## How near the half precision glaze's lightness comes to the full one's.
const L_TOLERANCE := 0.001

## The hash of a full precision Normal glaze, which this suite must not move.
const FULL_PRECISION_GLAZE_SHA256 := "ac4e9f5ed116204663f952cd7088a4bb9981eff5a09774ece96c9a4b114d1b70"

## Every stroke's seed is this plus its index. The base keeps the hash stable.
const SEED_BASE := 241000

var _surfaces: Array[SaSurface] = []
## The app's blend modes, which a bare easel's compositor lacks, so Multiply and
## Overlay are what the commit runs rather than Normal by fallback.
var _registries: SaRegistries = Fixtures.make_registries()


func after_each() -> void:
    for surface in _surfaces:
        Fixtures.teardown(surface)
    _surfaces.clear()


func _surface(depth: SaColorSpace.Depth) -> SaSurface:
    var easel := SaEasel.create_default(SIZE, null, SaColorSpace.oklab_p3().with_depth(depth))
    easel.compositor.set_registry(_registries.blend_modes)
    var surface := SaSurface.create(&"probe", easel, Fixtures.FakeView.new())
    _surfaces.append(surface)
    return surface


func _brush(surface: SaSurface, colour: Color, radius: float, opacity: float, mode: StringName) -> Object:
    var brush: Object = StateBrushScript.new()
    brush.surface = surface
    brush.settings.color = colour
    brush.settings.radius = radius / float(mini(SIZE.x, SIZE.y))
    brush.settings.hardness = GammaFloat.new(1.0, 1.0)
    brush.settings.opacity = opacity
    brush.settings.opacity_by_pressure = false
    brush.settings.blend_mode = mode
    return brush


## A noise brush with no grain, thickness or push, so its glaze is a plain
## colour laid through its own dab kernel and its own rounded store.
func _noise_brush(surface: SaSurface, colour: Color, radius: float, opacity: float) -> Object:
    var brush: Object = StateNoiseBrushScript.new()
    brush.surface = surface
    brush.settings.color = colour
    brush.settings.radius = radius / float(mini(SIZE.x, SIZE.y))
    brush.settings.hardness = 1.0
    brush.settings.opacity = opacity
    brush.settings.strength = 0.0
    brush.settings.thickness = 0.0
    brush.settings.push_colour_below = false
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


func _dab(brush: Object, seed_value: int) -> void:
    brush.stroke_seed = seed_value
    brush.surface.view.mouse_position = CENTRE
    _button(brush, true)
    _button(brush, false)


func _centre_chunk(layer: SaLayer) -> Vector2i:
    var side := 256
    for grid: Vector2i in layer.chunks:
        side = (layer.chunks[grid] as SaChunk).pixel_size()
        break
    return Vector2i(floori(CENTRE.x / side), floori(CENTRE.y / side))


func _chunk_bytes(layer: SaLayer) -> PackedByteArray:
    var here := _centre_chunk(layer)
    if not layer.chunks.has(here):
        return PackedByteArray()
    return GlobalShaderCompiler.get_rd().texture_get_data(layer.get_field(here).rid, 0)


func _centre_texel(layer: SaLayer) -> Color:
    var here := _centre_chunk(layer)
    var side := (layer.chunks[here] as SaChunk).pixel_size()
    @warning_ignore("static_called_on_instance")
    var image: Image = SaExport.get_texture_image_float(layer.get_field(here))
    return image.get_pixelv(Vector2i(CENTRE) - here * side)


## The disc, then *strokes* glaze strokes from *make_glaze*, on a fresh document.
func _glazed(depth: SaColorSpace.Depth, strokes: int, make_glaze: Callable) -> SaSurface:
    var surface := _surface(depth)
    _dab(_brush(surface, DISC, DISC_RADIUS, 1.0, SaLayer.BLEND_MODE.NORMAL), SEED_BASE - 1)
    var glaze: Object = make_glaze.call(surface)
    for i in strokes:
        _dab(glaze, SEED_BASE + i)
    return surface


func _stamp_glaze(mode: StringName) -> Callable:
    return func(surface: SaSurface) -> Object: return _brush(surface, GLAZE, GLAZE_RADIUS, GLAZE_OPACITY, mode)


func _noise_glaze() -> Callable:
    return func(surface: SaSurface) -> Object: return _noise_brush(surface, GLAZE, GLAZE_RADIUS, GLAZE_OPACITY)


func _assert_glaze_holds(label: String, make_glaze: Callable) -> void:
    var full := _centre_texel(_glazed(SaColorSpace.Depth.F32, STROKES, make_glaze).easel.document.active_layer)
    var half := _centre_texel(_glazed(SaColorSpace.Depth.F16, STROKES, make_glaze).easel.document.active_layer)
    print("%s glaze L at %d strokes: full %.5f, half %.5f" % [label, STROKES, full.r, half.r])
    assert_true(full.a > 0.99, "%s: the disc and the glaze cover the centre, alpha %.4f" % [label, full.a])
    var why := "%s: the half glaze reads L %.5f against the full one's %.5f" % [label, half.r, full.r]
    assert_almost_eq(half.r, full.r, L_TOLERANCE, why)


func test_a_half_precision_glaze_in_multiply_reaches_the_full_precision_one() -> void:
    _assert_glaze_holds("multiply", _stamp_glaze(SaLayer.BLEND_MODE.MULTIPLY))


func test_a_half_precision_glaze_in_overlay_reaches_the_full_precision_one() -> void:
    _assert_glaze_holds("overlay", _stamp_glaze(SaLayer.BLEND_MODE.OVERLAY))


func test_a_noise_brush_glaze_on_half_precision_reaches_the_full_precision_one() -> void:
    _assert_glaze_holds("noise", _noise_glaze())


## The disc and three glaze strokes, then one more stroke under one seed, twice
## from the same state, and the layer's bytes after each commit.
func _layer_after_one_stroke_twice(make_glaze: Callable) -> Array[PackedByteArray]:
    var layers: Array[PackedByteArray] = []
    for run in 2:
        var surface := _glazed(SaColorSpace.Depth.F16, 3, make_glaze)
        _dab(make_glaze.call(surface), SEED_BASE + 7)
        layers.append(_chunk_bytes(surface.easel.document.active_layer))
    return layers


func test_one_multiply_stroke_painted_twice_from_one_state_is_the_same_bytes() -> void:
    var layers := _layer_after_one_stroke_twice(_stamp_glaze(SaLayer.BLEND_MODE.MULTIPLY))
    assert_false(layers[0].is_empty(), "The Multiply stroke lands in the layer")
    assert_true(layers[0] == layers[1], "One Multiply stroke under one seed commits the same bytes both times")


func test_one_noise_stroke_painted_twice_with_one_seed_is_the_same_bytes() -> void:
    var layers := _layer_after_one_stroke_twice(_noise_glaze())
    assert_false(layers[0].is_empty(), "The noise stroke lands in the layer")
    assert_true(layers[0] == layers[1], "One noise stroke under one seed commits the same bytes both times")


func test_a_full_precision_glaze_still_paints_u241s_bytes() -> void:
    var surface := _glazed(SaColorSpace.Depth.F32, STROKES, _stamp_glaze(SaLayer.BLEND_MODE.NORMAL))
    var context := HashingContext.new()
    context.start(HashingContext.HASH_SHA256)
    context.update(_chunk_bytes(surface.easel.document.active_layer))
    assert_eq(context.finish().hex_encode(), FULL_PRECISION_GLAZE_SHA256, "A full precision Normal glaze is unchanged")
