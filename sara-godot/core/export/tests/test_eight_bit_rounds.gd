## An eight-bit export rounds a float rather than truncating it.
##
## found `Image.convert` to `FORMAT_RGBA8` puts every float on the step below
## it, so a stored `0.99999988` left a PNG as `254` and a mid grey of `0.5` as
## `127`. These read the bytes back through every door that narrows.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

## One texel per case, what is stored and the byte rounding gives it. The halves
## are a hair to either side of a step's middle, because a float exactly on it
## rounds whichever way the float lands.
const CASES := [
    [0.5, 128],
    [0.99999988, 255],
    [1.0, 255],
    [0.0, 0],
    [0.498, 127],
    [0.9981, 255],
    [0.9979, 254],
    [-0.25, 0],
    [3.0, 255],
]


func _texture_of(values: Array) -> SaTexture:
    var texture := SaTexture.new(Vector2i(values.size(), 1))
    var texels := PackedFloat32Array()
    for value: float in values:
        texels.append_array([value, value, value, 1.0])
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, texels.to_byte_array())
    return texture


func test_the_narrowing_rounds_to_the_nearest_step() -> void:
    var values: Array = CASES.map(func(pair: Array) -> float: return pair[0])
    var texture := _texture_of(values)
    var image := SaExportGamut.byte_image(texture)
    assert_not_null(image, "the texture reads back")
    assert_eq(image.get_format(), Image.FORMAT_RGBA8, "as eight bits a channel")
    var bytes := image.get_data()
    for i in CASES.size():
        assert_eq(bytes[i * 4], CASES[i][1], "%s is written as %d" % [CASES[i][0], CASES[i][1]])
        assert_eq(bytes[i * 4 + 3], 255, "and its opaque alpha stays 255")

    @warning_ignore("static_called_on_instance")
    var untouched := SaExport.get_texture_image_float(texture)
    assert_almost_eq(untouched.get_pixel(0, 0).r, 0.5, 0.0000001, "the texture it was handed is left as it was")


func test_a_half_covered_texel_rounds_its_alpha_too() -> void:
    var texture := SaTexture.new(Vector2i(1, 1))
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, PackedFloat32Array([0.2, 0.2, 0.2, 0.5]).to_byte_array())
    var bytes := SaExportGamut.byte_image(texture).get_data()
    assert_eq(bytes[3], 128, "alpha 0.5 is 128, not 127")


func test_a_png_export_of_mid_grey_holds_128() -> void:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(8, 8)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    canvas.document.fill_layer(Color(0.5, 0.5, 0.5, 1.0))
    canvas.easel.request_composite()
    canvas.easel.process_pending_composite()
    var path := SaDataRoot.path("test_d73_grey.png")
    assert_eq(SaExport.export_png(canvas.easel, path), OK, "the PNG is written")
    var image := Image.load_from_file(path)
    assert_eq(image.get_data()[0], 128, "and its mid grey is 128")
    var jpg_path := SaDataRoot.path("test_d73_grey.jpg")
    assert_eq(SaExport.export_jpg(canvas.easel, jpg_path, 1.0), OK, "the JPEG is written")
    assert_true(
        absi(Image.load_from_file(jpg_path).get_data()[0] - 128) <= 1, "and its grey is within JPEG's own rounding of 128"
    )
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(jpg_path))
    canvas.free()
