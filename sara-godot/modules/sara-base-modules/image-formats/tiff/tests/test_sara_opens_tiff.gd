## Sara opens TIFF, its own export first.
##
## A painter exported a 32-bit TIFF to carry a picture to another program and
## back, and File > Open said the file's first bytes matched no format Sara
## reads. An ordinary 8-bit TIFF made elsewhere was refused the same way, so
## Sara offered TIFF as an export and had no way back in.
##
## The writer's own files go round through the reader at both depths it
## offers, and the files Sara does not write are built here by hand, a
## big-endian eight-bit RGB and Deflate files packed with
## `PackedByteArray.compress`, because a reader tested only against its own
## writer would agree with it about everything. The last test exports a
## document and opens the file into it, and the layer it makes holds what the
## canvas held.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The last test composites a real document and reads its texels back.
const REQUIRES_GPU := true

## Values an 8-bit file would destroy: a negative, a highlight past one, a
## fraction no byte holds, and alphas between.
const FLOATS: Array[Color] = [
    Color(-0.25, 3.75, 0.5, 0.5),
    Color(0.0, 0.0, 0.0, 0.0),
    Color(1.0, 1.0, 1.0, 1.0),
    Color(0.123457, 0.987654, 0.333333, 0.75),
    Color(12.5, -3.0, 0.000001, 1.0),
    Color(0.5, 0.25, 0.125, 0.0625),
]

## Tags the hand-built files carry as LONG, the rest going in as SHORT.
const LONG_TAGS: Array[int] = [256, 257, 273, 278, 279]

var _problems: Array[String] = []
var _scratch: Array[String] = []

## The skeleton's formats with this module's after them, built again before
## each test because registries a test builds install over them.
var _formats: SaRegistries


func before_each() -> void:
    _formats = Fixtures.make_picture_registries()
    _problems.clear()
    _scratch.clear()
    # A refusal is a push_error while it announces, and a deliberate one fails
    # the run, so the lines come to the suite instead.
    SaProblems.announce = false
    SaProblems.attach_sink(func(line: String, _kind: SaProblems.Kind) -> void: _problems.append(line))
    _problems.clear()


func after_each() -> void:
    SaProblems.detach_sink()
    SaProblems.announce = true
    for path in _scratch:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _file(name: String, bytes: PackedByteArray) -> String:
    var path := SaDataRoot.path(name)
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(bytes)
    file.close()
    _scratch.append(path)
    return path


func _float_picture(width: int, height: int) -> Image:
    var image := Image.create_empty(width, height, false, Image.FORMAT_RGBAF)
    for y in height:
        for x in width:
            image.set_pixel(x, y, FLOATS[(x + y * width) % FLOATS.size()])
    return image


# --- Sara's own files ------------------------------------------------------------


## The float file holds every value, so the round trip is exact to the bit.
func test_sara_s_float_tiff_comes_back_as_it_left() -> void:
    var written := _float_picture(7, 5)
    var path := _file("test_s29_float.tif", SaExportTiff.encode(written))
    assert_eq(SaImageImport.sniff_format(path), "tiff", "The file's own bytes say TIFF")
    var back := SaImageImport.read(path)
    assert_not_null(back, "Sara opens the float TIFF it wrote")
    if back == null:
        return
    assert_eq(back.get_format(), Image.FORMAT_RGBAF, "as full floats")
    assert_eq(back.get_size(), Vector2i(7, 5), "at its own size")
    assert_eq(back.get_data(), written.get_data(), "and every sample to the bit, negatives and highlights included")
    assert_eq(SaImageImport.depth_for(back), SaColorSpace.Depth.F32, "A float file names F32")
    assert_true(_problems.is_empty(), "with nothing to report: %s" % [_problems])


## Sixteen bits are clamped and rounded by the writer, so the reader is held to
## half a step of the sixty-five thousand.
func test_sara_s_sixteen_bit_tiff_comes_back_within_a_step() -> void:
    var written := Image.create_empty(9, 4, false, Image.FORMAT_RGBAF)
    for y in 4:
        for x in 9:
            written.set_pixel(x, y, Color(x / 8.0, y / 3.0, 0.123457, 1.0 - x / 16.0))
    var path := _file("test_s29_sixteen.tiff", SaExportTiff.encode(written, 96.0, PackedByteArray(), 16))
    var back := SaImageImport.read(path)
    assert_not_null(back, "Sara opens the 16-bit TIFF it wrote")
    if back == null:
        return
    assert_eq(back.get_format(), Image.FORMAT_RGBAF, "as full floats, which carry all sixteen bits")
    var worst := 0.0
    for y in 4:
        for x in 9:
            var a := written.get_pixel(x, y)
            var b := back.get_pixel(x, y)
            worst = maxf(worst, maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a))))
    assert_true(worst <= 0.5 / 65535.0 + 1e-7, "every sample within half a step, the worst %s" % String.num_scientific(worst))
    assert_eq(SaImageImport.depth_for(back), SaColorSpace.Depth.F32, "and the file answers F32, as a 16-bit PNG does")


# --- Files made elsewhere ----------------------------------------------------------


## The byte order Sara never writes, and the eight bits it does not either.
func test_a_hand_built_big_endian_eight_bit_rgb_file_opens() -> void:
    var pixels := PackedByteArray([255, 0, 0, 0, 255, 0, 0, 0, 255, 10, 20, 30, 128, 128, 128, 1, 254, 77])
    var fields := {256: [3], 257: [2], 258: [8, 8, 8], 259: [1], 262: [2], 277: [3], 278: [2]}
    var bytes := _tiff(fields, [pixels], true)
    assert_eq(SaImageImport.format_of_header(bytes.slice(0, 16)), "tiff", "MM and 42 big-endian are a TIFF")
    var path := _file("test_s29_be.tif", bytes)
    var back := SaImageImport.read(path)
    assert_not_null(back, "A big-endian 8-bit RGB file opens")
    if back == null:
        return
    assert_eq(back.get_format(), Image.FORMAT_RGBA8, "as bytes, which hold it exactly")
    var expected := PackedByteArray()
    for i in 6:
        expected.append_array(pixels.slice(i * 3, i * 3 + 3))
        expected.append(255)
    assert_eq(back.get_data(), expected, "each pixel its own three bytes, opaque")
    assert_eq(SaImageImport.depth_for(back), -1, "An 8-bit file names no float width, so the painter is asked")
    var space := SaImageImport.space_for(path)
    assert_eq(space.gamut().id, SaGamut.ID_SRGB, "A file with no profile opens as sRGB")
    assert_eq(str(space.transfer.id), str(SaTransferFunction.ID_SRGB), "through sRGB's curve")
    assert_true(_problems.is_empty(), "with nothing to report: %s" % [_problems])


## Sixteen bits of RGBA in two strips, each Deflate with horizontal differencing,
## which is what a zip TIFF from another program is.
func test_a_deflate_file_with_the_predictor_opens() -> void:
    var width := 5
    var height := 3
    var samples := PackedInt64Array()
    for i in width * height * 4:
        samples.append((i * 4099 + 17) % 65536)
    var differenced := _differenced(samples, width, 4, 0xFFFF)
    var strips: Array[PackedByteArray] = []
    for rows: Vector2i in [Vector2i(0, 2), Vector2i(2, 3)]:
        var strip := PackedByteArray()
        for i in range(rows.x * width * 4, rows.y * width * 4):
            _put(strip, differenced[i], 2, false)
        strips.append(strip.compress(FileAccess.COMPRESSION_DEFLATE))
    var fields := {256: [width], 257: [height], 258: [16, 16, 16, 16], 259: [8], 262: [2], 277: [4], 278: [2], 317: [2], 338: [2]}
    var back := SaTiffReader.new(_tiff(fields, strips), "zip16.tif").picture()
    assert_not_null(back, "A Deflate file with the predictor opens")
    if back == null:
        return
    var floats := back.get_data().to_float32_array()
    var wrong := 0
    for i in samples.size():
        if absf(floats[i] - samples[i] / 65535.0) > 1e-7:
            wrong += 1
    assert_eq(wrong, 0, "and every one of its %d samples is the one packed, over both strips" % samples.size())
    assert_true(_problems.is_empty(), "with nothing to report: %s" % [_problems])


## The old number for Deflate, a grey with no alpha, and floats big-endian with
## the predictor run over their bits, which is the one order the swap and the
## predictor have to agree on.
func test_a_deflate_grey_and_a_big_endian_float_file_open() -> void:
    var greys := PackedByteArray([0, 64, 128, 192, 255, 7])
    var grey_fields := {256: [3], 257: [2], 258: [8], 259: [32946], 262: [1], 277: [1]}
    var grey := SaTiffReader.new(_tiff(grey_fields, [greys.compress(FileAccess.COMPRESSION_DEFLATE)]), "grey.tif").picture()
    assert_not_null(grey, "A Deflate grey opens")
    if grey != null:
        assert_eq(grey.get_pixel(1, 0).to_rgba32(), Color8(64, 64, 64, 255).to_rgba32(), "into three equal channels, opaque")
        assert_eq(grey.get_pixel(2, 1).to_rgba32(), Color8(7, 7, 7, 255).to_rgba32(), "to its last pixel")

    var colours := PackedFloat32Array([0.5, -2.0, 7.25, 1.0, 0.0, 0.333333, -0.0001, 100.0, 0.75])
    var words := PackedInt64Array()
    for value in colours:
        var one := PackedByteArray()
        one.resize(4)
        one.encode_float(0, value)
        words.append(one.decode_u32(0))
    var differenced := _differenced(words, 3, 3, 0xFFFFFFFF)
    var strip := PackedByteArray()
    for word in differenced:
        _put(strip, word, 4, true)
    var float_fields := {256: [3], 257: [1], 258: [32, 32, 32], 259: [8], 262: [2], 277: [3], 317: [2], 339: [3, 3, 3]}
    var floats := SaTiffReader.new(_tiff(float_fields, [strip.compress(FileAccess.COMPRESSION_DEFLATE)], true), "f.tif").picture()
    assert_not_null(floats, "A big-endian float RGB file with the predictor opens")
    if floats != null:
        assert_eq(floats.get_format(), Image.FORMAT_RGBAF, "as full floats")
        var back := floats.get_data().to_float32_array()
        var expected := PackedFloat32Array()
        for i in 3:
            expected.append_array(colours.slice(i * 3, i * 3 + 3))
            expected.append(1.0)
        assert_eq(back, expected, "every float as packed, made opaque")
    assert_true(_problems.is_empty(), "with nothing to report: %s" % [_problems])


## Associated alpha is divided back out, because a chunk holds a straight
## colour.
func test_an_associated_alpha_is_made_straight() -> void:
    var pixels := PackedByteArray([100, 50, 0, 200, 0, 0, 0, 0])
    var fields := {256: [2], 257: [1], 258: [8, 8, 8, 8], 262: [2], 277: [4], 338: [1]}
    var back := SaTiffReader.new(_tiff(fields, [pixels]), "premultiplied.tif").picture()
    assert_not_null(back, "A premultiplied file opens")
    if back != null:
        assert_eq(back.get_data(), PackedByteArray([128, 64, 0, 200, 0, 0, 0, 0]), "its colour divided by its alpha, rounded")


# --- What it does not read, and says ------------------------------------------------


## LZW, which the reader reads, is no longer refused, so the file
## refused by name through the import is now a JPEG one.
func test_a_jpeg_file_is_refused_naming_jpeg() -> void:
    var fields := {256: [2], 257: [2], 258: [8], 259: [7], 262: [1], 277: [1]}
    var path := _file("test_s29_jpeg.tif", _tiff(fields, [PackedByteArray([128, 0, 1, 2, 3])]))
    assert_null(SaImageImport.read(path), "A JPEG compressed file is not read")
    assert_eq(_problems.size(), 1, "and one line says so")
    var line := _problems[0] if not _problems.is_empty() else ""
    assert_true(line.contains("compressed with JPEG"), "naming JPEG: %s" % line)
    assert_true(line.contains("which Sara does not read yet"), "and that Sara does not read it")
    assert_true(line.contains(path), "about the file the painter chose")
    assert_false(line.contains("match no format"), "rather than saying its bytes match nothing")


func test_what_else_it_does_not_read_is_named() -> void:
    var plain := {256: [2], 257: [2], 258: [8], 262: [1], 277: [1]}
    var cases := [
        [{322: [16], 324: [100]}, "is stored in tiles"],
        [{262: [3]}, "in a palette"],
        [{262: [5], 277: [4], 258: [8, 8, 8, 8]}, "as CMYK"],
        [{262: [6], 277: [3], 258: [8, 8, 8]}, "as YCbCr"],
        [{262: [2], 277: [3], 258: [8, 8, 8], 284: [2]}, "in a plane of its own"],
        [{339: [2]}, "signed integer samples"],
        [{258: [1]}, "1-bit integer samples"],
        [{258: [16], 339: [3]}, "16-bit float samples"],
        [{259: [7]}, "compressed with JPEG"],
        [{259: [34925]}, "compressed with LZMA"],
        [{259: [8], 317: [3]}, "the floating point predictor"],
        [{262: [2], 277: [3], 258: [8, 16, 8]}, "samples of different widths"],
    ]
    for case: Array in cases:
        var fields: Dictionary = plain.duplicate()
        fields.merge(case[0], true)
        _problems.clear()
        assert_null(
            SaTiffReader.new(_tiff(fields, [PackedByteArray([0, 0, 0, 0])]), "x.tif").picture(), "%s is not read" % case[1]
        )
        var line := _problems[0] if not _problems.is_empty() else ""
        assert_true(line.contains(case[1]) and line.contains("does not read yet"), "and is named: %s" % line)

    var big := _tiff(plain, [PackedByteArray([0, 0, 0, 0])])
    big[2] = 43
    assert_eq(SaImageImport.format_of_header(big.slice(0, 16)), "tiff", "A BigTIFF reaches the reader")
    _problems.clear()
    assert_null(SaTiffReader.new(big, "big.tif").picture(), "which does not read it")
    assert_true(not _problems.is_empty() and _problems[0].contains("is a BigTIFF"), "and says it is a BigTIFF")


## A file whose numbers run past its own end is refused as unreadable, not as a
## format Sara has yet to learn.
func test_a_cut_short_file_is_refused_as_unreadable() -> void:
    var fields := {256: [64], 257: [64], 258: [8], 262: [1], 277: [1]}
    assert_null(
        SaTiffReader.new(_tiff(fields, [PackedByteArray([1, 2, 3])]), "cut.tif").picture(), "A cut short file is not read"
    )
    var line := _problems[0] if not _problems.is_empty() else ""
    assert_true(
        line.contains("Could not read 'cut.tif'") and line.contains("end before the picture does"), "and says so: %s" % line
    )


# --- The import's own door ---------------------------------------------------------


func test_the_import_knows_the_names_and_the_bytes() -> void:
    assert_true(SaImageImport.is_image_path("a.tif") and SaImageImport.is_image_path("B.TIFF"), "Both spellings are pictures")
    assert_true(SaImageImport.dialog_filter().contains("*.tif") and SaImageImport.dialog_filter().contains("*.tiff"), "listed")
    assert_eq(SaImageImport.claimed_format("a.tif"), "tiff", "and .tif claims what the sniffer answers")
    assert_eq(SaImageImport.claimed_format("a.TIFF"), "tiff", "as .tiff does")
    assert_eq(SaImageImport.format_of_header(PackedByteArray([0x49, 0x49, 0x2A, 0x00])), "tiff", "II*0 is a TIFF")
    assert_eq(SaImageImport.format_of_header(PackedByteArray([0x4D, 0x4D, 0x00, 0x2A])), "tiff", "MM0* is a TIFF")
    assert_eq(SaImageImport.format_of_header(PackedByteArray([0x49, 0x49, 0x00, 0x2A])), "", "and II with MM's version is not")

    # A TIFF under a PNG's name still reaches the reader, as a mislabelled WebP
    # reaches its decoder.
    var path := _file("test_s29_named_png.png", SaExportTiff.encode(_float_picture(2, 2)))
    assert_not_null(SaImageImport.read(path), "A TIFF called .png opens")
    assert_true(_problems.is_empty(), "with nothing to report: %s" % [_problems])


## The profile Sara wrote names the gamut it was written in, and any other
## profile, or none, opens as sRGB.
func test_the_profile_sara_wrote_names_the_gamut() -> void:
    var picture := _float_picture(2, 2)
    for gamut_id: StringName in SaExportGamut.PROFILE_FILES:
        var gamut := SaGamut.from_id(gamut_id)
        var path := _file("test_s29_%s.tif" % gamut_id, SaExportTiff.encode(picture, 96.0, SaExportGamut.profile_for(gamut)))
        var space := SaImageImport.space_for(path)
        assert_eq(space.gamut().id, gamut_id, "A file carrying %s's profile opens as %s" % [gamut_id, gamut_id])
        assert_eq(str(space.transfer.id), str(SaTransferFunction.ID_SRGB), "through sRGB's curve")
    var other := SaExportGamut.profile_for(SaGamut.from_id(SaGamut.ID_DISPLAY_P3))
    other[other.size() - 1] ^= 0xFF
    var foreign := _file("test_s29_foreign.tif", SaExportTiff.encode(picture, 96.0, other))
    assert_eq(SaImageImport.space_for(foreign).gamut().id, SaGamut.ID_SRGB, "and a profile Sara did not write opens as sRGB")


# --- A document and back -------------------------------------------------------------


## What a round trip asks for: File > Export TIFF, then the file into the same
## document, and the layer holds what the canvas held. The default document
## stores Oklab, a P3 one RGB in a wider gamut, and a linear one light rather
## than the curve, so each has its own conversion out and back in.
func test_an_exported_document_opens_as_the_canvas() -> void:
    var spaces := {"an Oklab document": SaColorSpace.oklab(), "a P3 document": SaColorSpace.display_p3()}
    spaces["a linear document"] = SaColorSpace.linear_srgb()
    for label: String in spaces:
        var space: SaColorSpace = spaces[label]
        var canvas := SaCanvas.new()
        canvas.canvas_size = Vector2i(300, 40)
        canvas.easel = SaEasel.create_default(canvas.canvas_size, null, space)
        canvas.add_child(canvas.easel)
        var document := canvas.document
        document.fill_layer(Color(0.8, 0.3, 0.1))
        var ramp := Image.create_empty(300, 20, false, Image.FORMAT_RGBA8)
        for x in 300:
            ramp.fill_rect(Rect2i(x, 0, 1, 20), Color(x / 299.0, 1.0 - x / 299.0, 0.35))
        SaImageImport.place(document, ramp, "Ramp", SaColorSpace.srgb())
        canvas.easel.request_composite()
        canvas.easel.process_pending_composite()
        # As an export reads it, the live colour rounded as a save rounds it.
        SaPictureFile.flush(canvas.easel)
        @warning_ignore("static_called_on_instance")
        var shown := SaExport.get_texture_image_float(canvas.easel.output)
        for bits: int in [32, 16]:
            var path := SaDataRoot.path("test_s29_document_%d.tif" % bits)
            _scratch.append(path)
            assert_eq(SaExportTiff.export(canvas.easel, path, bits), OK, "%s exports a %d-bit TIFF" % [label, bits])
            var layer := SaImageImport.open_into(document, path)
            assert_not_null(layer, "and the %d-bit file opens into it" % bits)
            if layer == null:
                continue
            var worst := 0.0
            for point: Vector2i in [Vector2i(3, 3), Vector2i(150, 10), Vector2i(299, 19), Vector2i(260, 35), Vector2i(10, 39)]:
                var want := shown.get_pixel(point.x, point.y)
                var got := _texel(layer, point.x, point.y)
                worst = maxf(
                    worst,
                    maxf(maxf(absf(want.r - got.r), absf(want.g - got.g)), maxf(absf(want.b - got.b), absf(want.a - got.a)))
                )
            var bound := 1e-4 if bits == 32 else 5e-4
            assert_true(
                worst < bound,
                (
                    "%s at %d bits: the layer holds the canvas, the worst channel %s off"
                    % [label, bits, String.num_scientific(worst)]
                )
            )
        canvas.free()
    assert_true(_problems.is_empty(), "with nothing to report: %s" % [_problems])


func _texel(layer: SaLayer, x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var texture := layer.get_field(Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE))
    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(texture)
    return image.get_pixel(x % SaChunk.SIZE, y % SaChunk.SIZE)


# --- Building a TIFF by hand ---------------------------------------------------------


## A whole TIFF: *fields* by tag, each a list of values, and *strips* the pixel
## strips, whose offsets and byte counts are worked out here. Values that do
## not fit an entry go after the directory, and the strips after them.
func _tiff(fields: Dictionary, strips: Array, big: bool = false) -> PackedByteArray:
    var all: Dictionary = fields.duplicate()
    var counts: Array = []
    for strip: PackedByteArray in strips:
        counts.append(strip.size())
    all[273] = counts.duplicate()
    all[279] = counts
    var tags: Array = all.keys()
    tags.sort()
    var at := 8 + 2 + tags.size() * 12 + 4
    var placed := {}
    for tag: int in tags:
        var length := (all[tag] as Array).size() * (4 if LONG_TAGS.has(tag) else 2)
        if length > 4:
            placed[tag] = at
            at += length
    var offsets: Array = []
    for strip: PackedByteArray in strips:
        offsets.append(at)
        at += strip.size()
    all[273] = offsets

    var out := ("MM" if big else "II").to_ascii_buffer()
    _put(out, 42, 2, big)
    _put(out, 8, 4, big)
    _put(out, tags.size(), 2, big)
    for tag: int in tags:
        var values: Array = all[tag]
        var width := 4 if LONG_TAGS.has(tag) else 2
        _put(out, tag, 2, big)
        _put(out, 4 if width == 4 else 3, 2, big)
        _put(out, values.size(), 4, big)
        if placed.has(tag):
            _put(out, placed[tag], 4, big)
            continue
        # Left-justified in its four bytes, which is where either byte order
        # looks for a value shorter than the field.
        var field := PackedByteArray()
        for value: int in values:
            _put(field, value, width, big)
        while field.size() < 4:
            field.append(0)
        out.append_array(field)
    _put(out, 0, 4, big)
    for tag: int in tags:
        if placed.has(tag):
            for value: int in all[tag]:
                _put(out, value, 4 if LONG_TAGS.has(tag) else 2, big)
    for strip: PackedByteArray in strips:
        out.append_array(strip)
    return out


func _put(into: PackedByteArray, value: int, width: int, big: bool) -> void:
    for i in width:
        var shift := 8 * (width - 1 - i) if big else 8 * i
        into.append((value >> shift) & 0xFF)


## *samples* with TIFF's horizontal differencing applied, each the difference
## from the same sample one pixel left, wrapping at *mask*, rows of *width*
## pixels of *per_pixel* samples.
func _differenced(samples: PackedInt64Array, width: int, per_pixel: int, mask: int) -> PackedInt64Array:
    var out := samples.duplicate()
    var row := width * per_pixel
    for i in samples.size():
        if i % row >= per_pixel:
            out[i] = (samples[i] - samples[i - per_pixel]) & mask
    return out
