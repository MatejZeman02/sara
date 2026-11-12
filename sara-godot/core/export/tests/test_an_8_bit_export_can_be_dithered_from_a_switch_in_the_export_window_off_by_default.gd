## An eight-bit export can be dithered, and is not unless asked.
##
## A painter, 2026-10-09: "8 bit export should not export dithered by
## default, but optional on export window." A mid grey of 0.5 sits on the
## middle of a step, so any paint at all over it, however faint, rounds a
## texel to the step below, and a soft edge less than a step deep lands as a
## hard edge one step off. Dithered, the rounding moves by a fixed pattern of
## up to half a step, so the two halves read the same in the mean.
##
## These export through the doors a painter's export takes and read the files
## back, and hold the switch off to the bytes the export wrote before it.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

## The field the first case lays its veil over half of, its halves either side
## of a line that is not a cell boundary, so the step is the veil's alone.
const FIELD := Vector2i(384, 96)
const VEIL_FROM: int = 192
## Columns either side of the veil's edge left out of each half's mean.
const MARGIN: int = 8

## The ramp the second case exports, wider than two cells so the walk meets
## itself twice, and every channel moving by a fraction of a step a column.
const RAMP := Vector2i(600, 40)

## What exporting the ramp wrote before this row, taken by a scratch suite on
## 43-features-19 at `4e8b6f5d0`, before the switch existed, with the metadata
## `SaExportMetadata.new()` gives. The PNG's whole file, its decoded bytes, and
## the JPEG at a quality of 0.9. The kernel's sum is a single correctly rounded
## add on every Vulkan card and the narrowing is the CPU's, so these hold on
## any machine.
const PNG_BEFORE := "3464bd3981abb5a16945dc8ba3ae4f10"
const PNG_PIXELS_BEFORE := "f339dd620569d95c919b3cb0608b8570"
const JPG_BEFORE := "256bee59152f19150224d3abd100f2e7"
## The PNG carries the program and its version in a text chunk, so the pin
## holds the version it was taken under rather than following every release.
const SOFTWARE_AT_THE_PIN := "Sara 0.19.1"

var _easel: SaEasel = null
var _written: PackedStringArray = []


func after_each() -> void:
    if _easel != null:
        _easel.free()
        _easel = null
    for path: String in _written:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    _written.clear()


## A file name under the data root, removed after the case.
func _path(file_name: String) -> String:
    var path := SaDataRoot.path(file_name)
    _written.append(path)
    return path


## A grey of 0.5 over the whole field, and black at an alpha of 1e-6 laid over
## its right half on a layer of its own, which the compositor blends to
## 0.4999995 there.
func _veiled_field() -> SaEasel:
    var easel := SaEasel.create_default(FIELD, null, SaColorSpace.srgb())
    var doc := easel.document
    doc.fill_layer(Color(0.5, 0.5, 0.5, 1.0))
    var veil := SaLayerOps.new(doc).add()
    doc.selection.select_rect(Rect2i(VEIL_FROM, 0, FIELD.x - VEIL_FROM, FIELD.y))
    doc.fill_layer(Color(0.0, 0.0, 0.0, 1e-6), veil)
    doc.selection.deselect()
    easel.request_composite()
    easel.process_pending_composite()
    return easel


## The mean red byte of *image* over the columns from *from* to *to*, every row.
func _mean(image: Image, from: int, to: int) -> float:
    var sum := 0.0
    for y in image.get_height():
        for x in range(from, to):
            sum += image.get_pixel(x, y).r8
    return sum / float((to - from) * image.get_height())


## The mean of the half left of the veil and of the half under it.
func _halves(image: Image) -> Vector2:
    return Vector2(_mean(image, MARGIN, VEIL_FROM - MARGIN), _mean(image, VEIL_FROM + MARGIN, FIELD.x - MARGIN))


## How many of *image*'s texels read *byte* in red.
func _count(image: Image, byte: int) -> int:
    var found := 0
    for y in image.get_height():
        for x in image.get_width():
            if image.get_pixel(x, y).r8 == byte:
                found += 1
    return found


func _ramp() -> SaTexture:
    var texture := SaTexture.new(RAMP)
    var texels := PackedFloat32Array()
    for y in RAMP.y:
        for x in RAMP.x:
            var across := float(x) / float(RAMP.x - 1)
            var down := float(y) / float(RAMP.y - 1)
            texels.append_array(
                [0.3 + 0.02 * across + 0.001 * down, 0.5 + 0.004 * across, 0.7 - 0.03 * across * down, 1.0 - 0.01 * down]
            )
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, texels.to_byte_array())
    return texture


## A flat field of *value* at *size*.
func _flat(size: Vector2i, value: float) -> SaTexture:
    var texture := SaTexture.new(size)
    texture.clear(Color(value, value, value, 1.0))
    return texture


func _md5(bytes: PackedByteArray) -> String:
    var context := HashingContext.new()
    context.start(HashingContext.HASH_MD5)
    context.update(bytes)
    return context.finish().hex_encode()


func test_a_veil_of_alpha_1e_6_over_half_of_a_mid_grey_is_a_whole_level_off_undithered_and_none_dithered() -> void:
    _easel = _veiled_field()
    var plain := _path("veil_plain.png")
    var dithered := _path("veil_dithered.png")
    assert_eq(SaExport.export_png(_easel, plain, 8), OK, "the PNG is written with the check off")
    assert_eq(SaExport.export_png(_easel, dithered, 8, false, SaGamutMapping.CLIP, false, true), OK, "and with it on")

    var off := Image.load_from_file(plain)
    var halves := _halves(off)
    assert_eq(halves.x, 128.0, "off, the bare grey is 128 throughout")
    assert_eq(halves.y, 127.0, "and the veiled half 127 throughout")
    assert_eq(halves.x - halves.y, 1.0, "a whole level apart, %s and %s" % [halves.x, halves.y])

    var on := Image.load_from_file(dithered)
    halves = _halves(on)
    assert_true(
        absf(halves.x - halves.y) < 0.25, "on, the halves' means are within a quarter level, %s and %s" % [halves.x, halves.y]
    )
    assert_true(absf(halves.x - 127.5) < 0.25, "and both stand at the grey's own 127.5, %s" % halves.x)
    var low := _count(on, 127)
    var high := _count(on, 128)
    assert_eq(low + high, FIELD.x * FIELD.y, "every texel is one of the two levels either side, never further")
    assert_true(mini(low, high) * 3 > FIELD.x * FIELD.y, "and each holds a fair share, %d and %d" % [low, high])
    assert_eq(on.get_pixel(10, 10).r8, on.get_pixel(10, 10).b8, "one number moves all three channels, so the grey stays grey")


func test_a_jpg_and_an_openraster_file_take_the_dither_too() -> void:
    _easel = _veiled_field()
    var plain := _path("veil_plain.jpg")
    var dithered := _path("veil_dithered.jpg")
    assert_eq(SaExport.export_jpg(_easel, plain, 1.0), OK, "the JPG is written with the check off")
    assert_eq(
        SaExport.export_jpg(_easel, dithered, 1.0, false, SaGamutMapping.CLIP, false, Color.WHITE, true), OK, "and with it on"
    )
    var halves := _halves(Image.load_from_file(plain))
    assert_true(halves.x - halves.y > 0.75, "off, the JPG's halves are a level apart, %s and %s" % [halves.x, halves.y])
    halves = _halves(Image.load_from_file(dithered))
    assert_true(absf(halves.x - halves.y) < 0.25, "on, within a quarter level, %s and %s" % [halves.x, halves.y])

    var ora := _path("veil_dithered.ora")
    # OpenRaster is the image formats module's, so its registries are held here.
    var formats := Fixtures.make_picture_registries()
    assert_eq(SaImageImport.formats(), formats.image_formats, "the formats asked are the ones these registries installed")
    assert_eq(Fixtures.export_through(&"ora", _easel, ora, 8, true), OK, "the OpenRaster file is written dithered")
    var reader := ZIPReader.new()
    assert_eq(reader.open(ora), OK, "and opens as a zip")
    var merged := Image.new()
    merged.load_png_from_buffer(reader.read_file("mergedimage.png"))
    reader.close()
    halves = _halves(merged)
    assert_true(
        absf(halves.x - halves.y) < 0.25, "its merged picture's halves within a quarter level, %s and %s" % [halves.x, halves.y]
    )


func test_two_dithered_exports_are_the_same_to_the_bit_and_an_undithered_one_is_the_bytes_before_this_row() -> void:
    var texture := _ramp()
    var space := SaColorSpace.srgb()
    var none := PackedFloat32Array()
    var first := _path("ramp_first.png")
    var second := _path("ramp_second.png")
    var plain := _path("ramp_plain.png")
    var meta := SaExportMetadata.new()
    meta.software = SOFTWARE_AT_THE_PIN
    assert_eq(SaExport.export_png_texture(texture, space, first, 8, none, SaGamutMapping.CLIP, meta, null, true), OK, "first")
    assert_eq(SaExport.export_png_texture(texture, space, second, 8, none, SaGamutMapping.CLIP, meta, null, true), OK, "second")
    assert_eq(SaExport.export_png_texture(texture, space, plain, 8, none, SaGamutMapping.CLIP, meta), OK, "plain")

    var first_bytes := FileAccess.get_file_as_bytes(first)
    assert_true(first_bytes.size() > 0, "the dithered PNG holds something")
    assert_true(first_bytes == FileAccess.get_file_as_bytes(second), "two dithered exports of one picture are one file")
    assert_eq(FileAccess.get_md5(plain), PNG_BEFORE, "the undithered PNG is the file the export wrote before this row")
    assert_eq(_md5(Image.load_from_file(plain).get_data()), PNG_PIXELS_BEFORE, "to its decoded bytes")
    assert_true(FileAccess.get_md5(first) != PNG_BEFORE, "and the dithered one is another")

    var jpg := _path("ramp_plain.jpg")
    assert_eq(SaExport.export_jpg_texture(texture, space, jpg, 0.9), OK, "the JPG is written with the check off")
    assert_eq(FileAccess.get_md5(jpg), JPG_BEFORE, "and is the JPG the export wrote before this row")


func test_the_pattern_is_keyed_to_the_picture_so_the_cells_meet_with_no_seam() -> void:
    var cell := SaChunk.SIZE
    var whole := SaExportGamut.encoded_byte_image(
        _flat(RAMP, 0.5), null, null, PackedFloat32Array(), SaGamutMapping.CLIP, null, true
    )
    assert_eq(SaExportGamut.cells_visited, 3, "the 600 pixels walk as three cells")

    var repeats := 0
    for y in RAMP.y:
        for x in cell:
            if whole.get_pixel(x, y).r8 == whole.get_pixel(x + cell, y).r8:
                repeats += 1
    assert_true(
        repeats * 4 < cell * RAMP.y * 3,
        "the second cell is not a copy of the first, %d of %d texels alike" % [repeats, cell * RAMP.y]
    )

    # A cell on its own, told where it sits, is the whole picture's texels
    # there, which is how an OpenRaster layer's tile meets the merged picture.
    var alone_texture := _flat(Vector2i(cell, RAMP.y), 0.5)
    var at := Vector2i(cell, 0)
    var alone := SaExportGamut.encoded_byte_image(
        alone_texture, null, null, PackedFloat32Array(), SaGamutMapping.CLIP, null, true, at
    )
    assert_true(
        alone.get_data() == whole.get_region(Rect2i(at, Vector2i(cell, RAMP.y))).get_data(),
        "a tile told it starts at %s is the picture's own pixels there" % at
    )
    var mean_first := _mean(whole, 0, cell)
    var mean_second := _mean(whole, cell, 2 * cell)
    assert_true(
        absf(mean_first - mean_second) < 0.25,
        "and the cells either side of the boundary read alike, %s and %s" % [mean_first, mean_second]
    )


## The running app's first dithered export had one texel of alpha 254 in a
## picture with no transparency, an opaque texel the composite left a hair
## under 1 that the dither moved below the step. The alpha is rounded alone.
func test_the_alpha_is_rounded_as_it_always_was() -> void:
    var none := PackedFloat32Array()
    var near := SaTexture.new(RAMP)
    near.clear(Color(0.5, 0.5, 0.5, 0.99999994))
    var opaque := SaExportGamut.encoded_byte_image(near, null, null, none, SaGamutMapping.CLIP, null, true)
    assert_eq(opaque.detect_alpha(), Image.ALPHA_NONE, "an opaque texel a hair under 1 stays 255 at every pixel")
    var half := SaTexture.new(RAMP)
    half.clear(Color(0.2, 0.2, 0.2, 0.5))
    var bytes := SaExportGamut.encoded_byte_image(half, null, null, none, SaGamutMapping.CLIP, null, true).get_data()
    var alphas := {}
    for i in range(3, bytes.size(), 4):
        alphas[bytes[i]] = true
    assert_eq(alphas.keys(), [128], "and a half alpha is 128 at every pixel, as undithered")


func test_sixteen_bits_never_dithers() -> void:
    var texture := _ramp()
    var space := SaColorSpace.srgb()
    var none := PackedFloat32Array()
    var meta := SaExportMetadata.new()
    var plain := _path("ramp_16_plain.png")
    var asked := _path("ramp_16_asked.png")
    assert_eq(SaExport.export_png_texture(texture, space, plain, 16, none, SaGamutMapping.CLIP, meta), OK, "plain")
    assert_eq(SaExport.export_png_texture(texture, space, asked, 16, none, SaGamutMapping.CLIP, meta, null, true), OK, "asked")
    assert_eq(FileAccess.get_md5(asked), FileAccess.get_md5(plain), "a sixteen-bit PNG asked to dither is the one that was not")
