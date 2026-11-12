## The Reference docker's Canvas button is a toggle.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The button shows pressed while the board in front holds
## the canvas element, a press puts it on or takes it off, and the pressed state
## follows a tab change, a delete on the board and a board read back from a
## file. Built outside the tree as the solo suite builds the docker, because a
## `Window` in the tree hangs a headless run. The running app's side is
## `scenarios/the-reference-docker-s-canvas-button-is-a-toggle.json`.
extends "res://tests/test_framework.gd"


func _button(docker: ReferenceDocker) -> Button:
    return docker.find_child("CanvasButton", true, false) as Button


## A hand's press: the toggle flips itself and then the docker sets it to what
## the board holds.
func _press(docker: ReferenceDocker) -> void:
    var button := _button(docker)
    button.button_pressed = not button.button_pressed
    button.pressed.emit()


func _docker() -> ReferenceDocker:
    var docker := ReferenceDocker.new()
    docker.board_view.size = Vector2(300, 200)
    return docker


func test_the_button_is_a_toggle_with_both_halves_in_its_hover() -> void:
    var docker := _docker()
    var button := _button(docker)
    assert_true(button.toggle_mode, "The Canvas button is a toggle")
    assert_false(button.button_pressed, "released on an empty board")
    assert_true(button.tooltip_text.contains("take it off"), "and its hover says a press takes the canvas off too")
    docker.free()


func test_a_press_puts_the_canvas_on_and_a_second_takes_it_off() -> void:
    var docker := _docker()
    _press(docker)
    var live := docker.board().canvas_picture()
    assert_not_null(live, "The first press puts the canvas element on the board")
    assert_true(_button(docker).button_pressed, "and the button shows pressed")

    _press(docker)
    assert_null(docker.board().canvas_picture(), "The second press takes it off")
    assert_eq(docker.board().pictures.size(), 0, "leaving the board empty")
    assert_false(_button(docker).button_pressed, "and the button released")
    docker.free()


func test_a_board_without_the_canvas_releases_the_button() -> void:
    var docker := _docker()
    _press(docker)
    docker.add_board("Second")
    assert_null(docker.board().canvas_picture(), "The second board has no canvas")
    assert_false(_button(docker).button_pressed, "and the button is released on its tab")
    docker.select_board(0)
    assert_true(_button(docker).button_pressed, "Back on the first tab it is pressed again")
    docker.free()


func test_a_delete_on_the_board_releases_the_button() -> void:
    var docker := _docker()
    _press(docker)
    var live := docker.board().canvas_picture()
    assert_true(docker.board_view.remove_picture(live), "The board's delete takes the element")
    assert_null(docker.board().canvas_picture(), "off the board")
    assert_false(_button(docker).button_pressed, "and the button is released")
    docker.free()


func test_a_board_read_from_a_file_sets_the_button() -> void:
    var docker := _docker()
    _press(docker)
    var header := docker.to_header()
    docker.restore([])
    assert_false(_button(docker).button_pressed, "No boards read back, the button is released")
    docker.restore(header)
    assert_not_null(docker.board().canvas_picture(), "The board read back holds the canvas")
    assert_true(_button(docker).button_pressed, "and the button shows pressed")
    docker.free()
