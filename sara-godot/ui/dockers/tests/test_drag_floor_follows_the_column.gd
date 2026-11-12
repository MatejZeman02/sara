## A hand-dragged docker is floored by the column inside it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The floor already followed the column for a size the layout store writes and stopped one path short.
## `DockerWindow.enforce_column_minimum` raises `min_size.x` to the column's want
## and runs twice, both during the window's own setup, so a column that finishes
## laying out afterwards never reaches the floor. The Minimap's does: its
## `min_size.x` stays at 177 while its column wants 335, and `minimum_size_of`
## read only `min_size`, so a drag walked straight through the column. Three
## `docker_resize` steps of -600 read 335, 335, 335 and then **177**, with the
## hide button's right edge at 331 in a window 177 wide.
##
## **The assertion no suite made** is the one no suite made before: what a
## window's floor answers *after* its column has grown. `test_stored_size_floor.gd`
## asks the store the same question and this asks the gesture, which is the pair
## that was one half short.
##
## What the assembled dockers do is
## `scenarios/docker-floor-never-follows-its-column.json`.
extends "res://tests/test_framework.gd"


## A window that answers `content_column` the way a `DockerWindow` does, which is
## what `DockerWindow.column_min_width` duck-types for. The same fixture the stored-size suite uses, and for
## the same reason: a real docker builds a picture and a row
## of controls in `_init` and this needs a column with a number in it.
class ColumnWindow:
    extends Window

    var column: VBoxContainer = null

    func _init(wants: Vector2i) -> void:
        column = VBoxContainer.new()
        column.custom_minimum_size = wants
        add_child(column)

    func content_column() -> Container:
        return column


## The defect, in one assertion, at the Minimap's own numbers.
func test_the_floor_a_drag_reads_follows_the_column_past_min_size() -> void:
    var window := ColumnWindow.new(Vector2i(335, 90))
    window.min_size = Vector2i(177, 144)

    assert_eq(window.min_size.x, 177, "The window's own floor is the one setup left behind")
    assert_eq(DockerWindow.column_min_width(window), 335, "and the column has grown past it since")

    var floor_size := DockerDragHandle.minimum_size_of(window)
    assert_eq(floor_size.x, 335, "A drag is floored by the column rather than by the stale min_size")
    assert_eq(floor_size.y, 144, "and the other axis is the window's own, which is above its column")
    window.free()


## The drag that made it visible: three inward drags of -600 each. Before this,
## the third one was the one that broke through.
func test_three_inward_drags_stop_at_the_column_rather_than_at_min_size() -> void:
    var window := ColumnWindow.new(Vector2i(335, 90))
    window.min_size = Vector2i(177, 144)
    var size := Vector2i(335, 230)
    for _drag in 3:
        size = DockerDragHandle.resize_size(size, Vector2(-600, -600), DockerDragHandle.minimum_size_of(window))
    assert_eq(size.x, 335, "Three drags of -600 leave the docker as wide as its column")
    assert_true(size.x > window.min_size.x, "which is wider than the floor the window itself declares")
    window.free()


## `min_size` is read and never written, which is the whole reason the fix is
## here rather than in `enforce_column_minimum`. Raising the window's own floor
## when its column grows would make a window grow under the hand holding it, and
## a drag that stops early is the smaller surprise.
func test_reading_the_floor_does_not_move_the_window() -> void:
    var window := ColumnWindow.new(Vector2i(335, 90))
    window.min_size = Vector2i(177, 144)
    var was_size := window.size
    DockerDragHandle.minimum_size_of(window)
    assert_eq(window.min_size, Vector2i(177, 144), "Asking for the floor leaves min_size alone")
    assert_eq(window.size, was_size, "and leaves the window the size it was")
    window.free()


## A window with no column answers exactly what it did before, so nothing that
## is not a docker changed. `column_min_width` answers -1 there and the guard is
## what keeps a negative out of the floor.
func test_a_window_with_no_column_answers_its_own_minimum() -> void:
    var window := Window.new()
    window.min_size = Vector2i(200, 160)
    assert_eq(DockerWindow.column_min_width(window), -1, "A plain window has no column to ask")
    assert_eq(DockerDragHandle.minimum_size_of(window), Vector2i(200, 160), "so the floor is its own minimum")
    window.free()


## The floor is a floor. A docker already wider than its column keeps its width,
## or a drag would snap every docker to its content the moment it was touched.
func test_a_window_wider_than_its_column_is_not_pulled_in() -> void:
    var window := ColumnWindow.new(Vector2i(200, 90))
    window.min_size = Vector2i(177, 144)
    var size := DockerDragHandle.resize_size(Vector2i(600, 480), Vector2(-40, -40), DockerDragHandle.minimum_size_of(window))
    assert_eq(size, Vector2i(560, 440), "A drag above both floors moves by exactly what it asked for")
    window.free()
