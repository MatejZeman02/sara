## The predefined tip loader: a PNG and a GBR become the same coverage
## mask.
##
## **Every fixture is written by this file rather than committed.** A binary in
## the tree is a file nobody can read in a diff, and a GBR is 28 bytes of header
## that the loader is being tested on: writing it here means the test says what
## the format is, in the same place it says what the loader should do with it.
## They go to `user://`, which the offscreen runner points at the checkout's own
## gitignored `scratch/`.
extends "res://tests/test_framework.gd"

## `upload` needs a RenderingDevice. Everything above it is arithmetic and would
## run without one, but a suite is skipped or run whole.
const REQUIRES_GPU := true

const TipImage = preload("res://core/api/tip/sa_tip_image.gd")
const GihPipe = preload("res://core/api/tip/sa_gih_pipe.gd")

static var scratch_png_path: String = SaDataRoot.path("test_tip.png")
static var scratch_png_alpha_path: String = SaDataRoot.path("test_tip_alpha.png")
static var scratch_png_colour_path: String = SaDataRoot.path("test_tip_colour.png")
static var scratch_gbr_v1_path: String = SaDataRoot.path("test_tip_v1.gbr")
static var scratch_gbr_v2_path: String = SaDataRoot.path("test_tip_v2.gbr")
static var scratch_gbr_rgba_path: String = SaDataRoot.path("test_tip_rgba.gbr")
static var scratch_abr_path: String = SaDataRoot.path("test_tip.abr")
static var scratch_gih_path: String = SaDataRoot.path("test_pipe.gih")


func after_each() -> void:
    for path: String in [
        scratch_png_path,
        scratch_png_alpha_path,
        scratch_png_colour_path,
        scratch_gbr_v1_path,
        scratch_gbr_v2_path,
        scratch_gbr_rgba_path,
        scratch_abr_path,
        scratch_gih_path
    ]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Four texels: black, white, mid grey and black again, all opaque. Black is
## full coverage under `(1 - red) * alpha` and white is none, which is the
## polarity every brush tip ever drawn assumes.
func _write_png(path: String, with_alpha: bool) -> void:
    var image := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
    image.set_pixel(0, 0, Color(0.0, 0.0, 0.0, 1.0))
    image.set_pixel(1, 0, Color(1.0, 1.0, 1.0, 1.0))
    image.set_pixel(0, 1, Color(0.5, 0.5, 0.5, 1.0))
    image.set_pixel(1, 1, Color(0.0, 0.0, 0.0, 0.5 if with_alpha else 1.0))
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(image.save_png_to_buffer())
    file.close()


func _be(value: int) -> PackedByteArray:
    var out := PackedByteArray()
    out.append((value >> 24) & 0xFF)
    out.append((value >> 16) & 0xFF)
    out.append((value >> 8) & 0xFF)
    out.append(value & 0xFF)
    return out


## A GBR by hand, which is the point: the header is the thing under test.
##
## *depth* 1 writes coverage bytes and *depth* 4 writes RGBA whose alpha is the
## coverage and whose colour is deliberately wrong, so a loader reading the red
## channel by mistake fails rather than passing by luck.
func _write_gbr(path: String, version: int, spacing: int, depth: int, coverage: PackedByteArray) -> void:
    var name := "fixture".to_utf8_buffer()
    var header_size := (20 if version == 1 else 28) + name.size() + 1
    var bytes := PackedByteArray()
    bytes.append_array(_be(header_size))
    bytes.append_array(_be(version))
    bytes.append_array(_be(2))
    bytes.append_array(_be(2))
    bytes.append_array(_be(depth))
    if version > 1:
        bytes.append_array(_be(0x47494D50))
        bytes.append_array(_be(spacing))
    bytes.append_array(name)
    bytes.append(0)
    for value in coverage:
        if depth == 1:
            bytes.append(value)
        else:
            # Red, green and blue are a colour the mask must not be read from.
            bytes.append_array(PackedByteArray([200, 30, 90, value]))
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(bytes)
    file.close()


## A black source texel is 1.0 and a white one 0.0.
func test_a_png_loads_as_coverage_with_black_full_and_white_empty() -> void:
    _write_png(scratch_png_path, false)
    var tip: TipImage.Tip = TipImage.load_from(scratch_png_path)

    assert_true(tip.ok(), "The PNG loaded: %s" % tip.error)
    assert_eq(tip.size, Vector2i(2, 2), "at the size it was written")
    assert_eq(tip.mask.size(), 4, "with one coverage value per texel")
    assert_almost_eq(tip.at(0, 0), 1.0, 1e-5, "Black is full coverage")
    assert_almost_eq(tip.at(1, 0), 0.0, 1e-5, "and white is none")
    assert_almost_eq(tip.at(0, 1), 0.5, 0.01, "and a mid grey is half, which is (1 - red)")


## Alpha multiplies the rule rather than replacing it, so a soft-edged tip drawn
## on transparency loads the way it looks.
func test_a_png_with_alpha_multiplies_it_in() -> void:
    _write_png(scratch_png_alpha_path, true)
    var tip: TipImage.Tip = TipImage.load_from(scratch_png_alpha_path)

    assert_true(tip.ok(), "The PNG loaded: %s" % tip.error)
    assert_almost_eq(tip.at(1, 1), 0.5, 0.01, "Black at half alpha is half coverage, which is (1 - red) * alpha")
    assert_almost_eq(tip.at(0, 0), 1.0, 1e-5, "and an opaque black texel beside it is still full")


## A picture that carries colour is read the other way round: its alpha is
## the coverage and its own luminance is the second channel.
##
## **Red beside blue, both opaque, which is the case the two rules disagree
## about.** Under the greyscale rule the red texel would be nothing and the blue
## one full, and under this one both are the whole texel's coverage.
func _write_colour_png(path: String) -> void:
    var image := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
    image.set_pixel(0, 0, Color(1.0, 0.0, 0.0, 1.0))
    image.set_pixel(1, 0, Color(0.0, 0.0, 1.0, 1.0))
    image.set_pixel(0, 1, Color(1.0, 0.0, 0.0, 0.25))
    image.set_pixel(1, 1, Color(0.5, 0.5, 0.0, 1.0))
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(image.save_png_to_buffer())
    file.close()


## The mask is the alpha, texel for texel, whatever the picture's own colour is.
func test_a_colour_png_takes_its_alpha_for_coverage() -> void:
    _write_colour_png(scratch_png_colour_path)
    var tip: TipImage.Tip = TipImage.load_from(scratch_png_colour_path)

    assert_true(tip.ok(), "The PNG loaded: %s" % tip.error)
    assert_true(tip.colourful, "and it is read as a picture that carries colour")
    assert_almost_eq(tip.at(0, 0), 1.0, 1e-5, "An opaque red texel is full coverage, which (1 - red) would not say")
    assert_almost_eq(tip.at(1, 0), 1.0, 1e-5, "and so is the opaque blue beside it")
    assert_almost_eq(tip.at(0, 1), 0.25, 1e-2, "and a quarter-alpha red one is a quarter")


## The second channel is the picture's own luminance, which is what the dab
## kernel shifts the colour by.
func test_a_colour_png_carries_its_luminance_as_the_second_channel() -> void:
    _write_colour_png(scratch_png_colour_path)
    var tip: TipImage.Tip = TipImage.load_from(scratch_png_colour_path)

    assert_eq(tip.lightness.size(), 4, "one lightness per texel")
    assert_almost_eq(tip.lightness_at(0, 0), 0.2126, 1e-2, "red is the red weight of Rec. 709")
    assert_almost_eq(tip.lightness_at(1, 0), 0.0722, 1e-2, "and blue is its blue one")
    assert_almost_eq(tip.lightness_at(1, 1), 0.4639, 1e-2, "and half red over half green is the sum of the two")


## A grey tip carries no colour, so its second channel is the neutral one and
## the kernel's shift is exactly nought. This is what keeps every image tip
## Sara had before the unit painting its own texels.
func test_a_grey_png_has_a_neutral_lightness_channel() -> void:
    _write_png(scratch_png_path, false)
    var tip: TipImage.Tip = TipImage.load_from(scratch_png_path)

    assert_false(tip.colourful, "Black, white and grey texels are a mask and not a picture")
    assert_eq(tip.lightness.size(), 4, "and it still carries the channel")
    for i in 4:
        assert_almost_eq(tip.lightness[i], TipImage.NEUTRAL_LIGHTNESS, 1e-6, "at mid grey, texel %d" % i)


## No `brush_spacing` chunk means the loader's stated default rather than zero,
## which would be a brush that stamps every pixel of every stroke.
func test_a_png_without_a_spacing_chunk_takes_the_default() -> void:
    _write_png(scratch_png_path, false)
    var tip: TipImage.Tip = TipImage.load_from(scratch_png_path)

    assert_almost_eq(tip.spacing, TipImage.SPACING_WHEN_UNSTATED, 1e-6, "0.25, the spacing a silent file gets")
    assert_eq(tip.tip_name, "test_tip", "and the file's own base name when the file names nothing")


## The second half of the Done-when for the GBR: the spacing read out of the
## file, and the polarity that makes a round tip round.
func test_a_gbr_reads_its_header_and_its_coverage() -> void:
    _write_gbr(scratch_gbr_v2_path, 2, 40, 1, PackedByteArray([255, 0, 128, 255]))
    var tip: TipImage.Tip = TipImage.load_from(scratch_gbr_v2_path)

    assert_true(tip.ok(), "The GBR loaded: %s" % tip.error)
    assert_eq(tip.size, Vector2i(2, 2), "at the size its header says")
    assert_almost_eq(tip.spacing, 0.4, 1e-6, "A spacing of 40 on disk is 0.4 of the tip")
    assert_almost_eq(tip.at(0, 0), 1.0, 1e-5, "A byte of 255 is full coverage, which is GIMP's polarity")
    assert_almost_eq(tip.at(1, 0), 0.0, 1e-5, "and a byte of 0 is none")
    assert_almost_eq(tip.at(0, 1), 0.502, 0.01, "and 128 is half")
    assert_eq(tip.tip_name, "fixture", "The name between the header and the pixels is read")


## Version 1 has no spacing field at all, so the name starts eight bytes earlier
## and the spacing is GIMP's default. Getting this wrong reads the name as
## rubbish and the spacing out of the name's first four bytes.
func test_a_version_one_gbr_has_no_spacing_field() -> void:
    _write_gbr(scratch_gbr_v1_path, 1, 0, 1, PackedByteArray([255, 255, 0, 0]))
    var tip: TipImage.Tip = TipImage.load_from(scratch_gbr_v1_path)

    assert_true(tip.ok(), "The version 1 GBR loaded: %s" % tip.error)
    assert_almost_eq(tip.spacing, TipImage.SPACING_WHEN_UNSTATED, 1e-6, "Version 1 takes 0.25 because the field is not there")
    assert_eq(tip.tip_name, "fixture", "and the name starts where the shorter header ends")
    assert_almost_eq(tip.at(0, 0), 1.0, 1e-5, "with the coverage read from the right offset")


## A four-byte GBR is RGBA and the alpha is the mask. The fixture's colour is
## deliberately not the coverage, so a loader reading red instead fails here.
## The alpha is the coverage and the colour is the lightness, which is the
## reading this depth is given: the three bytes were "a colour Sara has
## nowhere to put" and are now the second channel.
func test_an_rgba_gbr_takes_its_alpha_for_coverage_and_its_colour_for_lightness() -> void:
    _write_gbr(scratch_gbr_rgba_path, 2, 25, 4, PackedByteArray([255, 0, 64, 255]))
    var tip: TipImage.Tip = TipImage.load_from(scratch_gbr_rgba_path)

    assert_true(tip.ok(), "The RGBA GBR loaded: %s" % tip.error)
    assert_true(tip.colourful, "and it is read as a picture that carries colour")
    assert_almost_eq(tip.at(0, 0), 1.0, 1e-5, "Alpha 255 is full coverage")
    assert_almost_eq(tip.at(1, 0), 0.0, 1e-5, "and alpha 0 is none, though the red beside it is 200")
    assert_almost_eq(tip.at(0, 1), 0.251, 0.01, "and alpha 64 is a quarter")
    # Every texel of the fixture carries the same colour, (200, 30, 90), so the
    # channel says the same thing in all four.
    var expected := 0.2126 * float(200) / 255.0 + 0.7152 * float(30) / 255.0 + 0.0722 * float(90) / 255.0
    assert_almost_eq(tip.lightness_at(0, 0), expected, 1e-3, "and its colour is the lightness channel")
    assert_almost_eq(tip.lightness_at(1, 1), expected, 1e-3, "in every texel")


## A depth-one GBR is a mask with no colour, so its lightness channel is the
## neutral one.
func test_a_depth_one_gbr_has_a_neutral_lightness_channel() -> void:
    _write_gbr(scratch_gbr_v2_path, 2, 25, 1, PackedByteArray([255, 0, 128, 64]))
    var tip: TipImage.Tip = TipImage.load_from(scratch_gbr_v2_path)

    assert_false(tip.colourful, "One byte per texel is a mask")
    for i in 4:
        assert_almost_eq(tip.lightness[i], TipImage.NEUTRAL_LIGHTNESS, 1e-6, "mid grey, texel %d" % i)


## The refusal the spec asks for by name: told, not silent and not a crash.
func test_a_brush_collection_is_refused_by_name() -> void:
    FileAccess.open(scratch_abr_path, FileAccess.WRITE).store_string("not really a brush collection")
    var tip: TipImage.Tip = TipImage.load_from(scratch_abr_path)

    assert_false(tip.ok(), "An .abr is not a tip")
    assert_true(tip.error.contains("collection"), "and the refusal says why: %s" % tip.error)
    assert_true(tip.error.contains("test_tip.abr"), "naming the file, so a painter knows which one")
    assert_eq(tip.mask.size(), 0, "and it carries no mask to be used by mistake")


## An extension nothing reads is refused too, and differently, so the message
## tells a painter whether the format is deferred or simply wrong.
func test_an_unknown_extension_is_refused_differently() -> void:
    var tip: TipImage.Tip = TipImage.load_from(SaDataRoot.path("tip.jpeg"))

    assert_false(tip.ok(), "A .jpeg is not a brush tip")
    assert_true(tip.error.contains(".png"), "and the refusal names what is read instead: %s" % tip.error)


## A GBR whose header promises more pixels than the file holds is refused rather
## than read past the end, which is the failure a hand-written binary format
## invites and the one that would corrupt memory in C.
func test_a_truncated_gbr_is_refused_rather_than_read_past() -> void:
    _write_gbr(scratch_gbr_v2_path, 2, 25, 1, PackedByteArray([255, 255, 255, 255]))
    var bytes := FileAccess.get_file_as_bytes(scratch_gbr_v2_path)
    var file := FileAccess.open(scratch_gbr_v2_path, FileAccess.WRITE)
    file.store_buffer(bytes.slice(0, bytes.size() - 2))
    file.close()

    var tip: TipImage.Tip = TipImage.load_from(scratch_gbr_v2_path)
    assert_false(tip.ok(), "A short GBR is not a tip")
    assert_true(tip.error.contains("wants"), "and the refusal says how much was missing: %s" % tip.error)


## The upload, and the readback that proves it. `rd.texture_get_data` because a
## texture that was never written and a texture written wrong are the same
## object from the outside. **Two channels**, interleaved per texel: coverage
## in red and the tip's own lightness in green, which is the one texture the
## kernel's single sampler reads.
func test_the_mask_uploads_to_a_two_channel_texture_and_reads_back() -> void:
    _write_gbr(scratch_gbr_v2_path, 2, 25, 1, PackedByteArray([255, 0, 128, 64]))
    var tip: TipImage.Tip = TipImage.load_from(scratch_gbr_v2_path)
    var texture := TipImage.upload(tip)

    assert_not_null(texture, "The tip uploaded")
    assert_eq(texture.size, Vector2i(2, 2), "at the tip's own size, so one texture serves every stamp size")
    assert_eq(texture.format, RenderingDevice.DATA_FORMAT_R32G32_SFLOAT, "as coverage and lightness, two floats a texel")

    var data := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    assert_eq(data.size(), 32, "four texels of eight bytes")
    assert_almost_eq(data.decode_float(0), 1.0, 1e-5, "and the first texel's coverage is what went in")
    assert_almost_eq(data.decode_float(8), 0.0, 1e-5, "and so is the second's")
    assert_almost_eq(data.decode_float(24), 0.251, 0.01, "and the last's, which is what proves the whole array went")
    # A depth-one GBR carries no colour, so what the kernel reads beside each
    # coverage is the neutral one.
    assert_almost_eq(data.decode_float(4), TipImage.NEUTRAL_LIGHTNESS, 1e-5, "and a grey tip's lightness is mid grey")
    assert_almost_eq(data.decode_float(28), TipImage.NEUTRAL_LIGHTNESS, 1e-5, "in every texel")


## A refusal uploads to nothing rather than to an empty texture, which would be
## a tip that stamps nothing and reports no error anywhere.
func test_a_refusal_uploads_to_nothing() -> void:
    assert_null(TipImage.upload(TipImage.load_from(SaDataRoot.path("tip.abr"))), "A refused tip has no texture")
    assert_null(TipImage.upload(null), "and neither has nothing at all")


## CRC-32 the way PNG wants it, over a chunk's type and data.
##
## By hand because Godot offers none, and needed rather than optional: libpng
## rejects a chunk whose CRC does not match, so a fixture with four arbitrary
## bytes there would fail to decode at all and the test would pass for the wrong
## reason.
func _crc32(bytes: PackedByteArray) -> int:
    var crc := 0xFFFFFFFF
    for byte in bytes:
        crc ^= byte
        for _bit in 8:
            if crc & 1:
                crc = (crc >> 1) ^ 0xEDB88320
            else:
                crc >>= 1
    return crc ^ 0xFFFFFFFF


func _be_bytes(value: int) -> PackedByteArray:
    return PackedByteArray([(value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF])


## Splices a `tEXt` chunk in after the signature and the IHDR, which is where
## Krita writes one and where a decoder expects ancillary chunks.
func _write_png_with_text(path: String, key: String, value: String) -> void:
    _write_png(path, false)
    var bytes := FileAccess.get_file_as_bytes(path)
    # 8 signature bytes, then IHDR: 4 length, 4 type, 13 data, 4 CRC.
    var at := 8 + 4 + 4 + 13 + 4
    # Built as bytes rather than as a String with a `char(0)` in it: a GDScript
    # String cannot carry an embedded NUL and `to_ascii_buffer` drops it, which
    # leaves a chunk whose key and value nothing can tell apart.
    var payload := key.to_ascii_buffer()
    payload.append(0)
    payload.append_array(value.to_ascii_buffer())
    var chunk := PackedByteArray()
    chunk.append_array(_be_bytes(payload.size()))
    var typed := "tEXt".to_ascii_buffer()
    typed.append_array(payload)
    chunk.append_array(typed)
    chunk.append_array(_be_bytes(_crc32(typed)))
    var out := bytes.slice(0, at)
    out.append_array(chunk)
    out.append_array(bytes.slice(at, bytes.size()))
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(out)
    file.close()


## The half of the PNG path Godot's own decoder cannot reach: Krita writes the
## spacing and the name into text chunks and `Image` throws every ancillary
## chunk away, so a Krita tip that carries its own spacing loses it silently
## unless the bytes are read here.
func test_a_png_text_chunk_carries_the_spacing_and_the_name() -> void:
    _write_png_with_text(scratch_png_path, "brush_spacing", "0.35")
    var tip: TipImage.Tip = TipImage.load_from(scratch_png_path)

    assert_true(tip.ok(), "The PNG with a text chunk still decodes: %s" % tip.error)
    assert_almost_eq(tip.spacing, 0.35, 1e-5, "and its brush_spacing is read out of the chunk")
    assert_almost_eq(tip.at(0, 0), 1.0, 1e-5, "with the picture itself untouched by the splice")

    _write_png_with_text(scratch_png_alpha_path, "brush_name", "Krita Round")
    var named: TipImage.Tip = TipImage.load_from(scratch_png_alpha_path)
    assert_eq(named.tip_name, "Krita Round", "and a brush_name wins over the file's base name")
    assert_almost_eq(named.spacing, TipImage.SPACING_WHEN_UNSTATED, 1e-6, "while a file with no spacing keeps the default")


## A GBR as bytes rather than as a file, which is what a pipe needs: a `.gih`
## is one of these after another with nothing between them, so the fixture has
## to be able to build several at different sizes and concatenate them.
##
## *coverage* is read row major and is expected to be *width* by *height* long.
func _gbr_bytes(tip_name: String, width: int, height: int, spacing: int, coverage: PackedByteArray) -> PackedByteArray:
    var named := tip_name.to_utf8_buffer()
    var bytes := PackedByteArray()
    bytes.append_array(_be(28 + named.size() + 1))
    bytes.append_array(_be(2))
    bytes.append_array(_be(width))
    bytes.append_array(_be(height))
    bytes.append_array(_be(1))
    bytes.append_array(_be(0x47494D50))
    bytes.append_array(_be(spacing))
    bytes.append_array(named)
    bytes.append(0)
    bytes.append_array(coverage)
    return bytes


## A `.gih`: a name line, a parameter line, then the cells run together.
##
## Written here rather than committed for the reason every other fixture in this
## file is: the container is three lines of format and the test that says what
## it is stands beside the loader that reads it.
func _gih_bytes(pipe_name: String, parameters: String, cells: Array) -> PackedByteArray:
    var bytes := (pipe_name + "\n" + parameters + "\n").to_utf8_buffer()
    for cell: PackedByteArray in cells:
        bytes.append_array(cell)
    return bytes


func _flat(value: int, count: int) -> PackedByteArray:
    var out := PackedByteArray()
    out.resize(count)
    out.fill(value)
    return out


## A two-tip pipe answers both tips, their sizes,
## the rank and the placement.
func test_a_two_tip_gih_reads_both_its_tips_and_its_parasite() -> void:
    var cells := [
        _gbr_bytes("first", 2, 2, 20, PackedByteArray([255, 0, 128, 64])),
        _gbr_bytes("second", 3, 1, 20, PackedByteArray([255, 255, 0])),
    ]
    var line := "2 ncells:2 cellwidth:3 cellheight:2 step:20 dim:1 cols:1 rows:2 placement:constant rank0:2 sel0:incremental"
    var pipe: GihPipe.Pipe = GihPipe.read_bytes(_gih_bytes("Two tips", line, cells), "test_pipe.gih")

    assert_true(pipe.ok(), "The pipe read: %s" % pipe.error)
    assert_eq(pipe.pipe_name, "Two tips", "with the name off its first line")
    assert_eq(pipe.cell_count, 2, "and the count off the front of the parameter line")
    assert_eq(pipe.tips.size(), 2, "and that many tips actually read")
    assert_eq((pipe.tips[0] as TipImage.Tip).size, Vector2i(2, 2), "The first tip is the size its own header says")
    assert_eq((pipe.tips[1] as TipImage.Tip).size, Vector2i(3, 1), "and the second is its own size, not the first's")
    assert_eq(pipe.ranks, PackedInt32Array([2]), "rank0 is the tips in the one dimension")
    assert_eq(pipe.selections, PackedStringArray(["incremental"]), "and sel0 is what a dab advances by")
    assert_eq(pipe.placement, "constant", "and placement is the source image's grid, which is a separate field")
    assert_eq(String(pipe.parameters.get("cellwidth", "")), "3", "Every field of the line survives as written")
    assert_eq(String(pipe.parameters.get("step", "")), "20", "including the ones this reader has no opinion about")


## The tips are the same masks the single-tip reader gives, which is what proves
## the offset arithmetic: a second tip read at the wrong place still loads, and
## loads rubbish.
func test_every_tip_of_a_pipe_is_what_the_single_tip_reader_reads() -> void:
    var second := _gbr_bytes("second", 2, 2, 25, PackedByteArray([0, 64, 128, 255]))
    var cells := [_gbr_bytes("first", 2, 2, 20, PackedByteArray([255, 0, 128, 64])), second]
    var line := "2 ncells:2 dim:1 rank0:2 sel0:random placement:default"
    var pipe: GihPipe.Pipe = GihPipe.read_bytes(_gih_bytes("Pair", line, cells), "test_pipe.gih")

    assert_true(pipe.ok(), "The pipe read: %s" % pipe.error)
    var alone: TipImage.Tip = TipImage.load_bytes(second, "second.gbr")
    var inside: TipImage.Tip = pipe.tips[1]
    assert_true(alone.ok(), "and the same GBR alone loaded: %s" % alone.error)
    assert_eq(inside.mask, alone.mask, "The tip inside the pipe is the tip on its own, texel for texel")
    assert_eq(inside.tip_name, "second", "with the name out of its own header rather than the one before it")
    assert_almost_eq(inside.spacing, 0.25, 1e-6, "and its own spacing")
    assert_eq(pipe.placement, "default", "A placement of default is the other value the field may hold")


## Four tips, and a rank across two dimensions,
## which is where a reader that assumes one dimension quietly reads one number.
func test_a_four_tip_gih_reads_a_rank_in_each_dimension() -> void:
    var cells := []
    for index in 4:
        cells.append(_gbr_bytes("cell%d" % index, 2, 2, 20, _flat(index * 60, 4)))
    var line := "4 ncells:4 cellwidth:2 cellheight:2 dim:2 rank0:2 rank1:2 sel0:incremental sel1:angular placement:constant"
    var pipe: GihPipe.Pipe = GihPipe.read_bytes(_gih_bytes("Four", line, cells), "test_pipe.gih")

    assert_true(pipe.ok(), "The four-tip pipe read: %s" % pipe.error)
    assert_eq(pipe.tips.size(), 4, "with all four tips")
    assert_eq(pipe.dimension, 2, "indexed by two dimensions")
    assert_eq(pipe.ranks, PackedInt32Array([2, 2]), "whose ranks multiply to the count")
    assert_eq(pipe.selections, PackedStringArray(["incremental", "angular"]), "each with its own selection mode")
    for index in 4:
        var tip: TipImage.Tip = pipe.tips[index]
        assert_eq(tip.size, Vector2i(2, 2), "Tip %d is the size the cells were written at" % index)
        assert_almost_eq(tip.at(0, 0), float(index * 60) / 255.0, 0.01, "and carries its own coverage, in file order")


## A file that stops inside a tip is refused rather than read past the end, and
## the refusal names which tip it stopped in, so a painter knows the file is cut
## rather than that the format is wrong.
func test_a_truncated_gih_is_refused_naming_the_tip_it_stops_in() -> void:
    var cells := [
        _gbr_bytes("first", 2, 2, 20, PackedByteArray([255, 0, 128, 64])),
        _gbr_bytes("second", 2, 2, 20, PackedByteArray([255, 255, 255, 255])),
    ]
    var whole := _gih_bytes("Cut", "2 ncells:2 dim:1 rank0:2 sel0:incremental", cells)
    var pipe: GihPipe.Pipe = GihPipe.read_bytes(whole.slice(0, whole.size() - 3), "test_pipe.gih")

    assert_false(pipe.ok(), "A cut pipe is not a pipe")
    assert_true(pipe.error.contains("tip 2 of 2"), "and the refusal says where it stopped: %s" % pipe.error)
    assert_true(pipe.error.contains("test_pipe.gih"), "naming the file")
    assert_true(pipe.tips.is_empty(), "and carries no half a collection to be used by mistake")


## A file with no parameter line at all, which is the other half of truncated:
## the container itself is not there.
func test_a_gih_without_a_parameter_line_is_refused() -> void:
    var pipe: GihPipe.Pipe = GihPipe.read_bytes("Just a name\n".to_utf8_buffer(), "test_pipe.gih")
    assert_false(pipe.ok(), "A name and nothing else is not a pipe")
    assert_true(pipe.error.contains("parameter line"), "and the refusal says what is missing: %s" % pipe.error)

    var nameless: GihPipe.Pipe = GihPipe.read_bytes("no line breaks here".to_utf8_buffer(), "test_pipe.gih")
    assert_false(nameless.ok(), "and neither is one long line")
    assert_true(nameless.error.contains("name line"), "with its own reason: %s" % nameless.error)


## Every way the parameter line can be unreadable, each refused with the field
## named. A reader that guesses here paints the wrong picture per dab and says
## nothing, which is the failure this whole unit is split out to avoid.
func test_a_parameter_line_it_cannot_read_is_refused_with_the_reason() -> void:
    var cells := [_gbr_bytes("only", 2, 2, 20, PackedByteArray([255, 0, 128, 64]))]
    var reasons := {
        "ncells:1 dim:1 rank0:1": "number of tips",
        "1 ncells:2 dim:1 rank0:1": "ncells:2",
        "1 dim:1 rank0:1 sel0:sideways": "sel0:sideways",
        "1 dim:1 rank0:1 placement:diagonal": "placement:diagonal",
        "1 dim:9 rank0:1": "dim:9",
        "1 dim:1 rank0:many": "rank0",
        "1 dim:2 rank0:1": "rank1",
        "2 ncells:2 dim:2 rank0:1 rank1:1": "multiply",
        "1 dim:1 rank0:1 loose": "key:value",
        "0 ncells:0 dim:1 rank0:1": "needs at least one",
    }
    for line: String in reasons:
        var pipe: GihPipe.Pipe = GihPipe.read_bytes(_gih_bytes("Bad", line, cells), "test_pipe.gih")
        assert_false(pipe.ok(), 'The line "%s" is not one this reader understands' % line)
        assert_true(pipe.error.contains(reasons[line]), "and the refusal names %s: %s" % [reasons[line], pipe.error])


## The by-extension door, and the by-path one beside it, both the shape
## `SaTipImage` has.
func test_a_pipe_loads_from_a_path_and_a_non_pipe_is_refused_by_its_name() -> void:
    var cells := [_gbr_bytes("only", 2, 2, 20, PackedByteArray([255, 0, 128, 64]))]
    var file := FileAccess.open(scratch_gih_path, FileAccess.WRITE)
    file.store_buffer(_gih_bytes("One", "1 ncells:1 dim:1 rank0:1 sel0:constant", cells))
    file.close()

    var pipe: GihPipe.Pipe = GihPipe.load_from(scratch_gih_path)
    assert_true(pipe.ok(), "A pipe on disk loads: %s" % pipe.error)
    assert_eq(pipe.tips.size(), 1, "with its one tip")
    assert_eq(pipe.selections, PackedStringArray(["constant"]), "and a constant selection, which never advances")

    var wrong: GihPipe.Pipe = GihPipe.load_from(SaDataRoot.path("test_tip.gbr"))
    assert_false(wrong.ok(), "A .gbr is not a pipe")
    assert_true(wrong.error.contains(".gih"), "and the refusal names what a pipe is: %s" % wrong.error)


## The GBR reader's new half on its own: it reads at an offset and says how far
## it got, which is the only thing that lets a pipe find its second tip.
func test_a_gbr_read_at_an_offset_says_how_long_it_was() -> void:
    var first := _gbr_bytes("first", 2, 2, 20, PackedByteArray([255, 0, 128, 64]))
    var second := _gbr_bytes("second", 4, 1, 30, PackedByteArray([10, 20, 30, 40]))
    var both := first.duplicate()
    both.append_array(second)

    var head: TipImage.Tip = TipImage.gbr_at(both, 0, "both.gbr")
    assert_true(head.ok(), "The first GBR read: %s" % head.error)
    assert_eq(head.bytes_read, first.size(), "and reported its own whole length, header and pixels")

    var tail: TipImage.Tip = TipImage.gbr_at(both, head.bytes_read, "both.gbr")
    assert_true(tail.ok(), "The second read at the offset the first gave: %s" % tail.error)
    assert_eq(tail.size, Vector2i(4, 1), "at its own size")
    assert_eq(tail.tip_name, "second", "and its own name, which is what proves the offset reached the right header")
    assert_almost_eq(tail.at(3, 0), 40.0 / 255.0, 0.01, "with its own last texel")

    var past: TipImage.Tip = TipImage.gbr_at(both, both.size() - 4, "both.gbr")
    assert_false(past.ok(), "An offset past the last header is refused rather than read")


## Reading a pipe binds nothing. `SaTipImage`'s own door refuses a `.gih` by
## name, so a collection reaches a dab only through `SaBrushTipMask.load_pipe`.
func test_reading_a_pipe_does_not_make_the_tip_door_accept_one() -> void:
    var cells := [_gbr_bytes("only", 2, 2, 20, PackedByteArray([255, 0, 128, 64]))]
    var bytes := _gih_bytes("One", "1 ncells:1 dim:1 rank0:1 sel0:constant", cells)

    assert_true(GihPipe.read_bytes(bytes, "test_pipe.gih").ok(), "The pipe reader reads it")
    var refused: TipImage.Tip = TipImage.load_bytes(bytes, "test_pipe.gih")
    assert_false(refused.ok(), "and the tip door still refuses it")
    assert_true(refused.error.contains("Load Tip"), "with a sentence that sends it to Load Tip: %s" % refused.error)
    assert_null(TipImage.upload(refused), "and it uploads to nothing")
