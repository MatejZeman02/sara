## Opening an image into a layer, and what its colours mean when they land.
##
## An 8-bit PNG holds sRGB-encoded values. Uploaded as they are into a linear
## document they would be wrong by the whole transfer curve: a mid grey of
## 128 is 0.502 encoded and 0.214 linear, and the compositor would show the
## first as the second. The rule is that the import goes through the display
## conversion, and this is the suite that reads the texel back to check.
extends "res://tests/test_framework.gd"

## Uploads and conversions are real textures and a real kernel.
const REQUIRES_GPU := true

const PNG := "res://tests/data/import_gradient.png"
const JPG := "res://tests/data/import_gradient.jpg"
const EXR := "res://tests/data/import_linear.exr"

## An Extended WebP carrying a `.jpg` name, which is what the reported file is.
## Kept out of Godot's import pass by an `.import` of `importer="keep"`,
## because the image importer goes by extension too and errored on every import
## of the project until it was told not to try.
const MISLABELLED := "res://tests/data/webp_named_jpg.jpg"

var _problems: Array[String] = []


func before_each() -> void:
    _problems.clear()
    # A report is a push_error while it announces, and a deliberate one fails
    # the run. The sink is what a test reads.
    SaProblems.announce = false
    SaProblems.attach_sink(func(line: String, _kind: SaProblems.Kind) -> void: _problems.append(line))
    # The sink is handed every report kept while nothing was listening, which
    # is whatever earlier suites left behind, so only what arrives after this
    # line is this suite's.
    _problems.clear()


func after_each() -> void:
    SaProblems.detach_sink()
    SaProblems.announce = true


func _document(space: SaColorSpace = null, size: Vector2i = Vector2i(512, 512)) -> SaEasel:
    var easel := SaEasel.create_default(size)
    if space != null:
        easel.document.reset_to_default(size, space)
    return easel


func _texel(layer: SaLayer, x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var texture := layer.get_field(Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE))
    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(texture)
    return image.get_pixel(x % SaChunk.SIZE, y % SaChunk.SIZE)


func test_a_png_lands_as_stored_in_an_srgb_document() -> void:
    var easel := _document()
    var layer := SaImageImport.open_into(easel.document, PNG)
    assert_not_null(layer, "The PNG opens")
    assert_eq(str(layer.name), "import_gradient", "on a layer named after the file")
    assert_eq(easel.document.active_layer, layer, "which is active")
    var source := Image.load_from_file(PNG)
    var expected := source.get_pixel(150, 100)
    var got := _texel(layer, 150, 100)
    assert_almost_eq(got.r, expected.r, 1e-3, "An sRGB document stores the encoded values as they are: red")
    assert_almost_eq(got.g, expected.g, 1e-3, "green")
    assert_almost_eq(got.a, expected.a, 1e-3, "and the alpha, straight")
    assert_true(_problems.is_empty(), "with nothing to report")
    easel.free()


## The reason the item says "through the display conversion".
func test_a_png_is_decoded_into_a_linear_document() -> void:
    var easel := _document(SaColorSpace.linear_srgb())
    var layer := SaImageImport.open_into(easel.document, PNG)
    assert_not_null(layer, "The PNG opens into a linear document")
    var source := Image.load_from_file(PNG)
    var encoded := source.get_pixel(150, 100)
    var got := _texel(layer, 150, 100)
    var expected := SaTransferFunction.srgb().decode(encoded.r)
    assert_almost_eq(got.r, expected, 2e-3, "and its red is the decoded value, %.3f for %.3f encoded" % [expected, encoded.r])
    assert_true(absf(got.r - encoded.r) > 0.05, "which is not the encoded number")
    easel.free()


func test_a_jpeg_opens_too() -> void:
    var easel := _document()
    var layer := SaImageImport.open_into(easel.document, JPG)
    assert_not_null(layer, "The JPEG opens")
    var got := _texel(layer, 150, 100)
    assert_almost_eq(got.b, 128.0 / 255.0, 0.03, "with its colours within JPEG's rounding")
    assert_almost_eq(got.a, 1.0, 1e-6, "and no alpha, so opaque")
    easel.free()


## What export_exr wrote comes back as it was stored, negatives and values
## above one included, because both sides are linear floats.
func test_an_exr_round_trips_the_stored_values_in_a_linear_document() -> void:
    var easel := _document(SaColorSpace.linear_srgb(), Vector2i(64, 64))
    var layer := SaImageImport.open_into(easel.document, EXR)
    assert_not_null(layer, "The EXR opens")
    var left := _texel(layer, 10, 63)
    var right := _texel(layer, 40, 0)
    assert_almost_eq(left.b, -0.25, 1e-4, "A negative survives")
    assert_almost_eq(right.r, 40.0 / 63.0 * 2.0, 1e-3, "and so does a value above one")
    assert_almost_eq(left.g, 1.0, 1e-3, "and a plain one")
    easel.free()


func test_an_exr_is_encoded_into_an_srgb_document() -> void:
    var easel := _document(SaColorSpace.srgb(), Vector2i(64, 64))
    var layer := SaImageImport.open_into(easel.document, EXR)
    var got := _texel(layer, 40, 32)
    var expected := SaTransferFunction.srgb().encode(32.0 / 63.0)
    assert_almost_eq(got.g, expected, 2e-3, "Linear floats are encoded into an sRGB document")
    easel.free()


## Hard rule 3: the image allocates the chunks it covers and no more.
##
## changed what "covers" means. The upload stopped at the canvas edge,
## so a picture wider than the document lost everything past it on the way in.
## It lands whole now, and the canvas still does not grow: the overhang sits in
## chunks the compositor never reaches, which is what a later crop or resize is
## meant to find.
func test_only_the_covered_chunks_are_allocated() -> void:
    var easel := _document(null, Vector2i(1024, 1024))
    var layer := SaImageImport.open_into(easel.document, PNG)
    assert_eq(layer.chunks.size(), 2, "A 300 by 200 image covers two of the sixteen chunks")

    var small := _document(null, Vector2i(200, 100))
    var over := SaImageImport.open_into(small.document, PNG)
    assert_eq(over.chunks.size(), 2, "A canvas smaller than the image still takes both of the image's chunks")
    assert_true(over.chunks.has(Vector2i(1, 0)), "including the one entirely past the right edge")
    assert_eq(small.document.canvas_size, Vector2i(200, 100), "without the canvas growing")
    assert_almost_eq(
        _texel(over, 280, 50).a,
        Image.load_from_file(PNG).get_pixel(280, 50).a,
        1e-3,
        "and the pixels out there are the picture's, not a hole"
    )
    easel.free()
    small.free()


## The dirty set is what the compositor walks, and the output texture is
## document-sized, so a chunk past the edge cannot be drawn into. Marking one
## would dispatch a clear at coordinates the texture does not have.
func test_a_chunk_past_the_canvas_edge_is_never_marked_dirty() -> void:
    var easel := _document(null, Vector2i(200, 100))
    SaImageImport.open_into(easel.document, PNG)
    var dirty := easel.document.consume_dirty_chunks()
    assert_true(dirty.has(Vector2i(0, 0)), "The chunk the canvas holds is redrawn")
    assert_false(dirty.has(Vector2i(1, 0)), "and the one past the edge is not")

    easel.document.invalidate_chunks([Vector2i(0, 0), Vector2i(4, 4)])
    dirty = easel.document.consume_dirty_chunks()
    assert_eq(dirty.size(), 1, "Any caller asking for one outside the grid is dropped, not trusted")
    easel.free()


func test_a_file_that_is_not_an_image_is_refused_and_reported() -> void:
    var easel := _document()
    var layers_before := easel.document.get_child_count()
    var layer := SaImageImport.open_into(easel.document, "res://tests/data/painted_two_layers.sad")
    assert_null(layer, "A .sad is not an image")
    assert_eq(easel.document.get_child_count(), layers_before, "so no layer is added")
    assert_eq(_problems.size(), 1, "and the painter is told once")
    assert_false(SaImageImport.is_image_path("x.sad"), "which File > Open knows before trying")
    assert_true(SaImageImport.is_image_path("X.PNG"), "whatever the case of the extension")
    easel.free()


func test_an_import_is_one_undo() -> void:
    var easel := _document()
    var layer := SaImageImport.open_into(easel.document, PNG)
    assert_true(easel.document.undo(), "Undo")
    assert_null(layer.get_parent(), "takes the imported layer out")
    assert_true(easel.document.redo(), "and redo")
    assert_eq(layer.get_parent(), easel.document, "brings it back with its pixels")
    assert_almost_eq(_texel(layer, 150, 100).a, Image.load_from_file(PNG).get_pixel(150, 100).a, 1e-3, "intact")
    easel.free()


# --- A file whose name lies about its format ------------------------------------


## The note's own case. Every file in the folder it came from is a WebP that
## kept a `.jpg` name from the URL it was saved with, and `Image.load` picks its
## decoder by extension, so the JPEG decoder was handed WebP bytes and returned
## `ERR_FILE_CORRUPT`. The painter was told the file was corrupt about a picture
## every viewer opens, because a viewer reads the bytes.
##
## The fixture is an Extended WebP, VP8X with an XMP chunk, because that is the
## shape the reported file has and it is the harder of the two.
func test_a_webp_named_jpg_is_read_as_the_webp_it_is() -> void:
    var easel := _document()
    var layer := SaImageImport.open_into(easel.document, MISLABELLED)

    assert_not_null(layer, "The bytes say WebP, so the WebP decoder reads it")
    assert_true(_problems.is_empty(), "and nothing is reported about a file that opened")
    easel.free()


func test_the_bytes_are_what_names_the_format() -> void:
    assert_eq(SaImageImport.sniff_format(MISLABELLED), "webp", "The file's own bytes")
    assert_eq(SaImageImport.claimed_format(MISLABELLED), "jpg", "against what its name claims")
    assert_eq(SaImageImport.sniff_format(PNG), "png", "and a correctly named file agrees with itself")
    assert_eq(SaImageImport.claimed_format(PNG), "png", "both ways round")


## `jpeg` and `jpg` are one format under two names, so the two answers have to
## be spelled the same or every `.jpeg` file would read as mislabelled and take
## the sniffed path for no reason.
func test_jpeg_and_jpg_are_one_answer() -> void:
    assert_eq(SaImageImport.claimed_format("a.jpeg"), "jpg", "One format, two spellings")
    assert_eq(SaImageImport.claimed_format("a.JPG"), "jpg", "whatever the case")
    assert_eq(SaImageImport.claimed_format("a.sad"), "", "and a format this class does not read has no answer")


func test_each_signature_is_recognised() -> void:
    assert_eq(SaImageImport.format_of_header(PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])), "png")
    assert_eq(SaImageImport.format_of_header(PackedByteArray([0xFF, 0xD8, 0xFF, 0xE0])), "jpg")
    assert_eq(SaImageImport.format_of_header(PackedByteArray([0x76, 0x2F, 0x31, 0x01])), "exr")
    var webp := "RIFF".to_ascii_buffer()
    webp.append_array(PackedByteArray([0x88, 0x00, 0x00, 0x00]))
    webp.append_array("WEBP".to_ascii_buffer())
    assert_eq(SaImageImport.format_of_header(webp), "webp", "The name sits after the RIFF length")
    assert_eq(SaImageImport.format_of_header(PackedByteArray([0x00, 0x01, 0x02])), "", "and nothing else is guessed at")


## A colour space read off the extension would call an EXR named `.jpg` sRGB and
## land every value through the wrong transfer curve, which is the bug this
## whole suite exists for. Now that a mislabelled file opens at all, the space
## has to come from the same place the decoder does.
func test_the_colour_space_follows_the_bytes_too() -> void:
    var from_bytes := SaImageImport.space_for(MISLABELLED)
    assert_eq(from_bytes.id, SaColorSpace.srgb().id, "A WebP holds sRGB-encoded values whatever it is called")
    assert_eq(SaImageImport.space_for(EXR).id, SaColorSpace.linear_srgb().id, "and an EXR still holds linear ones")


## The fallback, for a path with no file behind it: nothing to sniff, so the
## extension is the only thing left and the answer is what it always was.
func test_an_unreadable_path_falls_back_to_its_extension() -> void:
    assert_eq(SaImageImport.sniff_format("res://tests/data/no_such_file.exr"), "", "Nothing to read")
    var guessed := SaImageImport.space_for("res://tests/data/no_such_file.exr")
    assert_eq(guessed.id, SaColorSpace.linear_srgb().id, "so the name decides, exactly as it always did")


## WebP is offered by name as well now, because the decoder was always
## there and the folder the note came from is full of them.
func test_webp_is_a_format_file_open_offers() -> void:
    assert_true(SaImageImport.is_image_path("a.webp"), "A WebP is an image Sara opens")
    assert_true(SaImageImport.dialog_filter().contains("*.webp"), "and the dialog says so")


# --- A sixteen-bit PNG, which Godot's loader reads at eight (d12) --------------------

## Where this suite writes the file it reads back, under the checkout's own
## `user://` rather than a path beside the fixtures, because it is one run's
## output and not something to commit.
static var scratch_sixteen_path: String = SaDataRoot.path("d12-sixteen-bit.png")

## One step of sixteen bits, the finest a sample in one of these files can move.
const SIXTEEN_STEP := 1.0 / float(SaImageImport.PNG_SAMPLE_MAX)


## The defect's own number. A stored 0.5 leaves as 32768 of 65535, and Godot's
## PNG loader answers 128 of 255 for that, which is not the same place: the two
## are 0.00196 apart, twelve times a step of the file, and nothing said so.
func test_a_sixteen_bit_png_keeps_its_sixteen_bits() -> void:
    var written := Image.create_empty(4, 2, false, Image.FORMAT_RGBAF)
    var wanted := [
        Color(0.5, 1.0 / 3.0, 0.0, 1.0),
        Color(1.0, 0.25, 0.75, 0.5),
        Color(0.1, 0.2, 0.3, 0.4),
        Color(0.125, 0.0625, 0.5, 0.999),
    ]
    for x in 4:
        written.set_pixel(x, 0, wanted[x])
        written.set_pixel(x, 1, Color(wanted[x].r, wanted[x].g, wanted[x].b, 1.0 - wanted[x].a))
    var file := FileAccess.open(scratch_sixteen_path, FileAccess.WRITE)
    file.store_buffer(SaPng16Writer.encode(written, true))
    file.close()

    var header := SaImageImport.png_header(scratch_sixteen_path)
    assert_eq(int(header.get("bit_depth", 0)), 16, "The file's own header says sixteen")
    assert_eq(int(header.get("colour_type", -1)), SaImageImport.PNG_COLOUR_TYPE_RGBA, "in four channels")

    var back := SaImageImport.read(scratch_sixteen_path)
    assert_not_null(back, "and the reader takes it")
    assert_eq(back.get_format(), Image.FORMAT_RGBAF, "into full floats, a half carrying eleven bits of the sixteen")
    assert_eq(SaImageImport.depth_for(back), SaColorSpace.Depth.F32, "which is the only float width that keeps them")

    for x in 4:
        for y in 2:
            var got := back.get_pixel(x, y)
            var expected := written.get_pixel(x, y)
            for channel in 4:
                assert_almost_eq(
                    got[channel],
                    expected[channel],
                    SIXTEEN_STEP,
                    "texel %d, %d keeps channel %d of the file's own grid" % [x, y, channel]
                )
    assert_almost_eq(back.get_pixel(0, 0).r, 0.5, SIXTEEN_STEP, "0.5 comes back on the file's step, not at 128 of 255")


## Four colour types a sixteen-bit PNG may carry, none of which Godot's loader
## is asked for. Palettes are one, two, four or eight bits a sample by
## definition, so sixteen bits is grey, grey with alpha, colour, or colour with
## alpha, and every one of them leaves as the four channels the upload takes.
func test_every_colour_type_a_sixteen_bit_png_may_carry_is_widened() -> void:
    # The samples are the file's own on the file's own grid, so 0x4000 is
    # 16384 of 65535 and not a quarter: the two are 3.8e-6 apart, which is a
    # quarter of a step at this width and nothing anyone should round away.
    var half := 32768.0 / float(SaImageImport.PNG_SAMPLE_MAX)
    var quarter := 16384.0 / float(SaImageImport.PNG_SAMPLE_MAX)
    var grey := _widened(_scanline([0x8000]), 1, SaImageImport.PNG_COLOUR_TYPE_GREY)
    _assert_colour(grey.get_pixel(0, 0), Color(half, half, half, 1.0), "A grey file")

    var both := _scanline([0x8000, 0x4000])
    var grey_alpha := _widened(both, 2, SaImageImport.PNG_COLOUR_TYPE_GREY_ALPHA)
    _assert_colour(grey_alpha.get_pixel(0, 0), Color(half, half, half, quarter), "A grey file with alpha")

    var rgb := _scanline([0x8000, 0x4000, 0x0000])
    _assert_colour(
        _widened(rgb, 3, SaImageImport.PNG_COLOUR_TYPE_RGB).get_pixel(0, 0),
        Color(half, quarter, 0.0, 1.0),
        "A colour file with no alpha"
    )

    var rgba := _scanline([0x8000, 0x4000, 0x0000, 0xFFFF])
    _assert_colour(
        _widened(rgba, 4, SaImageImport.PNG_COLOUR_TYPE_RGBA).get_pixel(0, 0), Color(half, quarter, 0.0, 1.0), "and one with it"
    )


## PNG's five scanline filters, which Sara's writer never emits, being filter 0
## on every line, and every other program's encoder does. The forward pass is
## written here rather than reached for, so the class is not graded against
## itself, and the sample is two scanlines because the byte above is the whole
## of three of the five and a one-line file would make it zero.
func test_pngs_five_scanline_filters_are_undone() -> void:
    var plain := PackedByteArray()
    for y in 2:
        plain.append(SaImageImport.PNG_FILTER_NONE)
        for i in 8:
            plain.append(((y * 8 + i) * 7 + 3) & 0xFF)
    for kind in 5:
        var filtered := _filtered(plain, kind, 2, 4)
        assert_eq(filtered[0], kind, "The file says which filter its first scanline used")
        var undone := SaPng16Decode.lanes_of(filtered, 2, 2, 4)
        var samples := SaPng16Decode.lanes_of(plain, 2, 2, 4)
        assert_eq(undone.size(), 4, "Filter %d is one PNG defines" % kind)
        for place in 4:
            assert_eq(undone[place].bytes, samples[place].bytes, "and undoing it gives byte %d of each pixel back" % place)
    assert_true(SaPng16Decode.lanes_of(PackedByteArray([9, 0, 0, 0, 0]), 1, 1, 4).is_empty(), "A filter past the five is refused")


## What the reader says when sixteen bits cannot be kept, which is the whole of
## what the defect was: the bits go and no line anywhere mentions it. The
## clause is read off the file's header before any pixel is decoded, so a file
## this reader cannot unpack is still named as one that carried sixteen.
func test_a_sixteen_bit_file_this_reader_cannot_unpack_says_what_it_lost() -> void:
    var plain: Dictionary[String, Variant] = {"interlace": 0, "compression": 0, "filter_method": 0, "colour_type": 6}
    assert_eq(SaImageImport._png16_refusal(plain), "", "A file this reader can unpack loses nothing")

    var interlaced := plain.duplicate()
    interlaced["interlace"] = 1
    assert_true(SaImageImport._png16_refusal(interlaced).contains("interlaced"), "An interlaced one says so")

    var palette := plain.duplicate()
    palette["colour_type"] = 3
    assert_true(SaImageImport._png16_refusal(palette).contains("neither colour nor grey"), "and so does a palette")

    var compressed := plain.duplicate()
    compressed["compression"] = 1
    assert_false(SaImageImport._png16_refusal(compressed).is_empty(), "and a header naming a method PNG has not")


## The header is read off the file rather than asked of Godot, because Godot is
## the half that loses it. An eight-bit PNG is left to Godot's own decoder, so
## its header is read and not decoded.
func test_the_png_header_is_read_off_the_file_itself() -> void:
    var eight := SaImageImport.png_header(PNG)
    assert_eq(int(eight.get("bit_depth", 0)), 8, "An eight-bit PNG says eight")
    assert_eq(int(eight.get("width", 0)), 300, "and its own size")

    assert_eq(SaImageImport.png_header("res://tests/data/painted_two_layers.sad"), {}, "A file that is not a PNG has no header")
    assert_eq(SaImageImport.png_header("res://tests/data/no_such_file.png"), {}, "and neither has a path with no file behind it")
    var signature := PackedByteArray(SaImageImport.PNG_SIGNATURE)
    assert_true(SaImageImport.png_of(signature).is_empty(), "nor has a PNG cut off inside its signature")


## The one pixel of an unfiltered scanline *raw* of *channels* samples, as the
## floats its colour type widens to.
func _widened(raw: PackedByteArray, channels: int, colour_type: int) -> Image:
    return SaPng16Decode.as_floats(SaPng16Decode.lanes_of(raw, 1, 1, channels * 2), 1, 1, channels, colour_type)


## One unfiltered scanline of sixteen-bit samples, its filter byte first.
func _scanline(samples: Array) -> PackedByteArray:
    var raw := PackedByteArray([SaImageImport.PNG_FILTER_NONE])
    for sample: int in samples:
        raw.append((sample >> 8) & 0xFF)
        raw.append(sample & 0xFF)
    return raw


## The same arithmetic as the reader runs, the other way round, which is what
## an encoder does. `pixel_bytes` is one whole pixel, so eight for the two
## samples a pixel carries at sixteen bits.
func _filtered(plain: PackedByteArray, kind: int, width: int, pixel_bytes: int) -> PackedByteArray:
    var out := plain.duplicate()
    var stride := 1 + width * pixel_bytes
    @warning_ignore("integer_division")
    var height := plain.size() / stride
    for y in height:
        var line := y * stride
        out[line] = kind
        for i in width * pixel_bytes:
            var value := plain[line + 1 + i]
            var left := plain[line + 1 + i - pixel_bytes] if i >= pixel_bytes else 0
            var up := plain[line + 1 + i - stride] if y > 0 else 0
            var corner := plain[line + 1 + i - stride - pixel_bytes] if (y > 0 and i >= pixel_bytes) else 0
            match kind:
                SaImageImport.PNG_FILTER_NONE:
                    pass
                SaImageImport.PNG_FILTER_SUB:
                    value = (value - left) & 0xFF
                SaImageImport.PNG_FILTER_UP:
                    value = (value - up) & 0xFF
                SaImageImport.PNG_FILTER_AVERAGE:
                    value = (value - ((left + up) >> 1)) & 0xFF
                _:
                    value = (value - _paeth(left, up, corner)) & 0xFF
            out[line + 1 + i] = value
    return out


## PNG's Paeth predictor, written here rather than borrowed from the class
## being graded: the neighbour whose distance from the gradient is smallest,
## left winning a tie. The three distances are walked rather than tested one
## against another, so a wrong tie-break in the reader has somewhere to show.
static func _paeth(left: int, up: int, corner: int) -> int:
    var estimate := left + up - corner
    var neighbours := [left, up, corner]
    var distances := [absi(estimate - left), absi(estimate - up), absi(estimate - corner)]
    var best := 0
    for i in 3:
        if distances[i] < distances[best]:
            best = i
    return neighbours[best]


func _assert_colour(got: Color, expected: Color, label: String) -> void:
    for channel in 4:
        assert_almost_eq(got[channel], expected[channel], 1e-6, "%s, channel %d" % [label, channel])
