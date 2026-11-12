## The manual's pictures show today's window.
##
## Every picture in `res://manual/pictures/` is a shot of one scenario,
## `scenarios/the-manuals-pictures-show-todays-window.json`, named after the
## picture it replaces, so the next retake is that scenario run again and its
## shots copied over the folder. These hold the three ends together: what the
## pages show, what the folder holds and what the scenario takes. A picture
## added to a page without the scenario taking it fails here, and so does a
## picture left in the folder that no page shows any more.
extends "res://tests/test_framework.gd"

const PICTURES := "res://manual/pictures"
const SCENARIO := "res://scenarios/the-manuals-pictures-show-todays-window.json"
## The window every picture is taken at, by the scenario's `window` step.
const TAKEN_AT := Vector2(1280, 1024)
## The ways a page would name the Settings menu, which went from the menu bar
## before these pictures were taken. Help's Display Settings... and Tablet
## Settings... are rows of Help and are not among them.
const SETTINGS_MENU := ["**Settings**", "Settings menu", "the Settings", "Settings, ", "Settings > "]


## The picture names every page shows, without the folder or the extension.
func _shown() -> Array[String]:
    var names: Array[String] = []
    for path: String in SaManualWindow.page_files():
        for target: String in SaManualWindow.render(path, 600)["pictures"]:
            names.append(target.get_file().get_basename())
    return names


## The pictures the folder holds, by the same names.
func _in_folder() -> Array[String]:
    var names: Array[String] = []
    for file: String in DirAccess.get_files_at(PICTURES):
        if file.get_extension() == "png":
            names.append(file.get_basename())
    names.sort()
    return names


func test_every_picture_a_page_shows_is_there_and_loads_at_the_size_it_was_taken() -> void:
    var shown := _shown()
    assert_true(shown.size() >= 29, "The pages show the pictures, %d of them" % shown.size())
    for picture_name: String in shown:
        var path := PICTURES.path_join(picture_name + ".png")
        assert_true(FileAccess.file_exists(path), "%s is in the folder" % picture_name)
        var picture := load(path) as Texture2D
        assert_not_null(picture, "%s loads as a picture" % picture_name)
        if picture != null:
            assert_eq(picture.get_size(), TAKEN_AT, "%s is a shot of the window at 1280 by 1024" % picture_name)


func test_every_picture_in_the_folder_is_shown_by_a_page() -> void:
    var shown := _shown()
    var folder := _in_folder()
    assert_false(folder.is_empty(), "The folder holds pictures")
    for picture_name: String in folder:
        assert_true(shown.has(picture_name), "%s is shown by some page" % picture_name)


func test_the_scenario_takes_every_picture_once_under_its_name() -> void:
    if not FileAccess.file_exists(SCENARIO):
        skip("the scenario that retakes the manual's pictures is not in this copy of the source")
        return
    var steps: Variant = JSON.parse_string(FileAccess.get_file_as_string(SCENARIO))
    assert_true(steps is Array, "The scenario reads as a list of steps")
    if not steps is Array:
        return
    var shots: Array[String] = []
    for step: Variant in steps:
        if step is Dictionary and (step as Dictionary).has("shot"):
            shots.append(String(step["shot"]))
    var taken := shots.duplicate()
    taken.sort()
    for index: int in range(1, taken.size()):
        assert_true(taken[index] != taken[index - 1], "%s is taken once" % taken[index])
    assert_eq(taken, _in_folder(), "The scenario's shots are the folder's pictures, name for name")


func test_no_page_names_the_settings_menu() -> void:
    for path: String in SaManualWindow.page_files():
        var text := FileAccess.get_file_as_string(path)
        for naming: String in SETTINGS_MENU:
            assert_false(text.contains(naming), "%s does not name the Settings menu as '%s'" % [path.get_file(), naming])
