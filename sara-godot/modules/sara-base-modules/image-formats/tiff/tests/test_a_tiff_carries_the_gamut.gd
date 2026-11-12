## A TIFF export carries the document's gamut.
##
## The intended display gamut is saved with the document and into the PNG, JPEG
## and TIFF files. The PNG and JPEG halves stay in the skeleton's
## `test_export_carries_the_gamut.gd`, and this is the TIFF's, which moved with
## the writer into this module. Each document is exported and the file's
## directory walked, so a tag written in the wrong place is a file that does not
## read rather than a number that happens to agree.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const RED := Color(1.0, 0.0, 0.0, 1.0)

const NAMED: Array[StringName] = [SaGamut.ID_SRGB, SaGamut.ID_DISPLAY_P3, SaGamut.ID_REC2020]

## How far a corner may move under the rounding of an export, as a float and in
## steps of sixteen bits.
const ROUNDED := 0.001
const ROUNDED_STEPS := 16

## The skeleton's formats with this module's after them, built again before
## each test because registries a test builds install over them.
var _formats: SaRegistries


func before_each() -> void:
    _formats = Fixtures.make_picture_registries()


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


static func _u16_le(bytes: PackedByteArray, at: int) -> int:
    return bytes[at] | (bytes[at + 1] << 8)


static func _u32_le(bytes: PackedByteArray, at: int) -> int:
    return bytes[at] | (bytes[at + 1] << 8) | (bytes[at + 2] << 16) | (bytes[at + 3] << 24)


## A little-endian TIFF's first directory, by tag.
static func _tiff_entries(bytes: PackedByteArray) -> Dictionary:
    var entries := {}
    var directory := _u32_le(bytes, 4)
    for i in _u16_le(bytes, directory):
        var at := directory + 2 + i * 12
        entries[_u16_le(bytes, at)] = {
            "type": _u16_le(bytes, at + 2), "count": _u32_le(bytes, at + 4), "value": _u32_le(bytes, at + 8)
        }
    return entries


## Every named gamut, in RGB and in OKLab coordinates, at thirty-two bits float
## and at sixteen bits integer, the sixteen-bit file carrying the
## same label.
func test_every_named_gamut_reaches_the_tiff_at_both_depths() -> void:
    for gamut_id: StringName in NAMED:
        var gamut := SaGamut.from_id(gamut_id)
        for coordinates: int in [SaColorSpace.Coordinates.RGB, SaColorSpace.Coordinates.OKLAB]:
            var space := SaColorSpace.srgb().with_gamut(gamut).with_coordinates(coordinates)
            var canvas := _canvas_in(space)
            var label := "%s in %s" % [gamut_id, SaColorSpace.coordinates_name(coordinates)]
            _check_tiff(canvas, gamut, label, SaExportTiff.BITS_PER_SAMPLE)
            _check_tiff(canvas, gamut, label + " at 16 bits", SaExportTiff.BITS_PER_SAMPLE_SIXTEEN)
            canvas.free()


func _check_tiff(canvas: SaCanvas, gamut: SaGamut, label: String, bits: int) -> void:
    var path := SaDataRoot.path("test_a7_export.tiff")
    assert_eq(SaExportTiff.export(canvas.easel, path, bits), OK, "%s exports a TIFF" % label)
    var bytes := FileAccess.get_file_as_bytes(path)
    var entries := _tiff_entries(bytes)
    var profile := SaExportGamut.profile_for(gamut)
    assert_true(entries.has(SaExportTiff.TAG_ICC_PROFILE), "%s: tag 34675 is there" % label)
    var entry: Dictionary = entries.get(SaExportTiff.TAG_ICC_PROFILE, {"type": 0, "count": 0, "value": 0})
    assert_eq(entry["type"], SaExportTiff.TYPE_UNDEFINED, "%s: as undefined bytes" % label)
    assert_eq(entry["count"], profile.size(), "%s: as many as the profile has" % label)
    assert_eq(bytes.slice(entry["value"], entry["value"] + entry["count"]), profile, "%s: and they are the profile" % label)
    var tags := entries.keys()
    var sorted := tags.duplicate()
    sorted.sort()
    assert_eq(tags, sorted, "%s: the directory is still sorted" % label)
    var depths: int = entries[SaExportTiff.TAG_BITS_PER_SAMPLE]["value"]
    assert_eq(_u16_le(bytes, depths), bits, "%s: at %d bits a sample" % [label, bits])
    var strip: int = entries[SaExportTiff.TAG_STRIP_OFFSETS]["value"]
    assert_eq(strip % 2, 0, "%s: the strip starts on an even offset" % label)
    # An export rounds the live colour to 12 significant bits as a save does,
    # which in Oklab moves a gamut's corner by a few parts
    # in ten thousand once carried back to RGB, an error accepted as rounding.
    if bits == SaExportTiff.BITS_PER_SAMPLE_SIXTEEN:
        assert_true(absi(_u16_le(bytes, strip) - 65535) <= ROUNDED_STEPS, "%s: the first red is 65535" % label)
        assert_true(_u16_le(bytes, strip + 2) <= ROUNDED_STEPS, "%s: its green 0" % label)
    else:
        assert_almost_eq(bytes.decode_float(strip), 1.0, ROUNDED, "%s: the first red is 1.0" % label)
        assert_almost_eq(bytes.decode_float(strip + 4), 0.0, ROUNDED, "%s: its green 0.0" % label)
    _cleanup(path)


## The ask in its own words for the TIFF: a Display P3 document written as a
## sixteen-bit TIFF holds exactly `profile_for`'s bytes in tag 34675.
func test_a_display_p3_document_at_sixteen_bits_names_its_gamut() -> void:
    var canvas := _canvas_in(SaColorSpace.display_p3())
    var gamut := SaGamut.from_id(SaGamut.ID_DISPLAY_P3)
    var tiff_path := SaDataRoot.path("test_e4_p3.tif")
    assert_eq(SaExportTiff.export(canvas.easel, tiff_path, SaExportTiff.BITS_PER_SAMPLE_SIXTEEN), OK, "a 16-bit TIFF")
    var tiff := FileAccess.get_file_as_bytes(tiff_path)
    var entry: Dictionary = _tiff_entries(tiff).get(SaExportTiff.TAG_ICC_PROFILE, {"count": 0, "value": 0})
    var held := tiff.slice(entry["value"], entry["value"] + entry["count"])
    assert_eq(held, SaExportGamut.profile_for(gamut), "tag 34675 holds the profile_for bytes unchanged")
    _cleanup(tiff_path)
    canvas.free()


## A TIFF handed no profile carries no profile tag, rather than one naming a
## gamut it was not given.
func test_a_tiff_with_no_profile_is_written_unlabelled() -> void:
    var tiff := SaExportTiff.encode(Image.create(2, 2, false, Image.FORMAT_RGBAF))
    assert_false(_tiff_entries(tiff).has(SaExportTiff.TAG_ICC_PROFILE), "a TIFF with no profile has no profile tag")
