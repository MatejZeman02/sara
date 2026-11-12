## A filter window is
## titled by the filter's own name, the one the Filter menu shows, and Levels
## labels both of its ranges.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Every filter passes `title()`, so a blur is not titled in sentence case,
## "Gaussian blur", under a menu row reading "Gaussian Blur". Levels heads its
## input range as well as its output range.
extends "res://tests/test_framework.gd"

const GaussianBlurFilter = preload("res://modules/sara-base-modules/base/usual/gaussian_blur_filter.gd")
const MotionBlurFilter = preload("res://modules/sara-base-modules/base/usual/motion_blur.gd")
const LensBlurFilter = preload("res://modules/sara-base-modules/base/usual/lens_blur_filter.gd")


func test_each_blur_window_is_titled_by_its_filters_name() -> void:
    for filter: SaFilter in [GaussianBlurFilter.new(), MotionBlurFilter.new(), LensBlurFilter.new()]:
        var dialog := SaDialog.new()
        var host := VBoxContainer.new()
        filter.build(dialog)
        dialog.realize(host)
        assert_eq(dialog.dialog_title, filter.title(), "the %s window says what its menu row says" % filter.title())
        host.free()
    assert_eq(GaussianBlurFilter.new().title(), "Gaussian Blur", "and the name is the menu's")


func test_levels_labels_its_input_range_as_it_labels_its_output() -> void:
    var panel := SaLevelsPanel.new()
    var input_label := panel.find_child("InputLabel", true, false) as Label
    var output_label := panel.find_child("OutputLabel", true, false) as Label
    assert_not_null(input_label, "the input range has a label")
    if input_label != null:
        assert_eq(input_label.text, "Input levels", "and it names the range")
        assert_false(input_label.tooltip_text.is_empty(), "and says what it is")
        assert_true(input_label.get_index() < panel.find_child("InputBar", true, false).get_parent().get_index(), "above its bar")
    assert_eq(output_label.text if output_label != null else "", "Output levels", "beside the output range's")
    panel.free()
