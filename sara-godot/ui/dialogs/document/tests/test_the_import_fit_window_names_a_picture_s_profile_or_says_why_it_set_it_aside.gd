## The Import Fit window names the colour profile a picture carries, and says
## why it set aside one Sara cannot use.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The pictures are the ones `scripts/make_profiled_pictures.py` writes for the
## suite in `core/image/tests` that reads their profiles. Each is asked the way
## `SaDocumentFiles` asks it and handed to a detached window, because a
## `Window` added to the tree in a headless run hangs. The scenario
## `scenarios/a-picture-opens-in-the-colours-its-embedded-profile-names.json`
## shoots the same window over the running app.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const FOLDER := "res://core/image/tests/fixtures/profiled/"

## The skeleton's formats with the image formats module's after them, as the
## running app registers them, built again before each test.
var _formats: SaRegistries


func before_each() -> void:
    _formats = Fixtures.make_picture_registries()


## The Import Fit window names the profile it read, and says why it set aside
## one it could not use.
func test_the_import_fit_window_names_the_profile_or_says_why_it_was_not_used() -> void:
    var adobe := _window_for(FOLDER + "adobe_rgb.jpg")
    var line := _line_of(adobe)
    assert_true(line.contains("Adobe RGB (1998)"), "The line names the profile: %s" % line)
    assert_eq(adobe.chosen_space().id, SaColorSpace.ID_CUSTOM, "The row is on the profile's space")
    adobe.free()
    var lut := _window_for(FOLDER + "lookup_table.jpg")
    line = _line_of(lut)
    assert_true(line.contains("Coated Paper LUT"), "The line names the profile it set aside: %s" % line)
    assert_true(line.contains("lookup table profile, which Sara does not read"), "and why: %s" % line)
    assert_true(line.contains("Sara assumes sRGB"), "and what the row starts at: %s" % line)
    assert_eq(lut.chosen_space().id, SaColorSpace.ID_SRGB, "which is sRGB")
    lut.free()


func _window_for(path: String) -> SaImportFitDialog:
    var named := SaImageImport.named_space_for(path)
    var dialog := SaImportFitDialog.new()
    var source := named if named != null else SaImageImport.convention_for(path)
    dialog.configure(Vector2i(32, 16), Vector2i(1920, 1080), source, named != null, SaImageImport.profile_for(path))
    return dialog


func _line_of(dialog: SaImportFitDialog) -> String:
    var hint := dialog.page.row(&"space").line.find_child("Hint", true, false) as Label
    return hint.text if hint != null else ""
