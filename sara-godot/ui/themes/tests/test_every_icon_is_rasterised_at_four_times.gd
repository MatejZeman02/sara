## Every shipped icon is at least as wide as a choice row draws it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A choice row's icon is capped at `SaChoicePopup.ICON_SIZE` rather than
## expanded, because every icon is imported at `svg/scale=4.0` and the cap
## sizes it. An import at `svg/scale=1.0` with no mipmaps gives a 16 pixel
## texture, under the cap of 18, and the paint flyout would draw that icon at 16
## and start its label two logical pixels left of its neighbours', while a
## toolbox button, which expands its icon, would draw a 16 pixel picture
## upscaled. Every icon is imported at four times, the scale an icon's SVG
## import file must carry.
##
## What a person sees is
## `scenarios/the-gradient-and-crop-icons-are-rasterised-at-four-times-like-the-rest.json`,
## the paint flyout at interface scale 2 with its four labels at one x.
extends "res://tests/test_framework.gd"

const ICONS := "res://assets/icons"

## The scale every SVG's import file carries.
const SVG_SCALE := 4.0


## Every picture in the folder, by its source name. Read from the import files
## rather than the sources, because an exported build lists only those.
func _icons() -> Array[String]:
    var found: Array[String] = []
    for file: String in DirAccess.get_files_at(ICONS):
        if file.get_extension() == "import":
            found.append(file.get_basename())
    return found


func test_there_are_icons_to_check() -> void:
    assert_true(_icons().size() >= 40, "res://assets/icons holds the icon set, found %d" % _icons().size())


## The clause the row is held to. A texture under the cap is drawn at its
## own size, so its row's label starts left of its neighbours'.
func test_every_icon_is_at_least_a_choice_rows_icon_wide() -> void:
    for icon: String in _icons():
        var texture := load(ICONS.path_join(icon)) as Texture2D
        assert_not_null(texture, "%s loads as a texture" % icon)
        if texture == null:
            continue
        assert_true(
            texture.get_width() >= SaChoicePopup.ICON_SIZE,
            "%s is %d pixels wide, under a choice row's %d" % [icon, texture.get_width(), SaChoicePopup.ICON_SIZE]
        )


## The cause, held so that a new SVG drawn at 24 and imported at one times
## fails here too, although its width passes the clause above.
func test_every_svg_is_imported_at_four_times_with_mipmaps() -> void:
    for icon: String in _icons():
        if icon.get_extension() != "svg":
            continue
        var config := ConfigFile.new()
        assert_eq(config.load(ICONS.path_join(icon + ".import")), OK, "%s has an import file" % icon)
        assert_eq(float(config.get_value("params", "svg/scale", 0.0)), SVG_SCALE, "%s is rasterised at four times" % icon)
        assert_true(bool(config.get_value("params", "mipmaps/generate", false)), "%s has mipmaps for the downscale" % icon)


## The two icons the check was first written for, by name, so the record says which they were.
func test_the_gradient_and_crop_icons_are_four_times_their_drawing() -> void:
    for icon: String in ["gradient", "crop"]:
        var texture := SaUI.get_icon(icon)
        assert_not_null(texture, "%s resolves through SaUI.get_icon" % icon)
        if texture != null:
            assert_eq(texture.get_width(), 64, "%s is its 16 pixel drawing at four times" % icon)
