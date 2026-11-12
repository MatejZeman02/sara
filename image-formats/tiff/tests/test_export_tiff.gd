## Sara's own TIFF writer.
##
## `TODO.md` line 113 asked for `.tiff` export beside PNG, JPG and EXR. Godot has
## no TIFF encoder, so unlike the other three this is a file Sara writes byte by
## byte, and a wrong offset is a file that opens as noise rather than as an
## error. So this suite parses the bytes back rather than round-tripping through
## a reader of Sara's own: a reader that shares the writer's mistakes would agree
## with it about everything.
##
## The claim that matters is the one EXR already carries and PNG cannot: a value
## the canvas holds outside 0 to 1 survives the file. Half of these are about
## that and the rest are about the file being a TIFF at all.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Writes a real file and reads a real canvas back.
const REQUIRES_GPU := true

## Values a PNG would destroy: a negative, a highlight far above one, and a
## number that is neither.
const OUT_OF_RANGE := Color(-0.25, 3.75, 0.5, 0.5)

## The skeleton's formats with this module's after them, built again before
## each test because registries a test builds install over them.
var _formats: SaRegistries


func before_each() -> void:
    _formats = Fixtures.make_picture_registries()


func _image(width: int = 4, height: int = 3, fill: Color = OUT_OF_RANGE) -> Image:
    var image := Image.create_empty(width, height, false, Image.FORMAT_RGBAF)
    image.fill(fill)
    return image


func _scratch(name: String) -> String:
    return SaDataRoot.path(name)


# --- Reading the file back, without going through the writer --------------------


func _u16(bytes: PackedByteArray, at: int) -> int:
    return bytes[at] | (bytes[at + 1] << 8)


func _u32(bytes: PackedByteArray, at: int) -> int:
    return bytes[at] | (bytes[at + 1] << 8) | (bytes[at + 2] << 16) | (bytes[at + 3] << 24)


## Every directory entry as `tag -> {type, count, value}`, where `value` is what
## the entry's own four bytes hold: the value itself when it fits, and an offset
## into the file when it does not.
func _directory(bytes: PackedByteArray) -> Dictionary:
    var at := _u32(bytes, 4)
    var count := _u16(bytes, at)
    var out: Dictionary = {}
    for i in count:
        var entry := at + 2 + i * 12
        out[_u16(bytes, entry)] = {
            "type": _u16(bytes, entry + 2),
            "count": _u32(bytes, entry + 4),
            "value": _u32(bytes, entry + 8),
        }
    return out


## The four floats of the pixel at *index*, read out of the strip.
func _pixel(bytes: PackedByteArray, index: int) -> Color:
    var strip := int(_directory(bytes)[SaExportTiff.TAG_STRIP_OFFSETS]["value"])
    var at := strip + index * 16
    return Color(bytes.decode_float(at), bytes.decode_float(at + 4), bytes.decode_float(at + 8), bytes.decode_float(at + 12))


## The four unsigned shorts of the pixel at *index*, read out of a 16-bit strip,
## which is two bytes a sample where the float one is four.
func _u16_pixel(bytes: PackedByteArray, index: int) -> Array:
    var strip := int(_directory(bytes)[SaExportTiff.TAG_STRIP_OFFSETS]["value"])
    var at := strip + index * 8
    return [_u16(bytes, at), _u16(bytes, at + 2), _u16(bytes, at + 4), _u16(bytes, at + 6)]


# --- The file ------------------------------------------------------------------


func test_the_header_says_little_endian_tiff() -> void:
    var bytes := SaExportTiff.encode(_image())

    assert_eq(_u16(bytes, 0), SaExportTiff.BYTE_ORDER_LITTLE, "II, so every number after it is little-endian")
    assert_eq(_u16(bytes, 2), SaExportTiff.MAGIC, "and 42, which is the whole of the version field")
    assert_eq(_u32(bytes, 4), 8, "with the directory straight after the eight-byte header")


func test_the_directory_is_sorted_by_tag_and_ends() -> void:
    var bytes := SaExportTiff.encode(_image())
    var at := _u32(bytes, 4)
    var count := _u16(bytes, at)

    assert_true(count > 0, "There are entries")
    var previous := -1
    for i in count:
        var tag := _u16(bytes, at + 2 + i * 12)
        assert_true(tag > previous, "tag %d comes after the one before it, which the format requires" % tag)
        previous = tag
    assert_eq(_u32(bytes, at + 2 + count * 12), 0, "and there is no second directory")


## The three fields the whole format choice rests on. Without them a reader has
## every right to read four floats as four bytes.
func test_the_fields_say_thirty_two_bit_float_rgba() -> void:
    var bytes := SaExportTiff.encode(_image())
    var directory := _directory(bytes)

    assert_eq(int(directory[SaExportTiff.TAG_SAMPLES_PER_PIXEL]["value"]), 4, "Four samples a pixel")
    assert_eq(int(directory[SaExportTiff.TAG_PHOTOMETRIC]["value"]), 2, "read as RGB")
    assert_eq(int(directory[SaExportTiff.TAG_EXTRA_SAMPLES]["value"]), 2, "with unassociated alpha, which is what Sara stores")
    assert_eq(int(directory[SaExportTiff.TAG_COMPRESSION]["value"]), 1, "and no compression, which every reader must handle")

    var bits_at := int(directory[SaExportTiff.TAG_BITS_PER_SAMPLE]["value"])
    var format_at := int(directory[SaExportTiff.TAG_SAMPLE_FORMAT]["value"])
    for i in 4:
        assert_eq(_u16(bytes, bits_at + i * 2), 32, "sample %d is 32 bits" % i)
        assert_eq(_u16(bytes, format_at + i * 2), 3, "and sample %d is IEEE float" % i)


## The other depth, and the reason it is here at all: a program that will not
## open a float TIFF opens this one. Three fields move, the other twelve are the
## file above.
func test_the_fields_say_sixteen_bit_unsigned_rgba() -> void:
    var bytes := SaExportTiff.encode(_image(4, 3), 96.0, PackedByteArray(), 16)
    var directory := _directory(bytes)

    assert_eq(int(directory[SaExportTiff.TAG_SAMPLES_PER_PIXEL]["value"]), 4, "Four samples a pixel")
    assert_eq(int(directory[SaExportTiff.TAG_PHOTOMETRIC]["value"]), 2, "read as RGB")
    assert_eq(int(directory[SaExportTiff.TAG_EXTRA_SAMPLES]["value"]), 2, "with unassociated alpha")

    var bits_at := int(directory[SaExportTiff.TAG_BITS_PER_SAMPLE]["value"])
    var format_at := int(directory[SaExportTiff.TAG_SAMPLE_FORMAT]["value"])
    for i in 4:
        assert_eq(_u16(bytes, bits_at + i * 2), 16, "sample %d is 16 bits" % i)
        assert_eq(_u16(bytes, format_at + i * 2), 1, "and sample %d is unsigned integer" % i)
    assert_eq(int(directory[SaExportTiff.TAG_STRIP_BYTE_COUNTS]["value"]), 4 * 3 * 8, "which is two bytes a sample")
    var strip := int(directory[SaExportTiff.TAG_STRIP_OFFSETS]["value"])
    assert_eq(bytes.size(), strip + 4 * 3 * 8, "and the file ends where the strip does")


## The rounding rule at the other depth, and the clamp that comes with it: half
## lands on the middle step rather than the one below, which is d73, and a value
## outside 0 to 1 lands on the end it left by, which is what a fixed point depth
## does to the no-clamp promise.
func test_a_sixteen_bit_sample_is_rounded_and_clamped() -> void:
    var bytes := SaExportTiff.encode(_image(2, 1, Color(0.5, 0.25, 3.75, -1.0)), 96.0, PackedByteArray(), 16)

    var pixel := _u16_pixel(bytes, 0)
    assert_eq(pixel[0], 32768, "Half is the middle of the range, rounded up and not truncated")
    assert_eq(pixel[1], 16384, "and a quarter is a quarter of it")
    assert_eq(pixel[2], 65535, "while a highlight above one clamps to the top")
    assert_eq(pixel[3], 0, "and a negative clamps to the bottom")


## Eight bits is the depth the writer refuses rather than rounds, because the
## header would otherwise promise what the strip does not hold.
func test_a_depth_that_is_neither_thirty_two_nor_sixteen_is_refused() -> void:
    assert_eq(SaExportTiff.encode(_image(), 96.0, PackedByteArray(), 8).size(), 0, "An eight-bit encode writes nothing")
    assert_eq(SaExportTiff.encode(_image(), 96.0, PackedByteArray(), 24).size(), 0, "and neither does a twenty-four bit one")

    var path := _scratch("t12-eight-bit.tif")
    assert_true(SaExportTiff.write(_image(), path, 96.0, PackedByteArray(), 8) != OK, "and a write is refused")
    assert_false(FileAccess.file_exists(path), "with no file left on disk")


func test_the_strip_is_the_size_the_directory_claims() -> void:
    var bytes := SaExportTiff.encode(_image(4, 3))
    var directory := _directory(bytes)
    var strip := int(directory[SaExportTiff.TAG_STRIP_OFFSETS]["value"])
    var length := int(directory[SaExportTiff.TAG_STRIP_BYTE_COUNTS]["value"])

    assert_eq(int(directory[SaExportTiff.TAG_IMAGE_WIDTH]["value"]), 4, "Four across")
    assert_eq(int(directory[SaExportTiff.TAG_IMAGE_LENGTH]["value"]), 3, "three down")
    assert_eq(int(directory[SaExportTiff.TAG_ROWS_PER_STRIP]["value"]), 3, "in one strip of three rows")
    assert_eq(length, 4 * 3 * 4 * 4, "which is width by height by four floats")
    assert_eq(bytes.size(), strip + length, "and the file ends where the strip does")
    assert_eq(strip % 2, 0, "with the strip on an even offset, which the specification asks for")


## The whole reason the format is here. PNG clips this and JPEG clips it twice.
func test_a_value_outside_zero_to_one_survives_the_file() -> void:
    var bytes := SaExportTiff.encode(_image(2, 2, OUT_OF_RANGE))

    for i in 4:
        var pixel := _pixel(bytes, i)
        assert_eq(pixel.r, OUT_OF_RANGE.r, "pixel %d keeps its negative red exactly" % i)
        assert_eq(pixel.g, OUT_OF_RANGE.g, "and its highlight green, well above one")
        assert_eq(pixel.b, OUT_OF_RANGE.b, "and everything between")
        assert_eq(pixel.a, OUT_OF_RANGE.a, "and its alpha")


## Bit exact rather than close: the file holds the same float32 the canvas did,
## and a writer that lost a bit of mantissa would pass an approximate assertion.
##
## The expected value comes back out of a `Color` rather than from the literal,
## because a GDScript float is a double and a `Color` channel is a float32, so
## the narrowing has already happened before the writer sees anything.
func test_the_float_extremes_are_bit_exact() -> void:
    var extremes := [-3.4e38, -1.0e-30, 0.0, 1.0e-30, 3.4e38]
    for value: float in extremes:
        var stored := Color(value, value, value, 1.0)
        var pixel := _pixel(SaExportTiff.encode(_image(1, 1, stored)), 0)
        assert_eq(pixel.r, stored.r, "%e came back as itself" % value)


## An F16 document exports at the same precision as an F32 one, which is what
## `get_texture_image_float` already promises and what the writer must not undo.
func test_a_half_float_image_widens_rather_than_being_refused() -> void:
    var image := Image.create_empty(2, 1, false, Image.FORMAT_RGBAH)
    image.fill(Color(2.5, -0.5, 0.25, 1.0))

    var pixel := _pixel(SaExportTiff.encode(image), 0)

    assert_almost_eq(pixel.r, 2.5, 1e-6, "The highlight came through")
    assert_almost_eq(pixel.g, -0.5, 1e-6, "and the negative")
    assert_almost_eq(pixel.b, 0.25, 1e-6, "and the ordinary value")


func test_the_resolution_fields_carry_the_documents_dpi() -> void:
    var bytes := SaExportTiff.encode(_image(), 300.0)
    var directory := _directory(bytes)
    var at := int(directory[SaExportTiff.TAG_X_RESOLUTION]["value"])

    assert_eq(_u32(bytes, at), 300, "Three hundred dots")
    assert_eq(_u32(bytes, at + 4), 1, "over one, which is what a RATIONAL of a whole number is")
    assert_eq(int(directory[SaExportTiff.TAG_RESOLUTION_UNIT]["value"]), 2, "an inch")


func test_an_image_with_no_pixels_is_refused_rather_than_written() -> void:
    var path := _scratch("t12-empty.tif")
    assert_true(SaExportTiff.write(null, path) != OK, "No image, no file")


# --- Through the export path ---------------------------------------------------


## The other half: the canvas reaches the file, not just an Image built in a
## test. Written to disk and read back off it.
func test_the_canvas_reaches_a_file_on_disk() -> void:
    var easel := SaEasel.create_default(Vector2i(8, 8))
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    # Opaque, so the composite over the default background is the fill itself
    # and the assertion below is about the export rather than about Porter-Duff.
    var opaque := Color(OUT_OF_RANGE.r, OUT_OF_RANGE.g, OUT_OF_RANGE.b, 1.0)
    easel.document.fill_layer(opaque)
    easel.request_full_composite()
    easel.process_pending_composite()

    var path := _scratch("t12-canvas.tif")
    assert_eq(SaExportTiff.export_texture(easel.output, path, 96.0), OK, "The export reports success")

    var bytes := FileAccess.get_file_as_bytes(path)
    assert_true(bytes.size() > 0, "and there is a file")
    assert_eq(_u16(bytes, 0), SaExportTiff.BYTE_ORDER_LITTLE, "which is a TIFF")
    var directory := _directory(bytes)
    assert_eq(int(directory[SaExportTiff.TAG_IMAGE_WIDTH]["value"]), 8, "at the canvas's own width")
    var pixel := _pixel(bytes, 0)
    assert_almost_eq(pixel.g, opaque.g, 1e-4, "holding the highlight the canvas held")

    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    easel.free()


## The dialog offers it, which is the difference between a writer and a feature.
func test_the_export_dialog_offers_tiff() -> void:
    assert_true(SaExportDialog.format_ids().has(&"tiff"), "TIFF is one of the formats")
    var tiff := SaImageImport.formats().find(&"tiff")
    assert_eq(tiff.label, "TIFF", "with a label")
    assert_false(tiff.save_filter.is_empty(), "and a file filter")
    for format in SaImageImport.formats().exported():
        assert_false(format.note.is_empty(), "%s says what it does to a value outside 0 to 1" % format.id)
