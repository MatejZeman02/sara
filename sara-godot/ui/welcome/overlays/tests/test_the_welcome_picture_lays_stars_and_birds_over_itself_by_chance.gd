## The Welcome picture lays stars and flocks of birds over itself by chance. A
## sidecar lists `overlays`, each rolled once at every opening of the window,
## drawn when it wins at an opacity in its range and faded with the lights it
## belongs to.
##
## The pictures here are the suite's own in `tests/pictures/`, a dawn at 6 and a
## night at 23, stars of the night and two flocks of the dawn. How they look is
## `scenarios/the-welcome-picture-lays-stars-and-bird-flocks-over-itself-by-chance.json`.
extends "res://tests/test_framework.gd"

const FOLDER := "res://ui/welcome/overlays/tests/pictures/"


func _lights() -> Array[PictureLights.Light]:
    return PictureLights.lights_in(_sidecar(), FOLDER)


func _sidecar() -> Dictionary:
    return JSON.parse_string(FileAccess.get_file_as_string(FOLDER + "0.1.json"))


func test_an_overlay_at_chance_one_is_drawn_and_one_at_chance_nothing_is_not() -> void:
    var sidecar := {
        "overlays": [{"file": "stars.png", "chance": 1}, {"file": "birds-1.png", "chance": 0}],
    }
    var layer := PictureOverlays.new(sidecar, FOLDER)
    assert_eq(layer.overlays.size(), 2, "both overlays of the sidecar are read")
    var lights := _lights()
    var fade := PictureLights.fade_at(lights, 23.0)
    for opening in 20:
        layer.roll_now()
        layer.show_over(lights, fade, 23.0)
        assert_true(layer.layers[0].visible, "the overlay at chance 1 is drawn at opening %d" % opening)
        assert_not_null(layer.layers[0].texture, "with its picture loaded at opening %d" % opening)
        assert_false(layer.layers[1].visible, "the one at chance 0 is absent at opening %d" % opening)
    layer.free()


func test_four_hundred_rolls_at_three_in_four_show_about_three_hundred() -> void:
    var stars := PictureOverlays.Overlay.new(FOLDER + "stars.png", 0.75)
    var dice := RandomNumberGenerator.new()
    dice.randomize()
    var shown := 0
    for i in 400:
        stars.roll(dice.randf(), dice.randf())
        shown += 1 if stars.drawn else 0
    assert_true(shown >= 270 and shown <= 330, "between 270 and 330 of 400 shown, read %d" % shown)


func test_the_kinds_carry_the_chosen_chances() -> void:
    var overlays := PictureOverlays.overlays_in(_sidecar(), FOLDER)
    assert_eq(overlays.size(), 3, "stars and two flocks")
    assert_eq(overlays[0].chance, 0.75, "stars are drawn three openings in four")
    assert_eq(overlays[1].chance, 0.5, "a flock one in two")
    assert_eq(overlays[2].chance, 0.5, "and the second flock too")
    var lights := _lights()
    assert_true(overlays[0].belongs_to(lights[1]), "stars belong to the night")
    assert_false(overlays[0].belongs_to(lights[0]), "and not to the dawn")
    assert_true(overlays[0].at_hour(19.0), "dusk is theirs as well")
    assert_true(overlays[1].belongs_to(lights[0]), "the first flock names the dawn")
    assert_false(overlays[1].belongs_to(lights[1]), "and not the night")
    assert_true(overlays[2].belongs_to(lights[0]), "the second flock's hours take in 6")


func test_an_overlay_is_drawn_inside_its_opacity_range() -> void:
    var stars := PictureOverlays.overlays_in(_sidecar(), FOLDER)[0]
    assert_eq([stars.low, stars.high], [0.6, 1.0], "the sidecar's range")
    var dice := RandomNumberGenerator.new()
    dice.randomize()
    for i in 200:
        stars.roll(0.0, dice.randf())
        assert_true(stars.drawn, "a roll of 0 wins")
        assert_true(stars.opacity >= 0.6 and stars.opacity <= 1.0, "opacity %.3f inside 0.6 to 1" % stars.opacity)
    stars.roll(0.0, 0.5)
    assert_almost_eq(stars.opacity, 0.8, 0.0001, "half way up the range is 0.8")
    stars.roll(0.99, 0.5)
    assert_false(stars.drawn, "a roll over the chance loses")
    assert_eq(stars.opacity, 0.0, "and is drawn at nothing")


func test_an_overlay_fades_with_the_light_it_belongs_to() -> void:
    var layer := PictureOverlays.new(_sidecar(), FOLDER)
    for overlay in layer.overlays:
        overlay.roll(0.0, 1.0)
    var lights := _lights()
    for at: float in [23.0, 1.0, 3.0, 5.0, 6.0, 9.0, 13.0, 20.0]:
        var fade := PictureLights.fade_at(lights, at)
        layer.show_over(lights, fade, at)
        var night_share := (1.0 - fade.fraction) if fade.first == 1 else fade.fraction
        if not fade.faded():
            night_share = 1.0 if fade.first == 1 else 0.0
        var stars_alpha := layer.layers[0].modulate.a
        var birds_alpha := layer.layers[1].modulate.a
        assert_almost_eq(stars_alpha, night_share, 0.0001, "the stars are as much there as the night at %.0f" % at)
        assert_almost_eq(birds_alpha, 1.0 - night_share, 0.0001, "the dawn's flock as much as the dawn at %.0f" % at)
        assert_eq(layer.layers[0].visible, night_share > 0.0, "and the stars are hidden only with no night at %.0f" % at)
    layer.free()


func test_a_debug_roll_fixes_every_overlay() -> void:
    var had := OS.get_environment(PictureOverlays.ROLL_VARIABLE)
    var layer := PictureOverlays.new(_sidecar(), FOLDER)
    OS.set_environment(PictureOverlays.ROLL_VARIABLE, "0")
    layer.roll_now()
    for overlay in layer.overlays:
        assert_true(overlay.drawn, "a roll of 0 draws %s" % overlay.path.get_file())
    assert_almost_eq(layer.overlays[0].opacity, 0.6, 0.0001, "at the lowest of its range")
    OS.set_environment(PictureOverlays.ROLL_VARIABLE, "1")
    layer.roll_now()
    for overlay in layer.overlays:
        assert_false(overlay.drawn, "a roll of 1 draws none, %s" % overlay.path.get_file())
    if had.is_empty():
        OS.unset_environment(PictureOverlays.ROLL_VARIABLE)
    else:
        OS.set_environment(PictureOverlays.ROLL_VARIABLE, had)
    layer.free()


func test_the_band_lays_its_overlays_between_the_lights_and_the_words() -> void:
    var band := WelcomePicture.new("0.1.0", FOLDER)
    assert_eq(band.overlays.get_index(), band.over.get_index() + 1, "the overlays lie over the second light")
    assert_eq(band.overlays.overlays.size(), 3, "and are the sidecar's")
    for overlay in band.overlays.overlays:
        overlay.roll(0.0, 1.0)
    band.show_at(23.0)
    assert_true(band.overlays.layers[0].visible, "the stars are out at 23")
    assert_false(band.overlays.layers[1].visible, "and the dawn's flock is not")
    band.show_at(6.0)
    assert_false(band.overlays.layers[0].visible, "at 6 the stars are gone")
    assert_true(band.overlays.layers[1].visible, "and the flock is there")
    band.free()
