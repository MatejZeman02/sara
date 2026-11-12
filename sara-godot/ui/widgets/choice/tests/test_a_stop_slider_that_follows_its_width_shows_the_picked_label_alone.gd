## The Exposure docker's way toggle fits its docker in a
## language longer than English.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The ask: "Under the test language the Exposure docker's Apply button passes
## its window's edge: the way toggle above it asks for 402 pixels in a docker
## 226 wide." A stop slider made to follow its width asks for its widest label
## once rather than every label side by side, and when the labels do not fit
## their cells it shows the picked one alone over the track, kept inside the
## control. A plain slider asks and draws as before, so no English toggle moves.
extends "res://tests/test_framework.gd"

const WayToggle := preload("res://modules/sara-base-modules/exposure/exposure_way_toggle.gd")

## Long words, the length the test language gives Bake, Attach and Layer.
const LONG: Array[String] = ["Bakeжщыюжщыю", "Attachжщыюжщыю", "Layerжщыюжщыю"]

## Short words, which fit side by side at the minimum a plain slider asks.
const SHORT: Array[String] = ["Bake", "Attach", "Layer"]


func test_a_slider_following_its_width_asks_for_one_cell_and_a_plain_one_for_every_cell() -> void:
    var plain := _slider(LONG, false)
    var follows := _slider(LONG, true)
    var cell := follows._widest_cell()
    assert_almost_eq(plain.get_combined_minimum_size().x, cell * 3.0, 0.01, "A plain slider asks for every label side by side")
    assert_almost_eq(follows.get_combined_minimum_size().x, cell, 0.01, "One following its width asks for its widest label once")
    assert_almost_eq(follows.get_combined_minimum_size().y, plain.get_combined_minimum_size().y, 0.01, "and for the same height")
    plain.free()
    follows.free()


func test_labels_that_fit_are_all_drawn_as_a_plain_slider_draws_them() -> void:
    var plain := _slider(SHORT, false)
    var follows := _slider(SHORT, true)
    follows.size = plain.size
    assert_true(follows.shows_every_label(), "Short labels at a plain slider's width all fit")
    assert_eq(follows.shown_labels(), [0, 1, 2] as Array[int], "and every one is drawn")
    for index in SHORT.size():
        assert_eq(follows.label_rect(index), plain.label_rect(index), "'%s' stands where a plain slider puts it" % SHORT[index])
    plain.free()
    follows.free()


func test_labels_that_do_not_fit_show_the_picked_one_alone_inside_the_control() -> void:
    var slider := _slider(LONG, true)
    slider.size.x = slider._widest_cell() * 1.5
    assert_false(slider.shows_every_label(), "Three long labels do not fit one and a half cells")
    for index in LONG.size():
        slider.value = index
        assert_eq(slider.shown_labels(), [index] as Array[int], "With '%s' picked only it is drawn" % LONG[index])
        var place := slider.label_rect(index)
        assert_true(
            place.position.x >= -0.01 and place.end.x <= slider.size.x + 0.01,
            "and '%s' stays inside the control, %s in %.1f" % [LONG[index], place, slider.size.x]
        )
    slider.free()


func test_a_held_drag_shows_the_label_of_the_stop_under_the_pointer() -> void:
    var slider := _slider(LONG, true)
    slider.size.x = slider._widest_cell() * 1.5
    slider.value = 0
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = Vector2(slider.size.x - 1.0, slider.size.y - 2.0)
    slider._gui_input(press)
    assert_eq(slider.shown_labels(), [2] as Array[int], "A drag held over the last stop shows its label")
    press.pressed = false
    slider._gui_input(press)
    assert_eq(slider.value, 2, "and letting go picks it")
    assert_eq(slider.shown_labels(), [2] as Array[int], "whose label stays")
    slider.free()


func test_the_exposure_way_toggle_follows_its_width() -> void:
    var toggle := WayToggle.new()
    var asked := toggle.get_combined_minimum_size().x
    assert_almost_eq(asked, toggle._widest_cell(), 0.01, "The Exposure docker's toggle asks for its widest way once")
    toggle.free()


## A slider of *words*, ids the indices, at its minimum size.
func _slider(words: Array[String], follows_width: bool) -> SaStopSlider:
    var choices: Array = []
    for index in words.size():
        choices.append({"id": index, "label": words[index]})
    var slider := SaStopSlider.new(choices, follows_width)
    slider.size = slider.get_combined_minimum_size()
    return slider
