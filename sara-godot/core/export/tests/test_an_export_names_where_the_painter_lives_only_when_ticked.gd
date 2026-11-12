## An exported PNG or TIFF names the painter's country and town
## when "Write the location into exported pictures" is ticked, and nothing of
## either when it is not.
##
## Read by `exiv2 -pa`, the common reader the row names, so the test is what a
## painter's own tools show and not what Sara's writer believes it wrote. Every
## export is made the painter's way, with no record handed in, so the record is
## the one `SaExportMetadata.now` makes from the settings.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The export path builds a real easel and reads a real canvas back.
const REQUIRES_GPU := true

const SETTINGS: Array[StringName] = [&"location_country", &"location_zone", &"location_place", &"location_in_exports"]

var _easel: SaEasel
## The skeleton's formats and the image formats module's, the TIFF among them.
var _formats: SaRegistries
var _before: Dictionary = {}


func before_each() -> void:
    for property in SETTINGS:
        _before[property] = SaSettings.get(property)
    _formats = Fixtures.make_picture_registries()
    _easel = SaEasel.create_default(Vector2i(8, 8))
    _easel.compositor.set_registry(_formats.blend_modes)
    _easel.document.fill_layer(Color(0.25, 0.5, 0.75, 1.0))
    _easel.request_full_composite()
    _easel.process_pending_composite()


func after_each() -> void:
    _easel.free()
    _easel = null
    for property in SETTINGS:
        SaSettings.set(property, _before[property])


## What `exiv2 -pa` lists for the file at *path*, which is then deleted, or
## null when there is no `exiv2` to ask.
func _exiv2(path: String) -> Variant:
    var out: Array = []
    var code := OS.execute("exiv2", ["-pa", ProjectSettings.globalize_path(path)], out, true)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    if code < 0 or (out.size() > 0 and str(out[0]).contains("not found")):
        return null
    return "\n".join(out)


## Both formats exported now, and what `exiv2` reads off each.
func _both() -> Array:
    var png := SaDataRoot.path("location.png")
    var tiff := SaDataRoot.path("location.tif")
    assert_eq(SaExport.export_png(_easel, png), OK, "the PNG exported")
    assert_eq(Fixtures.export_through(&"tiff", _easel, tiff), OK, "the TIFF exported")
    return [_exiv2(png), _exiv2(tiff)]


func test_the_box_off_writes_no_trace_of_the_country_or_the_place_and_on_writes_both() -> void:
    SaSettings.location_country = "CZ"
    SaSettings.location_place = "Brno"
    SaSettings.location_in_exports = false
    var off := _both()
    if off[0] == null:
        skip("no exiv2 on this machine to read the files with")
        return
    for i in 2:
        var read: String = off[i]
        assert_false(read.contains("Czech"), "%s with the box off has no country: %s" % [["PNG", "TIFF"][i], read])
        assert_false(read.contains("Brno"), "nor the place")

    SaSettings.location_in_exports = true
    var on := _both()
    for i in 2:
        var read: String = on[i]
        var format: String = ["PNG", "TIFF"][i]
        assert_true(
            read.contains("Xmp.photoshop.Country") and read.contains("Czech Republic"),
            "%s names the country: %s" % [format, read]
        )
        assert_true(read.contains("Xmp.photoshop.City") and read.contains("Brno"), "%s names the place" % format)


func test_automatic_with_the_box_on_writes_the_guessed_country() -> void:
    SaSettings.location_country = ""
    SaSettings.location_place = ""
    SaSettings.location_in_exports = true
    var guessed := SaLocation.country_name(SaLocation.guessed(Time.get_datetime_dict_from_system()["month"]).country)
    var record := SaExportMetadata.now()
    assert_eq(record.country, guessed, "Automatic writes the guess, %s" % guessed)
    assert_eq(record.place, "", "and no place when none is typed")


func test_the_packet_escapes_what_a_town_may_be_called() -> void:
    var record := SaExportMetadata.new("", 0, 0, "", 'Smith & "Sons" <1>')
    assert_true(record.xmp().contains('photoshop:City="Smith &amp; &quot;Sons&quot; &lt;1&gt;"'), record.xmp())
    assert_false(record.xmp().contains("photoshop:Country"), "and no country with none given")
    assert_eq(SaExportMetadata.new("Ada").xmp(), "", "neither, no packet")


func test_the_location_is_a_stored_preference_and_never_the_documents() -> void:
    for property in SETTINGS:
        assert_eq(SaSettingsKeys.place_of(property), ["files", String(property)], "%s is stored under files" % property)
    for file in DirAccess.get_files_at("res://core/sad-file"):
        if file.ends_with(".gd"):
            var source := FileAccess.get_file_as_string("res://core/sad-file/" + file)
            assert_false(source.contains("location_") or source.contains("SaLocation"), "%s reads no location" % file)
