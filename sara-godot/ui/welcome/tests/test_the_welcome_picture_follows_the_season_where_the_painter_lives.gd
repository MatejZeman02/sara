## The Welcome picture follows the season where the painter
## lives. A light of a picture may name a season, the season is the month of the
## clock turned round for a country in the south, and a locale with no country or
## a country on the equator's band has none and sees only the lights with none.
##
## The lights here are three plain pictures in `tests/pictures/seasons/`, a pale
## winter and a yellow summer, both at 6, and a grey one with no season at 18.
## How the picture looks in each of four places is
## `scenarios/the-welcome-picture-follows-the-season-where-the-painter-lives.json`.
extends "res://tests/test_framework.gd"

const FOLDER := "res://ui/welcome/tests/pictures/seasons/"


func _sidecar() -> Dictionary:
    return JSON.parse_string(FileAccess.get_file_as_string(FOLDER + "0.1.json"))


func _files(lights: Array[PictureLights.Light]) -> Array[String]:
    var named: Array[String] = []
    for light in lights:
        named.append(light.path.get_file())
    return named


func test_four_locales_in_january_read_winter_summer_and_none_twice() -> void:
    assert_eq(PictureLights.season_of(1, "cs_CZ"), "winter", "Czechia in January")
    assert_eq(PictureLights.season_of(1, "en_AU"), "summer", "Australia in January")
    assert_eq(PictureLights.season_of(1, "es_EC"), "", "Ecuador has none, so no snow in Quito")
    assert_eq(PictureLights.season_of(1, "C"), "", "a locale with no country has none")
    var sidecar := _sidecar()
    var lights := PictureLights.lights_in(sidecar, FOLDER)
    var shown := {}
    for place: String in ["cs_CZ", "en_AU", "es_EC", "C"]:
        shown[place] = _files(PictureLights.in_season(lights, PictureLights.season_of(1, place)))
    assert_eq(shown["cs_CZ"], ["winter.png", "plain.png"], "Czechia is shown the winter light and the one for every season")
    assert_eq(shown["en_AU"], ["summer.png", "plain.png"], "Australia the summer light and that one")
    assert_eq(shown["es_EC"], ["summer.png", "plain.png"], "Ecuador summer's, the season the picture was first painted in")
    assert_eq(shown["C"], ["summer.png", "plain.png"], "and so does a locale with no country")


func test_the_year_runs_round_in_the_north_and_the_other_way_about_in_the_south() -> void:
    var north: Array[String] = []
    var south: Array[String] = []
    for month in range(1, 13):
        north.append(PictureLights.season_of(month, "cs_CZ"))
        south.append(PictureLights.season_of(month, "en_AU"))
    var year: Array[String] = [
        "winter",
        "winter",
        "spring",
        "spring",
        "spring",
        "summer",
        "summer",
        "summer",
        "autumn",
        "autumn",
        "autumn",
        "winter",
    ]
    var turned: Array[String] = [
        "summer",
        "summer",
        "autumn",
        "autumn",
        "autumn",
        "winter",
        "winter",
        "winter",
        "spring",
        "spring",
        "spring",
        "summer",
    ]
    assert_eq(north, year, "December to February is winter, three months to a season")
    assert_eq(south, turned, "and the south is two seasons along, so December is summer")
    assert_eq(PictureLights.season_of(0, "cs_CZ"), "", "a month that is not one is no season")
    assert_eq(PictureLights.season_of(13, "cs_CZ"), "", "at either end")


func test_the_country_is_the_last_part_of_the_locale_when_it_is_two_capitals() -> void:
    assert_eq(PictureLights.country_of("cs_CZ"), "CZ", "the plain case")
    assert_eq(PictureLights.country_of("en_AU.UTF-8"), "AU", "a POSIX encoding is left off")
    assert_eq(PictureLights.country_of("de_DE@euro"), "DE", "and so is a modifier")
    assert_eq(PictureLights.country_of("pt-BR"), "BR", "a hyphen is read as an underscore")
    assert_eq(PictureLights.country_of("zh_Hans_CN"), "CN", "a script in the middle does not hide the country")
    assert_eq(PictureLights.country_of("sr_Latn"), "", "a script is not a country")
    for none: String in ["C", "POSIX", "en", "", "_", "en_", "en_001", "en_au"]:
        assert_eq(PictureLights.country_of(none), "", "'%s' names no country" % none)


func test_a_locales_country_reads_its_side_of_the_equator_from_the_zones_table() -> void:
    # The lists of southern and tropical countries are gone, and a locale's
    # country now stands at its zone furthest from the equator.
    assert_eq(PictureLights.season_of(1, "pt_BR"), "summer", "Brazil is in the south")
    assert_eq(PictureLights.season_of(1, "af_ZA"), "summer", "so is South Africa")
    assert_eq(PictureLights.season_of(1, "id_ID"), "", "Indonesia is on the equator's band")
    assert_eq(PictureLights.season_of(1, "en_US"), "winter", "the United States in the north")
    assert_eq(PictureLights.season_of(1, "xx_QQ"), "", "a country with no zone has no season")


func test_a_sidecar_names_the_season_of_a_light() -> void:
    var lights := PictureLights.lights_in(_sidecar(), FOLDER)
    assert_eq(lights.size(), 3, "the three lights of the sidecar")
    assert_eq(lights[2].path.get_file(), "plain.png", "the grey one is last at 18")
    assert_eq(lights[2].season, "", "with no season, so every season's")
    var seasons: Array[String] = []
    for light: PictureLights.Light in lights.slice(0, 2):
        seasons.append(light.season)
    seasons.sort()
    assert_eq(seasons, ["summer", "winter"], "and the two at 6 are one season each")


func test_a_season_that_is_not_one_leaves_its_entry_out() -> void:
    var sidecar := {
        "variants":
        [
            {"file": "winter.png", "hour": 6, "season": "winter"},
            {"file": "winter.png", "hour": 7, "season": "monsoon"},
            {"file": "winter.png", "hour": 8, "season": "Winter"},
            {"file": "winter.png", "hour": 9, "season": 2},
            {"file": "winter.png", "hour": 10, "season": ""},
            {"file": "plain.png", "hour": 12},
        ]
    }
    var lights := PictureLights.lights_in(sidecar, FOLDER)
    assert_eq(lights.size(), 2, "the winter one and the one with no season key")
    assert_eq(lights[0].season, "winter", "winter at 6")
    assert_eq(lights[1].season, "", "and the one with no season at 12")


func test_the_fade_runs_within_the_lights_the_season_shows() -> void:
    var lights := PictureLights.lights_in(_sidecar(), FOLDER)
    var winter := PictureLights.in_season(lights, "winter")
    var noon := PictureLights.fade_at(winter, 12.0)
    assert_eq(noon.fraction, 0.5, "half way at noon between the winter dawn and the grey dusk")
    assert_eq(winter[noon.first].path.get_file(), "winter.png", "from the winter light")
    assert_eq(winter[noon.second].path.get_file(), "plain.png", "to the one with no season")
    var summer := PictureLights.in_season(lights, "summer")
    var summer_noon := PictureLights.fade_at(summer, 12.0)
    assert_eq(summer[summer_noon.first].path.get_file(), "summer.png", "the summer painter's noon starts from the summer light")
    var none := PictureLights.in_season(lights, "")
    assert_eq(_files(none), ["summer.png", "plain.png"], "a painter with no season is shown summer's")
    assert_eq(PictureLights.in_season(lights, "spring").size(), 1, "spring has no light of its own here, only the one for all")
    assert_eq(winter.size(), lights.size() - 1, "and winter drops only the summer one")


func test_the_band_shows_the_season_of_the_place_it_is_opened_in() -> void:
    var band := WelcomePicture.new("0.1.0", FOLDER)
    assert_eq(band.key, "0.1", "the test folder's picture")
    assert_eq(band.lights.size(), 3, "which lists three lights")
    band.show_at(6.0, PictureLights.season_of(1, "cs_CZ"))
    assert_eq(band.season, "winter", "Czechia in January")
    assert_true(band.picture.texture.resource_path.ends_with("winter.png"), "the winter light at its own hour")
    assert_null(band.over.texture, "with nothing over it")
    band.show_at(6.0, PictureLights.season_of(1, "en_AU"))
    assert_true(band.picture.texture.resource_path.ends_with("summer.png"), "the summer light in Australia")
    band.show_at(12.0, PictureLights.season_of(1, "en_AU"))
    assert_true(band.picture.texture.resource_path.ends_with("summer.png"), "which fades at noon")
    assert_true(band.over.texture.resource_path.ends_with("plain.png"), "into the grey one")
    assert_eq(band.over.modulate.a, 0.5, "half way")
    for locale: String in ["es_EC", "C"]:
        band.show_at(6.0, PictureLights.season_of(1, locale))
        assert_true(band.picture.texture.resource_path.ends_with("summer.png"), "%s sees summer's light at 6" % locale)
        assert_null(band.over.texture, "with nothing over it")
        band.show_at(12.0, PictureLights.season_of(1, locale))
        assert_true(band.over.texture.resource_path.ends_with("plain.png"), "fading at noon into the grey one")
    band.show_at(12.0, PictureLights.season_of(7, "cs_CZ"))
    assert_true(band.picture.texture.resource_path.ends_with("summer.png"), "July in Czechia is the summer light")
    band.free()


func test_a_season_that_leaves_no_light_shows_the_one_picture() -> void:
    var band := WelcomePicture.new()
    var one := load("%s%s.png" % [WelcomePicture.FOLDER, band.key]) as Texture2D
    assert_not_null(one, "the picture named for the version is there")
    assert_false(band.lights.is_empty(), "the shipped sidecar lists its lights")
    for light: PictureLights.Light in band.lights:
        assert_true(PictureLights.SEASONS.has(light.season), "%s is one season's" % light.path.get_file())
    for place: String in ["cs_CZ", "en_AU", "es_EC", "C"]:
        var season := PictureLights.season_of(1, place)
        band.show_at(3.0, season)
        var one_mood := PictureLights.one_each(PictureLights.in_season(band.lights, season), band.mood_roll)
        assert_eq(band.shown.size(), one_mood.size(), "every shipped light of the mood rolled is shown in %s" % place)
        var held := season if not season.is_empty() else "summer"
        for light: PictureLights.Light in band.shown:
            var named := light.path.get_file()
            assert_true(named.begins_with("0.18-%s-" % held), "%s is %s's in %s" % [named, held, place])
    band.lights = [PictureLights.Light.new(band.lights[0].path, 6.0, "winter")]
    band.show_at(6.0, "winter")
    assert_eq(band.shown.size(), 1, "a winter light is shown in winter")
    band.show_at(6.0, "summer")
    assert_true(band.shown.is_empty(), "and not in summer")
    assert_eq(band.picture.texture, one, "where the picture named for the version is shown in its place")
    assert_null(band.over.texture, "with nothing over it")
    band.show_at(6.0, "")
    assert_eq(band.picture.texture, one, "and for a painter with no season")
    band.free()


func test_the_band_reads_the_clocks_season() -> void:
    var season := WelcomeSun.now().season
    assert_true(season.is_empty() or PictureLights.SEASONS.has(season), "one of the four or none: '%s'" % season)
    var band := WelcomePicture.new("0.1.0", FOLDER)
    assert_eq(band.season, season, "the one the band opened in, as the clock had it")
    band.free()
