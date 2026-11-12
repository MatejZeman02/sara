## A docker opens at the height its content needs.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The default size of a docker fits all its items and crops none. Three things
## have to be true for that, and each is a case here.
##
## **`column_min_height` is not the content's height.** It was added first and
## a a `ScrollContainer` in three dockers, and a scroll reports its own
## minimum rather than its content's. Measured on the running app,
## `column_min_height` answers 41 for the Tool Options docker with a brush
## selected while its rows want 1449: the number that matters was invisible
## to the only function that looked like it held it. `column_content_height`
## reaches through the scroll.
##
## **A docker that can scroll is not cropping anything.** The argument still
## stands: flooring a window at its content traps a painter
## behind a size they cannot reduce, and a scroll is the docker's own answer to
## not fitting. So the floor is raised only for a docker with no scroll, and the
## opening height is raised for every docker up to half the screen.
##
## What the assembled dockers do is
## `scenarios/docker-opens-at-content-size.json`.
extends "res://tests/test_framework.gd"


## A window that answers `content_column` the way a `DockerWindow` does, which
## is what the three static readers duck-type for. The same shape the other docker-size suites use, and for
## the same reason: a real docker builds a picture and
## a row of controls in `_init`, and this needs a column with a number in it.
class ColumnWindow:
    extends Window

    var column: VBoxContainer = null
    var scroll: ScrollContainer = null

    ## *rows* are the heights of the children the column stacks. When *scrolled*
    ## is true they go inside a `ScrollContainer` instead, which is how three dockers are built.
    ##
    ## **The separation is the theme's and is not overridden**, which cost one
    ## reading. `add_theme_constant_override` on a node outside the tree is
    ## visible to `get_theme_constant` at once and to the container's own layout
    ## only once it is in one, so a fixture that overrode the gap to nothing had
    ## `column_content_height` answering 180 against a column that wanted 188.
    ## Every docker is in a tree, so the two agree there.
    func _init(rows: Array, scrolled: bool = false) -> void:
        column = VBoxContainer.new()
        add_child(column)
        var host: Node = column
        if scrolled:
            scroll = ScrollContainer.new()
            scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
            column.add_child(scroll)
            var inner := VBoxContainer.new()
            scroll.add_child(inner)
            host = inner
        for height: Variant in rows:
            var row := Control.new()
            row.custom_minimum_size = Vector2(0.0, float(height))
            host.add_child(row)

    func content_column() -> Container:
        return column


## Reaching through the scroll is the whole of the measurement.
##
## The rows are read against the column's own minimum rather than against 180,
## because a `VBoxContainer` lays its children out with the theme's separation
## between them whether or not this fixture asks for none, and the gaps are part
## of what the window has to be. What matters is that the two answers agree
## without a scroll and disagree with one.
func test_the_content_height_reaches_through_a_scroll() -> void:
    var plain := ColumnWindow.new([40, 60, 80])
    var plain_wants := DockerWindow.column_min_height(plain)
    assert_true(plain_wants >= 180, "Three rows of 40, 60 and 80 want at least 180, and want %d" % plain_wants)
    assert_eq(DockerWindow.column_content_height(plain), plain_wants, "A plain column is its own minimum")
    plain.free()

    var scrolled := ColumnWindow.new([40, 60, 80], true)
    assert_true(
        DockerWindow.column_content_height(scrolled) >= 180,
        "The same rows inside a scroll still want 180, and want %d" % DockerWindow.column_content_height(scrolled)
    )
    assert_true(
        DockerWindow.column_min_height(scrolled) < 180,
        "while the column's own minimum is the scroll's, %d" % DockerWindow.column_min_height(scrolled)
    )
    scrolled.free()


## A box lays its children out with a gap between them, and the gaps are part of
## what the window has to be to show every row.
##
## Read as a difference rather than as a total, so the theme's own separation
## cannot make the arithmetic a guess: one more row costs its own height plus one
## gap, and the gap is whatever the container says it is.
func test_the_separation_between_rows_counts() -> void:
    var two := ColumnWindow.new([40, 60])
    var three := ColumnWindow.new([40, 60, 80])
    var gap := two.column.get_theme_constant(&"separation")
    assert_eq(
        DockerWindow.column_content_height(three) - DockerWindow.column_content_height(two),
        80 + gap,
        "A third row of 80 costs 80 and one gap of %d" % gap
    )
    two.free()
    three.free()

    var one := ColumnWindow.new([40])
    assert_eq(DockerWindow.column_content_height(one), 40, "One row has no gap after it")
    one.free()


## A window with no column answers -1, the same as its two neighbours, rather
## than zero: nothing to measure is not a height of nothing.
func test_a_window_with_no_column_answers_minus_one() -> void:
    var bare := Window.new()
    assert_eq(DockerWindow.column_content_height(bare), -1, "No column, no answer")
    assert_false(DockerWindow.column_has_scroll(bare), "and no scroll either")
    bare.free()


## Which dockers get a floor and which keep the one they declared.
func test_only_a_docker_that_cannot_scroll_is_floored_at_its_content() -> void:
    var plain := ColumnWindow.new([100, 100])
    assert_false(DockerWindow.column_has_scroll(plain), "A column of rows does not scroll")
    plain.free()

    var scrolled := ColumnWindow.new([100, 100], true)
    assert_true(DockerWindow.column_has_scroll(scrolled), "and one holding a ScrollContainer does")
    scrolled.free()


## Half the screen, because every shipped layout stacks two dockers down an
## edge, and a docker that takes the whole edge leaves nothing for the one under
## it. The Tool Options docker's 1449 rows are what makes a cap necessary at all.
func test_the_opening_height_is_capped_at_half_the_screen() -> void:
    var window := ColumnWindow.new([100])
    var cap := DockerWindow.content_height_cap(window)
    var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
    assert_true(cap > 0, "The cap is a height, %d" % cap)
    assert_true(float(cap) <= float(usable.size.y) * 0.51, "and no more than half the screen's %d" % usable.size.y)
    assert_true(float(cap) >= float(usable.size.y) * 0.49, "and no less either")
    window.free()
