## An exported TIFF names its author, its date and
## Sara. The PNG's half and the record's stay in the skeleton's
## `test_an_export_names_its_author.gd`, and this half moved with the writer into
## this module.
##
## Every file here is read back by walking the TIFF's directory rather than
## through a reader of Sara's own, which would agree with the writer about its
## own mistakes. The dates are held still by a record the suite makes, and the
## painter's path, where the name comes from the Preferences row's setting, is
## walked once at the end.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The export path builds a real easel and reads a real canvas back.
const REQUIRES_GPU := true

## 2026-09-23 19:04:05 UTC, a Wednesday, read off a clock two hours ahead.
const INSTANT: int = 1790190245
const ZONE_MINUTES: int = 120
const TIFF_DATE: String = "2026:09:23 21:04:05"

## Not ASCII, because the reason for UTF-8 in the TIFF is a painter whose name
## is not.
const AUTHOR: String = "Matěj Zeman"

var _easel: SaEasel


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(8, 8))
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _easel.document.fill_layer(Color(0.25, 0.5, 0.75, 1.0))
    _easel.request_full_composite()
    _easel.process_pending_composite()


func after_each() -> void:
    _easel.free()
    _easel = null


func _u16_le(bytes: PackedByteArray, at: int) -> int:
    return bytes[at] | (bytes[at + 1] << 8)


func _u32_le(bytes: PackedByteArray, at: int) -> int:
    return bytes[at] | (bytes[at + 1] << 8) | (bytes[at + 2] << 16) | (bytes[at + 3] << 24)


## Every ASCII field of the TIFF *bytes* as `tag -> text`, read inline when it
## is four bytes or fewer and at its offset when it is longer.
func _tiff_text(bytes: PackedByteArray) -> Dictionary:
    var out: Dictionary = {}
    var at := _u32_le(bytes, 4)
    for i in _u16_le(bytes, at):
        var entry := at + 2 + i * 12
        if _u16_le(bytes, entry + 2) != SaExportTiff.TYPE_ASCII:
            continue
        var count := _u32_le(bytes, entry + 4)
        var start := entry + 8 if count <= 4 else _u32_le(bytes, entry + 8)
        var raw := bytes.slice(start, start + count)
        assert_eq(raw[count - 1], 0, "tag %d ends in its zero" % _u16_le(bytes, entry))
        out[_u16_le(bytes, entry)] = raw.slice(0, count - 1).get_string_from_utf8()
    return out


## What the entry for *tag* holds in its own four bytes.
func _tiff_field(bytes: PackedByteArray, tag: int) -> int:
    var at := _u32_le(bytes, 4)
    for i in _u16_le(bytes, at):
        if _u16_le(bytes, at + 2 + i * 12) == tag:
            return _u32_le(bytes, at + 2 + i * 12 + 8)
    return -1


func _read(path: String) -> PackedByteArray:
    var bytes := FileAccess.get_file_as_bytes(path)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    return bytes


func _record(author: String) -> SaExportMetadata:
    return SaExportMetadata.new(author, INSTANT, ZONE_MINUTES)


## The canvas as a TIFF at *path*, with the suite's record for *author*.
func _tiff(path: String, bits: int, author: String) -> Error:
    var tonemap := PackedFloat32Array()
    return SaExportTiff.export_texture(_easel.output, path, 96.0, null, bits, tonemap, SaGamutMapping.CLIP, _record(author))


func test_a_tiff_names_its_author_date_and_sara() -> void:
    for bits: int in [SaExportTiff.BITS_PER_SAMPLE, SaExportTiff.BITS_PER_SAMPLE_SIXTEEN]:
        var path := SaDataRoot.path("e1-meta-%d.tif" % bits)
        var error := _tiff(path, bits, AUTHOR)
        assert_eq(error, OK, "exported at %d bits" % bits)
        var bytes := _read(path)
        var text := _tiff_text(bytes)
        assert_eq(text.get(SaExportTiff.TAG_ARTIST), AUTHOR, "The %d-bit TIFF names its artist" % bits)
        assert_eq(text.get(SaExportTiff.TAG_DATE_TIME), TIFF_DATE, "its date")
        assert_eq(text.get(SaExportTiff.TAG_SOFTWARE), "Sara %s" % SaBuildInfo.version(), "and the program")
        var strip := _tiff_field(bytes, SaExportTiff.TAG_STRIP_OFFSETS) + _tiff_field(bytes, SaExportTiff.TAG_STRIP_BYTE_COUNTS)
        assert_eq(strip, bytes.size(), "and the pixels still end the file where the directory says")


func test_a_short_name_sits_inside_its_entry() -> void:
    var image := Image.create_empty(2, 1, false, Image.FORMAT_RGBAF)
    var bytes := SaExportTiff.encode(image, 96.0, PackedByteArray(), 32, _record("Jo"))
    assert_eq(_tiff_text(bytes).get(SaExportTiff.TAG_ARTIST), "Jo", "A name of three bytes with its zero is read inline")
    var pixels := SaExportTiff.encode(image, 96.0, PackedByteArray(), 32, _record(""))
    assert_eq(bytes.size(), pixels.size() + SaExportTiff.ENTRY_BYTES, "and costs the file its entry and nothing after it")


func test_the_directory_stays_sorted_with_every_tag() -> void:
    var image := Image.create_empty(2, 1, false, Image.FORMAT_RGBAF)
    var bytes := SaExportTiff.encode(image, 96.0, PackedByteArray([1, 2, 3]), 32, _record(AUTHOR))
    var at := _u32_le(bytes, 4)
    var previous := -1
    for i in _u16_le(bytes, at):
        var tag := _u16_le(bytes, at + 2 + i * 12)
        assert_true(tag > previous, "tag %d comes after the one before it" % tag)
        previous = tag
    assert_eq(_u16_le(bytes, at), 19, "sixteen fields, the date, the artist and the profile")


func test_no_author_writes_no_artist_tag() -> void:
    var tiff := SaDataRoot.path("e1-meta-none.tif")
    assert_eq(_tiff(tiff, 32, ""), OK, "exported")
    var tiff_text := _tiff_text(_read(tiff))
    assert_false(tiff_text.has(SaExportTiff.TAG_ARTIST), "A TIFF with no author has no Artist tag, not an empty one")
    assert_eq(tiff_text.get(SaExportTiff.TAG_DATE_TIME), TIFF_DATE, "but still its date")


## No record handed in, which is every export from the dialog: the name is the
## setting's.
func test_the_setting_names_the_author_of_a_tiff_made_now() -> void:
    var before := SaSettings.export_author
    SaSettings.export_author = "  Ada Lovelace "
    var tiff := SaDataRoot.path("e1-meta-now.tif")
    assert_eq(SaExportTiff.export(_easel, tiff), OK, "exported")
    assert_eq(_tiff_text(_read(tiff)).get(SaExportTiff.TAG_ARTIST), "Ada Lovelace", "A TIFF made now names the setting")
    SaSettings.export_author = before
