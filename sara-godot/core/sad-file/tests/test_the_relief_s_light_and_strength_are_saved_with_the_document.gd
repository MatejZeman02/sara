## The relief's light and strength are saved with the document.
##
## A painter, 2026-10-09: "Shouldn't Relief light strength and direction be
## saved with the .sad file?" The light was two app settings, so one `.sad`
## exported a different picture on a machine with other settings. It is the
## document's now, `SaReliefLight`, kept in the header under
## `SaReliefLight.HEADER_KEY`, and Preferences says only where a new document's
## starts. The popup's undo is
## `ui/dialogs/tests/test_the_relief_light_popup_is_one_undo_step.gd`.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: a round trip reads chunks back and an export lights them.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## A file written on 2026-09-19, before the light was the document's.
const BEFORE_V4 := "res://tests/data/plain_v4.sad"

const SIZE := Vector2i(256, 256)
const RAMP_MM: float = 0.025

static var scratch_sad: String = SaDataRoot.path("relief-light.sad")
static var scratch_png_saved: String = SaDataRoot.path("lit-before.png")
static var scratch_png_opened: String = SaDataRoot.path("lit-after.png")
static var scratch_png_preferences: String = SaDataRoot.path("lit-by-preferences.png")

var _registries: SaRegistries = null
var _easels: Array[SaEasel] = []
var _kept_angle: float = 0.0
var _kept_strength: float = 0.0


func before_each() -> void:
    _kept_angle = SaSettings.relief_light_angle
    _kept_strength = SaSettings.relief_strength
    SaSettings.relief_light_angle = 315.0
    SaSettings.relief_strength = 2.0
    _registries = Fixtures.make_registries()


func after_each() -> void:
    for path: String in [scratch_sad, scratch_png_saved, scratch_png_opened, scratch_png_preferences]:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    for easel in _easels:
        easel.free()
    _easels.clear()
    _registries = null
    SaSettings.relief_light_angle = _kept_angle
    SaSettings.relief_strength = _kept_strength


func _easel() -> SaEasel:
    var made := SaEasel.create_default(SIZE)
    made.compositor.set_registry(_registries.blend_modes)
    _easels.append(made)
    return made


## A blue picture with a ramp of height rising to the right, composited.
func _painted() -> SaEasel:
    var made := _easel()
    var doc := made.document
    doc.active_layer.fill(doc.color_space.from_display(Color(0.3, 0.55, 0.8, 1.0)))
    SaHeightOps.new(doc).gain(doc.active_layer)
    var texture := doc.active_layer.get_or_create_field(Vector2i.ZERO, SaFieldSpec.HEIGHT)
    var bytes := PackedByteArray()
    bytes.resize(texture.size.x * texture.size.y * 2)
    for y in texture.size.y:
        for x in texture.size.x:
            bytes.encode_half((y * texture.size.x + x) * 2, float(x) * RAMP_MM)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, bytes)
    doc.invalidate_chunks([Vector2i.ZERO])
    _composite(made)
    return made


func _composite(made: SaEasel) -> void:
    made.document.update_caches()
    made.request_full_composite()
    made.process_pending_composite()


## The v4 header of the `.sad` at *path*, read the way `test_module_data.gd`
## reads it: the magic, the version, the two sizes and the packed JSON.
static func _header(path: String) -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    file.get_buffer(4)
    file.get_32()
    var packed_size := file.get_32()
    var raw_size := file.get_32()
    var packed := file.get_buffer(packed_size)
    file.close()
    return SaTyped.strings(JSON.parse_string(packed.decompress(raw_size, SaSadFile.SAD_BLOB_COMPRESS).get_string_from_utf8()))


## A flat export of *made* with Include impasto lighting, as eight-bit pixels.
func _lit(made: SaEasel, path: String) -> PackedByteArray:
    assert_eq(SaExport.export_png(made, path, 8, false, SaGamutMapping.CLIP, true), OK, "The lit export writes")
    var image := Image.new()
    image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
    return image.get_data()


func test_a_new_document_starts_from_preferences() -> void:
    SaSettings.relief_light_angle = 45.0
    SaSettings.relief_strength = 6.0
    var made := _easel()
    assert_almost_eq(made.document.relief_light.angle, 45.0, 1e-6, "A new document's light stands where Preferences says")
    assert_almost_eq(made.document.relief_light.strength, 6.0, 1e-6, "at Preferences' strength")
    made.document.relief_light.angle = 90.0
    SaSettings.relief_light_angle = 180.0
    SaSettings.relief_strength = 3.0
    assert_almost_eq(made.document.relief_light.angle, 90.0, 1e-6, "and Preferences moving after leaves it where it is")
    made.document.reset_to_default(SIZE)
    assert_almost_eq(made.document.relief_light.angle, 180.0, 1e-6, "File > New starts again from Preferences")
    assert_almost_eq(made.document.relief_light.strength, 3.0, 1e-6, "strength and all")


## The first case: a light of 90 degrees and strength 5 is saved, the file
## opened with Preferences at other values reads 90 and 5 back, and a flat export
## with Include impasto lighting is the same either side of the reopening.
func test_the_light_comes_back_from_the_file_and_lights_the_export_the_same() -> void:
    var saved := _painted()
    saved.document.relief_light.angle = 90.0
    saved.document.relief_light.strength = 5.0
    var before := _lit(saved, scratch_png_saved)
    assert_eq(SaExport.save_sad(saved.document, scratch_sad, 0), OK, "The document saves")
    var header := _header(scratch_sad)
    var stored := SaTyped.strings(header.get(SaReliefLight.HEADER_KEY))
    assert_almost_eq(SaTyped.float_at(stored, "angle", -1.0), 90.0, 1e-6, "The header keeps the angle")
    assert_almost_eq(SaTyped.float_at(stored, "strength", -1.0), 5.0, 1e-6, "and the strength")

    SaSettings.relief_light_angle = 200.0
    SaSettings.relief_strength = 1.5
    var opened := _easel()
    assert_almost_eq(opened.document.relief_light.angle, 200.0, 1e-6, "The opening document starts at Preferences' 200")
    assert_eq(SaExport.load_sad(opened.document, scratch_sad, opened.compositor), OK, "The file opens")
    assert_almost_eq(opened.document.relief_light.angle, 90.0, 1e-6, "and reads its own 90 degrees back")
    assert_almost_eq(opened.document.relief_light.strength, 5.0, 1e-6, "and its strength of 5")
    _composite(opened)
    var after := _lit(opened, scratch_png_opened)
    assert_eq(after.size(), before.size(), "The two exports are one size")
    assert_true(after == before, "and the lit export is the same either side of the reopening")

    opened.document.relief_light.angle = SaSettings.relief_light_angle
    opened.document.relief_light.strength = SaSettings.relief_strength
    var under_preferences := _lit(opened, scratch_png_preferences)
    assert_false(under_preferences == before, "Under Preferences' light the export would have differed")


## The second case: a `.sad` saved before this feature opens under
## Preferences' light, whatever the document it opened over was lit by.
func test_a_file_saved_before_the_row_opens_under_preferences_light() -> void:
    var header := _header(ProjectSettings.globalize_path(BEFORE_V4))
    assert_false(header.has(SaReliefLight.HEADER_KEY), "The old file holds no light")
    for preferences: Vector2 in [Vector2(200.0, 1.5), Vector2(45.0, 6.0)]:
        SaSettings.relief_light_angle = preferences.x
        SaSettings.relief_strength = preferences.y
        var made := _easel()
        made.document.relief_light.angle = 90.0
        made.document.relief_light.strength = 5.0
        assert_eq(SaExport.load_sad(made.document, ProjectSettings.globalize_path(BEFORE_V4), made.compositor), OK, "It opens")
        assert_almost_eq(made.document.relief_light.angle, preferences.x, 1e-6, "under Preferences' angle, %s" % preferences.x)
        assert_almost_eq(made.document.relief_light.strength, preferences.y, 1e-6, "and strength, %s" % preferences.y)


## A key a hand broke reads as Preferences' light, and the setters keep a
## light the file says is out of range inside it.
func test_a_broken_key_reads_as_preferences_light() -> void:
    var light := SaReliefLight.new()
    light.read_header({"angle": "west", "strength": 99.0})
    assert_almost_eq(light.angle, 315.0, 1e-6, "An angle that is no number is Preferences'")
    assert_almost_eq(light.strength, SaSettings.MAX_RELIEF_STRENGTH, 1e-6, "and a strength past the top is held at it")
    light.read_header({"angle": 450.0})
    assert_almost_eq(light.angle, 90.0, 1e-6, "The bearing goes round")
    assert_almost_eq(light.strength, 2.0, 1e-6, "and a missing strength is Preferences'")
