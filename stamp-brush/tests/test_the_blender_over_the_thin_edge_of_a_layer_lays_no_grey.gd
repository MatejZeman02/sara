extends "res://tests/test_framework.gd"

## The shipped Blender stroked across a half-transparent edge onto a
## transparent area lays no texel darker, in luminance, than the edge's own
## colour, and over a layer with no paint at all it lays nothing.
##
## A grey dash appeared where a Blender crossed the thin
## edge of a layer, and blots where a Blender crossed an empty layer. Both were the
## brush's own colour: a blurring or dulling pickup set the carry's strength to
## the share of paint under the dab, so over thin paint the dab laid mostly the
## colour in the painter's swatch, and over none it laid that colour at full
## opacity. The brush here holds black, so any of it shows as a darkening. The
## dab also laid the carried colour at full opacity wherever the layer was
## empty, so a thin edge blurred into a thick one, and this holds the blur to
## the edge's own alpha.

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const ShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_blender")

## A light paint, so the brush's black would read as a fall in luminance.
const EDGE := Color(0.9, 0.85, 0.7)
const BLACK := Color(0.0, 0.0, 0.0, 1.0)
## Half transparent, and the thin edge the carry-back painter met.
const ALPHAS: Array[float] = [0.5, 0.06]
const RADIUS: float = 24.0
const STEPS: int = 30
## A texel counts as laid from this alpha up.
const LAID_LEAST: float = 0.002
## The luminance a laid texel may fall below the edge's, rounding at half float.
const DARKER_MOST: float = 0.004
## How far past the edge's own alpha a blurred texel may stand. A blur spreads
## paint and never thickens it, and the Blender laid this edge opaque before.
const THICKER_MOST: float = 0.01

## A chunk's side, which the canvas is two of wide and one tall.
var _side: int = 0


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)


func after_each() -> void:
    ScratchFolder.clear(scratch_dir)


func _blender() -> Resource:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    store.install_shipped(SettingsScript.new(), ShippedPresetsScript)
    return store.load_preset("Blender")


static func _luminance(colour: Color) -> float:
    return 0.2126 * colour.r + 0.7152 * colour.g + 0.0722 * colour.b


## Two chunks side by side, the left one the edge's colour at *alpha* or empty
## when *alpha* is nought, the right one empty.
func _surface(alpha: float) -> SaSurface:
    var probe := Fixtures.make_surface(Vector2i(64, 64))
    var side := probe.get_document().active_layer.get_or_create_chunk(Vector2i(0, 0)).pixel_size()
    probe.get_document().free()
    probe.easel.free()
    _side = side
    var surface := Fixtures.make_surface(Vector2i(2 * side, side))
    var document := surface.get_document()
    if alpha > 0.0:
        document.active_layer.get_or_create_chunk(Vector2i(0, 0)).clear(Color(EDGE, alpha))
        document.invalidate_chunks([Vector2i(0, 0)])
    surface.easel.request_full_composite()
    surface.easel.process_pending_composite()
    return surface


func _stroke(surface: SaSurface, preset: Resource, from: Vector2, to: Vector2) -> void:
    var brush := StateBrushScript.new()
    brush.surface = surface
    SaPresetStore.copy_settings(preset, brush.settings)
    brush.settings.radius = RADIUS / float(_side)
    brush.settings.color = BLACK
    var view := surface.view
    for i in range(STEPS + 1):
        view.mouse_position = from.lerp(to, float(i) / float(STEPS))
        var event: InputEvent
        if i == 0:
            var press := InputEventMouseButton.new()
            press.button_index = MOUSE_BUTTON_LEFT
            press.pressed = true
            event = press
        else:
            var motion := InputEventMouseMotion.new()
            motion.button_mask = MOUSE_BUTTON_MASK_LEFT
            motion.pressure = 1.0
            event = motion
        brush.handle_input(event)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    brush.handle_input(release)
    surface.get_document().commit_stroke()


func _texels(layer: SaLayer, grid_pos: Vector2i) -> Array[Color]:
    var out: Array[Color] = []
    var chunk: SaChunk = layer.chunks.get(grid_pos)
    if chunk == null:
        return out
    var texture := chunk.albedo()
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    var step := 2 if half else 4
    for at in range(0, bytes.size(), step * 4):
        var channels: Array[float] = []
        for channel in range(4):
            var offset: int = at + channel * step
            channels.append(bytes.decode_half(offset) if half else bytes.decode_float(offset))
        out.append(Color(channels[0], channels[1], channels[2], channels[3]))
    return out


func test_the_blender_across_a_half_transparent_edge_lays_nothing_darker_than_the_edge() -> void:
    var preset := _blender()
    assert_not_null(preset, "The fresh store holds a Blender")
    if preset == null:
        return
    for alpha: float in ALPHAS:
        var surface := _surface(alpha)
        var document := surface.get_document()
        var middle := float(_side)
        _stroke(surface, preset, Vector2(middle - 40.0, middle * 0.5), Vector2(middle + 40.0, middle * 0.5))
        var laid := 0
        var darkest := INF
        var thickest := 0.0
        var broken := 0
        for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0)]:
            for texel: Color in _texels(document.active_layer, grid_pos):
                if is_nan(texel.r) or is_nan(texel.g) or is_nan(texel.b) or is_nan(texel.a):
                    broken += 1
                    continue
                if texel.a < LAID_LEAST:
                    continue
                darkest = minf(darkest, _luminance(texel))
                if grid_pos.x == 1:
                    laid += 1
                    thickest = maxf(thickest, texel.a)
        assert_eq(broken, 0, "At alpha %.2f no texel holds a NaN" % alpha)
        assert_true(
            thickest <= alpha + THICKER_MOST,
            "and the blur laid the edge no thicker than it was, %.4f against %.2f" % [thickest, alpha]
        )
        assert_true(laid > 0, "At alpha %.2f the stroke carried the edge onto the empty chunk, %d texels" % [alpha, laid])
        assert_true(
            darkest >= _luminance(EDGE) - DARKER_MOST,
            "and no texel it left is darker than the edge, darkest %.4f against %.4f" % [darkest, _luminance(EDGE)]
        )
        document.free()
        surface.easel.free()


func test_the_blender_over_a_layer_with_no_paint_lays_nothing() -> void:
    var preset := _blender()
    assert_not_null(preset, "The fresh store holds a Blender")
    if preset == null:
        return
    var surface := _surface(0.0)
    var document := surface.get_document()
    var middle := float(_side)
    _stroke(surface, preset, Vector2(middle - 40.0, middle * 0.5), Vector2(middle + 40.0, middle * 0.5))
    var laid := 0
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0)]:
        for texel: Color in _texels(document.active_layer, grid_pos):
            if texel.a >= LAID_LEAST:
                laid += 1
    assert_eq(laid, 0, "A Blender over an empty layer lays no blot of the brush's own colour")
    document.free()
    surface.easel.free()
