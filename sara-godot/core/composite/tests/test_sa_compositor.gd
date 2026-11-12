## GPU integration tests for SaCompositor.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true


func test_compositor_registration_and_caching() -> void:
    var comp := SaCompositor.new()
    # Built-ins are no longer registered inside SaCompositor._init: the skeleton
    # registers them through the public module API, which is what proves the API
    # can express its own built-ins.
    var registries := Fixtures.make_registries()
    comp.set_registry(registries.blend_modes)
    assert_true(comp.has_blend_mode(&"normal"), "Normal must resolve through the registry")
    assert_true(comp.has_blend_mode(&"multiply"), "So must every other built-in")

    # A mode is keyed by kernel *name*. The index is looked up in the compiled
    # shader rather than supplied by the caller, so inserting a #kernel can no
    # longer silently remap every mode after it.
    var custom := SaBlendModeDescriptor.create(&"test_custom", "screen")
    assert_true(registries.blend_modes.register(custom), "A module may add a blend mode")
    assert_true(comp.has_blend_mode(&"test_custom"), "and the compositor resolves it")
    assert_eq(
        registries.blend_modes.resolve_kernel(&"test_custom"),
        GlobalShaderCompiler.get_kernel_index("composite", "screen"),
        "Its kernel index comes from the shader, by name"
    )

    var c1 := comp.get_compute("composite")
    var c2 := comp.get_compute("composite")
    assert_eq(c1, c2, "get_compute should cache and return same SaCompute instance")


func test_composite_all_layers() -> void:
    var comp := SaCompositor.new()
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(256, 256), SaCompositor.new())

    # Fill active layer with red
    doc.active_layer.fill(Color(1, 0, 0, 1))

    var canvas_tex := SaTexture.new(Vector2i(256, 256))
    comp.composite_all_layers(canvas_tex, doc, Rect2(0, 0, 256, 256))

    var rd := GlobalShaderCompiler.get_rd()
    var data: PackedByteArray = rd.texture_get_data(canvas_tex.rid, 0)
    assert_true(data.size() >= 16, "Canvas texture should have data")

    if data.size() >= 16:
        var r := data.decode_float(0)
        data.decode_float(4)
        data.decode_float(8)
        var a := data.decode_float(12)
        assert_almost_eq(r, 1.0, 0.05, "Composited red should be ~1.0")
        assert_almost_eq(a, 1.0, 0.05, "Composited alpha should be ~1.0")

    doc.free()


func test_composite_only_invalidated_chunks() -> void:
    var comp := SaCompositor.new()
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(512, 256), SaCompositor.new())
    doc.compositor = comp
    var active_chunk := doc.active_layer.get_or_create_field(Vector2i(1, 0))
    GlobalShaderCompiler.get_rd().texture_clear(active_chunk.rid, Color.GREEN, 0, 1, 0, 1)

    var canvas_tex := SaTexture.new(Vector2i(512, 256))
    GlobalShaderCompiler.get_rd().texture_clear(canvas_tex.rid, Color.TRANSPARENT, 0, 1, 0, 1)
    comp.composite_chunks(canvas_tex, doc, {Vector2i(1, 0): SaDocument.WHOLE_CHUNK}, Rect2(0, 0, 512, 256))

    var rd := GlobalShaderCompiler.get_rd()
    var data: PackedByteArray = rd.texture_get_data(canvas_tex.rid, 0)
    var untouched_alpha := data.decode_float(12)
    var dirty_byte_index := (128 * 512 + 384) * 16
    var dirty_green := data.decode_float(dirty_byte_index + 4)
    assert_almost_eq(untouched_alpha, 0.0, 0.01, "Untouched output chunk should remain transparent")
    assert_almost_eq(dirty_green, 1.0, 0.05, "Invalidated output chunk should be composited")

    doc.free()
