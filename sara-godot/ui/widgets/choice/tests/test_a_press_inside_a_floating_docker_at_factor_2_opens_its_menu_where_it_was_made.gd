## `SaPopupRect.at_press` answers the main window's logical point of a
## press made inside a docker window scaled by 2, the corner its menu opens at.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## On a 4K screen at a UI scale of 2 the canvas menu opened down and right of
## the press, as far again from the window's corner as the pointer. Every menu
## place now hands its press and its control to the one helper, so this reads
## the helper's answer for a docker that stands at a place of its own and draws
## at factor 2, the case where a corner read in the docker's own pixels or in
## the screen's is wrong by the factor. The window is embedded in the suite's
## root, which places it in the root's logical units the way a docked docker
## stands, and the floating half is the scenario's, under mutter, since a
## suite's window of its own has no place a compositor honours. The picture is
## `scenarios/every-right-click-menu-opens-at-the-pointer-at-a-4k-screen-s-ui-scale.py`.
extends "res://tests/test_framework.gd"

const FACTOR := 2.0
const DOCKER_AT := Vector2i(300, 200)

var _docker: Window = null
var _row: Control = null


func before_each() -> void:
    _docker = Window.new()
    _docker.content_scale_factor = FACTOR
    _docker.position = DOCKER_AT
    _docker.size = Vector2i(400, 400)
    _row = Control.new()
    _row.position = Vector2(10, 30)
    _row.size = Vector2(100, 20)
    _docker.add_child(_row)
    EventBus.add_child(_docker)
    _docker.show()


func after_each() -> void:
    _docker.free()
    _docker = null


func _press(local: Vector2) -> InputEventMouseButton:
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_RIGHT
    press.pressed = true
    press.position = local
    return press


func test_a_press_in_a_row_of_a_docker_at_factor_2_reads_the_docker_place_and_twice_the_row_point() -> void:
    assert_true(_docker.is_embedded(), "the suite's root embeds the docker")
    var at := SaPopupRect.at_press(_press(Vector2(5, 4)), _row)
    var wanted := Vector2i(DOCKER_AT) + Vector2i(((_row.position + Vector2(5, 4)) * FACTOR).floor())
    assert_eq(at, wanted, "the docker's place and the press scaled by the docker's factor")


func test_the_answer_is_the_control_screen_transform_of_the_press() -> void:
    var local := Vector2(37, 11)
    var at := SaPopupRect.at_press(_press(local), _row)
    assert_eq(at, Vector2i((_row.get_screen_transform() * local).floor()), "one transform, the control's own")


func test_a_window_that_embeds_its_menus_takes_its_point_as_it_stands() -> void:
    var root := _docker.get_tree().root
    assert_true(root.is_embedding_subwindows(), "the suite's root embeds its windows")
    assert_eq(SaPopupRect.at_window_point(root, Vector2(412.4, 96.6)), Vector2i(412, 96), "logical, rounded down")
    assert_eq(SaPopupRect.extent_in(root, Vector2(280, 360)), Vector2(280, 360), "an embedded docker's size is logical")


func test_a_point_of_a_window_that_lets_its_menus_out_is_carried_through_its_place_and_factor() -> void:
    assert_false(_docker.is_embedding_subwindows(), "a docker's own menus are windows of their own")
    var at := SaPopupRect.at_window_point(_docker, Vector2(15, 34))
    assert_eq(at, Vector2i(DOCKER_AT) + Vector2i(30, 68), "the docker's place and the point at factor 2")
    assert_eq(SaPopupRect.extent_in(_docker, Vector2(560, 720)), Vector2(280, 360), "its pixels through its factor")


func test_a_menu_opened_at_the_press_has_its_corner_there() -> void:
    var menu := PopupMenu.new()
    menu.add_item("Rename")
    EventBus.add_child(menu)
    var at := SaPopupRect.at_press(_press(Vector2(5, 4)), _row)
    menu.popup(Rect2i(at, Vector2i(60, 30)))
    assert_eq(Vector2i(SaPopupRect.in_main_window(menu).round()), at, "the state dump reads the corner it was given")
    menu.free()
