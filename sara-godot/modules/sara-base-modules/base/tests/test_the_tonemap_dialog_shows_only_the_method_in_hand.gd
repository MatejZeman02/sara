## The Tonemap dialog shows only the method in hand.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## On the dialog with Paper picked, the openDrt sections would be useless and
## empty. A heading whose rows a rule has all hidden goes with them, which `SaPage.apply_rules` does for
## every declared page, and
## Paper's section carries the curve and the colour pair the Display page draws
## the view's roll-off with, through the dialog's `rolloff` door.
##
## No GPU: the dialog is declared and realized off screen, and every heading and
## row is read by the `visible` its line carries.
extends "res://tests/test_framework.gd"

const Params = preload("res://modules/sara-base-modules/base/usual/opendrt_parameters.gd")

const OWNER: StringName = &"sara-base-modules"
## OpenDRT's section headings, which Paper must not show.
const OPENDRT_HEADINGS: Array[String] = ["Preset", "Tonescale", "Creative White", "Purity", "Brilliance", "Hue Shift"]

var _filter: SaTonemapFilter = null
var _registry: SaFilterRegistry = null
var _host: VBoxContainer = null
var _dialog: SaDialog = null


func before_each() -> void:
    _registry = SaFilterRegistry.new()
    _filter = SaTonemapFilter.new()
    _registry.register(_filter, OWNER)
    _host = VBoxContainer.new()
    _dialog = SaDialog.for_filter(_filter)
    _dialog.realize(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    _dialog = null
    _filter = null
    _registry = null


## Every section column the dialog drew, as `{"heading": String, "shown": bool,
## "rows_shown": int}`, found by the meta `SaSettingsRows.section` sets on a
## section's rows. By the meta and not by name, since a second column called
## Section off the tree is given a name of the engine's making.
func _sections() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for column: Node in _host.get_children():
        var rows: Node = null
        var heading: Label = null
        for child: Node in column.get_children():
            if child.has_meta(SaSettingsRows.SECTION_META):
                rows = child
            elif child is Label and heading == null:
                heading = child as Label
        if rows == null:
            continue
        var shown := 0
        for line: Node in rows.get_children():
            if line is CanvasItem and (line as CanvasItem).visible:
                shown += 1
        (
            out
            . append(
                {
                    "heading": heading.text if heading != null else "",
                    "shown": (column as CanvasItem).visible,
                    "rows_shown": shown,
                }
            )
        )
    return out


func _shown_headings() -> Array[String]:
    var out: Array[String] = []
    for block: Dictionary in _sections():
        if bool(block["shown"]) and not String(block["heading"]).is_empty():
            out.append(String(block["heading"]))
    return out


func test_on_paper_every_heading_shown_has_a_row_shown_under_it() -> void:
    assert_eq(_dialog.row(&"method").read(), Params.METHOD_PAPER, "A fresh Tonemap opens at Paper")
    var blocks := _sections()
    assert_true(blocks.size() > 6, "The dialog drew its sections")
    for block: Dictionary in blocks:
        if bool(block["shown"]) and not String(block["heading"]).is_empty():
            assert_true(int(block["rows_shown"]) > 0, "Heading %s has a row on screen under it" % block["heading"])
    var shown := _shown_headings()
    assert_eq(shown, ["Method"], "and on Paper the only heading is Method")
    for heading in OPENDRT_HEADINGS:
        assert_false(shown.has(heading), "%s stays away on Paper" % heading)


func test_on_opendrt_its_sections_come_back_with_their_rows() -> void:
    _dialog.row(&"method").write(Params.METHOD_OPENDRT)
    var shown := _shown_headings()
    for heading in OPENDRT_HEADINGS:
        assert_true(shown.has(heading), "%s is on the page at OpenDRT" % heading)
    for block: Dictionary in _sections():
        if bool(block["shown"]) and not String(block["heading"]).is_empty():
            assert_true(int(block["rows_shown"]) > 0, "Heading %s has a row on screen under it" % block["heading"])
    _dialog.row(&"method").write(Params.METHOD_PAPER)
    assert_eq(_shown_headings(), ["Method"], "and back on Paper they go again")


func test_paper_shows_the_curve_and_the_colour_pair_and_opendrt_does_not() -> void:
    var curve := _dialog.row(&"the_curve")
    var colours := _dialog.row(&"every_colour")
    assert_not_null(curve, "Paper's section declares the curve")
    assert_not_null(colours, "and the colour pair")
    assert_true(curve.line.visible, "The curve is on the page at Paper")
    assert_true(colours.line.visible, "and so is the colour pair")
    _dialog.row(&"method").write(Params.METHOD_OPENDRT)
    assert_false(curve.line.visible, "At OpenDRT the curve steps aside")
    assert_false(colours.line.visible, "and so does the colour pair")


func test_moving_knee_moves_the_plots_knee() -> void:
    var drawn: Dictionary = _dialog.describe()["rolloff"]
    assert_almost_eq(float(drawn["knee"]), float(SaTonemapFilter.DEFAULTS["knee"]), 1e-6, "The curve opens at the filter's knee")
    _dialog.row(&"knee").write(0.4)
    drawn = _dialog.describe()["rolloff"]
    assert_almost_eq(float(drawn["knee"]), 0.4, 1e-6, "Moving Knee moves the plot's knee with it")
    _dialog.row(&"desaturation").write(0.6)
    drawn = _dialog.describe()["rolloff"]
    assert_almost_eq(float(drawn["desaturation"]), 0.6, 1e-6, "and Desaturation the plot's desaturation")
