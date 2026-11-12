## The Reference docker's hover bar shows on hover and not on selection.
##
## The docker is built but never added to the SceneTree, the way the other
## Reference suites build it, because a `Window` in the tree hangs a headless run.
## What is proved here is the gate: the bar's picture is the one under the
## pointer, or the selected one while the pointer is on the board, and none
## with the pointer off the docker. That the real `mouse_entered` and
## `mouse_exited` reach the gesture is proved on the running app by
## `scenarios/the-reference-bar-shows-on-hover.json`.
extends "res://tests/test_framework.gd"

const REFERENCE_IMAGE := "res://ui/icon.png"


func _docker() -> ReferenceDocker:
    var docker := ReferenceDocker.new()
    docker.board_view.size = Vector2(200, 200)
    return docker


func _move(docker: ReferenceDocker, at: Vector2) -> void:
    var event := InputEventMouseMotion.new()
    event.position = at
    docker.board_view.input(event)


## A picture is selected as soon as it is opened, and that alone is not a
## reason for the bar: with the pointer off the docker the bar is down.
func test_a_selection_alone_does_not_raise_the_bar() -> void:
    var docker := _docker()
    docker.open_paths(PackedStringArray([REFERENCE_IMAGE]))
    assert_not_null(docker.board_view.selected(), "Opened, the picture is selected")
    assert_false(docker.board_view.inside, "and the pointer has not entered")
    assert_null(docker.board_view.hover_target(), "so the bar has no picture")
    docker.board_view.sync_bar()
    assert_false(docker.board_view.bar_report()["visible"], "and is down")
    assert_eq(docker.board_view.bar_report()["picture"], -1, "over nothing")
    docker.free()


## Entering the docker puts the bar on the selected picture, a motion onto
## another picture moves it there, and leaving takes it down again.
func test_the_bar_follows_the_pointer_in_and_out() -> void:
    var docker := _docker()
    docker.open_paths(PackedStringArray([REFERENCE_IMAGE, REFERENCE_IMAGE]))
    var board := docker.board()
    var first := board.pictures[0]
    var second := board.pictures[1]

    docker.board_view.pointer_entered()
    assert_true(docker.board_view.inside, "Entered")
    assert_eq(docker.board_view.hover_target(), second, "the selected picture carries the bar")
    docker.board_view.sync_bar()
    assert_true(docker.board_view.bar_report()["visible"], "and the bar is up")
    assert_eq(docker.board_view.bar_report()["picture"], 1, "on the selected one")

    _move(docker, board.view_rect(first).get_center())
    assert_eq(docker.board_view.hover_target(), first, "Under the pointer, the first is the bar's")
    docker.board_view.sync_bar()
    assert_eq(docker.board_view.bar_report()["picture"], 0, "and the dump says so")

    docker.board_view.pointer_left()
    assert_false(docker.board_view.inside, "Left")
    assert_null(docker.board_view.hover, "the hover is cleared")
    assert_null(docker.board_view.hover_target(), "the bar has no picture")
    docker.board_view.sync_bar()
    assert_false(docker.board_view.bar_report()["visible"], "and is down, the picture whole")
    assert_eq(docker.board_view.selected(), second, "while the selection stands")
    docker.free()


## A motion is enough to count as inside, for a pointer that was already
## over the docker when it was built and never fired `mouse_entered`.
func test_a_motion_counts_as_entering() -> void:
    var docker := _docker()
    docker.open_paths(PackedStringArray([REFERENCE_IMAGE]))
    var picture := docker.board().pictures[0]
    _move(docker, docker.board().view_rect(picture).get_center())
    assert_true(docker.board_view.inside, "A motion means the pointer is inside")
    assert_eq(docker.board_view.hover_target(), picture, "and the picture under it is the bar's")
    docker.free()


## A motion over the bar itself is the bar's: it does not move the bar off
## the picture it sits on, even when the bar hangs over empty board.
func test_a_motion_over_the_bar_keeps_its_picture() -> void:
    var docker := _docker()
    docker.open_paths(PackedStringArray([REFERENCE_IMAGE]))
    var picture := docker.board().pictures[0]
    var rect := docker.board().view_rect(picture)
    _move(docker, rect.get_center())
    docker.board_view.sync_bar()
    # Outside the tree the container never lays out, so the bar is given the
    # size it would have, wide enough to run past the picture's right edge.
    docker.board_view._bar.row.size = Vector2(rect.size.x + 40.0, 20.0)
    var beyond := docker.board_view._bar.row.position + Vector2(rect.size.x + 30.0, 10.0)
    assert_null(docker.board().picture_at(docker.board().to_board(beyond)), "The point is off every picture")
    assert_true(docker.board_view.over_bar(beyond), "and on the bar")
    _move(docker, beyond)
    assert_eq(docker.board_view.hover, picture, "so the hover stays with the bar's picture")
    docker.free()
