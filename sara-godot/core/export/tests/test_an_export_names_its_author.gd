## An exported PNG or TIFF names its author, its date and Sara.
## The TIFF's half moved with its writer into the image formats module, as
## `test_a_tiff_names_its_author.gd`, and this is the PNG's and the record's.
##
## Every file here is read back by walking its bytes, the PNG's chunks, rather
## than through a reader of Sara's own, which would
## agree with the writer about its own mistakes. The dates are held still by a
## record the suite makes, and the painter's path, where the name comes from
## the Preferences row's setting, is walked once at the end.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The export path builds a real easel and reads a real canvas back.
const REQUIRES_GPU := true

## 2026-09-23 19:04:05 UTC, a Wednesday, read off a clock two hours ahead.
const INSTANT: int = 1790190245
const ZONE_MINUTES: int = 120
const PNG_DATE: String = "Wed, 23 Sep 2026 21:04:05 +0200"
const TIFF_DATE: String = "2026:09:23 21:04:05"

## Not ASCII, because the reason for `iTXt` and for UTF-8 in the TIFF is a
## painter whose name is not.
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


# --- Reading the files back ----------------------------------------------------


func _u32_be(bytes: PackedByteArray, at: int) -> int:
    return (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3]


## Every `iTXt` chunk of *bytes* as `keyword -> text`, and the chunk types in
## file order under `"order"`, walked the way a reader walks a PNG.
func _png_text(bytes: PackedByteArray) -> Dictionary:
    var out: Dictionary = {"order": []}
    var at := 8
    while at + 12 <= bytes.size():
        var length := _u32_be(bytes, at)
        var type := bytes.slice(at + 4, at + 8).get_string_from_ascii()
        (out["order"] as Array).append(type)
        if type == "iTXt":
            var data := bytes.slice(at + 8, at + 8 + length)
            var keyword_end := data.find(0)
            var keyword := data.slice(0, keyword_end).get_string_from_ascii()
            assert_eq(data[keyword_end + 1], 0, "%s is not compressed" % keyword)
            # The language tag and the translated keyword, each ended by a zero.
            var language_end := data.find(0, keyword_end + 3)
            var translated_end := data.find(0, language_end + 1)
            out[keyword] = data.slice(translated_end + 1).get_string_from_utf8()
        at += 12 + length
    return out


func _read(path: String) -> PackedByteArray:
    var bytes := FileAccess.get_file_as_bytes(path)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    return bytes


func _record(author: String) -> SaExportMetadata:
    return SaExportMetadata.new(author, INSTANT, ZONE_MINUTES)


## The canvas as a PNG at *path*, with the suite's record for *author*.
func _png(path: String, bits: int, author: String, space: SaColorSpace = null) -> Error:
    var tonemap := PackedFloat32Array()
    return SaExport.export_png_texture(_easel.output, space, path, bits, tonemap, SaGamutMapping.CLIP, _record(author))


# --- The record ----------------------------------------------------------------


func test_each_date_is_in_its_formats_own_form() -> void:
    var record := _record(AUTHOR)
    assert_eq(record.png_creation_time(), PNG_DATE, "The PNG's date is RFC 1123 with the clock's offset")
    assert_eq(record.tiff_date_time(), TIFF_DATE, "and the TIFF's is TIFF 6.0's nineteen characters")
    var west := SaExportMetadata.new("", INSTANT, -330)
    assert_eq(west.png_creation_time(), "Wed, 23 Sep 2026 13:34:05 -0530", "a clock behind UTC signs its offset")


func test_the_name_is_stripped_and_blank_is_none() -> void:
    assert_eq(_record("  Ada  ").author, "Ada", "Spaces around the name go")
    var entries := _record("   ").png_entries()
    assert_eq(entries.size(), 2, "and a blank name leaves two entries")
    assert_eq(entries[0][0], SaExportMetadata.KEY_CREATION_TIME, "starting with the date, not an empty Author")


# --- The files -----------------------------------------------------------------


func test_an_eight_bit_png_names_its_author_date_and_sara() -> void:
    var path := SaDataRoot.path("e1-meta-8.png")
    assert_eq(_png(path, 8, AUTHOR, null), OK, "exported")
    var text := _png_text(_read(path))
    assert_eq(text.get("Author"), AUTHOR, "The eight-bit PNG names its author, in UTF-8")
    assert_eq(text.get("Creation Time"), PNG_DATE, "its date")
    assert_eq(text.get("Software"), "Sara %s" % SaBuildInfo.version(), "and the program")
    assert_eq((text["order"] as Array)[0], "IHDR", "with the header still first")
    assert_true((text["order"] as Array).has("IDAT"), "and the pixels still there")


func test_a_sixteen_bit_png_names_its_author_date_and_sara() -> void:
    var path := SaDataRoot.path("e1-meta-16.png")
    assert_eq(_png(path, 16, AUTHOR, null), OK, "exported")
    var text := _png_text(_read(path))
    assert_eq(text.get("Author"), AUTHOR, "The sixteen-bit PNG names its author")
    assert_eq(text.get("Creation Time"), PNG_DATE, "its date")
    assert_eq(text.get("Software"), "Sara %s" % SaBuildInfo.version(), "and the program")


func test_a_named_gamut_and_the_text_share_the_file() -> void:
    var path := SaDataRoot.path("e1-meta-p3.png")
    var space := SaColorSpace.display_p3()
    assert_eq(_png(path, 8, AUTHOR, space), OK, "exported")
    var text := _png_text(_read(path))
    assert_true((text["order"] as Array).has("cICP"), "The gamut is still named")
    assert_eq(text.get("Author"), AUTHOR, "beside the author")


# --- No author -----------------------------------------------------------------


func test_no_author_writes_no_author_entry() -> void:
    var png := SaDataRoot.path("e1-meta-none.png")
    assert_eq(_png(png, 8, "", null), OK, "exported")
    var png_text := _png_text(_read(png))
    assert_false(png_text.has("Author"), "A PNG with no author has no Author entry, not an empty one")
    assert_eq(png_text.get("Creation Time"), PNG_DATE, "but still its date")

    var png16 := SaDataRoot.path("e1-meta-none-16.png")
    assert_eq(_png(png16, 16, "", null), OK, "exported")
    assert_false(_png_text(_read(png16)).has("Author"), "and neither has the sixteen-bit one")


# --- The painter's path --------------------------------------------------------


## No record handed in, which is every export from the dialog: the name is the
## setting's and the date is now's.
func test_the_setting_names_the_author_of_an_export_made_now() -> void:
    var before := SaSettings.export_author
    SaSettings.export_author = "  Ada Lovelace "
    assert_eq(SaSettings.export_author, "Ada Lovelace", "The setting keeps the name stripped")
    var path := SaDataRoot.path("e1-meta-now.png")
    assert_eq(SaExport.export_png(_easel, path), OK, "exported")
    var text := _png_text(_read(path))
    assert_eq(text.get("Author"), "Ada Lovelace", "and an export made now carries it")
    var rfc1123 := RegEx.create_from_string("^[A-Z][a-z]{2}, \\d{2} [A-Z][a-z]{2} \\d{4} \\d{2}:\\d{2}:\\d{2} [+-]\\d{4}$")
    assert_true(rfc1123.search(String(text.get("Creation Time", ""))) != null, "with a date in RFC 1123's form")

    SaSettings.export_author = ""
    assert_eq(SaExport.export_png(_easel, path), OK, "exported again")
    assert_false(_png_text(_read(path)).has("Author"), "and with the row emptied the Author entry goes")
    SaSettings.export_author = before


func test_the_author_is_a_stored_preference() -> void:
    assert_eq(SaSettingsKeys.place_of(&"export_author"), ["files", "export_author"], "stored under files")
