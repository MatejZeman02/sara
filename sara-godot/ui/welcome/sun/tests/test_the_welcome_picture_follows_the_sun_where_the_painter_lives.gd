## The Welcome picture follows the sun where the painter lives,
## guessed from the time zone. A zone's name gives the place of its city, the
## locale's country is taken only when the clock keeps one of its offsets, and
## past that daylight saving gives the side of the equator. The sun there sets
## within half an hour of a published table, and a sidecar of sun lights fades
## by the sun's place in its day, so a Swedish midsummer night is never full
## night.
##
## The sunsets below are api.sunrise-sunset.org's for 15 June and 15 December
## 2026, read on 2026-10-12 in UTC and set in each city's local time.
extends "res://tests/test_framework.gd"

const FOLDER := "res://ui/welcome/tests/pictures/seasons/"

## The city, the month, the season it reads and the published sunset in local
## minutes after midnight.
const TABLE: Array = [
    ["Europe/Stockholm", 6, "summer", 22 * 60 + 9],
    ["Europe/Stockholm", 12, "winter", 14 * 60 + 50],
    ["America/Guayaquil", 6, "", 18 * 60 + 21],
    ["America/Guayaquil", 12, "", 18 * 60 + 23],
    ["Pacific/Auckland", 6, "winter", 17 * 60 + 12],
    ["Pacific/Auckland", 12, "summer", 20 * 60 + 37],
]


func _clock(minutes: float) -> String:
    return "%02d:%02d" % [floori(minutes / 60.0), floori(fposmod(minutes, 60.0))]


func _night_sidecar() -> Dictionary:
    return {
        "variants":
        [
            {"file": "summer.png", "sun": 30, "side": "rising"},
            {"file": "winter.png", "sun": -4, "side": "setting"},
            {"file": "plain.png", "sun": -18, "side": "setting"},
            {"file": "plain.png", "sun": -18, "side": "rising"},
        ]
    }


func _files(lights: Array[PictureLights.Light]) -> Array[String]:
    var named: Array[String] = []
    for light in lights:
        named.append(light.path.get_file())
    return named


func test_three_cities_read_their_season_and_a_sunset_within_half_an_hour_of_the_table() -> void:
    var read: Array[String] = []
    for row: Array in TABLE:
        var place := SaLocation.place_of_zone(row[0], row[1])
        assert_eq(place.how, SaLocation.BY_ZONE, "%s is a zone of the table" % row[0])
        var noon := WelcomeSun.local_moment(2026, row[1], 15, 12.0, place.offset)
        var moment := WelcomeSun.Moment.new(place, noon)
        assert_eq(moment.season, row[2], "%s in month %d reads '%s'" % [row[0], row[1], row[2]])
        var sunset := WelcomeSun.sunset_at(place, noon)
        assert_false(is_nan(sunset), "the sun goes down in %s" % row[0])
        var local := fposmod(sunset + place.offset * 60.0, 86400.0) / 60.0
        var published: int = row[3]
        read.append("%s %d: %s, table %s" % [row[0], row[1], _clock(local), _clock(published)])
        var said := "%s in month %d sets at %s, the table says %s" % [row[0], row[1], _clock(local), _clock(published)]
        assert_true(absf(local - published) <= 30.0, said)
    print("sunsets read: ", "; ".join(read))


func test_stockholm_at_half_past_eleven_on_midsummer_is_twilight_and_never_full_night() -> void:
    var place := SaLocation.place_of_zone("Europe/Stockholm", 6)
    assert_eq(place.offset, 120, "Swedish summer time is two hours ahead")
    var late := WelcomeSun.local_moment(2026, 6, 21, 23.5, place.offset)
    var sky := WelcomeSun.sky_at(place, late)
    print("Stockholm 21 June 23:30: sun at %.2f, lowest %.2f" % [sky.height, sky.lowest])
    assert_true(sky.height < 0.0 and sky.height > -12.0, "twilight, the sun %.2f degrees down" % sky.height)
    assert_true(sky.lowest > -12.0, "and it goes no lower than %.2f that night" % sky.lowest)
    var lights := PictureLights.lights_in(_night_sidecar(), FOLDER)
    assert_true(PictureLights.by_sun(lights), "a sidecar of sun lights fades by the sun")
    var band := WelcomePicture.new("0.1.0", FOLDER)
    band.lights = lights
    band.show_at(23.5, "summer", sky)
    assert_false(_files(band.shown).has("plain.png"), "the night lights at -18 are out of the sun's reach")
    assert_true(band.picture.texture.resource_path.ends_with("winter.png"), "the dusk light is under")
    assert_true(band.over.modulate.a < 1.0, "and nothing over it is whole")
    band.free()


func test_stockholm_at_half_past_eleven_in_december_is_full_night() -> void:
    var place := SaLocation.place_of_zone("Europe/Stockholm", 12)
    var sky := WelcomeSun.sky_at(place, WelcomeSun.local_moment(2026, 12, 21, 23.5, place.offset))
    assert_true(sky.height < -18.0, "the sun is %.2f degrees down" % sky.height)
    var shown := PictureLights.reached(PictureLights.lights_in(_night_sidecar(), FOLDER), sky)
    assert_false(_files(shown).has("summer.png"), "a day light at 30 is past a December noon")
    var fade := PictureLights.fade_by_sun(shown, sky)
    assert_eq(shown[fade.first].path.get_file(), "plain.png", "night under")
    assert_eq(shown[fade.second].path.get_file(), "plain.png", "and night over it")


func test_the_sun_turns_round_its_day_with_no_jump_at_the_lowest() -> void:
    var before := WelcomeSun.SunNow.new(-7.0, false, -7.2, 53.9)
    var after := WelcomeSun.SunNow.new(-7.0, true, -7.2, 53.9)
    var lights := PictureLights.reached(PictureLights.lights_in(_night_sidecar(), FOLDER), before)
    var dusk := PictureLights.fade_by_sun(lights, before)
    var dawn := PictureLights.fade_by_sun(lights, after)
    assert_eq(dusk.first, dawn.first, "the same pair either side of the night's lowest")
    assert_almost_eq(dusk.fraction, dawn.fraction, 0.05, "at nearly the same fraction")


func test_with_no_zone_an_american_locale_on_a_central_european_clock_is_set_aside() -> void:
    var july := SaLocation.guess("", "en_US", 120, true, 7)
    assert_eq(july.how, SaLocation.BY_OFFSET, "the locale's country keeps no +2 in July")
    assert_eq(july.country, "", "so it is set aside")
    assert_true(july.latitude > WelcomeSun.TROPIC, "daylight saving in July is the north, at %.2f" % july.latitude)
    assert_eq(WelcomeSun.season_at(7, july.latitude), "summer", "and its summer")
    var january := SaLocation.guess("", "en_US", 60, false, 1)
    assert_eq(january.how, SaLocation.BY_OFFSET, "nor a +1 in January")
    assert_true(january.latitude > WelcomeSun.TROPIC, "no daylight saving in January is the north, at %.2f" % january.latitude)
    assert_eq(WelcomeSun.season_at(1, january.latitude), "winter", "and its winter")
    var auckland := SaLocation.guess("", "en_US", 780, true, 1)
    assert_true(auckland.latitude < -WelcomeSun.TROPIC, "daylight saving in January is the south")
    var odd := SaLocation.guess("", "en_US", 7 * 60 + 17, false, 1)
    assert_eq(odd.how, SaLocation.BY_NOTHING, "a clock no zone keeps tells nothing")
    assert_eq(odd.latitude, 0.0, "and is the equator")
    assert_eq(WelcomeSun.season_at(1, odd.latitude), "", "with no season")


func test_the_locale_is_kept_when_its_country_keeps_the_clock() -> void:
    var czech := SaLocation.guess("", "cs_CZ", 60, false, 1)
    assert_eq(czech.how, SaLocation.BY_LOCALE, "Czechia keeps +1 in January")
    assert_eq(czech.zone, "Europe/Prague", "at Prague")
    var american := SaLocation.guess("", "en_US", -300, false, 1)
    assert_eq(american.how, SaLocation.BY_LOCALE, "the United States keeps -5 in January")
    var named := SaLocation.guess("Pacific/Auckland", "en_US", 120, true, 7)
    assert_eq(named.how, SaLocation.BY_ZONE, "a zone's name comes before the locale")
    assert_eq(named.zone, "Pacific/Auckland", "and is the place")


func test_old_names_and_windows_names_find_their_zone() -> void:
    assert_eq(SaLocation.tz_name("Europe/Kiev"), "Europe/Kyiv", "an old name is its link's")
    assert_eq(SaLocation.tz_name("Central Europe Standard Time"), "Europe/Budapest", "a Windows name is CLDR's world zone")
    assert_eq(SaLocation.tz_name("Central Europe Daylight Time"), "Europe/Budapest", "in summer too")
    assert_eq(SaLocation.tz_name("CEST"), "", "an abbreviation is no zone")
    assert_eq(SaLocation.zone_row("Europe/Stockholm")[2], "SE", "Stockholm is Sweden's own row")
    var found := SaLocation.system_zone("")
    assert_true(found.is_empty() or not SaLocation.tz_name(found).is_empty(), "the system's '%s' is the table's or none" % found)
