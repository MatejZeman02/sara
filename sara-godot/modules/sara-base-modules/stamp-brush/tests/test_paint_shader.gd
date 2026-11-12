## GPU integration tests for the paint fixture kernel, the retired brush engine
## `tests/fixtures/paint_kernel.gd` keeps for the suites.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")


func test_paint_shader_execution() -> void:
    var rd := GlobalShaderCompiler.get_rd()
    assert_not_null(rd, "RenderingDevice should be available")

    # Create 64x64 destination canvas (transparent)
    var canvas_tex := SaTexture.new(Vector2i(64, 64))
    rd.texture_clear(canvas_tex.rid, Color(0, 0, 0, 0), 0, 1, 0, 1)

    var comp := PaintKernel.compute()
    comp.set_texture(0, canvas_tex.rid)
    # The paint kernel binds the selection mask too. A 1 by 1 mask is no
    # selection, and reads as full coverage everywhere.
    var mask_1 := SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    mask_1.clear(Color(1.0, 1.0, 1.0, 1.0))
    comp.set_texture(SaSelection.BINDING, mask_1.rid)

    # Draw solid white circle at center (32, 32) with radius 10
    var brush_pos := Vector2(32.0, 32.0)
    var offset := Vector2(0.0, 0.0)
    var color := Color(1.0, 1.0, 1.0, 1.0)
    var radius := 10.0
    var hardness := 1.0
    var hardness_gamma := 1.0
    var flow := 1.0

    var params := PaintKernel.pack_params(brush_pos, offset, color, radius, hardness, hardness_gamma, flow)
    comp.set_push_constant_float_array(params)

    # Dispatch 8x8 groups (since 64/8 = 8)
    comp.dispatch_kernel("paint", 8, 8, 1)

    # Read back pixel data
    var data: PackedByteArray = rd.texture_get_data(canvas_tex.rid, 0)
    assert_true(data.size() >= (32 * 64 + 32) * 16, "Texture data should contain center pixel")

    if data.size() >= (32 * 64 + 32) * 16:
        var byte_idx := (32 * 64 + 32) * 16
        var r: float = data.decode_float(byte_idx)
        var g: float = data.decode_float(byte_idx + 4)
        var b: float = data.decode_float(byte_idx + 8)
        var a: float = data.decode_float(byte_idx + 12)

        assert_almost_eq(r, 1.0, 0.01, "Center pixel red should be ~1.0")
        assert_almost_eq(g, 1.0, 0.01, "Center pixel green should be ~1.0")
        assert_almost_eq(b, 1.0, 0.01, "Center pixel blue should be ~1.0")
        assert_almost_eq(a, 1.0, 0.01, "Center pixel alpha should be ~1.0")


func test_state_brush_applies_flow_once() -> void:
    var surface := Fixtures.make_surface()

    var brush := StateBrushScript.new()
    brush.surface = surface
    brush.settings.color = Color(1.0, 0.0, 0.0, 1.0)
    brush.settings.radius = 20.0 / surface.get_canvas_size().x
    brush.settings.hardness = GammaFloat.new(1.0, 1.0)
    brush.settings.flow = GammaFloat.new(0.5, 1.0)
    brush.settings.opacity_by_pressure = false

    brush._stamp_brush(Vector2(128.0, 128.0), 1.0)

    var chunk: SaTexture = surface.get_document().stroke_layer.get_field(Vector2i(0, 0))
    assert_not_null(chunk, "Brush dab should allocate a stroke chunk")
    if chunk != null:
        var rd := GlobalShaderCompiler.get_rd()
        var data: PackedByteArray = rd.texture_get_data(chunk.rid, 0)
        var center_idx := (128 * 256 + 128) * 16
        assert_true(data.size() >= center_idx + 16, "Stroke chunk should contain the center pixel")
        if data.size() >= center_idx + 16:
            assert_almost_eq(
                data.decode_float(center_idx + 12), 0.5, 0.01, "Half flow should produce half opacity, not quarter opacity"
            )

    surface.get_document().free()
    surface.easel.free()


func test_eraser_shader_execution() -> void:
    var rd := GlobalShaderCompiler.get_rd()
    assert_not_null(rd, "RenderingDevice should be available")

    # Create 64x64 destination canvas filled with solid white (1, 1, 1, 1)
    var canvas_tex := SaTexture.new(Vector2i(64, 64))
    rd.texture_clear(canvas_tex.rid, Color(1, 1, 1, 1), 0, 1, 0, 1)

    var comp := PaintKernel.compute()
    comp.set_texture(0, canvas_tex.rid)
    # The paint kernel binds the selection mask too. A 1 by 1 mask is no
    # selection, and reads as full coverage everywhere.
    var mask_2 := SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    mask_2.clear(Color(1.0, 1.0, 1.0, 1.0))
    comp.set_texture(SaSelection.BINDING, mask_2.rid)

    # Stamp eraser at center (32, 32) with radius 10 and mode = 1.0 (erase)
    var brush_pos := Vector2(32.0, 32.0)
    var offset := Vector2(0.0, 0.0)
    var color := Color(1.0, 1.0, 1.0, 1.0)  # color doesn't matter for erase, but flow/alpha do
    var radius := 10.0
    var hardness := 1.0
    var hardness_gamma := 1.0
    var flow := 1.0
    var mode := 1.0  # 1.0 = erase mode

    var params := PaintKernel.pack_params(brush_pos, offset, color, radius, hardness, hardness_gamma, flow, mode)
    comp.set_push_constant_float_array(params)

    # Dispatch 8x8 groups
    comp.dispatch_kernel("paint", 8, 8, 1)

    # Read back pixel data
    var data: PackedByteArray = rd.texture_get_data(canvas_tex.rid, 0)
    assert_true(data.size() >= (32 * 64 + 32) * 16, "Texture data should contain center pixel")

    if data.size() >= (32 * 64 + 32) * 16:
        var byte_idx := (32 * 64 + 32) * 16
        var r: float = data.decode_float(byte_idx)
        var g: float = data.decode_float(byte_idx + 4)
        var b: float = data.decode_float(byte_idx + 8)
        var a: float = data.decode_float(byte_idx + 12)

        assert_almost_eq(r, 1.0, 0.01, "Erasing should preserve red color")
        assert_almost_eq(g, 1.0, 0.01, "Erasing should preserve green color")
        assert_almost_eq(b, 1.0, 0.01, "Erasing should preserve blue color")
        assert_almost_eq(a, 0.0, 0.01, "Center pixel alpha should be erased to ~0.0")
