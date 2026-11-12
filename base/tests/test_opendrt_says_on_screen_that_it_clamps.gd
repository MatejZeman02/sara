## OpenDRT says on screen that it clamps.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## With Oklab hue off, `opendrt.gmacs` clamps each channel to 0 to 1 as the
## DaVinci Resolve DCTL does, and writes that into the layer. The clamp stays,
## so the painter is told: the switch's tooltip and the muted line under its
## title name the clip, and so does the filter's sentence, which the Filter
## menu and the filter browser show.
##
## No GPU: the dialog is declared and realized off screen, and the switch is
## found by the row the dialog keeps for it.
extends "res://tests/test_framework.gd"

const OWNER: StringName = &"sara-base-modules"

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


func test_the_oklab_hue_switch_s_tooltip_names_the_clip() -> void:
    var hue := _dialog.row(&"oklab_hue")
    assert_true(hue.control is CheckButton, "The Oklab hue row is a switch")
    var tip := hue.control.tooltip_text
    assert_true(tip.contains("clips every channel to the display's range, 0 to 1"), "Its tooltip names the clip: %s" % tip)
    assert_true(tip.contains("Resolve"), "and says it is Resolve's")
    assert_true(tip.contains("Off "), "and that it is the switch off that clips")


func test_the_line_under_the_switch_says_the_same() -> void:
    var hue := _dialog.row(&"oklab_hue")
    var hint := hue.line.get_node_or_null(^"Labels/Hint") as Label
    assert_not_null(hint, "The switch's row draws its muted line")
    if hint != null:
        assert_eq(hint.text, hue.control.tooltip_text, "and it is the tooltip's sentence")


func test_the_filter_s_sentence_names_the_clip() -> void:
    var said := _filter.sentence()
    assert_true(said.contains("clips to the display's range as Resolve's does"), "The sentence names the clip: %s" % said)
    assert_true(said.ends_with("when Oklab hue is off."), "and the switch that stops it")


func test_a_switch_with_no_explanation_keeps_its_title_as_its_tooltip() -> void:
    var enable := _dialog.row(&"hs_rgb_enable")
    assert_eq(enable.control.tooltip_text, "Enable Hueshift RGB", "A switch the filter never explained still says its name")
