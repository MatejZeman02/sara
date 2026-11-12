## An export carries the document's gamut.
##
## A painter's note: "Also intended display gamut should be saved to the document
## and into the pngs/jpgs/tiffs." Each document here is exported in each format and
## the file is read back by walking the format's own structure, a PNG's chunks and
## their CRCs and a JPEG's markers, and then decoded by the reader Godot ships,
## so a chunk written in the wrong place is a file that does not open rather
## than a number that happens to agree. The TIFF's half moved with its writer
## into the image formats module, as `test_a_tiff_carries_the_gamut.gd`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const RED := Color(1.0, 0.0, 0.0, 1.0)

## The ICC connection space's white in CIE xy, which the profiles adapt to.
const D50_XY := Vector2(0.345703, 0.358539)

## What libpng writes after every `IEND`, which no code of Sara's computed.
const IEND_CRC: int = 0xAE426082

const NAMED: Array[StringName] = [SaGamut.ID_SRGB, SaGamut.ID_DISPLAY_P3, SaGamut.ID_REC2020]


func _canvas_in(space: SaColorSpace) -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(16, 16)
    canvas.easel = SaEasel.create_default(canvas.canvas_size, null, space)
    canvas.add_child(canvas.easel)
    canvas.document.fill_layer(RED)
    canvas.easel.request_composite()
    canvas.easel.process_pending_composite()
    return canvas


func _cleanup(path: String) -> void:
    if FileAccess.file_exists(path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _u32_be(bytes: PackedByteArray, at: int) -> int:
    return (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3]


## A PNG's chunks in order: type, data, and whether the CRC after them is the one
## their bytes give.
static func _png_chunks(bytes: PackedByteArray) -> Array:
    var chunks: Array = []
    var at := 8
    while at + 12 <= bytes.size():
        var length := _u32_be(bytes, at)
        var typed := bytes.slice(at + 4, at + 8 + length)
        var crc := _u32_be(bytes, at + 8 + length)
        chunks.append({"type": typed.slice(0, 4).get_string_from_ascii(), "data": typed.slice(4), "crc": crc})
        at += 12 + length
    return chunks


static func _chunk_index(chunks: Array, type: String) -> int:
    for i in chunks.size():
        if chunks[i]["type"] == type:
            return i
    return -1


## A JPEG's markers up to the start of scan, and the profile its APP2 segments
## carry, joined.
static func _jpeg_read(bytes: PackedByteArray) -> Dictionary:
    var markers: Array = []
    var profile := PackedByteArray()
    var at := 2
    while at + 4 <= bytes.size() and bytes[at] == 0xFF:
        var marker := bytes[at + 1]
        markers.append(marker)
        if marker == 0xDA:
            break
        var length := (bytes[at + 2] << 8) | bytes[at + 3]
        var body := bytes.slice(at + 4, at + 2 + length)
        if marker == 0xE2 and body.slice(0, 12).get_string_from_ascii() == "ICC_PROFILE":
            profile.append_array(body.slice(14))
        at += 2 + length
    return {"markers": markers, "profile": profile}


# --- Every gamut in every format -------------------------------------------------


func test_every_named_gamut_reaches_every_format() -> void:
    for gamut_id: StringName in NAMED:
        var gamut := SaGamut.from_id(gamut_id)
        for coordinates: int in [SaColorSpace.Coordinates.RGB, SaColorSpace.Coordinates.OKLAB]:
            var space := SaColorSpace.srgb().with_gamut(gamut).with_coordinates(coordinates)
            var canvas := _canvas_in(space)
            var label := "%s in %s" % [gamut_id, SaColorSpace.coordinates_name(coordinates)]
            _check_png(canvas, gamut, label)
            _check_jpg(canvas, gamut, label)
            canvas.free()


func _check_png(canvas: SaCanvas, gamut: SaGamut, label: String, bits: int = 8) -> void:
    var path := SaDataRoot.path("test_a7_export.png")
    assert_eq(SaExport.export_png(canvas.easel, path, bits), OK, "%s exports a PNG" % label)
    var bytes := FileAccess.get_file_as_bytes(path)
    var chunks := _png_chunks(bytes)
    assert_eq(chunks[0]["type"], "IHDR", "%s: the header is still first" % label)
    assert_eq((chunks[0]["data"] as PackedByteArray)[8], bits, "%s: at %d bits a sample" % [label, bits])
    var cicp := _chunk_index(chunks, "cICP")
    var iccp := _chunk_index(chunks, "iCCP")
    var idat := _chunk_index(chunks, "IDAT")
    assert_true(cicp > 0 and iccp > 0 and cicp < idat and iccp < idat, "%s: cICP and iCCP come before the pixels" % label)
    assert_eq(_chunk_index(chunks, "sRGB"), -1, "%s: and no sRGB chunk contradicts them" % label)
    for chunk: Dictionary in chunks:
        var typed: PackedByteArray = (chunk["type"] as String).to_ascii_buffer()
        typed.append_array(chunk["data"])
        assert_eq(SaExportGamut.crc32(typed), chunk["crc"], "%s: %s carries the CRC its bytes give" % [label, chunk["type"]])
    assert_eq(chunks[chunks.size() - 1]["crc"], IEND_CRC, "%s: which is libpng's own CRC for IEND" % label)
    assert_eq(
        Array(chunks[cicp]["data"]),
        [SaExportGamut.CICP_PRIMARIES[gamut.id], 13, 0, 1],
        "%s: cICP names the primaries, the sRGB curve, RGB and full range" % label
    )
    var body: PackedByteArray = chunks[iccp]["data"]
    var name_end := body.find(0)
    assert_eq(body[name_end + 1], 0, "%s: the profile is zlib, method zero" % label)
    var profile := body.slice(name_end + 2).decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)
    assert_eq(profile, SaExportGamut.profile_for(gamut), "%s: iCCP inflates to the profile Sara ships" % label)

    var image := Image.new()
    assert_eq(image.load_png_from_buffer(bytes), OK, "%s: Godot's PNG reader opens it" % label)
    var pixel := image.get_pixel(8, 8)
    assert_almost_eq(pixel.r, 1.0, 0.004, "%s: a painted red is 255 in the file" % label)
    assert_almost_eq(pixel.g, 0.0, 0.004, "%s: with no green" % label)
    assert_eq(SaExportGamut.png_primaries_at(path), SaExportGamut.CICP_PRIMARIES[gamut.id], "%s: read back off the disk" % label)
    var opened := SaImageImport.space_for(path)
    assert_eq(opened.gamut().id, gamut.id, "%s: and Sara opens it as the gamut it names" % label)
    assert_eq(str(opened.transfer.id), str(SaTransferFunction.ID_SRGB), "%s: through the sRGB curve" % label)
    _cleanup(path)


func _check_jpg(canvas: SaCanvas, gamut: SaGamut, label: String) -> void:
    var path := SaDataRoot.path("test_a7_export.jpg")
    assert_eq(SaExport.export_jpg(canvas.easel, path), OK, "%s exports a JPEG" % label)
    var bytes := FileAccess.get_file_as_bytes(path)
    var read := _jpeg_read(bytes)
    var markers: Array = read["markers"]
    assert_true(markers.has(0xE2), "%s: an APP2 segment is there" % label)
    assert_true(markers.find(0xE2) < markers.find(0xDA), "%s: before the scan" % label)
    assert_eq(read["profile"], SaExportGamut.profile_for(gamut), "%s: holding the whole profile" % label)
    var image := Image.new()
    assert_eq(image.load_jpg_from_buffer(bytes), OK, "%s: Godot's JPEG reader opens it" % label)
    assert_true(image.get_pixel(8, 8).r > 0.95, "%s: and the red is red" % label)
    _cleanup(path)


# --- The same labels over sixteen bits ---------------------------


## wrote a PNG Sara encodes itself, and the audit was met over files it
## had not written. An unlabelled sixteen-bit P3
## picture is the wide-gamut failure the gamut chunk exists to stop, so every named gamut is
## walked again at sixteen bits with the same reader, chunk by chunk and CRC by
## CRC, and then opened by Godot's own decoder.
func test_every_named_gamut_reaches_the_sixteen_bit_files() -> void:
    for gamut_id: StringName in NAMED:
        var gamut := SaGamut.from_id(gamut_id)
        for coordinates: int in [SaColorSpace.Coordinates.RGB, SaColorSpace.Coordinates.OKLAB]:
            var space := SaColorSpace.srgb().with_gamut(gamut).with_coordinates(coordinates)
            var canvas := _canvas_in(space)
            var label := "%s in %s at 16 bits" % [gamut_id, SaColorSpace.coordinates_name(coordinates)]
            _check_png(canvas, gamut, label, 16)
            canvas.free()


## The ask in its own words: a Display P3 document written as a sixteen-bit PNG
## carries primaries 12 and transfer 13 in `cICP`, an `iCCP` beside it, and still
## opens.
func test_a_display_p3_document_at_sixteen_bits_names_its_gamut() -> void:
    var canvas := _canvas_in(SaColorSpace.display_p3())
    var png_path := SaDataRoot.path("test_e4_p3.png")
    assert_eq(SaExport.export_png(canvas.easel, png_path, 16), OK, "the P3 document exports at 16 bits")
    var bytes := FileAccess.get_file_as_bytes(png_path)
    var chunks := _png_chunks(bytes)
    var cicp := _chunk_index(chunks, "cICP")
    assert_true(cicp > 0, "a cICP chunk is there")
    if cicp > 0:
        assert_eq(Array(chunks[cicp]["data"]), [12, 13, 0, 1], "primaries 12, transfer 13, RGB, full range")
    assert_true(_chunk_index(chunks, "iCCP") > 0, "an iCCP chunk is there")
    var image := Image.new()
    assert_eq(image.load_png_from_buffer(bytes), OK, "Image.load_png_from_buffer still reads the labelled file")
    _cleanup(png_path)
    canvas.free()


## The splice's offset is a constant only because `IHDR` has one length. A header
## of any other length is not a PNG this may cut into, so it is handed back as it
## came rather than labelled at the wrong place.
func test_a_header_of_the_wrong_length_is_left_unlabelled() -> void:
    var bad := PackedByteArray(SaExportGamut.PNG_SIGNATURE)
    var typed := "IHDR".to_ascii_buffer()
    typed.resize(4 + 14)
    bad.append_array(PackedByteArray([0, 0, 0, 14]))
    bad.append_array(typed)
    bad.append_array(PackedByteArray([0, 0, 0, 0]))
    var named := SaExportGamut.png_with_gamut(bad, SaGamut.from_id(SaGamut.ID_DISPLAY_P3))
    assert_eq(named, bad, "a fourteen-byte IHDR is handed back untouched")


# --- What the files hold ---------------------------------------------------------


## The profiles say the gamut they are named for: every colourant is the gamut's
## primary adapted to D50 by Bradford, the way `SaColorSpace` adapts a white.
func test_each_profile_holds_the_primaries_of_its_gamut() -> void:
    for gamut_id: StringName in NAMED:
        var gamut := SaGamut.from_id(gamut_id)
        var profile := SaExportGamut.profile_for(gamut)
        assert_eq(_u32_be(profile, 0), profile.size(), "%s: the header's size is the file's" % gamut_id)
        assert_eq(profile.slice(36, 40).get_string_from_ascii(), "acsp", "%s: the signature is where ICC puts it" % gamut_id)
        assert_eq(profile[8], 2, "%s: version 2, which the readers iCCP is for can read" % gamut_id)
        assert_eq(profile.slice(12, 20).get_string_from_ascii(), "mntrRGB ", "%s: a display profile over RGB" % gamut_id)
        var adapted: Basis = SaColorSpace.adaptation(SaColorSpace.WHITE_D65, D50_XY) * gamut.rgb_to_xyz(SaColorSpace.WHITE_D65)
        var tags := {}
        for i in _u32_be(profile, 128):
            var at := 132 + i * 12
            tags[profile.slice(at, at + 4).get_string_from_ascii()] = _u32_be(profile, at + 4)
        var signatures := ["rXYZ", "gXYZ", "bXYZ"]
        for channel in 3:
            var at: int = tags[signatures[channel]]
            var unit := Vector3.ZERO
            unit[channel] = 1.0
            var wanted: Vector3 = adapted * unit
            for axis in 3:
                var raw := _u32_be(profile, at + 8 + axis * 4)
                var value := float(raw - (1 << 32) if raw >= (1 << 31) else raw) / 65536.0
                assert_almost_eq(value, wanted[axis], 0.001, "%s: %s axis %d" % [gamut_id, signatures[channel], axis])


## A gamut Sara ships no profile for is written unlabelled rather than under a
## wrong name, and so is a document that never declared a space.
func test_a_gamut_with_no_profile_is_written_unlabelled() -> void:
    var path := SaDataRoot.path("test_a7_unlabelled.png")
    for space: SaColorSpace in [SaColorSpace.acescg(), SaColorSpace.unspecified()]:
        var canvas := _canvas_in(space)
        assert_eq(SaExport.export_png(canvas.easel, path), OK, "%s exports" % space.id)
        var chunks := _png_chunks(FileAccess.get_file_as_bytes(path))
        assert_eq(_chunk_index(chunks, "cICP"), -1, "%s names no primaries" % space.id)
        assert_eq(_chunk_index(chunks, "iCCP"), -1, "%s carries no profile" % space.id)
        assert_eq(SaImageImport.space_for(path).gamut().id, SaGamut.ID_SRGB, "%s opens as sRGB, as any PNG did" % space.id)
        canvas.free()
    _cleanup(path)


func test_the_export_dialog_says_the_gamut_and_offers_no_choice_of_it() -> void:
    var canvas := _canvas_in(SaColorSpace.display_p3())
    var dialog := SaExportDialog.new(canvas, &"png")
    assert_true(dialog._gamut_label.text.contains("Display P3"), "the line names the document's gamut")
    assert_true(dialog._gamut_label.text.contains("named in the file"), "and says the file carries it")
    dialog.page.row(&"format").drive(SaExportDialog.format_ids().find(&"exr"))
    assert_true(dialog._gamut_label.text.begins_with("Written as linear sRGB"), "an EXR says what it holds instead")
    var choosers: Array[String] = []
    var pending: Array[Node] = [dialog]
    while not pending.is_empty():
        var node: Node = pending.pop_back()
        if node is SaChoiceButton:
            choosers.append(String(node.name))
        pending.append_array(node.get_children())
    # Two now, which gave the dialog a depth row beside the format. The
    # gamut is still the one thing here that is said rather than offered, which
    # is what this test holds: no row on the dialog chooses it.
    choosers.sort()
    assert_eq(choosers, ["DepthOption", "FormatOption"], "a format and a depth, and no chooser for the gamut")
    dialog.free()
    canvas.free()
