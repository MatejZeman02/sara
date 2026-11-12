## Automated tests for Layer Locks (is_locked and alpha_locked).
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const DabPacking = preload("res://core/api/dab/sa_dab_packing.gd")
const StateBucketFillScript = preload("res://modules/sara-base-modules/base/tools/state_bucket_fill.gd")
const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")

var _lock_signal_emitted: bool = false
var _alpha_lock_signal_emitted: bool = false


func _on_lock_changed(val: bool) -> void:
    _lock_signal_emitted = val


func _on_alpha_lock_changed(val: bool) -> void:
    _alpha_lock_signal_emitted = val


func test_layer_lock_signals() -> void:
    var layer := SaLayer.new()
    layer.lock_changed.connect(_on_lock_changed)
    layer.alpha_lock_changed.connect(_on_alpha_lock_changed)

    _lock_signal_emitted = false
    layer.is_locked = true
    assert_true(_lock_signal_emitted, "lock_changed signal should be emitted when is_locked changes")

    _alpha_lock_signal_emitted = false
    layer.alpha_locked = true
    assert_true(_alpha_lock_signal_emitted, "alpha_lock_changed signal should be emitted when alpha_locked changes")

    layer.free()


func test_paint_lock_enforcement() -> void:
    var surface := Fixtures.make_surface()

    var layer := surface.get_document().active_layer
    var chunk: SaTexture = layer.get_or_create_field(Vector2i(0, 0))

    # Lock layer
    layer.is_locked = true

    # Try filling via document command
    surface.get_document().fill_layer(Color(1, 0, 0, 1))
    var rd := GlobalShaderCompiler.get_rd()
    var data: PackedByteArray = rd.texture_get_data(chunk.rid, 0)
    if data.size() >= 16:
        assert_almost_eq(data.decode_float(12), 0.0, 0.01, "Alpha should remain 0.0 when fill_layer is called on locked layer")

    # Try bucket fill tool
    var bucket := StateBucketFillScript.new()
    bucket.surface = surface
    # The fill reads the foreground rather than a settings resource of its own,
    # for the reason its own doc comment gives.
    SaColors.foreground = Color(0, 1, 0, 1)
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = true
    bucket.handle_input(event)

    data = rd.texture_get_data(chunk.rid, 0)
    if data.size() >= 16:
        assert_almost_eq(data.decode_float(12), 0.0, 0.01, "Alpha should remain 0.0 when bucket tool is used on locked layer")

    surface.get_document().free()
    surface.easel.free()


func test_alpha_lock_enforcement_in_fill() -> void:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(256, 256), SaCompositor.new())

    var layer := doc.active_layer
    var chunk: SaTexture = layer.get_or_create_field(Vector2i(0, 0))

    # Test filling on a completely transparent layer with alpha_locked = true -> should remain transparent and not draw
    layer.alpha_locked = true
    layer.fill(Color(1, 0, 0, 1.0))
    var rd := GlobalShaderCompiler.get_rd()
    var data: PackedByteArray = rd.texture_get_data(chunk.rid, 0)
    if data.size() >= 16:
        assert_almost_eq(
            data.decode_float(12), 0.0, 0.01, "Alpha should remain 0.0 when filled on transparent area under alpha lock"
        )
        assert_almost_eq(
            data.decode_float(0), 0.0, 0.01, "Red should remain 0.0 when filled on transparent area under alpha lock"
        )

    # Disable alpha lock and fill initially with half-transparent green
    layer.alpha_locked = false
    layer.fill(Color(0, 1, 0, 0.4))

    # Enable alpha lock and fill with red
    layer.alpha_locked = true
    layer.fill(Color(1, 0, 0, 1.0))

    data = rd.texture_get_data(chunk.rid, 0)
    if data.size() >= 16:
        assert_almost_eq(data.decode_float(0), 1.0, 0.01, "Red channel should be updated to ~1.0 under alpha lock")
        assert_almost_eq(data.decode_float(4), 0.0, 0.01, "Green channel should be replaced to ~0.0 under alpha lock")
        assert_almost_eq(data.decode_float(12), 0.4, 0.01, "Alpha channel should be preserved at ~0.4 under alpha lock")

    doc.free()


func test_alpha_lock_enforcement_in_brush() -> void:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(256, 256), SaCompositor.new())

    var layer := doc.active_layer
    var chunk: SaTexture = layer.get_or_create_field(Vector2i(0, 0))

    # 1. Fill layer with half-transparent green without alpha lock
    layer.fill(Color(0, 1, 0, 0.5))

    # 2. Clear a region by creating/verifying a brush and painting red WITH alpha lock
    layer.alpha_locked = true

    var brush := StateBrushScript.new()
    brush.settings.color = Color(1, 0, 0, 1.0)
    brush.settings.radius = 20.0
    brush.settings.hardness = GammaFloat.new(1.0, 1.0)
    brush.settings.flow = GammaFloat.new(1.0, 1.0)

    # Dispatch brush directly at center (128, 128), through the kernel the brush
    # itself dispatches: `dab`, and its own packer with it.
    var pos := Vector2(128, 128)
    var data_push := DabPacking.pack_dab_params(
        pos,
        Vector2(0, 0),
        Color(1, 0, 0, 1.0),
        Vector2(20.0, 20.0),
        0.0,
        DabPacking.fade_for_hardness(brush.settings.hardness.raw()),
        brush.settings.flow.apply(),
        SaDabGeometry.PaintMode.OVER,
        true
    )
    brush.compute.set_texture(0, chunk.rid)
    var mask_1 := SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    mask_1.clear(Color(1.0, 1.0, 1.0, 1.0))
    brush.compute.set_texture(SaSelection.BINDING, mask_1.rid)
    # The soft generator's table, which the kernel declares whichever generator
    # is running, so a uniform set that leaves it out builds nothing at all.
    # Everything the kernel samples, whichever generator is running, so
    # a uniform set that leaves one out builds nothing at all.
    var tip_mask := SaBrushTipMask.new()
    var bindings := SaStampBindings.of(tip_mask)
    brush.compute.set_buffer(StateBrushScript.SOFTNESS_BINDING, tip_mask.softness_for(brush.settings.tip).rid)
    brush.compute.set_sampled_texture(StateBrushScript.TIP_IMAGE_BINDING, tip_mask.sampler_rid())
    brush.compute.set_sampled_texture(StateBrushScript.PATTERN_BINDING, SaBrushTipMask.stand_in().rid)
    brush.compute.set_buffer(SaStampBindings.MASKING_BINDING, bindings.masking_for(null, brush.settings.tip.diameter).rid)
    SaSmudgeReservoir.bind(brush.compute, null)
    brush.compute.set_texture(StateBrushScript.HEIGHT_BINDING, SaStrokeHeights.held(null).rid)
    brush.compute.set_sampled_texture(SaStampBindings.RAMP_BINDING, SaBrushTipMask.stand_in().rid)
    brush.compute.set_push_constant_float_array(data_push)
    brush.compute.dispatch_kernel("dab", 32, 32, 1)

    var rd := GlobalShaderCompiler.get_rd()
    var data: PackedByteArray = rd.texture_get_data(chunk.rid, 0)
    if data.size() >= 16:
        # Check center pixel (128, 128 -> index (128*256 + 128) * 16 bytes)
        var center_idx := (128 * 256 + 128) * 16
        assert_almost_eq(data.decode_float(center_idx + 0), 1.0, 0.05, "Red should be ~1.0 under brush alpha lock")
        assert_almost_eq(data.decode_float(center_idx + 12), 0.5, 0.05, "Alpha should remain ~0.5 under brush alpha lock")

    doc.free()
