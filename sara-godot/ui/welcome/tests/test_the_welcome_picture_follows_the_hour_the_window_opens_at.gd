## The Welcome picture follows the hour the window opens at. A
## picture may come in lights, the same painting at another hour, and the band
## shows the two either side of the local hour, the second over the first at the
## fraction of the way between them.
##
## The lights here are two plain pictures in `tests/pictures/`, a blue morning at
## 6 and a red evening at 18 with a disc on each side, listed in the sidecar out
## of order. How the fade looks is
## `scenarios/the-welcome-picture-follows-the-hour-the-window-opens-at.json`.
extends "res://tests/test_framework.gd"

const FOLDER := "res://ui/welcome/tests/pictures/"


func _lights(hours: Array) -> Array[PictureLights.Light]:
    var made: Array[PictureLights.Light] = []
    for at: float in hours:
        made.append(PictureLights.Light.new("", at))
    return made


func test_the_fade_between_six_and_eighteen_is_read_at_four_times_of_day() -> void:
    var lights := _lights([6.0, 18.0])
    assert_eq(PictureLights.fade_at(lights, 6.0).fraction, 0.0, "all of the first at 6:00")
    assert_eq(PictureLights.fade_at(lights, 12.0).fraction, 0.5, "half way at 12:00")
    assert_eq(PictureLights.fade_at(lights, 18.0).fraction, 1.0, "all of the second at 18:00")
    var midnight := PictureLights.fade_at(lights, 0.0)
    assert_eq(midnight.fraction, 0.5, "half way at 0:00, over the night from 18 round to 6")
    assert_eq([midnight.first, midnight.second], [1, 0], "from the evening to the morning, round the circle")
    var noon := PictureLights.fade_at(lights, 12.0)
    assert_eq([noon.first, noon.second], [0, 1], "and from the morning to the evening by day")


func test_one_light_has_no_fade() -> void:
    var one := _lights([6.0])
    for at: float in [0.0, 6.0, 12.0, 23.5]:
        var fade := PictureLights.fade_at(one, at)
        assert_false(fade.faded(), "no second light at %.1f" % at)
        assert_eq(fade.fraction, 0.0, "and none of it over the first at %.1f" % at)
        assert_eq(fade.first, 0, "the one light is on show at %.1f" % at)
    assert_eq(PictureLights.fade_at(_lights([]), 12.0).first, -1, "no lights, no first either")


func test_four_lights_fade_along_the_circle() -> void:
    var four := _lights([6.0, 13.0, 19.0, 23.0])
    var morning := PictureLights.fade_at(four, 9.5)
    assert_eq([morning.first, morning.second], [0, 1], "9:30 is between dawn and day")
    assert_almost_eq(morning.fraction, 0.5, 0.0001, "half way between 6 and 13")
    var late := PictureLights.fade_at(four, 3.0)
    assert_eq([late.first, late.second], [3, 0], "3:00 is between night and the next dawn")
    assert_almost_eq(late.fraction, 4.0 / 7.0, 0.0001, "four of the seven hours from 23 to 6")
    var after := PictureLights.fade_at(four, 23.5)
    assert_eq([after.first, after.second], [3, 0], "23:30 is just past night")
    assert_almost_eq(after.fraction, 0.5 / 7.0, 0.0001, "half an hour into the seven")
    var round_the_clock := PictureLights.fade_at(four, 30.0)
    assert_eq(round_the_clock.fraction, PictureLights.fade_at(four, 6.0).fraction, "30 hours is read as 6")


func test_lights_that_share_an_hour_do_not_divide_by_nothing() -> void:
    var twins := _lights([6.0, 6.0])
    assert_eq(PictureLights.fade_at(twins, 6.0).fraction, 0.0, "a span with no length is none of the second")
    assert_eq(PictureLights.fade_at(twins, 15.0).fraction, 0.375, "and round the circle it is 9 of the 24 hours at 15:00")


func test_a_sidecar_lists_its_lights_by_hour() -> void:
    var sidecar: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FOLDER + "0.1.json"))
    var lights := PictureLights.lights_in(sidecar, FOLDER)
    assert_eq(lights.size(), 2, "both pictures of the sidecar are lights")
    assert_eq(lights[0].path, FOLDER + "morning.png", "the morning comes first though the sidecar lists it second")
    assert_eq(lights[0].hour, 6.0, "at 6")
    assert_eq(lights[1].path, FOLDER + "evening.png", "then the evening")
    assert_eq(lights[1].hour, 18.0, "at 18")


func test_an_entry_that_cannot_be_a_light_is_left_out() -> void:
    var sidecar := {
        "variants":
        [
            {"file": "morning.png", "hour": 6},
            {"file": "no-such-picture.png", "hour": 9},
            {"file": "evening.png"},
            {"file": "../pictures/evening.png", "hour": 18},
            {"file": "evening.png", "hour": "18"},
            {"hour": 12},
            "evening.png",
            {"file": "evening.png", "hour": 30.5},
        ]
    }
    var lights := PictureLights.lights_in(sidecar, FOLDER)
    assert_eq(lights.size(), 2, "the two with a bare file that is there and an hour that is a number")
    assert_eq(lights[0].path, FOLDER + "morning.png", "the morning")
    assert_eq(lights[1].hour, 6.5, "and the evening, whose 30.5 is read round the clock as 6.5")
    assert_eq(PictureLights.lights_in({"variants": "evening.png"}, FOLDER).size(), 0, "a list that is not a list lists none")
    assert_eq(PictureLights.lights_in({}, FOLDER).size(), 0, "and a sidecar with no list lists none")


func test_the_band_shows_the_second_over_the_first_at_the_fraction() -> void:
    var band := WelcomePicture.new("0.1.0", FOLDER)
    assert_eq(band.key, "0.1", "the test folder's picture")
    assert_eq(band.title, "A test picture", "with its own words")
    band.show_at(12.0)
    assert_eq(band.fade.fraction, 0.5, "half way at noon")
    assert_true(band.picture.texture.resource_path.ends_with("morning.png"), "the morning under")
    assert_true(band.over.texture.resource_path.ends_with("evening.png"), "the evening over it")
    assert_eq(band.over.modulate.a, 0.5, "at half")
    band.show_at(6.0)
    assert_eq(band.over.modulate.a, 0.0, "nothing of the second at its first light")
    assert_null(band.over.texture, "and it is not even loaded")
    band.show_at(18.0)
    assert_eq(band.over.modulate.a, 1.0, "all of the evening at 18:00")
    band.show_at(0.0)
    assert_true(band.picture.texture.resource_path.ends_with("evening.png"), "the evening under at midnight")
    assert_true(band.over.texture.resource_path.ends_with("morning.png"), "and the morning coming over it")
    band.free()


func test_the_band_opens_at_the_clocks_hour() -> void:
    var before := WelcomeSun.now().hour
    var band := WelcomePicture.new("0.1.0", FOLDER)
    var after := WelcomeSun.now().hour
    assert_true(band.hour >= 0.0 and band.hour < 24.0, "an hour of the day")
    # A run across midnight reads either side of it.
    assert_true((band.hour >= before and band.hour <= after) or after < before, "the one the clock gave as it was built")
    band.free()


func test_a_picture_with_no_list_is_the_one_picture() -> void:
    var band := WelcomePicture.new("0.1.0", "res://ui/welcome/no-such-folder/")
    assert_true(band.lights.is_empty(), "no folder, no lights")
    assert_false(band.fade.faded(), "and no fade")
    band.free()
    var listless := PictureLights.lights_in({"title": "x"}, FOLDER)
    assert_eq(listless.size(), 0, "a sidecar with no list lists none, and the picture named for its key is the one shown")
