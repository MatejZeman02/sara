## Bounding canvas growth from placed pictures with Grow and from crop boxes to
## SaResample.MAX_DIMENSION.
extends "res://tests/test_framework.gd"

## Real uploads into real chunks and compute passes.
const REQUIRES_GPU := true

const START_SIZE := Vector2i(512, 256)


func _texel(layer: SaLayer, x: int, y: int) -> Color:
    var gx := floori(float(x) / float(SaChunk.SIZE))
    var gy := floori(float(y) / float(SaChunk.SIZE))
    var texture := layer.get_field(Vector2i(gx, gy))
    if texture == null:
        return Color(0.0, 0.0, 0.0, 0.0)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var local_x := x - gx * SaChunk.SIZE
    var local_y := y - gy * SaChunk.SIZE
    return SaFieldSpec.decode_texel(bytes, texture.format, local_y * texture.size.x + local_x)


func _picture(size: Vector2i, color: Color = Color(0.8, 0.2, 0.2, 1.0)) -> Image:
    var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
    image.fill(color)
    return image


## Placing a picture wider than 16,384 pixels with Grow caps the canvas at the
## limit and keeps the whole picture in the layer's chunks.
func test_placing_picture_wider_than_limit_with_grow_caps_canvas_and_keeps_all_columns() -> void:
    var easel := SaEasel.create_default(START_SIZE)
    var doc := easel.document
    var image := _picture(Vector2i(17000, 256))
    var layer := SaImageImport.place(doc, image, "Wide", SaColorSpace.srgb(), SaImageImport.Fit.GROW)
    assert_not_null(layer, "The wide picture lands on a layer")
    assert_true(doc.canvas_size.x <= SaResample.MAX_DIMENSION, "The canvas is no wider than the resample limit")
    assert_eq(doc.canvas_size, Vector2i(SaResample.MAX_DIMENSION, 256), "and reaches exactly the limit")

    # The canvas is 16,384 wide and the picture is 17,000 wide, so centred it
    # starts at (16384 - 17000) / 2 = -308 and ends at 16,691.
    @warning_ignore("integer_division")
    var at_x := (SaResample.MAX_DIMENSION - 17000) / 2
    var last_x := at_x + 17000 - 1
    assert_eq(at_x, -308, "Centred top left starts off canvas at -308")
    assert_eq(last_x, 16691, "Centred bottom right ends off canvas at 16691")
    assert_eq(last_x - at_x + 1, 17000, "The column span is exactly 17,000")

    assert_almost_eq(_texel(layer, at_x, 0).a, 1.0, 1e-3, "The first column of 17,000 holds paint")
    assert_almost_eq(_texel(layer, last_x, 0).a, 1.0, 1e-3, "The last column of 17,000 holds paint")
    assert_almost_eq(_texel(layer, at_x - 1, 0).a, 0.0, 1e-3, "Past the left edge is empty")
    assert_almost_eq(_texel(layer, last_x + 1, 0).a, 0.0, 1e-3, "Past the right edge is empty")

    # Chunks are 256 wide, so -308 lands in chunk -2 and 16,691 in chunk 65.
    assert_true(layer.chunks.has(Vector2i(-2, 0)), "Chunk -2 holds the left overhang")
    assert_true(layer.chunks.has(Vector2i(65, 0)), "Chunk 65 holds the right overhang")
    assert_false(layer.chunks.has(Vector2i(-3, 0)), "No chunk allocated further left")
    assert_false(layer.chunks.has(Vector2i(66, 0)), "No chunk allocated further right")

    easel.process_pending_composite()
    var valid := easel.output != null and easel.output.rid.is_valid()
    assert_true(valid, "The easel output is made and valid at the limit")

    easel.free()


## Cropping to a rectangle wider than 16,384 pixels caps the canvas at the limit,
## and one undo restores the old canvas size.
func test_crop_to_rectangle_wider_than_limit_caps_canvas_and_undoes() -> void:
    var easel := SaEasel.create_default(START_SIZE)
    var doc := easel.document
    var crop := SaCrop.new(doc)
    var done := crop.crop_to(Rect2i(-9000, 0, 18000, 256))
    assert_true(done, "Crop step succeeds")
    assert_true(doc.canvas_size.x <= SaResample.MAX_DIMENSION, "The canvas is no wider than the resample limit")
    assert_eq(doc.canvas_size.x, SaResample.MAX_DIMENSION, "and reaches exactly the limit")

    easel.process_pending_composite()
    var valid := easel.output != null and easel.output.rid.is_valid()
    assert_true(valid, "The easel output is made and valid")

    assert_true(doc.undo(), "One undo succeeds")
    assert_eq(doc.canvas_size, START_SIZE, "The old canvas size is brought back")

    easel.free()


## Sizing inside the limit grows and crops exactly as before.
func test_grow_and_crop_inside_the_limit_behave_as_before() -> void:
    var easel := SaEasel.create_default(START_SIZE)
    var doc := easel.document
    var image := _picture(Vector2i(1024, 512))
    var layer := SaImageImport.place(doc, image, "Inside", SaColorSpace.srgb(), SaImageImport.Fit.GROW)
    assert_not_null(layer, "Picture placed inside limit")
    assert_eq(doc.canvas_size, Vector2i(1024, 512), "Canvas grows to picture size inside limit")

    var crop := SaCrop.new(doc)
    var done := crop.crop_to(Rect2i(50, 50, 400, 300))
    assert_true(done, "Crop inside limit succeeds")
    assert_eq(doc.canvas_size, Vector2i(400, 300), "Canvas cropped to rectangle inside limit")

    assert_true(doc.undo(), "Undo crop succeeds")
    assert_eq(doc.canvas_size, Vector2i(1024, 512), "Undo brings grown size back")

    easel.free()
