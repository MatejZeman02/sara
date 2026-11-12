## The Welcome window opens on a painted picture, a band across
## its top as wide as the window and a third of that tall, with the version and
## the credit in its lower right corner.
##
## The window is built and never added to a tree, for the reason
## `test_welcome_window.gd` gives, so the size of the band, its place above the
## panes and the words on it are what is read here. How it looks at a scale of 1
## and of 2, and that a press on it leaves the window up, are
## `scenarios/the-welcome-window-opens-on-a-painted-picture.json`.
extends "res://tests/test_framework.gd"


func test_the_shipped_picture_is_twice_the_band_at_the_opening_width() -> void:
    var window := SaWelcomeWindow.new()
    # Parts an earlier suite left kept are composed on the pool.
    window.band.settle()
    var texture := window.band.picture.texture
    assert_not_null(texture, "the band carries a picture")
    assert_eq(texture.get_size(), Vector2(1440, 480), "1440 by 480, twice the 720 by 240 the band is at the opening width")
    window.free()


func test_the_band_is_above_the_panes() -> void:
    var window := SaWelcomeWindow.new()
    var frame := window.band.get_parent()
    assert_eq(frame.name, "Frame", "the band stands in the frame that holds the whole window")
    assert_eq(window.band.get_index(), 0, "first in it, above the light mode offer and the panes")
    assert_true(frame.get_child(1).is_ancestor_of(window.tabs), "the panes are in what comes after it")
    assert_true(frame.get_child(1).is_ancestor_of(window.light_mode_offer), "and so is the offer")
    window.free()


func test_the_version_line_is_the_projects_version() -> void:
    var window := SaWelcomeWindow.new()
    var version := str(ProjectSettings.get_setting("application/config/version"))
    assert_false(version.is_empty(), "the project has a version")
    assert_eq(window.band.version_line.text, version, "the line in the corner says it")
    window.free()


func test_the_credit_line_is_the_pictures_title_alone() -> void:
    var window := SaWelcomeWindow.new()
    assert_false(window.band.title.is_empty(), "the sidecar gives the picture a title")
    assert_eq(window.band.credit, "", "and no credit")
    assert_eq(window.band.credit_line.text, window.band.title, "so the line says the title alone")
    window.free()


func test_a_minor_without_a_picture_shows_the_newest() -> void:
    var shipped := WelcomePicture.keys_in(WelcomePicture.FOLDER)
    assert_true(shipped.size() > 0, "a picture ships")
    var band := WelcomePicture.new("0.99.3")
    band.settle()
    assert_eq(band.key, WelcomePicture.pick(shipped, "99.99"), "a minor with no picture shows the newest shipped")
    assert_not_null(band.picture.texture, "and that picture loads")
    band.free()
    var patch := WelcomePicture.new("0.18.7")
    assert_eq(patch.key, "0.18", "a patch release keeps its minor's picture")
    patch.free()


func test_the_pick_is_its_own_minor_else_the_newest_numerically() -> void:
    var keys := PackedStringArray(["0.9", "0.18", "1.2"])
    assert_eq(WelcomePicture.pick(keys, "0.9.4"), "0.9", "a minor with its picture shows it, newest or not")
    assert_eq(WelcomePicture.pick(keys, "0.18.0"), "0.18", "and 0.18 is not mistaken for 0.1")
    assert_eq(WelcomePicture.pick(keys, "0.10.0"), "1.2", "a minor with none shows the newest, 0.18 over 0.9 and 1.2 over both")
    assert_eq(WelcomePicture.pick(keys, ""), "1.2", "and so does a version nobody could read")
    assert_eq(WelcomePicture.pick(PackedStringArray(), "0.18.0"), "", "with no pictures there is none to show")


func test_a_version_names_its_picture_by_major_and_minor() -> void:
    assert_eq(WelcomePicture.key_of("0.17.4"), "0.17", "major and minor")
    assert_eq(WelcomePicture.key_of("1.2"), "1.2", "a version of two numbers")
    assert_eq(WelcomePicture.key_of("0.18.0-rc1"), "0.18", "a suffix is left off")
    assert_eq(WelcomePicture.key_of("dev"), "", "a version with no numbers names no picture")
    assert_eq(WelcomePicture.key_of("1"), "", "nor does one with no minor")


func test_the_folder_is_listed_by_its_sidecars() -> void:
    var keys := WelcomePicture.keys_in(WelcomePicture.FOLDER)
    assert_true(keys.has("0.18"), "the working picture of 0.18 is listed")
    for key in keys:
        assert_eq(WelcomePicture.key_of(key), key, "%s is a major and a minor and nothing else" % key)
    assert_eq(WelcomePicture.keys_in("res://ui/welcome/no-such-folder/").size(), 0, "a folder that is not there lists nothing")


func test_the_band_is_a_third_as_tall_as_it_is_wide() -> void:
    assert_eq(WelcomePicture.band_height(720), 240, "240 at the opening width")
    assert_eq(WelcomePicture.band_height(520), 174, "174 at the floor, the third rounded up")
    assert_eq(WelcomePicture.band_height(1440), WelcomePicture.BAND_CEILING, "and the ceiling at twice the width")


func test_the_window_grew_by_the_band_at_its_widths() -> void:
    var window := SaWelcomeWindow.new()
    assert_eq(window.logical_size, Vector2i(720, 780), "540 high and 240 of band, at 720 wide")
    assert_eq(window.logical_min_size, Vector2i(520, 534), "360 high and 174 of band, at the floor's 520 wide")
    window.free()


func test_a_press_on_the_band_is_a_press_on_the_window() -> void:
    var window := SaWelcomeWindow.new()
    window.visible = true
    var on_band := Vector2(float(window.size.x) / 2.0, window.title_strip_height() + 20.0)
    var embedded: Array[Window] = [window]
    assert_false(SaWelcomeWindow.press_closes(on_band, embedded), "a press inside the window, the band included, leaves it up")
    assert_eq(window.band.mouse_filter, Control.MOUSE_FILTER_STOP, "and the band takes it rather than passing it through")
    window.free()
