## The Shape Check's rows on Preferences > Display: the method, how far Masses
## reaches, how many blocks Blocks cuts the long side into, whether the
## lightness is posterised and to how many steps, and how many values a notan
## cuts it into and where.
##
## A class of their own beside `display_page.gd`, because they are the Shape
## Check's method and its numbers, a responsibility of their own. The page
## declares them under its View transform list and reads back whether they are
## live.
##
## Every row dims under any view but the Shape Check: the choice is worth making
## before the view goes on, and a row that vanished would leave a painter
## looking for it. A row that belongs to some methods dims under the rest, the
## count of levels dims while the posterise is off, and a notan's thresholds dim
## under the count of values they do not belong to.
class_name SaShapeCheckRows
extends RefCounted

## The Shape Check view transform's registry id, the mode these rows describe.
const VIEW_ID := &"shape_check"

## The Method row, held so a test and the dump can read whether it is live.
var _method_row: SaPageRow = null


## The section, under *view_row*, the View transform list, whose mode decides
## whether any of it answers a painter. Every row is bound to its preference, so
## nothing here keeps a value of its own.
func declare(ui: SaPage, view_row: SaPageRow) -> void:
    var section := ui.section("Shape check")
    _method_row = (
        section
        . choice("Method", _method_choices(), SaSettings, ^"shape_check_method")
        . explain(
            tr(
                (
                    "How the Shape Check view throws the detail away, shown only while that view is on, picked above or"
                    + " from the View menu. Blocks averages the canvas into flat squares. Masses smooths inside each mass"
                    + " and keeps the edges between them where they are, alike at any canvas size. None leaves the"
                    + " picture whole for the posterise below. Grey masses is Masses with the colour gone. Notan is"
                    + " Masses cut into two or three greys, black and white with a middle grey between. Nothing here"
                    + " touches a pixel."
                )
            )
        )
        . named(&"shape_check_method")
        . node("ShapeCheckMethodOption")
    )
    var reach := (
        section
        . number(
            "Reach", SaSettings.MIN_SHAPE_REACH * 100.0, SaSettings.MAX_SHAPE_REACH * 100.0, SaSettings, ^"shape_check_reach"
        )
        . scale(100)
        . step(0.1)
        . with_suffix(tr("%"))
        . explain(
            tr(
                (
                    "How far Masses, Grey masses and Notan look for the side of an edge a pixel is on, as a share of"
                    + " the canvas's long side, so a picture and the same picture at twice the size read alike. A mass"
                    + " narrower than about this melts into its neighbours."
                )
            )
        )
        . named(&"shape_check_reach")
        . node("ShapeCheckReachSpin")
    )
    var across := (
        section
        . number("Blocks across", SaSettings.MIN_SHAPE_ACROSS, SaSettings.MAX_SHAPE_ACROSS, SaSettings, ^"shape_check_across")
        . explain(tr("How many blocks Blocks cuts the canvas's long side into, whatever the canvas measures."))
        . named(&"shape_check_across")
        . node("ShapeCheckAcrossSpin")
    )
    var levels := (
        section
        . toggle("Posterise lightness", SaSettings, ^"shape_check_levels")
        . explain(
            tr(
                (
                    "Snaps the lightness to a few steps after the method, so the values read as flat shapes. Blocks,"
                    + " Masses and None keep the hue and chroma, and Grey masses draws the steps in grey."
                )
            )
        )
        . named(&"shape_check_levels")
        . node("ShapeCheckLevelsCheck")
    )
    var count := (
        section
        . number("Levels", SaSettings.MIN_SHAPE_LEVELS, SaSettings.MAX_SHAPE_LEVELS, SaSettings, ^"shape_check_level_count")
        . explain(tr("How many steps of lightness the posterise snaps to. The Info docker sets the same number."))
        . named(&"shape_check_level_count")
        . node("ShapeCheckLevelCountSpin")
    )
    # Notan's rows, its count of values and its thresholds: the one of two
    # values, then the dark and the light one of three. Each threshold is a
    # share of the lightness, shown as a per cent of it.
    var values := (
        section
        . choice(
            "Notan values",
            [{"id": 2, "label": tr("Two")}, {"id": 3, "label": tr("Three")}],
            SaSettings,
            ^"shape_check_notan_values"
        )
        . explain(tr("How many greys Notan cuts the lightness into: black and white, or a middle grey between them."))
        . named(&"shape_check_notan_values")
        . node("ShapeCheckNotanValuesOption")
    )
    var threshold := (
        section
        . number("Threshold", 0.0, 100.0, SaSettings, ^"shape_check_notan_threshold")
        . scale(100)
        . with_suffix(tr("%"))
        . explain(tr("Where a notan of two values turns from black to white, on the lightness. The middle by default."))
        . named(&"shape_check_notan_threshold")
        . node("ShapeCheckNotanThresholdSpin")
    )
    var dark := (
        section
        . number("Dark threshold", 0.0, 100.0, SaSettings, ^"shape_check_notan_dark")
        . scale(100)
        . with_suffix(tr("%"))
        . explain(tr("Where a notan of three values turns from black to the middle grey, on the lightness."))
        . named(&"shape_check_notan_dark")
        . node("ShapeCheckNotanDarkSpin")
    )
    var light := (
        section
        . number("Light threshold", 0.0, 100.0, SaSettings, ^"shape_check_notan_light")
        . scale(100)
        . with_suffix(tr("%"))
        . explain(tr("Where a notan of three values turns from the middle grey to white, on the lightness."))
        . named(&"shape_check_notan_light")
        . node("ShapeCheckNotanLightSpin")
    )
    for row: SaPageRow in [_method_row, reach, across, levels, count, values, threshold, dark, light]:
        view_row.dims(row, [VIEW_ID])
    _method_row.dims(reach, SaSettings.SHAPE_REACHING)
    _method_row.dims(across, [SaSettings.SHAPE_BLOCKS])
    _method_row.dims(levels, SaSettings.SHAPE_POSTERISING)
    _method_row.dims(count, SaSettings.SHAPE_POSTERISING)
    levels.dims(count)
    for row: SaPageRow in [values, threshold, dark, light]:
        _method_row.dims(row, [SaSettings.SHAPE_NOTAN])
    values.dims(threshold, [2])
    values.dims(dark, [3])
    values.dims(light, [3])


## Whether the Method row is live, the way `SaPage.set_live` leaves it: drawn at
## full strength and its dropdown not disabled.
func live() -> bool:
    if _method_row == null or _method_row.line == null or not is_instance_valid(_method_row.line):
        return false
    var button := _method_row.control as BaseButton
    return is_equal_approx(_method_row.line.modulate.a, 1.0) and (button == null or not button.disabled)


## The Method row's entries, one per entry of `SHAPE_METHODS`, written straight
## to the setting. The labels are translated here rather than by the builder,
## because a choice row's entries are its own list and not the row's title.
func _method_choices() -> Array:
    var choices: Array = []
    for value: String in SaSettings.SHAPE_METHODS:
        choices.append({"id": value, "label": tr(_method_name(value))})
    return choices


## What the Method row calls one of its values.
static func _method_name(value: String) -> String:
    if value == SaSettings.SHAPE_BLOCKS:
        return "Blocks"
    if value == SaSettings.SHAPE_MASSES:
        return "Masses"
    if value == SaSettings.SHAPE_GREY_MASSES:
        return "Grey masses"
    if value == SaSettings.SHAPE_NOTAN:
        return "Notan"
    return "None"
