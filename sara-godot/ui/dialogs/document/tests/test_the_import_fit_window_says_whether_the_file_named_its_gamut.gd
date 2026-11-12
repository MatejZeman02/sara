## The Import Fit window says whether the file named its gamut.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The window's line under "Read the picture as" said "No format says which
## gamut it holds", and its header said the gamut is readable in none of the
## formats Sara opens. A PNG's `cICP` and a TIFF's profile both say
## it, and the dropdown already opened on what they said, so the painter read a
## sentence the window had just proved wrong.
##
## Each picture here is asked the way `SaDocumentFiles` asks it, the gamut the
## file names or else the format's convention, and handed to a detached window
## because a `Window` added to the tree in a headless run hangs. The two shots
## `scenarios/the-import-fit-window-says-whether-the-file-named-its-gamut.json`
## takes are the same window over the running app.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A PNG whose `cICP` names Display P3, and one that names nothing.
const P3_PNG := "res://tests/data/display_p3_cicp.png"
const PLAIN_PNG := "res://tests/data/import_gradient.png"
const JPEG := "res://tests/data/import_gradient.jpg"
const EXR := "res://tests/data/import_linear.exr"

var _scratch: Array[String] = []

## The skeleton's formats with the image formats module's after them, as the
## running app registers them, built again before each test.
var _formats: SaRegistries


func before_each() -> void:
    _formats = Fixtures.make_picture_registries()


func after_each() -> void:
    for path in _scratch:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    _scratch.clear()


func _tiff(name: String, profile: PackedByteArray) -> String:
    var picture := Image.create_empty(2, 2, false, Image.FORMAT_RGBAF)
    picture.fill(Color(0.25, 0.5, 0.75, 1.0))
    var path := SaDataRoot.path(name)
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(Fixtures.tiff_bytes(picture, 96.0, profile))
    file.close()
    _scratch.append(path)
    return path


func _p3_profile() -> PackedByteArray:
    return SaExportGamut.profile_for(SaGamut.from_id(SaGamut.ID_DISPLAY_P3))


## The window for *path*, built from the two answers the import gives.
func _window_for(path: String) -> SaImportFitDialog:
    var named := SaImageImport.named_space_for(path)
    var dialog := SaImportFitDialog.new()
    dialog.configure(
        Vector2i(300, 200), Vector2i(1920, 1080), named if named != null else SaImageImport.convention_for(path), named != null
    )
    return dialog


## The line as the painter reads it, off the label the page drew.
func _line_of(dialog: SaImportFitDialog) -> String:
    var hint := dialog.page.row(&"space").line.find_child("Hint", true, false) as Label
    return hint.text if hint != null else ""


func _tooltip_of(dialog: SaImportFitDialog) -> String:
    return dialog.page.row(&"space").control.tooltip_text


## A PNG that carries a `cICP` for Display P3 is read as Display P3, the row is
## on it and the line says the file named it.
func test_a_png_with_a_cicp_is_named_in_the_line() -> void:
    var dialog := _window_for(P3_PNG)
    assert_eq(dialog.chosen_space().id, SaColorSpace.ID_DISPLAY_P3, "The row opens on the gamut the cICP names")
    var line := _line_of(dialog)
    assert_true(line.contains("The file names its colour space"), "and the line says the file named it: %s" % line)
    assert_true(line.contains("Display P3"), "and which gamut it is: %s" % line)
    assert_false(line.contains("Sara assumes"), "and it does not fall back to the usual space")
    assert_false(line.contains("No format"), "nor to the old claim that no format says: %s" % line)
    assert_true(_tooltip_of(dialog).contains("Display P3"), "The tooltip names it too: %s" % _tooltip_of(dialog))
    dialog.free()


## A TIFF written with one of Sara's profiles is named the same way.
func test_a_tiff_with_one_of_saras_profiles_is_named_in_the_line() -> void:
    var dialog := _window_for(_tiff("c1_p3.tif", _p3_profile()))
    assert_eq(dialog.chosen_space().id, SaColorSpace.ID_DISPLAY_P3, "The row opens on the gamut the profile names")
    var line := _line_of(dialog)
    assert_true(line.contains("The file names its colour space"), "and the line says the file named it: %s" % line)
    assert_true(line.contains("Display P3"), "and which gamut it is: %s" % line)
    assert_true(_tooltip_of(dialog).contains("Display P3"), "The tooltip names it too: %s" % _tooltip_of(dialog))
    dialog.free()


## A JPEG with no profile names nothing, so the line is the convention's. So is
## a plain PNG, an EXR, a TIFF with no profile, and a TIFF whose profile's curve
## table no Sara curve meets: its last entry flipped puts the top 1/255 off, past
## what `SaIccProfile.ToneCurve` allows, so the profile is set aside and the gamut
## it would name is not taken without its curve.
func test_a_file_that_names_nothing_gets_the_conventions_line() -> void:
    var foreign := _p3_profile()
    foreign[foreign.size() - 1] ^= 0xFF
    var files := {
        "a JPEG": JPEG,
        "a plain PNG": PLAIN_PNG,
        "an EXR": EXR,
        "a TIFF with no profile": _tiff("c1_none.tif", PackedByteArray()),
        "a TIFF whose profile's curve Sara cannot take": _tiff("c1_foreign.tif", foreign),
    }
    for label: String in files:
        var dialog := _window_for(files[label])
        var line := _line_of(dialog)
        assert_true(line.contains("names no colour space"), "%s: the line says the file named none: %s" % [label, line])
        assert_true(line.contains("Sara assumes sRGB for 8-bit"), "%s: and what the row starts at: %s" % [label, line])
        assert_false(line.contains("names its colour space"), "%s: and does not claim a name" % label)
        assert_true(_tooltip_of(dialog).contains("is a guess"), "%s: The tooltip calls it a guess" % label)
        dialog.free()


## The convention is still what the row opens on for those files, which is what
## the line says it starts at.
func test_the_conventions_line_is_true_of_the_row() -> void:
    var jpeg := _window_for(JPEG)
    assert_eq(jpeg.chosen_space().id, SaColorSpace.ID_SRGB, "A JPEG opens on sRGB")
    jpeg.free()
    var exr := _window_for(EXR)
    assert_eq(exr.chosen_space().id, SaColorSpace.ID_LINEAR_SRGB, "An EXR opens on linear sRGB")
    exr.free()


## A TIFF that names sRGB has said so, which is not the file saying nothing, and
## it is the reason `named_space_for` answers null for the second and not sRGB.
func test_a_file_that_names_srgb_is_not_a_file_that_names_nothing() -> void:
    var named := _window_for(_tiff("c1_srgb.tif", SaExportGamut.profile_for(SaGamut.from_id(SaGamut.ID_SRGB))))
    assert_true(
        _line_of(named).contains("The file names its colour space, sRGB"), "sRGB's own profile is a name: %s" % _line_of(named)
    )
    named.free()
    assert_null(SaImageImport.named_space_for(PLAIN_PNG), "A PNG with no cICP names no gamut")
    assert_not_null(SaImageImport.named_space_for(P3_PNG), "and one with a cICP does")


## The window is one per host and reused, so a plain picture after a named one
## has to take the claim back, and moving the row does not rewrite where it
## started.
func test_the_line_follows_the_file_and_not_the_row() -> void:
    var dialog := _window_for(P3_PNG)
    assert_true(dialog.select_space(SaColorSpace.ID_SRGB), "The painter moves the row")
    assert_true(_line_of(dialog).contains("Display P3"), "and the line still says what the file named: %s" % _line_of(dialog))
    dialog.configure(Vector2i(300, 200), Vector2i(1920, 1080), SaColorSpace.srgb())
    assert_true(_line_of(dialog).contains("names no colour space"), "A picture naming none takes it back: %s" % _line_of(dialog))
    dialog.configure_open(Vector2i(300, 200), SaImageImport.named_space_for(P3_PNG), -1, true)
    assert_true(_line_of(dialog).contains("The file names its colour space, Display P3"), "and the open question says it too")
    dialog.free()
