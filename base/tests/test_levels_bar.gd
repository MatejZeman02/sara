## The Levels handle bars and the gamma maths behind the grey handle.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The bar is
## `SaLevelsBar` and the maths `SaLevelsPanel`'s. What is tested is the two
## things that need no window: the bar, a Control that works at a size set by
## hand, and the static maths that turns a gamma into a place on the bar and
## back. The last case reads source files, because the claim that
## Brightness/Contrast lost its graph is a claim about those files.
extends "res://tests/test_framework.gd"

const WIDTH := 300.0

## The bars a case made, freed after it: a Control outside a tree is freed by
## nobody else, and the runner counts what is left.
var _bars: Array = []


func after_each() -> void:
    for bar: Control in _bars:
        bar.free()
    _bars.clear()


func _bar(keys: Array, derived: String) -> Control:
    var bar: Control = SaLevelsBar.new("Bar", keys, derived)
    bar.size = Vector2(WIDTH, 40.0)
    _bars.append(bar)
    return bar


func test_a_gamma_of_one_puts_the_grey_handle_in_the_middle() -> void:
    assert_almost_eq(SaLevelsPanel.gamma_position(0.0, 1.0, 1.0), 0.5)
    assert_almost_eq(SaLevelsPanel.gamma_position(0.2, 1.0, 0.6), 0.4, 0.0001, "and in the middle of a narrowed range")


func test_a_gamma_above_one_sits_left_of_centre() -> void:
    assert_true(SaLevelsPanel.gamma_position(0.0, 2.0, 1.0) < 0.5, "the drag that brightens the midtones goes left")
    assert_true(SaLevelsPanel.gamma_position(0.0, 0.5, 1.0) > 0.5, "and the one that darkens them goes right")


func test_the_gamma_maths_round_trips() -> void:
    for gamma: float in [0.1, 0.5, 1.0, 1.7, 4.0]:
        var at := SaLevelsPanel.gamma_position(0.1, gamma, 0.9)
        assert_almost_eq(SaLevelsPanel.gamma_at(0.1, at, 0.9), gamma, 0.001, "gamma %s survives the bar" % gamma)


func test_a_met_range_reads_as_gamma_one() -> void:
    assert_eq(SaLevelsPanel.gamma_at(0.5, 0.5, 0.5), 1.0)


func test_a_drag_moves_the_handle_and_reports_it() -> void:
    var bar := _bar(["out_black", "out_white"], "")
    bar.set_positions({"out_black": 0.0, "out_white": 1.0})
    var heard: Array = []
    bar.handle_dragged.connect(func(key: String, at: float) -> void: heard.append([key, at]))

    bar.drag_to("out_black", 0.25)

    assert_eq(heard.size(), 1, "one report for one drag")
    assert_eq(heard[0][0], "out_black")
    assert_almost_eq(float(heard[0][1]), 0.25, 0.01, "the handle lands where the drag went, within a pixel")
    assert_almost_eq(float(bar.positions["out_black"]), 0.25, 0.01)


func test_a_level_handle_stops_short_of_the_other() -> void:
    var bar := _bar(["out_black", "out_white"], "")
    bar.set_positions({"out_black": 0.0, "out_white": 0.6})

    bar.drag_to("out_black", 0.9)

    assert_almost_eq(float(bar.positions["out_black"]), 0.6 - SaLevelsBar.GAP, 0.0001, "black stops a gap below white")


func test_the_black_handle_passes_over_the_grey_one() -> void:
    var bar := _bar(["in_black", "gamma", "in_white"], "gamma")
    bar.set_positions({"in_black": 0.0, "gamma": 0.5, "in_white": 1.0})

    bar.drag_to("in_black", 0.7)

    assert_almost_eq(float(bar.positions["in_black"]), 0.7, 0.01, "the grey handle is derived and does not bar the way")


func test_the_grey_handle_stays_between_its_neighbours() -> void:
    var bar := _bar(["in_black", "gamma", "in_white"], "gamma")
    bar.set_positions({"in_black": 0.2, "gamma": 0.5, "in_white": 0.8})

    bar.drag_to("gamma", 1.0)
    assert_almost_eq(float(bar.positions["gamma"]), 0.8 - SaLevelsBar.GAP, 0.0001, "held under white")
    bar.drag_to("gamma", 0.0)
    assert_almost_eq(float(bar.positions["gamma"]), 0.2 + SaLevelsBar.GAP, 0.0001, "and over black")


func _press(bar: Control, x: float, pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = Vector2(x, 20.0)
    bar._gui_input(event)


func _motion(bar: Control, x: float) -> void:
    var event := InputEventMouseMotion.new()
    event.position = Vector2(x, 20.0)
    bar._gui_input(event)


func test_a_press_takes_the_nearest_handle_within_reach() -> void:
    var bar := _bar(["out_black", "out_white"], "")
    bar.set_positions({"out_black": 0.0, "out_white": 1.0})
    var heard: Array = []
    bar.handle_dragged.connect(func(key: String, _at: float) -> void: heard.append(key))

    _press(bar, bar._x_of(0.0) + 3.0, true)
    _motion(bar, bar._x_of(0.3))
    _press(bar, bar._x_of(0.3), false)
    assert_eq(heard.back(), "out_black", "a press beside the black handle takes it")
    assert_almost_eq(float(bar.positions["out_black"]), 0.3, 0.01, "and the motion carries it")

    heard.clear()
    _press(bar, bar._x_of(0.65), true)
    _motion(bar, bar._x_of(0.5))
    _press(bar, bar._x_of(0.5), false)
    assert_true(heard.is_empty(), "a press on the ramp away from both handles takes nothing")


## The file the first half reads is the Brightness/Contrast filter's, and an
## empty read is a failure here rather than a pass: a string nobody could read never
## contained the graph either.
func test_brightness_contrast_has_no_graph() -> void:
    var source := FileAccess.get_file_as_string("res://modules/sara-base-modules/base/filters/brightness_contrast_filter.gd")
    assert_false(source.is_empty(), "the Brightness/Contrast filter is read")
    assert_false(source.contains("SaAdjustGraph"), "the grey graph under Brightness/Contrast went to Levels")
    var levels := FileAccess.get_file_as_string("res://modules/sara-base-modules/base/filters/levels/sa_levels_panel.gd")
    assert_true(levels.contains("SaAdjustGraph.new("), "and Levels is the one filter that makes it")
