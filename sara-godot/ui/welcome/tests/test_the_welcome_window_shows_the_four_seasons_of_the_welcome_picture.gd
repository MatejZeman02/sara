## The Welcome picture ships its four seasons, spring, summer, autumn and
## winter, each in the six lights of `0.18.json`, every light in its parts and
## every file the sidecar names beside it, so the window shows the season of
## the painter's place and date.
##
## `scripts/export_welcome_lights.py` writes them from the source document. The scenario of the same name
## shows the window in January, April,
## July and October at one hour, which is winter, spring, summer and autumn in
## Czechia.
extends "res://tests/test_framework.gd"

const SHIPPED := "res://ui/welcome/pictures/"

## The six lights of each season, by the name its files take after the season.
const LIGHTS: Array[String] = ["dawn", "day-clear", "day-hazy", "day-overcast", "dusk", "night"]


func _sidecar() -> Dictionary:
    var said: Variant = JSON.parse_string(FileAccess.get_file_as_string(SHIPPED + "0.18.json"))
    return said if said is Dictionary else {}


func _present(file: String) -> bool:
    return FileAccess.file_exists(SHIPPED + file)


func test_the_sidecar_lists_six_lights_in_each_of_the_four_seasons() -> void:
    var lights := PictureLights.lights_in(_sidecar(), SHIPPED)
    var files: Array[String] = []
    for light in lights:
        files.append(light.path.get_file())
    for season: String in PictureLights.SEASONS:
        var own := PictureLights.in_season(lights, season)
        var wanted: Array[String] = []
        for light: String in LIGHTS:
            wanted.append("0.18-%s-%s.png" % [season, light])
        var named: Array[String] = []
        for light in own:
            assert_eq(light.season, season, "%s is %s's" % [light.path.get_file(), season])
            if not named.has(light.path.get_file()):
                named.append(light.path.get_file())
        named.sort()
        wanted.sort()
        assert_eq(named, wanted, "%s shows its own six lights and no other season's" % season)
    var distinct := {}
    for file in files:
        distinct[file] = true
    assert_eq(distinct.size(), 24, "twenty four lights in all")


func test_every_light_comes_in_parts_and_every_file_the_sidecar_names_is_there() -> void:
    var sidecar := _sidecar()
    var parts := PictureParts.listed_in(sidecar, SHIPPED)
    assert_eq(parts.size(), 24, "each of the twenty four lights in parts")
    for variant: Dictionary in sidecar["variants"]:
        var file := str(variant["file"])
        assert_true(_present(file), "%s is shipped" % file)
        assert_true(parts.has(file), "%s comes in parts" % file)
        assert_true(PictureLights.SEASONS.has(str(variant.get("season", ""))), "%s names its season" % file)
    for file: String in sidecar["parts"]:
        var entry: Dictionary = sidecar["parts"][file]
        for part: String in ["back", "clouds", "land"]:
            assert_true(_present(str(entry[part])), "%s's %s %s is shipped" % [file, part, entry[part]])
            assert_true(PictureParts.image_of(SHIPPED + str(entry[part])) != null, "and reads as an image")
        if entry.has("body"):
            assert_true(_present(str(entry["body"]["file"])), "%s's body is shipped" % file)
    var overlays := 0
    for overlay: Dictionary in sidecar["overlays"]:
        overlays += 1
        assert_true(_present(str(overlay["file"])), "the overlay %s is shipped" % overlay["file"])
        for light: String in overlay.get("variants", []):
            assert_true(parts.has(light), "%s lies over %s, a light of the sidecar" % [overlay["file"], light])
    # The summer night is a midsummer twilight over the whole sky, so it
    # carries one flock and no stars.
    assert_eq(overlays, 77, "three flocks over every light but summer's night, the stars over each dusk and other night")


func test_the_window_in_four_months_shows_four_seasons() -> void:
    var band := WelcomePicture.new()
    for month: Dictionary in [
        {"month": 1, "season": "winter"},
        {"month": 4, "season": "spring"},
        {"month": 7, "season": "summer"},
        {"month": 10, "season": "autumn"},
    ]:
        var season := PictureLights.season_of(int(month["month"]), "cs_CZ")
        assert_eq(season, month["season"], "month %d in Czechia" % month["month"])
        band.show_at(13.0, season)
        assert_false(band.shown.is_empty(), "%s shows a light" % season)
        for light: PictureLights.Light in band.shown:
            assert_true(light.path.get_file().begins_with("0.18-%s-" % season), "%s is %s's" % [light.path.get_file(), season])
    band.free()
