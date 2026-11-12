## The Change Gamut question says what Convert does.
##
## the question read "Colours outside sRGB / Rec. 709 will be clipped on screen
## and on export", and the canvas after Convert was the canvas before it byte for
## byte. A conversion keeps every colour, and the view draws a document through
## linear sRGB into the display profile, so the screen has nothing new to clip.
## What clips is an eight-bit export written in the new gamut. Each clause of
## [constant SaImageMenu.GAMUT_QUESTION] is held here against the pixels, in both
## coordinate systems a gamut row converts.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true
## The TIFF tag that says where the strips begin.
const TIFF_STRIP_OFFSETS := 273

const RED := Color(1.0, 0.0, 0.0, 1.0)
const EPSILON := 0.0005
static var scratch_png_path: String = SaDataRoot.path("test_d36.png")
static var scratch_jpg_path: String = SaDataRoot.path("test_d36.jpg")
static var scratch_tiff_path: String = SaDataRoot.path("test_d36.tiff")
static var scratch_exr_path: String = SaDataRoot.path("test_d36.exr")


func after_each() -> void:
    for path: String in [scratch_png_path, scratch_jpg_path, scratch_tiff_path, scratch_exr_path]:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## RGB and Oklab, from a function rather than a const, because a const holding
## another class's enum is not a constant expression.
func _coordinates() -> Array[int]:
    return [SaColorSpace.Coordinates.RGB, SaColorSpace.Coordinates.OKLAB]


func _p3(coordinates: int) -> SaColorSpace:
    return SaColorSpace.srgb().with_gamut(SaGamut.from_id(SaGamut.ID_DISPLAY_P3)).with_coordinates(coordinates)


## A small canvas in *space* filled with the picked `1, 0, 0`, which is the
## red of the document's own gamut, so a P3 document holds P3's red.
func _canvas_in(space: SaColorSpace) -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(16, 16)
    canvas.easel = SaEasel.create_default(canvas.canvas_size, null, space)
    canvas.add_child(canvas.easel)
    canvas.document.fill_layer(RED)
    return canvas


func _convert_to_srgb(canvas: SaCanvas, label: String) -> void:
    var target := canvas.document.color_space.with_gamut(SaGamut.from_id(SaGamut.ID_SRGB))
    assert_true(SaColorConversion.new(canvas.document).convert_to(target), "%s: Convert runs" % label)


## The composited output's middle texel, as the document stores it.
func _stored(canvas: SaCanvas) -> Color:
    canvas.easel.request_composite()
    canvas.easel.process_pending_composite()
    # Through the autoload, the way `SaExportGamut` reaches the same readback.
    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(canvas.canvas)
    return image.get_pixel(8, 8)


## *stored* as the light it names, in linear sRGB, which is what the view's
## shader reaches before the display profile takes it to the screen.
func _light(canvas: SaCanvas) -> Color:
    return canvas.document.color_space.carried_to(SaColorSpace.linear_srgb(), _stored(canvas))


func _assert_rgb(actual: Color, expected: Color, epsilon: float, message: String) -> void:
    assert_almost_eq(actual.r, expected.r, epsilon, "%s, red" % message)
    assert_almost_eq(actual.g, expected.g, epsilon, "%s, green" % message)
    assert_almost_eq(actual.b, expected.b, epsilon, "%s, blue" % message)


func _png_pixel(path: String) -> Color:
    var image := Image.new()
    assert_eq(image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)), OK, "Godot's PNG reader opens %s" % path)
    return image.get_pixel(8, 8)


static func _u16_le(bytes: PackedByteArray, at: int) -> int:
    return bytes[at] | (bytes[at + 1] << 8)


static func _u32_le(bytes: PackedByteArray, at: int) -> int:
    return bytes[at] | (bytes[at + 1] << 8) | (bytes[at + 2] << 16) | (bytes[at + 3] << 24)


## The first texel of a little-endian float TIFF's first strip.
static func _tiff_first_texel(bytes: PackedByteArray) -> Color:
    var directory := _u32_le(bytes, 4)
    var strip := -1
    for i in _u16_le(bytes, directory):
        var at := directory + 2 + i * 12
        if _u16_le(bytes, at) == TIFF_STRIP_OFFSETS:
            strip = _u32_le(bytes, at + 8)
    if strip < 0:
        return Color(-9.0, -9.0, -9.0, -9.0)
    return Color(bytes.decode_float(strip), bytes.decode_float(strip + 4), bytes.decode_float(strip + 8), 1.0)


## "Every colour keeps its value, so the canvas looks the same." P3's red is
## outside sRGB before Convert, and the same light reaches the view after it, so
## neither display profile has anything new to clip.
func test_a_converted_colour_keeps_its_light_so_the_canvas_has_nothing_new_to_clip() -> void:
    for coordinates: int in _coordinates():
        var label := SaColorSpace.coordinates_name(coordinates)
        var canvas := _canvas_in(_p3(coordinates))
        var before := _light(canvas)
        assert_true(before.r > 1.01 and before.g < -0.01, "%s: P3's red is outside sRGB, red past one, green below zero" % label)
        _convert_to_srgb(canvas, label)
        assert_eq(canvas.document.color_space.gamut().id, SaGamut.ID_SRGB, "%s: the document is sRGB now" % label)
        _assert_rgb(_light(canvas), before, EPSILON, "%s: and the light the view draws is the light it drew" % label)
        canvas.free()


## "A PNG or JPEG export clips the colours outside" the new gamut. Before Convert
## the PNG is P3's red named Display P3, after it the same bytes named sRGB, which
## is sRGB's red and not the colour the document holds.
func test_a_png_or_jpeg_export_clips_the_colours_outside_the_new_gamut() -> void:
    for coordinates: int in _coordinates():
        var label := SaColorSpace.coordinates_name(coordinates)
        var canvas := _canvas_in(_p3(coordinates))
        _stored(canvas)
        assert_eq(SaExport.export_png(canvas.easel, scratch_png_path), OK, "%s: exports a PNG before Convert" % label)
        var p3_code: int = SaExportGamut.CICP_PRIMARIES[SaGamut.ID_DISPLAY_P3]
        assert_eq(SaExportGamut.png_primaries_at(scratch_png_path), p3_code, "%s: named Display P3" % label)
        _assert_rgb(_png_pixel(scratch_png_path), RED, 0.004, "%s: P3's red leaves as 255, 0, 0" % label)
        _convert_to_srgb(canvas, label)
        _stored(canvas)
        assert_eq(SaExport.export_png(canvas.easel, scratch_png_path), OK, "%s: exports a PNG after Convert" % label)
        var srgb_code: int = SaExportGamut.CICP_PRIMARIES[SaGamut.ID_SRGB]
        assert_eq(SaExportGamut.png_primaries_at(scratch_png_path), srgb_code, "%s: named sRGB" % label)
        _assert_rgb(_png_pixel(scratch_png_path), RED, 0.004, "%s: and still 255, 0, 0, sRGB's red, which is the clip" % label)
        assert_eq(SaExport.export_jpg(canvas.easel, scratch_jpg_path), OK, "%s: exports a JPEG after Convert" % label)
        var jpeg := Image.new()
        assert_eq(jpeg.load_jpg_from_buffer(FileAccess.get_file_as_bytes(scratch_jpg_path)), OK, "%s: the JPEG opens" % label)
        var pixel := jpeg.get_pixel(8, 8)
        assert_true(pixel.r > 0.95 and pixel.g < 0.05 and pixel.b < 0.05, "%s: and clips to the same red" % label)
        canvas.free()


## "A TIFF or EXR export keeps them." The TIFF is the new gamut through sRGB's
## curve with its sign, and the EXR is the same colour in linear sRGB, the space
## every EXR is written in, past one and below nought as the TIFF is.
func test_a_tiff_or_exr_export_keeps_the_colours_outside_it() -> void:
    # The TIFF is the image formats module's, so its registries are held here.
    var formats := Fixtures.make_picture_registries()
    assert_eq(SaImageImport.formats(), formats.image_formats, "the formats asked are the ones these registries installed")
    for coordinates: int in _coordinates():
        var label := SaColorSpace.coordinates_name(coordinates)
        var canvas := _canvas_in(_p3(coordinates))
        _convert_to_srgb(canvas, label)
        assert_eq(
            Fixtures.export_through(&"tiff", canvas.easel, scratch_tiff_path), OK, "%s: exports a TIFF after Convert" % label
        )
        # Read after the export, which rounds the live colour as a save does.
        var stored := _stored(canvas)
        var texel := _tiff_first_texel(FileAccess.get_file_as_bytes(scratch_tiff_path))
        assert_true(texel.r > 1.01 and texel.g < -0.01, "%s: the TIFF's red is past one and its green below zero" % label)
        assert_eq(SaExport.export_exr(canvas.easel, scratch_exr_path), OK, "%s: exports an EXR after Convert" % label)
        var exr := Image.load_from_file(scratch_exr_path)
        assert_not_null(exr, "%s: the EXR loads back" % label)
        if exr != null:
            var linear := canvas.document.color_space.carried_to(SaColorSpace.linear_srgb(), stored)
            _assert_rgb(exr.get_pixel(8, 8), linear, 0.0001, "%s: holding the colour as linear sRGB, unclipped" % label)
            assert_true(linear.r > 1.01 and linear.g < -0.01, "%s: which is outside the cube" % label)
        canvas.free()


func test_the_question_says_the_canvas_keeps_it_and_names_what_clips() -> void:
    var sentence: String = SaImageMenu.GAMUT_QUESTION
    assert_false(sentence.contains("on screen"), "the question no longer promises a clip the canvas does not make")
    assert_true(sentence.contains("the canvas looks the same"), "it says the canvas is unchanged")
    assert_true(sentence.contains("PNG or JPEG export clips"), "it names the exports that clip")
    assert_true(sentence.contains("TIFF or EXR export keeps"), "and the ones that keep the colours")
    assert_eq(sentence.count("%s"), 3, "and still takes the two gamuts and the target again")
