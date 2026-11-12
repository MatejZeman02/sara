## Tests for StateBucketFill tool and canvas clear/fill operations.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const StateBucketFillScript = preload("res://modules/sara-base-modules/base/tools/state_bucket_fill.gd")


func test_document_fill_layer_and_undo() -> void:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(256, 256), SaCompositor.new())

    var layer := doc.active_layer
    var chunk: SaTexture = layer.get_or_create_field(Vector2i(0, 0))

    # Fill layer with solid red
    doc.fill_layer(Color(1, 0, 0, 1))

    var rd := GlobalShaderCompiler.get_rd()
    var data: PackedByteArray = rd.texture_get_data(chunk.rid, 0)
    assert_true(data.size() >= 16, "Chunk should have pixel data")
    if data.size() >= 16:
        assert_almost_eq(data.decode_float(0), 1.0, 0.01, "Red channel after fill should be ~1.0")
        assert_almost_eq(data.decode_float(12), 1.0, 0.01, "Alpha channel after fill should be ~1.0")

    # Undo fill
    assert_true(doc.undo_redo.has_undo(), "UndoRedo should have an action for fill_layer")
    doc.undo_redo.undo()

    var current_chunk: SaTexture = layer.get_or_create_field(Vector2i(0, 0))
    data = rd.texture_get_data(current_chunk.rid, 0)
    if data.size() >= 16:
        assert_almost_eq(data.decode_float(12), 0.0, 0.01, "Alpha channel after undo should revert to ~0.0")

    doc.free()


func test_document_clear_layer() -> void:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(256, 256), SaCompositor.new())

    var layer := doc.active_layer

    doc.fill_layer(Color(0, 1, 0, 1))
    doc.clear_layer()

    var current_chunk: SaTexture = layer.get_or_create_field(Vector2i(0, 0))
    var rd := GlobalShaderCompiler.get_rd()
    var data: PackedByteArray = rd.texture_get_data(current_chunk.rid, 0)
    if data.size() >= 16:
        assert_almost_eq(data.decode_float(12), 0.0, 0.01, "Alpha channel after clear_layer should be ~0.0")

    doc.free()


func test_bucket_fill_tool_action() -> void:
    var surface := Fixtures.make_surface()

    var bucket := StateBucketFillScript.new()
    bucket.surface = surface
    # The foreground rather than a settings resource of the tool's own, because
    # a resource of its own was only ever written by the eyedropper's signal, so
    # every other way of choosing a colour left the fill painting the one it was
    # constructed with.
    SaColors.foreground = Color(0, 0, 1, 1)

    # Simulate left mouse button press
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = true

    bucket.handle_input(event)

    # An empty layer is one flat transparent field, so a flood from the corner
    # reaches all of it and the click still fills everything. What changed is
    # why: the region is grown rather than the grid being allocated whole.
    var layer := surface.get_document().active_layer
    var chunk: SaTexture = layer.get_or_create_field(Vector2i(0, 0))
    var rd := GlobalShaderCompiler.get_rd()
    var data: PackedByteArray = rd.texture_get_data(chunk.rid, 0)
    if data.size() >= 16:
        assert_almost_eq(data.decode_float(8), 1.0, 0.01, "Blue channel after bucket tool fill should be ~1.0")

    surface.get_document().free()
    surface.easel.free()
