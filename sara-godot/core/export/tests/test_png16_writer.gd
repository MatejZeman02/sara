## the 16-bit PNG encoder.
##
## A release needs a PNG deeper than Godot's eight bits, and
## Godot's `save_png_to_buffer` takes no depth argument at all, so the file is
## Sara's own. A wrong chunk length or a little-endian sample is a file that
## opens as noise rather than as an error, so most of this parses the bytes back
## rather than round-tripping through a reader of Sara's own, which would agree
## with the writer about its own mistakes.
##
## The two claims that matter are d73's rounding, kept from the eight-bit path,
## and that the depth survives as far as the `IHDR`, which is what a reader looks
## at before it believes anything else in the file.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The export path at the end builds a real easel and reads a real canvas back.
const REQUIRES_GPU := true

## Where a stored 0.5 lands: half of 65535 is 32767.5, and the rule is the
## nearest step rather than the one below it (d73).
const HALF_ROUNDED: int = 32768
const HALF_TRUNCATED: int = 32767


## A four by three picture whose columns hold 0.0, 0.5, 1.0 and 0.5 again, so one
## file holds both ends of the range and the rounding case between them.
func _image() -> Image:
    var image := Image.create_empty(4, 3, false, Image.FORMAT_RGBAF)
    for y in 3:
        image.set_pixel(0, y, Color(0.0, 0.0, 0.0, 1.0))
        image.set_pixel(1, y, Color(0.5, 0.5, 0.5, 1.0))
        image.set_pixel(2, y, Color(1.0, 1.0, 1.0, 1.0))
        image.set_pixel(3, y, Color(0.5, 0.5, 0.5, 1.0))
    return image


# --- Reading the file back, without going through the writer --------------------


func _u16_be(bytes: PackedByteArray, at: int) -> int:
    return (bytes[at] << 8) | bytes[at + 1]


func _u32_be(bytes: PackedByteArray, at: int) -> int:
    return (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3]


## Every chunk as `type -> data`, walked the way a reader walks a PNG.
func _chunks(bytes: PackedByteArray) -> Dictionary:
    var out: Dictionary = {}
    var at := 8
    while at + 12 <= bytes.size():
        var length := _u32_be(bytes, at)
        out[bytes.slice(at + 4, at + 8).get_string_from_ascii()] = bytes.slice(at + 8, at + 8 + length)
        at += 12 + length
    return out


## The number the sample at *x*, *y* holds, read out of the decompressed
## scanlines: the filter byte first, then two bytes big-endian a sample.
func _sample(raw: PackedByteArray, x: int, y: int, width: int, channels: int = 4) -> int:
    var stride := 1 + width * channels * 2
    return _u16_be(raw, y * stride + 1 + x * channels * 2)


## The decompressed scanlines.
##
## `decompress` is not the inverse of `compress` here: for Deflate it hands back
## a single byte for a stream `compress` wrote itself, silently, where the
## dynamic form with a bound inflates it whole. The bound is generous because the
## images this reads are four by three.
func _scanlines(encoded: PackedByteArray) -> PackedByteArray:
    var data: PackedByteArray = _chunks(encoded)["IDAT"]
    return data.decompress_dynamic(1 << 20, FileAccess.COMPRESSION_DEFLATE)


# --- The file ------------------------------------------------------------------


func test_the_header_says_sixteen_bits_and_rgba() -> void:
    var bytes := SaPng16Writer.encode(_image())
    var header: PackedByteArray = _chunks(bytes)["IHDR"]

    assert_eq(bytes.slice(0, 8), PackedByteArray(SaPng16Writer.PNG_SIGNATURE), "It starts with the signature")
    assert_eq(bytes.slice(12, 16).get_string_from_ascii(), "IHDR", "and the header is the first chunk")
    assert_eq(header.size(), 13, "which is thirteen bytes, where SaExportGamut splices the gamut in")
    assert_eq(header[8], 16, "the bit depth is sixteen")
    assert_eq(header[9], 6, "and the colour type is six, which is RGBA")
    assert_eq(header[10], 0, "with Deflate")
    assert_eq(header[11], 0, "no filtering beyond the filter byte")
    assert_eq(header[12], 0, "and no interlacing")


func test_the_width_and_the_height_are_there_big_endian() -> void:
    var header: PackedByteArray = _chunks(SaPng16Writer.encode(_image()))["IHDR"]

    assert_eq(_u32_be(header, 0), 4, "Four across")
    assert_eq(_u32_be(header, 4), 3, "and three down")


## The clause d73 wrote down and the eight-bit path already paid for: the step
## above, never the one below.
func test_a_stored_half_rounds_up_to_the_step_above() -> void:
    var raw := _scanlines(SaPng16Writer.encode(_image()))
    var sample := _sample(raw, 1, 0, 4)

    assert_eq(sample, HALF_ROUNDED, "0.5 is the step above the halfway point")
    assert_true(sample != HALF_TRUNCATED, "not the step below it, which is what a truncating writer writes")


func test_the_ends_of_the_range_are_reachable() -> void:
    var raw := _scanlines(SaPng16Writer.encode(_image()))

    assert_eq(_sample(raw, 0, 0, 4), 0, "A stored 0.0 is the low end")
    assert_eq(_sample(raw, 2, 0, 4), 65535, "and a stored 1.0 the high one")


## A value the container cannot hold is clipped rather than wrapped, which is
## what the eight-bit path does with the same document.
func test_a_value_outside_the_range_is_clipped() -> void:
    var image := Image.create_empty(2, 1, false, Image.FORMAT_RGBAF)
    image.set_pixel(0, 0, Color(-0.5, 2.0, 0.5, 1.0))
    var raw := _scanlines(SaPng16Writer.encode(image))

    assert_eq(_sample(raw, 0, 0, 2, 3), 0, "A negative red clips to nothing")


func test_every_scanline_carries_the_unfiltered_filter_byte() -> void:
    var raw := _scanlines(SaPng16Writer.encode(_image()))
    var stride := 1 + 4 * 4 * 2

    for y in 3:
        assert_eq(raw[y * stride], SaPng16Writer.FILTER_NONE, "row %d says it is unfiltered" % y)
    assert_eq(raw.size(), stride * 3, "and the stream is exactly the rows")


func test_an_rgb_file_drops_the_alpha_channel() -> void:
    var bytes := SaPng16Writer.encode(_image(), false)
    var header: PackedByteArray = _chunks(bytes)["IHDR"]
    var raw := _scanlines(bytes)

    assert_eq(header[9], 2, "the colour type is two, which is RGB")
    assert_eq(raw.size(), (1 + 4 * 3 * 2) * 3, "and three samples a pixel rather than four")


## Godot opens the file, and it is worth being exact about what it opens it as:
## its PNG loader strips sixteen bits down to eight, so this reader can say the
## file is readable and can say nothing about the depth. The samples themselves
## are asserted from the `IDAT` above, which is the only place they exist.
func test_godot_reads_the_file_back() -> void:
    var image := Image.new()

    assert_eq(image.load_png_from_buffer(SaPng16Writer.encode(_image())), OK, "Godot's own PNG reader opens it")
    assert_eq(image.get_width(), 4, "at the width it was written")
    assert_eq(image.get_height(), 3, "and the height")
    assert_eq(image.get_format(), Image.FORMAT_RGBA8, "narrowed to eight bits a channel on the way in")
    assert_almost_eq(image.get_pixel(1, 0).r, 128.0 / 255.0, 1e-6, "a stored 0.5 read as the eighth-bit step")


## The splice this checks: the writer's header has to be the shape
## `SaExportGamut.png_with_gamut` assumes, or a 16-bit export loses its gamut
## silently.
func test_the_gamut_splice_still_finds_the_header() -> void:
    var named := SaExportGamut.png_with_gamut(SaPng16Writer.encode(_image()), SaGamut.from_id(SaGamut.ID_DISPLAY_P3))
    var chunks := _chunks(named)

    assert_eq(chunks["IHDR"].size(), 13, "the header is still thirteen bytes")
    assert_true(chunks.has("cICP"), "the primaries code went in")
    assert_eq(chunks["cICP"][0], 12, "which says Display P3")
    var image := Image.new()
    assert_eq(image.load_png_from_buffer(named), OK, "and the named file still opens")


func test_an_image_with_no_pixels_is_refused_rather_than_written() -> void:
    assert_true(SaPng16Writer.write(null, SaDataRoot.path("e1-empty.png")) != OK, "No image, no file")


# --- Through the export path ---------------------------------------------------


## The other half: the canvas reaches a file on disk at 16 bits, not just an
## Image built in a test.
func test_the_canvas_reaches_a_sixteen_bit_file_on_disk() -> void:
    var easel := SaEasel.create_default(Vector2i(8, 8))
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    easel.document.fill_layer(Color(0.25, 0.5, 0.75, 1.0))
    easel.request_full_composite()
    easel.process_pending_composite()

    var path := SaDataRoot.path("e1-png16.png")
    assert_eq(SaExport.export_png_texture(easel.output, null, path, 16), OK, "The export reports success")

    var bytes := FileAccess.get_file_as_bytes(path)
    assert_true(bytes.size() > 0, "and there is a file")
    assert_eq(_chunks(bytes)["IHDR"][8], 16, "whose header says sixteen bits")
    var quarter := float(_sample(_scanlines(bytes), 0, 0, 8)) / 65535.0
    assert_almost_eq(quarter, 0.25, 1e-3, "holding the quarter the canvas held")

    assert_true(SaExport.export_png_texture(easel.output, null, path, 32) != OK, "and another depth is refused")

    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    easel.free()
