## The Welcome picture ships its repaint: six lights,
## dawn, three day moods, dusk and night, each by the sun, the day moods taking
## turns at each opening by a roll, and the stars and flocks laid over the
## lights they show in by chance.
##
## The light a band shows is read off `shown` rather than its texture's path,
## because the band shows a texture composed from the light's parts.
##
## The sidecar is the shipped `0.18.json`, which
## `scripts/export_welcome_lights.py` wrote from the source document. How the
## window looks is
## `scenarios/the-welcome-picture-ships-the-repaint-every-light-and-mood-with-stars-and-birds-by-chance.json`.
extends "res://tests/test_framework.gd"

const SHIPPED := "res://ui/welcome/pictures/"

const MOODS: Array[String] = ["0.18-summer-day-clear.png", "0.18-summer-day-hazy.png", "0.18-summer-day-overcast.png"]


## Summer's lights, the ones the shipped repaint was, which are one season of four.
func _lights() -> Array[PictureLights.Light]:
    var sidecar: Variant = JSON.parse_string(FileAccess.get_file_as_string(SHIPPED + "0.18.json"))
    return PictureLights.in_season(PictureLights.lights_in(sidecar, SHIPPED), "summer")


func _files(lights: Array[PictureLights.Light]) -> Array[String]:
    var named: Array[String] = []
    for light in lights:
        named.append(light.path.get_file())
    return named


## Prague at noon on 15 June 2026, where every light the sidecar lists is
## reached.
func _prague(hour: float) -> WelcomeSun.SunNow:
    var place := SaLocation.place_of_zone("Europe/Prague", 6)
    return WelcomeSun.sky_at(place, WelcomeSun.local_moment(2026, 6, 15, hour, place.offset))


func test_the_new_sidecar_lists_six_lights_every_one_by_the_sun() -> void:
    var lights := _lights()
    var files := _files(lights)
    for light: String in ["0.18-summer-dawn.png", "0.18-summer-dusk.png", "0.18-summer-night.png"] + MOODS:
        assert_true(files.has(light), "%s is a light of the sidecar" % light)
    assert_false(files.has("0.18-day.png"), "the old day is gone")
    assert_false(ResourceLoader.exists(SHIPPED + "0.18-day.png"), "and its file with it")
    assert_false(files.has("0.18.png"), "the one picture is no light")
    var plain := FileAccess.get_file_as_bytes(SHIPPED + "0.18.png")
    assert_eq(plain, FileAccess.get_file_as_bytes(SHIPPED + "0.18-summer-dawn.png"), "summer's dawn when no light is left")
    assert_true(PictureLights.by_sun(lights), "every light names a sun, so the picture fades by the sun")
    for light in lights:
        var texture := load(light.path) as Texture2D
        assert_eq(texture.get_size(), Vector2(1440, 480), "%s is twice the opening band" % light.path.get_file())


func test_a_thousand_openings_roll_the_day_moods_by_their_weights() -> void:
    var lights := _lights()
    var counts := {}
    for mood in MOODS:
        counts[mood] = 0
    var dice := RandomNumberGenerator.new()
    dice.seed = 175
    for opening in 1000:
        var kept := PictureLights.one_each(lights, dice.randf())
        var days: Array[String] = []
        for light in kept:
            if MOODS.has(light.path.get_file()):
                days.append(light.path.get_file())
        assert_eq(days.size(), 2, "one day kept at the rising and one at the setting sun, opening %d" % opening)
        assert_eq(days[0], days[days.size() - 1], "the same mood at both, opening %d" % opening)
        counts[days[0]] += 1
    var clear: int = counts["0.18-summer-day-clear.png"]
    var hazy: int = counts["0.18-summer-day-hazy.png"]
    var overcast: int = counts["0.18-summer-day-overcast.png"]
    assert_true(absi(clear - 500) < 60, "the clear day half the time: %d" % clear)
    assert_true(absi(hazy - 250) < 50, "the hazy a quarter: %d" % hazy)
    assert_true(absi(overcast - 250) < 50, "the overcast a quarter: %d" % overcast)


func test_a_fixed_roll_reads_each_mood_where_its_weight_stands() -> void:
    var cases: Array = [
        [0.0, "0.18-summer-day-clear.png"],
        [0.2, "0.18-summer-day-clear.png"],
        [0.49, "0.18-summer-day-clear.png"],
        [0.5, "0.18-summer-day-hazy.png"],
        [0.6, "0.18-summer-day-hazy.png"],
        [0.75, "0.18-summer-day-overcast.png"],
        [0.9, "0.18-summer-day-overcast.png"],
        [1.0, "0.18-summer-day-overcast.png"],
    ]
    for case: Array in cases:
        var band := WelcomePicture.new("0.18.0", SHIPPED)
        band.mood_roll = case[0]
        band.show_at(13.0, "summer", _prague(13.0))
        assert_eq(band.shown[band.fade.first].path.get_file(), case[1], "a roll of %s shows %s at noon" % case)
        assert_true(band.over.texture == null or band.shown[band.fade.second].path.get_file() == case[1], "and nothing else")
        band.free()


func test_a_moment_that_only_one_light_holds_reads_that_light() -> void:
    var lights := _lights()
    for roll: float in [0.0, 0.3, 0.6, 1.0]:
        var kept := _files(PictureLights.one_each(lights, roll))
        for alone: String in ["0.18-summer-dawn.png", "0.18-summer-dusk.png", "0.18-summer-night.png"]:
            assert_eq(kept.count(alone), 1, "%s is kept whatever the roll, at %s" % [alone, roll])
        assert_eq(kept.size(), 5, "and one day at each of its two sides")
    var place := SaLocation.place_of_zone("Europe/Prague", 6)
    var band := WelcomePicture.new("0.18.0", SHIPPED)
    var sunrise := WelcomeSun.local_moment(2026, 6, 15, 4.0, place.offset)
    var sky := WelcomeSun.sky_at(place, sunrise)
    var dawn := WelcomeSun.SunNow.new(0.0, true, sky.lowest, sky.highest)
    for roll: float in [0.0, 1.0]:
        band.mood_roll = roll
        band.show_at(4.9, "summer", dawn)
        assert_eq(band.shown[band.fade.first].path.get_file(), "0.18-summer-dawn.png", "the rising sun on the horizon")
        assert_null(band.over.texture, "alone, at a roll of %s" % roll)
    band.free()


func test_the_stars_show_three_openings_in_four_at_an_opacity_drawn_each_time() -> void:
    var sidecar: Variant = JSON.parse_string(FileAccess.get_file_as_string(SHIPPED + "0.18.json"))
    var layer := PictureOverlays.new(sidecar, SHIPPED)
    var stars: Array[PictureOverlays.Overlay] = []
    var flocks := 0
    for overlay in layer.overlays:
        if overlay.path.get_file().ends_with("-stars.png"):
            stars.append(overlay)
            var stars_says := "%s at the stars' chance" % overlay.path.get_file()
            assert_almost_eq(overlay.chance, PictureOverlays.STARS_CHANCE, 0.0001, stars_says)
        else:
            flocks += 1
            var birds_says := "%s at the birds' chance" % overlay.path.get_file()
            assert_almost_eq(overlay.chance, PictureOverlays.BIRDS_CHANCE, 0.0001, birds_says)
    # The summer night is a midsummer twilight painted over the whole
    # sky, so the shared stars and two of the flocks do not show in it and the
    # export writes no file for them.
    var summer := _names(stars).filter(func(named: String) -> bool: return named.begins_with("0.18-summer-"))
    assert_eq(summer, ["0.18-summer-dusk-stars.png"], "the stars of the dusk, the night's twilight hides them")
    var spring := _names(stars).filter(func(named: String) -> bool: return named.begins_with("0.18-spring-"))
    assert_eq(spring, ["0.18-spring-dusk-stars.png", "0.18-spring-night-stars.png"], "the stars of the dusk and of the night")
    assert_eq(stars.size(), 7, "in each of the four seasons, summer's night but")
    assert_eq(flocks, 70, "three flocks over each of the six lights of each season, summer's night one")
    var drawn := 0
    var opacities := {}
    for opening in 400:
        layer.roll_now()
        assert_eq(stars[0].drawn, stars[1].drawn, "the dusk's and the night's stars are one sky, opening %d" % opening)
        assert_almost_eq(stars[0].opacity, stars[1].opacity, 0.0001, "at one opacity")
        if stars[0].drawn:
            drawn += 1
            opacities[snappedf(stars[0].opacity, 0.05)] = true
    assert_true(absi(drawn - 300) < 40, "drawn three openings in four: %d of 400" % drawn)
    assert_true(opacities.size() > 5, "at an opacity drawn per opening, %d of them" % opacities.size())
    layer.free()


func _names(overlays: Array[PictureOverlays.Overlay]) -> Array[String]:
    var named: Array[String] = []
    for overlay in overlays:
        named.append(overlay.path.get_file())
    return named
